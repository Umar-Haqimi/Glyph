@TestOn('vm')
library;

import 'dart:io';

import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/glyph_core_host.dart';
import 'package:test/test.dart';

import 'support/transcripts.dart';

/// Runs the real desktop Stockfish ($STOCKFISH_PATH). Skipped when unset.
/// Tolerant assertions only: structure, signs and terminal handling, never
/// exact centipawns (SPEC trap 8).
void main() {
  final path = Platform.environment['STOCKFISH_PATH'];
  final skip = path == null || path.isEmpty || !File(path).existsSync() ? 'STOCKFISH_PATH not set' : null;

  test('analyses a short game with the real engine', () async {
    final store = InMemoryAnalysisStore();
    final pipeline = AnalysisPipeline(
      createDriver: ProcessEngineDriver.fromEnvironment,
      store: store,
      timeouts: const PipelineTimeouts(handshake: Duration(seconds: 20), searchIdle: Duration(seconds: 60)),
    );
    // 1.f3 e5 2.g4 Qh4# : Fool's mate, ends in checkmate (Black wins).
    const moves = ['f2f3', 'e7e5', 'g2g4', 'd8h4'];
    final result = await pipeline.analyze(const AnalysisRequest(
      gameId: 1,
      startFen: 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
      moves: moves,
      depth: 8,
    ));
    expect(result, isA<AnalysisCompleted>(), reason: '$result');
    expect(store.positions, hasLength(5));
    for (var ply = 0; ply < 4; ply++) {
      final lines = store.positions[(1, ply)]!.lines;
      expect(lines, isNotEmpty);
      expect(lines.first.rank, 1);
      expect(lines.first.depth, greaterThanOrEqualTo(1));
      expect(lines.first.pv, isNotEmpty);
    }
    // After 2.g4 Black mates in 1: White POV mate score is negative.
    final beforeMate = store.positions[(1, 3)]!.lines.first.score;
    expect(beforeMate.mate, isNotNull);
    expect(beforeMate.mateWinner, Side.black);
    // White's start-position edge is small and positive-ish; just check it is not a mate.
    expect(store.positions[(1, 0)]!.lines.first.score.isMate, isFalse);
    // The checkmate position was not searched.
    final last = store.positions[(1, 4)]!;
    expect(last.terminal!.kind, TerminalKind.checkmate);
    expect(last.terminal!.winner, Side.black);
    await pipeline.dispose();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('cancel mid-search with the real engine ends cancelled with consistent progress', () async {
    final store = InMemoryAnalysisStore();
    final pipeline = AnalysisPipeline(
      createDriver: ProcessEngineDriver.fromEnvironment,
      store: store,
      timeouts: const PipelineTimeouts(handshake: Duration(seconds: 20), searchIdle: Duration(seconds: 60)),
    );
    final game = transcriptGame('queens_gambit');
    final req = requestFor(game, depth: 18);
    final run = pipeline.analyze(req);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await pipeline.cancel();
    final r = await run;
    expect(r, isA<AnalysisCancelled>());
    final done = r.completed;
    expect(store.analyses[1]!.completedPositions, done);
    await pipeline.dispose();
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));
}
