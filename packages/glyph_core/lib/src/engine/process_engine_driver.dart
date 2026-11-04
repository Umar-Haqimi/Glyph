import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'engine_driver.dart';

/// Runs a desktop UCI engine binary (host only; `package:glyph_core/glyph_core_host.dart`).
/// Used by `tool/record_transcripts.dart` and env-gated tests with
/// `$STOCKFISH_PATH`.
class ProcessEngineDriver implements EngineDriver {
  ProcessEngineDriver._(this._process) {
    _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_controller.add, onError: _controller.addError, onDone: _controller.close);
    // Drain stderr so the child never blocks on a full pipe.
    _process.stderr.drain<void>();
  }

  /// Starts [executable]. Throws [ProcessException] if it cannot be started.
  static Future<ProcessEngineDriver> start(String executable) async =>
      ProcessEngineDriver._(await Process.start(executable, const []));

  /// Starts `$STOCKFISH_PATH`.
  static Future<ProcessEngineDriver> fromEnvironment() {
    final path = Platform.environment['STOCKFISH_PATH'];
    if (path == null || path.isEmpty) {
      throw StateError('STOCKFISH_PATH is not set');
    }
    return start(path);
  }

  final Process _process;
  final StreamController<String> _controller = StreamController<String>.broadcast();
  bool _disposed = false;

  @override
  Stream<String> get lines => _controller.stream;

  @override
  void send(String command) {
    if (_disposed) throw StateError('ProcessEngineDriver is disposed');
    _process.stdin.writeln(command);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      _process.stdin.writeln('quit');
      await _process.stdin.flush();
      await _process.stdin.close();
    } catch (_) {
      // Pipe already closed: the process is gone.
    }
    await _process.exitCode.timeout(const Duration(seconds: 2), onTimeout: () {
      _process.kill(ProcessSignal.sigkill);
      return -1;
    });
    if (!_controller.isClosed) await _controller.close();
  }
}
