// Regenerates the synthetic PGN fixtures in test/vectors/pgn/ (deterministic).
// Real data comes from docs/m0/lichess_sample.ndjson and docs/m0/chesscom_sample.json.
//
//   cd packages/glyph_core && dart run tool/gen_pgn_fixtures.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dartchess/dartchess.dart' hide File;

const outDir = 'test/vectors/pgn';

void write(String name, String content) =>
    File('$outDir/$name').writeAsStringSync(content);

/// A random but legal game (seeded), as a PGN with optional clock comments.
String randomGame(Random rnd, int n) {
  final white = ['Alice', 'Boris', 'Chen', 'Dara', 'Elif', 'Farid', 'Greta', 'Hugo'][rnd.nextInt(8)];
  final black = ['Ines', 'Jun', 'Kofi', 'Lena', 'Mateo', 'Nora', 'Omar', 'Petra'][rnd.nextInt(8)];
  Position pos = Chess.initial;
  final sans = <String>[];
  final target = 20 + rnd.nextInt(80);
  while (sans.length < target && !pos.isGameOver) {
    final moves = <Move>[];
    for (final e in pos.legalMoves.entries) {
      for (final to in e.value.squares) {
        final isPawn = pos.board.roleAt(e.key) == Role.pawn;
        final lastRank = to.rank == Rank.first || to.rank == Rank.eighth;
        moves.add(NormalMove(from: e.key, to: to, promotion: isPawn && lastRank ? Role.queen : null));
      }
    }
    final move = moves[rnd.nextInt(moves.length)];
    final (next, san) = pos.makeSan(move);
    sans.add(san);
    pos = next;
  }
  final result = pos.outcome == null
      ? ['1-0', '0-1', '1/2-1/2'][rnd.nextInt(3)]
      : Outcome.toPgnString(pos.outcome);
  final withClock = n.isEven;
  final b = StringBuffer()
    ..writeln('[Event "Club Rapid Open"]')
    ..writeln('[Site "https://example.org/g/${1000 + n}"]')
    ..writeln('[Date "2026.0${1 + n % 9}.${10 + n % 18}"]')
    ..writeln('[Round "${1 + n}"]')
    ..writeln('[White "$white"]')
    ..writeln('[Black "$black"]')
    ..writeln('[Result "$result"]')
    ..writeln('[WhiteElo "${1400 + rnd.nextInt(800)}"]')
    ..writeln('[BlackElo "${1400 + rnd.nextInt(800)}"]')
    ..writeln('[TimeControl "600+5"]')
    ..writeln()
    ..write(_movetext(sans, withClock, rnd))
    ..writeln(' $result');
  return b.toString();
}

String _movetext(List<String> sans, bool withClock, Random rnd) {
  final b = StringBuffer();
  var wClock = 600000, bClock = 600000;
  for (var i = 0; i < sans.length; i++) {
    if (i.isEven) b.write('${i ~/ 2 + 1}. ');
    b.write(sans[i]);
    if (withClock) {
      final spent = 500 + rnd.nextInt(9000);
      if (i.isEven) {
        wClock = max(1000, wClock - spent + 5000);
      } else {
        bClock = max(1000, bClock - spent + 5000);
      }
      final c = i.isEven ? wClock : bClock;
      final h = c ~/ 3600000, m = (c ~/ 60000) % 60, s = (c ~/ 1000) % 60, t = (c % 1000) ~/ 100;
      b.write(' {[%clk $h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}${t == 0 ? '' : '.$t'}]}');
    }
    b.write(i == sans.length - 1 ? '' : ' ');
  }
  return b.toString();
}

void main() {
  final rnd = Random(2026);

  // Real data from the M0 samples.
  final lichess = File('../../docs/m0/lichess_sample.ndjson')
      .readAsLinesSync()
      .where((l) => l.isNotEmpty)
      .map((l) => jsonDecode(l) as Map<String, dynamic>)
      .toList();
  final chesscom = (jsonDecode(File('../../docs/m0/chesscom_sample.json').readAsStringSync())
      as Map<String, dynamic>)['games'] as List<dynamic>;
  final li0 = lichess[0]['pgn'] as String; // standard, %eval + %clk + Opening
  final li1 = lichess[1]['pgn'] as String; // Chess960, [SetUp][FEN], castling
  final cc0 = (chesscom[0] as Map<String, dynamic>)['pgn'] as String;
  final cc1 = (chesscom[1] as Map<String, dynamic>)['pgn'] as String;

  write('chesscom_download_clk.pgn', cc0);
  write('chesscom_app_share.pgn',
      'Check out my game on Chess.com!\nhttps://www.chess.com/game/live/185962590893\n\n$cc1');
  write('lichess_api_export.pgn', li0);
  write('chess960_fen.pgn', li1);

  // lichess app "share PGN": no comments, one movetext paragraph.
  final g = PgnGame.parsePgn(li0, initHeaders: PgnGame.emptyHeaders);
  final keep = ['Event', 'Site', 'Date', 'Round', 'White', 'Black', 'Result', 'WhiteElo',
      'BlackElo', 'Variant', 'TimeControl', 'ECO', 'Opening', 'Termination'];
  final sans = g.moves.mainline().map((d) => d.san).toList();
  final share = StringBuffer();
  for (final k in keep) {
    if (g.headers.containsKey(k)) share.writeln('[$k "${g.headers[k]}"]');
  }
  share
    ..writeln()
    ..writeln('${_movetext(sans, false, rnd)} ${g.headers['Result']}');
  write('lichess_app_share.pgn', share.toString());

  final fifty = [for (var i = 0; i < 50; i++) randomGame(rnd, i)];
  write('fifty_games.pgn', fifty.join('\n'));
  write('no_blank_lines.pgn', fifty.take(3).join());

  // CRLF + BOM (bytes).
  File('$outDir/crlf_bom.pgn').writeAsBytesSync(
    [0xEF, 0xBB, 0xBF, ...utf8.encode(li0.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n'))],
  );

  // An illegal move: cc0's 14th white move (Bxc4) replaced by "Nxe5".
  final bad = cc0.replaceFirst('14. Bxc4', '14. Nxe5');
  assert(bad != cc0);
  write('illegal_move_single.pgn', bad);
  write('illegal_move_in_multi.pgn', '${fifty[0]}\n$bad\n${fifty[1]}');

  write('crazyhouse.pgn', '''
[Event "Rated Crazyhouse game"]
[Site "https://lichess.org/Zq81hVqK"]
[Date "2026.09.14"]
[White "player_white"]
[Black "player_black"]
[Result "0-1"]
[Variant "Crazyhouse"]
[TimeControl "180+0"]

1. e4 e5 2. Nf3 Nc6 3. Bc4 Nf6 4. Ng5 d5 5. exd5 Nxd5 6. Nxf7 Kxf7 7. Qf3+ Ke6 8. Nc3 Nb4 9. N@d5 Nxd5 10. Nxd5 Kd6 0-1
''');
  write('crazyhouse_mixed.pgn', '${fifty[2]}\n${File('$outDir/crazyhouse.pgn').readAsStringSync()}\n${fifty[3]}');

  write('zero_moves.pgn', '''
[Event "Casual game"]
[Site "?"]
[Date "2026.10.01"]
[Round "-"]
[White "Alice"]
[Black "Boris"]
[Result "*"]

*
''');
  stdout.writeln('done');
}
