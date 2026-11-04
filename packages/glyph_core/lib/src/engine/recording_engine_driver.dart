import 'dart:async';

import 'engine_driver.dart';
import 'transcript.dart';

/// Wraps a real driver and records every `position` + `go` exchange into a
/// [Transcript] (used by `tool/record_transcripts.dart`). Because the recorder
/// runs the real `AnalysisPipeline`, the recorded command strings are exactly
/// the ones the pipeline sends when it replays them.
class RecordingEngineDriver implements EngineDriver {
  RecordingEngineDriver(this._inner, this.transcript) {
    _sub = _inner.lines.listen(_onLine, onError: _controller.addError, onDone: _controller.close);
  }

  final EngineDriver _inner;
  final Transcript transcript;
  late final StreamSubscription<String> _sub;
  final StreamController<String> _controller = StreamController<String>.broadcast();

  String? _position;
  String? _go;
  List<String>? _output;

  @override
  Stream<String> get lines => _controller.stream;

  void _onLine(String line) {
    final out = _output;
    if (out != null) {
      out.add(line);
      if (line.startsWith('bestmove')) {
        transcript.add(_position!, _go!, out);
        _output = null;
      }
    }
    _controller.add(line);
  }

  @override
  void send(String command) {
    final cmd = command.trim();
    if (cmd.startsWith('position')) {
      _position = cmd;
    } else if (cmd.startsWith('go')) {
      _go = cmd;
      _output = [];
    }
    _inner.send(command);
  }

  @override
  Future<void> dispose() async {
    await _sub.cancel();
    await _inner.dispose();
    if (!_controller.isClosed) await _controller.close();
  }
}
