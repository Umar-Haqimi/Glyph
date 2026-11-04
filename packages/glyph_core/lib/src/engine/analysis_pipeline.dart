// ignore_for_file: prefer_initializing_formals
import 'dart:async';

import 'package:dartchess/dartchess.dart' show Position, kInitialFEN;

import '../util/clock.dart';
import 'analysis_job.dart';
import 'engine_driver.dart';
import 'terminal.dart';
import 'uci_parser.dart';

/// Time limits of the pipeline. Tests shorten them.
class PipelineTimeouts {
  const PipelineTimeouts({
    this.handshake = const Duration(seconds: 10),
    this.stop = const Duration(seconds: 2),
    this.searchIdle = const Duration(seconds: 90),
    this.engineStart = const Duration(seconds: 30),
  });

  /// Maximum wait for `uciok` / `readyok`.
  final Duration handshake;

  /// After `stop`, the engine must answer `bestmove` within this time
  /// (SPEC trap 5), else it is disposed and recreated.
  final Duration stop;

  /// A search that produces no output for this long is considered hung.
  final Duration searchIdle;

  /// Maximum wait for the [EngineDriverFactory] to hand over an engine. Past
  /// it the job fails with `engineUnavailable` (the engine, if it still
  /// arrives, is disposed at once).
  final Duration engineStart;
}

/// The `position ...` command for the position after [moveCount] moves
/// (SPEC trap 9: always with the full history). The standard start uses
/// `startpos`, everything else `fen <startFen>`.
String positionCommand(String startFen, List<String> moves, int moveCount) {
  final base = startFen == kInitialFEN ? 'position startpos' : 'position fen $startFen';
  return moveCount == 0 ? base : '$base moves ${moves.take(moveCount).join(' ')}';
}

/// Analyses a game position by position, with Stockfish behind an
/// [EngineDriver] (SPEC 2.1, 5.3).
///
/// Per job: session setup (`uci`/`uciok`, `setoption` Threads, Hash, MultiPV,
/// `UCI_Chess960 true`, `isready`/`readyok`), `ucinewgame` + `isready`, then
/// for each position `position <start> moves <history>` and `go depth D`.
/// Terminal positions (checkmate, stalemate, insufficient material) are
/// computed with [detectTerminal] and never reach the engine. Each completed
/// position is persisted through the [AnalysisStore] **before** the next `go`,
/// so a job can resume from `completed_plies` after a cancel, a pause, a crash
/// or a process kill.
///
/// One pipeline owns at most one engine and runs one job at a time; queueing
/// and app-lifecycle policy belong to the caller (`EngineService`).
class AnalysisPipeline {
  AnalysisPipeline({
    required EngineDriverFactory createDriver,
    required AnalysisStore store,
    Clock clock = const SystemClock(),
    this.timeouts = const PipelineTimeouts(),
  })  : _createDriver = createDriver,
        _store = store,
        _clock = clock;

  final EngineDriverFactory _createDriver;
  final AnalysisStore _store;
  final Clock _clock;
  final PipelineTimeouts timeouts;

  final StreamController<AnalysisJobState> _states = StreamController<AnalysisJobState>.broadcast();
  AnalysisJobState _state = const AnalysisIdle();

  _Session? _session;
  String? _configured;

  bool _running = false;
  _StopReason? _stopReason;
  Completer<void>? _stopSignal;
  Future<void>? _job;

  /// Disposal of a discarded engine that may still be in progress. A new
  /// engine is only created after it completed (one engine per flavor, SPEC
  /// trap 5).
  Future<void>? _discarding;

  /// An engine creation that was given up on (timeout, cancel, pause); it
  /// disposes the engine if one still arrives.
  Future<void>? _abandoned;

  /// How many engines were created so far (tests: "retry recreates").
  int enginesCreated = 0;

  /// Progress and state changes. Broadcast.
  Stream<AnalysisJobState> get states => _states.stream;

  AnalysisJobState get state => _state;

  bool get isRunning => _running;

