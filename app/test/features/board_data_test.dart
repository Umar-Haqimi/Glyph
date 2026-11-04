import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/in_memory.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/data/providers.dart';
import 'package:glyph/features/board/board_data.dart';
import 'package:glyph/features/board/coach.dart';
import 'package:glyph_core/glyph_core.dart';

import '../support/review_fixture.dart';
import '../support/test_app.dart';

final Game _game = parsePgn(reviewPgn).games.single;

/// Remembers how much each `positionLines` call read.
class _CountingAnalyses extends InMemoryAnalysisRepository {
  _CountingAnalyses(super.store);

  final List<({int fromPly, int rows})> reads = [];

  @override
  Future<List<PositionLineRecord>> positionLines(int gameId, {int fromPly = 0}) async {
    final out = await super.positionLines(gameId, fromPly: fromPly);
    reads.add((fromPly: fromPly, rows: out.length));
    return out;
  }
}

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

  group('BoardDataBuilder (incremental)', () {
    // A fixture with a Book prefix (the real opening book) and a Miss at ply 5:
    // White had mate in 3 in position 4 and played Bc4 (engine line 2, no mate).
    List<PositionLineRecord> rows(int positions) => [
          for (final r in _rows(positions))
            if (r.ply == 4 && r.rank == 1)
              PositionLineRecord(gameId: 1, ply: 4, rank: 1, scoreMate: 3, depth: 16, pvUci: r.pvUci)
            else
              r,
        ];

    void expectSame(BoardData a, BoardData b, String reason) {
      expect(a.provisional, b.provisional, reason: reason);
      for (var i = 0; i < a.plyCount; i++) {
        final x = a.moves[i];
        final y = b.moves[i];
        expect(x == null, y == null, reason: '$reason ply ${i + 1}');
        if (x == null || y == null) continue;
        expect((x.label, x.epLoss, x.winBefore, x.winAfter, x.bestUci), (y.label, y.epLoss, y.winBefore, y.winAfter, y.bestUci),
            reason: '$reason ply ${i + 1}');
      }
      expect([for (var p = 0; p <= a.plyCount; p++) a.whiteWinAt(p)], [for (var p = 0; p <= b.plyCount; p++) b.whiteWinAt(p)], reason: reason);
      expect(a.lines.keys.toList(), b.lines.keys.toList(), reason: reason);
      expect([for (final k in a.keyMoments) k.ply], [for (final k in b.keyMoments) k.ply], reason: reason);
    }

    test('feeding one position at a time gives, at every prefix, exactly the from-scratch result', () {
      final seen = <MoveLabel>{};
      final all = rows(9);
      // With the real opening book the whole game is theory (Book labels,
      // no engine data needed); without it the Miss at ply 5 shows up.
      final realOne = realBook();
      expect(realOne.annotate(_game).bookPlies, greaterThan(0), reason: 'the fixture starts with theory');
      for (final book in <OpeningBook?>[realOne, null]) {
        final builder = BoardDataBuilder(game: _game, book: book);
        for (var k = 1; k <= 9; k++) {
          // What the provider does: only the rows from the last known position on.
          expect(builder.append([for (final r in all) if (r.ply < k && r.ply >= builder.nextPly) r]), isTrue);
          final scratch = BoardData.build(
            record: _record(status: AnalysisStatus.running),
            game: _game,
            rows: [for (final r in all) if (r.ply < k) r],
            storedLabels: const [],
            book: book,
          );
          final inc = builder.snapshot(record: _record(status: AnalysisStatus.running), storedLabels: const []);
          expectSame(inc, scratch, 'book=${book != null}, after $k positions');
          seen.addAll([for (final m in inc.moves) ?m?.label]);
        }
      }
      expect(seen, containsAll([MoveLabel.book, MoveLabel.miss]), reason: '$seen');
    });

    test('a snapshot does not change when more rows arrive', () {
      final builder = BoardDataBuilder(game: _game);
      final all = rows(9);
      builder.append([for (final r in all) if (r.ply < 3) r]);
      final early = builder.snapshot(record: _record(status: AnalysisStatus.running), storedLabels: const []);
      final labelled = early.moves.where((m) => m != null).length;
      builder.append([for (final r in all) if (r.ply >= builder.nextPly) r]);
      expect(early.moves.where((m) => m != null).length, labelled);
      expect(early.lines.keys, [0, 1, 2]);
      expect(early.whiteWinAt(5), isNull);
    });

    test('a restarted analysis is detected (the position it re-reads is missing or different)', () {
      final all = rows(9);
      final builder = BoardDataBuilder(game: _game)..append([for (final r in all) if (r.ply < 6) r]);
      expect(builder.nextPly, 5);
      // Same position again: fine, nothing changes.
      expect(builder.append([for (final r in all) if (r.ply >= 5 && r.ply < 7) r]), isTrue);
      expect(builder.nextPly, 6);
      // Cleared: the tail is gone.
      expect(builder.append(const []), isFalse);
      // Re-analysed at another depth: same position, other numbers.
      expect(
        builder.append([
          PositionLineRecord(gameId: 1, ply: 6, rank: 1, scoreCp: 99, depth: 20, pvUci: 'g8f6 d2d3'),
        ]),
        isFalse,
      );
      expect(builder.nextPly, 6, reason: 'a rejected append changes nothing');
    });

    test('the game is replayed once: the builder owns the positions the snapshots share', () {
      final builder = BoardDataBuilder(game: _game)..append(rows(9));
      final a = builder.snapshot(record: _record(status: AnalysisStatus.running), storedLabels: const []);
      final b = builder.snapshot(record: _record(status: AnalysisStatus.running), storedLabels: const []);
      for (var p = 0; p <= 8; p++) {
        expect(identical(a.positionAt(p), b.positionAt(p)), isTrue, reason: 'position $p');
      }
    });

    test('final-position draws: threefold repetition and the 50-move rule end the game, only at the last position', () {
      final shuffle = parsePgn('[White "a"]\n[Black "b"]\n\n1. Nf3 Nf6 2. Ng1 Ng8 3. Nf3 Nf6 4. Ng1 Ng8 *').games.single;
      final d = BoardData.build(record: _record(), game: shuffle, rows: const [], storedLabels: const []);
      expect([for (var p = 0; p <= 8; p++) d.gameOverAt(p)], [false, false, false, false, false, false, false, false, true]);
      expect(d.drawnByRuleAt(8), isTrue);
      expect(d.terminalAt(8), isNull);
      expect(d.whiteWinAt(8), 50);
      final fifty = parsePgn(
        '[White "a"]\n[Black "b"]\n[SetUp "1"]\n[FEN "4k3/8/8/8/8/8/8/R3K3 w - - 98 80"]\n\n80. Ra2 Kd7 *',
      ).games.single;
      final f = BoardData.build(record: _record(), game: fifty, rows: const [], storedLabels: const []);
      expect([f.gameOverAt(0), f.gameOverAt(1), f.gameOverAt(2)], [false, false, true]);
      // Checkmate is still game over.
      final mate = parsePgn('[White "a"]\n[Black "b"]\n\n1. f3 e5 2. g4 Qh4# 0-1').games.single;
      final m = BoardData.build(record: _record(), game: mate, rows: const [], storedLabels: const []);
      expect(m.gameOverAt(4), isTrue);
      expect(m.gameOverAt(3), isFalse);
    });
  });

  group('boardDataProvider reads only the new rows', () {
    setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

    Future<void> savePosition(TestEnv env, int id, int ply) => env.analyses.savePosition(
          id,
          ply,
          [
            for (final r in _rows(9))
              if (r.ply == ply) PositionLineRecord(gameId: id, ply: ply, rank: r.rank, scoreCp: r.scoreCp, depth: 16, pvUci: r.pvUci),
          ],
          completedPlies: ply + 1,
          updatedAt: 2 + ply,
        );

    test('each new position costs a read of the tail, not of the game; the result matches a full build', () async {
      late _CountingAnalyses counting;
      final env = TestEnv(analysesBuilder: (store) => counting = _CountingAnalyses(store));
      final id = (await env.games.save(NewGame(
        source: GameSource.paste,
        pgn: reviewPgn,
        white: 'Alice',
        black: 'Bob',
        plyCount: 8,
        importedAt: 1,
      )))
          .id;
      await env.analyses.upsert(AnalysisRecord(
        gameId: id,
        engine: 'Stockfish',
        depth: 16,
        multipv: 2,
        status: AnalysisStatus.running,
        updatedAt: 1,
      ));
      final container = ProviderContainer(overrides: env.overrides);
      addTearDown(container.dispose);
      container.listen(boardDataProvider(id), (_, _) {});

      for (var ply = 0; ply <= 8; ply++) {
        await savePosition(env, id, ply);
        container.invalidate(gameProvider(id)); // what a new tick does to the provider
        final data = (await container.read(boardDataProvider(id).future))!;
        expect(data.analysedPositions, ply + 1);
      }
      // Position p is read when it is new and once more (to notice a restart) with the next one: never the whole game.
      expect([for (final r in counting.reads) r.fromPly], [0, 0, 1, 2, 3, 4, 5, 6, 7], reason: '${counting.reads}');
      expect(counting.reads.every((r) => r.rows <= 4), isTrue, reason: '${counting.reads}');

      final incremental = (await container.read(boardDataProvider(id).future))!;
      final scratch = BoardData.build(
        record: incremental.record,
        game: _game,
        rows: await env.analyses.positionLines(id),
        storedLabels: const [],
      );
      expect([for (final m in incremental.moves) m?.label], [for (final m in scratch.moves) m?.label]);
      expect(incremental.lines.length, scratch.lines.length);
    });

    test('a cleared and restarted analysis is read from the start again', () async {
      late _CountingAnalyses counting;
      final env = TestEnv(analysesBuilder: (store) => counting = _CountingAnalyses(store));
      final id = (await env.games.save(NewGame(
        source: GameSource.paste,
        pgn: reviewPgn,
        white: 'Alice',
        black: 'Bob',
        plyCount: 8,
        importedAt: 1,
      )))
          .id;
      await env.analyses.upsert(AnalysisRecord(
        gameId: id,
        engine: 'Stockfish',
        depth: 16,
        multipv: 2,
        status: AnalysisStatus.running,
        updatedAt: 1,
      ));
      final container = ProviderContainer(overrides: env.overrides);
      addTearDown(container.dispose);
      container.listen(boardDataProvider(id), (_, _) {});
      for (var ply = 0; ply <= 5; ply++) {
        await savePosition(env, id, ply);
      }
      expect((await container.read(boardDataProvider(id).future))!.analysedPositions, 6);

      // Re-analyse: everything is cleared, two positions come in at another depth.
      await env.analyses.clear(id);
      await env.analyses.upsert(AnalysisRecord(
        gameId: id,
        engine: 'Stockfish',
        depth: 20,
        multipv: 2,
        status: AnalysisStatus.running,
        updatedAt: 9,
      ));
      for (var ply = 0; ply < 2; ply++) {
        await env.analyses.savePosition(
          id,
          ply,
          [PositionLineRecord(gameId: id, ply: ply, rank: 1, scoreCp: -500, depth: 20, pvUci: _rows(9).firstWhere((r) => r.ply == ply).pvUci)],
          completedPlies: ply + 1,
          updatedAt: 10 + ply,
        );
      }
      container.invalidate(gameProvider(id));
      final data = (await container.read(boardDataProvider(id).future))!;
      expect(data.analysedPositions, 2, reason: 'the stale positions 2..5 are gone');
      expect(data.topLineAt(0)!.depth, 20);
      expect(data.whiteWinAt(0)!, lessThan(50));
      expect(counting.reads.last.fromPly, 0, reason: 'the fallback re-read everything');
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
