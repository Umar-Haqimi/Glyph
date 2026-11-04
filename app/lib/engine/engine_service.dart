import 'dart:async';
import 'dart:collection';

import 'package:glyph_core/glyph_core.dart';

/// Owns the single engine of the app and runs analysis jobs one at a time
/// (SPEC trap 5, 5.3).
///
/// * **Serial queue.** [enqueue] adds a job; the engine never searches two
///   games at once and `multistockfish` never sees a second `create()`.
///   Enqueueing the game that is already running is ignored when it asks for
///   the same analysis; a different depth / MultiPV or a restart cancels the
///   running job and runs the new request next.
/// * **Cancel** a running job with [cancel] (stop, await bestmove, 2 s rule in
///   the pipeline). Cancelled / failed / paused jobs are resumed by enqueueing
///   the same request again: the pipeline continues at `completed_plies`.
///   A cancel always wins over a pause that races it: the job ends in
///   `cancelled` and does not come back on resume.
/// * **Lifecycle.** [onAppPaused] (AppLifecycleState.paused) stops the running
///   job, marks it `paused`, disposes the engine and stops the queue;
///   [onAppResumed] continues with the paused job (always without `restart`,
///   so the stored progress is kept), then the rest of the queue. Pauses are
///   serialised, and the queue only starts a job once the previous engine is
///   fully disposed, so a resume that arrives while the pause is still
///   stopping still resumes, and never creates a second engine.
/// * **Crash recovery.** A crash or an unavailable engine ends the job in
///   `failed`; the engine is discarded, so enqueueing the request again
///   (Retry) creates a new engine and resumes from the last persisted ply.
///   Rows left `running` by a process kill are set to `paused` at startup
///   (`AnalysisRepository.pauseInterrupted`, called from `main`).
/// * **Hot reload (debug).** [releaseForHotReload] behaves like a pause and
///   comes back by itself a moment later, so no live engine isolate survives
///   a reload.
class EngineService {
  EngineService({
    required EngineDriverFactory driverFactory,
    required AnalysisStore store,
    Clock clock = const SystemClock(),
    PipelineTimeouts timeouts = const PipelineTimeouts(),
    this.hotReloadResumeDelay = const Duration(milliseconds: 300),
  }) : _pipeline = AnalysisPipeline(
          createDriver: driverFactory,
          store: store,
          clock: clock,
          timeouts: timeouts,
        );

  final AnalysisPipeline _pipeline;
  final Duration hotReloadResumeDelay;

  final Queue<AnalysisRequest> _queue = Queue();
  final StreamController<List<int>> _queueChanges = StreamController<List<int>>.broadcast();
  AnalysisRequest? _current;

  /// The running job was cancelled or superseded: whatever it ends in, it
  /// must not be stored for resume.
  bool _dropCurrent = false;
  AnalysisRequest? _pausedRequest;
  bool _background = false;
  bool _pumping = false;
  bool _disposed = false;

  /// The pause (stop + engine disposal) in progress, if any.
  Future<void>? _lifecycle;

  /// Job state changes (broadcast).
  Stream<AnalysisJobState> get states => _pipeline.states;

  AnalysisJobState get state => _pipeline.state;

  /// The queued game ids after every change of the queue (broadcast).
  Stream<List<int>> get queueChanges => _queueChanges.stream;

  /// Engines created so far (a retry after a crash makes this grow).
  int get enginesCreated => _pipeline.enginesCreated;

  /// Game ids waiting behind the running job.
  List<int> get queuedGameIds => [for (final r in _queue) r.gameId];

  bool isQueued(int gameId) => _queue.any((r) => r.gameId == gameId);

  /// Game ids that are running, paused for the background, or queued.
  bool isActive(int gameId) =>
      (_current?.gameId == gameId && _pipeline.isRunning) || _pausedRequest?.gameId == gameId || isQueued(gameId);

  void _queueChanged() {
    if (!_queueChanges.isClosed) _queueChanges.add(queuedGameIds);
  }

