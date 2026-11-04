import 'dart:io';

import 'package:dartchess/dartchess.dart' show Move, kInitialFEN;
import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/testing.dart';

import 'transcripts.dart';

/// Runs the real [AnalysisPipeline] over [startFen] + [moves] with the
/// recorded transcript [transcript] replayed by a [FakeEngineDriver] (fails
/// loudly on any position the transcript does not hold), and returns the
/// stored engine lines per position, exactly what the app persists.
Future<Map<int, List<EngineLine>>> analyseFromTranscript(
  String transcript, {
  required String startFen,
  required List<String> moves,
}) =>
    analyseWith(loadTranscript(transcript), startFen: startFen, moves: moves, label: transcript);

/// [analyseFromTranscript] with a [Transcript] object.
Future<Map<int, List<EngineLine>>> analyseWith(
  Transcript transcript, {
  required String startFen,
  required List<String> moves,
  String label = 'transcript',
}) async {
  final store = InMemoryAnalysisStore();
  final pipeline = AnalysisPipeline(
    createDriver: () async => FakeEngineDriver(transcript),
    store: store,
    timeouts: fastTimeouts,
  );
  final result = await pipeline.analyze(AnalysisRequest(
    gameId: 1,
    startFen: startFen,
    moves: moves,
    depth: 16,
    multipv: 2,
    threads: 1,
    hashMb: 16,
  ));
  await pipeline.dispose();
  if (result is! AnalysisCompleted) throw StateError('analysis of $label did not complete: $result');
  return {
    for (final MapEntry(key: (_, ply), value: p) in store.positions.entries) ply: p.lines,
  };
}

/// [analyseFromTranscript] for a game listed in games.json, then classified.
Future<List<ClassifiedMove?>> classifyTranscriptGame(
  String name, {
  int bookPlies = 0,
  ClassifierConfig config = ClassifierConfig.standard,
}) async {
  final g = transcriptGame(name);
  final lines = await analyseFromTranscript(name, startFen: g.startFen, moves: g.moves);
  return Classifier(config: config).classify(startFen: g.startFen, moves: g.moves, lines: lines, bookPlies: bookPlies);
}

/// A [Game] built from [startFen] + dartchess UCI [moves] (no headers), for
/// [reviewGame] and [OpeningBook.annotate].
Game gameFrom(String startFen, List<String> moves, {GameVariant variant = GameVariant.standard}) {
  final positions = replayPositions(startFen, moves);
  return Game(
    headers: const {},
    startFen: startFen,
    variant: variant,
    plies: [
      for (var i = 0; i < moves.length; i++)
        Ply(
          number: i + 1,
          san: positions[i].makeSan(Move.parse(moves[i])!).$2,
          uci: moves[i],
          fen: positions[i + 1].fen,
        ),
    ],
    result: '*',
    pgn: '',
  );
}

/// The bundled openings asset (the same file the app ships).
OpeningBook realOpeningBook() => OpeningBook.parseTsv(File('../../app/assets/openings.tsv').readAsStringSync());

/// The colour-mirrored transcript of a game recorded from [startFen]: every
/// `position` command is mirrored (board flipped, colours swapped, moves
/// mirrored) and so is every move in the engine output. Scores stay as they
/// are, because UCI scores are from the side to move, which is mirrored too.
Transcript mirrorTranscript(Transcript t) {
  String mirrorMoves(List<String> ms) => ms.map(mirrorUci).join(' ');
  String mirrorPosition(String cmd) {
    final tokens = cmd.split(' ');
    final movesAt = tokens.indexOf('moves');
    final head = movesAt < 0 ? tokens : tokens.sublist(0, movesAt);
    final fen = head[1] == 'startpos' ? kInitialFEN : head.sublist(2).join(' ');
    final base = 'position fen ${mirrorFen(fen)}';
    return movesAt < 0 ? base : '$base moves ${mirrorMoves(tokens.sublist(movesAt + 1))}';
  }

  String mirrorLine(String line) {
    final tokens = line.split(' ');
    if (tokens.first == 'bestmove') {
      return [for (final x in tokens) RegExp(r'^[a-h][1-8][a-h][1-8][qrbn]?$').hasMatch(x) ? mirrorUci(x) : x].join(' ');
    }
    final pv = tokens.indexOf('pv');
    if (tokens.first != 'info' || pv < 0) return line;
    return [...tokens.sublist(0, pv + 1), mirrorMoves(tokens.sublist(pv + 1))].join(' ');
  }

  final out = Transcript(header: [...t.header, 'colour-mirrored by mirrorTranscript (test support)']);
  for (final MapEntry(key: key, value: lines) in t.entries.entries) {
    final [position, go] = key.split('\n');
    out.add(mirrorPosition(position), go, [for (final l in lines) mirrorLine(l)]);
  }
  return out;
}
