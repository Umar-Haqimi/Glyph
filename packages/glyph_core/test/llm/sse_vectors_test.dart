import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

/// The SSE vectors of SPEC 7.1 item 6. They are SYNTHETIC (see
/// test/vectors/sse/manifest.json and docs/m0/VECTORS.md section 4): built
/// from each provider's documented format, because no API keys were available.
/// The test is the one that will run on real captures too.
const dir = 'test/vectors/sse';

final manifest = jsonDecode(File('$dir/manifest.json').readAsStringSync()) as Map<String, dynamic>;
final vectors = [for (final v in manifest['vectors'] as List<dynamic>) v as Map<String, dynamic>];

/// What reading a stream gives: the text, the finish reason and the failure.
class Outcome {
  String text = '';
  String? finish;
  bool done = false;
  LlmErrorKind? error;
}

Outcome readStream(List<List<int>> chunks) {
  final out = Outcome();
  final decoder = SseDecoder();
  bool feed(List<SseEvent> events) {
    for (final e in events) {
      for (final item in parseChatEvent(e)) {
        switch (item) {
          case ChatDelta(:final text):
            out.text += text;
          case ChatFinish(:final reason):
            out.finish = reason;
          case ChatDone():
            out.done = true;
            return true;
          case ChatFailure(:final error):
            out.error = error.kind;
            return true;
        }
      }
    }
    return false;
  }

  for (final c in chunks) {
    if (feed(decoder.add(c))) return out;
  }
  feed(decoder.close());
  return out;
}

void main() {
  final streams = vectors.where((v) => v['type'] == 'stream').toList();
  final errors = vectors.where((v) => v['type'] == 'http').toList();

  test('synthetic vectors carry the marker; the top-level flag means "any synthetic"', () {
    final flags = [for (final v in vectors) v['synthetic'] as bool];
    expect(manifest['synthetic'], flags.any((f) => f));
    for (final v in vectors) {
      final text = File('$dir/${v['file']}').readAsStringSync();
      if (v['synthetic'] == true) {
        expect(text.toLowerCase(), contains('synthetic'), reason: '${v['file']} must carry the marker');
      } else {
        // A real capture must not claim to be synthetic and must be redacted.
        expect(text.toLowerCase(), isNot(contains('synthetic')), reason: '${v['file']} is marked real');
        expect(text, isNot(matches(RegExp(r'sk-|bearer', caseSensitive: false))), reason: '${v['file']} is not redacted');
      }
    }
  });

  group('streams decode identically at every split', () {
    for (final v in streams) {
      final file = v['file'] as String;
      final bytes = File('$dir/$file').readAsBytesSync();

      void check(Outcome o, String reason) {
        expect(o.text, v['text'], reason: '$file $reason');
        expect(o.error?.name, v['errorKind'], reason: '$file $reason');
        expect(o.finish, v['finishReason'], reason: '$file $reason');
      }

      test('$file: whole', () => check(readStream([bytes]), 'whole'));

      test('$file: every byte boundary', () {
        for (var cut = 1; cut < bytes.length; cut++) {
          check(readStream([bytes.sublist(0, cut), bytes.sublist(cut)]), 'cut at $cut');
        }
      });

      test('$file: 200 random multi-chunk splits and byte-by-byte', () {
        final rnd = Random(42);
        for (var i = 0; i < 200; i++) {
          final cuts = <int>{for (var k = 0; k < 1 + rnd.nextInt(12); k++) 1 + rnd.nextInt(bytes.length - 1)}.toList()..sort();
          final chunks = <List<int>>[];
          var last = 0;
          for (final c in [...cuts, bytes.length]) {
            chunks.add(bytes.sublist(last, c));
            last = c;
          }
          check(readStream(chunks), 'cuts $cuts');
        }
        check(readStream([for (final b in bytes) [b]]), 'byte by byte');
      });

      test('$file: through LlmClient (MockClient, split into 7-byte chunks)', () async {
        final client = LlmClient(
          httpClient: () => MockClient.streaming((request, body) async {
            final chunks = <List<int>>[for (var i = 0; i < bytes.length; i += 7) bytes.sublist(i, min(i + 7, bytes.length))];
            return http.StreamedResponse(Stream.fromIterable(chunks), 200, headers: {'content-type': 'text/event-stream'});
          }),
        );
        final events = <LlmEvent>[];
        Object? error;
        await client
            .stream(
              const LlmRequest(
                config: LlmConfig(baseUrl: 'https://api.example.com/v1', model: 'm'),
                messages: [ChatMessage(ChatRole.user, 'hi')],
              ),
              readApiKey: () async => 'sk-test',
            )
            .handleError((Object e) => error = e)
            .forEach(events.add);
        final text = events.whereType<LlmTextDelta>().map((e) => e.text).join();
        expect(text, v['text'], reason: file);
        if (v['errorKind'] == null) {
          expect(error, isNull, reason: file);
          expect((events.last as LlmFinished).finishReason, v['finishReason']);
        } else {
          expect((error as LlmException).error.kind.name, v['errorKind']);
        }
      });
    }
  });

  group('HTTP error bodies map to the right failure', () {
    for (final v in errors) {
      final file = v['file'] as String;
      test(file, () {
        final raw = File('$dir/$file').readAsStringSync();
        final split = raw.indexOf('\r\n\r\n');
        final head = raw.substring(0, split);
        final body = raw.substring(split + 4);
        final status = int.parse(head.split(' ')[1]);
        expect(status, v['status']);
        final error = ErrorMapper.fromHttp(status, body);
        expect(error.kind.name, v['errorKind']);
        if (v['param'] != null) expect(error.param, v['param']);
        expect(error.status, status);
      });
    }
  });

  test('every stream truncated at an arbitrary byte is either a clean prefix or a clean failure', () {
    for (final v in streams.where((s) => s['errorKind'] == null)) {
      final bytes = File('$dir/${v['file']}').readAsBytesSync();
      for (var cut = 0; cut < bytes.length; cut += 17) {
        try {
          final o = readStream([bytes.sublist(0, cut)]);
          expect((v['text'] as String).startsWith(o.text), isTrue, reason: '${v['file']} cut $cut');
        } on LlmException catch (e) {
          expect(e.error.kind, LlmErrorKind.badStream, reason: '${v['file']} cut $cut'); // cut inside a JSON chunk
        }
      }
    }
  });
}
