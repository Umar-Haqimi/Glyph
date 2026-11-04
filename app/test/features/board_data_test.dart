import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/features/board/board_data.dart';
import 'package:glyph/features/board/coach.dart';
import 'package:glyph_core/glyph_core.dart';

import '../support/review_fixture.dart';
import '../support/test_app.dart';

final Game _game = parsePgn(reviewPgn).games.single;

GameRecord _record({AnalysisStatus? status, Side? userSide}) => GameRecord(
      id: 1,
      source: GameSource.paste,
      pgn: reviewPgn,
      white: 'Alice',
      black: 'Bob',
      plyCount: 8,
      importedAt: 1,
      analysisStatus: status,
      userSide: userSide,
    );

List<PositionLineRecord> _rows(int positions, {Map<int, int> cp = const {}}) => [
      for (var ply = 0; ply < positions; ply++)
        for (final (rank, pv, score) in [
          (1, reviewLines[ply]!.$1, cp[ply] ?? reviewLines[ply]!.$2),
          (2, reviewLines[ply]!.$3, reviewLines[ply]!.$4),
        ])
          PositionLineRecord(gameId: 1, ply: ply, rank: rank, scoreCp: score, depth: 16, pvUci: pv),
    ];

Map<int, List<EngineLine>> _lines(List<PositionLineRecord> rows) {
  final out = <int, List<EngineLine>>{};
  for (final r in rows) {
    (out[r.ply] ??= []).add(engineLineFromStored(
      rank: r.rank,
      scoreCp: r.scoreCp,
      scoreMate: r.scoreMate,
      depth: r.depth,
      pvUci: r.pvUci,
    )!);
  }
  return out;
}

