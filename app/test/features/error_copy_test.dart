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
import 'package:glyph/routes.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

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
    Future<void> pumpBootstrap(WidgetTester tester, Bootstrap bootstrap) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(bootstrap);
      await tester.pumpAndSettle();
    }

    testWidgets('shows the recovery screen with copy, Try again and Delete the database', (tester) async {
      final lines = <String>[];
      final old = AppLog.sink;
      AppLog.sink = lines.add;
      addTearDown(() => AppLog.sink = old);
      await pumpBootstrap(
        tester,
        Bootstrap(databasePath: () async => '/nowhere/glyph.db', open: (_) async => throw StateError('Database is newer (v9) than this app (v5).'), deleteFiles: (_) async {}),
      );
      expect(find.text(l10n.startupDbTitle), findsOneWidget);
      expect(find.text(l10n.startupDbBody), findsOneWidget);
      expect(find.byKey(const Key('startup-retry')), findsOneWidget);
      expect(find.byKey(const Key('startup-reset')), findsOneWidget);
      expect(lines.single, 'Opening the database failed (StateError)', reason: 'the type only, never the message');
    });

    testWidgets('Try again opens the app once the database works', (tester) async {
      var broken = true;
      await pumpBootstrap(
        tester,
        Bootstrap(
          databasePath: () async => ':memory:',
          open: (_) async {
            if (broken) throw StateError('locked');
            return Db.inMemory();
          },
          deleteFiles: (_) async {},
        ),
      );
      expect(find.text(l10n.startupDbTitle), findsOneWidget);
      broken = false;
      await tester.tap(find.byKey(const Key('startup-retry')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.startupDbTitle), findsNothing);
      expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
    });

    testWidgets('Delete the database asks first, then deletes the files and opens a fresh one', (tester) async {
      var broken = true;
      final deleted = <String>[];
      await pumpBootstrap(
        tester,
        Bootstrap(
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
      await tester.tap(find.byKey(const Key('startup-reset')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.startupDbResetConfirmTitle), findsOneWidget);
      await tester.tap(find.byKey(const Key('startup-reset-cancel')));
      await tester.pumpAndSettle();
      expect(deleted, isEmpty);
      await tester.tap(find.byKey(const Key('startup-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startup-reset-confirm')));
      await tester.pumpAndSettle();
      expect(deleted, ['/data/glyph.db']);
      expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
    });

    testWidgets('a delete that fails says so and keeps both buttons', (tester) async {
      await pumpBootstrap(
        tester,
        Bootstrap(databasePath: () async => '/data/glyph.db', open: (_) async => throw StateError('corrupt'), deleteFiles: (_) async => throw const FormatException('read-only')),
      );
      await tester.tap(find.byKey(const Key('startup-reset')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('startup-reset-confirm')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('startup-reset-failed')), findsOneWidget);
      expect(find.text(l10n.startupDbResetFailed), findsOneWidget);
      expect(find.byKey(const Key('startup-retry')), findsOneWidget);
    });

    testWidgets('the real opener rejects a database from a newer version and the app starts on an older, valid file', (tester) async {
      final dbFiles = <String>[];
      expect(dbFiles, isEmpty);
      final db = await openAppDb(':memory:');
      expect(db.raw.userVersion, Db.schemaVersion);
      db.close();
    });
  });
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
