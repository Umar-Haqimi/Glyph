import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/bootstrap.dart';
import 'package:glyph/data/db.dart';
import 'package:glyph/data/providers.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/data/sqlite_repositories.dart';
import 'package:glyph/engine/engine_providers.dart';
import 'package:glyph/features/settings/explain_settings.dart';
import 'package:glyph/platform/online_http.dart';
import 'package:glyph/platform/secret_store.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

/// A network client that only counts: any request the app makes at start-up
/// shows here (and is answered with an error, so nothing leaves the test).
class _RecordingClient extends http.BaseClient {
  final requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    throw http.ClientException('no network in tests');
  }
}

/// `dart:io` level: every `HttpClient` that gets created or used is counted,
/// so a request that bypasses the injected clients above is caught too.
class _CountingHttpOverrides extends HttpOverrides {
  int clientsCreated = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clientsCreated++;
    throw const SocketException('no network in tests');
  }
}

/// M8 startup work: a cold start with games in the library does only what the
/// first screen needs. The test goes through [Bootstrap] (the real start-up
/// path: database open, appearance read, `ProviderScope`), then checks that no
/// engine is created (a Stockfish process costs memory and a second or so of
/// start-up), the openings asset (700 KB) is not decoded, and no network
/// request goes out (SPEC 6: the app talks to the network only when asked).
void main() {
  testWidgets('starting the app through Bootstrap creates no engine, decodes no opening book and makes no HTTP request', (tester) async {
    var engines = 0;
    var bookReads = 0;
    final recorder = _RecordingClient();
    final io = _CountingHttpOverrides();
    final exports = FakeSharedExports();
    final db = Db.inMemory();
    final games = SqliteGameRepository(db);
    final analyses = SqliteAnalysisRepository(db);
    for (final (white, black, status, plies, at) in [
      ('A', 'B', AnalysisStatus.completed, 41, 1),
      ('C', 'D', AnalysisStatus.paused, 5, 2),
    ]) {
      final saved = await games.save(NewGame(
        source: GameSource.paste,
        pgn: '1. e4 *',
        white: white,
        black: black,
        result: '1-0',
        plyCount: 40,
        importedAt: at,
      ));
      await analyses.upsert(AnalysisRecord(
        gameId: saved.id,
        engine: 'Stockfish',
        depth: 16,
        multipv: 2,
        status: status,
        completedPlies: plies,
        updatedAt: 1,
      ));
    }
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await HttpOverrides.runZoned(
      () async {
        await tester.pumpWidget(Bootstrap(
          databasePath: () async => ':memory:',
          open: (_) async => db,
          secretStore: InMemorySecretStore(),
          sharedExports: exports,
          extraOverrides: [
            engineDriverFactoryProvider.overrideWithValue(() async {
              engines++;
              return FakeEngineDriver.permissive();
            }),
            openingBookProvider.overrideWith((ref) {
              bookReads++;
              return OpeningBook(const {});
            }),
            httpClientFactoryProvider.overrideWithValue(() => recorder),
            lichessClientProvider.overrideWithValue(LichessClient(httpClient: () => recorder, userAgent: 'test')),
            chessComClientProvider.overrideWithValue(ChessComClient(httpClient: () => recorder, userAgent: 'test', cache: InMemoryOnlineCache())),
          ],
        ));
        await tester.pumpAndSettle();
      },
      createHttpClient: io.createHttpClient,
    );

    // The real first screen is up: the Bootstrap path got there.
    expect(find.byType(GlyphApp), findsOneWidget);
    expect(find.textContaining(' – '), findsNWidgets(2), reason: 'the library lists the two seeded games');
    expect(engines, 0, reason: 'the engine starts when a board opens an unanalysed game, not at launch');
    expect(bookReads, 0, reason: 'the opening book is decoded on first use');
    expect(recorder.requests, isEmpty, reason: 'no request through the injected clients');
    expect(io.clientsCreated, 0, reason: 'no dart:io HttpClient was even created');
    expect(exports.clears, 1, reason: 'stale exported PGN files are removed at start');
  });
}
