import 'package:dartchess/dartchess.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

Position pos(String fen) => Position.setupPosition(Rule.chess, Setup.parseFen(fen));

NormalMove mv(Position p, String uci) => p.normalizeMove(Move.parse(uci)! as NormalMove) as NormalMove;

int see(String fen, String uci) {
  final p = pos(fen);
  final m = mv(p, uci);
  expect(p.isLegal(m), isTrue, reason: '$uci must be legal in $fen');
  return See.evaluate(p, m);
}

bool sac(String fen, String uci) {
  final p = pos(fen);
  return See.isSacrifice(p, mv(p, uci));
}

void main() {
  group('See.evaluate (classic exchanges)', () {
    test('undefended pawn: +1', () {
      expect(see('4k3/8/8/4p3/8/8/8/4R1K1 w - - 0 1', 'e1e5'), 1);
    });

    test('knight takes a pawn defended by a pawn: 1 - 3 = -2', () {
      expect(see('4k3/8/3p4/4p3/8/5N2/8/6K1 w - - 0 1', 'f3e5'), -2);
    });

    test('queen trade: 9 - 9 = 0', () {
      expect(see('3qk3/8/8/8/8/8/8/3QK3 w - - 0 1', 'd1d8'), 0);
    });

    test('pawn trade: 1 - 1 = 0', () {
      expect(see('4k3/8/4p3/3p4/4P3/8/8/4K3 w - - 0 1', 'e4d5'), 0);
    });

    test('x-ray: doubled rooks win a pawn defended by one rook (+1)', () {
      expect(see('4r1k1/8/8/4p3/8/8/4R3/4R1K1 w - - 0 1', 'e2e5'), 1);
    });

    test('without the second rook the same capture loses the exchange (1 - 5 = -4)', () {
      expect(see('4r1k1/8/8/4p3/8/8/4R3/6K1 w - - 0 1', 'e2e5'), -4);
    });

    test('the defender may decline a losing recapture', () {
      // Rxe5 wins the pawn; Black's rook would lose itself to the second rook.
      expect(see('4r1k1/8/8/4p3/8/8/4R3/4R1K1 w - - 0 1', 'e2e5'), greaterThan(0));
      // Bishop takes a pawn defended by a queen only: the queen recaptures
      // (gain 3), White has nothing left: 1 - 3 = -2.
      expect(see('3qk3/8/8/3p4/8/1B6/8/4K3 w - - 0 1', 'b3d5'), -2);
    });

    test('the king does not recapture on a defended square', () {
      // Qxf7+ with the bishop on c4 behind: Kxf7 is illegal.
      expect(see('6k1/5p2/8/8/2B5/8/8/5QK1 w - - 0 1', 'f1f7'), 1);
      // Without the bishop the king takes the queen: 1 - 9.
      expect(see('6k1/5p2/8/8/8/8/8/5QK1 w - - 0 1', 'f1f7'), -8);
    });

    test('en passant counts the captured pawn', () {
      expect(see('4k3/8/8/3pP3/8/8/8/4K3 w - d6 0 1', 'e5d6'), 1);
      expect(see('4k3/2p5/8/3pP3/8/8/8/4K3 w - d6 0 1', 'e5d6'), 0);
    });

    test('capture with promotion counts the new piece', () {
      expect(see('3r2k1/4P3/8/8/8/8/8/6K1 w - - 0 1', 'e7d8q'), 5 + 8);
      expect(see('3r2k1/4P3/8/8/8/8/8/6K1 w - - 0 1', 'e7d8n'), 5 + 2);
    });

    test('castling is not a capture', () {
      final p = pos('4k3/8/8/8/8/8/8/4K2R w K - 0 1');
      final castle = mv(p, 'e1h1');
      expect(See.evaluate(p, castle), 0);
      expect(See.capturedValue(p, castle), 0);
      expect(See.isCapture(p, castle), isFalse);
    });

    test('a quiet move onto an attacked square loses the piece', () {
      expect(see('4k3/8/5p2/8/8/8/3Q4/4K3 w - - 0 1', 'd2g5'), -9);
      expect(see('4k3/8/5p2/8/8/8/3Q4/4K3 w - - 0 1', 'd2d5'), 0);
    });
  });

  group('See.evaluate (pins)', () {
    const pinned = '2k5/8/4p3/3n4/6B1/8/8/K2R4 w - - 0 1';

    test('an absolutely pinned pawn cannot recapture: Rxd5 wins the knight', () {
      expect(see(pinned, 'd1d5'), 3);
      expect(sac(pinned, 'd1d5'), isFalse);
    });

    test('colour symmetry: the mirrored position gives the same result', () {
      expect(see('k2r4/8/8/6b1/3N4/4P3/8/2K5 b - - 0 1', 'd8d4'), 3);
      expect(sac('k2r4/8/8/6b1/3N4/4P3/8/2K5 b - - 0 1', 'd8d4'), isFalse);
    });

    test('without the pinning bishop the pawn recaptures: 3 - 5 = -2', () {
      expect(see('2k5/8/4p3/3n4/8/8/8/K2R4 w - - 0 1', 'd1d5'), -2);
      expect(sac('2k5/8/4p3/3n4/8/8/8/K2R4 w - - 0 1', 'd1d5'), isTrue);
    });

    test('a pinned piece may still capture the pinner along the pin line', () {
      // Rxa3 pins the a5 rook against the a8 king, but Rxa3 is along the pin: 1 - 5.
      expect(see('k7/8/8/r7/8/pR6/8/6K1 w - - 0 1', 'b3a3'), -4);
    });

    test('a pinned defender off the pin line does not defend (second step of the exchange)', () {
      // Black Rf7 is pinned to Kg8 by Bc4 and cannot retake on f5: Nxf5 wins the pawn.
      expect(see('6k1/5r2/8/5p2/2BN4/8/8/6K1 w - - 0 1', 'd4f5'), 1);
      // Without the bishop the rook recaptures: 1 - 3.
      expect(see('6k1/5r2/8/5p2/3N4/8/8/6K1 w - - 0 1', 'd4f5'), -2);
    });
  });

  group('See promotions (quiet)', () {
    const quiet = 'r5k1/3P4/8/8/8/8/6PP/6K1 w - - 0 1';

    test('a quiet promotion that is recaptured costs the pawn only', () {
      expect(see(quiet, 'd7d8q'), -1);
      expect(sac(quiet, 'd7d8q'), isFalse);
    });

    test('mirrored (Black promotes)', () {
      const mirrored = '6k1/6pp/8/8/8/8/3p4/R5K1 b - - 0 1';
      expect(see(mirrored, 'd2d1q'), -1);
      expect(sac(mirrored, 'd2d1q'), isFalse);
    });

    test('a capturing promotion still counts as a capture', () {
      expect(see('2r3k1/3P4/8/8/8/8/6PP/6K1 w - - 0 1', 'd7c8q'), 5 + 8);
    });

    test('a promotion that leaves a queen hanging elsewhere is still a sacrifice', () {
      // a8=N gains only 2, while the a1 queen can be taken by the h8 bishop.
      const fen = '4k2b/P7/8/8/8/8/8/Q3K3 w - - 0 1';
      final p = pos(fen);
      expect(See.isSacrifice(p, NormalMove(from: Square.fromName('a7'), to: Square.fromName('a8'), promotion: Role.knight)), isTrue);
      expect(See.isSacrifice(p, NormalMove(from: Square.fromName('a7'), to: Square.fromName('a8'), promotion: Role.queen)), isFalse,
          reason: 'the promotion gain (8) exceeds the queen at risk (9) by less than 2');
    });
  });

  group('See.isSacrifice (SPEC 2.1 Brilliant 2, trap 6)', () {
    test('Greek gift Bxh7+ is a sacrifice', () {
      expect(sac('r1bq1rk1/pppn1ppp/4p3/3pP3/1b1P4/2NB1N2/PPP2PPP/R1BQK2R w KQ - 0 1', 'd3h7'), isTrue);
    });

    test('leaving the queen en prise is a sacrifice', () {
      expect(sac('4k3/8/5p2/8/8/8/3Q4/4K3 w - - 0 1', 'd2g5'), isTrue);
    });

    test('queen trade, recapture and pawn trade are never sacrifices', () {
      expect(sac('3qk3/8/8/8/8/8/8/3QK3 w - - 0 1', 'd1d8'), isFalse, reason: 'queen trade');
      expect(sac('4k3/8/4p3/3P4/8/8/8/4K3 b - - 0 1', 'e6d5'), isFalse, reason: 'recapture');
      expect(sac('4k3/8/4p3/3p4/4P3/8/8/4K3 w - - 0 1', 'e4d5'), isFalse, reason: 'pawn trade');
    });

    test('a safe quiet move is not a sacrifice', () {
      expect(sac('4k3/8/5p2/8/8/8/3Q4/4K3 w - - 0 1', 'd2d5'), isFalse);
    });

    test('grabbing a pawn while leaving a rook to be taken is a sacrifice', () {
      // Nxe4 wins a pawn but uncovers the a1 rook to the h8 bishop: 5 - 1.
      expect(sac('4k2b/8/8/8/4p3/2N5/8/R3K3 w - - 0 1', 'c3e4'), isTrue);
    });
  });

  test('hangingPieces lists pieces the opponent wins with a capture', () {
    final p = pos('4k3/8/5p2/6Q1/8/8/8/4K3 b - - 0 1');
    expect(See.hangingPieces(p, Side.white), [(Square.fromName('g5'), Role.queen)]);
    expect(See.hangingPieces(p, Side.black), [(Square.fromName('f6'), Role.pawn)], reason: 'Qxf6 wins the pawn');
  });

  test('piece values (SPEC 2.1)', () {
    expect([for (final r in [Role.pawn, Role.knight, Role.bishop, Role.rook, Role.queen]) See.value(r)], [1, 3, 3, 5, 9]);
  });
}
