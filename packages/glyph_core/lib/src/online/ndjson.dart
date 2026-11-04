import 'dart:convert';
import 'dart:typed_data';

/// Splits a byte stream into NDJSON lines without ever holding more than
/// [maxLineBytes] of one line. A longer line is dropped as it arrives (its
/// bytes are skipped up to the next newline) and counted in [oversized].
///
/// Splitting is done on bytes (`\n`, with a trailing `\r` removed) and only
/// complete lines are decoded, so a multi-byte UTF-8 character cut by a chunk
/// boundary is never damaged. Blank lines (lichess keep-alives) are dropped.
class NdjsonLineSplitter {
  NdjsonLineSplitter({required this.maxLineBytes});

  final int maxLineBytes;
  final _line = BytesBuilder(copy: false);
  var _discarding = false;

  /// Lines dropped for exceeding [maxLineBytes].
  int oversized = 0;

  /// Feeds a chunk; returns the lines it completed.
  List<String> add(List<int> chunk) {
    final out = <String>[];
    var start = 0;
    for (var i = 0; i < chunk.length; i++) {
      if (chunk[i] != 0x0A) continue;
      _append(chunk, start, i);
      _finishLine(out);
      start = i + 1;
    }
    _append(chunk, start, chunk.length);
    return out;
  }

  /// The last line when the stream ended without a newline.
  List<String> close() {
    final out = <String>[];
    _finishLine(out);
    return out;
  }

  void _append(List<int> chunk, int start, int end) {
    if (end <= start || _discarding) return;
    if (_line.length + (end - start) > maxLineBytes + 1) {
      // +1: a trailing \r does not count against the cap.
      _discarding = true;
      oversized++;
      _line.clear();
      return;
    }
    _line.add(chunk is Uint8List ? Uint8List.sublistView(chunk, start, end) : Uint8List.fromList(chunk.sublist(start, end)));
  }

  void _finishLine(List<String> out) {
    if (_discarding) {
      _discarding = false;
      return;
    }
    var bytes = _line.takeBytes();
    if (bytes.isNotEmpty && bytes.last == 0x0D) bytes = Uint8List.sublistView(bytes, 0, bytes.length - 1);
    if (bytes.isEmpty) return;
    if (bytes.length > maxLineBytes) {
      oversized++;
      return;
    }
    final text = utf8.decode(bytes, allowMalformed: true).trim();
    if (text.isNotEmpty) out.add(text);
  }
}
