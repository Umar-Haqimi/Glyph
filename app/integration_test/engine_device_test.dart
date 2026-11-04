@Tags(['device'])
library;

// Device-only: runs the real multistockfish engine (Stockfish 19, embedded
// light net) through EngineService and SQLite. Not part of `flutter test`
// (CI); run it on an emulator or phone:
//
//   flutter test integration_test/engine_device_test.dart -d <device id>
//
// Tolerant assertions only (SPEC trap 8): structure, progress, signs. Never
// exact centipawns, the device net differs from the desktop one.
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/db.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/data/sqlite_repositories.dart';
import 'package:glyph/engine/engine_service.dart';
import 'package:glyph/engine/multistockfish_driver.dart';
import 'package:glyph/engine/repository_analysis_store.dart';
import 'package:glyph/features/settings/engine_settings.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:integration_test/integration_test.dart';

/// 30 plies of Morphy's Opera game, with an O-O-O (ply 23): castling goes to
/// the engine as king-takes-rook in Chess960 mode.
const _moves30 = 'e4 e5 Nf3 d6 d4 Bg4 dxe5 Bxf3 Qxf3 dxe5 Bc4 Nf6 Qb3 Qe7 Nc3 c6 Bg5 b5 Nxb5 cxb5 Bxb5+ '
    'Nbd7 O-O-O Rd8 Rxd7 Rxd7 Rd1 Qe6 Bxd7+ Nxd7';

class Rig {
  Rig() {
    db = Db.inMemory();
    games = SqliteGameRepository(db);
    analyses = SqliteAnalysisRepository(db);
    service = EngineService(
      driverFactory: MultistockfishDriver.create,
      store: RepositoryAnalysisStore(analyses),
    );
  }

  late final Db db;
  late final SqliteGameRepository games;
  late final SqliteAnalysisRepository analyses;
  late final EngineService service;

  Future<int> addGame(int plyCount) async => (await games.save(NewGame(
        source: GameSource.paste,
        pgn: '*',
        plyCount: plyCount,
        importedAt: 1,
      ))).id;

  AnalysisRequest request(int id, String startFen, List<String> moves, {int depth = 12}) => AnalysisRequest(
        gameId: id,
        startFen: startFen,
        moves: moves,
        depth: depth,
        multipv: EngineDefaults.multiPv,
        threads: EngineDefaults.defaultThreads,
        hashMb: EngineDefaults.hashMb,
        engineName: EngineDefaults.engineName,
      );

  Future<AnalysisJobState> until(bool Function(AnalysisJobState) test, {Duration timeout = const Duration(minutes: 3)}) async {
    if (test(service.state)) return service.state;
    return service.states.firstWhere(test).timeout(timeout);
  }

