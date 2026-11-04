import 'dart:async';

import 'package:chessground/chessground.dart' show Arrow, CustomShape, StaticChessboard;
import 'package:dartchess/dartchess.dart';
import 'dart:ui' show CheckedState, Tristate;

import 'package:flutter/semantics.dart' show SemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/engine/engine_providers.dart';
import 'package:glyph/features/board/analysis_board.dart';
import 'package:glyph/features/board/move_badge.dart';
import 'package:glyph/features/board/player_strip.dart';
import 'package:glyph/features/board/spoken_move.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../support/review_fixture.dart';
import '../support/test_app.dart';

StaticChessboard _board(WidgetTester t) => t.widget<StaticChessboard>(find.byType(StaticChessboard));

Future<void> _tap(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await settleBoard(t, rounds: 12);
}

Future<void> _openMenu(WidgetTester t, String itemKey) async {
  await t.tap(find.byKey(const Key('board-menu')));
  await settleBoard(t, rounds: 25);
  await t.tap(find.byKey(Key(itemKey)));
  await settleBoard(t, rounds: 12);
}

/// 1. Nf3 Nf6 2. Ng1 Ng8 ... [cycles] times: 4 * cycles plies, and the last
/// position is the start position for the (cycles + 1)th time.
String _shufflePgn(int cycles) {
  final b = StringBuffer('[White "Alice"]\n[Black "Bob"]\n\n');
  for (var i = 1; i <= cycles; i++) {
    b.write('${2 * i - 1}. Nf3 Nf6 ${2 * i}. Ng1 Ng8 ');
  }
  b.write('*');
  return b.toString();
}

/// Engine lines of the four positions of the shuffle (position `ply % 4`).
const _shuffleLines = <int, (String, String)>{
  0: ('g1f3 g8f6', 'e2e4 e7e5'),
  1: ('g8f6 f3g1', 'd7d5 d2d4'),
  2: ('f3g1 f6g8', 'e2e3 d7d5'),
  3: ('f6g8 b1c3', 'd7d5 e2e4'),
};

Future<int> _seedShuffle(TestEnv env, int cycles, {AnalysisStatus status = AnalysisStatus.completed}) async {
  final plies = cycles * 4;
  final saved = await env.games.save(NewGame(
    source: GameSource.paste,
    pgn: _shufflePgn(cycles),
    white: 'Alice',
    black: 'Bob',
    plyCount: plies,
    importedAt: 1,
  ));
  final id = saved.id;
  await env.analyses.upsert(AnalysisRecord(
    gameId: id,
    engine: 'Stockfish 19 light',
    depth: 16,
    multipv: 2,
    status: status,
    completedPlies: plies + 1,
    updatedAt: 1,
  ));
  for (var ply = 0; ply <= plies; ply++) {
    final l = _shuffleLines[ply % 4]!;
    await env.analyses.savePosition(
      id,
      ply,
      [
        PositionLineRecord(gameId: id, ply: ply, rank: 1, scoreCp: 20, depth: 16, pvUci: l.$1),
        PositionLineRecord(gameId: id, ply: ply, rank: 2, scoreCp: 10, depth: 16, pvUci: l.$2),
      ],
      completedPlies: ply + 1,
      updatedAt: 1,
    );
  }
  return id;
}

