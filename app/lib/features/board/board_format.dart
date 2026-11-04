import 'package:dartchess/dartchess.dart';
import 'package:glyph_core/glyph_core.dart';

/// Pure helpers of the analysis board: score text, engine lines in SAN,
/// Chess960 castling on the board, clocks and move numbers. No Flutter here.

/// A score as engines UIs write it (SPEC F8): `+1.3`, `-0.4`, `0.0`, `#4`,
/// `-#2`. Always White's point of view, like everything stored.
String formatScore(WhiteScore score) {
  final mate = score.mate;
  if (mate != null) {
    if (mate == 0) return '#';
    return mate > 0 ? '#$mate' : '-#${-mate}';
  }
  return formatCp(score.cp!);
}

/// Centipawns in pawns with one decimal and an explicit sign (`0.0` has none).
String formatCp(int cp) {
  final pawns = cp.abs() / 100;
  // Round half away from zero to one decimal.
  final tenths = (pawns * 10 + 0.5).floor();
  final text = '${tenths ~/ 10}.${tenths % 10}';
  if (tenths == 0) return text;
  return cp < 0 ? '-$text' : '+$text';
}

/// A move as it is *drawn*: castling in dartchess is king-takes-rook
/// (`e1h1`), the board shows the king landing on the g or c file (the
/// lichess mobile `altCastles` rule, docs/DECISIONS.md M0 section 2.2). When
/// the king does not move at all (Chess960, king already on g1) the rook's
/// square is used so there is still something to highlight or point at.
({Square from, Square to}) displaySquares(Position position, NormalMove move) {
  final piece = position.board.pieceAt(move.from);
  final target = position.board.pieceAt(move.to);
  if (piece != null && piece.role == Role.king && target != null && target.color == piece.color && target.role == Role.rook) {
    final file = move.to > move.from ? File.g : File.c;
    final dest = Square.fromCoords(file, move.from.rank);
    return (from: move.from, to: dest == move.from ? move.to : dest);
  }
  return (from: move.from, to: move.to);
}

/// The played move in the form used for the last-move highlight.
NormalMove displayMove(Position position, NormalMove move) {
  final d = displaySquares(position, move);
  return NormalMove(from: d.from, to: d.to, promotion: move.promotion);
}

/// A legal [NormalMove] from engine/dartchess UCI in [position], or null.
NormalMove? legalUci(Position position, String uci) {
  if (uci.length < 4 || uci.length > 5) return null;
  final move = Move.parse(uci);
  if (move is! NormalMove || !position.isLegal(move)) return null;
  return move;
}

/// SAN of the principal variation [pv] (dartchess UCI) played from
/// [position]; stops at the first illegal move, so garbage never throws.
List<String> pvToSan(Position position, List<String> pv, {int maxMoves = 10}) {
  final out = <String>[];
  var pos = position;
  for (final uci in pv.take(maxMoves)) {
    final move = legalUci(pos, uci);
    if (move == null) break;
    final (next, san) = pos.makeSan(move);
    out.add(san);
    pos = next;
  }
  return out;
}

/// `12. Nf3 Nc6 13. d4`, or `12… Nc6 13. d4` when Black moves first.
String formatMoveSequence(Position start, List<String> sans) {
  final buffer = StringBuffer();
  var number = start.fullmoves;
  var white = start.turn == Side.white;
  for (var i = 0; i < sans.length; i++) {
    if (buffer.isNotEmpty) buffer.write(' ');
    if (white) {
      buffer.write('$number. ');
    } else if (i == 0) {
      buffer.write('$number\u2026 ');
    }
    buffer.write(sans[i]);
    if (!white) number++;
    white = !white;
  }
  return buffer.toString();
}

/// `12.` for a White move, `12…` for Black: the number in front of the move
/// that is played from [before].
String moveNumberLabel(Position before) =>
    before.turn == Side.white ? '${before.fullmoves}.' : '${before.fullmoves}…';

/// `12. Nf3` / `12… Nf6`.
String formatMove(Position before, String san) => '${moveNumberLabel(before)} $san';

/// Clock text of `[%clk]` milliseconds: `1:23:45`, `9:58`, and tenths below
/// ten seconds (`0:07.4`).
String formatClock(int ms) {
  final total = ms < 0 ? 0 : ms;
  final seconds = total ~/ 1000;
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int n) => n.toString().padLeft(2, '0');
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  if (seconds < 10) return '$m:${two(s)}.${(total % 1000) ~/ 100}';
  return '$m:${two(s)}';
}

/// Base time in milliseconds of a PGN `TimeControl` tag (`600+5`, `180`),
/// or null for anything else (daily `1/86400`, `-`, `?`).
int? baseTimeMs(String? timeControl) {
  if (timeControl == null) return null;
  final m = RegExp(r'^(\d+)(?:\+\d+)?$').firstMatch(timeControl.trim());
  if (m == null) return null;
  final seconds = int.tryParse(m.group(1)!);
  return seconds == null || seconds <= 0 ? null : seconds * 1000;
}

/// The clock of [side] after ply [ply] of [game]: the `[%clk]` of that side's
/// latest move at or before [ply]; before its first move the base time of the
/// time control. Null when the game has no `[%clk]` comments at all.
int? clockAt(Game game, Side side, int ply) {
  if (!game.plies.any((p) => p.clockMs != null)) return null;
  for (var p = ply.clamp(0, game.plyCount); p >= 1; p--) {
    if (_moverOf(game, p) == side) return game.plies[p - 1].clockMs;
  }
  return baseTimeMs(game.timeControl);
}

Side _moverOf(Game game, int ply) {
  final first = game.startSide;
  return (ply - 1).isEven ? first : first.opposite;
}

/// Which side made ply [ply] (1-based) of [game].
Side moverOfPly(Game game, int ply) => _moverOf(game, ply);