  Future<void> dispose() async {
    await service.dispose();
    db.close();
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final moves30 = sanOrUciToUci(kInitialFenForTest, _moves30.split(' '));

  testWidgets('analyses a 30-ply game at Fast: every ply has lines, progress is stored', (tester) async {
    expect(moves30, hasLength(30));
    final rig = Rig();
    final id = await rig.addGame(30);
    final seen = <int>[];
    rig.service.states.listen((s) {
      if (s is AnalysisRunning) seen.add(s.completed);
    });
    rig.service.enqueue(rig.request(id, kInitialFenForTest, moves30, depth: DepthPreset.fast.depth));
    final done = await rig.until((s) => s is AnalysisCompleted);
    expect(done.total, 31);

    final a = (await rig.analyses.get(id))!;
    expect((a.status, a.completedPlies, a.depth, a.multipv), (AnalysisStatus.completed, 31, 12, 2));
    final lines = await rig.analyses.positionLines(id);
    final byPly = <int, List<PositionLineRecord>>{};
    for (final l in lines) {
      (byPly[l.ply] ??= []).add(l);
    }
    for (var ply = 0; ply <= 30; ply++) {
      final rows = byPly[ply];
      expect(rows, isNotNull, reason: 'ply $ply has no lines');
      expect(rows!.first.rank, 1);
      expect(rows.first.pvUci, isNotEmpty);
      expect(rows.first.scoreCp != null || rows.first.scoreMate != null, isTrue, reason: 'ply $ply');
      expect(rows.first.depth, greaterThanOrEqualTo(1));
    }
    expect(byPly.values.where((r) => r.length == 2).length, greaterThan(25), reason: 'MultiPV 2');
    expect(seen, isNotEmpty);
    await rig.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('eval sign sanity: scores are White POV whoever is to move', (tester) async {
    final rig = Rig();
    // White has an extra rook and a back-rank mate: Rd8#. Same material, Black to move.
    const whiteWinsWhiteToMove = '6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1';
    const whiteWinsBlackToMove = '6k1/5ppp/8/8/8/8/5PPP/3R2K1 b - - 0 1';
    // Colour-swapped: Black has the rook and the mate.
    const blackWinsBlackToMove = '3r2k1/5ppp/8/8/8/8/5PPP/6K1 b - - 0 1';
    const blackWinsWhiteToMove = '3r2k1/5ppp/8/8/8/8/5PPP/6K1 w - - 0 1';

    Future<PositionLineRecord> best(String fen) async {
      final id = await rig.addGame(0);
      rig.service.enqueue(rig.request(id, fen, const [], depth: 12));
      await rig.until((s) => s is AnalysisCompleted && s.gameId == id);
      return (await rig.analyses.positionLines(id)).first;
    }

    int signOf(PositionLineRecord l) => l.scoreMate != null ? l.scoreMate!.sign : l.scoreCp!.sign;

    expect(signOf(await best(whiteWinsWhiteToMove)), 1);
    expect(signOf(await best(whiteWinsBlackToMove)), 1);
    expect(signOf(await best(blackWinsBlackToMove)), -1);
    expect(signOf(await best(blackWinsWhiteToMove)), -1);
    await rig.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));

  testWidgets('cancel mid-game, resume from completed_plies, and pause/resume with a new engine', (tester) async {
    final rig = Rig();
    final id = await rig.addGame(30);
    // Depth 18 so a position takes long enough to interrupt.
    final req = rig.request(id, kInitialFenForTest, moves30, depth: 18);
    rig.service.enqueue(req);
    await rig.until((s) => s is AnalysisRunning && s.completed >= 2);
    await rig.service.cancel(id);
    final cancelled = rig.service.state;
    expect(cancelled, isA<AnalysisCancelled>());
    expect(cancelled.completed, inInclusiveRange(2, 30));
    var a = (await rig.analyses.get(id))!;
    expect((a.status, a.completedPlies), (AnalysisStatus.cancelled, cancelled.completed));
    expect(rig.service.enginesCreated, 1);

    // Resume: same request; continues after the stored ply.
    rig.service.enqueue(req);
    await rig.until((s) => s is AnalysisRunning && s.completed > cancelled.completed);
    // Background the app: job paused, engine released ...
    await rig.service.onAppPaused();
    final paused = rig.service.state;
    expect(paused, isA<AnalysisPaused>());
    a = (await rig.analyses.get(id))!;
    expect((a.status, a.completedPlies), (AnalysisStatus.paused, paused.completed));
    // ... foreground: a new engine is created (the one-per-flavor slot was freed) and the job finishes.
    await rig.service.onAppResumed();
    final done = await rig.until((s) => s is AnalysisCompleted);
    expect(done.total, 31);
    expect(rig.service.enginesCreated, 2);
    final lines = await rig.analyses.positionLines(id);
    expect(lines.map((l) => l.ply).toSet(), hasLength(31));
    await rig.dispose();
  }, timeout: const Timeout(Duration(minutes: 10)));
}

const kInitialFenForTest = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';
