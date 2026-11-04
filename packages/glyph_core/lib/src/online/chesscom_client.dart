import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import '../llm/llm_client.dart' show HttpClientFactory;
import '../util/limits.dart';
import 'online_cache.dart';
import 'online_models.dart';
import 'online_transport.dart';
import 'usernames.dart';

/// Fetches a user's recent games from the chess.com public API:
/// `GET /pub/player/{u}/games/archives` (monthly URLs, ascending), then the
/// months newest-first, **one request at a time**, until [Limits.defaultOnlineGames]
/// games are collected.
///
/// * Only `rules` "chess" and "chess960" are kept (bughouse, crazyhouse,
///   king of the hill ... are counted in [OnlineFetchOutcome.skipped]).
/// * The monthly URLs are rebuilt from the year and month in the archive list;
///   no URL from a response is ever requested.
/// * `ETag` / `If-None-Match`: the archive list and each month are stored in
///   an [OnlineCache] with their `ETag`; a 304 reuses the stored data. A month
///   is stored as our trimmed copy (its newest 50 supported games), never the
///   raw 2+ MB body.
/// * 404 on the player is [OnlineErrorKind.userNotFound]; 410 is
///   [OnlineErrorKind.unavailable]; a month that is 404/410 is skipped; 429
///   waits and retries like lichess; no redirects; 16 MB cap per response;
///   at most [Limits.maxChessComArchiveRequests] months per fetch.
class ChessComClient implements OnlineGamesClient {
  ChessComClient({
    required HttpClientFactory httpClient,
    required String userAgent,
    this.cache,
    Uri? baseUri,
    OnlineTimeouts timeouts = const OnlineTimeouts(),
    Duration rateLimitWait = Limits.rateLimitWait,
    int maxRateLimitRetries = Limits.maxRateLimitRetries,
    Future<void> Function(Duration)? sleep,
  })  : baseUri = baseUri ?? Uri.parse(defaultBaseUrl),
        _transport = OnlineTransport(
          httpClient: httpClient,
          userAgent: userAgent,
          timeouts: timeouts,
          rateLimitWait: rateLimitWait,
          maxRateLimitRetries: maxRateLimitRetries,
          sleep: sleep,
        );

  /// Hard-coded https (SPEC 6). Tests aim [baseUri] at a local server.
  static const defaultBaseUrl = 'https://api.chess.com';

  /// Bodies larger than this are decoded in an isolate.
  static const _isolateThreshold = 256 * 1024;

  final Uri baseUri;
  final OnlineCache? cache;
  final OnlineTransport _transport;

  Uri archivesUri(String username) =>
      baseUri.replace(pathSegments: ['pub', 'player', username.toLowerCase(), 'games', 'archives'], queryParameters: null);

  Uri monthUri(String username, int year, int month) => baseUri.replace(
        pathSegments: ['pub', 'player', username.toLowerCase(), 'games', '$year', month.toString().padLeft(2, '0')],
        queryParameters: null,
      );

  @override
  Future<OnlineFetchOutcome> fetchGames(
    String username, {
    int max = Limits.defaultOnlineGames,
    OnlineCancelToken? cancel,
    void Function(OnlineEvent event)? onEvent,
  }) async {
    final name = username.trim();
    if (!Usernames.isValidChessCom(name)) {
      return const OnlineFetchOutcome(error: OnlineFetchError(OnlineErrorKind.invalidUsername));
    }
    final limit = max.clamp(1, Limits.maxOnlineGames);
    final token = cancel ?? OnlineCancelToken();
    final emit = onEvent ?? (_) {};
    final games = <OnlineGame>[];
    final seen = <String>{};
    var skipped = 0;

    try {
      final months = await _archives(name, token, emit);
      var requests = 0;
      for (final (year, month) in months.reversed) {
        if (games.length >= limit || requests >= Limits.maxChessComArchiveRequests) break;
        requests++;
        final MonthResult result;
        try {
          result = await _month(name, year, month, token, emit);
        } on OnlineFetchException catch (e) {
          // A month that vanished is just empty; anything else stops the walk.
          final kind = e.error.kind;
          if (e.error.status == 404 || e.error.status == 410 || kind == OnlineErrorKind.unavailable) continue;
          rethrow;
        }
        skipped += result.skipped;
        for (final game in result.games) {
          if (games.length >= limit) break;
          if (!seen.add(game.sourceId)) continue;
          games.add(game);
          emit(OnlineGameReceived(game, games.length));
        }
      }
    } on OnlineCancelled {
      return OnlineFetchOutcome(games: games, cancelled: true, skipped: skipped);
    } on OnlineFetchException catch (e) {
      return OnlineFetchOutcome(games: games, error: e.error, skipped: skipped);
    }
    return OnlineFetchOutcome(games: games, skipped: skipped);
  }