void main() {
  group('BoardData labels', () {
    test('while the analysis is unfinished the labels are the classifier\'s, computed in memory', () {
      final rows = _rows(9);
      final data = BoardData.build(
        record: _record(status: AnalysisStatus.running),
        game: _game,
        rows: rows,
        storedLabels: const [],
      );
      expect(data.provisional, isTrue);
      final expected = reviewGame(_game, _lines(rows)).moves;
      expect(data.moves, hasLength(8));
      for (var i = 0; i < 8; i++) {
        expect(data.moves[i]?.label, expected[i]?.label, reason: 'ply ${i + 1}');
        expect(data.moves[i]?.bestUci, expected[i]?.bestUci, reason: 'ply ${i + 1}');
      }
    });

    test('a label shown early is the label the finished analysis gives', () {
      final early = BoardData.build(
        record: _record(status: AnalysisStatus.running),
        game: _game,
        rows: _rows(4),
        storedLabels: const [],
      );
      final full = BoardData.build(
        record: _record(status: AnalysisStatus.running),
        game: _game,
        rows: _rows(9),
        storedLabels: const [],
      );
      var labelled = 0;
      for (var i = 0; i < 8; i++) {
        final e = early.moves[i];
        if (e == null) continue;
        labelled++;
        expect(e.label, full.moves[i]!.label, reason: 'ply ${i + 1}');
        expect(e.epLoss, full.moves[i]!.epLoss);
      }
      expect(labelled, inInclusiveRange(2, 4));
      expect(early.moves[7], isNull, reason: 'ply 8 needs positions the engine has not reached');
    });

    test('a completed analysis with stored labels uses them (nothing is recomputed)', () {
      final stored = [
        for (final e in reviewLabels.entries)
          MoveLabelRecord(gameId: 1, ply: e.key, label: e.value.$1, epLoss: 0.01, winBefore: 55, winAfter: 54, bestUci: e.value.$2),
      ];
      final data = BoardData.build(
        record: _record(status: AnalysisStatus.completed),
        game: _game,
        rows: _rows(9),
        storedLabels: stored,
      );
      expect(data.provisional, isFalse);
      expect([for (final m in data.moves) m!.label], [for (final e in reviewLabels.values) e.$1]);
      expect(data.moves[6]!.side, Side.white);
      expect(data.moves[7]!.side, Side.black);
      expect(data.moves[2]!.uci, _game.plies[2].uci);
      expect([for (final k in data.keyMoments) k.ply], [3, 5, 6, 7, 8]);
    });

    test('completed but labels missing (not stored yet): falls back to the in-memory labels', () {
      final data = BoardData.build(
        record: _record(status: AnalysisStatus.completed),
        game: _game,
        rows: _rows(9),
        storedLabels: const [],
      );
      expect(data.provisional, isTrue);
      expect(data.moves.every((m) => m != null), isTrue);
    });

    test('counts per side', () {
      final stored = [
        for (final e in reviewLabels.entries)
          MoveLabelRecord(gameId: 1, ply: e.key, label: e.value.$1, bestUci: e.value.$2),
      ];
      final data = BoardData.build(
        record: _record(status: AnalysisStatus.completed),
        game: _game,
        rows: _rows(9),
        storedLabels: stored,
      );
      final white = data.counts(Side.white);
      final black = data.counts(Side.black);
      expect(white.values.fold(0, (a, b) => a + b), 4);
      expect(black.values.fold(0, (a, b) => a + b), 4);
      expect(white[MoveLabel.mistake], 1);
      expect(black[MoveLabel.blunder], 1);
      expect(black[MoveLabel.mistake], 0);
    });
  });

  group('BoardData positions', () {
    test('Win% series is White POV and null where the engine has not been', () {
      final data = BoardData.build(
        record: _record(status: AnalysisStatus.running),
        game: _game,
        rows: _rows(3, cp: {2: -200}),
        storedLabels: const [],
      );
      expect(data.whiteWinAt(0), closeTo(WinPercent.fromCp(30), 1e-9));
      expect(data.whiteWinAt(2), closeTo(WinPercent.fromCp(-200), 1e-9));
      expect(data.whiteWinAt(2), lessThan(50));
      expect(data.whiteWinAt(5), isNull);
      expect(data.analysedPositions, 3);
      expect(data.analysedAt(2), isTrue);
      expect(data.analysedAt(3), isFalse);
    });

    test('a checkmate position is known without the engine', () {
      final mate = parsePgn('[White "a"]\n[Black "b"]\n\n1. f3 e5 2. g4 Qh4# 0-1').games.single;
      final data = BoardData.build(
        record: _record(status: AnalysisStatus.running),
        game: mate,
        rows: const [],
        storedLabels: const [],
      );
      expect(data.terminalAt(4)?.kind, TerminalKind.checkmate);
      expect(data.whiteWinAt(4), lessThan(5));
    });
  });

  group('coach line', () {
    test('missed mate and game end', () {
      final mate = parsePgn('[White "a"]\n[Black "b"]\n\n1. f3 e5 2. g4 Qh4# 0-1').games.single;
      final stored = [
        const MoveLabelRecord(gameId: 1, ply: 1, label: MoveLabel.mistake, bestUci: 'e2e4'),
        const MoveLabelRecord(gameId: 1, ply: 2, label: MoveLabel.best, bestUci: 'e7e5'),
        const MoveLabelRecord(gameId: 1, ply: 3, label: MoveLabel.blunder, bestUci: 'd2d4'),
        const MoveLabelRecord(gameId: 1, ply: 4, label: MoveLabel.best, bestUci: 'd8h4'),
      ];
      final data = BoardData.build(
        record: GameRecord(
          id: 1,
          source: GameSource.paste,
          pgn: '',
          plyCount: 4,
          importedAt: 1,
          analysisStatus: AnalysisStatus.completed,
        ),
        game: mate,
        rows: const [],
        storedLabels: stored,
      );
      expect(coachLineAt(data, l10n, 4).text, '${l10n.coachBest} ${l10n.coachGameEnds(l10n.evalResultBlackWins)}');
      // Move 3 (g4) had a better alternative, but there are no lines to quote an eval from.
      expect(coachLineAt(data, l10n, 3).text, startsWith(l10n.coachBestWasNoEval('d4')));
    });

    test('no label yet: waiting; complete without data: no data', () {
      final running = BoardData.build(
        record: _record(status: AnalysisStatus.running),
        game: _game,
        rows: _rows(1),
        storedLabels: const [],
      );
      expect(coachLineAt(running, l10n, 5).text, l10n.coachWaiting);
      expect(coachLineAt(running, l10n, 5).label, isNull);
    });

    test('Miss with a forced mate before the move names the mate', () {
      final data = BoardData.build(
        record: _record(status: AnalysisStatus.completed),
        game: _game,
        rows: const [
          PositionLineRecord(gameId: 1, ply: 0, rank: 1, scoreMate: 3, depth: 16, pvUci: 'g1f3 b8c6'),
        ],
        storedLabels: [
          const MoveLabelRecord(gameId: 1, ply: 1, label: MoveLabel.miss, bestUci: 'g1f3'),
          for (var p = 2; p <= 8; p++) MoveLabelRecord(gameId: 1, ply: p, label: MoveLabel.good),
        ],
      );
      expect(coachLineAt(data, l10n, 1).text, '${l10n.coachMissedMate(3)} ${l10n.coachBestWas('Nf3', '#3')}');
      // A mate for the other side is not "missed".
      final black = BoardData.build(
        record: _record(status: AnalysisStatus.completed),
        game: _game,
        rows: const [
          PositionLineRecord(gameId: 1, ply: 0, rank: 1, scoreMate: -3, depth: 16, pvUci: 'g1f3 b8c6'),
        ],
        storedLabels: [
          const MoveLabelRecord(gameId: 1, ply: 1, label: MoveLabel.miss, bestUci: 'g1f3'),
          for (var p = 2; p <= 8; p++) MoveLabelRecord(gameId: 1, ply: p, label: MoveLabel.good),
        ],
      );
      expect(coachLineAt(black, l10n, 1).text, startsWith(l10n.coachMiss));
    });
  });
}
