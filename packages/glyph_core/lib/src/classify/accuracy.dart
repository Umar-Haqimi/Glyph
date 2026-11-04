import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side;

import 'win_percent.dart';

/// Accuracy per player, 0..100 (unrounded; display with [Accuracy.display]).
class GameAccuracy {
  const GameAccuracy({this.white, this.black});

  static const none = GameAccuracy();

  final double? white;
  final double? black;

  double? of(Side side) => side == Side.white ? white : black;

  @override
  String toString() => 'GameAccuracy(white: $white, black: $black)';
}

/// Lichess's accuracy, exactly (lila `modules/analyse/src/main/
/// AccuracyPercent.scala`, docs/m0/algorithms.md 1.2-1.3).
abstract final class Accuracy {
  /// lichess's legacy initial evaluation when the analysis has none (+15 cp,
  /// lila `tree/eval.scala` L30). Glyph uses its own start-position search.
  static const int lichessInitialCp = 15;

  static const double _a = 103.1668100711649;
  static const double _k = -0.04354415386753951;
  static const double _b = -3.166924740191411;

  /// Accuracy of one move from the mover's Win% before and after it
  /// (`AccuracyPercent.fromWinPercents`, L47-54): 100 when the mover did not
  /// lose anything, else `103.1668... * exp(-0.04354... * d) - 3.1669... + 1`
  /// (the +1 "uncertainty bonus") clamped to `[0, 100]`.
  static double ofMove(double before, double after) {
    if (after >= before) return 100;
    final d = before - after;
    final raw = _a * math.exp(_k * d) + _b;
    return (raw + 1).clamp(0.0, 100.0);
  }

  /// Game accuracy per player (`AccuracyPercent.gameAccuracy`, L79-113).
  ///
  /// [whiteWins] are White's Win% of the start position and of the position
  /// after every ply (`plies + 1` entries; a shorter list simply ends the
  /// game earlier, e.g. lichess omits the final checkmate position). A null
  /// entry is a missing evaluation: its windows and moves are skipped.
  /// [startSide] moves first (Black for a FEN start with Black to move).
  ///
  /// Volatility-weighted mean and harmonic mean of the per-move accuracies,
  /// averaged. The window is `clamp(plies ~/ 10, 2, 8)` positions; a move's
  /// weight is the population standard deviation of its window clamped to
  /// `[0.5, 12]`. Returns [GameAccuracy.none] unless both players moved.
  static GameAccuracy ofGame(List<double?> whiteWins, {Side startSide = Side.white}) {
    final n = whiteWins.length;
    if (n < 2) return GameAccuracy.none;
    final plies = n - 1;
    final ws = (plies ~/ 10).clamp(2, 8);

    // Windows: (min(ws, n) - 2) copies of the first window, then every
    // sliding window (one window of everything when n < ws): n - 1 in all.
    final windows = <List<double?>>[];
    final head = whiteWins.take(ws).toList();
    for (var i = 0; i < math.min(ws, n) - 2; i++) {
      windows.add(head);
    }
    if (n < ws) {
      windows.add(whiteWins);
    } else {
      for (var i = 0; i + ws <= n; i++) {
        windows.add(whiteWins.sublist(i, i + ws));
      }
    }
    final weights = [for (final w in windows) w.contains(null) ? null : _stdDev(w.cast<double>()).clamp(0.5, 12.0)];

    final acc = {Side.white: <double>[], Side.black: <double>[]};
    final wts = {Side.white: <double>[], Side.black: <double>[]};
    for (var i = 0; i < n - 1; i++) {
      final prev = whiteWins[i];
      final next = whiteWins[i + 1];
      final weight = i < weights.length ? weights[i] : null;
      if (prev == null || next == null || weight == null) continue;
      final white = (i % 2 == 0) == (startSide == Side.white);
      final side = white ? Side.white : Side.black;
      // lila: fromWinPercents(color.fold(prev, next), color.fold(next, prev))
      final a = white ? ofMove(prev, next) : ofMove(next, prev);
      acc[side]!.add(a);
      wts[side]!.add(weight);
    }
    if (acc[Side.white]!.isEmpty || acc[Side.black]!.isEmpty) return GameAccuracy.none;
    double? result(Side s) {
      final xs = acc[s]!;
      final ws = wts[s]!;
      var sw = 0.0, sxw = 0.0, inv = 0.0;
      for (var i = 0; i < xs.length; i++) {
        sxw += xs[i] * ws[i];
        sw += ws[i];
        inv += 1 / math.max(1, xs[i]);
      }
      if (sw == 0) return null;
      final weighted = sxw / sw;
      final harmonic = xs.length / inv;
      return (weighted + harmonic) / 2;
    }

    return GameAccuracy(white: result(Side.white), black: result(Side.black));
  }

  /// [ofGame] from White-POV centipawns (mates already mapped to ±1000 or
  /// any |cp| >= 1000), with lichess's initial +15 cp prepended when
  /// [initialCp] is given.
  static GameAccuracy ofCentipawns(List<int?> whiteCps, {Side startSide = Side.white, int? initialCp}) => ofGame([
    if (initialCp != null) WinPercent.fromCp(initialCp),
    for (final cp in whiteCps) cp == null ? null : WinPercent.fromCp(cp),
  ], startSide: startSide);

  /// Display value: rounded half up like scalalib's `Percent.toInt`
  /// (`Math.round`).
  static int display(double accuracy) => (accuracy + 0.5).floor();

  static double _stdDev(List<double> xs) {
    final mean = xs.reduce((a, b) => a + b) / xs.length;
    var sum = 0.0;
    for (final x in xs) {
      sum += (x - mean) * (x - mean);
    }
    return math.sqrt(sum / xs.length);
  }
}