void main() {
  group('move list is lazy', () {
    testWidgets('a 300-ply game builds a handful of chips, follows the current move, and stays that way', (tester) async {
      final env = TestEnv();
      final id = await _seedShuffle(env, 75);
      await pumpReview(tester, env, id);
      final chips = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_MoveChip');
      expect(chips.evaluate().length, lessThan(20), reason: 'only the visible chips (plus the cache) exist');
      expect(find.byKey(const Key('move-chip-1')), findsOneWidget);
      expect(find.byKey(const Key('move-chip-250')), findsNothing);

      await _tap(tester, 'nav-last');
      expect(chips.evaluate().length, lessThan(20));
      expect(find.byKey(const Key('move-chip-300')), findsOneWidget);
      expect(find.byKey(const Key('move-chip-1')), findsNothing);
      // The current chip is (as far as the end of the list allows) in view.
      final list = tester.getRect(find.byKey(const Key('move-list')));
      expect(list.overlaps(tester.getRect(find.byKey(const Key('move-chip-300')))), isTrue);

      // Stepping back keeps centring the current move.
      for (var i = 0; i < 6; i++) {
        await _tap(tester, 'nav-back');
      }
      final chip = tester.getRect(find.byKey(const Key('move-chip-294')));
      expect(chip.center.dx, closeTo(list.center.dx, chip.width / 2 + 1));
      expect(chips.evaluate().length, lessThan(20));

      // Tapping a visible chip selects it.
      await tester.tap(find.byKey(const Key('move-chip-292')));
      await settleBoard(tester, rounds: 12);
      expect(_board(tester).fen, startsWith('rnbqkbnr'));
    });
  });

  group('accessibility actions', () {
    testWidgets('a move chip is a button with a tap action, and activating it jumps there', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 2);
      final data = tester.getSemantics(find.bySemanticsLabel('Move 3, White: Bishop c4, Mistake')).getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isTrue, reason: 'TalkBack must be able to activate the chip');
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.flagsCollection.isSelected, Tristate.isFalse);
      // The current chip says it is selected.
      final current = tester.getSemantics(find.bySemanticsLabel('Move 1, Black: e5, Excellent')).getSemanticsData();
      expect(current.flagsCollection.isSelected, Tristate.isTrue);

      tester.semantics.tap(find.semantics.byLabel('Move 3, White: Bishop c4, Mistake'));
      await settleBoard(tester, rounds: 12);
      expect(_board(tester).fen, 'r1bqkbnr/pppp1ppp/2n5/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R b KQkq - 3 3');
      handle.dispose();
    });

    testWidgets('a key moment row is a button with a tap action, and activating it jumps and closes', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      await _tap(tester, 'open-key-moments');
      final label = RegExp(r"^Move 3, Black: Bishop c5, Blunder, White's win chance");
      expect(tester.getSemantics(find.bySemanticsLabel(label)).getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(find.semantics.byLabel(label));
      await settleBoard(tester, rounds: 20);
      expect(find.byKey(const Key('key-moments-list')), findsNothing, reason: 'the sheet closed');
      expect(_board(tester).fen, 'r1bqk1nr/pppp1ppp/2n5/2b1p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4');
      handle.dispose();
    });

    testWidgets('"Set your side" options are radio-like: checked state and a mutually exclusive group', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv();
      final id = await seedReview(env, userSide: Side.black);
      await pumpReview(tester, env, id);
      await _openMenu(tester, 'menu-set-side');
      final black = tester.getSemantics(find.byKey(const Key('your-side-black'))).getSemanticsData();
      final white = tester.getSemantics(find.byKey(const Key('your-side-white'))).getSemanticsData();
      final none = tester.getSemantics(find.byKey(const Key('your-side-none'))).getSemanticsData();
      expect(black.flagsCollection.isChecked, CheckedState.isTrue);
      expect(white.flagsCollection.isChecked, CheckedState.isFalse);
      expect(none.flagsCollection.isChecked, CheckedState.isFalse);
      for (final d in [black, white, none]) {
        expect(d.flagsCollection.isInMutuallyExclusiveGroup, isTrue);
        expect(d.hasAction(SemanticsAction.tap), isTrue);
      }
      expect(black.label, l10n.sideBlack);
      handle.dispose();
    });
  });

  group('badge pop-in', () {
    testWidgets('scales in over 150 ms; not at all when the system asks for reduced motion', (tester) async {
      Future<double> scaleAfterFirstFrame({required bool reduce, required bool play}) async {
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(disableAnimations: reduce),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: PopIn(play: play, child: const SizedBox(width: 10, height: 10)),
          ),
        ));
        await tester.pump(const Duration(milliseconds: 30));
        return tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value;
      }

      expect(await scaleAfterFirstFrame(reduce: false, play: true), lessThan(1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<ScaleTransition>(find.byType(ScaleTransition)).scale.value, 1);
      await tester.pumpWidget(const SizedBox());
      expect(await scaleAfterFirstFrame(reduce: true, play: true), 1);
      await tester.pumpWidget(const SizedBox());
      expect(await scaleAfterFirstFrame(reduce: false, play: false), 1, reason: 'a chip scrolled into view does not animate');
    });

    testWidgets('the board badge does not animate when animations are disabled', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpReview(tester, env, id, initialPly: 6);
      final board = tester.widget<AnalysisBoard>(find.byType(AnalysisBoard));
      expect(board.badge, isNotNull);
      final settings = _board(tester).settings;
      expect(settings.animationDuration, Duration.zero);
    });
  });

  group('spoken moves', () {
    test('SAN in words', () {
      final l = l10n;
      expect(spokenSan(l, 'Nf3'), 'Knight f3');
      expect(spokenSan(l, 'e4'), 'e4');
      expect(spokenSan(l, 'exd5'), 'e takes d5');
      expect(spokenSan(l, 'Qxd5+'), 'Queen takes d5, check');
      expect(spokenSan(l, 'Nbd7'), 'Knight b d7');
      expect(spokenSan(l, 'R1e2#'), 'Rook 1 e2, checkmate');
      expect(spokenSan(l, 'O-O'), 'castles kingside');
      expect(spokenSan(l, 'O-O-O+'), 'castles queenside, check');
      expect(spokenSan(l, 'e8=Q#'), 'e8, promotes to Queen, checkmate');
      expect(spokenSan(l, 'bxa8=N'), 'b takes a8, promotes to Knight');
      expect(spokenSan(l, '?'), '?');
    });
  });

  group('report cursor', () {
    testWidgets('"Show on board" without touching the graph keeps the board where it was', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 5);
      final fen = _board(tester).fen;
      await _tap(tester, 'open-report');
      await tester.tap(find.byKey(const Key('report-show-on-board')));
      await settleBoard(tester, rounds: 20);
      expect(find.byKey(const Key('report-card')), findsNothing);
      expect(_board(tester).fen, fen, reason: 'still on ply 5, not reset to the start');
    });
  });

  group('games that end by rule', () {
    testWidgets('threefold repetition at the end: result in the coach, no arrow, no to-move highlight', (tester) async {
      final env = TestEnv();
      final id = await _seedShuffle(env, 3); // 12 plies; the start position for the 4th time
      await pumpReview(tester, env, id, initialPly: 12);
      expect(tester.widget<Text>(find.byKey(const Key('coach-text'))).data, contains(l10n.coachGameEnds(l10n.evalResultDraw)));
      expect(_board(tester).shapes.whereType<Arrow>(), isEmpty);
      expect([for (final s in tester.widgetList<PlayerStrip>(find.byType(PlayerStrip))) s.toMove], [false, false]);

      // The same position in the middle of the game was not claimed: still in play.
      await tester.tap(find.byKey(const Key('nav-first')));
      await settleBoard(tester, rounds: 8);
      expect(_board(tester).shapes.whereType<Arrow>(), hasLength(1));
      expect(tester.widgetList<PlayerStrip>(find.byType(PlayerStrip)).where((s) => s.toMove), hasLength(1));
      await tester.tap(find.byKey(const Key('move-chip-4')));
      await settleBoard(tester, rounds: 12);
      expect(_board(tester).shapes.whereType<Arrow>(), hasLength(1));
      expect(tester.widget<Text>(find.byKey(const Key('coach-text'))).data, isNot(contains(l10n.coachGameEnds(l10n.evalResultDraw))));
    });

    testWidgets('50-move rule at the last position ends the game too', (tester) async {
      final env = TestEnv();
      const pgn = '[White "Alice"]\n[Black "Bob"]\n[SetUp "1"]\n[FEN "4k3/8/8/8/8/8/8/R3K3 w - - 98 80"]\n\n80. Ra2 Kd7 *';
      final saved = await env.games.save(NewGame(
        source: GameSource.paste,
        pgn: pgn,
        white: 'Alice',
        black: 'Bob',
        plyCount: 2,
        importedAt: 1,
        startFen: '4k3/8/8/8/8/8/8/R3K3 w - - 98 80',
      ));
      final id = saved.id;
      await env.analyses.upsert(AnalysisRecord(
        gameId: id,
        engine: 'Stockfish',
        depth: 16,
        multipv: 2,
        status: AnalysisStatus.running,
        completedPlies: 3,
        updatedAt: 1,
      ));
      const pvs = ['a1a2 e8d7', 'e8d7 e1d2', 'a2a8 d7e7'];
      for (var ply = 0; ply < 3; ply++) {
        await env.analyses.savePosition(
          id,
          ply,
          [PositionLineRecord(gameId: id, ply: ply, rank: 1, scoreCp: 600, depth: 16, pvUci: pvs[ply])],
          completedPlies: ply + 1,
          updatedAt: 1,
        );
      }
      await pumpReview(tester, env, id, initialPly: 2);
      expect(tester.widget<Text>(find.byKey(const Key('coach-text'))).data, contains(l10n.evalResultDraw));
      expect(_board(tester).shapes.whereType<Arrow>(), isEmpty);
      await tester.tap(find.byKey(const Key('nav-back')));
      await settleBoard(tester, rounds: 12);
      expect(_board(tester).shapes.whereType<Arrow>(), hasLength(1), reason: 'one ply earlier the game is still on');
    });
  });

  group('Chess960 castling where the king does not move', () {
    testWidgets('badge and highlight sit on the king, nothing is drawn on the rook\'s empty square', (tester) async {
      final env = TestEnv();
      const fen = 'bbqnnrkr/pppppppp/8/8/8/8/PPPPPPPP/BBQNNRKR w HFhf - 0 1';
      const pgn = '[Variant "Chess960"]\n[SetUp "1"]\n[FEN "$fen"]\n\n1. f4 f5 2. Rf2 Rf7 3. O-O *';
      final game = parsePgn(pgn).games.single;
      expect(game.plies.last.uci, 'g1h1', reason: 'king takes rook, the king does not move');
      final saved = await env.games.save(NewGame(
        source: GameSource.paste,
        pgn: pgn,
        white: 'Alice',
        black: 'Bob',
        variant: GameVariant.chess960,
        startFen: fen,
        plyCount: 5,
        importedAt: 1,
      ));
      final id = saved.id;
      await env.analyses.upsert(AnalysisRecord(
        gameId: id,
        engine: 'Stockfish',
        depth: 16,
        multipv: 2,
        status: AnalysisStatus.running,
        completedPlies: 6,
        updatedAt: 1,
      ));
      // Position 4 (before 3. O-O): the engine's best move is the castling move.
      const pvs = ['f2f4 f7f5', 'f7f5 f2f4', 'f1f2 f8f7', 'f8f7 f1f2', 'g1h1 g8h8', 'f7f6 h1h2'];
      for (var ply = 0; ply < 6; ply++) {
        await env.analyses.savePosition(
          id,
          ply,
          [
            PositionLineRecord(gameId: id, ply: ply, rank: 1, scoreCp: 30, depth: 16, pvUci: pvs[ply]),
            PositionLineRecord(gameId: id, ply: ply, rank: 2, scoreCp: 20, depth: 16, pvUci: pvs[ply]),
          ],
          completedPlies: ply + 1,
          updatedAt: 1,
        );
      }
      // Best move = the castling move: nothing to draw, and no crash.
      await pumpReview(tester, env, id, initialPly: 4);
      expect(tester.takeException(), isNull);
      expect(_board(tester).shapes.whereType<Arrow>(), isEmpty);

      await _tap(tester, 'nav-next');
      expect(tester.takeException(), isNull);
      expect(game.plies.last.san, 'O-O');
      final move = _board(tester).lastMove;
      expect(move, const NormalMove(from: Square.g1, to: Square.g1));
      final badges = _board(tester).shapes.whereType<CustomShape>().toList();
      expect(badges, hasLength(1));
      expect(badges.single.orig, Square.g1, reason: 'the king\'s square, not the (empty) square h1');
      // The board really shows the castled position: king g1, rook f1, h1 empty.
      expect(_board(tester).fen.split(' ').first.split('/').last, 'BBQNNRK1');
    });
  });

  group('key moments and graph, White point of view', () {
    testWidgets('the win chance is White\'s for both sides', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env); // stored labels: win 60 -> 50 from the mover's side
      await pumpReview(tester, env, id);
      await _tap(tester, 'open-key-moments');
      String subtitle(int ply) => tester.widget<Text>(find.descendant(of: find.byKey(Key('key-moment-$ply')), matching: find.byType(Text)).last).data!;
      // White moved (ply 5, Mistake): 60 -> 50 for White.
      expect(subtitle(5), l10n.keyMomentSubtitle('Mistake', l10n.keyMomentWinChance(60, 50)));
      // Black moved (ply 6, Blunder): 60 -> 50 for Black = 40 -> 50 for White.
      expect(subtitle(6), l10n.keyMomentSubtitle('Blunder', l10n.keyMomentWinChance(40, 50)));
      expect(subtitle(6), "Blunder · White's win chance 40% → 50%");
    });

    testWidgets('the graph announces the full move number and the side', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 6);
      final data = tester.getSemantics(find.byKey(const Key('eval-graph')).first).getSemanticsData();
      expect(data.value, 'Move 3, Black');
      expect(data.increasedValue, 'Move 4, White');
      expect(data.decreasedValue, 'Move 3, White');
      await _tap(tester, 'nav-first');
      final start = tester.getSemantics(find.byKey(const Key('eval-graph')).first).getSemanticsData();
      expect(start.value, 'Start position');
      expect(start.increasedValue, 'Move 1, White');
      handle.dispose();
    });
  });

  group('overflow menu', () {
    testWidgets('lists the arrow, side, re-analyse and delete entries', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      await tester.tap(find.byKey(const Key('board-menu')));
      await settleBoard(tester, rounds: 8);
      for (final k in ['menu-best-arrow', 'menu-set-side', 'menu-reanalyse', 'menu-delete']) {
        expect(find.byKey(Key(k)), findsOneWidget, reason: k);
      }
    });

    testWidgets('Re-analyse at depth restarts the analysis at the chosen depth', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      expect((await env.analyses.get(id))!.depth, 16);
      expect(await env.analyses.labels(id), hasLength(8));
      await pumpReview(tester, env, id);
      await _openMenu(tester, 'menu-reanalyse');
      // The current preset (Normal, 16) is marked.
      final normal = tester.getSemantics(find.byKey(const Key('reanalyse-normal')));
      expect(normal.getSemanticsData().flagsCollection.isChecked, CheckedState.isTrue);
      await tester.tap(find.byKey(const Key('reanalyse-deep')));
      await settleBoard(tester, rounds: 120);
      final analysis = (await env.analyses.get(id))!;
      expect(analysis.depth, 20);
      expect(analysis.status, AnalysisStatus.completed);
      // Fresh start: the seeded lines were thrown away and rewritten by the new job.
      expect(analysis.updatedAt, greaterThan(1));
      final first = (await env.analyses.positionLines(id)).first;
      expect(first.pvUci, isNot(reviewLines[0]!.$1));
      expect(find.text(l10n.analysisCompleted), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Delete game asks, then removes the game and its running job, and returns to the library', (tester) async {
      final fakes = <FakeEngineDriver>[];
      final env = TestEnv(driverFactory: () async {
        final f = FakeEngineDriver.permissive()..holdSearch = 2;
        fakes.add(f);
        return f;
      });
      final saved = await env.games.save(NewGame(
        source: GameSource.paste,
        pgn: reviewPgn,
        white: 'Alice',
        black: 'Bob',
        plyCount: 8,
        importedAt: 1,
      ));
      final id = saved.id;
      await env.pump(tester);
      await tester.tap(find.textContaining('Alice'));
      await settleBoard(tester, rounds: 40);
      expect(find.byKey(const Key('board-menu')), findsOneWidget);
      expect(find.text(l10n.analysisRunning(1, 9)), findsOneWidget, reason: 'analysis started and is held');

      // Cancel in the dialog keeps everything.
      await _openMenu(tester, 'menu-delete');
      expect(find.text(l10n.boardDeleteTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete-cancel')));
      await settleBoard(tester, rounds: 12);
      expect(await env.games.get(id), isNotNull);

      await _openMenu(tester, 'menu-delete');
      await tester.tap(find.byKey(const Key('delete-confirm')));
      await settleBoard(tester, rounds: 60);
      expect(await env.games.get(id), isNull);
      expect(find.byKey(const Key('board-menu')), findsNothing, reason: 'back on the library');
      expect(find.textContaining('Alice'), findsNothing);
      final container = ProviderScope.containerOf(tester.element(find.byType(GlyphApp)));
      expect(container.read(analysisJobProvider.notifier).isActive(id), isFalse);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
    });
  });

  group('auto-start only for games nobody has started or cancelled', () {
    Future<(ProviderContainer, int, int, int)> setUpQueue(TestEnv env) async {
      Future<int> save(String name) async => (await env.games.save(NewGame(
            source: GameSource.paste,
            pgn: reviewPgn,
            white: name,
            black: 'Bob',
            plyCount: 8,
            importedAt: 1,
          )))
              .id;
      final a = await save('Running');
      final b = await save('QueuedB');
      final c = await save('QueuedC');
      final container = ProviderContainer(overrides: env.overrides);
      addTearDown(container.dispose);
      final jobs = container.read(analysisJobProvider.notifier);
      for (final id in [a, b, c]) {
        await jobs.analyse((await env.games.get(id))!);
      }
      return (container, a, b, c);
    }

    Future<void> stopAll(WidgetTester tester, ProviderContainer container, List<int> ids) async {
      final jobs = container.read(analysisJobProvider.notifier);
      for (final id in ids) {
        unawaited(jobs.cancel(id)); // stopping the held search needs the fake clock to advance
      }
      await settleBoard(tester, rounds: 40);
    }

    TestEnv held() => TestEnv(driverFactory: () async => FakeEngineDriver.permissive()..holdSearch = 1);

    testWidgets('opening the board of a queued game does not move it to the back of the queue', (tester) async {
      final env = held();
      final (container, a, b, c) = await setUpQueue(env);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      expect(container.read(analysisQueueProvider), [b, c]);
      await pumpReview(tester, env, b, container: container);
      await settleBoard(tester, rounds: 20);
      expect(find.text(l10n.analysisQueued), findsOneWidget);
      expect(container.read(analysisQueueProvider), [b, c], reason: 'B is still ahead of C');
      expect(container.read(analysisJobProvider.notifier).isActive(a), isTrue);
      await stopAll(tester, container, [a, b, c]);
    });

    testWidgets('a game cancelled while queued shows Resume and is not restarted by reopening', (tester) async {
      final env = held();
      final (container, a, b, c) = await setUpQueue(env);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await container.read(analysisJobProvider.notifier).cancel(b); // queued: nothing to stop
      expect(container.read(analysisQueueProvider), [c]);
      await pumpReview(tester, env, b, container: container);
      await settleBoard(tester, rounds: 20);
      expect(container.read(analysisQueueProvider), [c], reason: 'not enqueued again');
      expect(find.text(l10n.analysisCancelled(0, 9)), findsOneWidget);
      expect(find.text(l10n.analysisResume), findsOneWidget);
      // Resume is the user's explicit choice and does enqueue it.
      await tester.tap(find.text(l10n.analysisResume));
      await settleBoard(tester, rounds: 20);
      expect(container.read(analysisQueueProvider), [c, b]);
      await stopAll(tester, container, [a, b, c]);
    });

    testWidgets('a never-started game still starts when its board opens', (tester) async {
      final env = TestEnv();
      final saved = await env.games.save(NewGame(
        source: GameSource.paste,
        pgn: reviewPgn,
        white: 'Alice',
        black: 'Bob',
        plyCount: 8,
        importedAt: 1,
      ));
      await pumpReview(tester, env, saved.id);
      await settleBoard(tester, rounds: 80);
      expect((await env.analyses.get(saved.id))?.status, AnalysisStatus.completed);
    });
  });
}
