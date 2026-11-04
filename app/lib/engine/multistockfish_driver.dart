import 'dart:async';

import 'package:glyph_core/glyph_core.dart';
import 'package:multistockfish/multistockfish.dart';

/// [EngineDriver] over `multistockfish` (Stockfish 19, embedded light net).
///
/// Only one `light` engine can exist at a time (a second `Stockfish.create`
/// throws `StateError`); `EngineService` guarantees there is just one driver.
class MultistockfishDriver implements EngineDriver {
  MultistockfishDriver._(this._engine, this._controller) {
    _engine.state.addListener(_onState);
  }

  /// Starts the engine and completes once it is ready for commands. Throws
  /// `StateError` if a light engine is already live, `TimeoutException` if it
  /// does not start.
  static Future<MultistockfishDriver> create() async {
    final controller = StreamController<String>.broadcast();
    final Stockfish engine;
    try {
      engine = await Stockfish.create(
        flavor: StockfishFlavor.light,
        // onStdout is attached before the engine spawns and gets every line.
        onStdout: (line) {
          if (!controller.isClosed) controller.add(line);
        },
      );
    } catch (_) {
      await controller.close();
      rethrow;
    }
    return MultistockfishDriver._(engine, controller);
  }

  final Stockfish _engine;
  final StreamController<String> _controller;
  bool _disposed = false;

  @override
  Stream<String> get lines => _controller.stream;

  void _onState() {
    // The engine died on its own: end the line stream so the pipeline notices.
    final s = _engine.state.value;
    if (!_disposed && (s == StockfishState.error || s == StockfishState.disposed)) {
      _close();
    }
  }

  void _close() {
    _engine.state.removeListener(_onState);
    if (!_controller.isClosed) unawaited(_controller.close());
  }

  @override
  void send(String command) {
    // Throws StateError when the engine is no longer `ready`; the pipeline
    // turns that into EngineClosed.
    _engine.stdin = command;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _engine.state.removeListener(_onState);
    try {
      await _engine.dispose();
    } finally {
      if (!_controller.isClosed) await _controller.close();
    }
  }
}
