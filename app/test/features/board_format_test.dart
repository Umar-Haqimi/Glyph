import 'package:dartchess/dartchess.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/board/board_format.dart';
import 'package:glyph_core/glyph_core.dart';

Position _fen(String fen) => Position.setupPosition(Rule.chess, Setup.parseFen(fen));

void main() {
  group('formatScore', () {
    test('centipawns in pawns with one decimal and a sign', () {
      expect(formatScore(const WhiteScore.cp(130)), '+1.3');
      expect(formatScore(const WhiteScore.cp(-40)), '-0.4');
      expect(formatScore(const WhiteScore.cp(0)), '0.0');
      expect(formatScore(const WhiteScore.cp(4)), '0.0');
      expect(formatScore(const WhiteScore.cp(5)), '+0.1');
      expect(formatScore(const WhiteScore.cp(-5)), '-0.1');
      expect(formatScore(const WhiteScore.cp(1234)), '+12.3');
    });

    test('mates: #N for White, -#N for Black (White POV)', () {
      expect(formatScore(const WhiteScore.mate(4)), '#4');
      expect(formatScore(const WhiteScore.mate(-2)), '-#2');
      expect(formatScore(const WhiteScore.mate(1)), '#1');
    });
  });

  group('castling on the board (Chess960 king-takes-rook)', () {
    test('standard king: e1h1 is drawn e1-g1, e1a1 e1-c1', () {
      final p = _fen('r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1');
      final short = displaySquares(p, const NormalMove(from: Square.e1, to: Square.h1));
      expect((short.from, short.to), (Square.e1, Square.g1));
      final long = displaySquares(p, const NormalMove(from: Square.e1, to: Square.a1));
      expect((long.from, long.to), (Square.e1, Square.c1));
      final black = _fen('r3k2r/8/8/8/8/8/8/R3K2R b KQkq - 0 1');
      expect(displaySquares(black, const NormalMove(from: Square.e8, to: Square.h8)).to, Square.g8);
      expect(displaySquares(black, const NormalMove(from: Square.e8, to: Square.a8)).to, Square.c8);
    });

    test('Chess960 king on b1: b1h1 lands on g1, b1a1 on c1', () {
      final p = _fen('4k3/8/8/8/8/8/8/RK5R w AH - 0 1');
      expect(displaySquares(p, const NormalMove(from: Square.b1, to: Square.h1)).to, Square.g1);
      expect(displaySquares(p, const NormalMove(from: Square.b1, to: Square.a1)).to, Square.c1);
    });

    test('Chess960 king that stays on g1: the king\'s square (the rook\'s origin is empty afterwards)', () {
      final p = _fen('4k3/8/8/8/8/8/8/5RKR w FH - 0 1');
      final d = displaySquares(p, const NormalMove(from: Square.g1, to: Square.h1));
      expect((d.from, d.to), (Square.g1, Square.g1));
      // Queenside, king already on c8: the king stays on c8 as well.
      final q = _fen('r1k5/8/8/8/8/8/8/4K3 b a - 0 1');
      final e = displaySquares(q, const NormalMove(from: Square.c8, to: Square.a8));
      expect((e.from, e.to), (Square.c8, Square.c8));
    });

    test('ordinary moves and captures of an enemy rook are untouched', () {
      final p = _fen('r3k3/8/8/8/8/8/8/R3K2R w KQ - 0 1');
      final d = displaySquares(p, const NormalMove(from: Square.a1, to: Square.a8));
      expect((d.from, d.to), (Square.a1, Square.a8));
      // A king capturing an enemy rook is not castling.
      final q = _fen('4k3/8/8/8/8/8/4r3/4K3 w - - 0 1');
      expect(displaySquares(q, const NormalMove(from: Square.e1, to: Square.e2)).to, Square.e2);
    });

    test('SAN of a king-takes-rook principal variation', () {
      final p = _fen('r3k2r/pppppppp/8/8/8/8/PPPPPPPP/R3K2R w KQkq - 0 1');
      expect(pvToSan(p, ['e1h1', 'e8a8']), ['O-O', 'O-O-O']);
      expect(formatMoveSequence(p, pvToSan(p, ['e1h1', 'e8a8'])), '1. O-O O-O-O');
      final b = _fen('4k3/8/8/8/8/8/8/RK5R w AH - 0 1');
      expect(pvToSan(b, ['b1h1']).single, startsWith('O-O'));
    });
  });

  group('pv to SAN', () {
    test('stops at the first illegal or malformed move', () {
      final p = Chess.initial;
      expect(pvToSan(p, ['e2e4', 'e7e5', 'e2e4', 'g1f3']), ['e4', 'e5']);
      expect(pvToSan(p, ['zz', 'e2e4']), isEmpty);
      expect(pvToSan(p, ['e']), isEmpty);
      expect(pvToSan(p, const []), isEmpty);
      expect(pvToSan(p, ['e2e4', 'e7e5', 'g1f3'], maxMoves: 2), ['e4', 'e5']);
    });

    test('move numbers and the Black-first ellipsis', () {
      final p = Chess.initial;
      expect(formatMoveSequence(p, ['e4', 'e5', 'Nf3']), '1. e4 e5 2. Nf3');
      final afterE4 = p.play(const NormalMove(from: Square.e2, to: Square.e4));
      expect(formatMoveSequence(afterE4, ['e5', 'Nf3']), '1… e5 2. Nf3');
      expect(formatMoveSequence(p, const []), '');
      expect(moveNumberLabel(p), '1.');
      expect(moveNumberLabel(afterE4), '1…');
      expect(formatMove(afterE4, 'e5'), '1… e5');
    });
  });

  group('clocks', () {
    test('format', () {
      expect(formatClock(298500), '4:58');
      expect(formatClock(3 * 3600 * 1000 + 5 * 60 * 1000 + 9000), '3:05:09');
      expect(formatClock(7400), '0:07.4');
      expect(formatClock(0), '0:00.0');
      expect(formatClock(-5), '0:00.0');
    });

    test('base time of a time control', () {
      expect(baseTimeMs('600+5'), 600000);
      expect(baseTimeMs('180'), 180000);
      expect(baseTimeMs('1/86400'), isNull);
      expect(baseTimeMs('-'), isNull);
      expect(baseTimeMs(null), isNull);
    });
  });
}
