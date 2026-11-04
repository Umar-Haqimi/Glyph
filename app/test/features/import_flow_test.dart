import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/features/library/library_screen.dart';
import 'package:glyph/platform/file_picker_service.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

Future<void> openPaste(WidgetTester tester) async {
  await tester.tap(find.text(l10n.libraryImportFab));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.importPastePgn));
  await tester.pumpAndSettle();
}

Future<void> paste(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const Key('pgnField')), text);
  await tester.pumpAndSettle();
}

String summary(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('importSummary'))).data!;
String error(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('importError'))).data!;
bool saveEnabled(WidgetTester tester) => tester.widget<FilledButton>(find.byKey(const Key('importSave'))).onPressed != null;

void main() {
  group('paste flow', () {
    testWidgets('empty input: no validation message, Save disabled', (tester) async {
      await TestEnv().pump(tester);
      await openPaste(tester);
      expect(find.byKey(const Key('importSummary')), findsNothing);
      expect(find.byKey(const Key('importError')), findsNothing);
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('one game: "1 game found", save, open the board, game in the library', (tester) async {
      final env = TestEnv(book: realBook());
      await env.pump(tester);
      await openPaste(tester);
      await paste(tester, vectorPgn('lichess_api_export.pgn'));
      expect(summary(tester), '1 game found');
      expect(summary(tester), l10n.importGamesFound(1));
      expect(saveEnabled(tester), isTrue);
      expect(find.text(l10n.importChooseGame), findsNothing, reason: 'no picker for a single game');

      await tester.tap(find.byKey(const Key('importSave')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.boardTitleGame('player_white', 'player_black')), findsOneWidget);

      final saved = (await env.games.list()).single;
      expect(saved.source, GameSource.paste);
      expect(saved.plyCount, 31);
      expect(saved.result, '1-0');
      expect(saved.whiteElo, 3203);
      expect(saved.date, '2023.07.01');
      expect(saved.startFen, isNull);
      expect(saved.eco, 'A01');
      expect(saved.pgn, contains('1. b3'));

      // Back to the library: the new card is listed.
      tester.state<NavigatorState>(find.byType(Navigator)).pop();
      await tester.pumpAndSettle();
      expect(find.byType(GameCard), findsOneWidget);
      expect(find.textContaining('player_white'), findsOneWidget);
    });

    testWidgets('opening is named from the book, user side from the configured name', (tester) async {
      final env = TestEnv(book: realBook(), settings: {'lichess_username': 'PLAYER_black'});
      await env.pump(tester);
      await openPaste(tester);
      await paste(tester, '[Site "https://lichess.org/abc"]\n[White "someone"]\n[Black "player_Black"]\n\n1. e4 e5 2. Nf3 Nc6 3. Bb5 a6 1-0');
      await tester.tap(find.byKey(const Key('importSave')));
      await tester.pumpAndSettle();
      final saved = (await env.games.list()).single;
      expect(saved.eco, matches(RegExp(r'^C[67]\d$')));
      expect(saved.openingName, startsWith('Ruy Lopez'));
      expect(saved.userSide, Side.black);
    });

    testWidgets('several games: count, picker, Save only after choosing', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      await openPaste(tester);
      await paste(tester, vectorPgn('no_blank_lines.pgn'));
      expect(summary(tester), '3 games found');
      expect(find.text(l10n.importChooseGame), findsOneWidget);
      expect(find.byKey(const ValueKey('game-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('game-2')), findsOneWidget);
      expect(saveEnabled(tester), isFalse);

      await tester.tap(find.byKey(const ValueKey('game-1')));
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
      await tester.tap(find.byKey(const Key('importSave')));
      await tester.pumpAndSettle();

      final saved = (await env.games.list()).single;
      final expected = parsePgn(vectorPgn('no_blank_lines.pgn')).games[1];
      expect(saved.white, expected.white);
      expect(saved.black, expected.black);
      expect(saved.plyCount, expected.plyCount);
      expect(find.text(l10n.boardTitleGame(expected.white!, expected.black!)), findsOneWidget);
    });

    testWidgets('live validation updates as the text changes', (tester) async {
      await TestEnv().pump(tester);
      await openPaste(tester);
      await paste(tester, '1. e4 e5 *');
      expect(summary(tester), '1 game found');
      await paste(tester, '1. e4 e5 *\n\n1. d4 d5 *');
      expect(summary(tester), '2 games found');
      await paste(tester, 'not a pgn at all');
      expect(error(tester), l10n.importErrorNoGames);
      expect(saveEnabled(tester), isFalse);
      await paste(tester, '');
      expect(find.byKey(const Key('importError')), findsNothing);
    });

    testWidgets('illegal move names game, move and SAN', (tester) async {
      await TestEnv().pump(tester);
      await openPaste(tester);
      await paste(tester, vectorPgn('illegal_move_single.pgn'));
      expect(error(tester), 'Game 1, move 14 (Nxe5): illegal move.');
      expect(saveEnabled(tester), isFalse);
    });

    testWidgets('illegal move in game 2 of a file: the other games remain importable', (tester) async {
      final env = TestEnv();
      await env.pump(tester);
      await openPaste(tester);
      await paste(tester, vectorPgn('illegal_move_in_multi.pgn'));
      expect(summary(tester), '2 games found, 1 skipped');
      expect(find.text('Game 2, move 14 (Nxe5): illegal move.'), findsOneWidget);
      // Games 1 and 3 are listed under their position in the file.
      expect(find.byKey(const ValueKey('game-1')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('game-2')));
      await tester.pumpAndSettle();
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('crazyhouse is rejected', (tester) async {
      await TestEnv().pump(tester);
      await openPaste(tester);
      await paste(tester, vectorPgn('crazyhouse.pgn'));
      expect(error(tester), "Crazyhouse games aren't supported.");
    });

    testWidgets('a Black-first illegal move after a FEN start reads "14..."', (tester) async {
      await TestEnv().pump(tester);
      await openPaste(tester);
      await paste(tester, '[FEN "rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq - 0 7"]\n[SetUp "1"]\n\n7... e5 8. Nf3 Ke6 *');
      expect(error(tester), 'Game 1, move 8... (Ke6): illegal move.');
    });

    testWidgets('Chess960 game keeps its start FEN', (tester) async {
      final env = TestEnv(book: realBook());
      await env.pump(tester);
      await openPaste(tester);
      await paste(tester, vectorPgn('chess960_fen.pgn'));
      await tester.tap(find.byKey(const Key('importSave')));
      await tester.pumpAndSettle();
      final saved = (await env.games.list()).single;
      expect(saved.variant, GameVariant.chess960);
      expect(saved.startFen, 'brnkqbnr/pppppppp/8/8/8/8/PPPPPPPP/BRNKQBNR w KQkq - 0 1');
      expect(saved.openingName, isNull, reason: 'no opening book for Chess960');
    });
  });

  group('file flow', () {
    testWidgets('pick a file with several games, choose one, save', (tester) async {
      final env = TestEnv(picker: FakeFilePicker(PickedPgn.bytes('games.pgn', bytesOf(vectorPgn('fifty_games.pgn')))));
      await env.pump(tester);
      await tester.tap(find.text(l10n.libraryImportFab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.importOpenFile));
      await tester.pumpAndSettle();

      expect(summary(tester), '50 games found');
      expect(saveEnabled(tester), isFalse);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('game-7')), 200, scrollable: find.byType(Scrollable).first);
      await tester.tap(find.byKey(const ValueKey('game-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('importSave')));
      await tester.pumpAndSettle();

      final saved = (await env.games.list()).single;
      expect(saved.source, GameSource.file);
      final expected = parsePgn(vectorPgn('fifty_games.pgn')).games[7];
      expect(saved.white, expected.white);
      expect(saved.plyCount, expected.plyCount);
    });

    testWidgets('a single-game file needs no picking', (tester) async {
      final env = TestEnv(picker: FakeFilePicker(PickedPgn.bytes('g.pgn', bytesOf(vectorPgn('chesscom_download_clk.pgn')))));
      await env.pump(tester);
      await tester.tap(find.text(l10n.libraryImportFab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.importOpenFile));
      await tester.pumpAndSettle();
      expect(summary(tester), '1 game found');
      expect(saveEnabled(tester), isTrue);
    });

    testWidgets('file over 2 MB: clear message, nothing imported', (tester) async {
      final env = TestEnv(picker: FakeFilePicker(const PickedPgn.tooLarge('huge.pgn')));
      await env.pump(tester);
      await tester.tap(find.text(l10n.libraryImportFab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.importOpenFile));
      await tester.pumpAndSettle();
      expect(find.text('This file is larger than 2 MB.'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.libraryEmptyTitle), findsOneWidget);
      expect(await env.games.list(), isEmpty);
    });

    testWidgets('unreadable PGN in a file shows the error', (tester) async {
      final env = TestEnv(picker: FakeFilePicker(PickedPgn.bytes('bad.pgn', bytesOf(vectorPgn('illegal_move_single.pgn')))));
      await env.pump(tester);
      await tester.tap(find.text(l10n.libraryImportFab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.importOpenFile));
      await tester.pumpAndSettle();
      expect(find.text('Game 1, move 14 (Nxe5): illegal move.'), findsOneWidget);
    });

    testWidgets('cancelling the picker keeps the sheet open; a picker error is reported', (tester) async {
      final picker = FakeFilePicker(null);
      final env = TestEnv(picker: picker);
      await env.pump(tester);
      await tester.tap(find.text(l10n.libraryImportFab));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.importOpenFile));
      await tester.pumpAndSettle();
      expect(picker.calls, 1);
      expect(find.text(l10n.importOpenFile), findsOneWidget, reason: 'sheet still open');

      picker.error = StateError('no picker');
      await tester.tap(find.text(l10n.importOpenFile));
      await tester.pumpAndSettle();
      expect(find.text(l10n.importFileOpenFailed), findsOneWidget);
    });

    testWidgets('lichess and chess.com rows are not available yet', (tester) async {
      await TestEnv().pump(tester);
      await tester.tap(find.text(l10n.libraryImportFab));
      await tester.pumpAndSettle();
      expect(find.text(l10n.importComingSoon), findsNWidgets(2));
    });
  });
}
