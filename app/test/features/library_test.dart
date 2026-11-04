import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/engine/engine_providers.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

void main() {
  testWidgets('empty state', (tester) async {
    await TestEnv().pump(tester);
    expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
    expect(find.text(l10n.libraryEmptyAction), findsOneWidget);
    expect(find.text(l10n.libraryImportFab), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('empty-state button opens the import sheet', (tester) async {
    await TestEnv().pump(tester);
    await tester.tap(find.text(l10n.libraryEmptyAction));
    await tester.pumpAndSettle();
    expect(find.text(l10n.importPastePgn), findsOneWidget);
  });

  testWidgets('list: players, result, date, source, analysis status and accuracy chips', (tester) async {
    final env = TestEnv();
    await env.seed(white: 'Alice', black: 'Bob', result: '1-0', importedAt: 1, plyCount: 41);
    await env.seed(
      white: 'Carol',
      black: 'Dave',
      result: '1/2-1/2',
      date: '2026.10.01',
      source: GameSource.lichess,
      importedAt: 2,
      status: AnalysisStatus.completed,
      completedPlies: 40,
      whiteAccuracy: 91.4,
      blackAccuracy: 78.6,
      userSide: Side.black,
      eco: 'C60',
      openingName: 'Ruy Lopez',
    );
    await env.seed(
      white: 'Erin',
      black: 'Frank',
      result: '0-1',
      source: GameSource.file,
      importedAt: 3,
      plyCount: 40,
      status: AnalysisStatus.cancelled,
      completedPlies: 10,
    );
    await env.seed(white: 'Gus', black: 'Hana', result: '*', source: GameSource.share, importedAt: 4, status: AnalysisStatus.running, completedPlies: 20);
    await env.pump(tester);

    // Newest first.
    final titles = tester.widgetList<Text>(find.textContaining(' – ')).map((t) => t.data).toList();
    expect(titles, [
      'Gus (1500) – Hana',
      'Erin (1500) – Frank',
      'Carol (1500) – Dave',
      'Alice (1500) – Bob',
    ]);

    // Game 1 (oldest): never analysed, pasted.
    expect(find.text(l10n.libraryAnalysisNone), findsOneWidget);
    expect(find.text(l10n.librarySourcePaste), findsOneWidget);
    expect(find.text(l10n.libraryMoveCount(21)), findsOneWidget); // 41 plies -> 21 moves
    // Game 2: lichess, analysed, accuracy chips, user side, opening, ½-½, date.
    expect(find.text(l10n.librarySourceLichess), findsOneWidget);
    expect(find.text(l10n.libraryAnalysisDone), findsOneWidget);
    expect(find.text(l10n.libraryAccuracyWhite('91')), findsOneWidget);
    expect(find.text(l10n.libraryAccuracyBlack('79')), findsOneWidget);
    expect(find.text(l10n.libraryYouBlack), findsOneWidget);
    expect(find.text('C60 · Ruy Lopez'), findsOneWidget);
    expect(find.text('½-½'), findsOneWidget);
    expect(find.text('2026-10-01'), findsOneWidget);
    // Game 3: stopped at 10 of 41 positions (completed_plies counts positions).
    expect(find.text(l10n.libraryAnalysisPartial(24)), findsOneWidget);
    expect(find.text(l10n.librarySourceFile), findsOneWidget);
    // Game 4: running at 20 of 41 positions.
    expect(find.text(l10n.libraryAnalysisRunning(48)), findsOneWidget);
    expect(find.text(l10n.librarySourceShare), findsOneWidget);
    expect(find.text(l10n.libraryEmptyTitle), findsNothing);
  });

  testWidgets('tapping a game opens the board for it', (tester) async {
    final env = TestEnv();
    await env.seed(white: 'Carol', black: 'Dave');
    await env.pump(tester);
    await tester.tap(find.textContaining('Carol'));
    await tester.pumpAndSettle();
    expect(find.text(l10n.boardTitleGame('Carol', 'Dave')), findsOneWidget);
  });

  testWidgets('swipe to delete, then Undo brings the game back', (tester) async {
    final env = TestEnv();
    final id = await env.seed(white: 'Carol', black: 'Dave');
    await env.pump(tester);

    await tester.drag(find.textContaining('Carol'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.textContaining('Carol'), findsNothing);
    expect(find.text(l10n.libraryGameDeleted), findsOneWidget);
    expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
    expect(await env.games.get(id), isNotNull, reason: 'not deleted for real until the undo window closes');

    await tester.tap(find.text(l10n.libraryUndo));
    await tester.pumpAndSettle();
    expect(find.textContaining('Carol'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(await env.games.get(id), isNotNull);
  });

  testWidgets('swipe to delete without Undo deletes for real (and cascades)', (tester) async {
    final env = TestEnv();
    final id = await env.seed(white: 'Carol', black: 'Dave', status: AnalysisStatus.completed, completedPlies: 40);
    final keep = await env.seed(white: 'Erin', black: 'Frank', importedAt: 5);
    await env.pump(tester);

    await tester.drag(find.textContaining('Carol'), const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(await env.games.get(id), isNull);
    expect(await env.analyses.get(id), isNull);
    expect(await env.games.get(keep), isNotNull);
    expect(find.textContaining('Erin'), findsOneWidget);
    expect(find.textContaining('Carol'), findsNothing);
  });

  testWidgets('deleting a game whose analysis is running cancels the job first', (tester) async {
    final fakes = <FakeEngineDriver>[];
    final env = TestEnv(driverFactory: () async {
      final f = FakeEngineDriver.permissive()..holdSearch = 1;
      fakes.add(f);
      return f;
    }, timeouts: const PipelineTimeouts(searchIdle: Duration(minutes: 1), stop: Duration(milliseconds: 100)));
    final id = await env.seed(white: 'Carol', black: 'Dave', plyCount: 1);
    await env.pump(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(GlyphApp)));
    final states = <AnalysisJobState>[];
    container.read(engineServiceProvider).states.listen(states.add);
    await container.read(analysisJobProvider.notifier).analyse((await env.games.get(id))!);
    for (var i = 0; i < 20 && (fakes.isEmpty || fakes.first.goCount == 0); i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(fakes.single.goCount, 1);

    await tester.drag(find.textContaining('Carol'), const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
    expect(fakes.single.sent, contains('stop'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 10)); // bestmove, then the delete
    }
    expect(await env.games.get(id), isNull);
    expect(await env.analyses.get(id), isNull);
    expect(states.whereType<AnalysisFailed>(), isEmpty);
    expect(states.last, isA<AnalysisCancelled>());
  });
}
