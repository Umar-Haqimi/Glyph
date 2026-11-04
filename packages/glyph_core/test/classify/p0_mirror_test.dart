// SPEC trap 1 / acceptance 9 P0: the same blunder, mirrored for both
// colours, must give the same label and mirrored evals.
import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import '../support/review.dart';
import '../support/transcripts.dart';

class _Run {
  _Run(this.game, this.moves, this.wins, this.accuracy);

  final TranscriptGame game;
  final List<ClassifiedMove?> moves;
  final List<PositionWin> wins;
  final GameAccuracy accuracy;
}

Future<_Run> _classify(TranscriptGame g, Transcript t) async {
  final lines = await analyseWith(t, startFen: g.startFen, moves: g.moves, label: g.name);
  // No opening book: the White game would be Book in the opening and the
  // mirrored one (a FEN start) never is; P0 is about the point of view.
  final review = reviewGame(gameFrom(g.startFen, g.moves), lines);
  return _Run(g, review.moves, Classifier.positionWins(g.startFen, g.moves, lines), review.accuracy);
}

void main() {
  group('P0 exact mirror (the engine output mirrored move by move)', () {
    for (final (white, black) in [('blunder_white', 'blunder_black'), ('p0_blunder_white', 'p0_blunder_black')]) {
      test('$white vs its mirror: identical labels and numbers, mirrored White-POV evals', () async {
        final w = await _classify(transcriptGame(white), loadTranscript(white));
        final b = await _classify(transcriptGame(black), mirrorTranscript(loadTranscript(white)));
        expect(b.game.startFen, startsWith('rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR b'));
        expect(w.moves, hasLength(b.moves.length));
        for (var i = 0; i < w.moves.length; i++) {
          final mw = w.moves[i]!, mb = b.moves[i]!;
          expect(mb.side, mw.side.opposite);
          expect(mb.label, mw.label, reason: 'ply ${i + 1}');
          expect(mb.epLoss, closeTo(mw.epLoss!, 1e-12));
          expect(mb.winBefore, closeTo(mw.winBefore!, 1e-9));
          expect(mb.winAfter, closeTo(mw.winAfter!, 1e-9));
          expect(mb.bestUci, mirrorUci(mw.bestUci!));
        }
        for (var i = 0; i < w.wins.length; i++) {
          expect(b.wins[i].whiteWin, closeTo(100 - w.wins[i].whiteWin!, 1e-9), reason: 'position $i');
        }
        expect(b.accuracy.black, closeTo(w.accuracy.white!, 1e-9));
        expect(b.accuracy.white, closeTo(w.accuracy.black!, 1e-9));
      });
    }

    test('the White game really contains a blunder that the mirror labels the same', () async {
      final w = await _classify(transcriptGame('p0_blunder_white'), loadTranscript('p0_blunder_white'));
      final b = await _classify(transcriptGame('p0_blunder_black'), mirrorTranscript(loadTranscript('p0_blunder_white')));
      expect(w.moves[5]!.label, MoveLabel.blunder, reason: '3...Nf6?? allows Qxf7#');
      expect(b.moves[5]!.label, MoveLabel.blunder, reason: '3.Nf3?? allows Qxf2#');
      expect(w.moves[5]!.side, Side.black);
      expect(b.moves[5]!.side, Side.white);
    });
  });

  group('P0 recorded pairs (both colours searched by Stockfish)', () {
    // Stockfish is not colour-symmetric at a fixed depth (move ordering
    // depends on square order), so two genuine searches of mirrored positions
    // differ by a few Win% points (up to ~3 here; the tolerance is 5). The labels that sit right on a band edge
    // can then differ; these plies are listed (engine noise, not a POV bug).
    // A point-of-view bug would flip whole evaluations (97 vs 3).
    final cases = {
      // Stockfish 19. 6: the two searches pick different (equal) top moves;
      // 10: 0.064 vs 0.101 EP; 15: line-2 gap just under / over 20.
      ('blunder_white', 'blunder_black'): {6, 10, 15},
      ('p0_blunder_white', 'p0_blunder_black'): {5}, // Stockfish 16: 0.052 vs 0.047 EP
    };
    for (final MapEntry(key: (white, black), value: noise) in cases.entries) {
      test('$white / $black', () async {
        final w = await _classify(transcriptGame(white), loadTranscript(white));
        final b = await _classify(transcriptGame(black), loadTranscript(black));
        for (var i = 0; i < w.moves.length; i++) {
          final ply = i + 1;
          final mw = w.moves[i]!, mb = b.moves[i]!;
          expect(mb.side, mw.side.opposite);
          if (!noise.contains(ply)) expect(mb.label, mw.label, reason: 'ply $ply: $mw / $mb');
          expect((mb.winBefore! - mw.winBefore!).abs(), lessThan(5), reason: 'mover-POV Win% before, ply $ply');
          expect((mb.winAfter! - mw.winAfter!).abs(), lessThan(5), reason: 'mover-POV Win% after, ply $ply');
        }
        for (var i = 0; i < w.wins.length; i++) {
          expect((b.wins[i].whiteWin! - (100 - w.wins[i].whiteWin!)).abs(), lessThan(5), reason: 'mirrored eval, position $i');
        }
      });
    }

    test('the decisive moves agree: Blunder, then the mate is Best', () async {
      final w = await _classify(transcriptGame('p0_blunder_white'), loadTranscript('p0_blunder_white'));
      final b = await _classify(transcriptGame('p0_blunder_black'), loadTranscript('p0_blunder_black'));
      expect([w.moves[5]!.label, w.moves[6]!.label], [MoveLabel.blunder, MoveLabel.best]);
      expect([b.moves[5]!.label, b.moves[6]!.label], [MoveLabel.blunder, MoveLabel.best]);
      final m3 = await _classify(transcriptGame('blunder_white'), loadTranscript('blunder_white'));
      final m3b = await _classify(transcriptGame('blunder_black'), loadTranscript('blunder_black'));
      expect(m3.moves[10]!.label, MoveLabel.brilliant, reason: '6.Nxf7');
      expect(m3b.moves[10]!.label, MoveLabel.brilliant, reason: '6...Nxf2');
    });
  });
}
