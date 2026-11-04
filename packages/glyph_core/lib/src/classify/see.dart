import 'package:dartchess/dartchess.dart';

/// Static exchange evaluation (SPEC 2.1 and trap 6).
///
/// Values are in pawns with the classifier's piece values (P=1, N=3, B=3,
/// R=5, Q=9; the king counts [kingValue] so it is never "won" by an exchange).
/// The exchange on the target square is played out with the least valuable
/// attacker first, x-rays included (sliders behind a capturing piece join in
/// because occupancy is updated after every capture), and either side may
/// stop capturing when continuing would lose material (the usual swap-list
/// minimax).
///
/// Approximations, as in most engines' SEE: pins are ignored after the first
/// capture, and a pawn that recaptures on the last rank is valued as a queen.
/// A king only recaptures when the square is no longer attacked.
abstract final class See {
  static const int kingValue = 100;

  /// Piece values used by SEE and by the classifier (SPEC 2.1).
  static int value(Role role) => switch (role) {
    Role.pawn => 1,
    Role.knight => 3,
    Role.bishop => 3,
    Role.rook => 5,
    Role.queen => 9,
    Role.king => kingValue,
  };

  /// Net material the side to move in [position] gains by playing the
  /// capture [move] and the best exchange that follows on its target square
  /// (negative = the capture loses material). A non-capture returns the
  /// result of putting the piece on the square: 0 if it is safe, minus its
  /// value if it can be taken for free, and so on.
  ///
  /// [move] must be legal in [position]; castling is never a capture (0).
  static int evaluate(Position position, NormalMove move) {
    final board = position.board;
    final from = move.from;
    final to = move.to;
    final mover = board.pieceAt(from);
    if (mover == null) throw ArgumentError('No piece on ${from.name}');
    final target = board.pieceAt(to);
    if (mover.role == Role.king && target != null && target.color == mover.color) return 0; // castling

    var occupied = board.occupied.withoutSquare(from);
    var captured = 0;
    if (target != null) {
      captured = value(target.role);
    } else if (mover.role == Role.pawn && from.file != to.file) {
      // En passant: the captured pawn stands beside the target square.
      captured = 1;
      occupied = occupied.withoutSquare(Square.fromCoords(to.file, from.rank));
    }
    occupied = occupied.withSquare(to);

    var onSquare = value(mover.role);
    final promotion = move.promotion;
    if (promotion != null) {
      captured += value(promotion) - 1;
      onSquare = value(promotion);
    }

    final gain = <int>[captured];
    var side = mover.color.opposite;
    while (true) {
      final attackers = board.attacksTo(to, side, occupied: occupied).intersect(occupied);
      if (attackers.isEmpty) break;
      final (sq, role) = _leastValuable(board, attackers);
      if (role == Role.king &&
          board.attacksTo(to, side.opposite, occupied: occupied.withoutSquare(sq)).intersect(occupied).isNotEmpty) {
        break; // the king may not capture into a defended square
      }
      var next = value(role);
      var extra = 0;
      if (role == Role.pawn && (to.rank == Rank.first || to.rank == Rank.eighth)) {
        next = value(Role.queen);
        extra = next - 1;
      }
      gain.add(onSquare + extra - gain.last);
      onSquare = next;
      occupied = occupied.withoutSquare(sq);
      side = side.opposite;
    }
    for (var d = gain.length - 1; d > 0; d--) {
      final stand = -gain[d - 1];
      gain[d - 1] = -(stand > gain[d] ? stand : gain[d]);
    }
    return gain.first;
  }

  static (Square, Role) _leastValuable(Board board, SquareSet attackers) {
    for (final role in const [Role.pawn, Role.knight, Role.bishop, Role.rook, Role.queen, Role.king]) {
      final s = attackers.intersect(board.byRole(role));
      if (s.isNotEmpty) return (s.first!, role);
    }
    throw StateError('unreachable');
  }

