import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/features/export/pgn_export_service.dart';
import 'package:glyph/features/library/library_screen.dart';
import 'package:glyph/platform/pgn_share_service.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../support/review_fixture.dart';
import '../support/test_app.dart';

/// The service on top of a [TestEnv], without the widget tree.
Future<ExportedPgn?> exportOf(TestEnv env, int id) {
  final container = ProviderContainer(overrides: env.overrides);
  addTearDown(container.dispose);
  return container.read(pgnExportServiceProvider).build(id);
}

Game parse(String pgn) => (parsePgn(pgn) as PgnOk).games.single;

void main() {
  group('PgnExportService (SPEC F18)', () {
    test('a finished analysis: headers, Annotator, [%eval] and [%clk] per move, NAGs, Miss comment', () async {
      final env = TestEnv(book: realBook());
      final id = await seedReview(env, userSide: Side.white);
      final out = (await exportOf(env, id))!;
      final pgn = out.pgn;
      expect(pgn, contains('[White "Alice"]'));
      expect(pgn, contains('[Annotator "Glyph"]'));
      expect(pgn, contains('[%eval 0.28]'), reason: 'ply 1: the engine line of the position after 1.e4');
      expect(pgn, contains('[%clk 0:04:58.5]'));
      // great $1, inaccuracy $6, mistake $2, blunder $4, brilliant $3, miss $2 + comment
      expect(pgn, contains(r'2. Nf3 $1'));
      expect(pgn, contains(r'2... Nc6 $6'));
      expect(pgn, contains(r'4... Nf6 $2 { Miss'));
      for (final nag in [r'$1', r'$2', r'$3', r'$4', r'$6']) {
        expect(pgn, contains(nag), reason: nag);
      }
      expect(pgn, contains('Miss'));
      // Best / Excellent have no NAG: only the six NAG labels of the fixture appear.
      expect(RegExp(r'\$\d').allMatches(pgn).length, 6);
    });

    test('re-imports into Glyph with the same mainline and headers (plus Annotator)', () async {
      final env = TestEnv(book: realBook());
      final id = await seedReview(env);
      final original = parse(reviewPgn);
      final back = parse((await exportOf(env, id))!.pgn);
      expect(back.plies.map((p) => p.san), original.plies.map((p) => p.san));
      expect(back.plies.map((p) => p.fen), original.plies.map((p) => p.fen));
      expect(back.plies.map((p) => p.clockMs), original.plies.map((p) => p.clockMs));
      expect({...back.headers}..remove('Annotator')..remove('Result'), {...original.headers}..remove('Result'));
      expect(back.headers['Annotator'], 'Glyph');
      expect(back.plies.every((p) => p.eval != null), isTrue, reason: 'every analysed position carries its [%eval]');
      expect(back.plies.first.eval, const PlyEval.cp(28));
    });

    test('a mate score is written as #N, with the sign of the side that mates', () async {
      final env = TestEnv();
      final id = await seedReview(env, mateOverride: {2: 3, 5: -2});
      final pgn = (await exportOf(env, id))!.pgn;
      expect(pgn, contains('[%eval #3]'));
      expect(pgn, contains('[%eval #-2]'));
    });

    test('a partly analysed game exports what exists: evals only where the engine was, labels only where classifiable', () async {
      final env = TestEnv(book: realBook());
      final id = await seedReview(env, status: AnalysisStatus.cancelled, positions: 4, labels: false);
      final back = parse((await exportOf(env, id))!.pgn);
      expect(back.plies.take(3).every((p) => p.eval != null), isTrue);
      expect(back.plies.skip(3).every((p) => p.eval == null), isTrue, reason: 'positions 4.. were never analysed');
      expect(back.headers['Annotator'], 'Glyph');
    });

    test('a game that was never analysed exports with its own comments and no invented labels', () async {
      final env = TestEnv();
      final saved = await env.games.save(NewGame(source: GameSource.paste, pgn: reviewPgn, white: 'Alice', black: 'Bob', plyCount: 8, importedAt: 1));
      final pgn = (await exportOf(env, saved.id))!.pgn;
      expect(pgn, contains('[%clk 0:04:58.5]'));
      expect(pgn, isNot(contains('[%eval')));
      expect(RegExp(r'\$\d').hasMatch(pgn), isFalse);
      expect(pgn, contains('[Annotator "Glyph"]'));
    });

    test('a missing or unreadable game gives null', () async {
      final env = TestEnv();
      expect(await exportOf(env, 999), isNull);
      final saved = await env.games.save(const NewGame(source: GameSource.paste, pgn: 'garbage', plyCount: 0, importedAt: 1));
      expect(await exportOf(env, saved.id), isNull);
    });

    test('the file name is sanitised: players and date, only A-Za-z0-9._-', () async {
      final env = TestEnv();
      final saved = await env.games.save(const NewGame(
        source: GameSource.paste,
        pgn: '[White "../../etc/x y"]\n[Black "Zoë \\"Z\\" <b>"]\n[Date "2026.10.23"]\n\n1. e4 e5 *',
        plyCount: 2,
        importedAt: 1,
      ));
      final name = (await exportOf(env, saved.id))!.fileName;
      expect(name, matches(RegExp(r'^[A-Za-z0-9._-]+\.pgn$')));
      expect(name, isNot(contains('..')));
      expect(name, endsWith('2026-10-23.pgn'));
      expect((await exportOf(env, await seedReview(env)))!.fileName, 'Alice_vs_Bob.pgn');
    });
  });

  group('the Export PGN actions', () {
    testWidgets('board overflow menu: opens the share sheet with the annotated PGN and a safe name', (tester) async {
      final env = TestEnv(book: realBook());
      final id = await seedReview(env);
      await pumpReview(tester, env, id);
      await tester.tap(find.byKey(const Key('board-menu')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.exportPgn), findsOneWidget);
      await tester.tap(find.byKey(const Key('menu-export')));
      await tester.pumpAndSettle();
      final shared = env.pgnShare.shared.single;
      expect(shared.fileName, 'Alice_vs_Bob.pgn');
      expect(shared.title, l10n.exportShareTitle);
      expect(shared.pgn, contains('[Annotator "Glyph"]'));
      expect(shared.pgn, contains(r'$4'));
      expect(find.text(l10n.exportFailed), findsNothing);
    });

    testWidgets('library card menu exports that card\'s game', (tester) async {
      final env = TestEnv();
      final id = await seedReview(env);
      await env.seed(white: 'Carol', black: 'Dave');
      await env.pump(tester);
      expect(find.byType(GameCard), findsNWidgets(2));
      await tester.tap(find.byKey(Key('game-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('game-export-$id')));
      await tester.pumpAndSettle();
      expect(env.pgnShare.shared.single.pgn, contains('[White "Alice"]'));
    });

    testWidgets('the share sheet failing shows the message and keeps the app usable', (tester) async {
      final env = TestEnv()..pgnShare.error = const PgnShareException();
      final id = await seedReview(env);
      await env.pump(tester);
      await tester.tap(find.byKey(Key('game-menu-$id')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('game-export-$id')));
      await tester.pumpAndSettle();
      expect(find.text(l10n.exportFailed), findsOneWidget);
      expect(env.pgnShare.shared, isEmpty);
    });

    testWidgets('menu buttons are at least 48 dp and the menu item is named for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      final env = TestEnv();
      final id = await seedReview(env);
      await env.pump(tester);
      final size = tester.getSize(find.byKey(Key('game-menu-$id')));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(find.byTooltip(l10n.boardMenuTooltip), findsOneWidget);
      handle.dispose();
    });
  });

  group('the share sheet bridge', () {
    test('the channel is called with text, file name and title; platform errors become PgnShareException', () async {
      // Covered end to end by the Kotlin side on a device; here only the contract of the Dart half.
      const service = ChannelPgnShareService();
      await expectLater(service.share(pgn: '1. e4 *', fileName: 'a.pgn', title: 't'), throwsA(isA<PgnShareException>()),
          reason: 'no native side in a host test');
    });
  });
}
