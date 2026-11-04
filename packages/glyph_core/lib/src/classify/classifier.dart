import 'package:dartchess/dartchess.dart';

import '../engine/analysis_job.dart' show replayPositions;
import '../engine/score.dart';
import '../engine/terminal.dart';
import '../engine/uci_parser.dart';
import '../game/ply.dart' show epdOfFen;
import 'classifier_config.dart';
import 'expected_points.dart';
import 'move_label.dart';
import 'see.dart';
import 'win_percent.dart';

/// The classification of one move (SPEC 2.1), with the numbers behind it.
///
/// All Win% values are from the **mover's** point of view (0..100); they are
/// what `move_labels.win_before` / `win_after` store.
class ClassifiedMove {
  const ClassifiedMove({
    required this.ply,
    required this.side,
    required this.uci,
    required this.label,
    this.epLoss,
    this.winBefore,
    this.winAfter,
    this.bestUci,
    this.isTopMove = false,
    this.sacrifice = false,
    this.onlyMove = false,
    this.missedMateIn,
    this.punishedOpponentError = false,
  });

  /// 1-based: the move that leads to position [ply].
  final int ply;
  final Side side;

  /// The played move, dartchess UCI (castling king-takes-rook).
  final String uci;
  final MoveLabel label;

  /// Expected-points loss, 0..1. Null when the engine data is missing (a
  /// Book move of an unanalysed position).
  final double? epLoss;

  /// `W_best_before`: Win% of the engine's best line before the move.
  final double? winBefore;

  /// `W_after`: Win% after the played move (see [Classifier] for its source).
  final double? winAfter;

  /// First move of the engine's best line before the move (engine UCI, which
  /// is dartchess UCI because the engine runs with `UCI_Chess960 = true`).
  final String? bestUci;

  /// The played move is the engine's top move.
  final bool isTopMove;

  /// The move is a sacrifice by the SEE rule (whatever its label).
  final bool sacrifice;

  /// Great: the only move that keeps the outcome bucket.
  final bool onlyMove;

  /// Set when the best line was a forced mate in at most
  /// [ClassifierConfig.missMateMaxMoves] for the mover and the move lost it.
  final int? missedMateIn;

  /// The opponent's previous move lost >= 0.10 EP and this move did not give
  /// it back (no Miss (a)).
  final bool punishedOpponentError;

  @override
  String toString() =>
      'ClassifiedMove($ply $uci ${label.name} ep=${epLoss?.toStringAsFixed(4)} '
      'win ${winBefore?.toStringAsFixed(2)} -> ${winAfter?.toStringAsFixed(2)} best=$bestUci)';
}

/// Win% data of one position of the game, White POV.
class PositionWin {
  const PositionWin({required this.position, required this.whiteWin, this.terminal, this.drawnByRule = false});

  final Position position;

  /// White's Win% (null when the position has no engine data).
  final double? whiteWin;
  final Terminal? terminal;

  /// The game ended here by threefold repetition or the 50-move rule.
  final bool drawnByRule;
}

/// Labels every move of a game from its per-position engine lines (SPEC 2.1).
///
/// ### Inputs
/// * [startFen] and [moves] (dartchess UCI), the same the pipeline analysed.
/// * `lines[ply]`: the engine lines of position `ply` (0 = start), White POV,
///   rank 1 first. A terminal position (checkmate, stalemate, insufficient
///   material) has no lines; it is recognised from the replayed position
///   with [detectTerminal], never from the stored marker row.
/// * `bookPlies`: the contiguous Book prefix (`OpeningBook.annotate`); 0 for
///   FEN-start and Chess960 games.
///
/// ### Win% of a position (one rule for classification and accuracy)
/// Rank-1 score through [WinPercent] (mates = ±1000 cp). Checkmate on the
/// board = the mate score of the winner ([WinPercent.mateWin]); stalemate,
/// insufficient material, and a **final** position that is a threefold
/// repetition or has the 50-move counter at 100 = 50.
///
/// ### `W_after` without phantom losses (trap 3)
/// Played move = line 1 -> `W_after = W_best_before`, loss exactly 0. Played
/// move = line 2 -> line 2's score from the same search. Otherwise the Win%
/// of the next position's own search. Moves are compared as normalised
/// dartchess `Move`s, never as strings (trap 2).
///
/// ### Precedence (first match wins)
/// Book, Forced, Brilliant, Great, Miss, Best, Excellent, Good, Inaccuracy,
/// Mistake, Blunder; the constants are in [ClassifierConfig].
class Classifier {
  const Classifier({this.config = ClassifierConfig.standard});

