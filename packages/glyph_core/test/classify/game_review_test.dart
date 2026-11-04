import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import '../support/review.dart';
import '../support/transcripts.dart';

EngineLine line(int rank, int cp, List<String> pv) => EngineLine(rank: rank, score: WhiteScore.cp(cp), depth: 16, pv: pv);

void main() {
  group('reviewGame (ClassifyGame + ComputeAccuracy)', () {
    test('Opera game: labels, accuracy, key moments, opening', () async {
      final g = transcriptGame('mate_opera');
      final lines = await analyseFromTranscript('mate_opera', startFen: g.startFen, moves: g.moves);
      final review = reviewGame(gameFrom(g.startFen, g.moves), lines, book: realOpeningBook());
      expect(review.moves, hasLength(33));
      expect(review.moves.every((m) => m != null), isTrue);
      expect(review.book.bookPlies, 7);
      expect(review.opening!.eco, 'C41');
      expect(review.opening!.name, startsWith('Philidor Defense'));
      expect(review.classifierVersion, ClassifierConfig.standard.version);

      final white = review.counts(Side.white);
      final black = review.counts(Side.black);
      expect(white.values.fold(0, (a, b) => a + b), 17);
      expect(black.values.fold(0, (a, b) => a + b), 16);
      expect(white[MoveLabel.brilliant], 1);
      expect(black[MoveLabel.forced], 1);

      // Morphy played almost perfectly; the Duke and Count did not.
      expect(review.accuracy.white!, greaterThan(90));
      expect(review.accuracy.black!, lessThan(review.accuracy.white!));

      final km = review.keyMoments;
      expect(km.map((m) => m.ply), containsAll([12, 18, 19, 25]));
      expect(km.every((m) => KeyMoments.labels.contains(m.label)), isTrue);
      expect(KeyMoments.ofSide(km, Side.white).every((m) => m.side == Side.white), isTrue);
      final top = KeyMoments.mostSignificant(km, limit: 3);
      expect(top, hasLength(3));
      expect(top.map((m) => m.label), containsAll([MoveLabel.brilliant, MoveLabel.great]));
      expect([for (final m in top) m.ply], orderedEquals([...top.map((m) => m.ply)]..sort()));
    });

    test('Chess960 game: no book, castling classified, accuracy for both', () async {
      final g = transcriptGame('lichess_PXXPWDlC_960');
      final lines = await analyseFromTranscript(g.name, startFen: g.startFen, moves: g.moves);
      final review = reviewGame(gameFrom(g.startFen, g.moves, variant: GameVariant.chess960), lines, book: realOpeningBook());
      expect(review.book.bookPlies, 0);
      expect(review.opening, isNull);
      expect(review.moves.every((m) => m != null && m.label != MoveLabel.book), isTrue);
      expect(review.moves[16]!.isTopMove, isFalse, reason: '9.O-O');
      // lichess's server analysis of this game: 86 / 78. Glyph's own engine
      // (another Stockfish, another depth) lands close by.
      expect(review.accuracy.white!, closeTo(86, 8));
      expect(review.accuracy.black!, closeTo(78, 8));
    });

    test('missing engine data leaves the move unlabelled (and still Book in book)', () {
      final moves = sanOrUciToUci(kInitialFENForTests, ['e4', 'e5', 'Nf3']);
      final lines = {
        0: [line(1, 30, ['e2e4']), line(2, 20, ['d2d4'])],
        1: [line(1, 30, ['e7e5'])],
        // positions 2 and 3 missing
      };
      final review = reviewGame(gameFrom(kInitialFENForTests, moves), lines, book: realOpeningBook());
      expect(review.moves[0]!.label, MoveLabel.book);
      expect(review.moves[1]!.label, MoveLabel.book, reason: 'Book needs no engine data');
      expect(review.moves[1]!.epLoss, 0);
      expect(review.moves[2]!.label, MoveLabel.book);
      expect(review.moves[2]!.epLoss, isNull);
      final noBook = reviewGame(gameFrom(kInitialFENForTests, moves), lines);
      expect(noBook.moves[0]!.label, MoveLabel.best);
      expect(noBook.moves[2], isNull);
    });

    test('a final position at the 50-move counter is a draw (W 50)', () {
      // White is a rook up, the counter stands at 99: any quiet move ends the game.
      const fen = '7k/8/8/8/8/8/8/R5K1 w - - 99 120';
      final moves = ['g1g2'];
      final wins = Classifier.positionWins(fen, moves, {
        0: [line(1, 900, ['a1a7'])],
        1: [line(1, 900, ['h8g8'])],
      });
      expect(wins[1].drawnByRule, isTrue);
      expect(wins[1].whiteWin, 50);
      final m = const Classifier().classify(startFen: fen, moves: moves, lines: {
        0: [line(1, 900, ['a1a7'])],
        1: [line(1, 900, ['h8g8'])],
      }).single!;
      expect(m.label, MoveLabel.blunder);
    });

    test('a threefold repetition that is not the final position is not a draw', () {
      final g = transcriptGame('repetition_winning');
      final wins = Classifier.positionWins(g.startFen, [...g.moves, 'h8h7'], {});
      expect(wins[8].drawnByRule, isFalse, reason: 'the game went on');
      expect(wins[9].drawnByRule, isFalse);
    });

    test('ClassifierConfig: a stricter Good band turns a Good into an Inaccuracy', () async {
      final g = transcriptGame('italian_castle');
      final lines = await analyseFromTranscript(g.name, startFen: g.startFen, moves: g.moves);
      const strict = ClassifierConfig(version: 99, goodMaxLoss: 0.02);
      final normal = const Classifier().classify(startFen: g.startFen, moves: g.moves, lines: lines)[10]!;
      final stricter = const Classifier(config: strict).classify(startFen: g.startFen, moves: g.moves, lines: lines)[10]!;
      expect(normal.label, MoveLabel.good);
      expect(stricter.label, MoveLabel.inaccuracy);
    });
  });

  test('engineLineFromStored: terminal marker row is null, pv split', () {
    expect(engineLineFromStored(rank: 1, depth: 0, pvUci: ''), isNull);
    final l = engineLineFromStored(rank: 2, scoreMate: -3, depth: 16, pvUci: 'e2e4 e7e5')!;
    expect((l.rank, l.score, l.depth), (2, const WhiteScore.mate(-3), 16));
    expect(l.pv, ['e2e4', 'e7e5']);
    expect(engineLineFromStored(rank: 1, scoreCp: 12, depth: 9, pvUci: '')!.pv, isEmpty);
  });
}

const kInitialFENForTests = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
