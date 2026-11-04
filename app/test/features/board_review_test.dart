import 'dart:async';

import 'package:chessground/chessground.dart' show Arrow, CustomShape, StaticChessboard;
import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/engine/engine_providers.dart';
import 'package:glyph/features/board/eval_graph.dart';
import 'package:glyph/features/board/move_badge.dart';
import 'package:glyph/features/board/move_list.dart';
import 'package:glyph/features/report/report_screen.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../support/review_fixture.dart';
import '../support/test_app.dart';

final Game _game = parsePgn(reviewPgn).games.single;

StaticChessboard _board(WidgetTester t) => t.widget<StaticChessboard>(find.byType(StaticChessboard));

List<CustomShape> _badgeShapes(WidgetTester t) => _board(t).shapes.whereType<CustomShape>().toList();

MoveLabel? _boardBadge(WidgetTester t) {
  final badges = find.descendant(of: find.byType(StaticChessboard), matching: find.byType(MoveBadge));
  return badges.evaluate().isEmpty ? null : t.widget<MoveBadge>(badges).label;
}

String _text(WidgetTester t, String key) {
  final f = find.byKey(Key(key));
  final w = t.widget(f);
  return w is Text ? w.data! : t.widget<Text>(find.descendant(of: f, matching: find.byType(Text))).data!;
}

String _fenAt(int ply) => ply == 0 ? _game.startFen : _game.plies[ply - 1].fen;

Future<void> _tap(WidgetTester t, String key) async {
  await t.tap(find.byKey(Key(key)));
  await settleBoard(t, rounds: 12);
}

MoveLabel? _chipBadge(WidgetTester t, int ply) {
  final f = find.descendant(of: find.byKey(Key('move-chip-$ply')), matching: find.byType(MoveBadge));
  return f.evaluate().isEmpty ? null : t.widget<MoveBadge>(f).label;
}