  final ClassifierConfig config;

  /// Per-position Win% data for [startFen] + [moves] (length `moves + 1`).
  static List<PositionWin> positionWins(String startFen, List<String> moves, Map<int, List<EngineLine>> lines) {
    final positions = replayPositions(startFen, moves);
    final counts = <String, int>{};
    final out = <PositionWin>[];
    for (var i = 0; i < positions.length; i++) {
      final p = positions[i];
      final key = epdOfFen(p.fen);
      final seen = counts[key] = (counts[key] ?? 0) + 1;
      final terminal = detectTerminal(p);
      final last = i == positions.length - 1;
      final drawnByRule = terminal == null && last && (seen >= 3 || p.halfmoves >= 100);
      out.add(PositionWin(
        position: p,
        whiteWin: _whiteWin(terminal, drawnByRule, lines[i]),
        terminal: terminal,
        drawnByRule: drawnByRule,
      ));
    }
    return out;
  }

  /// The one Win% rule of a position (White POV): the winner's mate score on
  /// a checkmate, 50 on a stalemate / dead position / final claimable draw,
  /// else the rank-1 line (null without one).
  static double? _whiteWin(Terminal? terminal, bool drawnByRule, List<EngineLine>? lines) {
    if (terminal != null) {
      return switch (terminal.winner) {
        Side.white => WinPercent.mateWin,
        Side.black => 100 - WinPercent.mateWin,
        null => 50,
      };
    }
    if (drawnByRule) return 50;
    final top = _rank(lines, 1);
    return top == null ? null : WinPercent.ofWhiteScore(top.score);
  }

  /// One entry per move (index 0 = ply 1). An entry is null when the engine
  /// data needed for it is missing (an unfinished analysis).
  List<ClassifiedMove?> classify({
    required String startFen,
    required List<String> moves,
    required Map<int, List<EngineLine>> lines,
    int bookPlies = 0,
  }) {
    final wins = positionWins(startFen, moves, lines);
    final out = <ClassifiedMove?>[];
    for (var ply = 1; ply <= moves.length; ply++) {
      out.add(_classifyMove(ply, wins, moves, lines, bookPlies, ply >= 2 ? out[ply - 2] : null));
    }
    return out;
  }

