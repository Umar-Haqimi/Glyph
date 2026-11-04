import 'package:dartchess/dartchess.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../l10n/app_localizations.dart';
import 'board_data.dart';
import 'board_format.dart';
import 'eval_gauge.dart';
import 'spoken_move.dart';

/// Labels whose Explain button is emphasised (SPEC F10).
const Set<MoveLabel> explainEmphasised = {
  MoveLabel.brilliant,
  MoveLabel.great,
  MoveLabel.miss,
  MoveLabel.inaccuracy,
  MoveLabel.mistake,
  MoveLabel.blunder,
};

/// The deterministic one-liner of the coach card (SPEC F10): a template
/// filled from the label, the loss and the best move in SAN; no LLM.
class CoachLine {
  const CoachLine({required this.text, this.label, this.moveText, this.spokenMoveText});

  /// The sentence(s) under the badge.
  final String text;

  /// The move's classification, null at the start position or while the
  /// engine has not reached the move.
  final MoveLabel? label;

  /// `12. Nf3` / `12… Nf6`; null at the start position.
  final String? moveText;

  /// [moveText] in words for a screen reader ("Move 12, White: Knight f3").
  final String? spokenMoveText;
}

/// The coach line for position [ply]. Evaluations are White's point of view,
/// like the gauge and the engine lines (`+0.8` means White is better).
///
/// Template (examples):
/// * Mistake: `Best was Bd3 (+0.8). After Nxe5, eval is -2.4.`
/// * Best: `Best move. Eval is +0.3.`
/// * Miss with a missed mate: `Missed mate in 2. Best was Qh7#. After ...`
/// * Start position: the opening's name.
CoachLine coachLineAt(BoardData data, AppLocalizations l10n, int ply) {
  if (ply <= 0) {
    final name = data.record.openingName ?? data.book.opening?.name;
    final eco = data.record.eco ?? data.book.opening?.eco;
    if (name == null) return CoachLine(text: l10n.coachStart);
    return CoachLine(text: eco == null ? l10n.coachStartOpening(name) : l10n.coachStartOpeningEco(eco, name));
  }
  final played = data.plyAt(ply)!;
  final before = data.positionBefore(ply);
  final moveText = formatMove(before, played.san);
  final spoken = spokenMove(l10n, before, played.san);
  final move = data.moveAt(ply);
  if (move == null) {
    return CoachLine(
      text: data.analysisComplete ? l10n.coachNoData : l10n.coachWaiting,
      moveText: moveText,
      spokenMoveText: spoken,
    );
  }
  final label = move.label;
  final parts = <String>[];

  // The engine's best move before this one, in SAN, and whether it is the
  // move that was played (compared as normalised moves, SPEC trap 2).
  final bestMove = move.bestUci == null ? null : legalUci(before, move.bestUci!);
  final playedMove = Move.parse(played.uci);
  final isTop = move.isTopMove ||
      (bestMove != null && playedMove is NormalMove && before.normalizeMove(bestMove) == before.normalizeMove(playedMove));
  final bestSan = bestMove == null ? null : before.makeSan(bestMove).$2;
  final topBefore = data.topLineAt(ply - 1);
  final bestEval = topBefore == null ? null : formatScore(topBefore.score);

  final after = evalDisplayAt(data, l10n, ply);
  final afterText = after.text ?? (isTop ? bestEval : null);
  // Checkmate, stalemate, dead position, or the final position claimed as a
  // threefold / 50-move draw (the classifier's rule): the game ends here.
  final gameOver = data.gameOverAt(ply);

  switch (label) {
    case MoveLabel.book:
      final opening = data.book.opening;
      parts.add(data.book.openingPly == ply && opening != null ? l10n.coachBookOpening(opening.name) : l10n.coachBook);
    case MoveLabel.forced:
      parts.add(l10n.coachForced);
    case MoveLabel.brilliant:
      parts.add(l10n.coachBrilliant);
    case MoveLabel.great:
      parts.add(l10n.coachGreat);
    case MoveLabel.best:
      parts.add(l10n.coachBest);
    case MoveLabel.miss:
      // Stored labels do not carry the flag: read it off the engine line
      // before the move (a forced mate for the mover within the Miss limit).
      final mate = move.missedMateIn ?? _missedMate(topBefore?.score, move.side);
      parts.add(mate != null ? l10n.coachMissedMate(mate) : l10n.coachMiss);
      if (bestSan != null && !isTop) parts.add(_bestWas(l10n, bestSan, bestEval));
    case MoveLabel.excellent:
    case MoveLabel.good:
    case MoveLabel.inaccuracy:
    case MoveLabel.mistake:
    case MoveLabel.blunder:
      if (isTop) {
        parts.add(l10n.coachBest);
      } else if (bestSan != null) {
        parts.add(_bestWas(l10n, bestSan, bestEval));
      }
  }

  // Book and Forced moves stay short; everything else says where the game
  // stands afterwards.
  if (label != MoveLabel.book && label != MoveLabel.forced && afterText != null) {
    if (gameOver) {
      parts.add(l10n.coachGameEnds(afterText));
    } else if (isTop || label == MoveLabel.brilliant || label == MoveLabel.great || label == MoveLabel.best) {
      parts.add(l10n.coachEvalIs(afterText));
    } else {
      parts.add(l10n.coachEvalAfter(played.san, afterText));
    }
  }
  return CoachLine(text: parts.join(' '), label: label, moveText: moveText, spokenMoveText: spoken);
}

String _bestWas(AppLocalizations l10n, String san, String? eval) =>
    eval == null ? l10n.coachBestWasNoEval(san) : l10n.coachBestWas(san, eval);

/// Mate distance when [score] is a forced mate for [side] within the limit of
/// the Miss rule (b), else null.
int? _missedMate(WhiteScore? score, Side side) {
  final m = score?.mate;
  if (m == null || m == 0) return null;
  final n = (side == Side.white) == (m > 0) ? m.abs() : null;
  return n != null && n <= ClassifierConfig.standard.missMateMaxMoves ? n : null;
}
