import 'package:glyph_core/glyph_core.dart';

import '../data/models.dart';
import '../data/repositories.dart';
import '../platform/app_log.dart';

/// A finished analysis read back from storage, with its review.
class LoadedReview {
  const LoadedReview({
    required this.record,
    required this.analysis,
    required this.game,
    required this.lines,
    required this.review,
  });

  final GameRecord record;
  final AnalysisRecord analysis;
  final Game game;

  /// Engine lines per position (0 = start), White POV.
  final Map<int, List<EngineLine>> lines;
  final GameReview review;
}

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

  /// Reads the stored game and engine lines of a **completed** analysis and
  /// runs the review (labels, accuracy, key moments, opening) without
  /// storing anything. Null when there is nothing to review: no game, an
  /// unfinished analysis, an unreadable PGN, or a position without stored
  /// lines. The game summary (M6) builds its prompt from this.
  Future<LoadedReview?> load(int gameId) async {
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
    return LoadedReview(record: record, analysis: analysis, game: game, lines: lines, review: review);
  }

  /// Classifies [gameId] if its analysis is `completed`, and stores the
  /// labels and accuracies. Returns the review, or null when there is nothing
  /// to classify (see [load]) or the analysis was restarted while this ran.
  Future<GameReview?> classify(int gameId) async {
    final loaded = await load(gameId);
    if (loaded == null) return null;
    final review = loaded.review;
    final analysis = loaded.analysis;

    // One transaction, guarded by the snapshot the review was computed from:
    // if a re-analysis cleared / restarted / re-completed the row meanwhile,
    // nothing is written (no labels over a running analysis, no stale
    // `completed` row resurrected).
    final saved = await analyses.saveReview(
      gameId,
      expectedUpdatedAt: analysis.updatedAt,
      labels: [
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
      ],
      whiteAccuracy: review.accuracy.white,
      blackAccuracy: review.accuracy.black,
    );
    if (!saved) return null;
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
  /// of games re-labelled. The new version is recorded only when no game
  /// failed to re-label (an exception, or a game that is completed but could
  /// not be classified for a reason other than being restarted meanwhile), so
  /// the next start retries; a game whose analysis was restarted during the
  /// pass is not a failure (it gets labelled when it completes again).
  Future<int> reclassifyIfStale() async {
    final stored = await settings.get(SettingsKeys.classifierVersion);
    final current = '${config.version}';
    if (stored == current) return 0;
    var n = 0;
    var failed = false;
    for (final g in await games.list()) {
      if (g.analysisStatus != AnalysisStatus.completed) continue;
      try {
        if (await classify(g.id) != null) {
          n++;
        } else {
          final now = await analyses.get(g.id);
          // Still completed but nothing was written: unreadable PGN or
          // missing lines. Retry on the next start.
          if (now != null && now.status == AnalysisStatus.completed) failed = true;
        }
      } on Object catch (e) {
        failed = true;
        AppLog.warning('Re-classifying a game failed', e); // type only, never game data
      }
    }
    if (!failed) await settings.set(SettingsKeys.classifierVersion, current);
    return n;
  }
}