  void _emit(AnalysisJobState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  /// Runs [request] to a final state and returns it: completed, cancelled,
  /// paused or failed. Resumes from the stored progress when the stored depth
  /// and MultiPV match (unless [AnalysisRequest.restart]).
  Future<AnalysisJobState> analyze(AnalysisRequest request) {
    if (_running) throw StateError('AnalysisPipeline is already running a job');
    _running = true;
    _stopReason = null;
    _stopSignal = Completer<void>();
    final completer = Completer<AnalysisJobState>();
    _job = completer.future.then<void>((_) {}, onError: (Object _) {});
    _run(request).then(completer.complete, onError: completer.completeError);
    return completer.future;
  }

  /// Cancels the running job: `stop`, then wait for `bestmove` (2 s timeout
  /// -> the engine is disposed and recreated for the next job). The partial
  /// search is discarded. Completes when the job has ended in `cancelled`.
  Future<void> cancel() => _stop(_StopReason.cancel);

  /// Like [cancel] but ends in `paused` and also releases the engine (app
  /// went to the background).
  Future<void> pause() => _stop(_StopReason.pause);

  Future<void> _stop(_StopReason reason) async {
    if (_running) {
      // A cancel wins over a pause, in either order: a job the user cancelled
      // must not come back when the app returns to the foreground.
      if (_stopReason != _StopReason.cancel) _stopReason = reason;
      final signal = _stopSignal;
      if (signal != null && !signal.isCompleted) signal.complete();
      _interruptSearch();
      await _job;
    }
    if (reason == _StopReason.pause) await _discardSession();
  }

  /// Releases the engine (e.g. before a hot reload). Only valid while idle.
  Future<void> releaseEngine() => _discardSession();

  Future<void> dispose() async {
    if (_running) await cancel();
    await _discardSession();
    await _states.close();
  }

  // ---------------------------------------------------------------------------

  Future<AnalysisJobState> _run(AnalysisRequest req) async {
    final total = req.totalPositions;
    var completed = 0;
    AnalysisJobState finish(AnalysisJobState s) {
      _emit(s);
      return s;
    }

    try {
      _emit(AnalysisStarting(req.gameId, total: total));

      // Replay first: a malformed request must not touch the store or engine.
      final List<Position> positions;
      try {
        positions = replayPositions(req.startFen, req.moves);
      } on ArgumentError catch (e) {
        return finish(AnalysisFailed(req.gameId, AnalysisFailureKind.invalidGame, '${e.message}', 0, total));
      }

      final stored = await _store.load(req.gameId);
      final resumable = !req.restart &&
          stored != null &&
          stored.depth == req.depth &&
          stored.multipv == req.multipv &&
          stored.completedPositions > 0;
      completed = resumable ? stored.completedPositions.clamp(0, total) : 0;
      await _store.begin(
        req.gameId,
        engine: req.engineName,
        depth: req.depth,
        multipv: req.multipv,
        completedPositions: completed,
        clear: !resumable,
        nowMs: _clock.nowMs(),
      );

      if (completed >= total) {
        await _store.end(req.gameId, AnalysisStatus.completed, nowMs: _clock.nowMs());
        return finish(AnalysisCompleted(req.gameId, total));
      }
      _emit(AnalysisRunning(req.gameId, completed, total));

      // Games that end in terminal positions only (e.g. bare kings) never
      // touch the engine.
      final needsEngine = positions.skip(completed).any((p) => detectTerminal(p) == null);
      _Session? session;
      if (needsEngine) {
        try {
          session = await _ensureSession(req);
        } on _Interrupted {
          return await _stopped(req, completed, total);
        } catch (e) {
          await _discardSession();
          if (_stopReason != null) return await _stopped(req, completed, total);
          return await _fail(req, AnalysisFailureKind.engineUnavailable, e, completed, total);
        }
        if (_stopReason != null) return await _stopped(req, completed, total);
      }

      try {
        if (session != null) {
          session.send('ucinewgame');
          await session.expect('isready', (l) => l == 'readyok', timeouts.handshake, 'readyok');
          if (_stopReason != null) return await _stopped(req, completed, total);
        }

        for (var ply = completed; ply < total; ply++) {
          final position = positions[ply];
          final terminal = detectTerminal(position);
          if (terminal != null) {
            await _store.savePosition(
              req.gameId,
              PositionAnalysis(ply: ply, terminal: terminal),
              nowMs: _clock.nowMs(),
            );
          } else {
            final engine = session!;
            engine.send(positionCommand(req.startFen, req.moves, ply));
            final output = await engine.search(
              'go depth ${req.depth}',
              idle: timeouts.searchIdle,
            );
            if (_stopReason != null) return await _stopped(req, completed, total);

            final parser = UciParser(sideToMove: position.turn);
            UciSearchResult? result;
            for (final line in output) {
              result = parser.feed(line) ?? result;
            }
            if (result == null || result.lines.isEmpty) {
              throw EngineProtocolException('No analysis returned for ply $ply');
            }
            await _store.savePosition(
              req.gameId,
              PositionAnalysis(ply: ply, lines: result.lines),
              nowMs: _clock.nowMs(),
            );
          }
          completed = ply + 1;
          _emit(AnalysisRunning(req.gameId, completed, total));
          if (_stopReason != null) return await _stopped(req, completed, total);
        }
      } on _StopTimeout {
        // The engine ignored `stop`: throw it away; the next job recreates it.
        await _discardSession();
        return await _stopped(req, completed, total);
      } on GameMissingException {
        return finish(AnalysisCancelled(req.gameId, completed, total));
      } on Object catch (e) {
        await _discardSession();
        // A cancel or pause that raced the failure wins (the engine closed
        // because of the stop, an idle timeout fired just before it, ...).
        if (_stopReason != null) return await _stopped(req, completed, total);
        return await _fail(req, AnalysisFailureKind.engineCrashed, e, completed, total);
      }

      await _store.end(req.gameId, AnalysisStatus.completed, nowMs: _clock.nowMs());
      return finish(AnalysisCompleted(req.gameId, total));
    } on GameMissingException {
      // The game was deleted: nothing to record, nothing to resume.
      return finish(AnalysisCancelled(req.gameId, completed, total));
    } catch (e) {
      // Store failures and other surprises: a failed job, never a thrown error.
      await _discardSession();
      return await _fail(req, AnalysisFailureKind.engineCrashed, e, completed, total);
    } finally {
      _running = false;
      _stopReason = null;
      _stopSignal = null;
    }
  }

  Future<AnalysisJobState> _stopped(AnalysisRequest req, int completed, int total) async {
    final paused = _stopReason == _StopReason.pause;
    // A paused job releases its engine before it reports, so whatever runs
    // next (a resume) never meets the old engine still alive.
    if (paused) await _discardSession();
    await _store.end(
      req.gameId,
      paused ? AnalysisStatus.paused : AnalysisStatus.cancelled,
      nowMs: _clock.nowMs(),
    );
    final s = paused
        ? AnalysisPaused(req.gameId, completed, total)
        : AnalysisCancelled(req.gameId, completed, total);
    _emit(s);
    return s;
  }

  Future<AnalysisJobState> _fail(
    AnalysisRequest req,
    AnalysisFailureKind kind,
    Object error,
    int completed,
    int total,
  ) async {
    try {
      await _store.end(req.gameId, AnalysisStatus.failed, nowMs: _clock.nowMs());
    } catch (_) {
      // Failing to record a failure must not hide the failure itself.
    }
    final s = AnalysisFailed(req.gameId, kind, '$error', completed, total);
    _emit(s);
    return s;
  }

  // --- engine session --------------------------------------------------------

  Future<_Session> _ensureSession(AnalysisRequest req) async {
    final options = '${req.threads}/${req.hashMb}/${req.multipv}';
    var session = _session;
    if (session != null && session.closed) {
      await _discardSession();
      session = null;
    }
    if (session == null) {
      final driver = await _startEngine();
      enginesCreated++;
      session = _Session(driver);
      _session = session;
      _configured = null;
      await session.expect('uci', (l) => l == 'uciok', timeouts.handshake, 'uciok');
    }
    if (_configured != options) {
      // Threads before Hash: changing Threads reallocates the table at the
      // current Hash size (docs/DECISIONS.md, multistockfish).
      session.send('setoption name Threads value ${req.threads}');
      session.send('setoption name Hash value ${req.hashMb}');
      session.send('setoption name MultiPV value ${req.multipv}');
      // Always on: dartchess castling is king-takes-rook, which is what
      // Stockfish accepts only in Chess960 mode (docs/DECISIONS.md).
      session.send('setoption name UCI_Chess960 value true');
      await session.expect('isready', (l) => l == 'readyok', timeouts.handshake, 'readyok');
      _configured = options;
    }
    return session;
  }

  /// Creates an engine, bounded by [PipelineTimeouts.engineStart] and
  /// interruptible by cancel / pause (throws [_Interrupted]). Waits first for
  /// any engine that is still being disposed.
  Future<EngineDriver> _startEngine() async {
    final discarding = _discarding;
    if (discarding != null) await discarding;
    final abandoned = _abandoned;
    if (abandoned != null) {
      // Bounded: a factory that never completes must not block every later job.
      await abandoned.timeout(timeouts.engineStart, onTimeout: () {});
    }
    if (_stopReason != null) throw const _Interrupted();

    final pending = _createDriver();
    final stop = _stopSignal?.future ?? Completer<void>().future;
    final EngineDriver? driver;
    try {
      driver = await Future.any<EngineDriver?>([pending, stop.then((_) => null)]).timeout(timeouts.engineStart);
    } on TimeoutException {
      _abandon(pending);
      throw EngineTimeoutException('the engine did not start within ${timeouts.engineStart.inSeconds} s');
    }
    if (driver == null) {
      _abandon(pending);
      throw const _Interrupted();
    }
    return driver;
  }

  void _abandon(Future<EngineDriver> pending) {
    final f = pending.then((d) => d.dispose(), onError: (Object _) {}).catchError((Object _) {});
    _abandoned = f;
    unawaited(f.whenComplete(() {
      if (identical(_abandoned, f)) _abandoned = null;
    }));
  }

  /// Drops the current engine. The returned future (also kept in
  /// [_discarding]) completes when the engine has been disposed.
  Future<void> _discardSession() {
    final s = _session;
    _session = null;
    _configured = null;
    if (s == null) return _discarding ?? Future<void>.value();
    final previous = _discarding;
    final f = Future.wait([?previous, s.dispose()]).then((_) {});
    _discarding = f;
    unawaited(f.whenComplete(() {
      if (identical(_discarding, f)) _discarding = null;
    }));
    return f;
  }

  /// `stop` the in-flight search, if any; arm the stop timeout.
  void _interruptSearch() {
    final s = _session;
    if (s != null && s.searching) s.stopSearch(timeouts.stop);
  }
}

enum _StopReason { cancel, pause }

class _StopTimeout implements Exception {
  const _StopTimeout();
}

/// Engine creation was interrupted by a cancel or pause.
class _Interrupted implements Exception {
  const _Interrupted();
}

/// One live engine and the line plumbing around it. One request is in flight
/// at a time (a search can additionally be interrupted with `stop`).
class _Session {
  _Session(this.driver) {
    _sub = driver.lines.listen(_onLine, onError: _onError, onDone: _onDone);
  }

