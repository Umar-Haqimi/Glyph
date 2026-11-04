import 'dart:async';
import 'dart:collection';

import 'package:glyph_core/glyph_core.dart';

/// Owns the single engine of the app and runs analysis jobs one at a time
/// (SPEC trap 5, 5.3).
///
/// * **Serial queue.** [enqueue] adds a job; the engine never searches two
///   games at once and `multistockfish` never sees a second `create()`.
/// * **Cancel** a running job with [cancel] (stop, await bestmove, 2 s rule in
///   the pipeline). Cancelled / failed / paused jobs are resumed by enqueueing
///   the same request again: the pipeline continues at `completed_plies`.
/// * **Lifecycle.** [onAppPaused] (AppLifecycleState.paused) stops the running
///   job, marks it `paused`, disposes the engine and stops the queue;
///   [onAppResumed] recreates the engine and continues with the paused job,
///   then the rest of the queue.
/// * **Crash recovery.** A crash or an unavailable engine ends the job in
///   `failed`; the engine is discarded, so enqueueing the request again
///   (Retry) creates a new engine and resumes from the last persisted ply.
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
  AnalysisRequest? _current;
  AnalysisRequest? _pausedRequest;
  bool _background = false;
  bool _pumping = false;
  bool _disposed = false;

  /// Job state changes (broadcast).
  Stream<AnalysisJobState> get states => _pipeline.states;

  AnalysisJobState get state => _pipeline.state;

  /// Engines created so far (a retry after a crash makes this grow).
  int get enginesCreated => _pipeline.enginesCreated;

  /// Game ids waiting behind the running job.
  List<int> get queuedGameIds => [for (final r in _queue) r.gameId];

  bool isQueued(int gameId) => _queue.any((r) => r.gameId == gameId);

  /// Game ids that are running, paused for the background, or queued.
  bool isActive(int gameId) =>
      (_current?.gameId == gameId && _pipeline.isRunning) || _pausedRequest?.gameId == gameId || isQueued(gameId);

  /// Adds [request] to the queue (replacing a queued request for the same
  /// game). Ignored if that game is already running.
  void enqueue(AnalysisRequest request) {
    if (_disposed) return;
    if (_current?.gameId == request.gameId && _pipeline.isRunning) return;
    _queue.removeWhere((r) => r.gameId == request.gameId);
    if (_pausedRequest?.gameId == request.gameId) _pausedRequest = null;
    _queue.add(request);
    unawaited(_pump());
  }

  /// Cancels the job for [gameId]: stops it if it is running, drops it from
  /// the queue otherwise.
  Future<void> cancel(int gameId) async {
    _queue.removeWhere((r) => r.gameId == gameId);
    if (_pausedRequest?.gameId == gameId) _pausedRequest = null;
    if (_current?.gameId == gameId) await _pipeline.cancel();
  }

  /// `AppLifecycleState.paused`: stop searching and release the engine.
  Future<void> onAppPaused() async {
    _background = true;
    await _pipeline.pause();
    await _pipeline.releaseEngine();
  }

  /// Back in the foreground: continue the paused job, then the queue.
  Future<void> onAppResumed() async {
    _background = false;
    final paused = _pausedRequest;
    if (paused != null) {
      _pausedRequest = null;
      _queue.addFirst(paused);
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
    await _pipeline.dispose();
  }

  Future<void> _pump() async {
    if (_pumping || _disposed) return;
    _pumping = true;
    try {
      while (!_disposed && !_background && _queue.isNotEmpty) {
        final request = _queue.removeFirst();
        _current = request;
        final AnalysisJobState result;
        try {
          result = await _pipeline.analyze(request);
        } finally {
          _current = null;
        }
        if (result is AnalysisPaused) {
          _pausedRequest = request;
          break;
        }
      }
    } finally {
      _pumping = false;
    }
  }
}