  static final _archivePattern = RegExp(r'^https://api\.chess\.com/pub/player/[^/]+/games/(\d{4})/(\d{2})$');

  /// The (year, month) pairs of the player's archives, ascending.
  Future<List<(int, int)>> _archives(String name, OnlineCancelToken token, void Function(OnlineEvent) emit) async {
    final uri = archivesUri(name);
    final key = uri.toString();
    final cached = await _cacheGet(key);
    var useCached = false;
    String? etag;
    final body = await _transport.get<List<int>?>(
      uri,
      source: OnlineSource.chesscom,
      token: token,
      onEvent: emit,
      headers: {'Accept': 'application/json', if (cached != null) 'If-None-Match': cached.etag},
      handle: (response) async {
        final status = response.statusCode;
        if (status == 304 && cached != null) {
          useCached = true;
          return null;
        }
        if (status < 200 || status >= 300) throw OnlineFetchException(OnlineTransport.errorForStatus(status));
        etag = response.headers['etag'];
        return _transport.readAll(response, token);
      },
    );
    final text = useCached ? cached!.body : utf8.decode(body!, allowMalformed: true);
    final List<(int, int)> months;
    try {
      months = _parseArchives(text);
    } on FormatException {
      // A damaged cache entry: fetch again without the conditional header.
      if (useCached) return _archivesFresh(name, token, emit);
      throw const OnlineFetchException(OnlineFetchError(OnlineErrorKind.badResponse));
    }
    final newTag = etag;
    if (!useCached && newTag != null && newTag.isNotEmpty && utf8.encode(text).length <= Limits.maxOnlineCacheBodyBytes) await _cachePut(key, CachedResponse(newTag, text));
    return months;
  }

  Future<List<(int, int)>> _archivesFresh(String name, OnlineCancelToken token, void Function(OnlineEvent) emit) async {
    final bytes = await _transport.get<List<int>>(
      archivesUri(name),
      source: OnlineSource.chesscom,
      token: token,
      onEvent: emit,
      headers: const {'Accept': 'application/json'},
      handle: (response) async {
        final status = response.statusCode;
        if (status < 200 || status >= 300) throw OnlineFetchException(OnlineTransport.errorForStatus(status));
        return _transport.readAll(response, token);
      },
    );
    try {
      return _parseArchives(utf8.decode(bytes, allowMalformed: true));
    } on FormatException {
      throw const OnlineFetchException(OnlineFetchError(OnlineErrorKind.badResponse));
    }
  }