  final EngineDriver driver;
  late final StreamSubscription<String> _sub;
  bool closed = false;
  bool searching = false;

  Completer<List<String>>? _pending;
  bool Function(String)? _isEnd;
  List<String> _buffer = [];
  Timer? _timer;
  Duration? _idle;
  String _what = '';

  void send(String command) {
    if (closed) throw const EngineClosedException();
    try {
      driver.send(command);
    } on StateError catch (e) {
      closed = true;
      throw EngineClosedException(e.message);
    }
  }

  /// Sends [command] and collects lines up to and including the first one for
  /// which [isEnd] holds. Fails on timeout, `CRITICAL ERROR` or a closed engine.
  Future<List<String>> expect(String command, bool Function(String) isEnd, Duration timeout, String what) {
    _begin(isEnd, what, timeout);
    _sendOrAbort(command);
    return _pending!.future.whenComplete(_clearTimer);
  }

  /// Sends `go ...` (the `position` command was sent before) and collects the
  /// output up to `bestmove`.
  Future<List<String>> search(String goCommand, {required Duration idle}) {
    _begin((l) => l.startsWith('bestmove'), 'bestmove', idle);
    searching = true;
    _sendOrAbort(goCommand);
    return _pending!.future.whenComplete(() {
      searching = false;
      _clearTimer();
    });
  }

