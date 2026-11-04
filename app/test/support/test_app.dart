import 'dart:async';
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
import 'package:glyph/features/settings/engine_settings.dart';
import 'package:glyph/features/settings/explain_settings.dart';
import 'package:glyph/platform/file_picker_service.dart';
import 'package:glyph/platform/online_http.dart';
import 'package:glyph/platform/pgn_share_service.dart';
import 'package:glyph/platform/share_intake.dart';
import 'package:glyph/platform/secret_store.dart';
import 'package:glyph/platform/shared_exports.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/testing.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

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

/// The platform side of Share / Open with: tests push [SharedContent] into it.
class FakeShareIntake implements ShareIntakeService {
  final _controller = StreamController<SharedContent>.broadcast();
  int starts = 0;

  @override
  Stream<SharedContent> get shared => _controller.stream;

  @override
  Future<void> start() async => starts++;

  void push(SharedContent content) => _controller.add(content);
}

/// The Android share sheet: records what was shared.
class FakePgnShare implements PgnShareService {
  final shared = <({String pgn, String fileName, String title})>[];
  Object? error;

  @override
  Future<void> share({required String pgn, required String fileName, required String title}) async {
    if (error != null) throw error!;
    shared.add((pgn: pgn, fileName: fileName, title: title));
  }
}

/// The exported-PGN folder: counts how often it was emptied (and can fail).
class FakeSharedExports implements SharedExports {
  int clears = 0;
  Object? error;

  @override
  Future<void> clear() async {
    clears++;
    if (error != null) throw error!;
  }
}

/// A game source that is always offline.
class OfflineOnlineClient implements OnlineGamesClient {
  @override
  Future<OnlineFetchOutcome> fetchGames(String username, {int max = 30, OnlineCancelToken? cancel, void Function(OnlineEvent event)? onEvent}) async =>
      const OnlineFetchOutcome(error: OnlineFetchError(OnlineErrorKind.offline));
}

/// An [LlmClient] whose connection always fails.
LlmClient offlineLlmClient() =>
    LlmClient(httpClient: () => MockClient((request) async => throw http.ClientException('offline in tests')));

class TestEnv {
  TestEnv({
    Map<String, String>? settings,
    InMemorySettingsRepository? settingsRepo,
    FilePickerService? picker,
    OpeningBook? book,
    EngineDriverFactory? driverFactory,
    InMemoryAnalysisRepository Function(InMemoryStore store)? analysesBuilder,
    InMemoryGameRepository Function(InMemoryStore store)? gamesBuilder,
    Map<String, String>? secrets,
    InMemorySecretStore? secretStore,
    LlmClient? llm,
    OnlineGamesClient? lichess,
    OnlineGamesClient? chessCom,
    FakeShareIntake? intake,
    FakePgnShare? pgnShare,
    FakeSharedExports? exports,
    this.maxHashMb = EngineDefaults.maxHashMb,
    this.timeouts = const PipelineTimeouts(
      handshake: Duration(seconds: 2),
      stop: Duration(milliseconds: 100),
      searchIdle: Duration(seconds: 2),
    ),
  })
      : store = InMemoryStore(),
        settings = settingsRepo ?? InMemorySettingsRepository(settings),
        picker = picker ?? FakeFilePicker(null),
        book = book ?? OpeningBook(const {}),
        driverFactory = driverFactory ?? (() async => FakeEngineDriver.permissive()),
        secrets = secretStore ?? InMemorySecretStore(secrets),
        llm = llm ?? offlineLlmClient(),
        lichess = lichess ?? OfflineOnlineClient(),
        chessCom = chessCom ?? OfflineOnlineClient(),
        intake = intake ?? FakeShareIntake(),
        pgnShare = pgnShare ?? FakePgnShare(),
        exports = exports ?? FakeSharedExports() {
    games = gamesBuilder?.call(store) ?? InMemoryGameRepository(store);
    cache = InMemoryLlmCacheRepository(store);
    analyses = analysesBuilder?.call(store) ?? InMemoryAnalysisRepository(store);
  }

  final InMemoryStore store;
  late final InMemoryGameRepository games;
  late final InMemoryAnalysisRepository analyses;
  final InMemorySettingsRepository settings;
  late final InMemoryLlmCacheRepository cache;
  final InMemorySecretStore secrets;

  /// The LLM client of the app under test. Default: every request fails as
  /// if offline (no test touches a real network).
  final LlmClient llm;
  final FilePickerService picker;
  final OpeningBook book;

  /// The lichess / chess.com clients of the app under test (default: always
  /// offline, so no test touches a network).
  final OnlineGamesClient lichess;
  final OnlineGamesClient chessCom;

  /// The share / open-with intake and the share sheet of the app under test.
  final FakeShareIntake intake;
  final FakePgnShare pgnShare;

  /// The exported-PGN folder of the app under test.
  final FakeSharedExports exports;

  /// The hash ceiling of the device under test (the picker offers up to it).
  final int maxHashMb;

  /// The chess.com ETag cache of the app under test.
  final onlineCache = InMemoryOnlineCache();

  /// Creates the engine of the app under test (default: a fake that answers
  /// every search with a trivial line).
  final EngineDriverFactory driverFactory;
  final PipelineTimeouts timeouts;
  int clock = 1000000;

  /// How many times the opening book was asked for (startup test).
  int bookReads = 0;

  List<Override> get overrides => [
        gameRepositoryProvider.overrideWithValue(games),
        analysisRepositoryProvider.overrideWithValue(analyses),
        settingsRepositoryProvider.overrideWithValue(settings),
        llmCacheRepositoryProvider.overrideWithValue(cache),
        secretStoreProvider.overrideWithValue(secrets),
        llmClientProvider.overrideWithValue(llm),
        filePickerServiceProvider.overrideWithValue(picker),
        lichessClientProvider.overrideWithValue(lichess),
        chessComClientProvider.overrideWithValue(chessCom),
        shareIntakeServiceProvider.overrideWithValue(intake),
        pgnShareServiceProvider.overrideWithValue(pgnShare),
        sharedExportsProvider.overrideWithValue(exports),
        maxHashMbProvider.overrideWithValue(maxHashMb),
        onlineCacheProvider.overrideWithValue(onlineCache),
        openingBookProvider.overrideWith((ref) {
          bookReads++;
          return book;
        }),
        nowMsProvider.overrideWithValue(() => clock++),
        engineDriverFactoryProvider.overrideWithValue(driverFactory),
        pipelineTimeoutsProvider.overrideWithValue(timeouts),
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

