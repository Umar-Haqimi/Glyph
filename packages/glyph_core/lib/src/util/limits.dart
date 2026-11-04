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

  /// Maximum length of one NDJSON line from an online source, in bytes: 1 MB.
  static const int maxNdjsonLineBytes = 1024 * 1024;

  /// Maximum size of an LLM response stream, in bytes: 32 KB. Beyond this the
  /// stream is stopped and the result is marked truncated.
  static const int maxLlmStreamBytes = 32 * 1024;

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
