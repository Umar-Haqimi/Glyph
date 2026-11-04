import 'dart:convert';
import 'dart:io';

import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

/// One lichess game of `test/vectors/lichess_accuracy/*.ndjson`.
class LichessVector {
  LichessVector(this.file, Map<String, dynamic> j)
      : id = j['id'] as String,
        status = j['status'] as String,
        initialFen = j['initialFen'] as String?,
        plies = j['plies'] as int,
        analysis = [for (final e in j['analysis'] as List) e as Map<String, dynamic>],
        white = (j['accuracy'] as Map)['white'] as int,
        black = (j['accuracy'] as Map)['black'] as int;

  final String file;
  final String id;
  final String status;
  final String? initialFen;
  final int plies;
  final List<Map<String, dynamic>> analysis;
  final int white;
  final int black;

  Side get startSide => initialFen?.split(' ')[1] == 'b' ? Side.black : Side.white;

  /// lichess's own White-POV evals, mates mapped to ±1000 cp (server rule).
  List<int> get cps => [
        for (final e in analysis)
          if (e.containsKey('mate')) ((e['mate'] as int) > 0 ? 1000 : -1000) else e['eval'] as int,
      ];
}

List<LichessVector> lichessVectors() {
  final dir = Directory('test/vectors/lichess_accuracy');
  final files = dir.listSync().whereType<File>().where((f) => f.path.endsWith('.ndjson')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      for (final line in f.readAsLinesSync())
        if (line.trim().isNotEmpty) LichessVector(f.uri.pathSegments.last, jsonDecode(line) as Map<String, dynamic>),
  ];
}

