import 'package:dartchess/dartchess.dart' show Side;

import '../engine/score.dart';
import '../engine/uci_parser.dart';
import '../game/game.dart';
import '../openings/opening_book.dart';
import 'accuracy.dart';
import 'classifier.dart';
import 'classifier_config.dart';
import 'key_moments.dart';
import 'move_label.dart';

/// Everything M4 derives from a finished analysis (SPEC F5, F6, F9 data).
class GameReview {
  const GameReview({
    required this.moves,
    required this.accuracy,
    required this.keyMoments,
    required this.book,
    required this.classifierVersion,
  });

  /// One entry per ply (index 0 = ply 1); null where engine data is missing.
  final List<ClassifiedMove?> moves;
  final GameAccuracy accuracy;
  final List<KeyMoment> keyMoments;

  /// Book prefix and opening name (ECO + name of the deepest named position).
  final BookAnnotation book;
  final int classifierVersion;

  OpeningEntry? get opening => book.opening;

  /// Label count per side (the report card's table).
  Map<MoveLabel, int> counts(Side side) {
    final out = {for (final l in MoveLabel.values) l: 0};
    for (final m in moves) {
      if (m != null && m.side == side) out[m.label] = out[m.label]! + 1;
    }
    return out;
  }
}

/// Rebuilds an [EngineLine] from a `position_lines` row (White POV). Returns
/// null for the terminal marker row (both scores NULL).
EngineLine? engineLineFromStored({
  required int rank,
  int? scoreCp,
  int? scoreMate,
  required int depth,
  required String pvUci,
}) {
  final score = WhiteScore.fromStored(cp: scoreCp, mate: scoreMate);
  if (score == null) return null;
  return EngineLine(rank: rank, score: score, depth: depth, pv: pvUci.split(' ').where((m) => m.isNotEmpty).toList());
}

/// The `ClassifyGame` + `ComputeAccuracy` use case (SPEC 5.3): labels, accuracy,
/// key moments and opening of [game] from the engine lines of its positions
/// (`lines[ply]`, 0 = start; White POV; terminal positions have none).
///
/// Book moves come from [book] (`OpeningBook.annotate`: contiguous prefix,
/// standard start only). Accuracy uses the same per-position Win% as the
/// classifier, from Glyph's own search of the start position (lichess falls
/// back to +15 cp only when it has none).
GameReview reviewGame(
  Game game,
  Map<int, List<EngineLine>> lines, {
  OpeningBook? book,
  ClassifierConfig config = ClassifierConfig.standard,
}) {
  final moves = [for (final p in game.plies) p.uci];
  final annotation = book?.annotate(game) ?? BookAnnotation.none;
  final classifier = Classifier(config: config);
  final classified = classifier.classify(
    startFen: game.startFen,
    moves: moves,
    lines: lines,
    bookPlies: annotation.bookPlies,
  );
  final wins = Classifier.positionWins(game.startFen, moves, lines);
  final accuracy = Accuracy.ofGame([for (final w in wins) w.whiteWin], startSide: game.startSide);
  return GameReview(
    moves: classified,
    accuracy: accuracy,
    keyMoments: KeyMoments.of(classified),
    book: annotation,
    classifierVersion: config.version,
  );
}
