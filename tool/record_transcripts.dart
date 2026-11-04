// Records raw Stockfish output for the games in
// packages/glyph_core/test/vectors/uci_transcripts/games.json, one
// <name>.txt per game, by running the real AnalysisPipeline against a desktop
// engine ($STOCKFISH_PATH): Threads=1, Hash=16, MultiPV=2, `go depth 16`, full
// move history (SPEC 7.1 item 3).
//
// Usage (from the repo root, after `source ~/development/glyph-env.sh`):
//   dart run tool/record_transcripts.dart                 # records games without a transcript
//   dart run tool/record_transcripts.dart --force         # re-records everything
//   dart run tool/record_transcripts.dart name1 name2     # only these games (re-recorded)
//   dart run tool/record_transcripts.dart --depth 12      # other depth (default 16)
import 'dart:io';

import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/glyph_core_host.dart';

const _dir = 'packages/glyph_core/test/vectors/uci_transcripts';

Future<void> main(List<String> args) async {
  var force = false;
  var depth = 16;
  final only = <String>{};
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--force':
        force = true;
      case '--depth':
        depth = int.parse(args[++i]);
      default:
        only.add(args[i]);
    }
  }
  if ((Platform.environment['STOCKFISH_PATH'] ?? '').isEmpty) {
    stderr.writeln('STOCKFISH_PATH is not set (source ~/development/glyph-env.sh)');
    exitCode = 2;
    return;
  }

  final games = parseTranscriptGames(await File('$_dir/games.json').readAsString());
  for (final g in games) {
    if (only.isNotEmpty && !only.contains(g.name)) continue;
    final out = File('$_dir/${g.name}.txt');
    if (only.isEmpty && !force && out.existsSync()) {
      stdout.writeln('skip   ${g.name} (exists)');
      continue;
    }
    final transcript = Transcript();
    var engineName = 'Stockfish';
    final pipeline = AnalysisPipeline(
      createDriver: () async {
        final inner = await ProcessEngineDriver.fromEnvironment();
        inner.lines.listen((l) {
          if (l.startsWith('id name ')) engineName = l.substring(8);
        });
        return RecordingEngineDriver(inner, transcript);
      },
      store: InMemoryAnalysisStore(),
      timeouts: const PipelineTimeouts(searchIdle: Duration(minutes: 5), handshake: Duration(seconds: 30)),
    );
    final result = await pipeline.analyze(AnalysisRequest(
      gameId: 1,
      startFen: g.startFen,
      moves: g.moves,
      depth: depth,
      multipv: 2,
      threads: 1,
      hashMb: 16,
    ));
    await pipeline.dispose();
    if (result is! AnalysisCompleted) {
      stderr.writeln('FAILED ${g.name}: $result');
      exitCode = 1;
      continue;
    }
    transcript.header
      ..add('$engineName, Threads=1 Hash=16 MultiPV=2 UCI_Chess960=true, go depth $depth')
      ..add('game: ${g.name}')
      ..add('startFen: ${g.startFen}')
      ..add('moves: ${g.moves.join(' ')}');
    await out.writeAsString(transcript.serialize());
    stdout.writeln('wrote  ${out.path} (${transcript.entries.length} searches)');
  }
}
