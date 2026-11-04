import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import 'fake_site.dart';

void main() {
  late FakeSite site;
  setUp(() async => site = await FakeSite.start());
  tearDown(() => site.close());

  LichessClient client({
    OnlineTimeouts timeouts = const OnlineTimeouts(),
    Future<void> Function(Duration)? sleep,
    Duration? rateLimitWait,
    int retries = Limits.maxRateLimitRetries,
    Uri? base,
  }) =>
      LichessClient(
        httpClient: plainClient,
        userAgent: userAgent,
        baseUri: base ?? site.baseUri,
        timeouts: timeouts,
        sleep: sleep,
        rateLimitWait: rateLimitWait ?? Limits.rateLimitWait,
        maxRateLimitRetries: retries,
      );

  group('request', () {
    test('GET /api/games/user/{name} with the documented parameters, a generic User-Agent, no credentials', () async {
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(ndjson([lichessGame('aaaaaaaa')])), 1000);
      final outcome = await client().fetchGames('Alice_99');
      expect(outcome.ok, isTrue);
      final seen = site.requests.single;
      expect(seen.method, 'GET');
      expect(seen.path, '/api/games/user/Alice_99');
      final q = seen.uri.queryParameters;
      expect(q['max'], '30');
      expect(q['pgnInJson'], 'true');
      expect(q['clocks'], 'true');
      expect(q['evals'], 'true');
      expect(q['opening'], 'true');
      expect(q['sort'], 'dateDesc');
      expect(q['perfType']!.split(','), containsAll(['bullet', 'blitz', 'rapid', 'classical', 'correspondence', 'chess960']));
      expect(q['perfType'], isNot(contains('crazyhouse')));
      expect(seen.headers['accept'], 'application/x-ndjson');
      expect(seen.headers['user-agent'], userAgent);
      expect(seen.headers['authorization'], isNull);
      expect(seen.headers['cookie'], isNull);
    });

    test('the default host is https lichess.org', () {
      expect(LichessClient.defaultBaseUrl, 'https://lichess.org');
      expect(LichessClient(httpClient: plainClient, userAgent: userAgent).baseUri.scheme, 'https');
    });

    test('an invalid username never reaches the network', () async {
      for (final bad in ['', 'a', 'x y', '../etc', 'bob/../../x', 'a' * 31, 'bob?x=1', 'bob#', '_bob', 'bob_']) {
        final outcome = await client().fetchGames(bad);
        expect(outcome.error?.kind, OnlineErrorKind.invalidUsername, reason: bad);
      }
      expect(site.requests, isEmpty);
    });

    test('max is capped at 50', () async {
      site.handler = (req, seen) => sendChunked(req.response, const [], 10);
      await client().fetchGames('alice', max: 500);
      expect(site.requests.single.uri.queryParameters['max'], '${Limits.maxOnlineGames}');
    });
  });

  group('NDJSON stream', () {
    final names = ['Zoë', '日本語', 'bob'];
    final games = [
      for (var i = 0; i < 5; i++) lichessGame('game000$i', white: names[i % 3], black: 'bob', createdAt: 1700000000000 - i),
    ];
    final body = utf8.encode(ndjson(games));

    for (final chunk in [1, 2, 3, 7, 64, 1000, 1 << 20]) {
      test('lines split across chunks of $chunk byte(s), including inside multi-byte characters', () async {
        site.handler = (req, seen) => sendChunked(req.response, body, chunk);
        final events = <OnlineEvent>[];
        final outcome = await client().fetchGames('alice', onEvent: events.add);
        expect(outcome.ok, isTrue);
        expect(outcome.games.map((g) => g.sourceId), [for (var i = 0; i < 5; i++) 'game000$i']);
        expect(outcome.games.map((g) => g.white).toSet(), containsAll(['Zoë', '日本語']));
        expect(events.whereType<OnlineGameReceived>().map((e) => e.count), [1, 2, 3, 4, 5]);
      });
    }

    test('games are reported as they arrive, before the response ends', () async {
      final gate = Completer<void>();
      site.handler = (req, seen) async {
        req.response.bufferOutput = false;
        req.response.headers.contentType = ContentType.parse('application/x-ndjson');
        req.response.write(ndjson([lichessGame('first000')]));
        await req.response.flush();
        await gate.future;
        req.response.write(ndjson([lichessGame('second00')]));
        await req.response.close();
      };
      final first = Completer<void>();
      final future = client().fetchGames('alice', onEvent: (e) {
        if (e is OnlineGameReceived && e.count == 1) first.complete();
      });
      await first.future.timeout(const Duration(seconds: 5));
      expect(gate.isCompleted, isFalse, reason: 'the first game was seen while the server still held the rest');
      gate.complete();
      final outcome = await future;
      expect(outcome.games.length, 2);
    });

    test('a last line without a newline is still read; CRLF and blank keep-alive lines are ignored', () async {
      final text = '\n\r\n${jsonEncode(lichessGame('aaaaaaa1'))}\r\n\n${jsonEncode(lichessGame('aaaaaaa2'))}';
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(text), 9);
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.map((g) => g.sourceId), ['aaaaaaa1', 'aaaaaaa2']);
      expect(outcome.skipped, 0);
    });

    test('a malformed line is skipped and the rest still arrives', () async {
      final text = '${jsonEncode(lichessGame('aaaaaaa1'))}\n{"id": "broken\n[1,2,3]\n"just a string"\n${jsonEncode(lichessGame('aaaaaaa2'))}\n';
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(text), 5);
      final outcome = await client().fetchGames('alice');
      expect(outcome.ok, isTrue);
      expect(outcome.games.map((g) => g.sourceId), ['aaaaaaa1', 'aaaaaaa2']);
      expect(outcome.skipped, 3);
    });

    test('a game without a usable id or PGN is skipped', () async {
      final text = ndjson([
        lichessGame('aaaaaaa1', omitPgn: true),
        lichessGame('bad id!'),
        lichessGame('aaaaaaa3'),
        lichessGame('aaaaaaa4', moves: ''),
      ]);
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(text), 100);
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.map((g) => g.sourceId), ['aaaaaaa3']);
      expect(outcome.skipped, 3);
    });

    test('variants other than standard / Chess960 / from position are filtered out', () async {
      final text = ndjson([
        lichessGame('aaaaaaa1', variant: 'crazyhouse'),
        lichessGame('aaaaaaa2', variant: 'chess960'),
        lichessGame('aaaaaaa3', variant: 'atomic'),
        lichessGame('aaaaaaa4', variant: 'fromPosition'),
        lichessGame('aaaaaaa5', variant: 'kingOfTheHill'),
      ]);
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(text), 100);
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.map((g) => g.sourceId), ['aaaaaaa2', 'aaaaaaa4']);
      expect(outcome.games.first.chess960, isTrue);
      expect(outcome.skipped, 3);
    });

    test('a line over 1 MB is dropped as it arrives; the games around it survive', () async {
      final huge = '{"id":"hugehuge","pgn":"${'x' * (Limits.maxNdjsonLineBytes + 1000)}"}';
      final text = '${jsonEncode(lichessGame('aaaaaaa1'))}\n$huge\n${jsonEncode(lichessGame('aaaaaaa2'))}\n';
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(text), 64 * 1024);
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.map((g) => g.sourceId), ['aaaaaaa1', 'aaaaaaa2']);
      expect(outcome.skipped, 1);
    });

    test('reading stops after 30 games and the rest of the stream is not needed', () async {
      final text = ndjson([for (var i = 0; i < 45; i++) lichessGame('game${i.toString().padLeft(4, '0')}')]);
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(text), 4096);
      final events = <OnlineEvent>[];
      final outcome = await client().fetchGames('alice', onEvent: events.add);
      expect(outcome.games.length, 30);
      expect(outcome.ok, isTrue);
      expect(events.whereType<OnlineGameReceived>().length, 30);
      expect(outcome.games.first.sourceId, 'game0000');
    });

    test('duplicate ids are listed once', () async {
      final text = ndjson([lichessGame('aaaaaaa1'), lichessGame('aaaaaaa1'), lichessGame('aaaaaaa2')]);
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(text), 100);
      expect((await client().fetchGames('alice')).games.length, 2);
    });

    test('game fields: players, ratings, result, speed, time control, date', () async {
      final text = ndjson([
        lichessGame('aaaaaaa1', speed: 'ultraBullet', winner: 'black', createdAt: 1688238840635),
        lichessGame('aaaaaaa2', winner: null, status: 'draw'),
        lichessGame('aaaaaaa3', winner: null, status: 'started'),
      ]);
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(text), 1000);
      final g = (await client().fetchGames('alice')).games;
      expect(g[0].result, '0-1');
      expect(g[0].speed, OnlineSpeed.bullet);
      expect(g[0].white, 'alice');
      expect(g[0].whiteRating, 1500);
      expect(g[0].timeControl, '180+2');
      expect(g[0].playedAtMs, 1688238840635);
      expect(g[0].source, OnlineSource.lichess);
      expect(g[0].pgn, contains('[White "alice"]'));
      expect(g[1].result, '1/2-1/2');
      expect(g[2].result, '*');
      expect(g[0].sideOf('ALICE'), Side.white);
      expect(g[0].sideOf('Bob'), Side.black);
      expect(g[0].sideOf('carol'), isNull);
    });

    test('the real M0 sample export is read (pgnInJson)', () async {
      final sample = File('../../docs/m0/lichess_sample.ndjson').readAsStringSync();
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode(sample), 777);
      final outcome = await client().fetchGames('player_white');
      expect(outcome.ok, isTrue);
      expect(outcome.games.length, 2);
      final first = outcome.games.firstWhere((g) => g.sourceId == 'Lk80KJQh');
      expect(first.result, '1-0');
      expect(first.speed, OnlineSpeed.blitz);
      expect(first.sideOf('player_white'), Side.white);
      expect(parsePgn(first.pgn), isA<PgnOk>());
      expect(outcome.games.any((g) => g.chess960), isTrue);
    });

    test('a 200 that is not NDJSON at all is badResponse', () async {
      site.handler = (req, seen) => sendChunked(req.response, utf8.encode('<html>Login to continue</html>\n<p>more</p>\n'), 10, type: 'text/html');
      final outcome = await client().fetchGames('alice');
      expect(outcome.error?.kind, OnlineErrorKind.badResponse);
      expect(outcome.games, isEmpty);
    });

    test('an empty result is ok with no games', () async {
      site.handler = (req, seen) => sendChunked(req.response, const [], 10);
      final outcome = await client().fetchGames('alice');
      expect(outcome.ok, isTrue);
      expect(outcome.games, isEmpty);
    });
  });

  group('errors', () {
    test('404 is userNotFound', () async {
      site.handler = (req, seen) => sendStatus(req.response, 404);
      expect((await client().fetchGames('nobody')).error?.kind, OnlineErrorKind.userNotFound);
    });

    test('other statuses are server errors carrying the status', () async {
      for (final status in [400, 401, 403, 500, 502, 503]) {
        site.handler = (req, seen) => sendStatus(req.response, status);
        final error = (await client().fetchGames('alice')).error;
        expect(error?.kind, OnlineErrorKind.server, reason: '$status');
        expect(error?.status, status);
      }
    });

    test('redirects are not followed', () async {
      site.handler = (req, seen) => sendStatus(req.response, 302, headers: {'location': 'http://127.0.0.1:1/elsewhere'});
      final outcome = await client().fetchGames('alice');
      expect(outcome.error?.kind, OnlineErrorKind.server);
      expect(outcome.error?.status, 302);
      expect(site.requests.length, 1);
    });

    test('nothing listening: offline', () async {
      final dead = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final base = Uri.parse('http://127.0.0.1:${dead.port}');
      await dead.close(force: true);
      final outcome = await client(base: base).fetchGames('alice');
      expect(outcome.error?.kind, OnlineErrorKind.offline);
    });

    test('no response headers within the first-byte limit: timeout', () async {
      final hold = Completer<void>();
      site.handler = (req, seen) => hold.future;
      final outcome = await client(timeouts: const OnlineTimeouts(firstByte: Duration(milliseconds: 200))).fetchGames('alice');
      hold.complete();
      expect(outcome.error?.kind, OnlineErrorKind.timeout);
    });

    test('a stream that stalls between chunks: timeout, games so far are kept', () async {
      final hold = Completer<void>();
      site.handler = (req, seen) async {
        req.response.bufferOutput = false;
        req.response.write(ndjson([lichessGame('aaaaaaa1')]));
        await req.response.flush();
        await hold.future;
      };
      final outcome = await client(timeouts: const OnlineTimeouts(firstByte: Duration(milliseconds: 250))).fetchGames('alice');
      hold.complete();
      expect(outcome.error?.kind, OnlineErrorKind.timeout);
      expect(outcome.games.map((g) => g.sourceId), ['aaaaaaa1']);
    });

    test('a stream that never ends hits the total timeout', () async {
      var open = true;
      site.handler = (req, seen) async {
        req.response.bufferOutput = false;
        while (open) {
          req.response.write('\n');
          await req.response.flush();
          await Future<void>.delayed(const Duration(milliseconds: 40));
        }
      };
      final outcome = await client(timeouts: const OnlineTimeouts(firstByte: Duration(seconds: 5), total: Duration(milliseconds: 400))).fetchGames('alice');
      open = false;
      expect(outcome.error?.kind, OnlineErrorKind.timeout);
    });

    test('a response over 16 MB is cut off: tooLarge', () async {
      final line = '{"junk":"${'x' * 1000}"}\n';
      site.handler = (req, seen) async {
        req.response.bufferOutput = false;
        final chunk = utf8.encode(line * 1000); // ~1 MB
        for (var i = 0; i < 20; i++) {
          req.response.add(chunk);
          await req.response.flush();
        }
        await req.response.close();
      };
      final outcome = await client().fetchGames('alice');
      expect(outcome.error?.kind, OnlineErrorKind.tooLarge);
    });
  });

  group('429', () {
    test('429 -> 60 s backoff (reported, cancellable) -> retry -> success', () async {
      var calls = 0;
      site.handler = (req, seen) async {
        if (++calls == 1) return sendStatus(req.response, 429);
        return sendChunked(req.response, utf8.encode(ndjson([lichessGame('aaaaaaa1')])), 100);
      };
      final slept = <Duration>[];
      final events = <OnlineEvent>[];
      final outcome = await client(sleep: (d) async => slept.add(d)).fetchGames('alice', onEvent: events.add);
      expect(outcome.ok, isTrue);
      expect(outcome.games.length, 1);
      expect(site.requests.length, 2);
      expect(slept.fold<Duration>(Duration.zero, (a, b) => a + b), const Duration(seconds: 60));
      final backoffs = events.whereType<OnlineBackoff>().toList();
      expect(backoffs.length, 60);
      expect(backoffs.first.remaining, const Duration(seconds: 60));
      expect(backoffs.first.total, const Duration(seconds: 60));
      expect(backoffs.last.remaining, const Duration(seconds: 1));
      expect(backoffs.first.source, OnlineSource.lichess);
      // The backoff comes before the game.
      expect(events.indexWhere((e) => e is OnlineGameReceived), greaterThan(events.lastIndexWhere((e) => e is OnlineBackoff)));
    });

    test('the default wait is at least a full minute', () {
      expect(Limits.rateLimitWait, greaterThanOrEqualTo(const Duration(seconds: 60)));
    });

    test('Retry-After above 60 s is honoured, up to five minutes', () async {
      var calls = 0;
      final waits = <int>[120, 100000];
      site.handler = (req, seen) async {
        if (calls < 2) return sendStatus(req.response, 429, headers: {'retry-after': '${waits[calls++]}'});
        return sendChunked(req.response, utf8.encode(ndjson([lichessGame('aaaaaaa1')])), 100);
      };
      final totals = <Duration>[];
      await client(sleep: (d) async {}).fetchGames('alice', onEvent: (e) {
        if (e is OnlineBackoff && !totals.contains(e.total)) totals.add(e.total);
      });
      expect(totals, [const Duration(seconds: 120), Limits.maxRateLimitWait]);
    });

    test('Retry-After as an HTTP-date is parsed, capped at five minutes; a past or junk date falls back to the default', () async {
      var calls = 0;
      String future(Duration d) => HttpDate.format(DateTime.now().toUtc().add(d));
      final headers = <String>[future(const Duration(minutes: 3)), future(const Duration(hours: 5)), future(const Duration(hours: -1)), 'soon'];
      site.handler = (req, seen) async {
        if (calls < headers.length) return sendStatus(req.response, 429, headers: {'retry-after': headers[calls++]});
        return sendChunked(req.response, utf8.encode(ndjson([lichessGame('aaaaaaa1')])), 100);
      };
      final totals = <Duration>[];
      await client(sleep: (d) async {}, retries: 4).fetchGames('alice', onEvent: (e) {
        if (e is OnlineBackoff && !totals.contains(e.total)) totals.add(e.total);
      });
      expect(totals.length, 3);
      expect(totals[0].inSeconds, inInclusiveRange(175, 180));
      expect(totals[1], Limits.maxRateLimitWait);
      expect(totals[2], Limits.rateLimitWait);
    });

    test('still 429 after the retries: rateLimited, requests = 1 + retries', () async {
      site.handler = (req, seen) => sendStatus(req.response, 429);
      final slept = <Duration>[];
      final outcome = await client(sleep: (d) async => slept.add(d)).fetchGames('alice');
      expect(outcome.error?.kind, OnlineErrorKind.rateLimited);
      expect(site.requests.length, 1 + Limits.maxRateLimitRetries);
      expect(slept.fold<Duration>(Duration.zero, (a, b) => a + b), const Duration(seconds: 60) * Limits.maxRateLimitRetries);
    });

    test('cancel during the backoff ends the fetch at once, without another request', () async {
      site.handler = (req, seen) => sendStatus(req.response, 429);
      final token = OnlineCancelToken();
      // The real sleep: the cancel must interrupt a minute-long wait.
      final stopwatch = Stopwatch()..start();
      final outcome = await client().fetchGames('alice', cancel: token, onEvent: (e) {
        if (e is OnlineBackoff && e.remaining == e.total) {
          Timer(const Duration(milliseconds: 100), token.cancel);
        }
      });
      expect(outcome.cancelled, isTrue);
      expect(outcome.ok, isFalse);
      expect(outcome.error, isNull);
      expect(site.requests.length, 1);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 10)));
    });

    test('cancelling from inside the first backoff event also stops it', () async {
      site.handler = (req, seen) => sendStatus(req.response, 429);
      final token = OnlineCancelToken();
      final outcome = await client(sleep: (d) async {}).fetchGames('alice', cancel: token, onEvent: (e) {
        if (e is OnlineBackoff) token.cancel();
      });
      expect(outcome.cancelled, isTrue);
      expect(site.requests.length, 1);
    });
  });

  group('cancel', () {
    test('cancelling while the stream is open keeps the games received so far', () async {
      final hold = Completer<void>();
      site.handler = (req, seen) async {
        req.response.bufferOutput = false;
        req.response.write(ndjson([lichessGame('aaaaaaa1')]));
        await req.response.flush();
        await hold.future;
      };
      final token = OnlineCancelToken();
      final outcome = await client().fetchGames('alice', cancel: token, onEvent: (e) {
        if (e is OnlineGameReceived) token.cancel();
      });
      hold.complete();
      expect(outcome.cancelled, isTrue);
      expect(outcome.games.length, 1);
    });

    test('cancelled before starting: no request', () async {
      final token = OnlineCancelToken()..cancel();
      final outcome = await client().fetchGames('alice', cancel: token);
      expect(outcome.cancelled, isTrue);
      expect(site.requests, isEmpty);
    });

    test('cancelling while waiting for the first byte', () async {
      final hold = Completer<void>();
      site.handler = (req, seen) => hold.future;
      final token = OnlineCancelToken();
      final future = client().fetchGames('alice', cancel: token);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      token.cancel();
      final outcome = await future.timeout(const Duration(seconds: 5));
      hold.complete();
      expect(outcome.cancelled, isTrue);
    });
  });
}
