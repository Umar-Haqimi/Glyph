import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/features/board/board_screen.dart';
import 'package:glyph/l10n/app_localizations.dart';
import 'package:glyph/theme/app_theme.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import 'test_app.dart';

/// A short Italian game with a castling move (ply 7) and `[%clk]` comments:
/// 1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5 4.O-O Nf6.
const reviewPgn = '[White "Alice"]\n[Black "Bob"]\n[TimeControl "300+0"]\n\n'
    '1. e4 {[%clk 0:04:58.5]} e5 {[%clk 0:04:57.2]} 2. Nf3 {[%clk 0:04:55]} Nc6 {[%clk 0:04:50.1]} '
    '3. Bc4 {[%clk 0:04:40]} Bc5 {[%clk 0:04:30]} 4. O-O {[%clk 0:04:20.8]} Nf6 {[%clk 0:04:10]} *';

/// Engine lines (White POV, dartchess UCI: castling is king-takes-rook) of
/// the 9 positions of [reviewPgn]: (rank 1 pv, rank 1 cp, rank 2 pv, rank 2 cp).
const reviewLines = <int, (String, int, String, int)>{
  0: ('e2e4 e7e5 g1f3', 30, 'd2d4 d7d5', 25),
  1: ('e7e5 g1f3', 28, 'c7c5 g1f3', 35),
  2: ('g1f3 b8c6', 30, 'f1c4 g8f6', 27),
  3: ('b8c6 f1b5', 25, 'g8f6 b1c3', 30),
  4: ('f1b5 g8f6', 28, 'f1c4 g8f6', 25),
  5: ('g8f6 d2d3', 22, 'f8c5 c2c3', 25),
  6: ('e1h1 g8f6 d2d3', 30, 'c2c3 g8f6', 28),
  7: ('g8f6 d2d3', 28, 'd7d6 d2d3', 33),
  8: ('d2d3 d7d6', 30, 'b1c3 d7d6', 25),
};

/// Stored labels for the 8 plies: best, excellent, great, inaccuracy,
/// mistake, blunder, brilliant, miss.
const reviewLabels = <int, (MoveLabel, String?)>{
  1: (MoveLabel.best, 'e2e4'),
  2: (MoveLabel.excellent, 'e7e5'),
  3: (MoveLabel.great, 'g1f3'),
  4: (MoveLabel.inaccuracy, 'g8f6'),
  5: (MoveLabel.mistake, 'f1b5'),
  6: (MoveLabel.blunder, 'g8f6'),
  7: (MoveLabel.brilliant, 'e1h1'),
  8: (MoveLabel.miss, 'd7d6'),
};

Future<int> seedReview(
  TestEnv env, {
  Side? userSide,
  AnalysisStatus status = AnalysisStatus.completed,
  bool labels = true,
  int positions = 9,
  Map<int, int> cpOverride = const {},
  Map<int, int> mateOverride = const {},
  double? whiteAccuracy = 87.4,
  double? blackAccuracy = 62.5,
  String pgn = reviewPgn,
  String? eco = 'C50',
  String? openingName = 'Italian Game',
}) async {
  final saved = await env.games.save(NewGame(
    source: GameSource.paste,
    pgn: pgn,
    white: 'Alice',
    black: 'Bob',
    whiteElo: 1500,
    blackElo: 1400,
    timeControl: '300+0',
    result: '*',
    plyCount: 8,
    importedAt: 1,
    userSide: userSide,
    eco: eco,
    openingName: openingName,
  ));
  final id = saved.id;
  await env.analyses.upsert(AnalysisRecord(
    gameId: id,
    engine: 'Stockfish 19 light',
    depth: 16,
    multipv: 2,
    status: status,
    completedPlies: positions,
    whiteAccuracy: status == AnalysisStatus.completed ? whiteAccuracy : null,
    blackAccuracy: status == AnalysisStatus.completed ? blackAccuracy : null,
    updatedAt: 1,
  ));
  for (var ply = 0; ply < positions; ply++) {
    final l = reviewLines[ply]!;
    PositionLineRecord row(int rank, String pv, int cp) => PositionLineRecord(
          gameId: id,
          ply: ply,
          rank: rank,
          scoreCp: rank == 1 && mateOverride.containsKey(ply) ? null : (rank == 1 ? (cpOverride[ply] ?? cp) : cp),
          scoreMate: rank == 1 ? mateOverride[ply] : null,
          depth: 16,
          pvUci: pv,
        );
    await env.analyses.savePosition(id, ply, [row(1, l.$1, l.$2), row(2, l.$3, l.$4)],
        completedPlies: ply + 1, updatedAt: 1);
  }
  if (labels) {
    await env.analyses.putLabels(id, [
      for (final e in reviewLabels.entries)
        MoveLabelRecord(
          gameId: id,
          ply: e.key,
          label: e.value.$1,
          epLoss: 0.03,
          winBefore: 60,
          winAfter: 50,
          bestUci: e.value.$2,
        ),
    ]);
  }
  return id;
}

/// Pumps the board of [id] in a tall window (the screen scrolls). The move
/// list is lazy: pass a large [width] to have every chip built.
Future<ProviderContainer> pumpReview(
  WidgetTester tester,
  TestEnv env,
  int id, {
  int initialPly = 0,
  ProviderContainer? container,
  Brightness brightness = Brightness.light,
  double width = 800,
}) async {
  tester.view.physicalSize = Size(width, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  if (container == null) {
    container = ProviderContainer(overrides: env.overrides);
    addTearDown(container.dispose);
  }
  final themes = buildThemes();
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: themes.light,
      darkTheme: themes.dark,
      themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: BoardScreen(gameId: id, initialPly: initialPly),
    ),
  ));
  await settleBoard(tester);
  return container;
}

Future<void> settleBoard(WidgetTester tester, {int rounds = 30}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