void main() {
  group('WinPercent', () {
    final vector = jsonDecode(File('test/vectors/winpercent.json').readAsStringSync()) as Map<String, dynamic>;
    final tol = (vector['tolerance'] as num).toDouble();

    test('winpercent.json: cp -2000..2000 step 50 within 1e-9', () {
      final cps = vector['cp'] as List;
      expect(cps, hasLength(81));
      for (final e in cps) {
        final cp = e['cp'] as int;
        expect(WinPercent.fromCp(cp), closeTo((e['win'] as num).toDouble(), tol), reason: 'cp $cp');
        expect(WinPercent.ofWhiteScore(WhiteScore.cp(cp)), closeTo((e['win'] as num).toDouble(), tol));
      }
    });

    test('winpercent.json: mates are ±1000 cp whatever the distance', () {
      for (final e in vector['mate'] as List) {
        final m = e['mate'] as int;
        expect(WinPercent.fromMate(m), closeTo((e['win'] as num).toDouble(), tol));
        expect(WinPercent.ofWhiteScore(WhiteScore.mate(m)), closeTo((e['win'] as num).toDouble(), tol));
      }
    });

    test('hand-checked reference values (docs/m0/algorithms.md 1.5)', () {
      expect(WinPercent.fromCp(0), 50);
      expect(WinPercent.fromCp(15), closeTo(51.380429102931544, 1e-12));
      expect(WinPercent.fromCp(100), closeTo(59.10258971916128, 1e-12));
      expect(WinPercent.fromCp(-300), closeTo(24.887450, 1e-6));
      expect(WinPercent.fromCp(500), closeTo(86.307166, 1e-6));
      expect(WinPercent.fromCp(1000), closeTo(97.54474363414323, 1e-12));
      expect(WinPercent.fromCp(1500), WinPercent.fromCp(1000));
      expect(WinPercent.fromCp(-1000), closeTo(2.4552563658567763, 1e-12));
      expect(WinPercent.mateWin, WinPercent.fromCp(1000));
    });

    test('mate 0 uses the winner; point-of-view conversion', () {
      expect(WinPercent.ofWhiteScore(const WhiteScore.mate(0, winnerWhenZero: Side.black)), WinPercent.fromCp(-1000));
      expect(WinPercent.ofWhiteScore(const WhiteScore.mate(0, winnerWhenZero: Side.white)), WinPercent.fromCp(1000));
      expect(WinPercent.forSide(70, Side.white), 70);
      expect(WinPercent.forSide(70, Side.black), 30);
    });

    test('ExpectedPoints.loss is the clamped Win% drop / 100', () {
      expect(ExpectedPoints.loss(60, 50), closeTo(0.10, 1e-12));
      expect(ExpectedPoints.loss(50, 60), 0);
      expect(ExpectedPoints.loss(97.5, 2.5), closeTo(0.95, 1e-12));
    });
  });

  group('Accuracy.ofMove (AccuracyPercent.fromWinPercents)', () {
    test('100 when nothing was lost', () {
      expect(Accuracy.ofMove(50, 50), 100);
      expect(Accuracy.ofMove(40, 60), 100);
    });

    test('formula with the +1 bonus and clamping', () {
      expect(Accuracy.ofMove(60, 50), closeTo(64.5798, 1e-3));
      expect(Accuracy.ofMove(51, 50), closeTo(96.604, 1e-3));
      expect(Accuracy.ofMove(100, 50), closeTo(9.5278, 1e-3));
      expect(Accuracy.ofMove(100, 0), 0);
      expect(Accuracy.ofMove(50, 49.9999999), lessThanOrEqualTo(100));
    });
  });

  group('Accuracy.ofGame (AccuracyPercent.gameAccuracy)', () {
    test('worked example of docs/m0/algorithms.md 1.5: 78.91 / 79.64 -> 79 / 80', () {
      final a = Accuracy.ofCentipawns([-50, 15, -40, 10], initialCp: Accuracy.lichessInitialCp);
      expect(a.white, closeTo(78.91, 0.01));
      expect(a.black, closeTo(79.64, 0.01));
      expect((Accuracy.display(a.white!), Accuracy.display(a.black!)), (79, 80));
    });

    test('one big blunder: white ~10.66, black 100', () {
      final a = Accuracy.ofCentipawns([-900, -900], initialCp: 15);
      expect(a.white, closeTo(10.66, 0.01));
      expect(a.black, 100);
    });

    test('needs a move by each side', () {
      expect(Accuracy.ofCentipawns([20], initialCp: 15).white, isNull);
      expect(Accuracy.ofGame(const []).white, isNull);
      expect(Accuracy.ofGame(const [50.0]).black, isNull);
    });

    test('start colour: a Black-first game assigns pair 0 to Black', () {
      final w = Accuracy.ofCentipawns([-900, -900], initialCp: 15);
      final b = Accuracy.ofCentipawns([-900, -900], initialCp: 15, startSide: Side.black);
      // White -> -900 cp is a White blunder when White moves first, a great
      // Black move when Black does.
      expect(w.white, closeTo(10.66, 0.01));
      expect(b.black, 100);
      expect(b.white, 100);
    });

    test('missing evaluations skip their windows and moves', () {
      final full = Accuracy.ofGame([51.4, 45.4, 51.4, 46.3, 50.9]);
      final gap = Accuracy.ofGame([51.4, 45.4, null, 46.3, 50.9]);
      expect(gap.white, isNotNull);
      expect(gap.white, isNot(full.white));
    });

    // From lila modules/analyse/src/test/AccuracyPercentTest.scala
    // (docs/m0/algorithms.md 1.5: 50 x (-50, 15) -> 76 +- 8).
    test('lila AccuracyPercentTest: steady, equal play', () {
      final cps = [for (var i = 0; i < 50; i++) ...[-50, 15]];
      final a = Accuracy.ofCentipawns(cps, initialCp: 15);
      expect(a.white, closeTo(76, 8));
      expect(a.black, closeTo(76, 8));
    });

    test('perfect play is 100', () {
      final a = Accuracy.ofCentipawns(List.filled(40, 15), initialCp: 15);
      expect(a.white, closeTo(100, 1e-9));
      expect(a.black, closeTo(100, 1e-9));
    });
  });

  group('lichess accuracy golden vectors (P0, SPEC 7.1 item 2)', () {
    final vectors = lichessVectors();

    test('the vector set covers SPEC 7.1', () {
      expect(vectors.length, greaterThanOrEqualTo(30));
      expect(vectors.where((v) => v.plies <= 40), hasLength(greaterThanOrEqualTo(4)));
      expect(vectors.where((v) => v.plies >= 120), hasLength(greaterThanOrEqualTo(4)));
      expect(vectors.where((v) => v.status == 'mate'), hasLength(greaterThanOrEqualTo(6)));
      expect(vectors.where((v) => v.status == 'draw'), hasLength(greaterThanOrEqualTo(4)));
      expect(vectors.where((v) => v.analysis.any((e) => e.containsKey('mate'))), hasLength(greaterThanOrEqualTo(6)));
      expect(vectors.where((v) => v.initialFen != null), hasLength(greaterThanOrEqualTo(2)), reason: 'chess960');
    });

    for (final v in vectors) {
      test('${v.file} ${v.id} (${v.plies} plies, ${v.status}): ${v.white} / ${v.black}', () {
        // lichess's analysis has one eval per ply (plies - 1 for a mate
        // ending) and no initial eval: lila's legacy +15 cp stands in.
        expect(v.analysis.length, v.status == 'mate' ? v.plies - 1 : v.plies);
        final a = Accuracy.ofCentipawns(v.cps, initialCp: Accuracy.lichessInitialCp, startSide: v.startSide);
        // Exact after rounding (stricter than SPEC's ±1).
        expect(Accuracy.display(a.white!), v.white, reason: 'white ${a.white}');
        expect(Accuracy.display(a.black!), v.black, reason: 'black ${a.black}');
      });
    }
  });
}
