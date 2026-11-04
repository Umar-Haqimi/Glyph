import 'package:glyph_core/glyph_core.dart';

import '../data/models.dart';
import '../data/repositories.dart';

/// Turns a finished analysis into move labels and accuracy (SPEC F5, F6):
/// reads the stored engine lines, runs `reviewGame` from `glyph_core` and
/// persists the result (`move_labels`, `analyses.white_accuracy` /
/// `black_accuracy`). Pure persistence glue; every rule lives in the core.
///
/// Labels are always recomputed from `position_lines`, never from earlier
/// labels, so a new [ClassifierConfig] re-labels every analysed game
/// ([reclassifyIfStale], keyed by `settings.classifier_version`, SPEC 5.4).
class ReviewService {
  ReviewService({
    required this.games,
    required this.analyses,
    required this.settings,
    required this.book,
    this.config = ClassifierConfig.standard,
  });

  final GameRepository games;
  final AnalysisRepository analyses;
  final SettingsRepository settings;

  /// The opening book (loaded lazily; an empty book just means no Book moves).
  final Future<OpeningBook> Function() book;
  final ClassifierConfig config;

  /// Classifies [gameId] if its analysis is `completed`, and stores the
  /// labels and accuracies. Returns the review, or null when there is nothing
  /// to classify (no game, unfinished analysis, unreadable PGN, a position
  /// without stored lines, or the analysis was restarted while this ran).
  Future<GameReview?> classify(int gameId) async {
    final record = await games.get(gameId);
    final analysis = await analyses.get(gameId);
    if (record == null || analysis == null || analysis.status != AnalysisStatus.completed) return null;
    final parsed = parsePgn(record.pgn);
    if (parsed.games.isEmpty) return null;
    final game = parsed.games.first;

    final rows = await analyses.positionLines(gameId);
    // Every position (start + one per ply) must be stored; otherwise the
    // data does not belong to this game's moves and nothing is written.
    final stored = {for (final r in rows) r.ply};
    for (var ply = 0; ply <= game.plyCount; ply++) {
      if (!stored.contains(ply)) return null;
    }
    final lines = <int, List<EngineLine>>{};
    for (final row in rows) {
      final line = engineLineFromStored(
        rank: row.rank,
        scoreCp: row.scoreCp,
        scoreMate: row.scoreMate,
        depth: row.depth,
        pvUci: row.pvUci,
      );
      // The terminal marker row (both scores NULL) yields no line; the
      // classifier recognises the position itself.
      (lines[row.ply] ??= []).addAll([?line]);
    }

    final review = reviewGame(game, lines, book: await book(), config: config);

    // Re-read: a re-analysis may have started (and cleared the lines) while
    // the review ran; never write labels over a running analysis.
    final current = await analyses.get(gameId);
    if (current == null || current.status != AnalysisStatus.completed) return null;
    await analyses.putLabels(gameId, [
      for (final m in review.moves)
        if (m != null)
          MoveLabelRecord(
            gameId: gameId,
            ply: m.ply,
            label: m.label,
            epLoss: m.epLoss,
            winBefore: m.winBefore,
            winAfter: m.winAfter,
            bestUci: m.bestUci,
          ),
    ]);
    await analyses.upsert(AnalysisRecord(
      gameId: gameId,
      engine: current.engine,
      depth: current.depth,
      multipv: current.multipv,
      status: current.status,
      completedPlies: current.completedPlies,
      whiteAccuracy: review.accuracy.white,
      blackAccuracy: review.accuracy.black,
      updatedAt: current.updatedAt,
    ));
    return review;
  }

  /// Classifies [gameId] when its analysis is completed but its labels are
  /// missing (e.g. the app was killed between the last ply and the review).
  /// Returns true when it classified (stored data changed).
  Future<bool> ensureClassified(int gameId) async {
    final analysis = await analyses.get(gameId);
    if (analysis == null || analysis.status != AnalysisStatus.completed) return false;
    final record = await games.get(gameId);
    if (record == null) return false;
    final labels = await analyses.labels(gameId);
    if (labels.length < record.plyCount || (analysis.whiteAccuracy == null && record.plyCount >= 2)) {
      return await classify(gameId) != null;
    }
    return false;
  }

  /// When the stored `classifier_version` differs from [config]'s, re-labels
  /// every completed analysis and records the new version. Returns the number
  /// of games re-labelled.
  Future<int> reclassifyIfStale() async {
    final stored = await settings.get(SettingsKeys.classifierVersion);
    final current = '${config.version}';
    if (stored == current) return 0;
    var n = 0;
    for (final g in await games.list()) {
      if (g.analysisStatus == AnalysisStatus.completed && await classify(g.id) != null) n++;
    }
    await settings.set(SettingsKeys.classifierVersion, current);
    return n;
  }
}
