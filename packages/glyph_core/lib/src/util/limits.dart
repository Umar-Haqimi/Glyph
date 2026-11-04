/// Caps on untrusted input (SPEC section 6, "DoS caps").
///
/// Every constant here is covered by a test in `test/limits_test.dart`; the
/// code that enforces each cap lands with the milestone that owns it.
abstract final class Limits {
  /// Maximum size of a PGN input (paste, file or share), in bytes: 2 MB.
  static const int maxPgnBytes = 2 * 1024 * 1024;

  /// Maximum number of games listed from one PGN file.
  static const int maxGamesPerFile = 500;

  /// Maximum number of plies in a single game.
  static const int maxPliesPerGame = 1000;

  /// Maximum length of a single PGN comment, in bytes (longer ones are truncated): 4 KB.
  static const int maxCommentBytes = 4 * 1024;

  /// Maximum number of games fetched from an online source in one go.
  static const int maxOnlineGames = 50;

  /// Default number of games fetched per username (SPEC section 10: 30).
  static const int defaultOnlineGames = 30;

  /// Maximum length of one NDJSON line from an online source, in bytes: 1 MB.
  /// A longer line is skipped (its bytes are dropped as they arrive).
  static const int maxNdjsonLineBytes = 1024 * 1024;

  /// Maximum bytes read from one response of lichess or chess.com: 16 MB (a
  /// chess.com month with 583 games is 2.4 MB, 30 lichess games with
  /// evaluations about 100 KB). Beyond it the fetch fails with `tooLarge`.
  static const int maxOnlineResponseBytes = 16 * 1024 * 1024;

  /// Maximum number of chess.com monthly archives requested for one fetch
  /// (requests are serial; users with a game every few months need many).
  static const int maxChessComArchiveRequests = 36;

  /// Longest wait accepted after an HTTP 429 (a larger `Retry-After` is cut).
  static const Duration maxRateLimitWait = Duration(minutes: 5);

  /// Wait after an HTTP 429: lichess asks for "a full minute".
  static const Duration rateLimitWait = Duration(seconds: 60);

  /// How often a 429 is retried before the fetch gives up.
  static const int maxRateLimitRetries = 2;

  /// Largest cached chess.com month (our trimmed copy), in bytes; a larger one
  /// is simply not cached.
  static const int maxOnlineCacheBodyBytes = 1024 * 1024;

  /// Maximum size of an LLM response stream, in bytes: 32 KB. Beyond this the
  /// stream is stopped and the result is marked truncated.
  static const int maxLlmStreamBytes = 32 * 1024;

  /// Maximum number of bytes read from one LLM response stream, of any kind
  /// (answer text, reasoning deltas, comments, keep-alives, usage chunks): 1 MB.
  /// [maxLlmStreamBytes] only counts answer text; a hostile or broken endpoint
  /// that streams anything else for ever is cut off at this total and the
  /// request fails with `badStream`.
  static const int maxLlmTotalStreamBytes = 1024 * 1024;

  /// Maximum size of one server-sent event (and of an unfinished line) from an
  /// LLM endpoint, in bytes: 256 KB. A stream that never ends a line is cut off.
  static const int maxSseEventBytes = 256 * 1024;

  /// Maximum size of an error body from an LLM endpoint that is read, in
  /// bytes: 64 KB (the rest is dropped).
  static const int maxLlmErrorBodyBytes = 64 * 1024;

  /// Timeout for establishing a connection.
  static const Duration connectTimeout = Duration(seconds: 15);

  /// Timeout for the first byte of a response (long, for reasoning models).
  static const Duration firstByteTimeout = Duration(seconds: 60);

  /// Overall timeout for one request.
  static const Duration totalTimeout = Duration(seconds: 180);
}
