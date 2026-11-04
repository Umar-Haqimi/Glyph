import 'dart:async';
import 'dart:convert';
import 'dart:io' show ContentType;

import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import 'fake_site.dart';

void main() {
  late FakeSite site;
  setUp(() async => site = await FakeSite.start());
  tearDown(() => site.close());

  ChessComClient client({OnlineCache? cache, OnlineTimeouts timeouts = const OnlineTimeouts(), Future<void> Function(Duration)? sleep, int retries = Limits.maxRateLimitRetries}) =>
      ChessComClient(
        httpClient: plainClient,
        userAgent: userAgent,
        cache: cache,
        baseUri: site.baseUri,
        timeouts: timeouts,
        sleep: sleep,
        maxRateLimitRetries: retries,
      );

  /// [perMonth] games per month, ids `m<year><month>_<i>`, newest game last
  /// (the API lists a month oldest first), plus one bughouse game each.
  Map<(int, int), List<Map<String, Object?>>> sampleMonths(List<(int, int)> keys, {int perMonth = 12, bool variants = true}) => {
        for (final k in keys)
          k: [
            for (var i = 0; i < perMonth; i++)
              chessComGame('${k.$1}${k.$2}_$i', endTime: 1700000000 + (k.$1 * 12 + k.$2) * 100000 + i * 60),
            if (variants) chessComGame('${k.$1}${k.$2}_bug', rules: 'bughouse', endTime: 1700000000 + (k.$1 * 12 + k.$2) * 100000 + 5000),
            if (variants) chessComGame('${k.$1}${k.$2}_cz', rules: 'crazyhouse', endTime: 1700000000 + (k.$1 * 12 + k.$2) * 100000 + 5001),
          ],
      };

  group('archive walk', () {
    test('newest month first, until 30 games; variants filtered; one request at a time', () async {
      final fake = FakeChessCom(site, 'alice', sampleMonths([(2026, 7), (2026, 8), (2026, 9), (2026, 10)]))..install();
      var concurrent = 0;
      var maxConcurrent = 0;
      final inner = site.handler!;
      site.handler = (req, seen) async {
        concurrent++;
        if (concurrent > maxConcurrent) maxConcurrent = concurrent;
        try {
          await inner(req, seen);
        } finally {
          concurrent--;
        }
      };
      final events = <OnlineEvent>[];
      final outcome = await client().fetchGames('Alice', onEvent: events.add);
      expect(outcome.ok, isTrue);
      expect(outcome.games.length, 30);
      expect(site.requests.map((r) => r.path), [
        '/pub/player/alice/games/archives',
        '/pub/player/alice/games/2026/10',
        '/pub/player/alice/games/2026/09',
        '/pub/player/alice/games/2026/08',
      ], reason: 'username lower-cased; 12 + 12 + 12 >= 30 so 2026/07 is never requested');
      expect(maxConcurrent, 1);
      // Newest first overall.
      final times = outcome.games.map((g) => g.playedAtMs!).toList();
      expect([...times]..sort((a, b) => b.compareTo(a)), times);
      expect(outcome.games.first.sourceId, 'https://www.chess.com/game/live/202610_11');
      expect(outcome.games.any((g) => g.sourceId.contains('_bug') || g.sourceId.contains('_cz')), isFalse);
      expect(outcome.skipped, 6, reason: '2 variants in each of the 3 months read');
      expect(events.whereType<OnlineGameReceived>().length, 30);
      expect(fake.served['/pub/player/alice/games/2026/07'], isNull);
    });

    test('stops at exactly 30 even in the middle of a month', () async {
      FakeChessCom(site, 'alice', sampleMonths([(2026, 9), (2026, 10)], perMonth: 20, variants: false)).install();
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.length, 30);
      expect(outcome.games.last.sourceId, 'https://www.chess.com/game/live/20269_10');
    });

    test('fewer than 30 in total: every archive is read, no error', () async {
      FakeChessCom(site, 'alice', sampleMonths([(2026, 9), (2026, 10)], perMonth: 4)).install();
      final outcome = await client().fetchGames('alice');
      expect(outcome.ok, isTrue);
      expect(outcome.games.length, 8);
    });

    test('a smaller max is honoured', () async {
      FakeChessCom(site, 'alice', sampleMonths([(2026, 9), (2026, 10)], perMonth: 20)).install();
      expect((await client().fetchGames('alice', max: 5)).games.length, 5);
      expect(site.requests.length, 2, reason: 'archives + one month');
    });

    test('only chess and chess960 are kept; chess960 is flagged; daily and result mapping', () async {
      FakeChessCom(site, 'alice', {
        (2026, 10): [
          chessComGame('a1', rules: 'chess960', timeClass: 'daily', endTime: 1790000100),
          chessComGame('a2', rules: 'kingofthehill'),
          chessComGame('a3', rules: 'threecheck'),
          chessComGame('a4', rules: 'oddschess'),
          chessComGame('a5', whiteResult: 'agreed', blackResult: 'agreed', endTime: 1790000200),
          chessComGame('a6', whiteResult: 'checkmated', blackResult: 'win', endTime: 1790000300),
          chessComGame('a7', whiteResult: 'abandoned', blackResult: 'abandoned', endTime: 1790000400),
        ],
      }).install();
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.map((g) => g.sourceId.split('/').last), ['a7', 'a6', 'a5', 'a1']);
      expect(outcome.skipped, 3);
      final byId = {for (final g in outcome.games) g.sourceId.split('/').last: g};
      expect(byId['a1']!.chess960, isTrue);
      expect(byId['a1']!.speed, OnlineSpeed.daily);
      expect(byId['a5']!.result, '1/2-1/2');
      expect(byId['a6']!.result, '0-1');
      expect(byId['a7']!.result, '*');
      expect(byId['a6']!.playedAtMs, 1790000300 * 1000);
      expect(byId['a1']!.sideOf('ALICE'), Side.white);
    });

    test('malformed entries and games without a chess.com URL or PGN are skipped', () async {
      FakeChessCom(site, 'alice', {
        (2026, 10): [
          chessComGame('ok1'),
          {...chessComGame('x'), 'url': 'https://evil.example/game/1'},
          {...chessComGame('y'), 'pgn': ''},
          {...chessComGame('z'), 'white': 'not a map'},
        ],
      }).install();
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.length, 1);
      expect(outcome.skipped, 3);
    });

    test('archive entries that are not chess.com monthly URLs are ignored; no URL from a response is requested', () async {
      site.handler = (req, seen) async {
        if (seen.path.endsWith('/archives')) {
          return sendJson(req.response, {
            'archives': [
              'https://evil.example/pub/player/alice/games/2026/09',
              'http://api.chess.com/pub/player/alice/games/2026/08',
              'https://api.chess.com/pub/player/alice/games/2026/13',
              'not a url',
              42,
              archiveUrl('alice', 2026, 10),
            ],
          });
        }
        return sendJson(req.response, {'games': [chessComGame('only')]});
      };
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.length, 1);
      expect(site.requests.map((r) => r.path), ['/pub/player/alice/games/archives', '/pub/player/alice/games/2026/10']);
    });

    test('at most 36 monthly archives are requested', () async {
      final keys = [for (var y = 2020; y < 2024; y++) for (var m = 1; m <= 12; m++) (y, m)]; // 48 months
      FakeChessCom(site, 'alice', sampleMonths(keys, perMonth: 1, variants: false)).install();
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.length, 30);
      expect(site.requests.length, 1 + 30);

      site.requests.clear();
      FakeChessCom(site, 'alice', {for (final k in keys) k: <Map<String, Object?>>[]}).install();
      await client().fetchGames('alice');
      expect(site.requests.length, 1 + Limits.maxChessComArchiveRequests);
    });

    test('request headers: generic User-Agent, JSON, no credentials', () async {
      FakeChessCom(site, 'alice', sampleMonths([(2026, 10)], perMonth: 1)).install();
      await client().fetchGames('alice');
      for (final r in site.requests) {
        expect(r.headers['user-agent'], userAgent);
        expect(r.headers['user-agent'], isNot(contains('@')));
        expect(r.headers['accept'], 'application/json');
        expect(r.headers['authorization'], isNull);
        expect(r.headers['cookie'], isNull);
      }
    });

    test('the default host is https api.chess.com', () {
      expect(ChessComClient.defaultBaseUrl, 'https://api.chess.com');
      expect(ChessComClient(httpClient: plainClient, userAgent: userAgent).baseUri.scheme, 'https');
    });

    test('an invalid username never reaches the network', () async {
      for (final bad in ['', 'ab', 'a b', '../x', 'x' * 26, 'a/b', 'a?b']) {
        expect((await client().fetchGames(bad)).error?.kind, OnlineErrorKind.invalidUsername, reason: bad);
      }
      expect(site.requests, isEmpty);
    });

    test('a month over 256 KB is decoded off the UI isolate and still correct', () async {
      FakeChessCom(site, 'alice', {
        (2026, 10): [for (var i = 0; i < 300; i++) chessComGame('big$i', endTime: 1790000000 + i, pgnPadding: 1500)],
      }).install();
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.length, 30);
      expect(outcome.games.first.sourceId, 'https://www.chess.com/game/live/big299');
    });
  });

  group('ETag / If-None-Match', () {
    test('the second fetch sends the stored ETags, gets 304s, and returns the same games', () async {
      final fake = FakeChessCom(site, 'alice', sampleMonths([(2026, 9), (2026, 10)], perMonth: 20, variants: true))..install();
      final cache = InMemoryOnlineCache();
      final first = await client(cache: cache).fetchGames('alice');
      expect(first.games.length, 30);
      expect(site.requests.every((r) => r.headers['if-none-match'] == null), isTrue, reason: 'nothing stored yet');
      expect(cache.entries.keys.length, 3, reason: 'archive list + the two months read');
      expect(cache.entries.values.every((e) => e.etag.startsWith('W/"')), isTrue);

      site.requests.clear();
      final second = await client(cache: cache).fetchGames('alice');
      expect(second.ok, isTrue);
      expect(second.games.map((g) => g.sourceId), first.games.map((g) => g.sourceId));
      expect(second.games.first.pgn, first.games.first.pgn);
      expect(second.skipped, first.skipped);
      expect(site.requests.map((r) => r.headers['if-none-match']), [
        'W/"archives-1"',
        fake.etags['/pub/player/alice/games/2026/10'],
        fake.etags['/pub/player/alice/games/2026/09'],
      ], reason: 'the weak ETag is sent back exactly as received');
      expect(fake.notModified.length, 3);
      expect(fake.served['/pub/player/alice/games/2026/10'], 1, reason: 'the month body was transferred only once');
    });

    test('an archive list over the cache cap is used but not stored', () async {
      FakeChessCom(site, 'alice', sampleMonths([(2026, 10)], perMonth: 2)).install();
      final inner = site.handler!;
      site.handler = (req, seen) {
        if (seen.path.endsWith('/games/archives')) {
          return sendJson(req.response, {
            'archives': [archiveUrl('alice', 2026, 10)],
            'padding': 'x' * (Limits.maxOnlineCacheBodyBytes + 10),
          }, headers: {'etag': 'W/"big"'});
        }
        return inner(req, seen);
      };
      final cache = InMemoryOnlineCache();
      final outcome = await client(cache: cache).fetchGames('alice');
      expect(outcome.games, isNotEmpty);
      expect(cache.entries.keys.any((k) => k.endsWith('/games/archives')), isFalse);
    });

    test('a changed month is fetched again and the cache is replaced', () async {
      final fake = FakeChessCom(site, 'alice', sampleMonths([(2026, 10)], perMonth: 3, variants: false))..install();
      final cache = InMemoryOnlineCache();
      await client(cache: cache).fetchGames('alice');
      final oldTag = fake.etags['/pub/player/alice/games/2026/10']!;
      fake.etags['/pub/player/alice/games/2026/10'] = 'W/"changed"';
      fake.months[(2026, 10)]!.add(chessComGame('new', endTime: 9000000000));
      final outcome = await client(cache: cache).fetchGames('alice');
      expect(outcome.games.length, 4);
      expect(outcome.games.first.sourceId, endsWith('/new'));
      expect(cache.entries['${site.baseUri}/pub/player/alice/games/2026/10']!.etag, 'W/"changed"');
      expect(oldTag, isNot('W/"changed"'));
    });

    test('a new month in the archive list is picked up', () async {
      final fake = FakeChessCom(site, 'alice', sampleMonths([(2026, 9)], perMonth: 3, variants: false))..install();
      final cache = InMemoryOnlineCache();
      await client(cache: cache).fetchGames('alice');
      fake.months[(2026, 10)] = [chessComGame('oct', endTime: 9000000000)];
      fake.archivesEtag = 'W/"archives-2"';
      final outcome = await client(cache: cache).fetchGames('alice');
      expect(outcome.games.first.sourceId, endsWith('/oct'));
      expect(outcome.games.length, 4);
    });

    test('a damaged cache entry is ignored: no If-None-Match, fresh data', () async {
      FakeChessCom(site, 'alice', sampleMonths([(2026, 10)], perMonth: 3, variants: false)).install();
      final cache = InMemoryOnlineCache();
      cache.entries['${site.baseUri}/pub/player/alice/games/2026/10'] = const CachedResponse('W/"x"', '{not json');
      cache.entries['${site.baseUri}/pub/player/alice/games/archives'] = const CachedResponse('W/"archives-1"', '{"archives": 5}');
      final outcome = await client(cache: cache).fetchGames('alice');
      expect(outcome.ok, isTrue);
      expect(outcome.games.length, 3);
      final monthRequest = site.requests.firstWhere((r) => r.path.endsWith('/2026/10'));
      expect(monthRequest.headers['if-none-match'], isNull);
    });

    test('a failing cache never breaks the fetch', () async {
      FakeChessCom(site, 'alice', sampleMonths([(2026, 10)], perMonth: 3, variants: false)).install();
      final outcome = await client(cache: _BrokenCache()).fetchGames('alice');
      expect(outcome.ok, isTrue);
      expect(outcome.games.length, 3);
    });

    test('without an ETag in the response nothing is stored', () async {
      site.handler = (req, seen) => seen.path.endsWith('/archives')
          ? sendJson(req.response, {'archives': [archiveUrl('alice', 2026, 10)]})
          : sendJson(req.response, {'games': [chessComGame('g')]});
      final cache = InMemoryOnlineCache();
      await client(cache: cache).fetchGames('alice');
      expect(cache.entries, isEmpty);
    });
  });

  group('errors', () {
    test('404 for the player is userNotFound', () async {
      site.handler = (req, seen) => sendJson(req.response, {'code': 0, 'message': 'User "x" not found.'}, status: 404);
      expect((await client().fetchGames('nobody1')).error?.kind, OnlineErrorKind.userNotFound);
    });

    test('410 for the player is unavailable', () async {
      site.handler = (req, seen) => sendStatus(req.response, 410);
      expect((await client().fetchGames('gone123')).error?.kind, OnlineErrorKind.unavailable);
    });

    test('a month that is 404 or 410 is skipped, the walk goes on', () async {
      site.handler = (req, seen) async {
        if (seen.path.endsWith('/archives')) {
          return sendJson(req.response, {
            'archives': [archiveUrl('alice', 2026, 8), archiveUrl('alice', 2026, 9), archiveUrl('alice', 2026, 10)],
          });
        }
        if (seen.path.endsWith('/10')) return sendStatus(req.response, 404);
        if (seen.path.endsWith('/09')) return sendStatus(req.response, 410);
        return sendJson(req.response, {'games': [chessComGame('aug')]});
      };
      final outcome = await client().fetchGames('alice');
      expect(outcome.ok, isTrue);
      expect(outcome.games.map((g) => g.sourceId), ['https://www.chess.com/game/live/aug']);
    });

    test('a failing later month keeps the games read so far and reports the error', () async {
      site.handler = (req, seen) async {
        if (seen.path.endsWith('/archives')) {
          return sendJson(req.response, {'archives': [archiveUrl('alice', 2026, 9), archiveUrl('alice', 2026, 10)]});
        }
        if (seen.path.endsWith('/09')) return sendStatus(req.response, 500);
        return sendJson(req.response, {'games': [chessComGame('oct')]});
      };
      final outcome = await client().fetchGames('alice');
      expect(outcome.games.length, 1);
      expect(outcome.error?.kind, OnlineErrorKind.server);
      expect(outcome.error?.status, 500);
    });

    test('an archive list that is not JSON is badResponse; redirects are not followed', () async {
      site.handler = (req, seen) => sendJson(req.response, 'nope');
      expect((await client().fetchGames('alice')).error?.kind, OnlineErrorKind.badResponse);
      site.handler = (req, seen) => sendStatus(req.response, 301, headers: {'location': 'http://127.0.0.1:1/'});
      final outcome = await client().fetchGames('alice');
      expect(outcome.error?.kind, OnlineErrorKind.server);
      expect(outcome.error?.status, 301);
    });

    test('a month body over 16 MB is tooLarge', () async {
      site.handler = (req, seen) async {
        if (seen.path.endsWith('/archives')) return sendJson(req.response, {'archives': [archiveUrl('alice', 2026, 10)]});
        req.response.bufferOutput = false;
        req.response.headers.contentType = ContentType.json;
        final chunk = utf8.encode('x' * (1024 * 1024));
        req.response.add(utf8.encode('{"games":["'));
        for (var i = 0; i < 18; i++) {
          req.response.add(chunk);
          await req.response.flush();
        }
        await req.response.close();
      };
      final outcome = await client().fetchGames('alice');
      expect(outcome.error?.kind, OnlineErrorKind.tooLarge);
    });

    test('nothing listening: offline; no answer: timeout', () async {
      final hold = Completer<void>();
      site.handler = (req, seen) => hold.future;
      final outcome = await client(timeouts: const OnlineTimeouts(firstByte: Duration(milliseconds: 200))).fetchGames('alice');
      hold.complete();
      expect(outcome.error?.kind, OnlineErrorKind.timeout);
    });
  });

  group('429', () {
    test('429 -> backoff -> retry -> success, on the archive list and on a month', () async {
      final fake = FakeChessCom(site, 'alice', sampleMonths([(2026, 10)], perMonth: 2, variants: false))..install();
      final inner = site.handler!;
      final limited = <String>{};
      site.handler = (req, seen) async {
        if (limited.add(seen.path)) return sendStatus(req.response, 429);
        return inner(req, seen);
      };
      final slept = <Duration>[];
      final events = <OnlineEvent>[];
      final outcome = await client(sleep: (d) async => slept.add(d)).fetchGames('alice', onEvent: events.add);
      expect(outcome.ok, isTrue);
      expect(outcome.games.length, 2);
      expect(slept.fold<Duration>(Duration.zero, (a, b) => a + b), const Duration(seconds: 120));
      expect(events.whereType<OnlineBackoff>().first.source, OnlineSource.chesscom);
      expect(fake.served.length, 2);
    });

    test('permanent 429 -> rateLimited; cancel during the wait stops without another request', () async {
      site.handler = (req, seen) => sendStatus(req.response, 429);
      final outcome = await client(sleep: (d) async {}).fetchGames('alice');
      expect(outcome.error?.kind, OnlineErrorKind.rateLimited);
      expect(site.requests.length, 1 + Limits.maxRateLimitRetries);

      site.requests.clear();
      final token = OnlineCancelToken();
      final cancelled = await client().fetchGames('alice', cancel: token, onEvent: (e) {
        if (e is OnlineBackoff) Timer(const Duration(milliseconds: 50), token.cancel);
      });
      expect(cancelled.cancelled, isTrue);
      expect(site.requests.length, 1);
    });
  });

  group('cancel', () {
    test('cancelled between months: games so far are kept', () async {
      FakeChessCom(site, 'alice', sampleMonths([(2026, 9), (2026, 10)], perMonth: 5, variants: false)).install();
      final token = OnlineCancelToken();
      final outcome = await client().fetchGames('alice', cancel: token, onEvent: (e) {
        if (e is OnlineGameReceived && e.count == 5) token.cancel();
      });
      expect(outcome.cancelled, isTrue);
      expect(outcome.games.length, 5);
      expect(site.requests.length, 2, reason: 'the older month was not requested');
    });
  });

  test('OnlineGame JSON round trip', () {
    final g = ChessComClient.gameFromJson(chessComGame('rt', rules: 'chess960', timeClass: 'daily'))!;
    final back = OnlineGame.fromJson(jsonDecode(jsonEncode(g.toJson())) as Map<String, Object?>);
    expect(back.toJson(), g.toJson());
    expect(() => OnlineGame.fromJson({'source': 'lichess'}), throwsFormatException);
  });
}

class _BrokenCache implements OnlineCache {
  @override
  Future<CachedResponse?> get(String key) async => throw StateError('disk full');

  @override
  Future<void> put(String key, CachedResponse response) async => throw StateError('disk full');

  @override
  Future<void> clear() async => throw StateError('disk full');
}
