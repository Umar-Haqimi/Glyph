import 'package:dartchess/dartchess.dart';

import '../game/ply.dart';

/// Builds the `epd\teco\tname` asset from the lichess chess-openings TSVs
/// (`eco\tname\tpgn`, header row first) by replaying each line with dartchess.
///
/// [tsvFiles] are the raw contents of `a.tsv` .. `e.tsv` in that order. Throws
/// [FormatException] on an unreadable row or a duplicate EPD, so a bad upstream
/// snapshot fails the build instead of shipping a wrong book.
String buildOpeningsTsv(Iterable<String> tsvFiles) {
  final seen = <String, String>{};
  final out = StringBuffer();
  for (final file in tsvFiles) {
    final lines = file.split('\n');
    for (var i = 1; i < lines.length; i++) {
      final line = lines[i].trimRight();
      if (line.isEmpty) continue;
      final f = line.split('\t');
      if (f.length != 3) throw FormatException('Bad openings row: $line');
      final (eco, name, pgn) = (f[0], f[1], f[2]);
      Position pos = Chess.initial;
      for (final token in pgn.split(RegExp(r'\s+'))) {
        if (token.isEmpty || RegExp(r'^\d+\.+$').hasMatch(token)) continue;
        final move = pos.parseSan(token);
        if (move == null) throw FormatException('Illegal move $token in: $line');
        pos = pos.play(move);
      }
      final epd = epdOfFen(pos.fen);
      final previous = seen[epd];
      if (previous != null) {
        throw FormatException('Duplicate EPD $epd: "$previous" and "$name"');
      }
      seen[epd] = name;
      out.write('$epd\t$eco\t$name\n');
    }
  }
  return out.toString();
}
