import 'package:dartchess/dartchess.dart';

import '../../l10n/app_localizations.dart';

/// A SAN move in words for a screen reader (SPEC section 4: "Squares and
/// moves are announced in SAN"): `Nf3` -> "Knight f3", `Qxd5+` -> "Queen
/// takes d5, check", `exd5` -> "e takes d5", `O-O` -> "castles kingside",
/// `e8=Q#` -> "e8, promotes to Queen, checkmate". The visible text stays
/// plain SAN. Anything that does not parse is returned unchanged.
String spokenSan(AppLocalizations l10n, String san) {
  var body = san.trim();
  if (body.isEmpty) return san;
  var check = false;
  var mate = false;
  while (body.endsWith('+') || body.endsWith('#') || body.endsWith('!') || body.endsWith('?')) {
    if (body.endsWith('+')) check = true;
    if (body.endsWith('#')) mate = true;
    body = body.substring(0, body.length - 1);
  }
  String spoken;
  if (body == 'O-O' || body == '0-0') {
    spoken = l10n.sanCastleShort;
  } else if (body == 'O-O-O' || body == '0-0-0') {
    spoken = l10n.sanCastleLong;
  } else {
    String? promotion;
    final eq = body.indexOf('=');
    if (eq > 0) {
      promotion = _pieceName(l10n, body.substring(eq + 1));
      body = body.substring(0, eq);
    }
    final pieceChar = body.isNotEmpty && 'KQRBN'.contains(body[0]) ? body[0] : null;
    var rest = pieceChar == null ? body : body.substring(1);
    if (rest.length < 2) return san;
    final square = rest.substring(rest.length - 2);
    rest = rest.substring(0, rest.length - 2);
    final capture = rest.endsWith('x');
    if (capture) rest = rest.substring(0, rest.length - 1);
    if (pieceChar == null) {
      spoken = capture && rest.isNotEmpty ? l10n.sanPieceCapture(rest, square) : l10n.sanPawnMove(square);
    } else {
      final piece = _pieceName(l10n, pieceChar)!;
      final who = rest.isEmpty ? piece : l10n.sanPieceFrom(piece, rest);
      spoken = capture ? l10n.sanPieceCapture(who, square) : l10n.sanPieceMove(who, square);
    }
    if (promotion != null) spoken = l10n.sanPromotes(spoken, promotion);
  }
  if (mate) return l10n.sanCheckmate(spoken);
  if (check) return l10n.sanCheck(spoken);
  return spoken;
}

String? _pieceName(AppLocalizations l10n, String letter) => switch (letter) {
      'K' => l10n.sanKing,
      'Q' => l10n.sanQueen,
      'R' => l10n.sanRook,
      'B' => l10n.sanBishop,
      'N' => l10n.sanKnight,
      _ => null,
    };

/// A move with its number and mover for a screen reader: "Move 12, Black:
/// Knight f6". [before] is the position the move is played from.
String spokenMove(AppLocalizations l10n, Position before, String san) => l10n.moveSpoken(
      before.fullmoves,
      before.turn == Side.white ? l10n.sideWhite : l10n.sideBlack,
      spokenSan(l10n, san),
    );
