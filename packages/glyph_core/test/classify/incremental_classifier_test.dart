import 'dart:math';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import '../support/review.dart';
import '../support/transcripts.dart';

/// Legal moves with queen promotions only (all the fuzz needs).
List<NormalMove> _legal(Position p) {
  final out = <NormalMove>[];
  for (final e in p.legalMoves.entries) {
    for (final to in e.value.squares) {
      final pawn = p.board.roleAt(e.key) == Role.pawn;
      out.add(pawn && (to.rank == Rank.first || to.rank == Rank.eighth)
          ? NormalMove(from: e.key, to: to, promotion: Role.queen)
          : NormalMove(from: e.key, to: to));
    }
  }
  return out;
}

/// A random game that avoids captures and ends; plus random 2-line "engine"
/// output for every position (top move often the played one, some mates), so
/// that all labels incl. Miss, Great and Brilliant turn up over many games.
({List<String> moves, Map<int, List<EngineLine>> lines}) _randomGame(Random r, int n) {
  Position p = Chess.initial;
  final moves = <String>[];
  final positions = <Position>[p];
  while (moves.length < n) {
    final ms = _legal(p)..shuffle(r);
    final pick = ms.firstWhere((m) {
      final nx = p.play(m);
      return !nx.isGameOver && !nx.isInsufficientMaterial;
    }, orElse: () => ms.first);
    moves.add(pick.uci);
    p = p.play(pick);
    positions.add(p);
    if (p.isGameOver) break;
  }
  final lines = <int, List<EngineLine>>{};
  for (var i = 0; i < positions.length; i++) {
    final pos = positions[i];
    if (pos.isGameOver || pos.isInsufficientMaterial) {
      lines[i] = [];
      continue;
    }
    final ms = _legal(pos)..shuffle(r);
    String pv(NormalMove first) => first.uci;
    final playedFirst = i < moves.length && r.nextDouble() < 0.45;
    final m1 = playedFirst ? Move.parse(moves[i])! as NormalMove : ms.first;
    var m2 = ms.length > 1 ? ms[1] : ms.first;
    if (i < moves.length && !playedFirst && r.nextDouble() < 0.25) m2 = Move.parse(moves[i])! as NormalMove;
    int? mate;
    int? cp;
    if (r.nextDouble() < 0.08) {
      mate = (r.nextInt(5) + 1) * (r.nextBool() ? 1 : -1);
    } else {
      cp = (r.nextDouble() * 1200 - 600).round();
    }
    final cp2 = (cp ?? 0) - r.nextInt(400);
    lines[i] = [
      EngineLine(rank: 1, score: mate != null ? WhiteScore.mate(mate) : WhiteScore.cp(cp!), depth: 16, pv: [pv(m1)]),
      EngineLine(rank: 2, score: WhiteScore.cp(cp2), depth: 16, pv: [pv(m2)]),
    ];
  }
  return (moves: moves, lines: lines);
}

void _expectSame(IncrementalClassifier inc, List<ClassifiedMove?> scratch, List<PositionWin> scratchWins, String reason) {
  expect(inc.moves, hasLength(scratch.length), reason: reason);
  for (var i = 0; i < scratch.length; i++) {
    final a = inc.moves[i];
    final b = scratch[i];
    expect(a == null, b == null, reason: '$reason ply ${i + 1} null-ness');
    if (a == null || b == null) continue;
    expect(a.label, b.label, reason: '$reason ply ${i + 1} label');
    expect(a.epLoss, b.epLoss, reason: '$reason ply ${i + 1} epLoss');
    expect(a.winBefore, b.winBefore, reason: '$reason ply ${i + 1} winBefore');
    expect(a.winAfter, b.winAfter, reason: '$reason ply ${i + 1} winAfter');
    expect(a.bestUci, b.bestUci, reason: '$reason ply ${i + 1} bestUci');
    expect(a.isTopMove, b.isTopMove);
    expect(a.sacrifice, b.sacrifice);
    expect(a.onlyMove, b.onlyMove);
    expect(a.missedMateIn, b.missedMateIn);
    expect(a.punishedOpponentError, b.punishedOpponentError);
  }
  for (var i = 0; i < scratchWins.length; i++) {
    expect(inc.wins[i].whiteWin, scratchWins[i].whiteWin, reason: '$reason win $i');
    expect(inc.wins[i].drawnByRule, scratchWins[i].drawnByRule);
  }
}

