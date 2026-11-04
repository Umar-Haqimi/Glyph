import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

Game game(String pgn) => parsePgn(pgn).games.single;

void main() {
  final g = game('''
[Event "T"]
[White "A"]
[Black "B"]
[Result "1-0"]

1. e4 {[%clk 0:03:00]} e5 2. Nf3 Nc6 3. Bb5 a6 4. Bxc6 dxc6 1-0
''');

  test('NAG table (SPEC F18)', () {
    expect(nagForLabel(MoveLabel.brilliant), 3);
    expect(nagForLabel(MoveLabel.great), 1);
    expect(nagForLabel(MoveLabel.inaccuracy), 6);
    expect(nagForLabel(MoveLabel.mistake), 2);
    expect(nagForLabel(MoveLabel.blunder), 4);
    expect(nagForLabel(MoveLabel.miss), 2);
    for (final l in [MoveLabel.best, MoveLabel.excellent, MoveLabel.good, MoveLabel.book, MoveLabel.forced]) {
      expect(nagForLabel(l), isNull);
    }
  });

  test('labels, evals, clock, Annotator header', () {
    final out = exportAnnotatedPgn(
      g,
      labels: {
        1: MoveLabel.brilliant,
        2: MoveLabel.great,
        4: MoveLabel.inaccuracy,
        5: MoveLabel.mistake,
        6: MoveLabel.miss,
        8: MoveLabel.blunder,
        3: MoveLabel.best,
      },
      evals: {
        1: const PlyEval.cp(30),
        2: const PlyEval.cp(-125),
        7: const PlyEval.mate(3),
        8: const PlyEval.mate(-2),
      },
    );
    expect(out, contains('[Annotator "Glyph"]'));
    expect(out, contains('[White "A"]'));
    expect(out, contains('1. e4 \$3 { [%eval 0.30] [%clk 0:03:00] }'));
    expect(out, contains('1... e5 \$1 { [%eval -1.25] }'));
    expect(out, contains('2. Nf3 Nc6 \$6'));
    expect(out, contains('3. Bb5 \$2 3... a6 \$2 { Miss }'));
    expect(out, contains('4. Bxc6 { [%eval #3] } dxc6 \$4 { [%eval #-2] }'));
    expect(out.trimRight(), endsWith('1-0'));
    // Best has no NAG.
    expect(out, isNot(contains('Nf3 \$')));
  });

  test('re-import of an annotated export reads the evals back', () {
    final out = exportAnnotatedPgn(g, evals: {3: const PlyEval.cp(-7), 4: const PlyEval.mate(5)});
    final back = game(out);
    expect(back.plies[2].eval, const PlyEval.cp(-7));
    expect(back.plies[3].eval, const PlyEval.mate(5));
    expect(back.plies[0].clockMs, 180000);
    expect(back.headers['Annotator'], 'Glyph');
  });

  test('a game without a Result header gets one', () {
    final h = game('1. e4 e5 1-0');
    expect(h.result, '1-0');
    final back = game(exportAnnotatedPgn(h));
    expect(back.result, '1-0');
  });

  test('FEN start with Black to move keeps move numbering', () {
    final f = game('[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 1"]\n[SetUp "1"]\n\n1... e5 2. Nf3 *');
    final out = exportAnnotatedPgn(f);
    expect(out, contains('1... e5 2. Nf3'));
    expect(game(out).plies.map((p) => p.san), ['e5', 'Nf3']);
  });
}
