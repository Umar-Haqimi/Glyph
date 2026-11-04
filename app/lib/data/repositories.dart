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

  /// All lines of a game ordered by (ply, rank).
  Future<List<PositionLineRecord>> positionLines(int gameId);

  Future<void> putLabels(int gameId, List<MoveLabelRecord> labels);

  /// All labels of a game ordered by ply.
  Future<List<MoveLabelRecord>> labels(int gameId);

  /// Removes lines, labels and the analysis row (for "Re-analyse").
  Future<void> clear(int gameId);
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
}