void main() {
  const classifier = Classifier();

  group('IncrementalClassifier == Classifier.classify on every prefix', () {
    test('recorded Opera game (Book prefix, Brilliant, Great, Forced, mate)', () async {
      final g = transcriptGame('mate_opera');
      final lines = await analyseFromTranscript('mate_opera', startFen: g.startFen, moves: g.moves);
      final game = gameFrom(g.startFen, g.moves);
      final book = realOpeningBook().annotate(game);
      expect(book.bookPlies, 7);
      final inc = IncrementalClassifier(startFen: g.startFen, moves: g.moves, bookPlies: book.bookPlies);
      // Before any engine data only the Book moves are labelled.
      expect(inc.moves.where((m) => m != null), hasLength(7));
      final seen = <MoveLabel>{};
      for (var k = 0; k < g.moves.length + 1; k++) {
        inc.setLines(k, lines[k] ?? const []);
        final prefix = {for (final e in lines.entries) if (e.key <= k) e.key: e.value};
        final scratch = classifier.classify(startFen: g.startFen, moves: g.moves, lines: prefix, bookPlies: book.bookPlies);
        _expectSame(inc, scratch, Classifier.positionWins(g.startFen, g.moves, prefix), 'prefix $k');
        seen.addAll([for (final m in inc.moves) ?m?.label]);
      }
      expect(seen, containsAll([MoveLabel.book, MoveLabel.brilliant, MoveLabel.forced]));
    });

    test('random games with Miss / Great / Brilliant, in order, shuffled and repeated', () {
      final r = Random(11);
      final seen = <MoveLabel>{};
      for (var g = 0; g < 60; g++) {
        final game = _randomGame(r, 30 + r.nextInt(30));
        final bookPlies = g % 4;
        final n = game.moves.length;
        final inc = IncrementalClassifier(startFen: kInitialFEN, moves: game.moves, bookPlies: bookPlies);
        // Every third game: positions arrive in a shuffled order.
        final order = [for (var k = 0; k <= n; k++) k];
        if (g % 3 == 2) order.shuffle(r);
        final have = <int, List<EngineLine>>{};
        for (final k in order) {
          inc.setLines(k, game.lines[k]!);
          if (g % 5 == 0) inc.setLines(k, game.lines[k]!); // idempotent
          have[k] = game.lines[k]!;
          final scratch = classifier.classify(startFen: kInitialFEN, moves: game.moves, lines: have, bookPlies: bookPlies);
          _expectSame(inc, scratch, Classifier.positionWins(kInitialFEN, game.moves, have), 'game $g after $k');
        }
        seen.addAll([for (final m in inc.moves) ?m?.label]);
      }
      expect(seen, containsAll([MoveLabel.miss, MoveLabel.great, MoveLabel.book, MoveLabel.blunder, MoveLabel.best]));
    });

    test('a final threefold repetition is a draw at the last position only', () {
      // 1. Nf3 Nf6 2. Ng1 Ng8 3. Nf3 Nf6 4. Ng1 Ng8: the start position, third time.
      final moves = ['g1f3', 'g8f6', 'f3g1', 'f6g8', 'g1f3', 'g8f6', 'f3g1', 'f6g8'];
      final inc = IncrementalClassifier(startFen: kInitialFEN, moves: moves);
      expect(inc.wins.last.drawnByRule, isTrue);
      expect(inc.wins.last.whiteWin, 50);
      expect(inc.wins[4].drawnByRule, isFalse);
      expect(inc.wins[4].whiteWin, isNull);
    });
  });
}
