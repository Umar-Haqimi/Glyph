import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/bootstrap.dart';
import 'package:glyph/data/db.dart';
import 'package:glyph/data/in_memory.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/features/errors/failure_text.dart';
import 'package:glyph/features/errors/recovery.dart';
import 'package:glyph/features/explain/error_text.dart';
import 'package:glyph/features/import/online_text.dart';
import 'package:glyph/features/import/pgn_issue_text.dart';
import 'package:glyph/features/import/share_intake.dart';
import 'package:glyph/features/library/library_screen.dart';
import 'package:glyph/features/settings/explain_settings.dart';
import 'package:glyph/platform/app_log.dart';
import 'package:glyph/platform/secret_store.dart';
import 'package:glyph/routes.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:sqlite3/sqlite3.dart';

import '../support/fake_online.dart';
import '../support/review_fixture.dart';
import '../support/test_app.dart';

/// M8 "all error copy wired": every value of every error / failure enum has its
/// own user-facing copy (in `app_en.arb`, through gen-l10n) and a recovery
/// action. The `switch`es behind the helpers are exhaustive, so adding an enum
/// value without copy or recovery does not compile; these tests check what the
/// compiler cannot: the copy is real text, finished (no stray placeholders),
/// different for different kinds, and the recovery the table promises is in
/// the screen that shows the error.
void _isCopy(String text, String what) {
  expect(text.trim(), isNotEmpty, reason: what);
  expect(text, isNot(matches(RegExp(r'[{}]'))), reason: '$what: unresolved placeholder in "$text"');
  expect(text, isNot(contains('null')), reason: what);
  expect(text, isNot(contains('Instance of')), reason: what);
  expect(text, isNot(contains('Exception')), reason: what);
  expect(text.length, greaterThan(8), reason: what);
}

