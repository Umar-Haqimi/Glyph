import 'dart:async';
import 'dart:convert';

import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

List<SseEvent> decodeAll(List<List<int>> chunks) {
  final d = SseDecoder();
  final out = <SseEvent>[];
  for (final c in chunks) {
    out.addAll(d.add(c));
  }
  out.addAll(d.close());
  return out;
}

List<SseEvent> decodeString(String s) => decodeAll([utf8.encode(s)]);

List<String> datas(List<SseEvent> events) => [for (final e in events) e.data];

void main() {
  group('lines and fields', () {
    test('LF, CRLF and lone CR all end lines', () {
      expect(datas(decodeString('data: a\n\ndata: b\r\n\r\ndata: c\r\r')), ['a', 'b', 'c']);
    });

    test('a CRLF split between chunks counts once', () {
      final events = decodeAll([utf8.encode('data: a\r'), utf8.encode('\ndata: b\r\n\r'), utf8.encode('\n')]);
      expect(datas(events), ['a\nb']);
    });

    test('multi-line data joins with newlines; one leading space is stripped', () {
      expect(datas(decodeString('data: line1\ndata:  line2\ndata:line3\ndata\n\n')), ['line1\n line2\nline3\n']);
    });

    test('an empty data line still dispatches an (empty) event', () {
      final events = decodeString('data:\n\n');
      expect(events, hasLength(1));
      expect(events.single.data, '');
    });

    test('comments and keep-alives are dropped, also between fields', () {
      final events = decodeString(': OPENROUTER PROCESSING\n\n: ping\ndata: x\n: mid\ndata: y\n\n');
      expect(datas(events), ['x\ny']);
    });

    test('event and id fields are read; retry and unknown fields are ignored', () {
      final events = decodeString('retry: 5\nfoo: bar\nid: 7\nevent: error\ndata: {}\n\ndata: next\n\n');
      expect(events.first.event, 'error');
      expect(events.first.id, '7');
      expect(events.last.event, isNull);
      expect(events.last.data, 'next');
    });

    test('blank lines without data dispatch nothing', () {
      expect(decodeString('\n\n\n: c\n\n'), isEmpty);
    });

    test('a colon in the value is kept', () {
      expect(datas(decodeString('data: {"a":"b:c"}\n\n')), ['{"a":"b:c"}']);
    });

    test('a leading byte-order mark is dropped', () {
      expect(datas(decodeAll([[0xEF, 0xBB, 0xBF], utf8.encode('data: hi\n\n')])), ['hi']);
    });

    test('an unterminated last event is still delivered at close (lenient)', () {
      expect(datas(decodeString('data: a\n\ndata: tail')), ['a', 'tail']);
      expect(datas(decodeString('data: a\n\ndata: tail\n')), ['a', 'tail']);
    });

    test('a comment alone at the end is not an event', () {
      expect(decodeString('data: a\n\n: bye'), hasLength(1));
    });
  });

  group('UTF-8', () {
    test('multi-byte characters split across chunks decode correctly', () {
      const text = 'data: café 日本語 ♞ 😀\n\n';
      final bytes = utf8.encode(text);
      for (var cut = 1; cut < bytes.length; cut++) {
        final events = decodeAll([bytes.sublist(0, cut), bytes.sublist(cut)]);
        expect(datas(events), ['café 日本語 ♞ 😀'], reason: 'cut at $cut');
      }
    });

    test('one byte at a time', () {
      final bytes = utf8.encode('data: 日本語 😀\r\n\r\n');
      expect(datas(decodeAll([for (final b in bytes) [b]])), ['日本語 😀']);
    });

    test('malformed bytes become U+FFFD, never an exception', () {
      final events = decodeAll([
        [...utf8.encode('data: a'), 0xFF, ...utf8.encode('b\n\n')],
      ]);
      expect(datas(events), ['a�b']);
    });
  });

  group('limits', () {
    test('a line without a terminator is refused above the cap', () {
      final d = SseDecoder(maxEventBytes: 100);
      expect(() => d.add(utf8.encode('data: ${'x' * 200}')), throwsA(isA<SseFormatException>()));
    });

    test('an event that grows over many data lines is refused above the cap', () {
      final d = SseDecoder(maxEventBytes: 100);
      expect(() {
        for (var i = 0; i < 50; i++) {
          d.add(utf8.encode('data: ${'y' * 10}\n'));
        }
      }, throwsA(isA<SseFormatException>()));
    });

    test('comment-only floods do not accumulate', () {
      final d = SseDecoder(maxEventBytes: 100);
      for (var i = 0; i < 1000; i++) {
        expect(d.add(utf8.encode(': keep-alive $i\n\n')), isEmpty);
      }
    });

    test('the default cap is Limits.maxSseEventBytes', () {
      expect(SseDecoder().maxEventBytes, Limits.maxSseEventBytes);
    });
  });

  test('bind() decodes a byte stream', () async {
    final stream = Stream.fromIterable([utf8.encode('data: a\n'), utf8.encode('\ndata: b\n\n')]);
    expect(datas(await SseDecoder.bind(stream).toList()), ['a', 'b']);
  });
}
