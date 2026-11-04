import 'dart:convert';

import '../llm/llm_client.dart' show HttpClientFactory;
import '../util/limits.dart';
import 'ndjson.dart';
import 'online_models.dart';
import 'online_transport.dart';
import 'usernames.dart';

/// Fetches a user's recent games from the public lichess API
/// (`GET /api/games/user/{username}`, NDJSON, no authentication).
///
/// * Request: `max`, `pgnInJson`, `clocks`, `evals`, `opening`, `sort=dateDesc`,
///   `perfType` limited to the speeds and Chess960 that Glyph can review
///   (other variants are filtered again client-side).
/// * The response is **streamed**: lines are split on bytes, each game is
///   reported as soon as its line is complete, and reading stops after
///   [maxGames]. A malformed line is skipped, an over-long one (1 MB) is
///   dropped, the whole response is capped at 16 MB.
/// * A 429 waits at least 60 s (cancellable, reported as [OnlineBackoff]) and
///   retries; a 404 is [OnlineErrorKind.userNotFound].
class LichessClient implements OnlineGamesClient {
  LichessClient({
    required HttpClientFactory httpClient,
    required String userAgent,
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
  static const defaultBaseUrl = 'https://lichess.org';

  /// Speeds Glyph can review: everything but the variants.
  static const perfTypes = ['ultraBullet', 'bullet', 'blitz', 'rapid', 'classical', 'correspondence', 'chess960'];

  final Uri baseUri;
  final OnlineTransport _transport;

  Uri requestUri(String username, int max) => baseUri.replace(
        pathSegments: ['api', 'games', 'user', username],
        queryParameters: {
          'max': '$max',
          'pgnInJson': 'true',
          'clocks': 'true',
          'evals': 'true',
          'opening': 'true',
          'sort': 'dateDesc',
          'perfType': perfTypes.join(','),
        },
      );

  /// Fetches up to [max] games (at most [Limits.maxOnlineGames]), newest
  /// first. Never throws; the outcome carries games, error and cancellation.
  @override
  Future<OnlineFetchOutcome> fetchGames(
    String username, {
    int max = Limits.defaultOnlineGames,
    OnlineCancelToken? cancel,
    void Function(OnlineEvent event)? onEvent,
  }) async {
    final name = username.trim();
    if (!Usernames.isValidLichess(name)) {
      return const OnlineFetchOutcome(error: OnlineFetchError(OnlineErrorKind.invalidUsername));
    }
    final limit = max.clamp(1, Limits.maxOnlineGames);
    final token = cancel ?? OnlineCancelToken();
    final emit = onEvent ?? (_) {};
    final games = <OnlineGame>[];
    final seen = <String>{};
    var unsupported = 0;
    var malformed = 0;

    void handleLine(String line) {
      if (games.length >= limit) return;
      final Object? decoded;
      try {
        decoded = jsonDecode(line);
      } on FormatException {
        malformed++;
        return;
      }
      if (decoded is! Map<String, Object?>) {
        malformed++;
        return;
      }
      final parsed = _parseGame(decoded);
      switch (parsed) {
        case _Unsupported():
          unsupported++;
        case _Malformed():
          malformed++;
        case _Parsed(:final game):
          if (!seen.add(game.sourceId)) return;
          games.add(game);
          emit(OnlineGameReceived(game, games.length));
      }
    }

    try {
      await _transport.get<void>(
        requestUri(name, limit),
        source: OnlineSource.lichess,
        token: token,
        onEvent: emit,
        headers: const {'Accept': 'application/x-ndjson'},
        handle: (response) async {
          final status = response.statusCode;
          if (status < 200 || status >= 300) throw OnlineFetchException(OnlineTransport.errorForStatus(status));
          final splitter = NdjsonLineSplitter(maxLineBytes: Limits.maxNdjsonLineBytes);
          var reachedLimit = false;
          await _transport.readChunks(response, token, (chunk) {
            for (final line in splitter.add(chunk)) {
              handleLine(line);
            }
            reachedLimit = games.length >= limit;
            return reachedLimit;
          });
          if (!reachedLimit && !token.isCancelled) {
            for (final line in splitter.close()) {
              handleLine(line);
            }
          }
          malformed += splitter.oversized;
        },
      );
    } on OnlineCancelled {
      return OnlineFetchOutcome(games: games, cancelled: true, skipped: unsupported + malformed);
    } on OnlineFetchException catch (e) {
      return OnlineFetchOutcome(games: games, error: e.error, skipped: unsupported + malformed);
    }
    // A 200 that was not NDJSON at all (a captive portal, a proxy page).
    if (games.isEmpty && malformed > 0 && unsupported == 0) {
      return OnlineFetchOutcome(skipped: malformed, error: const OnlineFetchError(OnlineErrorKind.badResponse));
    }
    return OnlineFetchOutcome(games: games, skipped: unsupported + malformed);
  }

  /// Reads one game object of the export.
  static _Result _parseGame(Map<String, Object?> j) {
    final id = j['id'];
    final pgn = j['pgn'];
    final moves = j['moves'];
    if (id is! String || !_idPattern.hasMatch(id) || pgn is! String || pgn.trim().isEmpty) return const _Malformed();
    final variant = j['variant'];
    if (variant != 'standard' && variant != 'chess960' && variant != 'fromPosition') return const _Unsupported();
    // Aborted / not started games have no moves.
    if (moves is! String || moves.trim().isEmpty) return const _Unsupported();

    final players = j['players'];
    Map<String, Object?>? side(String key) {
      if (players is! Map<String, Object?>) return null;
      final p = players[key];
      return p is Map<String, Object?> ? p : null;
    }

    String? name(Map<String, Object?>? p) {
      final user = p?['user'];
      if (user is Map<String, Object?> && user['name'] is String) return user['name'] as String;
      final level = p?['aiLevel'];
      return level is int ? 'Stockfish level $level' : null;
    }

    int? rating(Map<String, Object?>? p) => p?['rating'] is int ? p!['rating'] as int : null;

    final white = side('white');
    final black = side('black');
    final winner = j['winner'];
    final status = j['status'];
    final result = winner == 'white'
        ? '1-0'
        : winner == 'black'
            ? '0-1'
            : (status == 'draw' || status == 'stalemate')
                ? '1/2-1/2'
                : '*';
    String? timeControl;
    final clock = j['clock'];
    if (clock is Map<String, Object?> && clock['initial'] is int && clock['increment'] is int) {
      timeControl = '${clock['initial']}+${clock['increment']}';
    }
    return _Parsed(OnlineGame(
      source: OnlineSource.lichess,
      sourceId: id,
      pgn: pgn,
      white: name(white),
      black: name(black),
      whiteRating: rating(white),
      blackRating: rating(black),
      speed: OnlineSpeed.parse(j['speed'] as String?) ?? OnlineSpeed.classical,
      timeControl: timeControl,
      result: result,
      playedAtMs: j['createdAt'] is int ? j['createdAt'] as int : null,
      chess960: variant == 'chess960',
      rated: j['rated'] is bool ? j['rated'] as bool : null,
    ));
  }

  static final _idPattern = RegExp(r'^[A-Za-z0-9]{4,16}$');
}

sealed class _Result {
  const _Result();
}

final class _Parsed extends _Result {
  const _Parsed(this.game);

  final OnlineGame game;
}

final class _Unsupported extends _Result {
  const _Unsupported();
}

final class _Malformed extends _Result {
  const _Malformed();
}
