import 'models.dart';
import 'package:glyph_core/glyph_core.dart';

/// Saved games. The SQLite implementation is `SqliteGameRepository`; tests and
/// widget tests use `InMemoryGameRepository`.
abstract interface class GameRepository {
  /// Saves [game]. When `game.sourceId` is non-null and a game with the same
  /// (source, sourceId) exists, nothing is written and the existing id comes
  /// back with `duplicate: true`.
  Future<SaveResult> save(NewGame game);

  /// All games, newest import first, with their analysis summary.
  Future<List<GameRecord>> list();

  Future<GameRecord?> get(int id);

  /// Deletes the game and, by cascade, its analysis, lines and labels.
  Future<void> delete(int id);

  Future<void> setUserSide(int id, Side? side);

  /// Which of [sourceIds] already exist for [source]: source id -> game id.
  /// The online import uses it to mark games that are in the library
  /// (dedupe on `(source, source_id)`).
  Future<Map<String, int>> idsBySource(GameSource source, Iterable<String> sourceIds);
}

/// Per-game analysis results, written by the engine pipeline.
abstract interface class AnalysisRepository {
  Future<AnalysisRecord?> get(int gameId);

  Future<void> upsert(AnalysisRecord analysis);

  /// Replaces the lines of one position (one transaction), so a ply is either
  /// fully persisted or not at all.
  Future<void> putPositionLines(int gameId, int ply, List<PositionLineRecord> lines);

  /// Persists one analysed position **and** advances `completed_plies` in one
  /// transaction, so a crash never leaves lines without progress or progress
  /// without lines. [completedPlies] counts positions (ply + 1 for in-order
  /// analysis). The `analyses` row must exist (see [upsert]).
  Future<void> savePosition(
    int gameId,
    int ply,
    List<PositionLineRecord> lines, {
    required int completedPlies,
    required int updatedAt,
  });

  /// The lines of a game ordered by (ply, rank), from position [fromPly] on
  /// (0 = all). The analysis board re-reads only the tail after each new
  /// position instead of the whole game.
  Future<List<PositionLineRecord>> positionLines(int gameId, {int fromPly = 0});

  Future<void> putLabels(int gameId, List<MoveLabelRecord> labels);

  /// Stores a finished review atomically: **only if** the analysis row is
  /// still `completed` with `updated_at == expectedUpdatedAt` (the snapshot
  /// the review was computed from), writes [labels] and sets
  /// `white_accuracy` / `black_accuracy` (nothing else on the row) in one
  /// transaction and returns true. Otherwise (row cleared, restarted, resumed
  /// or re-completed since) writes nothing and returns false, so a stale
  /// review can neither overwrite a running analysis nor resurrect a
  /// `completed` row.
  Future<bool> saveReview(
    int gameId, {
    required int expectedUpdatedAt,
    required List<MoveLabelRecord> labels,
    double? whiteAccuracy,
    double? blackAccuracy,
  });

  /// All labels of a game ordered by ply.
  Future<List<MoveLabelRecord>> labels(int gameId);

  /// Removes lines, labels and the analysis row (for "Re-analyse").
  Future<void> clear(int gameId);

  /// Startup crash recovery: rows still `running` belong to a process that
  /// was killed mid-job (no job runs yet at startup). Sets them to `paused`
  /// so the UI offers Resume; returns how many rows changed.
  Future<int> pauseInterrupted({required int updatedAt});
}

/// Saved explanations and summaries (SPEC trap 17: keyed by `CacheKey.of`).
abstract interface class LlmCacheRepository {
  Future<CachedLlmText?> get(String key);

  /// Inserts or replaces the entry with that key (Regenerate overwrites) and
  /// trims the table to [maxEntries], oldest first.
  Future<void> put(CachedLlmText entry, {int maxEntries = defaultMaxEntries});

  /// Removes everything cached for [gameId] (the game was deleted or is being
  /// re-analysed). Returns how many rows went.
  Future<int> deleteForGame(int gameId);

  Future<int> count();

  static const int defaultMaxEntries = 500;
}

/// Plain key/value settings. Never holds secrets (SPEC 5.4).
abstract interface class SettingsRepository {
  Future<String?> get(String key);

  Future<void> set(String key, String value);

  Future<void> remove(String key);
}

/// Setting keys.
abstract final class SettingsKeys {
  static const lichessUsername = 'lichess_username';
  static const chessComUsername = 'chesscom_username';
  static const classifierVersion = 'classifier_version';
  static const engineDepthPreset = 'engine_depth_preset';
  static const engineThreads = 'engine_threads';
  static const engineHashMb = 'engine_hash_mb';

  // Explanations (SPEC F13, F14, F12). Never the API key: that lives in the
  // secret store only.
  static const llmProvider = 'llm_provider';
  static const llmBaseUrl = 'llm_base_url';
  static const llmModel = 'llm_model';
  static const llmTokenMode = 'llm_token_mode';
  static const llmTokenValue = 'llm_token_value';
  // The origin (scheme://host:port) an API key was saved for, per key slot,
  // and the origins allowed to receive a key over plain http. Origins only.
  static const llmKeyOriginPrefix = 'llm_bound_origin.';
  static const llmCleartextOrigins = 'llm_cleartext_origins';
  static const explainLanguage = 'explain_language';
  static const explainTone = 'explain_tone';
  static const explainAudience = 'explain_audience';
  static const summaryEnabled = 'summary_enabled';
  static const summaryAuto = 'summary_auto';
}
