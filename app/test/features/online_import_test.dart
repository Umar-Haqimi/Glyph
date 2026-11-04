import 'dart:async';
import 'dart:convert';
import 'dart:ui' show CheckedState;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/data/in_memory.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/features/board/board_screen.dart';
import 'package:glyph/features/import/online_import_screen.dart';
import 'package:glyph/features/library/library_screen.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_online.dart';
import '../support/test_app.dart';

Future<void> openOnline(WidgetTester tester, String row) async {
  await tester.tap(find.text(l10n.libraryImportFab));
  await tester.pumpAndSettle();
  await tester.tap(find.text(row));
  await tester.pumpAndSettle();
}

Future<void> typeName(WidgetTester tester, String name) async {
  await tester.enterText(find.byKey(const Key('onlineUsername')), name);
  await tester.pumpAndSettle();
}

Future<void> fetch(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('onlineFetch')));
  await tester.pumpAndSettle();
}

String status(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('onlineStatus'))).data!;
bool enabled(WidgetTester tester, String key) => tester.widget<FilledButton>(find.byKey(Key(key))).onPressed != null;
String importLabel(WidgetTester tester) => (tester.widget<FilledButton>(find.byKey(const Key('onlineImport'))).child! as Text).data!;
bool checked(WidgetTester tester, String id) => tester.widget<CheckboxListTile>(find.byKey(Key('online-game-$id'))).value!;

class _SlowSettings extends InMemorySettingsRepository {
  _SlowSettings(this.gate, Map<String, String> initial) : super(initial);

  final Future<void> gate;

  @override
  Future<String?> get(String key) async {
    await gate;
    return super.get(key);
  }
}

