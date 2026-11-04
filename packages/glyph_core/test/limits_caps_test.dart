// Every constant of `Limits` (SPEC section 6, "DoS caps on untrusted input"),
// exercised at the cap and one past it, in one place.
//
// The PGN caps keep their detailed tests in pgn_vectors_test.dart; this file
// re-checks them at cap / cap + 1 next to the others, adds the rest, and
// closes with a registry test: a new `Limits` constant without an entry in
// `_coverage` fails, and every entry must name a test file that really
// mentions the constant.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';

import 'online/fake_site.dart';

/// How each constant is covered. `cap` = a behavioural test at the cap and at
/// cap + 1 (here or in the named file); `value` = pinned value only, with the
/// reason no behavioural cap test exists.
const Map<String, ({String kind, String where})> _coverage = {
  'maxPgnBytes': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxGamesPerFile': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxPliesPerGame': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxCommentBytes': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxOnlineGames': (kind: 'cap', where: 'limits_caps_test.dart'),
  'defaultOnlineGames': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxNdjsonLineBytes': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxOnlineResponseBytes': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxChessComArchiveRequests': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxRateLimitWait': (kind: 'cap', where: 'limits_caps_test.dart'),
  'rateLimitWait': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxRateLimitRetries': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxOnlineCacheBodyBytes': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxLlmStreamBytes': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxLlmTotalStreamBytes': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxSseEventBytes': (kind: 'cap', where: 'limits_caps_test.dart'),
  'maxLlmErrorBodyBytes': (kind: 'cap', where: 'limits_caps_test.dart'),
  'firstByteTimeout': (kind: 'cap', where: 'limits_caps_test.dart'),
  'totalTimeout': (kind: 'cap', where: 'limits_caps_test.dart'),
  // The connect timeout is a setting of the dart:io client the app builds
  // (`createLlmHttpClient`, `createOnlineHttpClient`); the `http` interface
  // has no such knob, so the core cannot enforce it. app/test/platform_http_test.dart
  // checks that both app factories apply it. A connect that never answers
  // cannot be simulated reliably on a CI host.
  'connectTimeout': (kind: 'value', where: 'limits_test.dart'),
};

String _limitsSource() => File('lib/src/util/limits.dart').readAsStringSync();

Duration _ms(int n) => Duration(milliseconds: n);