  /// The material the move captures (0 for quiet moves and castling), in
  /// pawns; en passant counts a pawn.
  static int capturedValue(Position position, NormalMove move) {
    final board = position.board;
    final mover = board.pieceAt(move.from);
    final target = board.pieceAt(move.to);
    if (target != null) return mover != null && target.color == mover.color ? 0 : value(target.role);
    if (mover?.role == Role.pawn && move.from.file != move.to.file) return 1;
    return 0;
  }

  /// Whether [move] captures (en passant included, castling excluded).
  static bool isCapture(Position position, NormalMove move) => capturedValue(position, move) > 0;

  /// Captures available to the side to move in [position], as legal moves
  /// (promotions to a queen only).
  static Iterable<NormalMove> legalCaptures(Position position) sync* {
    final board = position.board;
    final enemy = board.bySide(position.turn.opposite);
    for (final MapEntry(key: from, value: dests) in position.legalMoves.entries) {
      final role = board.roleAt(from);
      for (final to in dests.squares) {
        final isEp = role == Role.pawn && from.file != to.file && board.pieceAt(to) == null;
        if (!enemy.has(to) && !isEp) continue;
        final promo = role == Role.pawn && (to.rank == Rank.first || to.rank == Rank.eighth) ? Role.queen : null;
        yield NormalMove(from: from, to: to, promotion: promo);
      }
    }
  }

  /// The sacrifice rule of SPEC 2.1 (Brilliant, condition 2), for the move
  /// [move] played by the side to move in [before]:
  ///
  /// * the move is a capture whose own exchange loses at least [threshold]
  ///   (`evaluate <= -threshold`, e.g. Bxh7+ Kxh7); **or**
  /// * after the move, the opponent has a legal capture of one of the mover's
  ///   pieces that nets the opponent at least [threshold] more than the move
  ///   itself captured (`evaluate(after, capture) - capturedValue >= threshold`;
  ///   for a quiet move that is exactly SPEC's "SEE gain >= 2").
  ///
  /// For a capture, opponent recaptures on the same square are left to the
  /// first rule: they are the exchange the move started. So a queen trade, a
  /// recapture or a pawn trade (`evaluate == 0`) is never a sacrifice
  /// (trap 6).
  static bool isSacrifice(Position before, NormalMove move, {int threshold = 2}) {
    final captured = capturedValue(before, move);
    if (captured > 0 && evaluate(before, move) <= -threshold) return true;
    final after = before.play(move);
    for (final c in legalCaptures(after)) {
      if (captured > 0 && c.to == move.to) continue;
      if (evaluate(after, c) - captured >= threshold) return true;
    }
    return false;
  }

  /// Pieces of [side] that the opponent can win by a capture (SEE > 0) in
  /// [position], as `(square, role)`. Ignores whose turn it is: the
  /// opponent's captures are tried as if it were to move. Used for the
  /// prompt's `hangingAfterMove` (M6).
  static List<(Square, Role)> hangingPieces(Position position, Side side) {
    final asOpponent = position.turn == side.opposite ? position : _withTurn(position, side.opposite);
    if (asOpponent == null) return const [];
    final out = <(Square, Role)>[];
    final seen = <Square>{};
    for (final c in legalCaptures(asOpponent)) {
      if (seen.contains(c.to)) continue;
      final role = asOpponent.board.roleAt(c.to);
      if (role == null || role == Role.king) continue;
      if (evaluate(asOpponent, c) > 0) {
        seen.add(c.to);
        out.add((c.to, role));
      }
    }
    out.sort((a, b) => a.$1.compareTo(b.$1));
    return out;
  }

  static Position? _withTurn(Position p, Side turn) {
    final parts = p.fen.split(' ');
    parts[1] = turn == Side.white ? 'w' : 'b';
    parts[3] = '-';
    try {
      return Position.setupPosition(Rule.chess, Setup.parseFen(parts.join(' ')));
    } on PositionSetupException {
      return null; // the other side would be in check: not a legal position
    }
  }
}
