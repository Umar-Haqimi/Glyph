import 'dart:async';

import 'package:dartchess/dartchess.dart' show Chess, Position, Rule, Setup, kInitialFEN;
import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import 'support/transcripts.dart';

AnalysisPipeline pipelineWith(
  EngineDriverFactory factory,
  AnalysisStore store, {
  PipelineTimeouts timeouts = fastTimeouts,
}) =>
    AnalysisPipeline(createDriver: factory, store: store, clock: FakeClock(1000), timeouts: timeouts);

List<String> positionCommands(FakeEngineDriver d) => [for (final c in d.sent) if (c.startsWith('position')) c];
List<String> goCommands(FakeEngineDriver d) => [for (final c in d.sent) if (c.startsWith('go')) c];

/// Records the order of go commands and store writes.
class LoggingStore extends InMemoryAnalysisStore {
  LoggingStore(this.log, {this.delay = Duration.zero});

  final List<String> log;
  final Duration delay;

  @override
  Future<void> savePosition(int gameId, PositionAnalysis position, {required int nowMs}) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    await super.savePosition(gameId, position, nowMs: nowMs);
    log.add('save ${position.ply}');
  }
}

class LoggingDriver implements EngineDriver {
  LoggingDriver(this.inner, this.log);

  final FakeEngineDriver inner;
  final List<String> log;

  @override
  Stream<String> get lines => inner.lines;

  @override
  void send(String command) {
    if (command.startsWith('go')) log.add('go');
    inner.send(command);
  }

  @override
  Future<void> dispose() => inner.dispose();
}