  /// Adds [request] to the queue (replacing a queued request for the same
  /// game). If that game is running: ignored when the request asks for the
  /// same analysis, otherwise the running job is cancelled and [request]
  /// runs next.
  void enqueue(AnalysisRequest request) {
    if (_disposed) return;
    final current = _current;
    if (current != null && current.gameId == request.gameId && _pipeline.isRunning && !_dropCurrent) {
      final same = !request.restart && request.depth == current.depth && request.multipv == current.multipv;
      if (same) return;
      _dropCurrent = true;
      _queue.removeWhere((r) => r.gameId == request.gameId);
      _queue.addFirst(request);
      _queueChanged();
      unawaited(_pipeline.cancel());
      return;
    }
    _queue.removeWhere((r) => r.gameId == request.gameId);
    if (_pausedRequest?.gameId == request.gameId) _pausedRequest = null;
    _queue.add(request);
    _queueChanged();
    unawaited(_pump());
  }

  /// Cancels the job for [gameId]: stops it if it is running, drops it from
  /// the queue (or from the paused slot) otherwise.
  Future<void> cancel(int gameId) async {
    _queue.removeWhere((r) => r.gameId == gameId);
    if (_pausedRequest?.gameId == gameId) _pausedRequest = null;
    _queueChanged();
    if (_current?.gameId == gameId) {
      _dropCurrent = true;
      await _pipeline.cancel();
    }
  }

  /// Cancels every job: the running one, the queued ones and a paused one
  /// (Settings > Delete all data, before the games go away).
  Future<void> cancelAll() async {
    _queue.clear();
    _pausedRequest = null;
    _queueChanged();
    if (_current != null) {
      _dropCurrent = true;
      await _pipeline.cancel();
    }
  }

  /// `AppLifecycleState.paused`: stop searching and release the engine.
  Future<void> onAppPaused() {
    _background = true;
    return _serialiseLifecycle(() async {
      await _pipeline.pause();
      await _pipeline.releaseEngine();
    });
  }

  /// Back in the foreground: continue the paused job, then the queue. If the
  /// pause is still stopping, the queue picks the job up once it has.
  Future<void> onAppResumed() async {
    _background = false;
    final paused = _pausedRequest;
    if (paused != null) {
      _pausedRequest = null;
      _queue.addFirst(paused);
      _queueChanged();
    }
    await _pump();
  }

  /// Debug hot reload: release the engine now, come back shortly after.
  Future<void> releaseForHotReload() async {
    await onAppPaused();
    Timer(hotReloadResumeDelay, () {
      if (!_disposed) unawaited(onAppResumed());
    });
  }

  Future<void> dispose() async {
    _disposed = true;
    _queue.clear();
    _pausedRequest = null;
    final lifecycle = _lifecycle;
    if (lifecycle != null) await lifecycle.catchError((Object _) {});
    await _pipeline.dispose();
    await _queueChanges.close();
  }

  Future<void> _serialiseLifecycle(Future<void> Function() op) {
    final previous = _lifecycle;
    final f = previous == null ? op() : previous.then((_) => op(), onError: (Object _) => op());
    _lifecycle = f;
    unawaited(f.catchError((Object _) {}).whenComplete(() {
      if (identical(_lifecycle, f)) _lifecycle = null;
    }));
    return f;
  }

  Future<void> _pump() async {
    if (_pumping || _disposed) return;
    _pumping = true;
    try {
      while (!_disposed && _queue.isNotEmpty) {
        // Never start a job while a pause is still stopping / disposing the
        // engine (one engine per flavor).
        final lifecycle = _lifecycle;
        if (lifecycle != null) {
          await lifecycle.catchError((Object _) {});
          if (identical(_lifecycle, lifecycle)) _lifecycle = null;
          continue;
        }
        if (_background) break;
        final request = _queue.removeFirst();
        _queueChanged();
        _current = request;
        _dropCurrent = false;
        final AnalysisJobState result;
        try {
          result = await _pipeline.analyze(request);
        } finally {
          _current = null;
        }
        if (result is AnalysisPaused && !_dropCurrent) {
          // Resume keeps the progress: never restart again.
          final resume = request.copyWith(restart: false);
          if (_background) {
            _pausedRequest = resume;
          } else {
            // The app came back while the pause was still stopping.
            _queue.addFirst(resume);
            _queueChanged();
          }
        }
      }
    } finally {
      _pumping = false;
    }
  }
}