void main() {
  group('copy exists for every error kind', () {
    test('LlmErrorKind: all kinds, each with its own sentence (SPEC 4 names and fills the model, parameter and status)', () {
      final texts = <LlmErrorKind, String>{};
      for (final kind in LlmErrorKind.values) {
        final error = LlmError(kind, status: 503, param: 'max_tokens');
        final text = llmErrorText(l10n, error, model: 'gpt-x');
        _isCopy(text, 'LlmErrorKind.${kind.name}');
        texts[kind] = text;
      }
      expect(texts.values.toSet(), hasLength(LlmErrorKind.values.length), reason: 'two kinds share one sentence');
      expect(texts[LlmErrorKind.modelNotFound], contains('gpt-x'));
      expect(texts[LlmErrorKind.unsupportedParam], contains('max_tokens'));
      expect(texts[LlmErrorKind.unsupportedParam], contains('Token limit parameter'), reason: 'SPEC 4: tells which setting to change');
      expect(texts[LlmErrorKind.server], contains('503'));
      expect(texts[LlmErrorKind.badRequest], contains('503'));
      // Variants without a status or parameter still read well.
      _isCopy(llmErrorText(l10n, const LlmError(LlmErrorKind.server)), 'server without status');
      _isCopy(llmErrorText(l10n, const LlmError(LlmErrorKind.badRequest)), 'badRequest without status');
      _isCopy(llmErrorText(l10n, const LlmError(LlmErrorKind.unsupportedParam)), 'unsupportedParam without parameter');
      expect(llmErrorText(l10n, const LlmError(LlmErrorKind.noKey)), 'Add an API key in Settings → Explanations.');
      expect(llmErrorText(l10n, const LlmError(LlmErrorKind.offline)), 'No connection.');
    });

    test('OnlineErrorKind: all kinds, for both sites, naming the site', () {
      for (final source in OnlineSource.values) {
        final texts = <String>{};
        for (final kind in OnlineErrorKind.values) {
          final text = onlineErrorText(l10n, source, OnlineFetchError(kind, status: 502));
          _isCopy(text, '${source.name} ${kind.name}');
          texts.add(text);
        }
        expect(texts, hasLength(OnlineErrorKind.values.length), reason: '${source.name}: shared sentence');
      }
      final lichess = onlineErrorText(l10n, OnlineSource.lichess, const OnlineFetchError(OnlineErrorKind.userNotFound));
      expect(lichess.toLowerCase(), contains('lichess'));
      expect(onlineErrorText(l10n, OnlineSource.chesscom, const OnlineFetchError(OnlineErrorKind.rateLimited)).toLowerCase(), contains('chess.com'));
    });

    test('PgnIssueKind: all kinds', () {
      final texts = <String>{};
      for (final kind in PgnIssueKind.values) {
        final issue = PgnIssue(kind, gameIndex: 2, ply: 27, san: 'Nxe5', moveNumber: 14, isBlackMove: true, variant: 'Crazyhouse');
        final text = pgnIssueText(l10n, issue);
        _isCopy(text, 'PgnIssueKind.${kind.name}');
        texts.add(text);
        _isCopy(pgnIssueText(l10n, issue, withGame: true), 'PgnIssueKind.${kind.name} with the game');
      }
      expect(texts, hasLength(PgnIssueKind.values.length));
      // SPEC 4 examples.
      expect(pgnIssueText(l10n, const PgnIssue(PgnIssueKind.illegalMove, gameIndex: 2, san: 'Nxe5', moveNumber: 14)), 'Game 2, move 14 (Nxe5): illegal move.');
      expect(pgnIssueText(l10n, const PgnIssue(PgnIssueKind.unsupportedVariant, variant: 'Crazyhouse')), "Crazyhouse games aren't supported.");
      expect(pgnIssueText(l10n, const PgnIssue(PgnIssueKind.tooLarge)), 'This file is larger than 2 MB.');
    });

    test('AnalysisFailureKind, ShareProblem, BaseUrlProblem, ApiKeyProblem, AppFailure: all values', () {
      for (final kind in AnalysisFailureKind.values) {
        _isCopy(analysisFailureText(l10n, kind), 'AnalysisFailureKind.${kind.name}');
      }
      for (final problem in ShareProblem.values) {
        _isCopy(shareProblemText(l10n, problem), 'ShareProblem.${problem.name}');
      }
      for (final problem in BaseUrlProblem.values) {
        _isCopy(baseUrlProblemText(l10n, problem) ?? '', 'BaseUrlProblem.${problem.name}');
      }
      for (final problem in ApiKeyProblem.values) {
        _isCopy(apiKeyProblemText(l10n, problem), 'ApiKeyProblem.${problem.name}');
      }
      final app = <String>{};
      for (final failure in AppFailure.values) {
        final text = appFailureText(l10n, failure);
        _isCopy(text, 'AppFailure.${failure.name}');
        app.add(text);
      }
      expect(app, hasLength(AppFailure.values.length));
      expect(AnalysisFailureKind.values.map((k) => analysisFailureText(l10n, k)).toSet(), hasLength(AnalysisFailureKind.values.length));
      expect(ShareProblem.values.map((p) => shareProblemText(l10n, p)).toSet(), hasLength(ShareProblem.values.length));
    });

    test('the other failure surfaces have copy: export, share intake, key, settings, startup', () {
      for (final text in [
        l10n.exportFailed,
        l10n.shareReadFailed,
        l10n.shareReadTimeout,
        l10n.onlineImportFailed,
        l10n.settingsSaveFailed,
        l10n.settingsDataFailed,
        l10n.startupDbTitle,
        l10n.startupDbBody,
        l10n.startupDbNewerBody,
        l10n.startupDbFullBody,
        l10n.startupDbResetFailed,
        l10n.importFileOpenFailed,
        l10n.libraryLoadFailed,
        l10n.boardLoadFailed,
        l10n.boardUnavailable,
      ]) {
        _isCopy(text, text);
      }
    });
  });

  group('every error kind has a recovery', () {
    test('LlmErrorKind: Settings can fix the configuration kinds (the sheet shows Open settings), the rest are retried', () {
      for (final kind in LlmErrorKind.values) {
        final recovery = llmRecovery(kind);
        expect(const [Recovery.openSettings, Recovery.retry], contains(recovery), reason: kind.name);
        expect(llmErrorFixableInSettings(kind), recovery == Recovery.openSettings, reason: kind.name);
      }
      // SPEC 4: the unsupported parameter copy sends the user to Settings.
      expect(llmRecovery(LlmErrorKind.unsupportedParam), Recovery.openSettings);
      expect(llmRecovery(LlmErrorKind.cleartextBlocked), Recovery.openSettings);
      expect(llmRecovery(LlmErrorKind.rateLimited), Recovery.retry);
      expect(llmRecovery(LlmErrorKind.offline), Recovery.retry);
    });

    test('online, PGN, analysis, share, URL and key problems have a recovery', () {
      for (final k in OnlineErrorKind.values) {
        expect(onlineRecovery(k), isA<Recovery>(), reason: k.name);
      }
      for (final k in PgnIssueKind.values) {
        expect(pgnRecovery(k), Recovery.fixInput, reason: k.name);
      }
      for (final k in AnalysisFailureKind.values) {
        expect(analysisRecovery(k), isA<Recovery>(), reason: k.name);
      }
      for (final k in ShareProblem.values) {
        expect(shareRecovery(k), isA<Recovery>(), reason: k.name);
      }
      for (final k in BaseUrlProblem.values) {
        expect(baseUrlRecovery(k), Recovery.fixInput, reason: k.name);
      }
      for (final k in ApiKeyProblem.values) {
        expect(apiKeyRecovery(k), Recovery.fixInput, reason: k.name);
      }
      for (final k in AppFailure.values) {
        expect(appFailureRecovery(k), isA<Recovery>(), reason: k.name);
      }
    });
  });

  group('the recovery action is in the screen', () {
    testWidgets('analysis failure: Retry for an engine failure, none (and a way out in the text) for an unreadable game', (tester) async {
      for (final kind in AnalysisFailureKind.values) {
        final env = TestEnv(driverFactory: () async => throw StateError('no engine'));
        final id = await seedReview(env, status: AnalysisStatus.paused, positions: 3, labels: false);
        await pumpReview(tester, env, id, initialPly: 0);
        // Retry is offered exactly when the table says so (the engine factory above fails: engineUnavailable).
        if (kind == AnalysisFailureKind.engineUnavailable) {
          await tester.tap(find.text(l10n.analysisResume));
          await settleBoard(tester, rounds: 40);
          expect(find.text(l10n.analysisFailedUnavailable), findsOneWidget);
          expect(find.text(l10n.analysisRetry), findsOneWidget);
          expect(analysisRecovery(kind), Recovery.retry);
        } else {
          expect(analysisRecovery(kind) == Recovery.retry, kind == AnalysisFailureKind.engineCrashed);
        }
        await tester.pumpWidget(const SizedBox());
      }
      expect(analysisFailureText(l10n, AnalysisFailureKind.invalidGame), contains('Delete it'), reason: 'the copy says what to do');
    });

    testWidgets('library load failure: message and Try again, which reloads', (tester) async {
      var fail = true;
      final env = TestEnv(gamesBuilder: (store) => _FlakyGames(store, () => fail));
      await env.pump(tester);
      expect(find.text(l10n.libraryLoadFailed), findsOneWidget);
      expect(find.byKey(const Key('library-retry')), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const Key('library-retry')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.libraryLoadFailed), findsNothing);
      expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
      expect(find.byType(LibraryScreen), findsOneWidget);
    });

    testWidgets('board: a game that cannot be read offers Try again; a missing game offers a way back', (tester) async {
      var fail = false;
      final env = TestEnv(gamesBuilder: (store) => _FlakyGames(store, () => false)..readFails = () => fail);
      final id = await seedReview(env);
      await env.pump(tester);
      tester.view.physicalSize = const Size(800, 2400);
      fail = true;
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(Routes.board, arguments: id);
      await tester.pumpAndSettle();
      expect(find.text(l10n.boardLoadFailed), findsOneWidget);
      expect(find.byKey(const Key('board-retry')), findsOneWidget);
      fail = false;
      await tester.tap(find.byKey(const Key('board-retry')));
      await settleBoard(tester);
      expect(find.text(l10n.boardLoadFailed), findsNothing);
      expect(find.byKey(const Key('nav-next')), findsOneWidget);

      // A game that no longer exists: a way back, not a dead end.
      tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(Routes.board, arguments: 999);
      await tester.pumpAndSettle();
      expect(find.text(l10n.boardUnavailable), findsOneWidget);
      await tester.tap(find.byKey(const Key('board-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nav-next')), findsOneWidget, reason: 'back on the first board');
    });

    testWidgets('saving an imported game that fails says so and Try again saves it', (tester) async {
      final env = TestEnv(gamesBuilder: (store) => _FlakyGames(store, () => false));
      final games = env.games as _FlakyGames;
      await env.pump(tester);
      await tester.tap(find.text(l10n.libraryImportFab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.importPastePgn));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('pgnField')), vectorPgn('lichess_app_share.pgn'));
      await tester.pumpAndSettle();
      games.failSave = true;
      await tester.tap(find.byKey(const Key('importSave')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.importSaveFailed), findsOneWidget);
      expect(find.byKey(const Key('importSave')), findsOneWidget, reason: 'still on the paste screen, text kept');
      expect(tester.widget<FilledButton>(find.byKey(const Key('importSave'))).onPressed, isNotNull);
      games.failSave = false;
      await tester.tap(find.text(l10n.commonRetry));
      await tester.pumpAndSettle();
      expect(await games.list(), hasLength(1));
      expect(find.byKey(const Key('importSave')), findsNothing, reason: 'moved on to the board');
    });

    testWidgets('export failure: message and Try again which exports again', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      env.pgnShare.error = const FormatException('no share sheet');
      await pumpReview(tester, env, id, initialPly: 2);
      await tester.tap(find.byKey(const Key('board-menu')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.exportPgn));
      await settleBoard(tester, rounds: 20);
      expect(find.text(l10n.exportFailed), findsOneWidget);
      env.pgnShare.error = null;
      await tester.tap(find.text(l10n.exportRetry));
      await settleBoard(tester, rounds: 20);
      expect(env.pgnShare.shared, hasLength(1));
    });

    testWidgets('online import: every failure kind shows its copy, and Fetch stays available to try again', (tester) async {
      for (final kind in OnlineErrorKind.values.where((k) => k != OnlineErrorKind.invalidUsername)) {
        final env = TestEnv(lichess: FakeOnlineClient.failing(OnlineFetchError(kind, status: 500)));
        await env.pump(tester);
        await tester.tap(find.text(l10n.libraryImportFab));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.importFromLichess));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('onlineUsername')), 'someone');
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('onlineFetch')));
        await tester.pumpAndSettle();
        expect(tester.widget<Text>(find.byKey(const Key('onlineStatus'))).data, onlineErrorText(l10n, OnlineSource.lichess, OnlineFetchError(kind, status: 500)), reason: kind.name);
        expect(find.byKey(const Key('onlineFetch')), findsOneWidget, reason: kind.name);
        expect(tester.widget<FilledButton>(find.byKey(const Key('onlineFetch'))).onPressed, isNotNull, reason: '${kind.name}: the user can try again or change the name');
        await tester.pumpWidget(const SizedBox());
      }
    });
  });

  group('startup: the database cannot be opened', () {
    late InMemorySecretStore keys;
    late FakeSharedExports exports;
    setUp(() {
      keys = InMemorySecretStore({'openai': 'sk-1', 'custom': 'sk-2'});
      exports = FakeSharedExports();
    });

    Bootstrap bootstrap({
      Future<String> Function()? databasePath,
      required Future<Db> Function(String path) open,
      Future<void> Function(String path)? deleteFiles,
    }) =>
        Bootstrap(
          databasePath: databasePath ?? () async => '/data/glyph.db',
          open: open,
          deleteFiles: deleteFiles ?? (_) async {},
          secretStore: keys,
          sharedExports: exports,
        );

    Future<void> pumpBootstrap(WidgetTester tester, Bootstrap bootstrap) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(bootstrap);
      await tester.pumpAndSettle();
    }

    /// A file database written by "a newer Glyph" (user_version above this build's).
    String newerDbFile() {
      final dir = Directory.systemTemp.createTempSync('glyph_newer');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/glyph.db';
      final raw = sqlite3.open(path);
      raw.execute('CREATE TABLE games (x)');
      raw.userVersion = Db.schemaVersion + 1;
      raw.close();
      return path;
    }

    testWidgets('shows the recovery screen with copy, Try again and Delete the database', (tester) async {
      final lines = <String>[];
      final old = AppLog.sink;
      AppLog.sink = lines.add;
      addTearDown(() => AppLog.sink = old);
      await pumpBootstrap(tester, bootstrap(databasePath: () async => '/nowhere/glyph.db', open: (_) async => throw StateError('malformed disk image: /secret/path')));
      expect(find.text(l10n.startupDbTitle), findsOneWidget);
      expect(find.text(l10n.startupDbBody), findsOneWidget);
      expect(find.byKey(const Key('startup-retry')), findsOneWidget);
      expect(find.byKey(const Key('startup-reset')), findsOneWidget);
      expect(lines.single, 'Opening the database failed (StateError)', reason: 'the type only, never the message');
    });

    testWidgets('a database from a newer Glyph (a real file with a higher user_version): "update Glyph", Try again, Delete only behind two confirmations', (tester) async {
      final path = newerDbFile();
      var deletes = 0;
      await pumpBootstrap(tester, bootstrap(databasePath: () async => path, open: openAppDb, deleteFiles: (_) async => deletes++));
      expect(find.text(l10n.startupDbNewerBody), findsOneWidget);
      expect(l10n.startupDbNewerBody, contains('Update Glyph'));
      expect(find.text(l10n.startupDbBody), findsNothing);
      expect(find.byKey(const Key('startup-retry')), findsOneWidget);
      // Delete is not the primary action: a text button with its own label, not the filled / outlined one.
      expect(find.widgetWithText(FilledButton, l10n.startupDbRetry), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, l10n.startupDbReset), findsNothing);
      expect(find.widgetWithText(TextButton, l10n.startupDbResetNewer), findsOneWidget);
      expect(find.text(l10n.startupDbReset), findsNothing);

      // First confirmation: Cancel stops everything.
      await tester.tap(find.byKey(const Key('startup-reset')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.startupDbNewerConfirmTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('startup-newer-cancel')));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      // Second confirmation: Continue leads to the normal one, Cancel there stops too.
      await tester.tap(find.byKey(const Key('startup-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startup-newer-continue')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.startupDbResetConfirmTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('startup-reset-cancel')));
      await tester.pumpAndSettle();
      expect(deletes, 0);
      expect(keys.slots, unorderedEquals(['openai', 'custom']), reason: 'nothing was deleted');
      expect(File(path).existsSync(), isTrue);
    });

    testWidgets('a database from a newer Glyph is left untouched by the failed open (the file and its user_version)', (tester) async {
      final path = newerDbFile();
      final before = File(path).readAsBytesSync();
      await pumpBootstrap(tester, bootstrap(databasePath: () async => path, open: openAppDb));
      final raw = sqlite3.open(path);
      addTearDown(raw.close);
      expect(raw.userVersion, Db.schemaVersion + 1);
      expect(File(path).readAsBytesSync(), before);
    });

    testWidgets('a full disk (a real SQLITE_FULL): "free some space" and Try again; Delete is not offered', (tester) async {
      var broken = true;
      await pumpBootstrap(
        tester,
        bootstrap(open: (_) async {
          if (broken) throw _realSqliteFull();
          return Db.inMemory();
        }),
      );
      expect(find.text(l10n.startupDbFullBody), findsOneWidget);
      expect(l10n.startupDbFullBody, contains('Free some space'));
      expect(find.byKey(const Key('startup-retry')), findsOneWidget);
      expect(find.byKey(const Key('startup-reset')), findsNothing);
      broken = false;
      await tester.tap(find.byKey(const Key('startup-retry')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
    });

    test('classifyDbOpenFailure: newer, full (SQLite and ENOSPC), everything else', () {
      expect(classifyDbOpenFailure(const DatabaseTooNewException(found: 9, supported: 5)), DbOpenProblem.newerVersion);
      expect(classifyDbOpenFailure(_realSqliteFull()), DbOpenProblem.diskFull);
      expect(classifyDbOpenFailure(const FileSystemException('write failed', '/x', OSError('No space left on device', 28))), DbOpenProblem.diskFull);
      expect(classifyDbOpenFailure(const FileSystemException('denied', '/x', OSError('Permission denied', 13))), DbOpenProblem.other);
      expect(classifyDbOpenFailure(StateError('Database is newer')), DbOpenProblem.other, reason: 'only the typed exception counts, not a message');
      expect(classifyDbOpenFailure(SqliteException(extendedResultCode: 11, message: 'malformed')), DbOpenProblem.other);
    });

    testWidgets('Try again opens the app once the database works', (tester) async {
      var broken = true;
      await pumpBootstrap(
        tester,
        bootstrap(open: (_) async {
          if (broken) throw StateError('locked');
          return Db.inMemory();
        }),
      );
      expect(find.text(l10n.startupDbTitle), findsOneWidget);
      broken = false;
      await tester.tap(find.byKey(const Key('startup-retry')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.startupDbTitle), findsNothing);
      expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
    });

    testWidgets('Try again twice in a row opens the database once (no concurrent opens)', (tester) async {
      var opens = 0;
      final gate = Completer<Db>();
      await pumpBootstrap(
        tester,
        bootstrap(open: (_) {
          opens++;
          return opens == 1 ? Future<Db>.error(StateError('locked')) : gate.future;
        }),
      );
      expect(opens, 1);
      final retry = tester.widget<FilledButton>(find.byKey(const Key('startup-retry'))).onPressed!;
      retry();
      retry();
      await tester.pump();
      expect(opens, 2, reason: 'the second tap is ignored while the first open runs');
      gate.complete(Db.inMemory());
      await tester.pumpAndSettle();
      expect(opens, 2);
      expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
    });

    testWidgets('the connection is closed when the settings read fails after a successful open', (tester) async {
      final db = Db.inMemory();
      db.raw.execute('DROP TABLE settings');
      await pumpBootstrap(tester, bootstrap(open: (_) async => db));
      expect(find.text(l10n.startupDbTitle), findsOneWidget);
      expect(() => db.raw.select('SELECT 1'), throwsA(anything), reason: 'a leaked handle would stay open (and later delete the new database\'s WAL)');
    });

    testWidgets('Delete the database asks first, then erases the API keys, the files and the exported PGN, and opens a fresh one', (tester) async {
      var broken = true;
      final deleted = <String>[];
      await pumpBootstrap(
        tester,
        bootstrap(
          databasePath: () async => '/data/glyph.db',
          open: (_) async {
            if (broken) throw StateError('corrupt');
            return Db.inMemory();
          },
          deleteFiles: (path) async {
            deleted.add(path);
            broken = false;
          },
        ),
      );
      expect(exports.clears, 1, reason: 'exported files are removed at every start');
      await tester.tap(find.byKey(const Key('startup-reset')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.startupDbResetConfirmTitle), findsOneWidget);
      expect(find.text(l10n.startupDbResetConfirmBody), findsOneWidget);
      await tester.tap(find.byKey(const Key('startup-reset-cancel')));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
      expect(keys.slots, isNotEmpty);
      await tester.tap(find.byKey(const Key('startup-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startup-reset-confirm')));
      await tester.pumpAndSettle();
      expect(deleted, ['/data/glyph.db']);
      expect(keys.slots, isEmpty, reason: 'the key bindings live in the database: a key must not survive without its binding');
      expect(exports.clears, 2);
      expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
    });

    test('the confirmation lists what is deleted, and no longer says the keys are kept', () {
      final body = l10n.startupDbResetConfirmBody;
      for (final word in ['games', 'analyses', 'saved explanations', 'settings', 'LLM configuration', 'API keys', 'accounts', 'appearance']) {
        expect(body, contains(word));
      }
      expect(body, isNot(contains('kept')));
      for (final word in ['games', 'analyses', 'saved explanations', 'settings', 'LLM configuration', 'API keys', 'accounts', 'appearance']) {
        expect(l10n.settingsDeleteAllBody, contains(word), reason: 'Delete all data says the same');
      }
    });

    testWidgets('a key that cannot be deleted stops the reset before any file is deleted, and says so', (tester) async {
      keys.failDeletes = true;
      final deleted = <String>[];
      await pumpBootstrap(tester, bootstrap(open: (_) async => throw StateError('corrupt'), deleteFiles: (p) async => deleted.add(p)));
      await tester.tap(find.byKey(const Key('startup-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startup-reset-confirm')));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty, reason: 'database and bindings stay together');
      expect(find.byKey(const Key('startup-reset-failed')), findsOneWidget);
      expect(find.byKey(const Key('startup-retry')), findsOneWidget);
      expect(find.byKey(const Key('startup-reset')), findsOneWidget);
    });

    testWidgets('a delete that fails says so and keeps both buttons', (tester) async {
      await pumpBootstrap(
        tester,
        bootstrap(open: (_) async => throw StateError('corrupt'), deleteFiles: (_) async => throw const FormatException('read-only')),
      );
      await tester.tap(find.byKey(const Key('startup-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startup-reset-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('startup-reset-failed')), findsOneWidget);
      expect(find.text(l10n.startupDbResetFailed), findsOneWidget);
      expect(find.byKey(const Key('startup-retry')), findsOneWidget);
    });

    test('deleteDatabaseFiles removes the database, -wal, -shm and -journal, leaves other files, and tolerates missing ones', () async {
      final dir = Directory.systemTemp.createTempSync('glyph_delete');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/glyph.db';
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        File('$path$suffix').writeAsStringSync('x$suffix');
      }
      File('${dir.path}/other.db').writeAsStringSync('keep');
      await deleteDatabaseFiles(path);
      expect(dir.listSync().map((e) => e.path.split('/').last), ['other.db']);
      await deleteDatabaseFiles(path); // nothing left: no error
      // Only some exist.
      File('$path-wal').writeAsStringSync('w');
      await deleteDatabaseFiles(path);
      expect(File('$path-wal').existsSync(), isFalse);
    });

    test('a real database in WAL mode is fully removed, and a fresh one opened at the same path holds none of its rows', () async {
      final dir = Directory.systemTemp.createTempSync('glyph_wal');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/glyph.db';
      final old = await openAppDb(path);
      old.raw.execute('PRAGMA wal_autocheckpoint = 0');
      old.raw.execute("INSERT INTO settings VALUES ('k', 'old')");
      expect(File('$path-wal').existsSync(), isTrue, reason: 'the row lives in the WAL');
      old.close();
      await deleteDatabaseFiles(path);
      expect(dir.listSync(), isEmpty);
      final fresh = await openAppDb(path);
      addTearDown(fresh.close);
      expect(fresh.raw.select("SELECT * FROM settings WHERE key = 'k'"), isEmpty);
    });

    test('a failed open of a newer database closes its native handle: no WAL / SHM is left behind by a leaked connection', () {
      final dir = Directory.systemTemp.createTempSync('glyph_leak');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/glyph.db';
      final w = sqlite3.open(path);
      w.execute('PRAGMA journal_mode = WAL');
      w.execute('CREATE TABLE t (x)');
      w.userVersion = 99;
      w.close();
      expect(() => Db.open(path), throwsA(isA<DatabaseTooNewException>()));
      // A closed WAL database leaves only the main file; a leaked connection keeps -wal and -shm.
      expect(dir.listSync().map((e) => e.path.split('/').last).toList(), ['glyph.db']);
    });

    test('a migration that fails also closes the handle', () {
      final dir = Directory.systemTemp.createTempSync('glyph_leak2');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/glyph.db';
      expect(
        () => Db.open(path, migrations: [(db) => db.execute('CREATE TABLE a (x)'), (db) => throw StateError('boom')]),
        throwsStateError,
      );
      expect(dir.listSync().map((e) => e.path.split('/').last).toList(), ['glyph.db']);
    });
  });
}

/// A real SQLITE_FULL: a database capped at two pages cannot take a bigger row.
SqliteException _realSqliteFull() {
  final raw = sqlite3.openInMemory();
  try {
    raw.execute('CREATE TABLE t (x BLOB)');
    raw.execute('PRAGMA max_page_count = 2');
    raw.execute("INSERT INTO t VALUES (randomblob(100000))");
  } on SqliteException catch (e) {
    return e;
  } finally {
    raw.close();
  }
  throw StateError('the insert should have failed with SQLITE_FULL');
}

/// A game repository whose reads can be made to fail, and whose `save` too.
class _FlakyGames extends InMemoryGameRepository {
  _FlakyGames(super.store, this.failing);

  final bool Function() failing;
  bool Function()? readFails;
  bool failSave = false;

  @override
  Future<List<GameRecord>> list() async {
    if (failing()) throw StateError('disk I/O error');
    return super.list();
  }

  @override
  Future<GameRecord?> get(int id) async {
    if (failing() || (readFails?.call() ?? false)) throw StateError('disk I/O error');
    return super.get(id);
  }

  @override
  Future<SaveResult> save(NewGame game) async {
    if (failSave) throw StateError('disk full');
    return super.save(game);
  }
}
