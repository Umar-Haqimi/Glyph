import 'package:dartchess/dartchess.dart' show Side;

/// A UCI score exactly as the engine reports it: from the point of view of the
/// **side to move** (SPEC trap 1). Never store or compare these; convert with
/// [toWhitePov] first.
final class Score {
  const Score.cp(int this.cp) : mate = null;

  /// [mate] is in moves: positive = the side to move mates, negative = the
  /// side to move is mated, 0 = the side to move is checkmated.
  const Score.mate(int this.mate) : cp = null;

  final int? cp;
  final int? mate;

  @override
  bool operator ==(Object other) => other is Score && other.cp == cp && other.mate == mate;

  @override
  int get hashCode => Object.hash(cp, mate);

  @override
  String toString() => mate != null ? 'mate $mate' : 'cp $cp';
}

/// A score from **White's** point of view: positive favours White. This is the
/// only form that is stored in the database and handed to the classifier.
///
/// [mate] > 0: White mates in that many moves; [mate] < 0: Black mates in
/// `-mate` moves; [mate] == 0: the game is already checkmate, [winner] says who
/// won (the sign cannot).
final class WhiteScore {
  const WhiteScore.cp(int this.cp)
      : mate = null,
        _zeroMateWinner = null;

  const WhiteScore.mate(int this.mate, {Side? winnerWhenZero})
      : cp = null,
        _zeroMateWinner = winnerWhenZero;

  /// Rebuilds a score from the two nullable database columns. Both null (a
  /// terminal position) returns null.
  static WhiteScore? fromStored({int? cp, int? mate}) {
    if (cp != null) return WhiteScore.cp(cp);
    if (mate != null) return WhiteScore.mate(mate);
    return null;
  }

  final int? cp;
  final int? mate;
  final Side? _zeroMateWinner;

  bool get isMate => mate != null;

  /// The side that delivers mate, or null for a centipawn score.
  Side? get mateWinner {
    final m = mate;
    if (m == null) return null;
    if (m > 0) return Side.white;
    if (m < 0) return Side.black;
    return _zeroMateWinner;
  }

  @override
  bool operator ==(Object other) =>
      other is WhiteScore && other.cp == cp && other.mate == mate && other.mateWinner == mateWinner;

  @override
  int get hashCode => Object.hash(cp, mate, mateWinner);

  @override
  String toString() => mate != null ? 'W#$mate' : 'W${cp}cp';
}

/// SPEC trap 1, the P0 rule. UCI scores are from the side to move's point of
/// view; this is the **only** function in Glyph that flips perspective.
/// Everything the parser hands out, everything stored and everything the
/// classifier reads is White POV.
WhiteScore toWhitePov(Score score, Side sideToMove) {
  final white = sideToMove == Side.white;
  final cp = score.cp;
  if (cp != null) return WhiteScore.cp(white ? cp : -cp);
  final m = score.mate!;
  if (m == 0) return WhiteScore.mate(0, winnerWhenZero: sideToMove.opposite);
  return WhiteScore.mate(white ? m : -m);
}