  ClassifiedMove? _classifyMove(
    int ply,
    List<PositionWin> wins,
    List<String> moves,
    Map<int, List<EngineLine>> lines,
    int bookPlies,
    ClassifiedMove? previous,
  ) {
    final before = wins[ply - 1];
    final after = wins[ply];
    final pos = before.position;
    final mover = pos.turn;
    final played = pos.normalizeMove(Move.parse(moves[ply - 1])! as NormalMove) as NormalMove;
    final uci = moves[ply - 1];
    final isBook = ply <= bookPlies;

    final line1 = _rank(lines[ply - 1], 1);
    final line2 = _rank(lines[ply - 1], 2);
    if (line1 == null) {
      return isBook ? ClassifiedMove(ply: ply, side: mover, uci: uci, label: MoveLabel.book) : null;
    }
    final best1 = _firstMove(pos, line1);
    final best2 = line2 == null ? null : _firstMove(pos, line2);
    final wBest = WinPercent.forSide(WinPercent.ofWhiteScore(line1.score), mover);
    final wLine2 = line2 == null ? null : WinPercent.forSide(WinPercent.ofWhiteScore(line2.score), mover);

    final isTop = best1 != null && best1 == played;
    final isSecond = !isTop && best2 != null && best2 == played;
    final double wAfter;
    if (isTop) {
      wAfter = wBest;
    } else if (isSecond) {
      wAfter = wLine2!;
    } else {
      final w = after.whiteWin;
      if (w == null) {
        return isBook ? ClassifiedMove(ply: ply, side: mover, uci: uci, label: MoveLabel.book) : null;
      }
      wAfter = WinPercent.forSide(w, mover);
    }
    final loss = isTop ? 0.0 : ExpectedPoints.loss(wBest, wAfter);

    final forced = _legalMoveCount(pos) == 1;
    final sacrifice = See.isSacrifice(pos, played, threshold: config.sacrificeMinGain);

    // Great: the only move that keeps the outcome.
    final obviousRecapture = previous != null && _isRecapture(wins[ply - 2].position, moves[ply - 2], played);
    // A checkmating move is Best, never Great (SPEC 7.1: "mate-in-1
    // delivered -> Best"), even when line 2 is far worse.
    final deliversMate = after.terminal?.kind == TerminalKind.checkmate;
    final onlyMove =
        isTop &&
        !deliversMate &&
        wLine2 != null &&
        wBest - wLine2 >= config.greatMinGap &&
        _bucket(wBest) != _bucket(wLine2) &&
        !obviousRecapture &&
        !forced;

    // Miss (a): the opponent erred, the reply gave most of it back.
    final opponentErred =
        previous != null &&
        previous.epLoss != null &&
        previous.winBefore != null &&
        previous.epLoss! >= config.missOpponentMinLoss;
    final missA =
        opponentErred &&
        loss >= config.missMinLoss &&
        wAfter <= (100 - previous.winBefore!) + config.missGiveBackMargin;

    // Miss (b): a forced mate in <= 5 was let go.
    final mateIn = _mateFor(line1.score, mover);
    final hadShortMate = mateIn != null && mateIn <= config.missMateMaxMoves;
    final keepsMate =
        isTop ||
        (isSecond && _mateFor(line2!.score, mover) != null) ||
        (after.terminal?.winner == mover) ||
        (!isSecond && !after.drawnByRule && _mateFor(_rank(lines[ply], 1)?.score, mover) != null);
    final missB = hadShortMate && !keepsMate && loss >= config.missMateMinLoss;

    final base = _baseLabel(loss, isTop: isTop, tiedSecond: isSecond && line2!.score == line1.score);

    final MoveLabel label;
    if (isBook) {
      label = MoveLabel.book;
    } else if (forced) {
      label = MoveLabel.forced;
    } else if (loss <= config.brilliantMaxLoss &&
        sacrifice &&
        wAfter >= config.brilliantMinWinAfter &&
        wBest <= config.brilliantMaxWinBefore) {
      label = MoveLabel.brilliant;
    } else if (onlyMove) {
      label = MoveLabel.great;
    } else if (missA || missB) {
      label = base == MoveLabel.blunder && wAfter <= config.missBlunderMaxWinAfter ? MoveLabel.blunder : MoveLabel.miss;
    } else {
      label = base;
    }

    return ClassifiedMove(
      ply: ply,
      side: mover,
      uci: uci,
      label: label,
      epLoss: loss,
      winBefore: wBest,
      winAfter: wAfter,
      bestUci: line1.pv.isEmpty ? null : line1.pv.first,
      isTopMove: isTop,
      sacrifice: sacrifice,
      onlyMove: onlyMove,
      missedMateIn: missB ? mateIn : null,
      punishedOpponentError: opponentErred && !missA,
    );
  }

  MoveLabel _baseLabel(double loss, {required bool isTop, required bool tiedSecond}) {
    if (isTop || tiedSecond) return MoveLabel.best;
    if (loss <= config.excellentMaxLoss) return MoveLabel.excellent;
    if (loss <= config.goodMaxLoss) return MoveLabel.good;
    if (loss <= config.inaccuracyMaxLoss) return MoveLabel.inaccuracy;
    if (loss <= config.mistakeMaxLoss) return MoveLabel.mistake;
    return MoveLabel.blunder;
  }

  int _bucket(double win) => win < config.losingBelow ? 0 : (win > config.winningAbove ? 2 : 1);

  static EngineLine? _rank(List<EngineLine>? lines, int rank) {
    if (lines == null) return null;
    for (final l in lines) {
      if (l.rank == rank) return l;
    }
    return null;
  }

  /// The first move of [line] as a normalised dartchess move, or null when the
  /// line is empty or its move is not legal here.
  static NormalMove? _firstMove(Position pos, EngineLine line) {
    if (line.pv.isEmpty) return null;
    final uci = line.pv.first;
    if (uci.length < 4 || uci.length > 5) return null;
    final m = Move.parse(uci);
    if (m is! NormalMove || !pos.isLegal(m)) return null;
    return pos.normalizeMove(m) as NormalMove;
  }

