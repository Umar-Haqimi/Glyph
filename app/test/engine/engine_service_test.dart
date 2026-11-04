import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/db.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/data/sqlite_repositories.dart';
import 'package:glyph/engine/engine_service.dart';
import 'package:glyph/engine/repository_analysis_store.dart';
import 'package:glyph_core/glyph_core.dart';

const _dir = '../packages/glyph_core/test/vectors/uci_transcripts';

Transcript transcript(String name) => Transcript.parse(File('$_dir/$name.txt').readAsStringSync());

List<TranscriptGame> games() => parseTranscriptGames(File('$_dir/games.json').readAsStringSync());

TranscriptGame game(String name) => games().firstWhere((g) => g.name == name);

AnalysisRequest request(int id, TranscriptGame g) => AnalysisRequest(
      gameId: id,
      startFen: g.startFen,
      moves: g.moves,
      depth: 16,
      multipv: 2,
      threads: 1,
      hashMb: 16,
    );

const fast = PipelineTimeouts(
  handshake: Duration(seconds: 2),
  stop: Duration(milliseconds: 100),
  searchIdle: Duration(seconds: 2),
);

class Harness {
  Harness(this.factory, {Duration reloadDelay = const Duration(milliseconds: 20)}) {
    db = Db.inMemory();
    games = SqliteGameRepository(db);
    analyses = SqliteAnalysisRepository(db);
    service = EngineService(
      driverFactory: factory,
      store: RepositoryAnalysisStore(analyses),
      clock: FakeClock(5),
      timeouts: fast,
      hotReloadResumeDelay: reloadDelay,
    );
  }

  final EngineDriverFactory factory;
  late final Db db;
  late final SqliteGameRepository games;
  late final SqliteAnalysisRepository analyses;
  late final EngineService service;
  final List<AnalysisJobState> states = [];

  Future<int> addGame(TranscriptGame g, {String name = 'g'}) async => (await games.save(NewGame(
        source: GameSource.paste,
        pgn: '1. e4 *',
        white: name,
        plyCount: g.moves.length,
        importedAt: 1,
      ))).id;

  Future<AnalysisJobState> waitFor(bool Function(AnalysisJobState) test) async {
    if (test(service.state)) return service.state;
    return service.states.firstWhere(test).timeout(const Duration(seconds: 10));
  }

  Future<void> dispose() async {
    await service.dispose();
    db.close();
  }
}

