// Host-side engine benchmark (SPEC 7.3, M8): analyses one game with a desktop
// Stockfish ($STOCKFISH_PATH) through the real AnalysisPipeline for a grid of
// depth / Threads / Hash settings and prints a markdown table (wall time per
// game, ms per position, hashfull at the end of the last search).
//
// Host numbers only rank the settings against each other; they say nothing
// about a phone (docs/HARDWARE_TEST.md section A has the device runs).
//
// Usage (repo root):
//   STOCKFISH_PATH=/usr/games/stockfish dart run tool/bench_engine.dart \
//       [--pgn packages/glyph_core/test/vectors/pgn/chesscom_download_clk.pgn] \
//       [--plies 80] [--depths 12,16] [--threads 1,2,4] [--hash 16,64,256]
import 'dart:io';

import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/glyph_core_host.dart';
import 'package:glyph_core/testing.dart';

Future<void> main(List<String> args) async {
  var pgnPath = 'packages/glyph_core/test/vectors/pgn/chesscom_download_clk.pgn';
  var depths = [12, 16];
  var threads = [1, 2, 4];
  var hashes = [16, 64, 256];
  var maxPlies = 80;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--pgn':
        pgnPath = args[++i];
      case '--plies':
        maxPlies = int.parse(args[++i]);
      case '--depths':
        depths = args[++i].split(',').map(int.parse).toList();
      case '--threads':
        threads = args[++i].split(',').map(int.parse).toList();
      case '--hash':
        hashes = args[++i].split(',').map(int.parse).toList();
    }
  }
  if ((Platform.environment['STOCKFISH_PATH'] ?? '').isEmpty) {
    stderr.writeln('STOCKFISH_PATH is not set');
    exitCode = 2;
    return;
  }
  final parsed = parsePgn(await File(pgnPath).readAsString());
  final game = parsed.games.first;
  final moves = game.plies.map((p) => p.uci).take(maxPlies).toList();
  final engine = await _engineName();
  stdout.writeln('Engine: $engine; ${Platform.numberOfProcessors} logical cores; game: ${moves.length} plies '
      '(${moves.length + 1} positions), MultiPV 2, full history, UCI_Chess960 true.');
  stdout.writeln();
  stdout.writeln('| Depth | Threads | Hash MB | Game time (s) | ms / position | hashfull (last position, per mille) |');
  stdout.writeln('|---|---|---|---|---|---|');
  for (final depth in depths) {
    for (final t in threads) {
      for (final h in hashes) {
        var hashfull = -1;
        final pipeline = AnalysisPipeline(
          createDriver: () async {
            final inner = await ProcessEngineDriver.fromEnvironment();
            inner.lines.listen((l) {
              final m = RegExp(r'hashfull (\d+)').firstMatch(l);
              if (m != null) hashfull = int.parse(m.group(1)!);
            });
            return inner;
          },
          store: InMemoryAnalysisStore(),
          timeouts: const PipelineTimeouts(searchIdle: Duration(minutes: 10), handshake: Duration(seconds: 30)),
        );
        final sw = Stopwatch()..start();
        final result = await pipeline.analyze(AnalysisRequest(
          gameId: 1,
          startFen: game.startFen,
          moves: moves,
          depth: depth,
          multipv: 2,
          threads: t,
          hashMb: h,
        ));
        sw.stop();
        await pipeline.dispose();
        if (result is! AnalysisCompleted) {
          stdout.writeln('| $depth | $t | $h | FAILED ($result) | | |');
          continue;
        }
        final s = sw.elapsedMilliseconds / 1000;
        stdout.writeln('| $depth | $t | $h | ${s.toStringAsFixed(1)} | ${(sw.elapsedMilliseconds / (moves.length + 1)).toStringAsFixed(0)} | $hashfull |');
      }
    }
  }
}

Future<String> _engineName() async {
  final driver = await ProcessEngineDriver.fromEnvironment();
  final name = driver.lines.firstWhere((l) => l.startsWith('id name '));
  driver.send('uci');
  final line = await name.timeout(const Duration(seconds: 10));
  await driver.dispose();
  return line.substring(8);
}
