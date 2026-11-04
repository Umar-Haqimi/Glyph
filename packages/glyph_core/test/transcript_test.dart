import 'dart:io';

import 'package:dartchess/dartchess.dart' show kInitialFEN;
import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import 'support/transcripts.dart';

void main() {
  test('transcript text format round-trips', () {
    final t = loadTranscript('italian_castle');
    expect(t.header.first, startsWith('Stockfish 19'));
    final again = Transcript.parse(t.serialize());
    expect(again.entries.keys.toList(), t.entries.keys.toList());
    expect(again.entries.values.first, t.entries.values.first);
    expect(again.header, t.header);
  });

  test('every transcript matches its games.json entry and ends each search with bestmove', () {
    final games = transcriptGames();
    expect(games.length, greaterThanOrEqualTo(6));
    for (final g in games) {
      final t = loadTranscript(g.name);
      expect(t.header, contains('moves: ${g.moves.join(' ')}'), reason: g.name);
      expect(t.entries, isNotEmpty);
      for (final out in t.entries.values) {
        expect(out.last, startsWith('bestmove'), reason: g.name);
      }
      expect(File('$transcriptDir/${g.name}.txt').existsSync(), isTrue);
    }
  });

  test('required coverage: castling, promotion, mirrored pair, repetition, stalemate, mate', () {
    final byName = {for (final g in transcriptGames()) g.name: g};
    expect(byName['italian_castle']!.moves, containsAll(['e1h1', 'e8h8']));
    expect(byName['promotion']!.moves.first, 'e7e8q');
    expect(byName['blunder_black']!.moves, [for (final m in byName['blunder_white']!.moves) mirrorUci(m)]);
    expect(byName['repetition']!.moves.length, 8);
    expect(byName.keys, containsAll(['stalemate', 'mate_opera', 'queens_gambit']));
  });

  test('mirrorFen / mirrorUci', () {
    expect(mirrorFen(kInitialFEN), 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b KQkq - 0 1');
    expect(mirrorFen(mirrorFen('r3k2r/8/8/8/4P3/8/8/R3K2R w Kq e3 0 5')), 'r3k2r/8/8/8/4P3/8/8/R3K2R w Kq e3 0 5');
    expect(mirrorFen('r3k2r/8/8/8/4P3/8/8/R3K2R w Kq e3 0 5'), 'r3k2r/8/8/4p3/8/8/8/R3K2R b Qk e6 0 5');
    expect(mirrorUci('e2e4'), 'e7e5');
    expect(mirrorUci('e7e8q'), 'e2e1q');
  });

  test('parseTranscriptGames: SAN or UCI, bad moves are rejected', () {
    final g = parseTranscriptGames('[{"name":"a","moves":"e4 e7e5 Nf3"}]').single;
    expect(g.moves, ['e2e4', 'e7e5', 'g1f3']);
    expect(() => parseTranscriptGames('[{"name":"a","moves":"e5"}]'), throwsFormatException);
  });
}
