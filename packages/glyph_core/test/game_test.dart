import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

Game game(String pgn) => parsePgn(pgn).games.single;

void main() {
  group('detectUserSide', () {
    final lichess = game('[Site "https://lichess.org/AbCdEfGh"]\n[White "DrNykterstein"]\n[Black "Hikaru"]\n\n1. e4 *');
    final chessCom = game('[Site "Chess.com"]\n[White "Hikaru"]\n[Black "someoneElse"]\n\n1. e4 *');
    final local = game('[Site "?"]\n[White "Alice"]\n[Black "Bob"]\n\n1. e4 *');

    test('case-insensitive header match', () {
      expect(detectUserSide(lichess, lichessUsername: 'drnykterstein'), Side.white);
      expect(detectUserSide(lichess, lichessUsername: 'HIKARU'), Side.black);
      expect(detectUserSide(chessCom, chessComUsername: 'hikaru'), Side.white);
      expect(detectUserSide(chessCom, chessComUsername: 'SOMEONEELSE'), Side.black);
    });

    test('site decides which account applies', () {
      // "Hikaru" configured as the *lichess* name does not match a chess.com game.
      expect(detectUserSide(chessCom, lichessUsername: 'Hikaru'), isNull);
      expect(detectUserSide(lichess, chessComUsername: 'DrNykterstein'), isNull);
    });

    test('unknown site: either account matches', () {
      expect(detectUserSide(local, lichessUsername: 'bob'), Side.black);
      expect(detectUserSide(local, chessComUsername: 'ALICE'), Side.white);
    });

    test('no match, empty names and ambiguity give null', () {
      expect(detectUserSide(local), isNull);
      expect(detectUserSide(local, lichessUsername: '  ', chessComUsername: ''), isNull);
      expect(detectUserSide(local, lichessUsername: 'Carol'), isNull);
      expect(detectUserSide(local, lichessUsername: 'Alice', chessComUsername: 'Bob'), isNull);
      final mirror = game('[White "Zed"]\n[Black "zed"]\n\n1. e4 *');
      expect(detectUserSide(mirror, lichessUsername: 'ZED'), isNull);
    });
  });

  group('Game accessors', () {
    test('unknown markers become null', () {
      final g = game('[White "?"]\n[Black "-"]\n[Date "????.??.??"]\n[WhiteElo "?"]\n[BlackElo "0"]\n\n1. e4 *');
      expect(g.white, isNull);
      expect(g.black, isNull);
      expect(g.date, isNull);
      expect(g.whiteElo, isNull);
      expect(g.blackElo, isNull);
    });

    test('date falls back to UTCDate', () {
      expect(game('[UTCDate "2023.07.01"]\n\n1. e4 *').date, '2023.07.01');
    });
  });

  group('MainlineCursor', () {
    final g = game('1. e4 e5 2. Nf3 Nc6 3. Bb5 *');
    test('walks the mainline and clamps', () {
      final c = MainlineCursor(g);
      expect((c.ply, c.length, c.canBack, c.canForward, c.lastMove), (0, 5, false, true, null));
      expect(c.position.fen, g.startFen);
      c.next();
      expect(c.position.fen, g.plies[0].fen);
      expect(c.lastMove?.uci, 'e2e4');
      c.last();
      expect((c.ply, c.canForward), (5, false));
      expect(c.position.fen, g.plies.last.fen);
      c.next();
      expect(c.ply, 5);
      c.goTo(2);
      expect(c.position.fen, g.plies[1].fen);
      c.back();
      c.back();
      c.back();
      expect(c.ply, 0);
      c.first();
      expect(MainlineCursor(g, ply: 3).position.fen, g.plies[2].fen);
    });

    test('works from a FEN start (Chess960)', () {
      final p = game('[Variant "Chess960"]\n[SetUp "1"]\n[FEN "brnkqbnr/pppppppp/8/8/8/8/PPPPPPPP/BRNKQBNR w KQkq - 0 1"]\n\n1. e4 b5 *');
      final c = MainlineCursor(p)..last();
      expect(c.position.fen, p.plies.last.fen);
    });
  });
}
