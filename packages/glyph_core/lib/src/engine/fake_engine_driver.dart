import 'dart:async';

import 'engine_driver.dart';
import 'transcript.dart';

/// Replays recorded transcripts (SPEC 5.2). The search output is looked up by
/// the exact `position ...` + `go ...` command pair; an unknown pair throws
/// [UnknownTranscriptKey] from [send], so a pipeline that deviates from the
/// recorded command sequence fails loudly instead of getting wrong data.
///
/// Everything else behaves like a polite UCI engine: `uci` -> `uciok`,
/// `isready` -> `readyok`, `setoption` / `ucinewgame` / `stop` are accepted
/// silently. Every command received is kept in [sent] for assertions.
///
/// Test hooks: [holdSearch] makes a search stall after a few info lines until
/// `stop` arrives, [crashOnGo] kills the engine when the n-th `go` arrives,
/// [ignoreStop] simulates an engine that never answers `stop`.
class FakeEngineDriver implements EngineDriver {
  FakeEngineDriver(this.transcript) : _permissive = false;

  /// Answers every `go` with a single trivial line (`score cp 0`), whatever the
  /// position. For widget tests that do not care about the analysis content.
  FakeEngineDriver.permissive()
      : transcript = Transcript(),
        _permissive = true;

  final Transcript transcript;
  final bool _permissive;

  /// Every command received, in order.
  final List<String> sent = [];

  /// Number of `go` commands received.
  int goCount = 0;

  /// Lines of output to emit before stalling in [holdSearch] mode.
  int holdLines = 1;

  /// When non-null, the n-th (1-based) `go` stalls after [holdLines] lines
  /// until `stop` is received, then answers with `bestmove`.
  int? holdSearch;

  /// When non-null, the n-th (1-based) `go` makes the engine exit (the output
  /// stream completes without a `bestmove`).
  int? crashOnGo;

  /// Never answer `stop` (the pipeline must time out and discard the engine).
  bool ignoreStop = false;

  bool disposed = false;

  final StreamController<String> _controller = StreamController<String>.broadcast();
  final List<Completer<void>> _goWaiters = [];

  String? _position;
  List<String>? _held;
  bool _closed = false;

  @override
  Stream<String> get lines => _controller.stream;

  /// Completes when the n-th `go` has been received.
  Future<void> waitForGo(int n) {
    if (goCount >= n) return Future.value();
    final c = Completer<void>();
    _goWaiters.add(c);
    return c.future.then((_) => waitForGo(n));
  }

  /// Completes the output stream as if the process died.
  void crash() => _close();

  @override
  void send(String command) {
    if (_closed) throw StateError('FakeEngineDriver: engine is closed (sent "$command")');
    sent.add(command);
    final cmd = command.trim();
    if (cmd == 'uci') {
      _emit(['id name FakeFish', 'id author Glyph tests', 'uciok']);
    } else if (cmd == 'isready') {
      _emit(['readyok']);
    } else if (cmd.startsWith('position')) {
      _position = cmd;
    } else if (cmd.startsWith('go')) {
      _go(cmd);
    } else if (cmd == 'stop') {
      _stop();
    } else if (cmd == 'quit') {
      _close();
    }
  }

  void _go(String go) {
    goCount++;
    final position = _position;
    if (position == null) {
      throw StateError('FakeEngineDriver: "$go" without a preceding position command');
    }
    final n = goCount;
    for (final w in _goWaiters.toList()) {
      w.complete();
    }
    _goWaiters.clear();

    if (crashOnGo == n) {
      scheduleMicrotask(_close);
      return;
    }

    List<String> output;
    if (_permissive) {
      output = const ['info depth 1 seldepth 1 multipv 1 score cp 0 nodes 1 pv e2e4', 'bestmove e2e4'];
    } else {
      final key = Transcript.keyFor(position, go);
      final found = transcript.entries[key];
      if (found == null) throw UnknownTranscriptKey(position, go);
      output = found;
    }

    if (holdSearch == n) {
      final head = output.where((l) => !l.startsWith('bestmove')).take(holdLines).toList();
      _held = [output.lastWhere((l) => l.startsWith('bestmove'), orElse: () => 'bestmove (none)')];
      _emit(head);
      return;
    }
    _emit(output);
  }

  void _stop() {
    if (ignoreStop) return;
    final held = _held;
    if (held != null) {
      _held = null;
      _emit(held);
    }
  }

  void _emit(List<String> out) {
    // One event-loop turn per batch, like a real pipe.
    Future<void>(() {
      if (_closed) return;
      for (final l in out) {
        _controller.add(l);
      }
    });
  }

  void _close() {
    if (_closed) return;
    _closed = true;
    _controller.close();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    _close();
  }
}

/// A `position ...` + `go ...` pair with no recording.
class UnknownTranscriptKey extends Error {
  UnknownTranscriptKey(this.position, this.go);

  final String position;
  final String go;

  @override
  String toString() => 'UnknownTranscriptKey: no recorded output for\n  $position\n  $go';
}