  static List<(int, int)> _parseArchives(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?> || decoded['archives'] is! List) throw const FormatException('no archives');
    final out = <(int, int)>[];
    for (final entry in decoded['archives'] as List) {
      if (entry is! String) continue;
      final m = _archivePattern.firstMatch(entry);
      if (m == null) continue;
      final year = int.parse(m.group(1)!);
      final month = int.parse(m.group(2)!);
      if (month < 1 || month > 12) continue;
      out.add((year, month));
    }
    out.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
    return out;
  }

  /// One month's supported games (newest first), via the cache when the
  /// server says 304.
  Future<MonthResult> _month(
    String name,
    int year,
    int month,
    OnlineCancelToken token,
    void Function(OnlineEvent) emit,
  ) async {
    final uri = monthUri(name, year, month);
    final key = uri.toString();
    var cached = await _cacheGet(key);
    final stored = cached == null ? null : _decodeStoredMonth(cached.body);
    if (stored == null) cached = null; // unusable entry: do not send its ETag
    final result = await _transport.get<MonthResult>(
      uri,
      source: OnlineSource.chesscom,
      token: token,
      onEvent: emit,
      headers: {'Accept': 'application/json', if (cached != null) 'If-None-Match': cached.etag},
      handle: (response) async {
        final status = response.statusCode;
        if (status == 304 && stored != null) return stored;
        if (status < 200 || status >= 300) throw OnlineFetchException(OnlineTransport.errorForStatus(status));
        final bytes = await _transport.readAll(response, token);
        if (token.isCancelled) throw const OnlineCancelled();
        final MonthResult parsed;
        try {
          parsed = await _parseMonth(bytes);
        } on FormatException {
          throw const OnlineFetchException(OnlineFetchError(OnlineErrorKind.badResponse));
        }
        final etag = response.headers['etag'];
        if (etag != null && etag.isNotEmpty) {
          final body = _encodeStoredMonth(parsed);
          if (utf8.encode(body).length <= Limits.maxOnlineCacheBodyBytes) {
            await _cachePut(key, CachedResponse(etag, body));
          }
        }
        return parsed;
      },
    );
    return result;
  }

  Future<MonthResult> _parseMonth(Uint8List bytes) async {
    if (bytes.length <= _isolateThreshold) return parseChessComMonth(bytes);
    return Isolate.run(() => parseChessComMonth(bytes));
  }

  static String _encodeStoredMonth(MonthResult m) => jsonEncode({
        'v': 1,
        'skipped': m.skipped,
        'games': [for (final g in m.games) g.toJson()],
      });

  static MonthResult? _decodeStoredMonth(String body) {
    try {
      final j = jsonDecode(body);
      if (j is! Map<String, Object?> || j['v'] != 1 || j['games'] is! List || j['skipped'] is! int) return null;
      return MonthResult([
        for (final g in j['games'] as List) OnlineGame.fromJson((g as Map).cast<String, Object?>()),
      ], j['skipped'] as int);
    } on Object {
      return null;
    }
  }

  Future<CachedResponse?> _cacheGet(String key) async {
    try {
      return await cache?.get(key);
    } on Object {
      return null;
    }
  }

  Future<void> _cachePut(String key, CachedResponse value) async {
    try {
      await cache?.put(key, value);
    } on Object {
      // A cache that cannot write only costs the next request its 304.
    }
  }

  /// Turns one chess.com game object into an [OnlineGame]; null for another
  /// variant than chess / Chess960 or an unusable entry.
  static OnlineGame? gameFromJson(Map<String, Object?> g) {
    final rules = g['rules'];
    if (rules != 'chess' && rules != 'chess960') return null;
    final url = g['url'];
    final pgn = g['pgn'];
    if (url is! String || !_gameUrl.hasMatch(url) || pgn is! String || pgn.trim().isEmpty) return null;
    final white = g['white'];
    final black = g['black'];
    if (white is! Map<String, Object?> || black is! Map<String, Object?>) return null;
    final whiteResult = white['result'];
    final blackResult = black['result'];
    final result = whiteResult == 'win'
        ? '1-0'
        : blackResult == 'win'
            ? '0-1'
            : (_drawResults.contains(whiteResult) && _drawResults.contains(blackResult))
                ? '1/2-1/2'
                : '*';
    final endTime = g['end_time'];
    final timeControl = g['time_control'];
    return OnlineGame(
      source: OnlineSource.chesscom,
      sourceId: url,
      pgn: pgn,
      white: white['username'] is String ? white['username'] as String : null,
      black: black['username'] is String ? black['username'] as String : null,
      whiteRating: white['rating'] is int ? white['rating'] as int : null,
      blackRating: black['rating'] is int ? black['rating'] as int : null,
      speed: OnlineSpeed.parse(g['time_class'] as String?) ?? OnlineSpeed.rapid,
      timeControl: timeControl is String ? timeControl : null,
      result: result,
      playedAtMs: endTime is int ? endTime * 1000 : null,
      chess960: rules == 'chess960',
      rated: g['rated'] is bool ? g['rated'] as bool : null,
    );
  }

  static final _gameUrl = RegExp(r'^https://www\.chess\.com/[A-Za-z0-9/_.-]{1,100}$');

  static const _drawResults = {'agreed', 'repetition', 'stalemate', 'insufficient', '50move', 'timevsinsufficient'};
}

/// One month after filtering: the supported games, newest first (at most
/// [Limits.maxOnlineGames]), and how many entries were left out.
class MonthResult {
  const MonthResult(this.games, this.skipped);

  final List<OnlineGame> games;
  final int skipped;
}

/// Parses a chess.com monthly archive body. Top level so it can run in an
/// isolate. Throws [FormatException] when the body is not an archive.
MonthResult parseChessComMonth(Uint8List bytes) {
  final decoded = jsonDecode(utf8.decode(bytes, allowMalformed: true));
  if (decoded is! Map<String, Object?> || decoded['games'] is! List) throw const FormatException('no games');
  var skipped = 0;
  final games = <OnlineGame>[];
  final seen = <String>{};
  for (final entry in decoded['games'] as List) {
    if (entry is! Map<String, Object?>) {
      skipped++;
      continue;
    }
    final game = ChessComClient.gameFromJson(entry);
    if (game == null) {
      skipped++;
      continue;
    }
    if (seen.add(game.sourceId)) games.add(game);
  }
  games.sort((a, b) => (b.playedAtMs ?? 0).compareTo(a.playedAtMs ?? 0));
  return MonthResult(games.length > Limits.maxOnlineGames ? games.sublist(0, Limits.maxOnlineGames) : games, skipped);
}
