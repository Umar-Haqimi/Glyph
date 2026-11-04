import 'dart:math' as math;

import 'package:dartchess/dartchess.dart' show Side;

import '../engine/score.dart';

/// Win% from centipawns, exactly as lichess computes it on the server
/// (scalachess `core/src/main/scala/eval.scala`, `WinPercent`; docs/m0/
/// algorithms.md 1.1):
///
/// * cp is clamped to `[-1000, 1000]` ([cpCeiling], `Cp.CEILING`, L57-69);
/// * `win = 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1)` (L101-110);
/// * **every mate counts as ±1000 cp**, whatever its distance (`fromScore`,
///   L95-98). (The lichess web client's gauge uses a distance-dependent
///   mapping; Glyph does not, so its accuracy matches the server's.)
///
/// This is the one Win% function of Glyph: classification, accuracy and the
/// eval bar all use it.
abstract final class WinPercent {
  /// `Cp.CEILING` in scalachess.
  static const int cpCeiling = 1000;

  /// The logistic multiplier (scalachess `winningChances`, lichess
  /// `ui/lib/src/ceval/winningChances.ts` L11).
  static const double multiplier = -0.00368208;

  /// Win% of the side the centipawns favour, 0..100.
  static double fromCp(int cp) {
    final c = cp.clamp(-cpCeiling, cpCeiling);
    final chances = (2 / (1 + math.exp(multiplier * c)) - 1).clamp(-1.0, 1.0);
    return 50 + 50 * chances;
  }

  /// Win% for a mate: positive [mate] (the scored side mates) is +1000 cp,
  /// zero or negative is -1000 cp (scalachess `fromScore`: `Mate(0)` means
  /// the scored side is mated).
  static double fromMate(int mate) => fromCp(mate > 0 ? cpCeiling : -cpCeiling);

  /// Win% of a decisive result that is already on the board (checkmate):
  /// the same number as a mate score, `fromCp(±1000)`, so a mating move and
  /// a mate-in-1 score agree (docs/DECISIONS.md, M4).
  static final double mateWin = fromCp(cpCeiling);

  /// White's Win% for a White-POV score.
  static double ofWhiteScore(WhiteScore score) {
    final cp = score.cp;
    if (cp != null) return fromCp(cp);
    return switch (score.mateWinner) {
      Side.white => fromCp(cpCeiling),
      Side.black => fromCp(-cpCeiling),
      // `mate 0` without a known winner never reaches the store (terminal
      // positions are not searched); treat it as unknown = level.
      null => 50,
    };
  }

  /// Converts White's Win% to [side]'s point of view.
  static double forSide(double whiteWin, Side side) => side == Side.white ? whiteWin : 100 - whiteWin;
}
