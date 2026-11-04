/// A White-POV engine evaluation read from a PGN `[%eval]` comment.
///
/// Exactly one of [cp] and [mate] is non-null. `mate` is positive when White
/// mates and negative when Black mates (same convention as lichess).
class PlyEval {
  const PlyEval.cp(int this.cp) : mate = null;
  const PlyEval.mate(int this.mate) : cp = null;

  final int? cp;
  final int? mate;

  @override
  bool operator ==(Object other) =>
      other is PlyEval && other.cp == cp && other.mate == mate;

  @override
  int get hashCode => Object.hash(cp, mate);

  @override
  String toString() => mate != null ? '#$mate' : '${cp}cp';
}

/// One half-move of the mainline.
class Ply {
  const Ply({
    required this.number,
    required this.san,
    required this.uci,
    required this.fen,
    this.clockMs,
    this.eval,
    this.comment,
  });

  /// 1-based ply number. This move leads to position `number` (0 = start).
  final int number;

  /// Standard algebraic notation as written in the PGN (normalised by dartchess).
  final String san;

  /// dartchess UCI form. Castling is king-takes-rook (`e1h1`), see DECISIONS.
  final String uci;

  /// Full FEN of the position after this move.
  final String fen;

  /// Remaining clock of the mover after this move, from `[%clk]`, in ms.
  final int? clockMs;

  /// White-POV evaluation from `[%eval]` (imported, e.g. from lichess).
  final PlyEval? eval;

  /// Free text of the comment (clock/eval annotations removed), truncated to
  /// `Limits.maxCommentBytes`.
  final String? comment;

  /// First four FEN fields of [fen] (the EPD used for opening lookup).
  String get epd => epdOfFen(fen);
}

/// The first four space-separated fields of a FEN.
String epdOfFen(String fen) {
  final parts = fen.split(' ');
  return parts.length <= 4 ? fen : parts.take(4).join(' ');
}
