import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

UciSearchResult? run(UciParser p, List<String> lines) {
  UciSearchResult? r;
  for (final l in lines) {
    r = p.feed(l) ?? r;
  }
  return r;
}

void main() {
  group('parseUciInfoLine', () {
    test('full line', () {
      final i = parseUciInfoLine(
          'info depth 12 seldepth 21 multipv 2 score cp 17 nodes 41218 nps 368017 hashfull 13 tbhits 0 time 112 pv f3g5 d7d5 e4d5')!;
      expect(i.depth, 12);
      expect(i.seldepth, 21);
      expect(i.multipv, 2);
      expect(i.score, const Score.cp(17));
      expect(i.exact, isTrue);
      expect(i.pv, ['f3g5', 'd7d5', 'e4d5']);
      expect(i.nodes, 41218);
    });

    test('multipv defaults to 1, mate scores', () {
      final i = parseUciInfoLine('info depth 3 score mate -2 pv e8e7')!;
      expect(i.multipv, 1);
      expect(i.score, const Score.mate(-2));
    });

    test('non-score lines are null', () {
      expect(parseUciInfoLine('info string NNUE evaluation using nn-1a298aa575a0.nnue'), isNull);
      expect(parseUciInfoLine('info depth 5 currmove e2e4 currmovenumber 1'), isNull);
      expect(parseUciInfoLine('info depth 5 nodes 1000 nps 1000'), isNull);
      expect(parseUciInfoLine('uciok'), isNull);
      expect(parseUciInfoLine('bestmove e2e4'), isNull);
      expect(parseUciInfoLine(''), isNull);
    });

    test('bound flags', () {
      expect(parseUciInfoLine('info depth 9 multipv 1 score cp 40 lowerbound pv e2e4')!.exact, isFalse);
      expect(parseUciInfoLine('info depth 9 multipv 1 score cp -40 upperbound pv e2e4')!.exact, isFalse);
    });
  });

  group('UciParser', () {
    test('lowerbound / upperbound scores are skipped', () {
      final p = UciParser(sideToMove: Side.white);
      final r = run(p, [
        'info depth 10 multipv 1 score cp 30 pv e2e4 e7e5',
        'info depth 11 multipv 1 score cp 80 lowerbound pv d2d4',
        'info depth 11 multipv 1 score cp -10 upperbound pv d2d4',
        'info depth 11 multipv 1 score cp 33 pv e2e4 c7c5',
        'bestmove e2e4 ponder c7c5',
      ])!;
      expect(r.lines.single.score, const WhiteScore.cp(33));
      expect(r.lines.single.depth, 11);
      expect(r.bestMove, 'e2e4');
      expect(r.ponder, 'c7c5');
    });

    test('only bounds at the last depth: previous exact depth wins', () {
      final r = run(UciParser(sideToMove: Side.white), [
        'info depth 10 multipv 1 score cp 30 pv e2e4',
        'info depth 11 multipv 1 score cp 99 lowerbound pv d2d4',
        'bestmove e2e4',
      ])!;
      expect(r.lines.single.score, const WhiteScore.cp(30));
      expect(r.depth, 10);
    });

    test('currmove and info string are ignored', () {
      final r = run(UciParser(sideToMove: Side.white), [
        'info string Available processors: 0-7',
        'info depth 1 currmove e2e4 currmovenumber 1',
        'info depth 5 multipv 1 score cp 12 pv e2e4',
        'info depth 5 currmove d2d4 currmovenumber 2',
        'info string NNUE evaluation using x.nnue',
        'bestmove e2e4',
      ])!;
      expect(r.lines, hasLength(1));
      expect(r.lines.single.score, const WhiteScore.cp(12));
    });

    test('interleaved multipv lines and a later depth overwrite earlier ones', () {
      final r = run(UciParser(sideToMove: Side.white), [
        'info depth 9 multipv 1 score cp 10 pv a2a3',
        'info depth 9 multipv 2 score cp 5 pv b2b3',
        'info depth 10 multipv 2 score cp 7 pv b2b3 e7e5',
        'info depth 10 multipv 1 score cp 12 pv a2a3 e7e5',
        'info depth 10 multipv 1 score cp 13 pv a2a3 e7e5 c2c3',
        'bestmove a2a3',
      ])!;
      expect([for (final l in r.lines) l.rank], [1, 2]);
      expect(r.lines[0].score, const WhiteScore.cp(13));
      expect(r.lines[0].pv, ['a2a3', 'e7e5', 'c2c3']);
      expect(r.lines[1].score, const WhiteScore.cp(7));
      expect(r.depth, 10);
    });

    test('highest completed depth: a depth with only rank 1 is not used', () {
      final r = run(UciParser(sideToMove: Side.white), [
        'info depth 9 multipv 1 score cp 10 pv a2a3',
        'info depth 9 multipv 2 score cp 5 pv b2b3',
        'info depth 10 multipv 1 score cp 12 pv a2a3', // stopped before rank 2 of depth 10
        'bestmove a2a3',
      ])!;
      expect(r.depth, 9);
      expect(r.lines.map((l) => l.score), [const WhiteScore.cp(10), const WhiteScore.cp(5)]);
    });

    test('scores are converted to White POV for Black to move', () {
      final r = run(UciParser(sideToMove: Side.black), [
        'info depth 8 multipv 1 score cp 50 pv e7e5',
        'info depth 8 multipv 2 score mate 3 pv d8h4',
        'bestmove e7e5',
      ])!;
      expect(r.lines[0].score, const WhiteScore.cp(-50));
      expect(r.lines[1].score, const WhiteScore.mate(-3));
    });

    test('score mate 0 means the side to move is mated', () {
      final r = run(UciParser(sideToMove: Side.white), [
        'info depth 0 score mate 0',
        'bestmove (none)',
      ])!;
      final s = r.lines.single.score;
      expect(s.mate, 0);
      expect(s.mateWinner, Side.black);
      expect(r.noMove, isTrue);
    });

    test('bestmove (none) as Stockfish 19 prints it for mate and stalemate', () {
      final r = run(UciParser(sideToMove: Side.black), [
        'info depth 0 score cp 0',
        'bestmove (none)',
      ])!;
      expect(r.bestMove, isNull);
      expect(r.noMove, isTrue);
      expect(r.lines.single.score, const WhiteScore.cp(0));
      expect(r.lines.single.pv, isEmpty);
    });

    test('bestmove without any info line', () {
      final r = UciParser(sideToMove: Side.white).feed('bestmove e2e4')!;
      expect(r.lines, isEmpty);
      expect(r.bestMove, 'e2e4');
      expect(r.depth, 0);
    });

    test('state resets after bestmove', () {
      final p = UciParser(sideToMove: Side.white);
      run(p, ['info depth 5 multipv 1 score cp 99 pv e2e4', 'bestmove e2e4']);
      final r = run(p, ['info depth 3 multipv 1 score cp 1 pv d2d4', 'bestmove d2d4'])!;
      expect(r.lines.single.score, const WhiteScore.cp(1));
    });

    test('non-final lines return null', () {
      expect(UciParser(sideToMove: Side.white).feed('info depth 1 multipv 1 score cp 1 pv e2e4'), isNull);
    });
  });
}
