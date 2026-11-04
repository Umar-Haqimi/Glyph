import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/engine/engine_providers.dart';
import 'package:glyph/features/board/board_screen.dart';
import 'package:glyph/l10n/app_localizations.dart';
import 'package:glyph_core/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

const _pgn = '[White "Alice"]\n[Black "Bob"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bc4 Bc5 4. c3 Nf6 *'; // 8 plies, 9 positions

Future<void> settle(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 10));
  }
}

Future<int> save(TestEnv env, {AnalysisStatus? status, int completed = 0, String pgn = _pgn}) async {
  final saved = await env.games.save(NewGame(
    source: GameSource.paste,
    pgn: pgn,
    white: 'Alice',
    black: 'Bob',
    plyCount: 8,
    importedAt: 1,
  ));
  if (status != null) {
    await env.analyses.upsert(AnalysisRecord(
      gameId: saved.id,
      engine: 'Stockfish 19 light',
      depth: 16,
      multipv: 2,
      status: status,
      completedPlies: completed,
      updatedAt: 1,
    ));
  }
  return saved.id;
}

Future<void> pumpBoard(WidgetTester tester, TestEnv env, int id, {ProviderContainer? container}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (container == null) {
    container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);
  }
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: BoardScreen(gameId: id),
    ),
  ));
  await tester.pump();
}

String status(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('analysis-status'))).data!;

void main() {
  testWidgets('a new game starts analysing by itself and reaches "Analysis complete"', (tester) async {
    final env = TestEnv();
    final id = await save(env);
    await pumpBoard(tester, env, id);
    await settle(tester);
    expect(status(tester), l10n.analysisCompleted);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    final stored = (await env.analyses.get(id))!;
    expect((stored.status, stored.completedPlies, stored.depth, stored.multipv), (AnalysisStatus.completed, 9, 16, 2));
    expect(await env.analyses.positionLines(id), hasLength(9)); // permissive fake: one line per position
  });

  testWidgets('shows "Analysing… k/N" with Cancel; Cancel then Resume finishes', (tester) async {
    final fakes = <FakeEngineDriver>[];
    final env = TestEnv(driverFactory: () async {
      final f = FakeEngineDriver.permissive();
      if (fakes.isEmpty) f.holdSearch = 3;
      fakes.add(f);
      return f;
    });
    final id = await save(env);
    await pumpBoard(tester, env, id);
    await settle(tester);

    expect(status(tester), l10n.analysisRunning(2, 9));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(l10n.analysisCancel), findsOneWidget);

    await tester.tap(find.text(l10n.analysisCancel));
    await settle(tester);
    expect(status(tester), l10n.analysisCancelled(2, 9));
    expect(find.text(l10n.analysisResume), findsOneWidget);
    expect((await env.analyses.get(id))!.status, AnalysisStatus.cancelled);

    await tester.tap(find.text(l10n.analysisResume));
    await settle(tester);
    expect(status(tester), l10n.analysisCompleted);
    expect((await env.analyses.get(id))!.completedPlies, 9);
    expect(fakes, hasLength(1));
  });

  testWidgets('engine that cannot start: failure copy and Retry', (tester) async {
    var attempts = 0;
    final env = TestEnv(driverFactory: () async {
      if (attempts++ == 0) throw StateError('A light engine is already live.');
      return FakeEngineDriver.permissive();
    });
    final id = await save(env);
    await pumpBoard(tester, env, id);
    await settle(tester);
    expect(status(tester), l10n.analysisFailedUnavailable);

    await tester.tap(find.text(l10n.analysisRetry));
    await settle(tester);
    expect(status(tester), l10n.analysisCompleted);
  });

  testWidgets('engine crash mid-game: crash copy, Retry resumes', (tester) async {
    var n = 0;
    final env = TestEnv(driverFactory: () async {
      final f = FakeEngineDriver.permissive();
      if (n++ == 0) f.crashOnGo = 4;
      return f;
    });
    final id = await save(env);
    await pumpBoard(tester, env, id);
    await settle(tester);
    expect(status(tester), l10n.analysisFailedCrashed);
    expect((await env.analyses.get(id))!.completedPlies, 3);

    await tester.tap(find.text(l10n.analysisRetry));
    await settle(tester);
    expect(status(tester), l10n.analysisCompleted);
    expect(n, 2);
  });

  testWidgets('a stored unfinished analysis is not restarted by itself; Resume continues it', (tester) async {
    final env = TestEnv();
    final id = await save(env, status: AnalysisStatus.running, completed: 3);
    await pumpBoard(tester, env, id);
    await settle(tester);
    expect(status(tester), l10n.analysisIncomplete(3, 9));
    expect(find.text(l10n.analysisResume), findsOneWidget);

    await tester.tap(find.text(l10n.analysisResume));
    await settle(tester);
    expect(status(tester), l10n.analysisCompleted);
  });

  testWidgets('app lifecycle: paused -> "paused", resumed -> continues', (tester) async {
    final fakes = <FakeEngineDriver>[];
    final env = TestEnv(driverFactory: () async {
      final f = FakeEngineDriver.permissive();
      if (fakes.isEmpty) f.holdSearch = 3;
      fakes.add(f);
      return f;
    });
    final id = await save(env);
    await pumpBoard(tester, env, id);
    await settle(tester);
    expect(status(tester), l10n.analysisRunning(2, 9));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await settle(tester);
    // (Frames are disabled while the app is in the background, so the text
    // cannot update here; the stored state shows what happened.)
    expect(fakes.first.disposed, isTrue);
    expect((await env.analyses.get(id))!.status, AnalysisStatus.paused);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await settle(tester);
    expect(status(tester), l10n.analysisCompleted);
    expect(fakes, hasLength(2));
  });

  testWidgets('a queued job has Cancel; cancelling it shows "cancelled" with Resume', (tester) async {
    final fakes = <FakeEngineDriver>[];
    final env = TestEnv(driverFactory: () async {
      final f = FakeEngineDriver.permissive();
      if (fakes.isEmpty) f.holdSearch = 2;
      fakes.add(f);
      return f;
    });
    final running = await save(env);
    final queued = await save(env);
    final container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);
    await container.read(analysisJobProvider.notifier).analyse((await env.games.get(running))!);
    await pumpBoard(tester, env, queued, container: container);
    await settle(tester);

    expect(status(tester), l10n.analysisQueued);
    expect(find.text(l10n.analysisCancel), findsOneWidget);
    await tester.tap(find.text(l10n.analysisCancel));
    await settle(tester);
    expect(status(tester), l10n.analysisCancelled(0, 9));
    expect(find.text(l10n.analysisResume), findsOneWidget);
    expect(await env.analyses.get(queued), isNull, reason: 'never started');

    // Not awaited: the stop needs the (fake) clock to advance.
    unawaited(container.read(analysisJobProvider.notifier).cancel(running));
    await settle(tester);
  });

  testWidgets('a game whose PGN does not parse fails at once (no endless "Starting…", no Retry)', (tester) async {
    final env = TestEnv();
    final id = await save(env, pgn: 'this is not a game');
    await pumpBoard(tester, env, id);
    await settle(tester);
    expect(status(tester), l10n.analysisFailedInvalid);
    expect(find.text(l10n.analysisRetry), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
  });
}
