import 'dart:convert';

import 'package:dartchess/dartchess.dart';

/// A game listed in `test/vectors/uci_transcripts/games.json`; the recorder
/// (`tool/record_transcripts.dart`) records one transcript per entry and
/// tests look games up by [name]. To add a vector, append an entry and run
/// the recorder (docs/m0/VECTORS.md).
///
/// JSON entry: `{"name": "...", "startFen": "<optional>", "moves": "e4 e5 Nf3"}`
/// where `moves` is a SAN string (or a list of SAN / UCI strings), or
/// `{"name": "...", "mirrorOf": "<other name>"}` for the same game with the
/// colours swapped (board flipped vertically, sides exchanged).
class TranscriptGame {
  const TranscriptGame(this.name, this.startFen, this.moves);

  final String name;
  final String startFen;

  /// dartchess UCI (castling = king takes rook).
  final List<String> moves;
}

List<TranscriptGame> parseTranscriptGames(String json) {
  final list = jsonDecode(json) as List<dynamic>;
  final byName = <String, TranscriptGame>{};
  final out = <TranscriptGame>[];
  for (final raw in list) {
    final e = raw as Map<String, dynamic>;
    final name = e['name'] as String;
    final TranscriptGame game;
    final mirrorOf = e['mirrorOf'] as String?;
    if (mirrorOf != null) {
      final src = byName[mirrorOf];
      if (src == null) throw FormatException('mirrorOf "$mirrorOf" must be listed before "$name"');
      game = TranscriptGame(name, mirrorFen(src.startFen), [for (final m in src.moves) mirrorUci(m)]);
    } else {
      final startFen = (e['startFen'] as String?) ?? kInitialFEN;
      final moves = e['moves'];
      final tokens = moves is String
          ? moves.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList()
          : [for (final m in moves as List<dynamic>) m as String];
      game = TranscriptGame(name, startFen, sanOrUciToUci(startFen, tokens));
    }
    byName[name] = game;
    out.add(game);
  }
  return out;
}

/// Converts SAN (or already-UCI) tokens to dartchess UCI by replaying them.
List<String> sanOrUciToUci(String startFen, List<String> tokens) {
  var pos = Position.setupPosition(Rule.chess, Setup.parseFen(startFen), ignoreImpossibleCheck: true);
  final out = <String>[];
  for (final t in tokens) {
    var move = pos.parseSan(t);
    if (move == null && RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(t)) {
      move = pos.normalizeMove(Move.parse(t)! as NormalMove);
    }
    if (move == null || !pos.isLegal(move)) throw FormatException('Illegal move "$t" in $startFen after ${out.join(' ')}');
    out.add(move.uci);
    pos = pos.playUnchecked(move);
  }
  return out;
}

String _mirrorSquare(String sq) => '${sq[0]}${9 - int.parse(sq[1])}';

/// The same move with the board flipped vertically (a2a3 -> a7a6).
String mirrorUci(String uci) => '${_mirrorSquare(uci.substring(0, 2))}${_mirrorSquare(uci.substring(2, 4))}${uci.substring(4)}';

/// The same position with colours swapped: ranks reversed, piece colours and
/// side to move exchanged, castling rights and en passant square mirrored.
String mirrorFen(String fen) {
  final f = fen.split(' ');
  String swap(String c) => c == c.toUpperCase() ? c.toLowerCase() : c.toUpperCase();
  final board = f[0].split('/').reversed.map((r) => r.split('').map((c) => RegExp(r'[0-9]').hasMatch(c) ? c : swap(c)).join()).join('/');
  final side = f[1] == 'w' ? 'b' : 'w';
  var castling = f[2] == '-' ? '-' : f[2].split('').map(swap).toList().join();
  if (castling != '-') {
    final order = 'KQkqABCDEFGHabcdefgh';
    final chars = castling.split('')..sort((a, b) => order.indexOf(a).compareTo(order.indexOf(b)));
    castling = chars.join();
  }
  final ep = f[3] == '-' ? '-' : _mirrorSquare(f[3]);
  return [board, side, castling, ep, ...f.skip(4)].join(' ');
}
