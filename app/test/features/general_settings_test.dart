import 'dart:io';

import 'package:chessground/chessground.dart' show ChessboardColorScheme, StaticChessboard;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/data/providers.dart';
import 'package:glyph/data/repositories.dart';
import 'package:glyph/engine/engine_providers.dart';
import 'package:glyph/features/board/board_assets.dart';
import 'package:glyph/features/board/board_preview.dart';
import 'package:glyph/features/board/board_screen.dart';
import 'package:glyph/features/library/library_controller.dart';
import 'package:glyph/features/settings/appearance_settings.dart';
import 'package:glyph/features/settings/appearance_settings_section.dart';
import 'package:glyph/features/settings/data_management.dart';
import 'package:glyph/features/settings/engine_settings.dart';
import 'package:glyph/features/settings/engine_settings_section.dart';
import 'package:glyph/features/settings/explain_settings.dart';
import 'package:glyph/features/settings/key_vault.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../support/review_fixture.dart';
import '../support/test_app.dart';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip(l10n.settingsTooltip));
  await tester.pumpAndSettle();
}

Future<void> tapTile(WidgetTester tester, String key) async {
  await tester.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).first);
  await tester.ensureVisible(find.byKey(Key(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

Future<void> choose(WidgetTester tester, String optionKey) async {
  await tester.tap(find.byKey(Key(optionKey)));
  await tester.pumpAndSettle();
}

ProviderContainer containerOf(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(GlyphApp)));

void main() {
  group('Settings > Engine (F19)', () {
    test('setThreads and setHashMb never store more than the picker offers on this device', () async {
      final repo = TestEnv().settings;
      final c = ProviderContainer(overrides: [
        settingsRepositoryProvider.overrideWithValue(repo),
        coreCountProvider.overrideWithValue(4),
        maxHashMbProvider.overrideWithValue(128),
      ]);
      addTearDown(c.dispose);
      final n = c.read(engineSettingsProvider.notifier);
      await n.setThreads(99);
      expect(await repo.get(SettingsKeys.engineThreads), '3', reason: 'cores - 1, the largest thread option');
      await n.setThreads(0);
      expect(await repo.get(SettingsKeys.engineThreads), '1');
      await n.setHashMb(4096);
      expect(await repo.get(SettingsKeys.engineHashMb), '128');
      final s = await c.read(engineSettingsProvider.future);
      expect((s.threads, s.hashMb), (1, 128));
      // Picker and clamp agree: every offered option survives a reload unchanged.
      for (final t in EngineDefaults.threadOptions(4)) {
        await n.setThreads(t);
        expect((await EngineSettings.load(repo, cores: 4, maxHashMb: 128)).threads, t);
      }
      expect(EngineDefaults.threadOptions(4).last, EngineDefaults.maxThreads(4));
    });

    test('the hash ceiling: 128 MB on a 32-bit ABI or below 3 GB of RAM (or unknown), else 256 MB', () {
      const gb = 1024 * 1024;
      expect(DeviceProfile.maxHashMb(is32Bit: false, totalMemKb: 8 * gb), 256);
      expect(DeviceProfile.maxHashMb(is32Bit: false, totalMemKb: 3 * gb), 256);
      expect(DeviceProfile.maxHashMb(is32Bit: false, totalMemKb: 3 * gb - 1), 128);
      expect(DeviceProfile.maxHashMb(is32Bit: true, totalMemKb: 8 * gb), 128);
      expect(DeviceProfile.maxHashMb(is32Bit: false, totalMemKb: null), 128);
      expect(EngineDefaults.hashOptionsFor(128), [16, 32, 64, 128]);
      expect(EngineDefaults.hashOptionsFor(256), EngineDefaults.hashOptionsMb);
      expect(DeviceProfile.parseMemTotalKb('MemTotal:        3921236 kB\nMemFree: 1 kB\n'), 3921236);
      expect(DeviceProfile.parseMemTotalKb('nothing'), isNull);
      expect(DeviceProfile.is32BitAbi('3.12.0 (stable) (Mon) on "android_arm"'), isTrue);
      expect(DeviceProfile.is32BitAbi('3.12.0 (stable) (Mon) on "android_arm64"'), isFalse);
      expect(DeviceProfile.is32BitAbi('3.12.0 (stable) (Mon) on "android_x64"'), isFalse);
    });

    testWidgets('on a device limited to 128 MB the hash picker does not offer 256 MB', (tester) async {
      final env = TestEnv(maxHashMb: 128);
      await env.pump(tester);
      await openSettings(tester);
      await tapTile(tester, 'settings-engine-hash');
      expect(find.byKey(const Key('engine-hash-128')), findsOneWidget);
      expect(find.byKey(const Key('engine-hash-256')), findsNothing);
    });

    testWidgets('shows the defaults and stores a changed preset, thread count and hash size', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      await openSettings(tester);
      expect(find.text(l10n.settingsEngine), findsOneWidget);
      expect(find.text(l10n.enginePresetNormal(16)), findsOneWidget);
      expect(find.text(l10n.settingsEngineHashDefault(64)), findsOneWidget);
      final defaultThreads = EngineDefaults.defaultThreads;
      expect(find.text(l10n.settingsEngineThreadsDefault(defaultThreads)), findsOneWidget);

      await tapTile(tester, 'settings-engine-preset');
      await choose(tester, 'engine-preset-${DepthPreset.deep}');
      expect(await env.settings.get(SettingsKeys.engineDepthPreset), 'deep');
      expect(find.text(l10n.enginePresetDeep(20)), findsOneWidget);

      await tapTile(tester, 'settings-engine-hash');
      await choose(tester, 'engine-hash-128');
      expect(await env.settings.get(SettingsKeys.engineHashMb), '128');
      expect(find.text(l10n.settingsEngineHashValue(128)), findsOneWidget);

      await tapTile(tester, 'settings-engine-threads');
      const pick = 1;
      await choose(tester, 'engine-threads-$pick');
      expect(await env.settings.get(SettingsKeys.engineThreads), '$pick');

      final settings = await containerOf(tester).read(engineSettingsProvider.future);
      expect((settings.preset, settings.hashMb, settings.threads), (DepthPreset.deep, 128, pick));
    });

    testWidgets('Reset engine settings forgets the three stored values', (tester) async {
      final env = TestEnv(settings: {
        SettingsKeys.engineDepthPreset: 'fast',
        SettingsKeys.engineThreads: '1',
        SettingsKeys.engineHashMb: '32',
      });
      await env.pump(tester);
      await openSettings(tester);
      expect(find.text(l10n.enginePresetFast(12)), findsOneWidget);
      await tapTile(tester, 'settings-engine-reset');
      expect(await env.settings.get(SettingsKeys.engineDepthPreset), isNull);
      expect(await env.settings.get(SettingsKeys.engineThreads), isNull);
      expect(await env.settings.get(SettingsKeys.engineHashMb), isNull);
      expect(find.text(l10n.enginePresetNormal(16)), findsOneWidget);
    });

    test('the thread choices are 1 to cores - 1; the hash choices are 16 to 256 MB', () {
      expect(EngineDefaults.threadOptions(8), [1, 2, 3, 4, 5, 6, 7]);
      expect(EngineDefaults.threadOptions(2), [1]);
      expect(EngineDefaults.threadOptions(1), [1]);
      expect(EngineDefaults.hashOptionsMb, [16, 32, 64, 128, 256]);
    });

    test('a stored thread count or hash size from a bigger device is clamped on this one', () async {
      final repo = TestEnv(settings: {SettingsKeys.engineThreads: '32', SettingsKeys.engineHashMb: '4096'}).settings;
      final s = await EngineSettings.load(repo, cores: 4);
      expect((s.threads, s.hashMb), (3, 256), reason: 'the picker offers 1 to cores - 1, and the stored value is clamped to the same');
      final small = await EngineSettings.load(repo, cores: 4, maxHashMb: 128);
      expect(small.hashMb, 128);
    });

    testWidgets('a new analysis uses the chosen depth, threads and hash', (tester) async {
      final env = TestEnv(settings: {
        SettingsKeys.engineDepthPreset: 'fast',
        SettingsKeys.engineThreads: '1',
        SettingsKeys.engineHashMb: '32',
      });
      final id = await env.seed(plyCount: 2, importedAt: 1);
      final record = (await env.games.get(id))!;
      await env.pump(tester);
      final container = containerOf(tester);
      await container.read(analysisJobProvider.notifier).analyse(record);
      await tester.pumpAndSettle();
      final analysis = await env.analyses.get(id);
      expect(analysis?.depth, 12);
    });
  });

  group('Settings > Appearance (F19)', () {
    testWidgets('the theme mode is stored and applied; dynamic colour off is stored', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      await openSettings(tester);
      await tapTile(tester, 'settings-theme');
      await tester.tap(find.text(l10n.settingsThemeDark));
      await tester.pumpAndSettle();
      expect(await env.settings.get(SettingsKeys.themeMode), 'dark');
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);

      await tapTile(tester, 'settings-dynamic-color');
      expect(await env.settings.get(SettingsKeys.dynamicColor), '0');
      await tapTile(tester, 'settings-dynamic-color');
      expect(await env.settings.get(SettingsKeys.dynamicColor), '1');
    });

    testWidgets('the stored theme is read when the app starts', (tester) async {
      final env = TestEnv(settings: {
        SettingsKeys.themeMode: 'light',
        SettingsKeys.dynamicColor: '0',
        SettingsKeys.boardScheme: 'wood',
        SettingsKeys.pieceSet: 'merida',
        SettingsKeys.moveSounds: '1',
      });
      await env.pump(tester);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.light);
      expect(containerOf(tester).read(appearanceProvider), const AppearanceSettings(
        themeMode: ThemeMode.light,
        dynamicColor: false,
        boardScheme: 'wood',
        pieceSet: 'merida',
        moveSounds: true,
      ));
    });

    testWidgets('a stored board or piece choice that is not on the allow-list falls back to the default', (tester) async {
      final env = TestEnv(settings: {
        SettingsKeys.boardScheme: 'horsey',
        SettingsKeys.pieceSet: 'alpha',
        SettingsKeys.themeMode: 'sepia',
      });
      await env.pump(tester);
      final a = containerOf(tester).read(appearanceProvider);
      expect((a.boardScheme, a.pieceSet, a.themeMode), (defaultBoardSchemeKey, defaultPieceSetKey, ThemeMode.system));
      // And a choice that is not on the list is refused, never applied.
      containerOf(tester).read(appearanceProvider.notifier)
        ..setBoardScheme('horsey')
        ..setPieceSet('alpha');
      await tester.pumpAndSettle();
      expect(containerOf(tester).read(appearanceProvider).boardScheme, defaultBoardSchemeKey);
      expect(containerOf(tester).read(appearanceProvider).pieceSet, defaultPieceSetKey);
    });

    testWidgets('the board colour and piece set pickers list exactly the allow-lists, store the choice and update the preview', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      await openSettings(tester);

      await tapTile(tester, 'settings-board-theme');
      for (final key in selectableBoardSchemes.keys) {
        await tester.scrollUntilVisible(find.byKey(Key('board-scheme-$key')), 100, scrollable: find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first);
        expect(find.byKey(Key('board-scheme-$key')), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('board-scheme-horsey')), findsNothing);
      await tester.scrollUntilVisible(find.byKey(const Key('board-scheme-wood')), 100, scrollable: find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable)).first);
      await choose(tester, 'board-scheme-wood');
      expect(await env.settings.get(SettingsKeys.boardScheme), 'wood');
      expect(find.text(l10n.boardScheme_wood), findsOneWidget);

      await tapTile(tester, 'settings-piece-set');
      for (final key in selectablePieceSets.keys) {
        expect(find.byKey(Key('piece-set-$key')), findsOneWidget, reason: key);
      }
      expect(find.byKey(const Key('piece-set-alpha')), findsNothing);
      await choose(tester, 'piece-set-merida');
      expect(await env.settings.get(SettingsKeys.pieceSet), 'merida');
      expect(find.text(l10n.pieceSet_merida), findsOneWidget);

      await tester.scrollUntilVisible(find.byKey(const Key('settings-board-preview')), 100, scrollable: find.byType(Scrollable).first);
      final preview = tester.widget<BoardPreview>(find.byKey(const Key('settings-board-preview')));
      expect((preview.schemeKey, preview.pieceSetKey), ('wood', 'merida'));
      final board = tester.widget<StaticChessboard>(find.descendant(of: find.byType(BoardPreview), matching: find.byType(StaticChessboard)));
      expect(board.settings.colorScheme, ChessboardColorScheme.wood);
      expect(board.settings.pieceAssets, pieceAssetsFor('merida'));
    });

    testWidgets('the board screen draws with the chosen colours and pieces', (tester) async {
      final env = TestEnv(settings: {SettingsKeys.boardScheme: 'marble', SettingsKeys.pieceSet: 'mpchess'});
      final id = await seedReview(env);
      await pumpReview(tester, env, id, initialPly: 2);
      final board = tester.widget<StaticChessboard>(find.byType(StaticChessboard));
      expect(board.settings.colorScheme, ChessboardColorScheme.marble);
      expect(board.settings.pieceAssets, pieceAssetsFor('mpchess'));
    });

    testWidgets('move sounds: off by default; on, a single step clicks once, a jump does not', (tester) async {
      final clicks = <int>[];
      final env = TestEnv();
      final id = await seedReview(env);
      final container = ProviderContainer(overrides: [...env.overrides, moveSoundProvider.overrideWithValue(() => clicks.add(1))]);
      addTearDown(container.dispose);
      await pumpReview(tester, env, id, container: container);
      await tester.tap(find.byKey(const Key('nav-next')));
      await settleBoard(tester);
      expect(clicks, isEmpty, reason: 'off by default');

      container.read(appearanceProvider.notifier).setMoveSounds(true);
      await tester.pump();
      await tester.tap(find.byKey(const Key('nav-next')));
      await settleBoard(tester);
      expect(clicks, hasLength(1));
      await tester.tap(find.byKey(const Key('nav-back')));
      await settleBoard(tester);
      expect(clicks, hasLength(2));
      await tester.tap(find.byKey(const Key('nav-last')));
      await settleBoard(tester);
      expect(clicks, hasLength(2), reason: 'a jump of several moves is silent');
      expect(await env.settings.get(SettingsKeys.moveSounds), '1');
    });

    testWidgets('names exist for every board colour and piece set', (tester) async {
      for (final key in selectableBoardSchemes.keys) {
        expect(boardSchemeName(l10n, key), isNot(key), reason: 'no display name for $key');
      }
      for (final key in selectablePieceSets.keys) {
        expect(pieceSetName(l10n, key), isNot(key), reason: 'no display name for $key');
      }
    });
  });

  group('Settings > Data (F19)', () {
    Future<TestEnv> seeded(WidgetTester tester) async {
      final env = TestEnv(settings: {
        SettingsKeys.lichessUsername: 'alice',
        SettingsKeys.llmModel: 'gpt',
        SettingsKeys.themeMode: 'dark',
        SettingsKeys.engineThreads: '2',
      }, secrets: {
        'openai': 'sk-secret-1234',
        'ollama': 'other-key',
      });
      final a = await env.seed(white: 'A', black: 'B', status: AnalysisStatus.completed, completedPlies: 3);
      await env.seed(white: 'C', black: 'D', importedAt: 2);
      await env.analyses.putPositionLines(a, 0, [PositionLineRecord(gameId: a, ply: 0, rank: 1, scoreCp: 12, depth: 12, pvUci: 'e2e4')]);
      await env.cache.put(CachedLlmText(key: 'k1', kind: PromptKind.move, content: 'x', model: 'm', createdAt: 1, gameId: a));
      await env.cache.put(CachedLlmText(key: 'k2', kind: PromptKind.summary, content: 'y', model: 'm', createdAt: 2, gameId: a));
      await env.onlineCache.put('https://api.chess.com/x', const CachedResponse('W/"1"', '{}'));
      return env;
    }

    testWidgets('Clear saved explanations asks first; Cancel keeps them, Clear empties the cache only and says how many went', (tester) async {
      final env = await seeded(tester);
      await env.pump(tester);
      await openSettings(tester);
      await tapTile(tester, 'settings-clear-explanations');
      expect(find.text(l10n.settingsClearExplanationsTitle), findsOneWidget);
      expect(find.text(l10n.settingsClearExplanationsBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('clear-explanations-cancel')));
      await tester.pumpAndSettle();
      expect(await env.cache.count(), 2, reason: 'Cancel changes nothing');
      expect(find.text(l10n.settingsClearExplanationsDone(2)), findsNothing);

      await tapTile(tester, 'settings-clear-explanations');
      await tester.tap(find.byKey(const Key('clear-explanations-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsClearExplanationsDone(2)), findsOneWidget);
      expect(await env.cache.count(), 0);
      expect((await env.games.list()), hasLength(2));
      expect(await env.onlineCache.get('https://api.chess.com/x'), isNotNull);
      // Nothing left: the message says so.
      await tapTile(tester, 'settings-clear-explanations');
      await tester.tap(find.byKey(const Key('clear-explanations-confirm')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text(l10n.settingsClearExplanationsDone(0)), findsOneWidget);
    });

    testWidgets('Clear online cache empties the ETag cache only', (tester) async {
      final env = await seeded(tester);
      await env.pump(tester);
      await openSettings(tester);
      await tapTile(tester, 'settings-clear-online');
      expect(find.text(l10n.settingsClearOnlineDone), findsOneWidget);
      expect(await env.onlineCache.get('https://api.chess.com/x'), isNull);
      expect(await env.cache.count(), 2);
      expect(await env.games.list(), hasLength(2));
    });

    testWidgets('Delete all data asks first; Cancel keeps everything', (tester) async {
      final env = await seeded(tester);
      await env.pump(tester);
      await openSettings(tester);
      await tapTile(tester, 'settings-delete-all');
      expect(find.text(l10n.settingsDeleteAllTitle), findsOneWidget);
      expect(find.text(l10n.settingsDeleteAllBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('delete-all-cancel')));
      await tester.pumpAndSettle();
      expect(await env.games.list(), hasLength(2));
      expect(await env.secrets.read('openai'), 'sk-secret-1234');
    });

    testWidgets('Delete all data removes games, analysis, explanations, caches, settings and every API key, and resets the appearance', (tester) async {
      final env = await seeded(tester);
      await env.pump(tester);
      await openSettings(tester);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
      await tapTile(tester, 'settings-delete-all');
      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsDeleteAllDone), findsOneWidget);
      expect(env.exports.clears, 1, reason: 'the exported PGN in the cache goes too');
      expect(await env.games.list(), isEmpty);
      expect(env.store.analyses, isEmpty);
      expect(env.store.lines, isEmpty);
      expect(await env.cache.count(), 0);
      expect(await env.onlineCache.get('https://api.chess.com/x'), isNull);
      expect(await env.settings.get(SettingsKeys.lichessUsername), isNull);
      expect(await env.settings.get(SettingsKeys.llmModel), isNull);
      expect(await env.secrets.read('openai'), isNull);
      expect(await env.secrets.read('ollama'), isNull);
      expect(env.secrets.slots, isEmpty);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.system);
      expect(containerOf(tester).read(appearanceProvider), const AppearanceSettings());
      final engine = await containerOf(tester).read(engineSettingsProvider.future);
      expect(engine.threads, EngineDefaults.defaultThreads);
      // The library is empty and shows the empty state.
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
    });

    testWidgets('Delete all data stops a running analysis first', (tester) async {
      final env = await seeded(tester);
      await env.pump(tester);
      final container = containerOf(tester);
      final record = (await env.games.list()).first;
      await container.read(analysisJobProvider.notifier).analyse(record);
      await tester.pump(const Duration(milliseconds: 50));
      await container.read(dataManagementProvider).deleteAll();
      await tester.pumpAndSettle();
      expect(await env.games.list(), isEmpty);
      expect(container.read(engineServiceProvider).queuedGameIds, isEmpty);
    });

    testWidgets('a failure says so, offers Try again, and the second try finishes the job', (tester) async {
      final env = await seeded(tester);
      env.secrets.failDeletes = true;
      await env.pump(tester);
      await openSettings(tester);
      await tapTile(tester, 'settings-delete-all');
      await tester.tap(find.byKey(const Key('delete-all-confirm')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsDataFailed), findsOneWidget);
      expect(find.text(l10n.commonRetry), findsOneWidget);
      expect(await env.games.list(), isEmpty, reason: 'every step that could run ran');
      expect(await env.secrets.read('openai'), 'sk-secret-1234', reason: 'the keys could not be removed');
      env.secrets.failDeletes = false;
      await tester.tap(find.text(l10n.commonRetry));
      await tester.pumpAndSettle();
      expect(find.text(l10n.settingsDeleteAllDone), findsOneWidget);
      expect(await env.secrets.read('openai'), isNull);
    });

    testWidgets('a key the keystore refuses to delete keeps its binding: it is never sendable to a new address (M8 review)', (tester) async {
      const bound = 'https://mine.example:443';
      final env = TestEnv(
        settings: {
          SettingsKeys.llmProvider: 'custom',
          SettingsKeys.llmBaseUrl: 'https://mine.example/v1',
          '${SettingsKeys.llmKeyOriginPrefix}custom': bound,
        },
        secrets: {'custom': 'sk-secret-1234'},
      );
      env.secrets.failDeletes = true;
      await env.pump(tester);
      final container = containerOf(tester);
      await expectLater(container.read(dataManagementProvider).deleteAll(), throwsA(isA<DataManagementException>()));
      expect(await env.settings.get(SettingsKeys.llmBaseUrl), isNull, reason: 'the rest of the settings are cleared');
      expect(await env.settings.get('${SettingsKeys.llmKeyOriginPrefix}custom'), bound, reason: 'the surviving key stays bound to where it was saved');
      final vault = KeyVault(env.secrets, env.settings);
      expect(await vault.keyFor(LlmProvider.custom, 'https://elsewhere.example/v1'), isNull);
      expect(await vault.keyFor(LlmProvider.custom, 'https://mine.example/v1'), 'sk-secret-1234', reason: 'unchanged from before the failed action');
      // The retry deletes the key and the binding.
      env.secrets.failDeletes = false;
      await container.read(dataManagementProvider).deleteAll();
      expect(env.secrets.slots, isEmpty);
      expect(await env.settings.get('${SettingsKeys.llmKeyOriginPrefix}custom'), isNull);
    });

    testWidgets('a failure to empty the export folder is reported, and the other steps still ran', (tester) async {
      final env = await seeded(tester);
      env.exports.error = const FileSystemException('denied');
      await env.pump(tester);
      final container = containerOf(tester);
      await expectLater(container.read(dataManagementProvider).deleteAll(), throwsA(isA<DataManagementException>().having((e) => e.failedSteps, 'steps', ['exported files'])));
      expect(await env.games.list(), isEmpty);
      expect(env.secrets.slots, isEmpty);
    });

    testWidgets('deleting one game empties the export folder too', (tester) async {
      final env = await seeded(tester);
      await env.pump(tester);
      final container = containerOf(tester);
      final id = (await env.games.list()).first.id;
      await container.read(libraryProvider.notifier).deleteNow(id);
      expect(env.exports.clears, 1);
      expect(await env.games.list(), hasLength(1));
    });
  });

  testWidgets('the settings sections come in the SPEC order: Engine, Explanations, Accounts, Appearance, Data, About', (tester) async {
    await TestEnv().pump(tester);
    tester.view.physicalSize = const Size(800, 4000);
    await openSettings(tester);
    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    final order = [l10n.settingsEngine, l10n.settingsExplanations, l10n.settingsAccounts, l10n.settingsAppearance, l10n.settingsData, l10n.settingsAbout];
    for (var i = 1; i < order.length; i++) {
      expect(y(order[i]), greaterThan(y(order[i - 1])), reason: order[i]);
    }
    expect(presetLabel(l10n, DepthPreset.fast), l10n.enginePresetFast(12));
  });
}