/// The engine is created lazily, after enqueue.
Future<FakeEngineDriver> firstEngine(List<FakeEngineDriver> fakes) async {
  while (fakes.isEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  return fakes.first;
}

void main() {
  test('runs a game end to end into SQLite: lines, terminal rows, completed status', () async {
    final h = Harness(() async => FakeEngineDriver(transcript('mate_opera')));
    final g = game('mate_opera');
    final id = await h.addGame(g);
    h.service.enqueue(request(id, g));
    final done = await h.waitFor((s) => s is AnalysisCompleted);
    expect(done.gameId, id);

    final a = (await h.analyses.get(id))!;
    expect((a.status, a.depth, a.multipv, a.completedPlies), (AnalysisStatus.completed, 16, 2, g.moves.length + 1));
    final lines = await h.analyses.positionLines(id);
    final byPly = <int, List<PositionLineRecord>>{};
    for (final l in lines) {
      (byPly[l.ply] ??= []).add(l);
    }
    expect(byPly, hasLength(g.moves.length + 1));
    expect(byPly[0]!.map((l) => l.rank), [1, 2]);
    expect(byPly[0]!.first.scoreCp, isNotNull);
    expect(byPly[0]!.first.pvUci, startsWith('e2e4'));
    // Final position is checkmate: one row, both scores NULL, depth 0.
    final last = byPly[g.moves.length]!.single;
    expect((last.scoreCp, last.scoreMate, last.depth, last.pvUci), (null, null, 0, ''));
    // A forced mate for White at ply 32 (before Rd8#).
    expect(byPly[g.moves.length - 1]!.first.scoreMate, 1);
    await h.dispose();
  });

  test('jobs run one at a time on one engine', () async {
    var created = 0;
    final h = Harness(() async {
      created++;
      return FakeEngineDriver(transcript('queens_gambit')..addAll(transcript('italian_castle')));
    });
    final g1 = game('queens_gambit');
    final g2 = game('italian_castle');
    final id1 = await h.addGame(g1);
    final id2 = await h.addGame(g2);
    final seen = <String>[];
    h.service.states.listen((s) {
      if (s is AnalysisCompleted) seen.add('done ${s.gameId}');
      if (s is AnalysisStarting) seen.add('start ${s.gameId}');
    });
    h.service.enqueue(request(id1, g1));
    h.service.enqueue(request(id2, g2));
    expect(h.service.isActive(id2), isTrue);
    await h.waitFor((s) => s is AnalysisCompleted && s.gameId == id2);
    expect(seen, ['start $id1', 'done $id1', 'start $id2', 'done $id2']);
    expect(created, 1);
    await h.dispose();
  });

  test('cancel a running job, drop a queued one; resume continues at completed_plies', () async {
    final fakes = <FakeEngineDriver>[];
    final h = Harness(() async {
      final f = FakeEngineDriver(transcript('queens_gambit'));
      if (fakes.isEmpty) f.holdSearch = 3;
      fakes.add(f);
      return f;
    });
    final g = game('queens_gambit');
    final id = await h.addGame(g);
    final other = await h.addGame(g, name: 'other');
    h.service.enqueue(request(id, g));
    h.service.enqueue(request(other, g));
    await (await firstEngine(fakes)).waitForGo(3);
    await h.service.cancel(other); // queued: just removed
    expect(h.service.isQueued(other), isFalse);
    await h.service.cancel(id);
    expect(h.service.state, isA<AnalysisCancelled>());
    expect(h.service.state.completed, 2);
    expect((await h.analyses.get(id))!.status, AnalysisStatus.cancelled);
    expect(await h.analyses.get(other), isNull);

    h.service.enqueue(request(id, g)); // Resume
    await h.waitFor((s) => s is AnalysisCompleted);
    expect(fakes, hasLength(1), reason: 'same engine reused');
    expect((await h.analyses.get(id))!.completedPlies, g.moves.length + 1);
    await h.dispose();
  });

  test('app paused: job paused, engine disposed; resumed: new engine, continues', () async {
    final fakes = <FakeEngineDriver>[];
    final h = Harness(() async {
      final f = FakeEngineDriver(transcript('queens_gambit'));
      if (fakes.isEmpty) f.holdSearch = 4;
      fakes.add(f);
      return f;
    });
    final g = game('queens_gambit');
    final id = await h.addGame(g);
    h.service.enqueue(request(id, g));
    await (await firstEngine(fakes)).waitForGo(4);

    await h.service.onAppPaused();
    expect(h.service.state, isA<AnalysisPaused>());
    expect(h.service.state.completed, 3);
    expect((await firstEngine(fakes)).disposed, isTrue);
    expect((await h.analyses.get(id))!.status, AnalysisStatus.paused);
    expect(h.service.isActive(id), isTrue, reason: 'a paused job is still wanted');

    // Nothing runs while in the background.
    final g2 = await h.addGame(g, name: 'second');
    h.service.enqueue(request(g2, g));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(fakes, hasLength(1));

    await h.service.onAppResumed();
    await h.waitFor((s) => s is AnalysisCompleted && s.gameId == g2);
    expect(fakes, hasLength(2));
    expect((await h.analyses.get(id))!.status, AnalysisStatus.completed);
    expect(fakes[1].sent.where((c) => c.startsWith('position')).first,
        'position startpos moves ${g.moves.take(3).join(' ')}', reason: 'resumed at the last persisted ply');
    await h.dispose();
  });

  test('crash: failed, then Retry recreates the engine and resumes', () async {
    var n = 0;
    final h = Harness(() async {
      final f = FakeEngineDriver(transcript('italian_castle'));
      if (n++ == 0) f.crashOnGo = 5;
      return f;
    });
    final g = game('italian_castle');
    final id = await h.addGame(g);
    h.service.enqueue(request(id, g));
    final failed = await h.waitFor((s) => s is AnalysisFailed);
    expect((failed as AnalysisFailed).kind, AnalysisFailureKind.engineCrashed);
    expect(failed.completed, 4);
    expect((await h.analyses.get(id))!.status, AnalysisStatus.failed);

    h.service.enqueue(request(id, g)); // Retry
    await h.waitFor((s) => s is AnalysisCompleted);
    expect(h.service.enginesCreated, 2);
    expect((await h.analyses.get(id))!.completedPlies, g.moves.length + 1);
    await h.dispose();
  });

  test('engine unavailable (StateError from create): failed, retry works', () async {
    var n = 0;
    final h = Harness(() async {
      if (n++ == 0) throw StateError('A light engine is already live.');
      return FakeEngineDriver(transcript('stalemate'));
    });
    final g = game('stalemate');
    final id = await h.addGame(g);
    h.service.enqueue(request(id, g));
    final failed = await h.waitFor((s) => s is AnalysisFailed);
    expect((failed as AnalysisFailed).kind, AnalysisFailureKind.engineUnavailable);
    h.service.enqueue(request(id, g));
    await h.waitFor((s) => s is AnalysisCompleted);
    await h.dispose();
  });

  test('hot reload: engine released, job comes back by itself', () async {
    final fakes = <FakeEngineDriver>[];
    final h = Harness(() async {
      final f = FakeEngineDriver(transcript('queens_gambit'));
      if (fakes.isEmpty) f.holdSearch = 2;
      fakes.add(f);
      return f;
    });
    final g = game('queens_gambit');
    final id = await h.addGame(g);
    h.service.enqueue(request(id, g));
    await (await firstEngine(fakes)).waitForGo(2);
    await h.service.releaseForHotReload();
    expect((await firstEngine(fakes)).disposed, isTrue);
    expect(h.service.state, isA<AnalysisPaused>());
    await h.waitFor((s) => s is AnalysisCompleted);
    expect(fakes, hasLength(2));
    await h.dispose();
  });

  test('enqueueing the game that is running is ignored', () async {
    final fake = FakeEngineDriver(transcript('queens_gambit'))..holdSearch = 2;
    final h = Harness(() async => fake);
    final g = game('queens_gambit');
    final id = await h.addGame(g);
    h.service.enqueue(request(id, g));
    await fake.waitForGo(2);
    h.service.enqueue(request(id, g));
    expect(h.service.queuedGameIds, isEmpty);
    await h.service.cancel(id);
    await h.dispose();
  });
}
