import 'dart:async';

import 'package:dartchess/dartchess.dart' show Side;

/// Where an online game comes from.
enum OnlineSource { lichess, chesscom }

/// The speed classes of lichess and chess.com, merged. lichess `ultraBullet`
/// counts as [bullet]; [daily] is chess.com's correspondence.
enum OnlineSpeed {
  bullet,
  blitz,
  rapid,
  classical,
  correspondence,
  daily;

  static OnlineSpeed? parse(String? name) => switch (name) {
        'ultraBullet' || 'bullet' => bullet,
        'blitz' => blitz,
        'rapid' => rapid,
        'classical' => classical,
        'correspondence' => correspondence,
        'daily' => daily,
        _ => null,
      };
}

/// One game from an online source, with just enough to list it and to import it
/// (the PGN is parsed by the normal import path).
class OnlineGame {
  const OnlineGame({
    required this.source,
    required this.sourceId,
    required this.pgn,
    this.white,
    this.black,
    this.whiteRating,
    this.blackRating,
    required this.speed,
    this.timeControl,
    required this.result,
    this.playedAtMs,
    this.chess960 = false,
    this.rated,
  });

  /// Rebuilds a game from [toJson]. Throws [FormatException] on a wrong shape.
  factory OnlineGame.fromJson(Map<String, Object?> j) {
    String? str(String k) {
      final v = j[k];
      if (v == null) return null;
      if (v is String) return v;
      throw FormatException('$k is not a string');
    }

    int? integer(String k) {
      final v = j[k];
      if (v == null) return null;
      if (v is int) return v;
      throw FormatException('$k is not an int');
    }

    final source = OnlineSource.values.asNameMap()[str('source')];
    final speed = OnlineSpeed.values.asNameMap()[str('speed')];
    final id = str('id');
    final pgn = str('pgn');
    final result = str('result');
    if (source == null || speed == null || id == null || pgn == null || result == null) {
      throw const FormatException('missing field');
    }
    return OnlineGame(
      source: source,
      sourceId: id,
      pgn: pgn,
      white: str('white'),
      black: str('black'),
      whiteRating: integer('whiteRating'),
      blackRating: integer('blackRating'),
      speed: speed,
      timeControl: str('timeControl'),
      result: result,
      playedAtMs: integer('playedAt'),
      chess960: j['chess960'] == true,
      rated: j['rated'] is bool ? j['rated'] as bool : null,
    );
  }

  final OnlineSource source;

  /// lichess: the 8-character game id. chess.com: the game URL. Together with
  /// the source this is the library's dedupe key.
  final String sourceId;
  final String pgn;
  final String? white;
  final String? black;
  final int? whiteRating;
  final int? blackRating;
  final OnlineSpeed speed;

  /// `180+2`, `1/86400` (days per move) and the like, as the site reports it.
  final String? timeControl;

  /// `1-0`, `0-1`, `1/2-1/2` or `*`.
  final String result;

  /// When the game was played, Unix epoch ms (lichess `createdAt`, chess.com
  /// `end_time`).
  final int? playedAtMs;
  final bool chess960;
  final bool? rated;

  Map<String, Object?> toJson() => {
        'source': source.name,
        'id': sourceId,
        'pgn': pgn,
        'white': white,
        'black': black,
        'whiteRating': whiteRating,
        'blackRating': blackRating,
        'speed': speed.name,
        'timeControl': timeControl,
        'result': result,
        'playedAt': playedAtMs,
        'chess960': chess960,
        'rated': rated,
      };

  /// The side [username] played (case-insensitive), or null when neither or
  /// both players carry that name. An online import knows the account it
  /// fetched, so this is more reliable than matching the configured names.
  Side? sideOf(String username) {
    final n = username.trim().toLowerCase();
    if (n.isEmpty) return null;
    final w = white?.toLowerCase() == n;
    final b = black?.toLowerCase() == n;
    if (w == b) return null;
    return w ? Side.white : Side.black;
  }
}

/// Why an online fetch failed (each has its own copy in the app).
enum OnlineErrorKind {
  /// The typed name cannot be a username of that site; nothing was requested.
  invalidUsername,
  userNotFound,

  /// chess.com answered 410: the data is permanently gone.
  unavailable,

  /// HTTP 429 and the retries ran out.
  rateLimited,
  offline,
  timeout,
  tls,

  /// A 4xx/5xx status the app has no better word for; see [OnlineFetchError.status].
  server,

  /// The answer could not be read (not JSON, wrong shape).
  badResponse,

  /// The answer exceeded [Limits.maxOnlineResponseBytes].
  tooLarge,
}

class OnlineFetchError {
  const OnlineFetchError(this.kind, {this.status});

  final OnlineErrorKind kind;
  final int? status;

  @override
  String toString() => 'OnlineFetchError(${kind.name}${status == null ? '' : ', $status'})';
}

/// Thrown inside the clients; never leaves them (fetches return an outcome).
class OnlineFetchException implements Exception {
  const OnlineFetchException(this.error);

  final OnlineFetchError error;

  @override
  String toString() => 'OnlineFetchException(${error.kind.name})';
}

/// Progress a fetch reports while it runs.
sealed class OnlineEvent {
  const OnlineEvent();
}

/// A game arrived ([count] so far).
class OnlineGameReceived extends OnlineEvent {
  const OnlineGameReceived(this.game, this.count);

  final OnlineGame game;
  final int count;
}

/// The site said "slow down" (HTTP 429) and the fetch waits: [remaining] of
/// [total], reported about once per second. The fetch resumes by itself.
class OnlineBackoff extends OnlineEvent {
  const OnlineBackoff(this.source, this.remaining, this.total);

  final OnlineSource source;
  final Duration remaining;
  final Duration total;
}

/// Everything a fetch produced. A failure after some games arrived keeps
/// them: [games] is whatever was received, [error] says why it stopped.
class OnlineFetchOutcome {
  const OnlineFetchOutcome({
    this.games = const [],
    this.error,
    this.cancelled = false,
    this.skipped = 0,
  });

  /// Newest first.
  final List<OnlineGame> games;
  final OnlineFetchError? error;
  final bool cancelled;

  /// Games that were not usable: another variant than chess / Chess960, or
  /// unreadable entries.
  final int skipped;

  bool get ok => error == null && !cancelled;
}

/// Lets the caller abort a fetch, including while it waits out a 429.
class OnlineCancelToken {
  final _done = Completer<void>();

  bool get isCancelled => _done.isCompleted;

  /// Completes when [cancel] is called.
  Future<void> get whenCancelled => _done.future;

  void cancel() {
    if (!_done.isCompleted) _done.complete();
  }
}

/// Request timeouts (SPEC 6: connect 15 s, first byte 60 s, total 180 s). The
/// connect timeout belongs to the HTTP client the factory builds; [firstByte]
/// also bounds every gap between two chunks; [total] bounds one request
/// (a wait after a 429 is not part of it).
class OnlineTimeouts {
  const OnlineTimeouts({
    this.firstByte = const Duration(seconds: 60),
    this.total = const Duration(seconds: 180),
  });

  final Duration firstByte;
  final Duration total;
}

/// What the app needs from a game source: both clients implement it, widget
/// tests substitute fakes.
abstract interface class OnlineGamesClient {
  /// Fetches the user's most recent games (at most [max], newest first) and
  /// reports progress through [onEvent]. Never throws: failures, partial
  /// results and cancellation are in the outcome.
  Future<OnlineFetchOutcome> fetchGames(
    String username, {
    int max,
    OnlineCancelToken? cancel,
    void Function(OnlineEvent event)? onEvent,
  });
}
