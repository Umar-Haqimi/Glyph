import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/features/board/board_screen.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph/features/import/import_preview_screen.dart';
import 'package:glyph/features/library/library_screen.dart';
import 'package:glyph/l10n/app_localizations.dart';
import 'package:glyph/routes.dart';
import 'package:glyph/features/import/share_intake.dart';
import 'package:glyph/platform/share_intake.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_online.dart';
import '../support/test_app.dart';

const _channelName = 'test/intake';
const _codec = StandardMethodCodec();

/// Plays the native side: sends `shared` to the Dart handler.
Future<void> nativePush(Object? arguments) async {
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(_channelName, _codec.encodeMethodCall(MethodCall('shared', arguments)), (_) {});
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('the platform channel (Dart side of the intent handling)', () {
    late ChannelShareIntakeService service;
    late List<MethodCall> calls;
    Object? Function(MethodCall) native = (_) => null;

    setUp(() {
      calls = [];
      native = (_) => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(_channelName), (call) async {
        calls.add(call);
        return native(call);
      });
      service = ChannelShareIntakeService(channel: const MethodChannel(_channelName));
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(_channelName), null));
    });

    test('start() tells the native side that Dart listens', () async {
      await service.start();
      expect(calls.map((c) => c.method), ['ready']);
    });

    test('start() survives a missing or failing native side', () async {
      native = (_) => throw PlatformException(code: 'boom');
      await service.start();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel(_channelName), null);
      await service.start(); // MissingPluginException
    });

    test('text, file, too-large and error messages arrive in order as typed content', () async {
      final events = <SharedContent>[];
      final sub = service.shared.listen(events.add);
      addTearDown(sub.cancel);
      await nativePush({'kind': 'text', 'text': '1. e4 e5 *'});
      await nativePush({'kind': 'file', 'bytes': Uint8List.fromList(utf8.encode('[Event "x"]\n\n1. d4 *'))});
      await nativePush({'kind': 'tooLarge'});
      await nativePush({'kind': 'error'});
      await Future<void>.delayed(Duration.zero);
      expect(events.length, 4);
      expect((events[0] as SharedText).text, '1. e4 e5 *');
      expect(utf8.decode((events[1] as SharedFile).bytes), contains('1. d4'));
      expect(events[2], isA<SharedTooLarge>());
      expect(events[3], isA<SharedUnreadable>());
    });

    test('a method other than "shared" is answered as not implemented (null reply)', () async {
      ByteData? reply = ByteData(0);
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(_channelName, _codec.encodeMethodCall(const MethodCall('other')), (data) => reply = data);
      expect(reply, isNull);
    });

    group('decode (the platform is an input like any other)', () {
      test('valid messages', () {
        expect(ChannelShareIntakeService.decode({'kind': 'text', 'text': 'x'}), isA<SharedText>());
        expect(ChannelShareIntakeService.decode({'kind': 'file', 'bytes': Uint8List(3)}), isA<SharedFile>());
      });

      test('over 2 MB is refused whatever the native side checked', () {
        final big = 'a' * (Limits.maxPgnBytes + 1);
        expect(ChannelShareIntakeService.decode({'kind': 'text', 'text': big}), isA<SharedTooLarge>());
        expect(ChannelShareIntakeService.decode({'kind': 'file', 'bytes': Uint8List(Limits.maxPgnBytes + 1)}), isA<SharedTooLarge>());
        // The cap is in bytes: 2 MB of 2-byte characters is over it with half the characters.
        final wide = 'é' * (Limits.maxPgnBytes ~/ 2 + 1);
        expect(ChannelShareIntakeService.decode({'kind': 'text', 'text': wide}), isA<SharedTooLarge>());
        expect(ChannelShareIntakeService.decode({'kind': 'file', 'bytes': Uint8List(Limits.maxPgnBytes)}), isA<SharedFile>());
      });

      test('junk is unreadable, never an exception', () {
        for (final junk in <Object?>[null, 5, 'text', [], {}, {'kind': 'nope'}, {'kind': 'text'}, {'kind': 'text', 'text': 5}, {'kind': 'text', 'text': '   '}, {'kind': 'file'}, {'kind': 'file', 'bytes': 'abc'}, {'kind': 'file', 'bytes': [1, 2]}]) {
          expect(ChannelShareIntakeService.decode(junk), isA<SharedUnreadable>(), reason: '$junk');
        }
      });
    });
  });

  group('decideShare (what a shared text or file leads to)', () {
    test('PGN text from the lichess API export', () async {
      final d = await decideShare(SharedText(vectorPgn('lichess_api_export.pgn')));
      expect((d as ShareReady).result.games.single.plyCount, 31);
    });

    test('the chess.com app share text with its preamble, and the lichess app share', () async {
      for (final name in ['chesscom_app_share.pgn', 'lichess_app_share.pgn', 'chesscom_download_clk.pgn']) {
        final d = await decideShare(SharedText(vectorPgn(name)));
        expect(d, isA<ShareReady>(), reason: name);
        expect((d as ShareReady).result.games, isNotEmpty, reason: name);
      }
    });

    test('a file (bytes), a multi-game file, CRLF + BOM', () async {
      expect(await decideShare(SharedFile(bytesOf(vectorPgn('lichess_api_export.pgn')))), isA<ShareReady>());
      final fifty = await decideShare(SharedFile(bytesOf(vectorPgn('fifty_games.pgn')))) as ShareReady;
      expect(fifty.result.games.length, 50);
      expect(await decideShare(SharedFile(Uint8List.fromList(utf8.encode(vectorPgn('crlf_bom.pgn'))))), isA<ShareReady>());
    });

    test('a link is not fetched and is not a game', () async {
      for (final text in ['https://lichess.org/AbCdEfGh', 'Check this out https://www.chess.com/game/live/123456789 !', 'http://example.com/game']) {
        final d = await decideShare(SharedText(text));
        expect((d as ShareRefused).problem, ShareProblem.link, reason: text);
      }
    });

    test('text without a game', () async {
      expect(((await decideShare(const SharedText('hello there'))) as ShareRefused).problem, ShareProblem.noGame);
    });

    test('PGN problems keep their own message: illegal move, unsupported variant', () async {
      final illegal = await decideShare(SharedText(vectorPgn('illegal_move_single.pgn')));
      expect((illegal as ShareInvalid).issue.kind, PgnIssueKind.illegalMove);
      final zh = await decideShare(SharedText(vectorPgn('crazyhouse.pgn')));
      expect((zh as ShareInvalid).issue.kind, PgnIssueKind.unsupportedVariant);
    });

    test('2 MB: the cap holds for text and files', () async {
      expect(((await decideShare(SharedText('a' * (Limits.maxPgnBytes + 1)))) as ShareRefused).problem, ShareProblem.tooLarge);
      expect(((await decideShare(SharedFile(Uint8List(Limits.maxPgnBytes + 1)))) as ShareInvalid).issue.kind, PgnIssueKind.tooLarge);
      expect(((await decideShare(const SharedTooLarge())) as ShareRefused).problem, ShareProblem.tooLarge);
      expect(((await decideShare(const SharedUnreadable())) as ShareRefused).problem, ShareProblem.unreadable);
    });
  });

  group('routing into the import flow', () {
    testWidgets('the intake starts after the first frame, once', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      expect(env.intake.starts, 1);
    });

    testWidgets('shared PGN text -> game picker -> Save -> board; saved as source "share"', (tester) async {
      final env = TestEnv(book: realBook());
      await env.pump(tester);
      env.intake.push(SharedText(vectorPgn('chesscom_app_share.pgn')));
      await tester.pumpAndSettle();
      expect(find.byType(ImportPreviewScreen), findsOneWidget);
      await tester.tap(find.byKey(const Key('importSave')));
      await tester.pumpAndSettle();
      expect(find.byType(BoardScreen), findsOneWidget);
      final saved = (await env.games.list()).single;
      expect(saved.source, GameSource.share);
      expect(saved.sourceId, isNull);
    });

    testWidgets('a shared file with several games asks which one', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      env.intake.push(SharedFile(bytesOf(vectorPgn('fifty_games.pgn'))));
      await tester.pumpAndSettle();
      expect(find.text(l10n.importChooseGame), findsOneWidget);
      expect(tester.widget<FilledButton>(find.byKey(const Key('importSave'))).onPressed, isNull);
    });

    testWidgets('the configured account names decide the side of a shared game', (tester) async {
      final env = TestEnv(settings: {'lichess_username': 'player_black'});
      await env.pump(tester);
      env.intake.push(SharedText(vectorPgn('lichess_api_export.pgn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('importSave')));
      await tester.pumpAndSettle();
      expect((await env.games.list()).single.userSide, Side.black);
    });

    testWidgets('a shared link says it is not imported; nothing is fetched', (tester) async {
      final lichess = FakeOnlineClient.games([]);
      final env = TestEnv(lichess: lichess);
      await env.pump(tester);
      env.intake.push(const SharedText('https://lichess.org/AbCdEfGh'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.shareLinkNotSupported), findsOneWidget);
      expect(lichess.usernames, isEmpty);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.shareLinkNotSupported), findsNothing);
      expect(await env.games.list(), isEmpty);
    });

    testWidgets('too large, unreadable, no game and a bad PGN each have their message', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      final cases = <(SharedContent, String)>[
        (const SharedTooLarge(), l10n.importErrorTooLarge),
        (const SharedUnreadable(), l10n.shareReadFailed),
        (const SharedText('just words'), l10n.shareNoGame),
        (SharedText(vectorPgn('illegal_move_single.pgn')), l10n.importErrorIllegalMove(1, '14', 'Nxe5')),
      ];
      for (final (content, message) in cases) {
        env.intake.push(content);
        await tester.pumpAndSettle();
        expect(find.text(message), findsOneWidget, reason: message);
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
      }
      expect(await env.games.list(), isEmpty);
    });

    testWidgets('a second share while the first is open shows its own screen on top', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      env.intake.push(SharedText(vectorPgn('lichess_api_export.pgn')));
      await tester.pumpAndSettle();
      env.intake.push(SharedText(vectorPgn('chesscom_app_share.pgn')));
      await tester.pumpAndSettle();
      expect(find.byType(ImportPreviewScreen, skipOffstage: false), findsNWidgets(2));
    });
  });

  group('review fixes', () {
    test('decode: reading and timeout', () {
      expect(ChannelShareIntakeService.decode({'kind': 'reading'}), isA<SharedReading>());
      expect(ChannelShareIntakeService.decode({'kind': 'timeout'}), isA<SharedTimedOut>());
    });

    testWidgets('a slow provider shows Reading..., then the result replaces it', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      env.intake.push(const SharedReading());
      await tester.pump();
      await tester.pump();
      expect(find.text(l10n.shareReading), findsOneWidget);
      env.intake.push(const SharedText('[Event "x"]\n\n1. e4 e5 *'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.shareReading), findsNothing);
      expect(find.byType(ImportPreviewScreen), findsOneWidget);
    });

    testWidgets('a timed-out read has its own message', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      env.intake.push(const SharedReading());
      await tester.pump();
      env.intake.push(const SharedTimedOut());
      await tester.pumpAndSettle();
      expect(find.text(l10n.shareReadTimeout), findsOneWidget);
      expect(find.text(l10n.shareReading), findsNothing);
    });

    testWidgets('one share that throws does not stop the next ones', (tester) async {
      final fake = FakeShareIntake();
      final navigatorKey = GlobalKey<NavigatorState>();
      final seen = <String>[];
      await tester.pumpWidget(ProviderScope(
        overrides: [shareIntakeServiceProvider.overrideWithValue(fake)],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => ShareIntakeHost(
            navigatorKey: navigatorKey,
            decide: (content) async {
              final text = (content as SharedText).text;
              seen.add(text);
              if (text == 'boom') throw StateError('boom');
              return const ShareRefused(ShareProblem.noGame);
            },
            child: child!,
          ),
          home: const Scaffold(),
        ),
      ));
      await tester.pump();
      fake.push(const SharedText('boom'));
      fake.push(const SharedText('after'));
      await tester.pumpAndSettle();
      expect(seen, ['boom', 'after']);
      expect(find.text(l10n.shareNoGame), findsOneWidget);
    });
  });

  group('routes', () {
    test('unknown names build nothing; known ones do', () {
      expect(Routes.onGenerateRoute(const RouteSettings(name: '/content://x/y.pgn')), isNull);
      expect(Routes.onGenerateRoute(const RouteSettings(name: '/nope')), isNull);
      expect(Routes.onGenerateRoute(const RouteSettings(name: Routes.about)), isNotNull);
    });

    testWidgets('pushing an unknown name does not stack a second Library', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      expect(find.byType(LibraryScreen), findsOneWidget);
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(navigator.pushNamed('/content://evil/x'));
      await tester.pumpAndSettle();
      expect(find.byType(LibraryScreen, skipOffstage: false), findsOneWidget);
      expect(navigator.canPop(), isFalse, reason: 'the unknown route removed itself');
    });
  });
}
