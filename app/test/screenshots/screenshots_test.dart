// Generates the README screenshots in docs/screenshots/.
//
// NOT part of the normal test run: the `screenshots` tag is skipped in
// app/dart_test.yaml. Run it on purpose from the app/ directory:
//
//   flutter test --run-skipped --tags screenshots test/screenshots
//
// What is real and what is not:
//   * The UI is the real app (GlyphApp / BoardScreen / ReportScreen / ...)
//     rendered by Flutter's test renderer with the real Roboto and Material
//     Icons fonts and the real chessground piece images.
//   * The engine lines are RECORDED Stockfish output (the UCI transcripts under
//     packages/glyph_core/test/vectors/uci_transcripts), run through the real
//     analysis pipeline, classifier and accuracy code, with the real opening book.
//   * The Explain and summary texts are CANNED strings streamed by a scripted
//     fake LLM client (test/support/fake_llm.dart). They are NOT the output of a
//     language model, and the sheets say "fake-client" as the model name.
//   * Window: 412 x 892 logical pixels at 2.625 (1080 x 2340 pixels), Pixel-like.
@Tags(['screenshots'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/engine/engine_providers.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/testing.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_llm.dart';
import '../support/test_app.dart';

const _fonts = '/opt/flutter/bin/cache/artifacts/material_fonts';
const _transcripts = '../packages/glyph_core/test/vectors/uci_transcripts';
const _outDir = '../docs/screenshots';

Future<void> _loadFont(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

String _flutterRoot() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && Directory('$root/bin/cache/artifacts/material_fonts').existsSync()) return root;
  return '/opt/flutter';
}

class _Sample {
  const _Sample(this.transcript, this.white, this.black, this.whiteElo, this.blackElo, this.date, this.source, this.userSide, this.result);
  final String transcript;
  final String white;
  final String black;
  final int whiteElo;
  final int blackElo;
  final String date;
  final GameSource source;
  final Side userSide;

  /// The real result of the recorded moves: 1-0 for the Opera game (it ends in
  /// Rd8#); the other three are recorded opening fragments (12 to 16 plies)
  /// that end mid-game, so their result is "*".
  final String result;
}

const _samples = [
  _Sample('blunder_white', 'glyph_demo', 'rook_roller', 1512, 1498, '2026.10.28', GameSource.lichess, Side.white, '*'),
  _Sample('italian_castle', 'knight_errant', 'glyph_demo', 1420, 1455, '2026.10.26', GameSource.chesscom, Side.black, '*'),
  _Sample('queens_gambit', 'glyph_demo', 'pawn_storm', 1533, 1561, '2026.10.21', GameSource.paste, Side.white, '*'),
  _Sample('mate_opera', 'Paul Morphy', 'Duke of Brunswick & Count Isouard', 0, 0, '1858.??.??', GameSource.paste, Side.white, '1-0'),
];

Future<void> _settle(WidgetTester tester, {int rounds = 12}) async {
  for (var i = 0; i < rounds; i++) {
    // Real time passes here so asset images decode and the engine fake runs.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 40));
  }
}

Future<void> _shot(WidgetTester tester, GlobalKey boundaryKey, String name) async {
  await _settle(tester, rounds: 8);
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2.625);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    Directory(_outDir).createSync(recursive: true);
    File('$_outDir/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('wrote $_outDir/$name.png ${image.width}x${image.height}');
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('README screenshots', timeout: const Timeout(Duration(minutes: 5)), (tester) async {
    WidgetsApp.debugAllowBannerOverride = false; // no "DEBUG" ribbon in the images
    addTearDown(() => WidgetsApp.debugAllowBannerOverride = true);
    // The test binding turns shadows off; the README images should show the real elevation.
    final shadowsWereDisabled = debugDisableShadows;
    debugDisableShadows = false;
    final root = _flutterRoot();
    await tester.runAsync(() async {
      await _loadFont('Roboto', [
        for (final w in ['Regular', 'Medium', 'Bold', 'Italic', 'Light']) '$root/bin/cache/artifacts/material_fonts/Roboto-$w.ttf',
      ]);
      await _loadFont('MaterialIcons', ['$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf']);
    });
    expect(Directory(_fonts).existsSync() || Directory('$root/bin/cache/artifacts/material_fonts').existsSync(), isTrue);

    final book = realBook();
    final transcript = Transcript();
    for (final s in _samples) {
      transcript.addAll(Transcript.parse(File('$_transcripts/${s.transcript}.txt').readAsStringSync()));
    }
    final fake = FakeLlm();
    final env = TestEnv(
      book: book,
      driverFactory: () async => FakeEngineDriver(transcript),
      // Same shape the app uses once a model is set up; the name says what it is.
      settings: {'llm_provider': 'openai', 'llm_base_url': 'https://api.openai.com/v1', 'llm_model': 'fake-client'},
      secrets: {'openai': 'sk-not-a-real-key-0000'},
      llm: fake.client,
    );
    final container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);

    // 1. Seed four games and run the REAL analysis + review over recorded engine output.
    final games = parseTranscriptGames(File('$_transcripts/games.json').readAsStringSync());
    final ids = <String, int>{};
    var importedAt = 100;
    for (final s in _samples) {
      final tg = games.firstWhere((g) => g.name == s.transcript);
      final pgn = '[Event "Glyph sample"]\n[Date "${s.date}"]\n[White "${s.white}"]\n[Black "${s.black}"]\n'
          '${s.whiteElo > 0 ? '[WhiteElo "${s.whiteElo}"]\n[BlackElo "${s.blackElo}"]\n' : ''}'
          '[Result "${s.result}"]\n\n${tg.toPgn()}';
      final game = parsePgn(pgn).games.first;
      final saved = await env.games.save(NewGame.fromGame(
        game,
        source: s.source,
        sourceId: s.source == GameSource.paste ? null : 'sample-${s.transcript}',
        importedAt: importedAt++,
        book: book.annotate(game),
        userSide: s.userSide,
      ));
      ids[s.transcript] = saved.id;
      await tester.runAsync(() async {
        final service = container.read(engineServiceProvider);
        final done = service.states.firstWhere((st) => st is AnalysisCompleted && st.gameId == saved.id);
        service.enqueue(AnalysisRequest.fromGame(saved.id, game, depth: 16));
        await done.timeout(const Duration(seconds: 60));
        await container.read(reviewServiceProvider).classify(saved.id);
      });
    }

    // 2. Pump the real app in a phone-sized window.
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: RepaintBoundary(key: boundaryKey, child: const GlyphApp()),
    ));
    await _settle(tester, rounds: 10);

    await _shot(tester, boundaryKey, 'library');

    // Board: the Opera game after 16. Qb8+ (ply 31 of 33).
    final opera = ids['mate_opera']!;
    await tester.tap(find.byKey(ValueKey('game-$opera')));
    await _settle(tester, rounds: 10);
    await tester.tap(find.byKey(const Key('nav-last')));
    await _settle(tester, rounds: 4);
    await tester.tap(find.byKey(const Key('nav-back')));
    await _settle(tester, rounds: 3);
    await tester.tap(find.byKey(const Key('nav-back')));
    await _settle(tester, rounds: 6);
    await _shot(tester, boundaryKey, 'board');

    // Explain sheet with a canned stream from the fake client.
    await tester.ensureVisible(find.byKey(const Key('explain-button')));
    await _settle(tester, rounds: 3);
    await tester.tap(find.byKey(const Key('explain-button')));
    await _settle(tester, rounds: 12);
    fake.send('Qb8+ is a queen sacrifice that works because every reply is forced. ');
    await _settle(tester, rounds: 3);
    fake.send('After Nxb8 the knight is pulled away from d7 and the rook on d1 delivers mate on d8. ');
    fake.send('The engine line shows Rd8# at once, so nothing else was needed. [Canned demo text from a scripted fake client, not a real model.]');
    await _settle(tester, rounds: 3);
    await fake.finish();
    await _settle(tester, rounds: 12);
    await _shot(tester, boundaryKey, 'explain');
    await tester.tapAt(const Offset(10, 10)); // the barrier closes the sheet
    await _settle(tester, rounds: 25);

    // Report with a canned summary.
    await tester.tap(find.byKey(const Key('open-report')));
    await _settle(tester, rounds: 14);
    final summaryButton = find.byKey(const Key('summary-button'));
    await tester.scrollUntilVisible(summaryButton, 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(summaryButton);
    await _settle(tester, rounds: 10);
    fake.send('A classic: you developed fast, kept the pressure up, and finished with the famous queen sacrifice. ');
    fake.send('[Canned demo text from a scripted fake client, not a real model.]');
    await _settle(tester, rounds: 3);
    await fake.finish();
    await _settle(tester, rounds: 12);
    // The report shot shows the summary card (scroll it into view).
    await tester.ensureVisible(find.byKey(const Key('summary-card')));
    await _settle(tester, rounds: 6);
    await _shot(tester, boundaryKey, 'report');

    // Settings, from the library.
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.popUntil((r) => r.isFirst);
    await _settle(tester, rounds: 12);
    await tester.tap(find.byTooltip(l10n.settingsTooltip));
    await _settle(tester, rounds: 12);
    await _shot(tester, boundaryKey, 'settings');
    debugDisableShadows = shadowsWereDisabled; // the binding checks this before tearDown runs
  });
}
