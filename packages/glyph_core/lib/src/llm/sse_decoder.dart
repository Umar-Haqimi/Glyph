import 'dart:async';
import 'dart:convert';

import '../util/limits.dart';

/// One dispatched server-sent event.
class SseEvent {
  const SseEvent({required this.data, this.event, this.id});

  /// The `data:` lines joined with `\n` (no trailing newline).
  final String data;

  /// The `event:` field, null for the default (`message`) event.
  final String? event;

  final String? id;

  @override
  String toString() => 'SseEvent(${event ?? 'message'}: $data)';
}

/// A stream the decoder cannot make sense of (an event or a line over
/// [Limits.maxSseEventBytes]).
class SseFormatException implements Exception {
  const SseFormatException(this.message);

  final String message;

  @override
  String toString() => 'SseFormatException: $message';
}

/// Incremental decoder for `text/event-stream` (WHATWG HTML, section 9.2.6).
///
/// * Bytes are UTF-8 decoded incrementally, so a multi-byte character split
///   across two chunks decodes correctly; malformed bytes become U+FFFD; a
///   leading byte-order mark is dropped.
/// * Lines end in LF, CRLF or a lone CR, wherever the chunk boundaries fall
///   (a CR at the end of one chunk and the LF at the start of the next count
///   once).
/// * A blank line dispatches the event; `data:` lines are joined with `\n`;
///   lines starting with `:` are comments (keep-alives such as OpenRouter's
///   `: OPENROUTER PROCESSING`) and are dropped; one space after the colon is
///   optional; unknown fields and `retry:` are ignored.
/// * Deviation (lenient): at [close] an event whose blank line never arrived
///   is still dispatched if it carries data; the WHATWG algorithm would drop
///   it. A stream cut mid-event then surfaces as unparseable data instead of
///   silently losing the last chunk.
///
/// Feed it with [add] / [close], or use [bind] on a byte stream. It never
/// splits a stream differently depending on where chunks end: the result for
/// one byte stream is the same for every chunking (tested at every boundary).
class SseDecoder {
  SseDecoder({this.maxEventBytes = Limits.maxSseEventBytes}) {
    _bytes = const Utf8Decoder(allowMalformed: true).startChunkedConversion(StringConversionSink.fromStringSink(_decoded));
  }

  final int maxEventBytes;

  final StringBuffer _decoded = StringBuffer();
  late final ByteConversionSink _bytes;
  final StringBuffer _line = StringBuffer();
  int _lineLength = 0;
  bool _afterCr = false;
  bool _first = true;

  final StringBuffer _data = StringBuffer();
  int _dataBytes = 0;
  bool _hasData = false;
  String? _event;
  String? _id;

  /// Decodes [chunk] and returns the events it completed.
  List<SseEvent> add(List<int> chunk) {
    _bytes.add(chunk);
    var text = _decoded.toString();
    _decoded.clear();
    if (_first && text.isNotEmpty) {
      _first = false;
      if (text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);
    }
    return _feed(text);
  }

  /// Ends the stream: flushes the UTF-8 decoder, handles an unterminated last
  /// line and dispatches a pending event (see the class comment).
  List<SseEvent> close() {
    _bytes.close();
    final tail = _decoded.toString();
    _decoded.clear();
    final out = _feed(tail);
    if (_lineLength > 0) {
      _processLine(_line.toString(), out);
      _line.clear();
      _lineLength = 0;
    }
    if (_hasData) _dispatch(out);
    return out;
  }

  /// Decodes a byte stream into events.
  static Stream<SseEvent> bind(Stream<List<int>> bytes, {int maxEventBytes = Limits.maxSseEventBytes}) async* {
    final decoder = SseDecoder(maxEventBytes: maxEventBytes);
    await for (final chunk in bytes) {
      for (final e in decoder.add(chunk)) {
        yield e;
      }
    }
    for (final e in decoder.close()) {
      yield e;
    }
  }

  List<SseEvent> _feed(String text) {
    final out = <SseEvent>[];
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (_afterCr) {
        _afterCr = false;
        if (c == 0x0A) {
          start = i + 1; // the LF of a CRLF that was split across chunks
          continue;
        }
      }
      if (c == 0x0A || c == 0x0D) {
        _append(text.substring(start, i));
        _processLine(_line.toString(), out);
        _line.clear();
        _lineLength = 0;
        start = i + 1;
        if (c == 0x0D) {
          // An LF right behind is part of this line break, even if it is the
          // first character of the next chunk.
          if (i + 1 < text.length) {
            if (text.codeUnitAt(i + 1) == 0x0A) {
              i++;
              start = i + 1;
            }
          } else {
            _afterCr = true;
          }
        }
      }
    }
    if (start < text.length) _append(text.substring(start));
    return out;
  }

  void _append(String s) {
    if (s.isEmpty) return;
    _lineLength += s.length;
    if (_lineLength > maxEventBytes) throw const SseFormatException('line too long');
    _line.write(s);
  }

  void _processLine(String line, List<SseEvent> out) {
    if (line.isEmpty) {
      if (_hasData) _dispatch(out);
      _event = null;
      _id = null;
      return;
    }
    if (line.startsWith(':')) return; // comment / keep-alive
    final colon = line.indexOf(':');
    final field = colon < 0 ? line : line.substring(0, colon);
    var value = colon < 0 ? '' : line.substring(colon + 1);
    if (value.startsWith(' ')) value = value.substring(1);
    switch (field) {
      case 'data':
        _dataBytes += value.length + 1;
        if (_dataBytes > maxEventBytes) throw const SseFormatException('event too large');
        if (_hasData) _data.write('\n');
        _data.write(value);
        _hasData = true;
      case 'event':
        _event = value.isEmpty ? null : value;
      case 'id':
        if (!value.contains('\u0000')) _id = value;
      default:
        break; // retry and unknown fields
    }
  }

  void _dispatch(List<SseEvent> out) {
    out.add(SseEvent(data: _data.toString(), event: _event, id: _id));
    _data.clear();
    _dataBytes = 0;
    _hasData = false;
    _event = null;
  }
}