  /// Mate distance in moves for [side] (positive), or null if [score] is not
  /// a forced mate for [side].
  static int? _mateFor(WhiteScore? score, Side side) {
    final m = score?.mate;
    if (m == null || m == 0) return null;
    if (side == Side.white) return m > 0 ? m : null;
    return m < 0 ? -m : null;
  }

  static int _legalMoveCount(Position pos) {
    var n = 0;
    final board = pos.board;
    for (final MapEntry(key: from, value: dests) in pos.legalMoves.entries) {
      final pawn = board.roleAt(from) == Role.pawn;
      for (final to in dests.squares) {
        n += pawn && (to.rank == Rank.first || to.rank == Rank.eighth) ? 4 : 1;
      }
    }
    return n;
  }

  /// SPEC 2.1 Great 4: the move captures on the square where the opponent's
  /// previous move ([previousUci], played in [previousPos]) captured.
  static bool _isRecapture(Position previousPos, String previousUci, NormalMove played) {
    final prev = Move.parse(previousUci);
    if (prev is! NormalMove) return false;
    final normalized = previousPos.normalizeMove(prev) as NormalMove;
    if (!See.isCapture(previousPos, normalized)) return false;
    return normalized.to == played.to;
  }
}

/// [Classifier.classify] kept up to date as engine positions arrive, without
/// redoing the work for the whole game (the analysis board needs a fresh
/// label set after every position the engine finishes).
///
/// The game is replayed once, in the constructor. [setLines] then recomputes
/// only what depends on the new position `p`: the Win% of `p`, and the labels
/// of ply `p` (its "after" position) and ply `p + 1` (its "before" position).
/// A label also reads the previous label (the Miss and Great rules), so the
/// recomputation goes on past those two plies only while a label really
/// changed. It is the same code as [Classifier.classify], so after any
/// sequence of [setLines] calls [moves] equals a from-scratch classification
/// of the same lines (tested with Book and Miss).
class IncrementalClassifier {
  IncrementalClassifier({
    required this.startFen,
    required List<String> moves,
    this.bookPlies = 0,
    ClassifierConfig config = ClassifierConfig.standard,
  })  : _uci = List.unmodifiable(moves),
        _classifier = Classifier(config: config) {
    _wins = Classifier.positionWins(startFen, _uci, const {});
    // Book moves are labelled without engine data.
    _moves = _classifier.classify(startFen: startFen, moves: _uci, lines: const {}, bookPlies: bookPlies);
  }

  final String startFen;
  final int bookPlies;
  final List<String> _uci;
  final Classifier _classifier;
  final Map<int, List<EngineLine>> _lines = {};
  late final List<PositionWin> _wins;
  late final List<ClassifiedMove?> _moves;

  int get plyCount => _uci.length;

  /// Engine lines per position stored so far (see [setLines]); live.
  Map<int, List<EngineLine>> get lines => _lines;

  /// Per-position Win% data (`plyCount + 1` entries); live, copy to keep.
  List<PositionWin> get wins => _wins;

  /// One entry per ply (index 0 = ply 1); live, copy to keep.
  List<ClassifiedMove?> get moves => _moves;

  /// Stores the engine lines of position [position] (0 = start; an empty list
  /// for a terminal marker) and updates the Win% and the labels it affects.
  /// Setting the same lines again changes nothing.
  void setLines(int position, List<EngineLine> lines) {
    if (position < 0 || position > plyCount) return;
    _lines[position] = lines;
    final w = _wins[position];
    _wins[position] = PositionWin(
      position: w.position,
      whiteWin: Classifier._whiteWin(w.terminal, w.drawnByRule, lines),
      terminal: w.terminal,
      drawnByRule: w.drawnByRule,
    );
    for (var ply = position < 1 ? 1 : position; ply <= plyCount; ply++) {
      final old = _moves[ply - 1];
      final updated = _classifier._classifyMove(
        ply,
        _wins,
        _uci,
        _lines,
        bookPlies,
        ply >= 2 ? _moves[ply - 2] : null,
      );
      _moves[ply - 1] = updated;
      if (ply > position && _sameForSuccessor(old, updated)) break;
    }
  }

  /// What the next ply's classification reads from this one.
  static bool _sameForSuccessor(ClassifiedMove? a, ClassifiedMove? b) {
    if (a == null || b == null) return a == null && b == null;
    return a.label == b.label && a.epLoss == b.epLoss && a.winBefore == b.winBefore;
  }
}