void main() {
  group('navigation', () {
    testWidgets('buttons step through the game; first/last jump; ends are disabled', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);

      expect(_board(tester).fen, _fenAt(0));
      expect(tester.widget<IconButton>(find.byKey(const Key('nav-back'))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const Key('nav-first'))).onPressed, isNull);

      await _tap(tester, 'nav-next');
      expect(_board(tester).fen, _fenAt(1));
      await _tap(tester, 'nav-next');
      expect(_board(tester).fen, _fenAt(2));
      await _tap(tester, 'nav-back');
      expect(_board(tester).fen, _fenAt(1));
      await _tap(tester, 'nav-last');
      expect(_board(tester).fen, _fenAt(8));
      expect(tester.widget<IconButton>(find.byKey(const Key('nav-next'))).onPressed, isNull);
      expect(tester.widget<IconButton>(find.byKey(const Key('nav-last'))).onPressed, isNull);
      await _tap(tester, 'nav-first');
      expect(_board(tester).fen, _fenAt(0));
    });

    testWidgets('arrow and home/end keys navigate', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await settleBoard(tester, rounds: 5);
      expect(_board(tester).fen, _fenAt(2));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await settleBoard(tester, rounds: 5);
      expect(_board(tester).fen, _fenAt(1));
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await settleBoard(tester, rounds: 5);
      expect(_board(tester).fen, _fenAt(8));
      await tester.sendKeyEvent(LogicalKeyboardKey.home);
      await settleBoard(tester, rounds: 5);
      expect(_board(tester).fen, _fenAt(0));
    });

    testWidgets('a horizontal swipe below the board steps forward and back', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      await tester.fling(find.byKey(const Key('swipe-area')), const Offset(-300, 0), 1200);
      await settleBoard(tester, rounds: 12);
      expect(_board(tester).fen, _fenAt(1));
      await tester.fling(find.byKey(const Key('swipe-area')), const Offset(-300, 0), 1200);
      await settleBoard(tester, rounds: 12);
      expect(_board(tester).fen, _fenAt(2));
      await tester.fling(find.byKey(const Key('swipe-area')), const Offset(300, 0), 1200);
      await settleBoard(tester, rounds: 12);
      expect(_board(tester).fen, _fenAt(1));
      // Swiping right at the start does nothing.
      await tester.fling(find.byKey(const Key('swipe-area')), const Offset(300, 0), 1200);
      await tester.fling(find.byKey(const Key('swipe-area')), const Offset(300, 0), 1200);
      await settleBoard(tester, rounds: 12);
      expect(_board(tester).fen, _fenAt(0));
    });

    testWidgets('flip turns the board and the strips around, and back', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(_board(tester).orientation, Side.white);
      final bottomBefore = tester.getTopLeft(find.byKey(const Key('strip-name-white'))).dy;
      final topBefore = tester.getTopLeft(find.byKey(const Key('strip-name-black'))).dy;
      expect(bottomBefore, greaterThan(topBefore));
      await _tap(tester, 'flip-board');
      expect(_board(tester).orientation, Side.black);
      expect(tester.getTopLeft(find.byKey(const Key('strip-name-white'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('strip-name-black'))).dy));
      await _tap(tester, 'flip-board');
      expect(_board(tester).orientation, Side.white);
    });

    testWidgets('pieces glide for one ply and jump for longer moves', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      await _tap(tester, 'nav-next');
      expect(_board(tester).settings.animationDuration, greaterThan(Duration.zero));
      await _tap(tester, 'nav-last');
      expect(_board(tester).settings.animationDuration, Duration.zero);
    });
  });

  group('move list', () {
    testWidgets('tapping a chip selects that move; the selected chip is highlighted', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      await tester.ensureVisible(find.byKey(const Key('move-chip-5')));
      await _tap(tester, 'move-chip-5');
      expect(_board(tester).fen, _fenAt(5));
      expect(_text(tester, 'coach-title'), startsWith('3. Bc4'));

      Color? fill(int ply) => tester
          .widget<Material>(find.ancestor(of: find.byKey(Key('move-chip-$ply')), matching: find.byType(Material)).first)
          .color;
      final scheme = Theme.of(tester.element(find.byType(MoveList))).colorScheme;
      expect(fill(5), scheme.primaryContainer);
      expect(fill(4), scheme.surfaceContainerHighest);
      await _tap(tester, 'nav-next');
      expect(fill(6), scheme.primaryContainer);
      expect(fill(5), scheme.surfaceContainerHighest);
    });

    testWidgets('numbers White moves 4. and Black moves 4…, and shows the badges', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(find.text('4. O-O'), findsOneWidget);
      expect(find.text('4… Nf6'), findsOneWidget);
      expect(_chipBadge(tester, 1), MoveLabel.best);
      expect(_chipBadge(tester, 6), MoveLabel.blunder);
      expect(_chipBadge(tester, 7), MoveLabel.brilliant);
    });
  });

  group('badges and arrow on the board', () {
    testWidgets('the badge sits on the destination square with the move\'s label', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(_badgeShapes(tester), isEmpty, reason: 'no badge at the start position');
      const expected = {
        1: (Square.e4, MoveLabel.best),
        2: (Square.e5, MoveLabel.excellent),
        3: (Square.f3, MoveLabel.great),
        4: (Square.c6, MoveLabel.inaccuracy),
        5: (Square.c4, MoveLabel.mistake),
        6: (Square.c5, MoveLabel.blunder),
        // Castling is stored king-takes-rook (e1h1); the badge belongs on g1.
        7: (Square.g1, MoveLabel.brilliant),
        8: (Square.f6, MoveLabel.miss),
      };
      for (final e in expected.entries) {
        await tester.tap(find.byKey(const Key('nav-next')));
        await settleBoard(tester, rounds: 12);
        final shapes = _badgeShapes(tester);
        expect(shapes, hasLength(1), reason: 'ply ${e.key}');
        expect(shapes.single.orig, e.value.$1, reason: 'ply ${e.key}');
        expect(_boardBadge(tester), e.value.$2, reason: 'ply ${e.key}');
      }
    });

    testWidgets('castling: badge on the king\'s landing square g1, last move e1-g1', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 7);
      final shapes = _badgeShapes(tester);
      expect(shapes.single.orig, Square.g1);
      expect(_boardBadge(tester), MoveLabel.brilliant);
      expect(_board(tester).lastMove, const NormalMove(from: Square.e1, to: Square.g1));
    });

    testWidgets('badges announce their label to screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 6);
      expect(find.bySemanticsLabel('Blunder on c5'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Board\\. Position after 3… Bc5, Blunder\\. White at the bottom\\.\$')), findsOneWidget);
      handle.dispose();
    });

    testWidgets('best-move arrow: engine line 1 of the shown position; castling points at g1', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      Arrow? arrow() => _board(tester).shapes.whereType<Arrow>().firstOrNull;
      expect((arrow()!.orig, arrow()!.dest), (Square.e2, Square.e4));
      await _tap(tester, 'nav-next');
      expect((arrow()!.orig, arrow()!.dest), (Square.e7, Square.e5));
      // Position 6: the engine castles, stored as e1h1 (king takes rook).
      await tester.tap(find.byKey(const Key('flip-board'))); // orientation must not matter
      await settleBoard(tester, rounds: 5);
      await tester.tap(find.byKey(const Key('flip-board')));
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const Key('nav-next')));
        await settleBoard(tester, rounds: 5);
      }
      expect(_board(tester).fen, _fenAt(6));
      expect((arrow()!.orig, arrow()!.dest), (Square.e1, Square.g1));
    });

    testWidgets('the arrow can be switched off in the menu', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(_board(tester).shapes.whereType<Arrow>(), hasLength(1));
      await _tap(tester, 'board-menu');
      await tester.tap(find.byKey(const Key('menu-best-arrow')));
      await settleBoard(tester, rounds: 12);
      expect(_board(tester).shapes.whereType<Arrow>(), isEmpty);
    });
  });

  group('eval gauge', () {
    double share(WidgetTester t) =>
        t.widget<AnimatedFractionallySizedBox>(find.byKey(const Key('eval-gauge-white'))).widthFactor!;

    testWidgets('White POV: a White edge fills past half, a Black edge below half', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, cpOverride: {8: -150});
      await pumpReview(tester, env, id);
      expect(_text(tester, 'eval-gauge-text'), '+0.3');
      expect(share(tester), closeTo(WinPercent.fromCp(30) / 100, 1e-9));
      expect(share(tester), greaterThan(0.5));

      await _tap(tester, 'nav-last');
      expect(_text(tester, 'eval-gauge-text'), '-1.5');
      expect(share(tester), closeTo(WinPercent.fromCp(-150) / 100, 1e-9));
      expect(share(tester), lessThan(0.5));
    });

    testWidgets('a mate shows #N / -#N and a (nearly) full bar for the mating side', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, mateOverride: {8: -2, 7: 4});
      await pumpReview(tester, env, id, initialPly: 7);
      expect(_text(tester, 'eval-gauge-text'), '#4');
      expect(share(tester), closeTo(WinPercent.mateWin / 100, 1e-9));
      await _tap(tester, 'nav-next');
      expect(_text(tester, 'eval-gauge-text'), '-#2');
      expect(share(tester), closeTo(1 - WinPercent.mateWin / 100, 1e-9));
    });

    testWidgets('has a text alternative', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(find.bySemanticsLabel(RegExp(r"Evaluation \+0\.3\. White's win chance is 53 percent\.")), findsOneWidget);
      handle.dispose();
    });

    testWidgets('an unanalysed position shows no number', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, status: AnalysisStatus.paused, labels: false, positions: 3);
      await pumpReview(tester, env, id, initialPly: 6);
      expect(_text(tester, 'eval-gauge-text'), l10n.evalUnknown);
      expect(share(tester), 0.5);
    });
  });

  group('player strips and orientation', () {
    testWidgets('clocks follow the move; the start shows the base time', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(_text(tester, 'strip-clock-white'), '5:00');
      expect(_text(tester, 'strip-clock-black'), '5:00');
      await tester.tap(find.byKey(const Key('nav-last')));
      await settleBoard(tester, rounds: 5);
      expect(_text(tester, 'strip-clock-white'), '4:20');
      expect(_text(tester, 'strip-clock-black'), '4:10');
      await tester.tap(find.byKey(const Key('move-chip-5')));
      await settleBoard(tester, rounds: 5);
      expect(_text(tester, 'strip-clock-white'), '4:40');
      expect(_text(tester, 'strip-clock-black'), '4:50');
    });

    testWidgets('names and ratings', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(find.text('Alice'), findsWidgets);
      expect(find.text(l10n.playerRating(1500)), findsOneWidget);
      expect(find.text(l10n.playerRating(1400)), findsOneWidget);
    });

    testWidgets('a game without clocks shows none', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, pgn: reviewPgn.replaceAll(RegExp(r' \{\[%clk [^}]*\}'), ''));
      await pumpReview(tester, env, id);
      expect(find.byKey(const Key('strip-clock-white')), findsNothing);
    });

    testWidgets('auto-orientation: a Black user sees Black at the bottom', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, userSide: Side.black);
      await pumpReview(tester, env, id);
      expect(_board(tester).orientation, Side.black);
      // Black's strip is below the board, and marked as the user.
      expect(tester.getTopLeft(find.byKey(const Key('strip-name-black'))).dy,
          greaterThan(tester.getTopLeft(find.byKey(const Key('strip-name-white'))).dy));
      expect(find.text(l10n.playerYou), findsOneWidget);
      // Flip still works on top of the automatic orientation.
      await _tap(tester, 'flip-board');
      expect(_board(tester).orientation, Side.white);
    });

    testWidgets('no known side: White at the bottom', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(_board(tester).orientation, Side.white);
      expect(find.text(l10n.playerYou), findsNothing);
    });

    testWidgets('"Set your side" overrides the side per game and re-orients', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, userSide: Side.white);
      await pumpReview(tester, env, id);
      expect(_board(tester).orientation, Side.white);

      await _tap(tester, 'board-menu');
      await tester.tap(find.byKey(const Key('menu-set-side')));
      await settleBoard(tester, rounds: 12);
      expect(find.text(l10n.boardYourSideTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('your-side-black')));
      await settleBoard(tester, rounds: 20);
      expect((await env.games.get(id))!.userSide, Side.black);
      expect(_board(tester).orientation, Side.black);

      await _tap(tester, 'board-menu');
      await tester.tap(find.byKey(const Key('menu-set-side')));
      await settleBoard(tester, rounds: 12);
      await tester.tap(find.byKey(const Key('your-side-none')));
      await settleBoard(tester, rounds: 20);
      expect((await env.games.get(id))!.userSide, isNull);
      expect(_board(tester).orientation, Side.white);
    });
  });

  group('engine lines', () {
    testWidgets('top two lines of the shown position in SAN with eval and depth', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(_text(tester, 'engine-line-moves-1'), '1. e4 e5 2. Nf3');
      expect(_text(tester, 'engine-line-moves-2'), '1. d4 d5');
      expect(_text(tester, 'engine-line-score-1'), '+0.3');
      expect(find.text(l10n.engineLineDepth(16)), findsNWidgets(2));
      await _tap(tester, 'nav-next');
      expect(_text(tester, 'engine-line-moves-1'), '1… e5 2. Nf3');
    });

    testWidgets('Chess960 king-takes-rook UCI is shown as O-O', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 6);
      expect(_text(tester, 'engine-line-moves-1'), '4. O-O Nf6 5. d3');
    });

    testWidgets('can be collapsed', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      await _tap(tester, 'engine-lines-toggle');
      expect(find.byKey(const Key('engine-line-moves-1')), findsNothing);
      await _tap(tester, 'engine-lines-toggle');
      expect(find.byKey(const Key('engine-line-moves-1')), findsOneWidget);
    });

    testWidgets('a position the engine has not reached says so', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, status: AnalysisStatus.paused, labels: false, positions: 3);
      await pumpReview(tester, env, id, initialPly: 5);
      expect(find.byKey(const Key('engine-lines-waiting')), findsOneWidget);
    });
  });

  group('coach card', () {
    testWidgets('start position names the opening and has no Explain button', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      expect(_text(tester, 'coach-text'), l10n.coachStartOpening('C50 Italian Game'));
      expect(find.byKey(const Key('explain-button')), findsNothing);
    });

    testWidgets('deterministic one-liners from label, best move and evals', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      const expected = {
        1: 'Best move. Eval is +0.3.',
        2: 'Best was e5 (+0.3). After e5, eval is +0.3.',
        3: 'Great: the only move that keeps the outcome. Eval is +0.3.',
        4: 'Best was Nf6 (+0.3). After Nc6, eval is +0.3.',
        5: 'Best was Bb5 (+0.3). After Bc4, eval is +0.2.',
        6: 'Best was Nf6 (+0.2). After Bc5, eval is +0.3.',
        7: 'Brilliant: a sacrifice that works. Eval is +0.3.',
        8: 'Missed chance. Best was d6 (+0.3). After Nf6, eval is +0.3.',
      };
      for (final e in expected.entries) {
        await tester.tap(find.byKey(const Key('nav-next')));
        await settleBoard(tester, rounds: 8);
        // Ply 2: the stored "excellent" move equals the engine's top move.
        final want = e.key == 2 ? 'Best move. Eval is +0.3.' : e.value;
        expect(_text(tester, 'coach-text'), want, reason: 'ply ${e.key}');
      }
    });

    testWidgets('title shows the move and the label; Black moves use the ellipsis', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 6);
      expect(_text(tester, 'coach-title'), '3… Bc5 · Blunder');
      await _tap(tester, 'nav-next');
      expect(_text(tester, 'coach-title'), '4. O-O · Brilliant');
    });

    testWidgets('the Explain button is filled tonal for key labels, outlined otherwise', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 1); // Best
      expect(find.byKey(const Key('explain-button')), findsOneWidget);
      expect(tester.widget(find.byKey(const Key('explain-button'))), isA<OutlinedButton>());
      await tester.tap(find.byKey(const Key('move-chip-6'))); // Blunder
      await settleBoard(tester, rounds: 8);
      expect(tester.widget(find.byKey(const Key('explain-button'))), isA<FilledButton>());
      await tester.tap(find.byKey(const Key('move-chip-4'))); // Inaccuracy
      await settleBoard(tester, rounds: 8);
      expect(tester.widget(find.byKey(const Key('explain-button'))), isA<FilledButton>());
      await tester.tap(find.byKey(const Key('move-chip-2'))); // Excellent
      await settleBoard(tester, rounds: 8);
      expect(tester.widget(find.byKey(const Key('explain-button'))), isA<OutlinedButton>());
    });

    testWidgets('a move the engine has not reached yet says it is waiting', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, status: AnalysisStatus.paused, labels: false, positions: 3);
      await pumpReview(tester, env, id, initialPly: 6);
      expect(_text(tester, 'coach-text'), l10n.coachWaiting);
    });
  });

  group('key moments sheet', () {
    testWidgets('lists Brilliant, Great, Miss, Mistake and Blunder per side; tapping jumps', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, userSide: Side.black);
      await pumpReview(tester, env, id);
      await _tap(tester, 'open-key-moments');
      expect(find.text(l10n.boardKeyMoments), findsWidgets);
      for (final ply in [3, 5, 6, 7, 8]) {
        expect(find.byKey(Key('key-moment-$ply')), findsOneWidget, reason: 'ply $ply');
      }
      // Best, Excellent and Inaccuracy are not key moments.
      for (final ply in [1, 2, 4]) {
        expect(find.byKey(Key('key-moment-$ply')), findsNothing, reason: 'ply $ply');
      }
      expect(find.text('White Alice'), findsOneWidget);
      expect(find.text('Black Bob (${l10n.playerYou})'), findsOneWidget);
      expect(find.text('4. O-O'), findsWidgets);

      await tester.tap(find.byKey(const Key('key-moment-6')));
      await settleBoard(tester, rounds: 20);
      expect(find.byKey(const Key('key-moments-list')), findsNothing);
      expect(_board(tester).fen, _fenAt(6));
    });

    testWidgets('empty state', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, labels: false, status: AnalysisStatus.paused, positions: 1);
      await pumpReview(tester, env, id);
      await _tap(tester, 'open-key-moments');
      expect(find.text(l10n.keyMomentsPending), findsOneWidget);
    });
  });

  group('report', () {
    Future<void> openReport(WidgetTester t) async {
      await t.tap(find.byKey(const Key('open-report')));
      await settleBoard(t, rounds: 30);
    }

    testWidgets('accuracy (rounded like lichess), label counts per side, opening', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, whiteAccuracy: 87.4, blackAccuracy: 62.5);
      await pumpReview(tester, env, id);
      await openReport(tester);
      expect(find.byType(ReportCard), findsOneWidget);
      expect(_text(tester, 'report-accuracy-white'), '87');
      expect(_text(tester, 'report-accuracy-black'), '63'); // 62.5 rounds half up, as lichess does
      expect(find.byKey(const Key('report-pending')), findsNothing);
      expect(_text(tester, 'report-opening'), 'C50 · Italian Game');
      const white = {
        MoveLabel.best: 1,
        MoveLabel.great: 1,
        MoveLabel.mistake: 1,
        MoveLabel.brilliant: 1,
      };
      const black = {
        MoveLabel.excellent: 1,
        MoveLabel.inaccuracy: 1,
        MoveLabel.blunder: 1,
        MoveLabel.miss: 1,
      };
      for (final label in MoveLabel.values) {
        expect(_text(tester, 'report-count-${label.name}-white'), '${white[label] ?? 0}', reason: '${label.name} white');
        expect(_text(tester, 'report-count-${label.name}-black'), '${black[label] ?? 0}', reason: '${label.name} black');
      }
    });

    testWidgets('accuracy is not shown before the analysis completes', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env, status: AnalysisStatus.paused, labels: false, positions: 4);
      await pumpReview(tester, env, id);
      await openReport(tester);
      expect(_text(tester, 'report-accuracy-white'), l10n.reportNoValue);
      expect(find.byKey(const Key('report-pending')), findsOneWidget);
    });

    testWidgets('tapping the graph and "Show on board" jumps the board', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      await openReport(tester);
      final rect = tester.getRect(find.byKey(const Key('eval-graph')));
      await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy)); // ply 4 of 8
      await settleBoard(tester, rounds: 8);
      await tester.tap(find.byKey(const Key('report-show-on-board')));
      await settleBoard(tester, rounds: 30);
      expect(find.byType(ReportCard), findsNothing);
      expect(_board(tester).fen, _fenAt(4));
    });
  });

  group('eval graph', () {
    testWidgets('tap and drag jump to the nearest ply', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      final finder = find.byKey(const Key('eval-graph'));
      await tester.ensureVisible(finder);
      await settleBoard(tester, rounds: 3);
      final rect = tester.getRect(finder);
      await tester.tapAt(Offset(rect.left + rect.width * 0.25, rect.center.dy));
      await settleBoard(tester, rounds: 8);
      expect(_board(tester).fen, _fenAt(2));
      // The coach card above changes height with the move: measure again.
      final moved = tester.getRect(finder);
      final gesture = await tester.startGesture(Offset(moved.left + moved.width * 0.25, moved.center.dy));
      for (var i = 0; i < 10; i++) {
        await gesture.moveBy(Offset(rect.width * 0.05, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await gesture.up();
      await settleBoard(tester, rounds: 8);
      expect(_board(tester).fen, _fenAt(6));
    });

    test('painter geometry: ply to x, Win% to y (White up)', () {
      expect(EvalGraphPainter.xOf(0, 8, 400), 0);
      expect(EvalGraphPainter.xOf(8, 8, 400), 400);
      expect(EvalGraphPainter.xOf(4, 8, 400), 200);
      expect(EvalGraphPainter.yOf(100, 80), 0);
      expect(EvalGraphPainter.yOf(0, 80), 80);
      expect(EvalGraphPainter.yOf(50, 80), 40);
    });

    testWidgets('has a slider semantics that steps through the plies', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 3);
      final node = tester.getSemantics(find.byKey(const Key('eval-graph')).first);
      expect(node.value, l10n.evalGraphValue(3, 8));
      handle.dispose();
    });
  });

  group('themes', () {
    testWidgets('light and dark both render badges with their theme colours', (tester) async {
      for (final brightness in Brightness.values) {
        final env = TestEnv();
        final id = await seedReview(env);
        await pumpReview(tester, env, id, initialPly: 6, brightness: brightness);
        final badge = find.descendant(of: find.byType(StaticChessboard), matching: find.byType(MoveBadge));
        final style = badgeStyleOf(tester.element(badge), MoveLabel.blunder);
        final disc = tester.widget<Container>(find.descendant(of: badge, matching: find.byType(Container)).first);
        expect((disc.decoration as BoxDecoration).color, style.background);
        expect(Theme.of(tester.element(badge)).brightness, brightness);
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('small phones and large text', () {
    for (final brightness in Brightness.values) {
      testWidgets('360x740 with 1.5x text and long names, ${brightness.name}: no overflow, board fits the width', (tester) async {
        final env = TestEnv();
        final id = await seedReview(
          env,
          pgn: reviewPgn.replaceAll('"Alice"', '"A very long player name indeed"').replaceAll('"Bob"', '"Another remarkably long name"'),
        );
        tester.platformDispatcher.textScaleFactorTestValue = 1.5;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await pumpReview(tester, env, id, initialPly: 6, brightness: brightness);
        tester.view.physicalSize = const Size(360, 740);
        await settleBoard(tester, rounds: 10);
        expect(tester.takeException(), isNull);
        expect(tester.getSize(find.byType(StaticChessboard)).width, 360);
        // Everything stays reachable by scrolling; the move list and the bottom bar are pinned.
        expect(find.byKey(const Key('nav-next')), findsOneWidget);
        expect(find.byKey(const Key('move-chip-6')), findsOneWidget);
        await tester.scrollUntilVisible(find.byKey(const Key('coach-card')), 200, scrollable: find.byType(Scrollable).first);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('screen reader labels', () {
    testWidgets('move chips, player strips, coach card and nav buttons are labelled', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv();
      final id = await seedReview(env, userSide: Side.white);
      await pumpReview(tester, env, id, initialPly: 5);
      expect(find.bySemanticsLabel('3. Bc4, Mistake'), findsOneWidget);
      expect(find.bySemanticsLabel('3\u2026 Bc5, Blunder'), findsOneWidget);
      expect(find.bySemanticsLabel('White, Alice, You, rated 1500, clock 4:40'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp(r'^3\. Bc4 \u00b7 Mistake\. Best was Bb5')), findsOneWidget);
      for (final tip in [l10n.boardNextMove, l10n.boardPreviousMove, l10n.boardFirstMove, l10n.boardLastMove, l10n.boardKeyMoments, l10n.boardReport, l10n.boardFlip]) {
        expect(find.byTooltip(tip), findsOneWidget, reason: tip);
      }
      handle.dispose();
    });
  });

  group('touch targets', () {
    testWidgets('navigation, menu and chips are at least 48 dp', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 3);
      for (final key in ['nav-first', 'nav-back', 'nav-next', 'nav-last', 'open-key-moments', 'open-report', 'flip-board', 'board-menu', 'engine-lines-toggle']) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.width, greaterThanOrEqualTo(48), reason: key);
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
      for (final ply in [1, 4, 8]) {
        expect(tester.getSize(find.byKey(Key('move-chip-$ply'))).height, greaterThanOrEqualTo(48), reason: 'chip $ply');
      }
    });
  });

  group('progressive fill during analysis', () {
    testWidgets('badges appear while the engine works, are in-memory only, and match the final labels', (tester) async {
      final fakes = <FakeEngineDriver>[];
      final env = TestEnv(driverFactory: () async {
        final f = FakeEngineDriver.permissive();
        if (fakes.isEmpty) f.holdSearch = 4; // positions 0..2 finish, the 4th search stalls
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
      final container = await pumpReview(tester, env, id);

      // Analysis started by itself and is held at 3 of 9 positions.
      expect(find.text(l10n.analysisRunning(3, 9)), findsOneWidget);
      expect(_chipBadge(tester, 1), isNotNull, reason: 'ply 1 is labelled as soon as its position is analysed');
      expect(_chipBadge(tester, 2), isNotNull);
      for (var ply = 3; ply <= 8; ply++) {
        expect(_chipBadge(tester, ply), isNull, reason: 'ply $ply is not analysed yet');
      }
      // Provisional labels are never persisted.
      expect(await env.analyses.labels(id), isEmpty);
      // Navigation stays possible while the analysis runs.
      await tester.tap(find.byKey(const Key('nav-next')));
      await settleBoard(tester, rounds: 10);
      expect(_board(tester).fen, _fenAt(1));
      expect(_boardBadge(tester), isNotNull);
      final provisional = [for (var p = 1; p <= 2; p++) _chipBadge(tester, p)];

      // Let the engine finish: the rest fills in and the labels get stored.
      unawaited(container.read(analysisJobProvider.notifier).cancel(id));
      await settleBoard(tester, rounds: 30);
      expect(find.text(l10n.analysisCancelled(3, 9)), findsOneWidget);
      await tester.tap(find.text(l10n.analysisResume));
      await settleBoard(tester, rounds: 80);
      expect(find.text(l10n.analysisCompleted), findsOneWidget);
      for (var ply = 1; ply <= 8; ply++) {
        expect(_chipBadge(tester, ply), isNotNull, reason: 'ply $ply');
      }
      expect(await env.analyses.labels(id), hasLength(8));
      // The labels that were shown early are the ones that were stored.
      expect([for (var p = 1; p <= 2; p++) _chipBadge(tester, p)], provisional);
    });
  });
}