void main() {
  group('registry', () {
    test('every Limits constant has an entry, and every entry names a test that mentions it', () {
      final names = RegExp(r'static const (?:int|Duration) (\w+) =').allMatches(_limitsSource()).map((m) => m.group(1)!).toSet();
      expect(names, isNotEmpty);
      expect(_coverage.keys.toSet(), names, reason: 'a Limits constant without a coverage entry (or an entry for a removed one)');
      for (final e in _coverage.entries) {
        final candidates = [
          File('test/${e.value.where}'),
          for (final d in Directory('test').listSync(recursive: true))
            if (d is File && d.path.endsWith(e.value.where)) d,
        ];
        final file = candidates.firstWhere((f) => f.existsSync(), orElse: () => File('missing'));
        expect(file.existsSync(), isTrue, reason: '${e.key}: ${e.value.where} does not exist');
        expect(file.readAsStringSync(), contains(e.key), reason: '${e.value.where} never mentions ${e.key}');
      }
    });

    test('constants without a behavioural cap test are listed (and justified above)', () {
      final valueOnly = _coverage.entries.where((e) => e.value.kind == 'value').map((e) => e.key).toList();
      expect(valueOnly, ['connectTimeout']);
    });
  });

  group('PGN input', () {
    final game = '[Event "x"]\n\n1. e4 e5 *\n';

    test('maxPgnBytes: exactly 2 MB parses, one byte more is refused (string and bytes)', () {
      final at = game + ' ' * (Limits.maxPgnBytes - game.length);
      expect(utf8.encode(at).length, Limits.maxPgnBytes);
      expect(parsePgn(at), isA<PgnOk>());
      final over = '$at ';
      expect(parsePgn(over), isA<PgnFailed>());
      expect((parsePgn(over) as PgnFailed).issues.single.kind, PgnIssueKind.tooLarge);
      expect(parsePgnBytes(Uint8List.fromList(utf8.encode(at))), isA<PgnOk>());
      expect(parsePgnBytes(Uint8List.fromList(utf8.encode(over))), isA<PgnFailed>());
    });

    test('maxGamesPerFile: 500 games are all listed, the 501st is dropped with a note', () {
      String tiny(int i) => '[Event "g$i"]\n\n1. e4 *\n';
      final at = parsePgn(List.generate(Limits.maxGamesPerFile, tiny).join('\n'));
      expect(at, isA<PgnOk>());
      expect(at.games, hasLength(Limits.maxGamesPerFile));
      final over = parsePgn(List.generate(Limits.maxGamesPerFile + 1, tiny).join('\n'));
      expect(over, isA<PgnPartial>());
      expect(over.games, hasLength(Limits.maxGamesPerFile));
      expect((over as PgnPartial).skipped.map((i) => i.kind), contains(PgnIssueKind.tooManyGames));
    });

    String shuffle(int plies) {
      final moves = <String>[];
      const cycle = ['Nf3', 'Nf6', 'Ng1', 'Ng8'];
      for (var i = 0; i < plies; i++) {
        final san = cycle[i % 4];
        moves.add(i.isEven ? '${i ~/ 2 + 1}. $san' : san);
      }
      return '${moves.join(' ')} *';
    }

    test('maxPliesPerGame: 1000 plies are accepted, 1001 are refused with the ply named', () {
      final at = parsePgn(shuffle(Limits.maxPliesPerGame));
      expect(at, isA<PgnOk>());
      expect(at.games.single.plyCount, Limits.maxPliesPerGame);
      final over = parsePgn(shuffle(Limits.maxPliesPerGame + 1));
      expect(over, isA<PgnFailed>());
      final issue = (over as PgnFailed).issue;
      expect(issue.kind, PgnIssueKind.tooManyPlies);
      expect(issue.ply, Limits.maxPliesPerGame + 1);
    });

    test('maxCommentBytes: a 4096-byte comment is kept whole, 4097 is cut to 4096', () {
      final at = parsePgn('1. e4 {${'y' * Limits.maxCommentBytes}} *').games.single.plies.single.comment!;
      expect(at.length, Limits.maxCommentBytes);
      final over = parsePgn('1. e4 {${'y' * (Limits.maxCommentBytes + 1)}} *').games.single.plies.single.comment!;
      expect(over.length, Limits.maxCommentBytes);
      // In bytes, not characters: two-byte characters are cut at a boundary.
      final wide = parsePgn('1. e4 {${'é' * (Limits.maxCommentBytes)}} *').games.single.plies.single.comment!;
      expect(utf8.encode(wide).length, lessThanOrEqualTo(Limits.maxCommentBytes));
    });
  });

  group('online fetch', () {
    late FakeSite site;
    setUp(() async => site = await FakeSite.start());
    tearDown(() => site.close());

    LichessClient lichess({Future<void> Function(Duration)? sleep, int retries = Limits.maxRateLimitRetries}) => LichessClient(
          httpClient: plainClient,
          userAgent: userAgent,
          baseUri: site.baseUri,
          sleep: sleep,
          maxRateLimitRetries: retries,
        );

    ChessComClient chessCom({OnlineCache? cache, Future<void> Function(Duration)? sleep}) => ChessComClient(
          httpClient: plainClient,
          userAgent: userAgent,
          baseUri: site.baseUri,
          cache: cache,
          sleep: sleep,
        );

    List<Map<String, Object?>> games(int n, [String prefix = 'game']) => [for (var i = 0; i < n; i++) lichessGame('$prefix${i.toString().padLeft(4, '0')}')];

    test('maxOnlineGames: 50 may be asked for and arrive; 51 is clamped to 50 (lichess and chess.com)', () async {
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(ndjson(games(Limits.maxOnlineGames + 10))), 8192);
      final at = await lichess().fetchGames('alice', max: Limits.maxOnlineGames);
      expect(at.games, hasLength(Limits.maxOnlineGames));
      expect(site.requests.last.uri.queryParameters['max'], '${Limits.maxOnlineGames}');
      final over = await lichess().fetchGames('alice', max: Limits.maxOnlineGames + 1);
      expect(over.games, hasLength(Limits.maxOnlineGames));
      expect(site.requests.last.uri.queryParameters['max'], '${Limits.maxOnlineGames}', reason: 'the request never asks for more than the cap');

      site.requests.clear();
      FakeChessCom(site, 'alice', {
        (2026, 10): [for (var i = 0; i < Limits.maxOnlineGames + 10; i++) chessComGame('c$i', endTime: 1700000000 + i)],
      }).install();
      expect((await chessCom().fetchGames('alice', max: Limits.maxOnlineGames)).games, hasLength(Limits.maxOnlineGames));
      expect((await chessCom().fetchGames('alice', max: Limits.maxOnlineGames + 1)).games, hasLength(Limits.maxOnlineGames));
    });

    test('defaultOnlineGames: 30 are asked for and returned, the 31st is never read', () async {
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(ndjson(games(Limits.defaultOnlineGames + 1))), 4096);
      final outcome = await lichess().fetchGames('alice');
      expect(site.requests.single.uri.queryParameters['max'], '${Limits.defaultOnlineGames}');
      expect(outcome.games, hasLength(Limits.defaultOnlineGames));
      expect(outcome.games.last.sourceId, 'game${(Limits.defaultOnlineGames - 1).toString().padLeft(4, '0')}');
    });

    test('maxNdjsonLineBytes: a line of exactly 1 MB is read, one byte more is dropped (the games around it survive)', () async {
      String lineOfSize(String id, int size) {
        final base = jsonEncode({...lichessGame(id), 'pad': ''});
        final pad = size - utf8.encode(base).length;
        expect(pad, isNonNegative);
        final line = jsonEncode({...lichessGame(id), 'pad': 'x' * pad});
        expect(utf8.encode(line).length, size);
        return line;
      }

      for (final (size, expected, skipped) in [
        (Limits.maxNdjsonLineBytes, ['aaaaaaa1', 'bigbigbg', 'aaaaaaa2'], 0),
        (Limits.maxNdjsonLineBytes + 1, ['aaaaaaa1', 'aaaaaaa2'], 1),
      ]) {
        final text = '${jsonEncode(lichessGame('aaaaaaa1'))}\n${lineOfSize('bigbigbg', size)}\n${jsonEncode(lichessGame('aaaaaaa2'))}\n';
        site.handler = (req, seen) => sendChunked(req.response, utf8.encode(text), 100000);
        final outcome = await lichess().fetchGames('alice');
        expect(outcome.games.map((g) => g.sourceId).toList(), expected, reason: 'line of $size bytes');
        expect(outcome.skipped, skipped, reason: 'line of $size bytes');
      }
    });

    test('maxOnlineResponseBytes: a stream of exactly 16 MB is read to its end, one byte more fails with tooLarge', () async {
      Future<void> serve(HttpResponse response, int total) async {
        response.bufferOutput = false;
        response.headers.contentType = ContentType.parse('application/x-ndjson');
        final first = utf8.encode('${jsonEncode(lichessGame('aaaaaaa1'))}\n');
        response.add(first);
        var sent = first.length;
        final blanks = Uint8List(1024 * 1024)..fillRange(0, 1024 * 1024, 0x0a);
        while (sent < total) {
          final n = (total - sent) < blanks.length ? total - sent : blanks.length;
          response.add(Uint8List.sublistView(blanks, 0, n));
          sent += n;
          await response.flush();
        }
        await response.close();
      }

      site.handler = (req, seen) => serve(req.response, Limits.maxOnlineResponseBytes);
      final at = await lichess().fetchGames('alice');
      expect(at.error, isNull, reason: 'exactly at the cap');
      expect(at.games.single.sourceId, 'aaaaaaa1');
      site.handler = (req, seen) => serve(req.response, Limits.maxOnlineResponseBytes + 1);
      final over = await lichess().fetchGames('alice');
      expect(over.error?.kind, OnlineErrorKind.tooLarge);
    });

    test('maxChessComArchiveRequests: at most 36 months are requested, however many the archive lists', () async {
      for (final listed in [Limits.maxChessComArchiveRequests - 1, Limits.maxChessComArchiveRequests, Limits.maxChessComArchiveRequests + 1, 80]) {
        site.requests.clear();
        // Months with nothing the app can use, so the walk never reaches 30 games.
        FakeChessCom(site, 'alice', {
          for (var i = 0; i < listed; i++) (2020 + i ~/ 12, i % 12 + 1): [chessComGame('b$i', rules: 'bughouse')],
        }).install();
        final outcome = await chessCom().fetchGames('alice');
        expect(outcome.games, isEmpty);
        final monthRequests = site.requests.where((r) => !r.path.endsWith('/archives')).length;
        expect(monthRequests, listed < Limits.maxChessComArchiveRequests ? listed : Limits.maxChessComArchiveRequests, reason: '$listed months listed');
      }
    });

    test('rateLimitWait and maxRateLimitWait: Retry-After is floored at 60 s and capped at 300 s (59, 60, 61, 300, 301)', () async {
      for (final (header, expected) in [
        (59, 60),
        (60, 60),
        (61, 61),
        (Limits.maxRateLimitWait.inSeconds, Limits.maxRateLimitWait.inSeconds),
        (Limits.maxRateLimitWait.inSeconds + 1, Limits.maxRateLimitWait.inSeconds),
      ]) {
        var calls = 0;
        site.handler = (req, seen) async {
          if (calls++ == 0) return sendStatus(req.response, 429, headers: {'retry-after': '$header'});
          return sendChunked(req.response, utf8.encode(ndjson([lichessGame('aaaaaaa1')])), 100);
        };
        final totals = <Duration>[];
        final outcome = await lichess(sleep: (d) async {}).fetchGames('alice', onEvent: (e) {
          if (e is OnlineBackoff && !totals.contains(e.total)) totals.add(e.total);
        });
        expect(outcome.games, hasLength(1));
        expect(totals, [Duration(seconds: expected)], reason: 'Retry-After: $header');
      }
    });

    test('maxRateLimitRetries: success on the last allowed retry works; one more 429 gives up after exactly 1 + retries requests', () async {
      var failures = Limits.maxRateLimitRetries;
      var calls = 0;
      site.handler = (req, seen) async {
        calls++;
        if (failures-- > 0) return sendStatus(req.response, 429);
        return sendChunked(req.response, utf8.encode(ndjson([lichessGame('aaaaaaa1')])), 100);
      };
      final ok = await lichess(sleep: (d) async {}).fetchGames('alice');
      expect(ok.games, hasLength(1));
      expect(calls, 1 + Limits.maxRateLimitRetries);

      site.requests.clear();
      failures = Limits.maxRateLimitRetries + 1;
      calls = 0;
      final over = await lichess(sleep: (d) async {}).fetchGames('alice');
      expect(over.error?.kind, OnlineErrorKind.rateLimited);
      expect(calls, 1 + Limits.maxRateLimitRetries, reason: 'the request after the last retry is never sent');
    });

    test('maxOnlineCacheBodyBytes: an archive list of exactly 1 MB is cached, one byte more is used but not stored', () async {
      for (final extra in [0, 1]) {
        final archives = [archiveUrl('alice', 2026, 10)];
        String body(int pad) => jsonEncode({'archives': archives, 'pad': 'x' * pad});
        final pad = Limits.maxOnlineCacheBodyBytes - utf8.encode(body(0)).length + extra;
        expect(utf8.encode(body(pad)).length, Limits.maxOnlineCacheBodyBytes + extra);
        FakeChessCom(site, 'alice', {(2026, 10): [chessComGame('only1')]}).install();
        final inner = site.handler!;
        site.handler = (req, seen) async {
          if (seen.path.endsWith('/games/archives')) {
            req.response.statusCode = 200;
            req.response.headers.contentType = ContentType.json;
            req.response.headers.set('etag', 'W/"big$extra"');
            req.response.write(body(pad));
            return req.response.close();
          }
          return inner(req, seen);
        };
        final cache = InMemoryOnlineCache();
        final outcome = await chessCom(cache: cache).fetchGames('alice');
        expect(outcome.games, hasLength(1), reason: 'extra $extra: the data is used either way');
        expect(cache.entries.keys.any((k) => k.endsWith('/games/archives')), extra == 0, reason: 'extra $extra');
      }
    });
  });

  group('LLM stream', () {
    String sse(String delta, {String? finish}) =>
        'data: ${jsonEncode({
          'choices': [
            {'index': 0, 'delta': delta.isEmpty ? <String, Object?>{} : {'content': delta}, 'finish_reason': finish},
          ],
        })}\n\n';

    LlmRequest request() => const LlmRequest(
          config: LlmConfig(baseUrl: 'https://llm.example/v1', model: 'm'),
          messages: [ChatMessage(ChatRole.user, 'hi')],
        );

    LlmClient clientFor(Stream<List<int>> Function() body, {LlmTimeouts timeouts = LlmTimeouts.standard, Duration? headersDelay}) => LlmClient(
          httpClient: () => MockClient.streaming((req, _) async {
            if (headersDelay != null) await Future<void>.delayed(headersDelay);
            return http.StreamedResponse(body(), 200, headers: {'content-type': 'text/event-stream'});
          }),
          timeouts: timeouts,
        );

    Future<({String text, LlmFinished? done, LlmException? error})> run(LlmClient c) async {
      final text = StringBuffer();
      LlmFinished? done;
      LlmException? error;
      await c.stream(request(), readApiKey: () async => 'k').handleError((Object e) => error = e as LlmException).forEach((e) {
        if (e is LlmTextDelta) text.write(e.text);
        if (e is LlmFinished) done = e;
      });
      return (text: text.toString(), done: done, error: error);
    }

    /// The answer split into 4 KB deltas, then `[DONE]`.
    Stream<List<int>> answer(int bytes) async* {
      var left = bytes;
      while (left > 0) {
        final n = left < 4096 ? left : 4096;
        yield utf8.encode(sse('a' * n));
        left -= n;
      }
      yield utf8.encode('data: [DONE]\n\n');
    }

    test('maxLlmStreamBytes: an answer of exactly 32 KB is complete, one byte more is cut and marked truncated', () async {
      final at = await run(clientFor(() => answer(Limits.maxLlmStreamBytes)));
      expect(at.error, isNull);
      expect(utf8.encode(at.text).length, Limits.maxLlmStreamBytes);
      expect(at.done!.truncated, isFalse);
      expect(at.done!.complete, isTrue);

      final over = await run(clientFor(() => answer(Limits.maxLlmStreamBytes + 1)));
      expect(over.error, isNull);
      expect(utf8.encode(over.text).length, Limits.maxLlmStreamBytes);
      expect(over.done!.truncated, isTrue);
      expect(over.done!.complete, isFalse);
    });

    test('maxLlmTotalStreamBytes: 1 MB of anything is read, one byte more fails with badStream', () async {
      Stream<List<int>> padded(int total) async* {
        final head = utf8.encode(sse('Hi'));
        final tail = utf8.encode('data: [DONE]\n\n');
        yield head;
        var sent = head.length;
        // Comment events carry no data: they only count towards the total.
        while (sent + tail.length < total) {
          final room = total - sent - tail.length;
          final n = room < 20000 ? room : 20000;
          final line = n >= 4 ? ': ${'p' * (n - 4)}\n\n' : ' ' * n;
          final bytes = utf8.encode(line);
          expect(bytes.length, n);
          yield bytes;
          sent += n;
        }
        yield tail;
      }

      final at = await run(clientFor(() => padded(Limits.maxLlmTotalStreamBytes)));
      expect(at.error, isNull, reason: 'exactly at the cap');
      expect(at.text, 'Hi');
      final over = await run(clientFor(() => padded(Limits.maxLlmTotalStreamBytes + 1)));
      expect(over.error?.error.kind, LlmErrorKind.badStream);
    });

    test('maxSseEventBytes: a line of exactly 256 KB is decoded, one character more is refused', () {
      final at = SseDecoder();
      final events = at.add(utf8.encode('data: ${'x' * (Limits.maxSseEventBytes - 6)}\n\n'));
      expect(events.single.data.length, Limits.maxSseEventBytes - 6);
      final over = SseDecoder();
      expect(() => over.add(utf8.encode('data: ${'x' * (Limits.maxSseEventBytes - 5)}\n\n')), throwsA(isA<SseFormatException>()));
    });

    test('maxLlmErrorBodyBytes: an error body of 64 KB is read whole, one byte more is cut at 64 KB', () async {
      Stream<List<int>> body(int n) => Stream.value(List.filled(n, 0x41));
      expect((await ErrorMapper.readBody(body(Limits.maxLlmErrorBodyBytes - 1))).length, Limits.maxLlmErrorBodyBytes - 1);
      expect((await ErrorMapper.readBody(body(Limits.maxLlmErrorBodyBytes))).length, Limits.maxLlmErrorBodyBytes);
      expect((await ErrorMapper.readBody(body(Limits.maxLlmErrorBodyBytes + 1))).length, Limits.maxLlmErrorBodyBytes);
    });

    test('firstByteTimeout and totalTimeout: the defaults are the SPEC values, and the boundary behaves (scaled)', () async {
      expect(LlmTimeouts.standard.firstByte, Limits.firstByteTimeout);
      expect(LlmTimeouts.standard.total, Limits.totalTimeout);
      expect(LlmTimeouts.standard.connect, Limits.connectTimeout);
      expect(const OnlineTimeouts().firstByte, Limits.firstByteTimeout);
      expect(const OnlineTimeouts().total, Limits.totalTimeout);

      // First byte: headers just inside the limit arrive; just outside time out.
      final firstByte = _ms(300);
      final inside = await run(clientFor(() => answer(10), timeouts: LlmTimeouts(firstByte: firstByte, total: const Duration(seconds: 30)), headersDelay: _ms(100)));
      expect(inside.error, isNull);
      expect(inside.text, 'a' * 10);
      final outside = await run(clientFor(() => answer(10), timeouts: LlmTimeouts(firstByte: firstByte, total: const Duration(seconds: 30)), headersDelay: _ms(900)));
      expect(outside.error?.error.kind, LlmErrorKind.timeout);

      // Total: a stream that finishes inside the limit completes; one that keeps
      // going past it is stopped with `timeout`.
      Stream<List<int>> slow(int chunks) async* {
        for (var i = 0; i < chunks; i++) {
          await Future<void>.delayed(_ms(60));
          yield utf8.encode(sse('x'));
        }
        yield utf8.encode('data: [DONE]\n\n');
      }

      final total = _ms(700);
      final done = await run(clientFor(() => slow(3), timeouts: LlmTimeouts(firstByte: const Duration(seconds: 5), total: total)));
      expect(done.error, isNull);
      expect(done.text, 'xxx');
      final late = await run(clientFor(() => slow(30), timeouts: LlmTimeouts(firstByte: const Duration(seconds: 5), total: total)));
      expect(late.error?.error.kind, LlmErrorKind.timeout);
    });
  });
}
