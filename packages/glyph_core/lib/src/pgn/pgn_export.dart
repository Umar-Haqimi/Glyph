import 'package:dartchess/dartchess.dart';

import '../classify/move_label.dart';
import '../game/game.dart';
import '../game/ply.dart';

/// NAG for a label, or null when the label has none (SPEC F18).
int? nagForLabel(MoveLabel label) => switch (label) {
      MoveLabel.brilliant => 3,
      MoveLabel.great => 1,
      MoveLabel.inaccuracy => 6,
      MoveLabel.mistake => 2,
      MoveLabel.blunder => 4,
      MoveLabel.miss => 2,
      _ => null,
    };

/// Exports [game] as an annotated PGN: original headers, `[%eval]` and
/// `[%clk]` per move, label NAGs, and `[Annotator "Glyph"]`.
///
/// [labels] and [evals] are keyed by 1-based ply number (the move that leads to
/// that position) and are inputs: the classifier arrives in M4. Evals are
/// White-POV. A ply without a supplied eval keeps the one read on import.
/// Miss is `$2` plus a `{Miss}` comment. Original free-text comments and NAGs
/// are not exported (the stored original PGN keeps them).
String exportAnnotatedPgn(
  Game game, {
  Map<int, MoveLabel> labels = const {},
  Map<int, PlyEval> evals = const {},
  bool annotator = true,
}) {
  final headers = Map<String, String>.of(game.headers);
  if (annotator) headers['Annotator'] = 'Glyph';
  if (!headers.containsKey('Result')) headers['Result'] = game.result;

  final root = PgnNode<PgnNodeData>();
  var tail = root;
  for (final ply in game.plies) {
    final label = labels[ply.number];
    final nag = label == null ? null : nagForLabel(label);
    final eval = evals[ply.number] ?? ply.eval;
    final comment = PgnComment(
      text: label == MoveLabel.miss ? 'Miss' : null,
      eval: eval == null
          ? null
          : eval.mate != null
              ? PgnEvaluation.mate(mate: eval.mate!)
              : PgnEvaluation.pawns(pawns: eval.cp! / 100),
      clock: ply.clockMs == null ? null : Duration(milliseconds: ply.clockMs!),
    ).makeComment();
    final node = PgnChildNode<PgnNodeData>(
      PgnNodeData(
        san: ply.san,
        nags: nag == null ? null : [nag],
        comments: comment.isEmpty ? null : [comment],
      ),
    );
    tail.children.add(node);
    tail = node;
  }
  return PgnGame<PgnNodeData>(headers: headers, moves: root, comments: const [])
      .makePgn();
}
