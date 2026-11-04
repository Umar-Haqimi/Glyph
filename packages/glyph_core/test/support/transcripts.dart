import 'dart:io';

import 'package:glyph_core/glyph_core.dart';

const transcriptDir = 'test/vectors/uci_transcripts';

List<TranscriptGame> transcriptGames() =>
    parseTranscriptGames(File('$transcriptDir/games.json').readAsStringSync());

TranscriptGame transcriptGame(String name) => transcriptGames().firstWhere((g) => g.name == name);

Transcript loadTranscript(String name) =>
    Transcript.parse(File('$transcriptDir/$name.txt').readAsStringSync());

/// Request matching how the transcripts were recorded.
AnalysisRequest requestFor(TranscriptGame g, {int gameId = 1, int depth = 16}) => AnalysisRequest(
      gameId: gameId,
      startFen: g.startFen,
      moves: g.moves,
      depth: depth,
      multipv: 2,
      threads: 1,
      hashMb: 16,
    );

/// A [Transcript] of the named game ready for a [FakeEngineDriver].
FakeEngineDriver fakeFor(String name) => FakeEngineDriver(loadTranscript(name));

/// Pipeline timeouts that keep failing tests fast.
const fastTimeouts = PipelineTimeouts(
  handshake: Duration(seconds: 2),
  stop: Duration(milliseconds: 100),
  searchIdle: Duration(seconds: 2),
);
