import 'dart:convert';

import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/src/online/ndjson.dart';
import 'package:test/test.dart';

void main() {
  group('Usernames', () {
    test('lichess: 2-30 chars of letters, digits, _ and -, ending in a letter or digit', () {
      for (final ok in ['ab', 'DrNykterstein', 'a_b-c', '1abc', 'x' * 30, 'Zz9']) {
        expect(Usernames.isValidLichess(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'a', '-ab', 'ab-', 'a b', 'x' * 31, 'a/b', 'ä', 'a.b', 'a\nb']) {
        expect(Usernames.isValidLichess(bad), isFalse, reason: bad);
      }
    });

    test('chess.com: 3-25 chars of letters, digits, _ and -', () {
      for (final ok in ['abc', 'Hikaru', 'a_b-c', 'x' * 25]) {
        expect(Usernames.isValidChessCom(ok), isTrue, reason: ok);
      }
      for (final bad in ['', 'ab', 'x' * 26, 'a b', 'a/b', 'a.b', 'ä1x', 'a\nb']) {
        expect(Usernames.isValidChessCom(bad), isFalse, reason: bad);
      }
    });
  });

  group('NdjsonLineSplitter', () {
    test('splits on \\n whatever the chunking', () {
      final bytes = utf8.encode('{"a":1}\n{"b":"ß"}\r\n\n{"c":3}');
      for (var size = 1; size <= bytes.length; size++) {
        final splitter = NdjsonLineSplitter(maxLineBytes: 100);
        final lines = <String>[];
        for (var i = 0; i < bytes.length; i += size) {
          lines.addAll(splitter.add(bytes.sublist(i, i + size > bytes.length ? bytes.length : i + size)));
        }
        lines.addAll(splitter.close());
        expect(lines, ['{"a":1}', '{"b":"ß"}', '{"c":3}'], reason: 'chunk size $size');
      }
    });

    test('an over-long line is dropped without being kept; the next line is intact', () {
      final splitter = NdjsonLineSplitter(maxLineBytes: 10);
      final lines = [
        ...splitter.add(utf8.encode('short\n')),
        ...splitter.add(utf8.encode('x' * 50)),
        ...splitter.add(utf8.encode('y' * 50)),
        ...splitter.add(utf8.encode('\nafter\n')),
        ...splitter.close(),
      ];
      expect(lines, ['short', 'after']);
      expect(splitter.oversized, 1);
    });

    test('a line of exactly the cap is kept; one byte more is dropped', () {
      final splitter = NdjsonLineSplitter(maxLineBytes: 10);
      expect(splitter.add(utf8.encode('${'a' * 10}\n')), ['a' * 10]);
      expect(splitter.add(utf8.encode('${'a' * 11}\n')), isEmpty);
      expect(splitter.oversized, 1);
    });

    test('malformed UTF-8 does not throw', () {
      final splitter = NdjsonLineSplitter(maxLineBytes: 100);
      expect(splitter.add([0xFF, 0x41, 0x0A]).single, contains('A'));
    });
  });

  group('limits and hygiene', () {
    test('online caps', () {
      expect(Limits.defaultOnlineGames, 30);
      expect(Limits.maxOnlineGames, 50);
      expect(Limits.maxOnlineResponseBytes, 16 * 1024 * 1024);
      expect(Limits.maxChessComArchiveRequests, 36);
      expect(Limits.rateLimitWait, const Duration(seconds: 60));
      expect(Limits.maxRateLimitWait, const Duration(minutes: 5));
    });
  });
}