void main() {
  group('the import sheet', () {
    testWidgets('both rows open the matching screen', (tester) async {
      await TestEnv().pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      expect(find.text(l10n.onlineUsernameLabelLichess), findsOneWidget);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await openOnline(tester, l10n.importFromChessCom);
      expect(find.text(l10n.onlineUsernameLabelChessCom), findsOneWidget);
    });
  });

  group('username', () {
    testWidgets('prefilled from Settings > Accounts, per site', (tester) async {
      final env = TestEnv(settings: {'lichess_username': 'Alice_99', 'chesscom_username': 'alice-cc'});
      await env.pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      expect(tester.widget<TextField>(find.byKey(const Key('onlineUsername'))).controller!.text, 'Alice_99');
      expect(enabled(tester, 'onlineFetch'), isTrue);
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      await openOnline(tester, l10n.importFromChessCom);
      expect(tester.widget<TextField>(find.byKey(const Key('onlineUsername'))).controller!.text, 'alice-cc');
    });

    testWidgets('an invalid name shows the format and cannot be fetched', (tester) async {
      final lichess = FakeOnlineClient.games([]);
      await TestEnv(lichess: lichess).pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      expect(enabled(tester, 'onlineFetch'), isFalse, reason: 'empty');
      await typeName(tester, 'bad name!');
      expect(find.text(l10n.onlineUsernameInvalidLichess), findsOneWidget);
      expect(enabled(tester, 'onlineFetch'), isFalse);
      await typeName(tester, 'good_name');
      expect(find.text(l10n.onlineUsernameInvalidLichess), findsNothing);
      expect(enabled(tester, 'onlineFetch'), isTrue);
      expect(lichess.usernames, isEmpty);
    });

    testWidgets('typing before the saved name arrives is not overwritten', (tester) async {
      final gate = Completer<void>();
      final repo = _SlowSettings(gate.future, {'lichess_username': 'saved'});
      await TestEnv(settingsRepo: repo).pump(tester);
      await tester.tap(find.text(l10n.libraryImportFab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.importFromLichess));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('onlineUsername')), 'typed');
      await tester.pump();
      gate.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byKey(const Key('onlineUsername'))).controller!.text, 'typed');
    });
  });

  group('fetch and list', () {
    testWidgets('games stream in, then chips filter, select and import', (tester) async {
      final gate = Completer<void>();
      final games = [
        lichessOnline('aaaaaaa1', speed: OnlineSpeed.bullet),
        lichessOnline('aaaaaaa2', speed: OnlineSpeed.blitz, white: 'carol', black: 'alice', result: '0-1'),
        lichessOnline('aaaaaaa3', speed: OnlineSpeed.rapid),
      ];
      final lichess = FakeOnlineClient((username, token, emit) async {
        emit(OnlineGameReceived(games[0], 1));
        await gate.future;
        emit(OnlineGameReceived(games[1], 2));
        emit(OnlineGameReceived(games[2], 3));
        return OnlineFetchOutcome(games: games);
      });
      final env = TestEnv(lichess: lichess, settings: {'lichess_username': 'alice'});
      await env.pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await tester.tap(find.byKey(const Key('onlineFetch')));
      await tester.pump();
      await tester.pump();

      // Streaming: one game is there, the others are not, Cancel replaces Fetch.
      expect(find.byKey(const Key('online-game-aaaaaaa1')), findsOneWidget);
      expect(find.byKey(const Key('online-game-aaaaaaa2')), findsNothing);
      expect(find.byKey(const Key('onlineCancel')), findsOneWidget);
      expect(find.byKey(const Key('onlineFetch')), findsNothing);
      expect(status(tester), l10n.onlineLoading(1, 'Lichess'));
      expect(find.byType(LinearProgressIndicator), findsOneWidget);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('onlineCancel')), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.byType(CheckboxListTile), findsNWidgets(3));
      expect(lichess.usernames, ['alice']);
      expect(find.textContaining('alice (1500)'), findsWidgets);
      expect(find.textContaining('2023-11-14'), findsNWidgets(3));
      expect(find.textContaining('Blitz 3+2'), findsOneWidget);

      // Chips filter by speed; the lichess set is Bullet/Blitz/Rapid/Classical/Correspondence.
      for (final name in [l10n.speedBullet, l10n.speedBlitz, l10n.speedRapid, l10n.speedClassical, l10n.speedCorrespondence]) {
        expect(find.widgetWithText(FilterChip, name), findsOneWidget);
      }
      expect(find.widgetWithText(FilterChip, l10n.speedDaily), findsNothing);
      await tester.tap(find.byKey(const Key('speed-blitz')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(1));
      await tester.tap(find.byKey(const Key('speed-bullet')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('speed-blitz')));
      await tester.tap(find.byKey(const Key('speed-bullet')));
      await tester.tap(find.byKey(const Key('speed-classical')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.onlineNoMatch), findsOneWidget);
      await tester.tap(find.byKey(const Key('speed-classical')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsNWidgets(3));

      // Select two and import.
      expect(enabled(tester, 'onlineImport'), isFalse);
      expect(importLabel(tester), l10n.onlineImportSelected(0));
      await tester.tap(find.byKey(const Key('online-game-aaaaaaa1')));
      await tester.tap(find.byKey(const Key('online-game-aaaaaaa2')));
      await tester.pumpAndSettle();
      expect(checked(tester, 'aaaaaaa1'), isTrue);
      expect(checked(tester, 'aaaaaaa3'), isFalse);
      expect(importLabel(tester), l10n.onlineImportSelected(2));
      expect(find.text(l10n.onlineSelectedCount(2, 3)), findsOneWidget);

      await tester.tap(find.byKey(const Key('onlineImport')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.onlineImported(2)), findsOneWidget);
      expect(find.byType(OnlineImportScreen), findsNothing);
      expect(find.byType(GameCard), findsNWidgets(2));
      final saved = await env.games.list();
      expect(saved.map((g) => g.source).toSet(), {GameSource.lichess});
      expect(saved.map((g) => g.sourceId).toSet(), {'aaaaaaa1', 'aaaaaaa2'});
      // The fetched account decides the side: alice was White in the first, Black in the second.
      final bySource = {for (final g in saved) g.sourceId!: g};
      expect(bySource['aaaaaaa1']!.userSide, Side.white);
      expect(bySource['aaaaaaa2']!.userSide, Side.black);
      expect(bySource['aaaaaaa1']!.plyCount, 10);
      expect(bySource['aaaaaaa1']!.whiteElo, 1500);
    });

    testWidgets('exactly one game: straight to the board', (tester) async {
      final env = TestEnv(lichess: FakeOnlineClient.games([lichessOnline('aaaaaaa1')]), book: realBook());
      await env.pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      await tester.tap(find.byKey(const Key('online-game-aaaaaaa1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onlineImport')));
      await tester.pumpAndSettle();
      expect(find.byType(BoardScreen), findsOneWidget);
      expect((await env.games.list()).single.sourceId, 'aaaaaaa1');
    });

    testWidgets('select all / none, and games already in the library are marked and skipped', (tester) async {
      final env = TestEnv(lichess: FakeOnlineClient.games([lichessOnline('aaaaaaa1'), lichessOnline('aaaaaaa2'), lichessOnline('aaaaaaa3')]));
      await env.pump(tester);
      await env.games.save(const NewGame(source: GameSource.lichess, sourceId: 'aaaaaaa2', pgn: '1. e4 *', plyCount: 1, importedAt: 1));
      // Same id from another source is not a duplicate.
      await env.games.save(const NewGame(source: GameSource.paste, sourceId: 'aaaaaaa3', pgn: '1. e4 *', plyCount: 1, importedAt: 1));
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);

      expect(find.byKey(const Key('in-library-aaaaaaa2')), findsOneWidget);
      expect(find.byKey(const Key('in-library-aaaaaaa1')), findsNothing);
      expect(find.byKey(const Key('in-library-aaaaaaa3')), findsNothing);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('online-game-aaaaaaa2'))).onChanged, isNull);
      await tester.tap(find.byKey(const Key('online-game-aaaaaaa2')));
      await tester.pumpAndSettle();
      expect(importLabel(tester), l10n.onlineImportSelected(0));

      await tester.tap(find.byKey(const Key('onlineSelectAll')));
      await tester.pumpAndSettle();
      expect(importLabel(tester), l10n.onlineImportSelected(2));
      await tester.tap(find.byKey(const Key('onlineSelectNone')));
      await tester.pumpAndSettle();
      expect(importLabel(tester), l10n.onlineImportSelected(0));

      await tester.tap(find.byKey(const Key('onlineSelectAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onlineImport')));
      await tester.pumpAndSettle();
      final games = await env.games.list();
      expect(games.length, 4, reason: '2 seeded + 2 new');
      expect(games.where((g) => g.source == GameSource.lichess).map((g) => g.sourceId).toSet(), {'aaaaaaa1', 'aaaaaaa2', 'aaaaaaa3'});
      expect(games.where((g) => g.sourceId == 'aaaaaaa2').length, 1);
    });

    testWidgets('after importing, the same fetch marks the games and a second fetch dedupes', (tester) async {
      final env = TestEnv(lichess: FakeOnlineClient.games([lichessOnline('aaaaaaa1'), lichessOnline('aaaaaaa2')]));
      await env.pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      await tester.tap(find.byKey(const Key('onlineSelectAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onlineImport')));
      await tester.pumpAndSettle();
      expect((await env.games.list()).length, 2);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      expect(find.byKey(const Key('in-library-aaaaaaa1')), findsOneWidget);
      expect(find.byKey(const Key('in-library-aaaaaaa2')), findsOneWidget);
      expect(enabled(tester, 'onlineImport'), isFalse);
    });

    testWidgets('a game whose PGN cannot be read is counted, the others are saved', (tester) async {
      final bad = lichessOnline('aaaaaaa2', pgn: '[White "x"]\n\n1. e4 e5 2. Ke5 *');
      final env = TestEnv(lichess: FakeOnlineClient.games([lichessOnline('aaaaaaa1'), bad]));
      await env.pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      await tester.tap(find.byKey(const Key('onlineSelectAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onlineImport')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.onlineImportedSome(1, 1)), findsOneWidget);
      expect((await env.games.list()).single.sourceId, 'aaaaaaa1');
    });

    testWidgets('configured account names are used when the game does not tell', (tester) async {
      final env = TestEnv(
        lichess: FakeOnlineClient.games([lichessOnline('aaaaaaa1', white: 'xx', black: 'yy')]),
        settings: {'lichess_username': 'yy'},
      );
      await env.pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await fetch(tester); // prefilled "yy"
      await tester.tap(find.byKey(const Key('onlineSelectAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onlineImport')));
      await tester.pumpAndSettle();
      expect((await env.games.list()).single.userSide, Side.black);
    });

    testWidgets('chess.com: Bullet/Blitz/Rapid/Daily chips, URL as source id', (tester) async {
      final env = TestEnv(
        chessCom: FakeOnlineClient.games([
          chessComOnline('1', speed: OnlineSpeed.daily),
          chessComOnline('2', speed: OnlineSpeed.rapid),
        ]),
      );
      await env.pump(tester);
      await openOnline(tester, l10n.importFromChessCom);
      await typeName(tester, 'alice-cc');
      await fetch(tester);
      for (final name in [l10n.speedBullet, l10n.speedBlitz, l10n.speedRapid, l10n.speedDaily]) {
        expect(find.widgetWithText(FilterChip, name), findsOneWidget);
      }
      expect(find.widgetWithText(FilterChip, l10n.speedClassical), findsNothing);
      await tester.tap(find.byKey(const Key('speed-daily')));
      await tester.pumpAndSettle();
      expect(find.byType(CheckboxListTile), findsOneWidget);
      await tester.tap(find.byKey(const Key('onlineSelectAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onlineImport')));
      await tester.pumpAndSettle();
      final saved = (await env.games.list()).single;
      expect(saved.source, GameSource.chesscom);
      expect(saved.sourceId, 'https://www.chess.com/game/live/1');
    });
  });

  group('429, cancel and errors', () {
    testWidgets('"Lichess asked us to slow down. Retrying in 60 s." counts down, the fetch resumes by itself', (tester) async {
      final gate = Completer<void>();
      final lichess = FakeOnlineClient((username, token, emit) async {
        emit(const OnlineBackoff(OnlineSource.lichess, Duration(seconds: 60), Duration(seconds: 60)));
        await gate.future;
        emit(const OnlineBackoff(OnlineSource.lichess, Duration(seconds: 59), Duration(seconds: 60)));
        await gate.future;
        final g = lichessOnline('aaaaaaa1');
        emit(OnlineGameReceived(g, 1));
        return OnlineFetchOutcome(games: [g]);
      });
      await TestEnv(lichess: lichess).pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await tester.tap(find.byKey(const Key('onlineFetch')));
      await tester.pump();
      await tester.pump();
      expect(status(tester), 'Lichess asked us to slow down. Retrying in 60 s.');
      expect(status(tester), l10n.onlineBackoffLichess(60));
      expect(find.byKey(const Key('onlineCancel')), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('online-game-aaaaaaa1')), findsOneWidget);
      expect(find.textContaining('slow down'), findsNothing);
    });

    testWidgets('chess.com uses its own name in the notice', (tester) async {
      final chessCom = FakeOnlineClient((username, token, emit) async {
        emit(const OnlineBackoff(OnlineSource.chesscom, Duration(milliseconds: 41500), Duration(seconds: 60)));
        await Completer<void>().future;
        return const OnlineFetchOutcome();
      });
      await TestEnv(chessCom: chessCom).pump(tester);
      await openOnline(tester, l10n.importFromChessCom);
      await typeName(tester, 'alice-cc');
      await tester.tap(find.byKey(const Key('onlineFetch')));
      await tester.pump();
      await tester.pump();
      expect(status(tester), l10n.onlineBackoffChessCom(42), reason: 'rounded up');
      expect(status(tester), startsWith('Chess.com asked us to slow down'));
    });

    testWidgets('Cancel during the backoff cancels the client\'s token and keeps what arrived', (tester) async {
      late FakeOnlineClient lichess;
      lichess = FakeOnlineClient((username, token, emit) async {
        final g = lichessOnline('aaaaaaa1');
        emit(OnlineGameReceived(g, 1));
        emit(const OnlineBackoff(OnlineSource.lichess, Duration(seconds: 60), Duration(seconds: 60)));
        await token.whenCancelled;
        return OnlineFetchOutcome(games: [g], cancelled: true);
      });
      await TestEnv(lichess: lichess).pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await tester.tap(find.byKey(const Key('onlineFetch')));
      await tester.pump();
      await tester.pump();
      expect(status(tester), l10n.onlineBackoffLichess(60));
      await tester.tap(find.byKey(const Key('onlineCancel')));
      await tester.pumpAndSettle();
      expect(lichess.tokens.single.isCancelled, isTrue);
      expect(status(tester), l10n.onlineCancelled);
      expect(find.byKey(const Key('online-game-aaaaaaa1')), findsOneWidget);
      expect(find.byKey(const Key('onlineFetch')), findsOneWidget);
    });

    testWidgets('leaving the screen cancels a running fetch', (tester) async {
      final lichess = FakeOnlineClient((username, token, emit) async {
        await token.whenCancelled;
        return const OnlineFetchOutcome(cancelled: true);
      });
      await TestEnv(lichess: lichess).pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await tester.tap(find.byKey(const Key('onlineFetch')));
      await tester.pump();
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(lichess.tokens.single.isCancelled, isTrue);
    });

    final cases = <(OnlineFetchError, String Function())>[
      (const OnlineFetchError(OnlineErrorKind.userNotFound), () => l10n.onlineErrorUserNotFound('Lichess')),
      (const OnlineFetchError(OnlineErrorKind.offline), () => l10n.onlineErrorOffline),
      (const OnlineFetchError(OnlineErrorKind.rateLimited), () => l10n.onlineErrorRateLimited('Lichess')),
      (const OnlineFetchError(OnlineErrorKind.timeout), () => l10n.onlineErrorTimeout('Lichess')),
      (const OnlineFetchError(OnlineErrorKind.tls), () => l10n.onlineErrorTls('Lichess')),
      (const OnlineFetchError(OnlineErrorKind.server, status: 503), () => l10n.onlineErrorServer('Lichess', 503)),
      (const OnlineFetchError(OnlineErrorKind.badResponse), () => l10n.onlineErrorBadResponse('Lichess')),
      (const OnlineFetchError(OnlineErrorKind.tooLarge), () => l10n.onlineErrorTooLarge('Lichess')),
      (const OnlineFetchError(OnlineErrorKind.unavailable), () => l10n.onlineErrorUnavailable('Lichess')),
    ];
    for (final (error, text) in cases) {
      testWidgets('error ${error.kind.name} has its own copy and Fetch again works', (tester) async {
        await TestEnv(lichess: FakeOnlineClient.failing(error)).pump(tester);
        await openOnline(tester, l10n.importFromLichess);
        await typeName(tester, 'alice');
        await fetch(tester);
        expect(status(tester), text());
        expect(find.text(l10n.onlineFetchAgain), findsOneWidget);
      });
    }

    testWidgets('user not found names chess.com on the chess.com screen', (tester) async {
      await TestEnv(chessCom: FakeOnlineClient.failing(const OnlineFetchError(OnlineErrorKind.userNotFound))).pump(tester);
      await openOnline(tester, l10n.importFromChessCom);
      await typeName(tester, 'nobody1');
      await fetch(tester);
      expect(status(tester), 'Chess.com has no user with that name.');
    });

    testWidgets('a failure after some games keeps them and says why; skipped games are counted', (tester) async {
      final lichess = FakeOnlineClient.games([lichessOnline('aaaaaaa1')], skipped: 3, error: const OnlineFetchError(OnlineErrorKind.timeout));
      await TestEnv(lichess: lichess).pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      expect(find.byKey(const Key('online-game-aaaaaaa1')), findsOneWidget);
      expect(status(tester), contains(l10n.onlineErrorTimeout('Lichess')));
      expect(status(tester), contains(l10n.onlineSkipped(3)));
    });

    testWidgets('no games: says so', (tester) async {
      await TestEnv(lichess: FakeOnlineClient.games([])).pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      expect(status(tester), l10n.onlineEmpty);
    });

    testWidgets('a client that throws is a bad-response message, never a crash', (tester) async {
      final lichess = FakeOnlineClient((username, token, emit) async => throw StateError('boom'));
      await TestEnv(lichess: lichess).pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      expect(status(tester), l10n.onlineErrorBadResponse('Lichess'));
    });
  });

  group('with the real clients (no network: a MockClient answers)', () {
    testWidgets('lichess NDJSON through LichessClient into the list and the library', (tester) async {
      final ndjson = [
        for (final id in ['aaaaaaa1', 'aaaaaaa2'])
          jsonEncode({
            'id': id,
            'variant': 'standard',
            'speed': 'blitz',
            'status': 'resign',
            'winner': 'white',
            'createdAt': 1700000000000,
            'moves': 'e4 e5',
            'players': {
              'white': {'user': {'name': 'alice'}, 'rating': 1500},
              'black': {'user': {'name': 'bob'}, 'rating': 1400},
            },
            'pgn': '[White "alice"]\n[Black "bob"]\n[Result "1-0"]\n\n1. e4 e5 1-0\n',
          }),
      ].join('\n');
      late http.BaseRequest seen;
      final client = LichessClient(
        httpClient: () => MockClient.streaming((request, body) async {
          seen = request;
          return http.StreamedResponse(Stream.value(utf8.encode(ndjson)), 200, request: request);
        }),
        userAgent: 'Glyph/test',
      );
      final env = TestEnv(lichess: client);
      await env.pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      expect(seen.url.host, 'lichess.org');
      expect(seen.url.scheme, 'https');
      expect(seen.headers['User-Agent'], 'Glyph/test');
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      await tester.tap(find.byKey(const Key('onlineSelectAll')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('onlineImport')));
      await tester.pumpAndSettle();
      expect((await env.games.list()).length, 2);
    });
  });

  group('accessibility', () {
    testWidgets('tiles read as one checkbox with title, details and state; buttons are at least 48 dp', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv(lichess: FakeOnlineClient.games([lichessOnline('aaaaaaa1'), lichessOnline('aaaaaaa2')]));
      await env.pump(tester);
      await env.games.save(const NewGame(source: GameSource.lichess, sourceId: 'aaaaaaa2', pgn: '1. e4 *', plyCount: 1, importedAt: 1));
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      await tester.tap(find.byKey(const Key('online-game-aaaaaaa1')));
      await tester.pumpAndSettle();

      final first = tester.getSemantics(find.byKey(const Key('online-game-aaaaaaa1')));
      expect(first.label, contains('alice (1500) – bob (1480)'));
      expect(first.label, contains(l10n.onlineGameSelected));
      expect(first.flagsCollection.isChecked, CheckedState.isTrue);
      final second = tester.getSemantics(find.byKey(const Key('online-game-aaaaaaa2')));
      expect(second.label, contains(l10n.onlineAlreadyImported));

      for (final key in ['onlineFetch', 'onlineImport']) {
        expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(48), reason: key);
      }
      expect(tester.getSize(find.byKey(const Key('onlineSelectAll'))).height, greaterThanOrEqualTo(48));
      expect(tester.getSize(find.byKey(const Key('speed-blitz'))).height, greaterThanOrEqualTo(48));
      handle.dispose();
    });

    testWidgets('the status line is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await TestEnv(lichess: FakeOnlineClient.failing(const OnlineFetchError(OnlineErrorKind.offline))).pump(tester);
      await openOnline(tester, l10n.importFromLichess);
      await typeName(tester, 'alice');
      await fetch(tester);
      final node = tester.getSemantics(find.byKey(const Key('onlineStatus')));
      expect(node.label, l10n.onlineErrorOffline);
      expect(node.flagsCollection.isLiveRegion, isTrue);
      handle.dispose();
    });

    testWidgets('large text and a small phone do not overflow, in dark theme too', (tester) async {
      final env = TestEnv(lichess: FakeOnlineClient.games([for (var i = 0; i < 4; i++) lichessOnline('aaaaaaa$i')]));
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(ProviderScope(overrides: env.overrides, child: const GlyphApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.libraryImportFab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.importFromLichess));
      await tester.pumpAndSettle();
      await typeName(tester, 'alice');
      await fetch(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('online-game-aaaaaaa0')), findsOneWidget);
    });
  });
}
