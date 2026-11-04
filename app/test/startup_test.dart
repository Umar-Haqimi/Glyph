import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph_core/testing.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

/// M8 startup work: a cold start with games in the library does only what the
/// first screen needs. No engine is created (a Stockfish process costs memory
/// and a second or so of start-up), the openings asset (700 KB) is not decoded,
/// and no request goes out.
void main() {
  testWidgets('starting the app creates no engine and decodes no opening book', (tester) async {
    var engines = 0;
    final env = TestEnv(driverFactory: () async {
      engines++;
      return FakeEngineDriver.permissive();
    });
    await env.seed(white: 'A', black: 'B', status: AnalysisStatus.completed, completedPlies: 41);
    await env.seed(white: 'C', black: 'D', status: AnalysisStatus.paused, completedPlies: 5, importedAt: 2);
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: env.overrides,
      child: const GlyphApp(),
    ));
    await tester.pumpAndSettle();
    expect(engines, 0, reason: 'the engine starts when a board opens an unanalysed game, not at launch');
    expect(env.bookReads, 0, reason: 'the opening book is decoded on first use');
  });

}