void main() {
  group('full game (recorded transcript)', () {
    test('italian_castle: session setup, history on every position, Chess960 on', () async {
      final fake = fakeFor('italian_castle');
      final store = InMemoryAnalysisStore();
      final game = transcriptGame('italian_castle');
      final pipeline = pipelineWith(() async => fake, store);
      final states = <AnalysisJobState>[];
      pipeline.states.listen(states.add);

      final result = await pipeline.analyze(requestFor(game));
      expect(result, isA<AnalysisCompleted>());
      expect(result.total, game.moves.length + 1);

      // Setup sequence, exactly (Threads before Hash).
      expect(fake.sent.take(9).toList(), [
        'uci',
        'setoption name Threads value 1',
        'setoption name Hash value 16',
        'setoption name MultiPV value 2',
        'setoption name UCI_Chess960 value true',
        'isready',
        'ucinewgame',
        'isready',
        startsWith('position startpos'),
      ]);
      expect(fake.sent.where((c) => c == 'ucinewgame'), hasLength(1));

      // Every position carries the whole history.
      final positions = positionCommands(fake);
      expect(positions, hasLength(game.moves.length + 1));
      expect(positions.first, 'position startpos');
      for (var i = 1; i < positions.length; i++) {
        expect(positions[i], 'position startpos moves ${game.moves.take(i).join(' ')}');
      }
      expect(goCommands(fake), everyElement('go depth 16'));

      // The castling moves are in the king-takes-rook form.
      expect(game.moves, containsAll(['e1h1', 'e8h8']));
      expect(positions.last, contains(' e1h1 '));

      // Everything persisted, two lines each, White POV.
      expect(store.positions, hasLength(game.moves.length + 1));
      for (final p in store.positions.values) {
        expect(p.terminal, isNull);
        expect(p.lines.map((l) => l.rank), [1, 2]);
        expect(p.lines.every((l) => l.depth == 16), isTrue);
      }
      expect(store.analyses[1]!.status, AnalysisStatus.completed);
      expect(store.analyses[1]!.completedPositions, game.moves.length + 1);

      // State machine: starting -> running(0..N) -> completed.
      expect(states.first, isA<AnalysisStarting>());
      expect(states[1], isA<AnalysisRunning>());
      expect(states.whereType<AnalysisRunning>().map((s) => s.completed), List.generate(game.moves.length + 2, (i) => i));
      expect(states.last, isA<AnalysisCompleted>());
      await pipeline.dispose();
    });

    test('White POV: the start position favours White, Black to move flips the sign', () async {
      final fake = fakeFor('italian_castle');
      final store = InMemoryAnalysisStore();
      final pipeline = pipelineWith(() async => fake, store);
      await pipeline.analyze(requestFor(transcriptGame('italian_castle')));
      // Transcript: pos 0 (White to move) "score cp 30", pos 1 (Black to move) "score cp -32" raw.
      final raw0 = loadTranscript('italian_castle').entries.values.first;
      final raw0Score = parseUciInfoLine(raw0.lastWhere((l) => l.contains('multipv 1') && l.startsWith('info depth 16')))!.score;
      expect(store.positions[(1, 0)]!.lines.first.score, WhiteScore.cp(raw0Score.cp!));
      final raw1 = loadTranscript('italian_castle').entries.values.elementAt(1);
      final raw1Score = parseUciInfoLine(raw1.lastWhere((l) => l.contains('multipv 1') && l.startsWith('info depth 16')))!.score;
      expect(store.positions[(1, 1)]!.lines.first.score, WhiteScore.cp(-raw1Score.cp!));
      await pipeline.dispose();
    });

    test('FEN start uses "position fen", promotion is sent as UCI', () async {
      final fake = fakeFor('promotion');
      final game = transcriptGame('promotion');
      final pipeline = pipelineWith(() async => fake, InMemoryAnalysisStore());
      final result = await pipeline.analyze(requestFor(game));
      expect(result, isA<AnalysisCompleted>());
      expect(game.moves.first, 'e7e8q');
      expect(positionCommands(fake).first, 'position fen ${game.startFen}');
      expect(positionCommands(fake)[1], 'position fen ${game.startFen} moves e7e8q');
      await pipeline.dispose();
    });

    test('repetition: history is sent so the engine can see the repetition', () async {
      final fake = fakeFor('repetition');
      final game = transcriptGame('repetition');
      final pipeline = pipelineWith(() async => fake, InMemoryAnalysisStore());
      await pipeline.analyze(requestFor(game));
      expect(positionCommands(fake).last, 'position startpos moves g1f3 g8f6 f3g1 f6g8 g1f3 g8f6 f3g1 f6g8');
      await pipeline.dispose();
    });
  });

  group('terminal positions never reach the engine', () {
    test('checkmate at the end of mate_opera', () async {
      final fake = fakeFor('mate_opera');
      final store = InMemoryAnalysisStore();
      final game = transcriptGame('mate_opera');
      final pipeline = pipelineWith(() async => fake, store);
      final result = await pipeline.analyze(requestFor(game));
      expect(result, isA<AnalysisCompleted>());

      final n = game.moves.length;
      expect(positionCommands(fake), hasLength(n)); // positions 0..n-1 only
      expect(positionCommands(fake).any((c) => c.endsWith(game.moves.join(' '))), isFalse);
      expect(goCommands(fake), hasLength(n));

      final last = store.positions[(1, n)]!;
      expect(last.lines, isEmpty);
      expect(last.terminal!.kind, TerminalKind.checkmate);
      expect(last.terminal!.winner, Side.white);
      expect(last.terminal!.whiteWinPercent, 100);
      expect(store.analyses[1]!.completedPositions, n + 1);
      await pipeline.dispose();
    });

    test('stalemate after Qg6', () async {
      final fake = fakeFor('stalemate');
      final store = InMemoryAnalysisStore();
      final pipeline = pipelineWith(() async => fake, store);
      await pipeline.analyze(requestFor(transcriptGame('stalemate')));
      expect(goCommands(fake), hasLength(1));
      final t = store.positions[(1, 1)]!.terminal!;
      expect(t.kind, TerminalKind.stalemate);
      expect(t.winner, isNull);
      expect(t.whiteWinPercent, 50);
      await pipeline.dispose();
    });

    test('a game of terminal positions only does not even start the engine', () async {
      var created = 0;
      final store = InMemoryAnalysisStore();
      // K vs K: insufficient material at every position.
      final pipeline = pipelineWith(() async {
        created++;
        return FakeEngineDriver(Transcript());
      }, store);
      final result = await pipeline.analyze(const AnalysisRequest(
        gameId: 1,
        startFen: '8/8/4k3/8/8/4K3/8/8 w - - 0 1',
        moves: ['e3d3', 'e6d6'],
        depth: 12,
      ));
      expect(result, isA<AnalysisCompleted>());
      expect(created, 0);
      expect(store.positions.values.map((p) => p.terminal!.kind), everyElement(TerminalKind.insufficientMaterial));
      await pipeline.dispose();
    });

    test('detectTerminal', () {
      Position p(String fen) => Position.setupPosition(Rule.chess, Setup.parseFen(fen));
      expect(detectTerminal(p('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1'))!.kind, TerminalKind.checkmate);
      expect(detectTerminal(p('7k/6Q1/6K1/8/8/8/8/8 b - - 0 1'))!.winner, Side.white);
      expect(detectTerminal(p('7k/5Q2/6K1/8/8/8/8/8 b - - 0 1'))!.kind, TerminalKind.stalemate);
      expect(detectTerminal(p('7k/5Q2/8/6K1/8/8/8/8 b - - 0 1'))!.kind, TerminalKind.stalemate);
      expect(detectTerminal(p('8/8/4k3/8/8/4K3/8/8 w - - 0 1'))!.kind, TerminalKind.insufficientMaterial);
      expect(detectTerminal(Chess.initial), isNull);
      // Threefold / 50-move are not terminal here (engine sees them through the history).
      expect(detectTerminal(p('8/8/4k3/8/8/4K3/8/R7 w - - 120 90')), isNull);
    });
  });

  group('persistence order', () {
    test('every position is saved before the next go (even with a slow store)', () async {
      final log = <String>[];
      final store = LoggingStore(log, delay: const Duration(milliseconds: 5));
      final fake = fakeFor('queens_gambit');
      final pipeline = pipelineWith(() async => LoggingDriver(fake, log), store);
      await pipeline.analyze(requestFor(transcriptGame('queens_gambit')));
      final n = transcriptGame('queens_gambit').moves.length + 1;
      expect(log, [for (var i = 0; i < n; i++) ...['go', 'save $i']]);
      await pipeline.dispose();
    });
  });

  group('cancel', () {
    test('mid-search: stop, await bestmove, discard the partial ply, resume later', () async {
      final fake = fakeFor('italian_castle')..holdSearch = 3;
      final store = InMemoryAnalysisStore();
      final game = transcriptGame('italian_castle');
      final pipeline = pipelineWith(() async => fake, store);

      final run = pipeline.analyze(requestFor(game));
      await fake.waitForGo(3);
      await pipeline.cancel();
      final cancelled = await run;

      expect(cancelled, isA<AnalysisCancelled>());
      expect(cancelled.completed, 2);
      expect(fake.sent.last, 'stop');
      expect(fake.disposed, isFalse, reason: 'bestmove arrived in time: no recreate');
      expect(store.analyses[1]!.status, AnalysisStatus.cancelled);
      expect(store.analyses[1]!.completedPositions, 2);
      expect(store.saveLog, [(1, 0), (1, 1)], reason: 'the interrupted ply is not persisted');
      expect(pipeline.state, isA<AnalysisCancelled>());

      // Resume: continues at position 2, same engine, positions 0 and 1 not searched again.
      fake.holdSearch = null;
      final before = goCommands(fake).length;
      final resumed = await pipeline.analyze(requestFor(game));
      expect(resumed, isA<AnalysisCompleted>());
      expect(goCommands(fake).length - before, game.moves.length + 1 - 2);
      expect(fake.sent.sublist(fake.sent.lastIndexOf('stop')).where((c) => c.startsWith('position')).first,
          'position startpos moves ${game.moves.take(2).join(' ')}');
      expect(store.saveLog, [for (var i = 0; i <= game.moves.length; i++) (1, i)]);
      expect(fake.sent.where((c) => c == 'ucinewgame'), hasLength(2));
      expect(pipeline.enginesCreated, 1);
      await pipeline.dispose();
    });

    test('engine ignores stop: 2 s rule -> dispose, recreate for the next job', () async {
      final first = fakeFor('italian_castle')
        ..holdSearch = 2
        ..ignoreStop = true;
      final second = fakeFor('italian_castle');
      final engines = [first, second];
      final store = InMemoryAnalysisStore();
      final game = transcriptGame('italian_castle');
      final pipeline = pipelineWith(() async => engines.removeAt(0), store);

      final run = pipeline.analyze(requestFor(game));
      await first.waitForGo(2);
      await pipeline.cancel();
      expect(await run, isA<AnalysisCancelled>());
      expect(first.disposed, isTrue);
      expect(store.analyses[1]!.completedPositions, 1);

      final resumed = await pipeline.analyze(requestFor(game));
      expect(resumed, isA<AnalysisCompleted>());
      expect(pipeline.enginesCreated, 2);
      expect(second.sent.first, 'uci', reason: 'a fresh engine gets the full handshake');
      expect(positionCommands(second).first, 'position startpos moves ${game.moves.first}');
      await pipeline.dispose();
    });

    test('cancel while idle does nothing', () async {
      final pipeline = pipelineWith(() async => FakeEngineDriver(Transcript()), InMemoryAnalysisStore());
      await pipeline.cancel();
      expect(pipeline.state, isA<AnalysisIdle>());
      await pipeline.dispose();
    });
  });

  group('pause', () {
    test('ends in paused, releases the engine, resumes from the last persisted ply', () async {
      final first = fakeFor('queens_gambit')..holdSearch = 4;
      final second = fakeFor('queens_gambit');
      final engines = [first, second];
      final store = InMemoryAnalysisStore();
      final game = transcriptGame('queens_gambit');
      final pipeline = pipelineWith(() async => engines.removeAt(0), store);

      final run = pipeline.analyze(requestFor(game));
      await first.waitForGo(4);
      await pipeline.pause();
      final paused = await run;
      expect(paused, isA<AnalysisPaused>());
      expect(paused.completed, 3);
      expect(first.disposed, isTrue);
      expect(store.analyses[1]!.status, AnalysisStatus.paused);

      final resumed = await pipeline.analyze(requestFor(game));
      expect(resumed, isA<AnalysisCompleted>());
      expect(positionCommands(second).first, 'position startpos moves ${game.moves.take(3).join(' ')}');
      await pipeline.dispose();
    });
  });

  group('resume from completed_plies', () {
    test('stored progress with the same depth/multipv is continued', () async {
      final game = transcriptGame('queens_gambit');
      // First run to completion, then pretend only 5 positions were saved.
      final store = InMemoryAnalysisStore();
      final p1 = pipelineWith(() async => fakeFor('queens_gambit'), store);
      await p1.analyze(requestFor(game));
      await p1.dispose();
      store.analyses[1] = const StoredAnalysis(depth: 16, multipv: 2, completedPositions: 5, status: AnalysisStatus.running);
      store.positions.removeWhere((k, _) => k.$2 >= 5);
      store.saveLog.clear();

      final fake = fakeFor('queens_gambit');
      final p2 = pipelineWith(() async => fake, store);
      final result = await p2.analyze(requestFor(game));
      expect(result, isA<AnalysisCompleted>());
      expect(positionCommands(fake).first, 'position startpos moves ${game.moves.take(5).join(' ')}');
      expect(goCommands(fake), hasLength(game.moves.length + 1 - 5));
      expect(store.saveLog.first, (1, 5));
      expect(store.positions, hasLength(game.moves.length + 1));
      await p2.dispose();
    });

    test('different depth, or restart: starts over and clears old lines', () async {
      final game = transcriptGame('queens_gambit');
      for (final req in [requestFor(game, depth: 16).copyWith(restart: true), requestFor(game, depth: 16)]) {
        final store = InMemoryAnalysisStore();
        store.analyses[1] = StoredAnalysis(
          depth: req.restart ? 16 : 12,
          multipv: 2,
          completedPositions: 5,
          status: AnalysisStatus.cancelled,
        );
        store.positions[(1, 0)] = const PositionAnalysis(ply: 0);
        final fake = fakeFor('queens_gambit');
        final pipeline = pipelineWith(() async => fake, store);
        await pipeline.analyze(req);
        expect(positionCommands(fake).first, 'position startpos');
        expect(goCommands(fake), hasLength(game.moves.length + 1));
        expect(store.positions[(1, 0)]!.lines, isNotEmpty, reason: 'the stale row was replaced');
        await pipeline.dispose();
      }
    });

    test('already complete: finishes without creating an engine', () async {
      final game = transcriptGame('italian_castle');
      final store = InMemoryAnalysisStore()
        ..analyses[1] = StoredAnalysis(
          depth: 16,
          multipv: 2,
          completedPositions: game.moves.length + 1,
          status: AnalysisStatus.completed,
        );
      var created = 0;
      final pipeline = pipelineWith(() async {
        created++;
        return fakeFor('italian_castle');
      }, store);
      expect(await pipeline.analyze(requestFor(game)), isA<AnalysisCompleted>());
      expect(created, 0);
      await pipeline.dispose();
    });
  });

  group('failures', () {
    test('engine crash -> failed(EngineCrashed) -> retry recreates and resumes', () async {
      final crashing = fakeFor('italian_castle')..crashOnGo = 4;
      final good = fakeFor('italian_castle');
      final engines = [crashing, good];
      final store = InMemoryAnalysisStore();
      final game = transcriptGame('italian_castle');
      final pipeline = pipelineWith(() async => engines.removeAt(0), store);

      final failed = await pipeline.analyze(requestFor(game));
      expect(failed, isA<AnalysisFailed>());
      expect((failed as AnalysisFailed).kind, AnalysisFailureKind.engineCrashed);
      expect(failed.completed, 3);
      expect(store.analyses[1]!.status, AnalysisStatus.failed);
      expect(store.analyses[1]!.completedPositions, 3);
      expect(crashing.disposed, isTrue);

      // Retry = analyze again: new engine, continues at position 3.
      final retried = await pipeline.analyze(requestFor(game));
      expect(retried, isA<AnalysisCompleted>());
      expect(pipeline.enginesCreated, 2);
      expect(positionCommands(good).first, 'position startpos moves ${game.moves.take(3).join(' ')}');
      await pipeline.dispose();
    });

    test('factory throws -> failed(EngineUnavailable), retry works', () async {
      var attempt = 0;
      final pipeline = pipelineWith(() async {
        if (attempt++ == 0) throw StateError('A light engine is already live.');
        return fakeFor('stalemate');
      }, InMemoryAnalysisStore());
      final failed = await pipeline.analyze(requestFor(transcriptGame('stalemate')));
      expect((failed as AnalysisFailed).kind, AnalysisFailureKind.engineUnavailable);
      expect(await pipeline.analyze(requestFor(transcriptGame('stalemate'))), isA<AnalysisCompleted>());
      await pipeline.dispose();
    });

    test('no uciok -> failed(EngineUnavailable)', () async {
      final mute = _MuteDriver();
      final pipeline = pipelineWith(
        () async => mute,
        InMemoryAnalysisStore(),
        timeouts: const PipelineTimeouts(handshake: Duration(milliseconds: 100)),
      );
      final failed = await pipeline.analyze(requestFor(transcriptGame('stalemate')));
      expect((failed as AnalysisFailed).kind, AnalysisFailureKind.engineUnavailable);
      expect(mute.disposed, isTrue);
      await pipeline.dispose();
    });

    test('unknown command pair in the fake fails loudly', () async {
      final fake = FakeEngineDriver(Transcript()); // nothing recorded
      final pipeline = pipelineWith(() async => fake, InMemoryAnalysisStore());
      final failed = await pipeline.analyze(requestFor(transcriptGame('stalemate')));
      expect(failed, isA<AnalysisFailed>());
      await pipeline.dispose();

      final direct = FakeEngineDriver(Transcript());
      direct.send('position startpos');
      expect(() => direct.send('go depth 16'), throwsA(isA<UnknownTranscriptKey>()));
    });

    test('engine rejecting a move (CRITICAL ERROR) fails the job', () async {
      final fake = fakeFor('queens_gambit');
      // Inject an error line into the first search.
      final entry = fake.transcript.entries.entries.first;
      fake.transcript.entries[entry.key] = ['info string CRITICAL ERROR: Illegal move: e1g1', ...entry.value];
      final pipeline = pipelineWith(() async => fake, InMemoryAnalysisStore());
      final failed = await pipeline.analyze(requestFor(transcriptGame('queens_gambit')));
      expect((failed as AnalysisFailed).kind, AnalysisFailureKind.engineCrashed);
      expect(failed.message, contains('CRITICAL ERROR'));
      await pipeline.dispose();
    });

    test('illegal move in the request fails before touching the engine', () async {
      var created = 0;
      final pipeline = pipelineWith(() async {
        created++;
        return FakeEngineDriver(Transcript());
      }, InMemoryAnalysisStore());
      final failed = await pipeline.analyze(const AnalysisRequest(
        gameId: 1,
        startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        moves: ['e2e5'],
        depth: 12,
      ));
      expect(failed, isA<AnalysisFailed>());
      expect(created, 0);
      await pipeline.dispose();
    });

    test('a second analyze while running is a programming error', () async {
      final fake = fakeFor('italian_castle')..holdSearch = 1;
      final pipeline = pipelineWith(() async => fake, InMemoryAnalysisStore());
      final run = pipeline.analyze(requestFor(transcriptGame('italian_castle')));
      await fake.waitForGo(1);
      expect(() => pipeline.analyze(requestFor(transcriptGame('italian_castle'))), throwsStateError);
      await pipeline.cancel();
      await run;
      await pipeline.dispose();
    });
  });

  group('P0: mirrored game gives mirrored White-POV scores', () {
    test('recorded blunder_white vs blunder_black', () async {
      final white = transcriptGame('blunder_white');
      final black = transcriptGame('blunder_black');
      expect(black.startFen, startsWith('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b '));
      expect(black.moves.first, 'e7e5');

      final storeW = InMemoryAnalysisStore();
      final storeB = InMemoryAnalysisStore();
      await pipelineWith(() async => fakeFor('blunder_white'), storeW).analyze(requestFor(white, gameId: 1));
      await pipelineWith(() async => fakeFor('blunder_black'), storeB).analyze(requestFor(black, gameId: 1));

      var compared = 0;
      for (var ply = 0; ply <= white.moves.length; ply++) {
        final w = storeW.positions[(1, ply)]!.lines.first.score;
        final b = storeB.positions[(1, ply)]!.lines.first.score;
        if (w.isMate || b.isMate) {
          expect(w.isMate && b.isMate, isTrue, reason: 'ply $ply');
          expect(b.mate, -w.mate!, reason: 'ply $ply');
          continue;
        }
        // Search noise between the two orientations is small; the sign must mirror.
        expect((w.cp! + b.cp!).abs(), lessThanOrEqualTo(60), reason: 'ply $ply: ${w.cp} vs ${b.cp}');
        if (w.cp!.abs() > 60) expect(w.cp!.sign, -b.cp!.sign, reason: 'ply $ply');
        compared++;
      }
      expect(compared, greaterThan(10));

      // Best moves mirror at the start (both orientations are the same engine decision).
      expect(mirrorUci(storeW.positions[(1, 0)]!.lines.first.pv.first), storeB.positions[(1, 0)]!.lines.first.pv.first);
      // The sacrifice 6.Nxf7 (white game, ply 10 is "after 5...Nxd5" i.e. White to move) is good for White;
      // in the mirror it is good for Black: the White-POV eval has the opposite sign.
      final w10 = storeW.positions[(1, 10)]!.lines.first.score.cp!;
      final b10 = storeB.positions[(1, 10)]!.lines.first.score.cp!;
      expect(w10.sign, isNot(b10.sign));
    });

    test('scripted engine: the same raw "cp +50" is +50 for White to move and -50 for Black to move', () async {
      final t = Transcript();
      t.add('position startpos', 'go depth 4', [
        'info depth 4 multipv 1 score cp 50 pv e2e4',
        'info depth 4 multipv 2 score cp 20 pv d2d4',
        'bestmove e2e4',
      ]);
      t.add('position startpos moves e2e4', 'go depth 4', [
        'info depth 4 multipv 1 score cp 50 pv e7e5',
        'info depth 4 multipv 2 score mate 2 pv d8h4',
        'bestmove e7e5',
      ]);
      final store = InMemoryAnalysisStore();
      final pipeline = pipelineWith(() async => FakeEngineDriver(t), store);
      await pipeline.analyze(const AnalysisRequest(gameId: 1, startFen: kInitialFEN, moves: ['e2e4'], depth: 4));
      expect(store.positions[(1, 0)]!.lines.map((l) => l.score), [const WhiteScore.cp(50), const WhiteScore.cp(20)]);
      expect(store.positions[(1, 1)]!.lines.map((l) => l.score), [const WhiteScore.cp(-50), const WhiteScore.mate(-2)]);
      await pipeline.dispose();
    });
  });
}

class _MuteDriver implements EngineDriver {
  bool disposed = false;

  @override
  Stream<String> get lines => const Stream<String>.empty().asBroadcastStream();

  @override
  void send(String command) {}

  @override
  Future<void> dispose() async => disposed = true;
}