  void _sendOrAbort(String command) {
    try {
      send(command);
    } catch (_) {
      _pending = null;
      searching = false;
      _clearTimer();
      rethrow;
    }
  }

  /// Sends `stop` and replaces the idle watchdog by the stop timeout.
  void stopSearch(Duration timeout) {
    if (closed || _pending == null) return;
    try {
      send('stop');
    } on EngineClosedException {
      return; // _onDone/_onError already failed the search
    }
    _idle = null;
    _timer?.cancel();
    _timer = Timer(timeout, () => _fail(const _StopTimeout()));
  }

  void _begin(bool Function(String) isEnd, String what, Duration timeout) {
    if (_pending != null) throw StateError('engine request already in flight');
    _pending = Completer<List<String>>();
    _isEnd = isEnd;
    _buffer = [];
    _what = what;
    _idle = timeout;
    _timer?.cancel();
    _timer = Timer(timeout, () => _fail(EngineTimeoutException('timed out waiting for $what')));
  }

  void _clearTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _onLine(String line) {
    final p = _pending;
    if (p == null) return;
    if (line.contains('CRITICAL ERROR')) {
      _fail(EngineProtocolException(line));
      return;
    }
    _buffer.add(line);
    final idle = _idle;
    if (idle != null) {
      _timer?.cancel();
      _timer = Timer(idle, () => _fail(EngineTimeoutException('timed out waiting for $_what')));
    }
    if (_isEnd!(line)) {
      _pending = null;
      p.complete(_buffer);
    }
  }

  void _onError(Object error) => _fail(error);

  void _onDone() {
    closed = true;
    _fail(const EngineClosedException());
  }

  void _fail(Object error) {
    final p = _pending;
    _pending = null;
    if (p != null && !p.isCompleted) p.completeError(error);
  }

  Future<void> dispose() async {
    closed = true;
    _clearTimer();
    final p = _pending;
    _pending = null;
    if (p != null && !p.isCompleted) {
      // Swallow: nobody awaits a discarded request.
      unawaited(p.future.catchError((Object _) => <String>[]));
      p.completeError(const EngineClosedException('engine disposed'));
    }
    // Not awaited: cancelling a broadcast subscription takes effect at once,
    // and awaiting its future never completes under fake_async in widget tests.
    unawaited(_sub.cancel());
    try {
      await driver.dispose();
    } catch (_) {
      // A dead engine may fail to quit cleanly; it is gone either way.
    }
  }
}
