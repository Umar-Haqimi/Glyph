import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/data/in_memory.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/data/providers.dart';
import 'package:glyph/engine/engine_providers.dart';
import 'package:glyph/l10n/app_localizations_en.dart';
import 'package:glyph/platform/file_picker_service.dart';
import 'package:glyph_core/glyph_core.dart';

final l10n = AppLocalizationsEn();

class FakeFilePicker implements FilePickerService {
  FakeFilePicker(this.result);

  PickedPgn? result;
  Object? error;
  int calls = 0;

  @override
  Future<PickedPgn?> pickPgn() async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

class TestEnv {
  TestEnv({
    Map<String, String>? settings,
    FilePickerService? picker,
    OpeningBook? book,
    EngineDriverFactory? driverFactory,
  })
      : store = InMemoryStore(),
        settings = InMemorySettingsRepository(settings),
        picker = picker ?? FakeFilePicker(null),
        book = book ?? OpeningBook(const {}),
        driverFactory = driverFactory ?? (() async => FakeEngineDriver.permissive()) {
    games = InMemoryGameRepository(store);
    analyses = InMemoryAnalysisRepository(store);
  }

  final InMemoryStore store;
  late final InMemoryGameRepository games;
  late final InMemoryAnalysisRepository analyses;
  final InMemorySettingsRepository settings;
  final FilePickerService picker;
  final OpeningBook book;

  /// Creates the engine of the app under test (default: a fake that answers
  /// every search with a trivial line).
  final EngineDriverFactory driverFactory;
  int clock = 1000000;

  List<Override> get overrides => [
        gameRepositoryProvider.overrideWithValue(games),
        analysisRepositoryProvider.overrideWithValue(analyses),
        settingsRepositoryProvider.overrideWithValue(settings),
        filePickerServiceProvider.overrideWithValue(picker),
        openingBookProvider.overrideWith((ref) => book),
        nowMsProvider.overrideWithValue(() => clock++),
        engineDriverFactoryProvider.overrideWithValue(driverFactory),
        pipelineTimeoutsProvider.overrideWithValue(const PipelineTimeouts(
          handshake: Duration(seconds: 2),
          stop: Duration(milliseconds: 100),
          searchIdle: Duration(seconds: 2),
        )),
      ];

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(overrides: overrides, child: const GlyphApp()));
    await tester.pumpAndSettle();
  }

  /// Adds a game directly to the repository.
  Future<int> seed({
    String white = 'Alice',
    String black = 'Bob',
    String result = '1-0',
    String? date = '2026.10.23',
    GameSource source = GameSource.paste,
    int plyCount = 40,
    int importedAt = 1,
    Side? userSide,
    AnalysisStatus? status,
    int completedPlies = 0,
    double? whiteAccuracy,
    double? blackAccuracy,
    String? eco,
    String? openingName,
  }) async {
    final saved = await games.save(NewGame(
      source: source,
      pgn: '1. e4 *',
      white: white,
      black: black,
      whiteElo: 1500,
      result: result,
      date: date,
      plyCount: plyCount,
      importedAt: importedAt,
      userSide: userSide,
      eco: eco,
      openingName: openingName,
    ));
    if (status != null) {
      await analyses.upsert(AnalysisRecord(
        gameId: saved.id,
        engine: 'Stockfish',
        depth: 16,
        multipv: 2,
        status: status,
        completedPlies: completedPlies,
        whiteAccuracy: whiteAccuracy,
        blackAccuracy: blackAccuracy,
        updatedAt: 1,
      ));
    }
    return saved.id;
  }
}

OpeningBook realBook() => OpeningBook.parseTsv(File('assets/openings.tsv').readAsStringSync());

String vectorPgn(String name) => File('../packages/glyph_core/test/vectors/pgn/$name').readAsStringSync();

Uint8List bytesOf(String s) => Uint8List.fromList(s.codeUnits);

