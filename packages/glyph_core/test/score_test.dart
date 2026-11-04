import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

void main() {
  group('toWhitePov (SPEC trap 1, P0)', () {
    test('centipawns: unchanged for White to move, negated for Black', () {
      expect(toWhitePov(const Score.cp(35), Side.white), const WhiteScore.cp(35));
      expect(toWhitePov(const Score.cp(35), Side.black), const WhiteScore.cp(-35));
      expect(toWhitePov(const Score.cp(-120), Side.black), const WhiteScore.cp(120));
      expect(toWhitePov(const Score.cp(0), Side.black), const WhiteScore.cp(0));
    });

    test('mate: positive = White mates', () {
      expect(toWhitePov(const Score.mate(3), Side.white), const WhiteScore.mate(3));
      expect(toWhitePov(const Score.mate(3), Side.black), const WhiteScore.mate(-3));
      expect(toWhitePov(const Score.mate(-2), Side.white), const WhiteScore.mate(-2));
      expect(toWhitePov(const Score.mate(-2), Side.black), const WhiteScore.mate(2));
    });

    test('mate 0: the winner is the side that is not to move', () {
      expect(toWhitePov(const Score.mate(0), Side.white).mateWinner, Side.black);
      expect(toWhitePov(const Score.mate(0), Side.black).mateWinner, Side.white);
    });

    test('flipping twice is the identity for every side', () {
      for (final s in [const Score.cp(77), const Score.cp(-5), const Score.mate(4), const Score.mate(-1)]) {
        for (final side in Side.values) {
          final w = toWhitePov(s, side);
          final back = toWhitePov(
            w.isMate ? Score.mate(side == Side.white ? w.mate! : -w.mate!) : Score.cp(side == Side.white ? w.cp! : -w.cp!),
            side,
          );
          expect(back, w);
        }
      }
    });

    test('mateWinner and fromStored', () {
      expect(const WhiteScore.mate(2).mateWinner, Side.white);
      expect(const WhiteScore.mate(-2).mateWinner, Side.black);
      expect(const WhiteScore.cp(9).mateWinner, isNull);
      expect(WhiteScore.fromStored(cp: 5), const WhiteScore.cp(5));
      expect(WhiteScore.fromStored(mate: -3), const WhiteScore.mate(-3));
      expect(WhiteScore.fromStored(), isNull);
    });
  });
}
