/// Every numeric constant of the move classifier (SPEC 2.1), in one place.
///
/// Win% values are 0..100 from the mover's point of view; expected-points
/// (EP) losses are 0..1. Bands are lower-exclusive and upper-inclusive: a loss
/// of exactly 0.05 is Good, 0.0500001 is an Inaccuracy.
///
/// Changing any value (or the rules in `Classifier`) must bump [version]: the
/// app stores it as `classifier_version` and re-labels every analysed game
/// from the stored engine lines when it changes (SPEC 5.4).
class ClassifierConfig {
  const ClassifierConfig({
    this.version = 1,
    this.excellentMaxLoss = 0.02,
    this.goodMaxLoss = 0.05,
    this.inaccuracyMaxLoss = 0.10,
    this.mistakeMaxLoss = 0.20,
    this.brilliantMaxLoss = 0.02,
    this.sacrificeMinGain = 2,
    this.brilliantMinWinAfter = 50,
    this.brilliantMaxWinBefore = 97,
    this.greatMinGap = 20,
    this.losingBelow = 30,
    this.winningAbove = 70,
    this.missOpponentMinLoss = 0.10,
    this.missMinLoss = 0.10,
    this.missGiveBackMargin = 5,
    this.missMateMaxMoves = 5,
    this.missMateMinLoss = 0.05,
    this.missBlunderMaxWinAfter = 50,
  });

  static const standard = ClassifierConfig();

  /// Stored in `settings.classifier_version`.
  final int version;

  // --- base table (chess.com's published EP cutoffs) ------------------------

  /// Excellent: `0 < loss <= 0.02` (or a non-top move that lost nothing).
  final double excellentMaxLoss;

  /// Good: `0.02 < loss <= 0.05`.
  final double goodMaxLoss;

  /// Inaccuracy: `0.05 < loss <= 0.10`.
  final double inaccuracyMaxLoss;

  /// Mistake: `0.10 < loss <= 0.20`; Blunder above.
  final double mistakeMaxLoss;

  // --- Brilliant -------------------------------------------------------------

  /// Brilliant needs `loss <= this` (Best or Excellent).
  final double brilliantMaxLoss;

  /// SEE threshold of the sacrifice rule, in pawns (P=1 N=3 B=3 R=5 Q=9).
  final int sacrificeMinGain;

  /// The mover is not worse after the sacrifice: `W_after >= this`.
  final double brilliantMinWinAfter;

  /// The mover was not already completely winning: `W_best_before <= this`.
  final double brilliantMaxWinBefore;

  // --- Great -------------------------------------------------------------------

  /// `W(line1) - W(line2) >= this` Win% points.
  final double greatMinGap;

  /// Outcome buckets: losing `< losingBelow`, unclear in between, winning
  /// `> winningAbove`. Great needs line 1 and line 2 in different buckets.
  final double losingBelow;
  final double winningAbove;

  // --- Miss --------------------------------------------------------------------

  /// (a) the opponent's previous move lost at least this much ...
  final double missOpponentMinLoss;

  /// ... the mover's reply loses at least this much ...
  final double missMinLoss;

  /// ... and `W_after <= (mover's Win% before the opponent's error) + this`.
  final double missGiveBackMargin;

  /// (b) the best line was a forced mate for the mover in at most this many
  /// moves, the played move keeps no forced mate, and the loss is at least
  /// [missMateMinLoss].
  final int missMateMaxMoves;
  final double missMateMinLoss;

  /// Exception: a move that would be a Blunder and leaves the mover at or
  /// below this Win% is a Blunder, not a Miss. (SPEC says `< 50`; `<= 50`
  /// makes stalemating a won position a Blunder, docs/DECISIONS.md M4.)
  final double missBlunderMaxWinAfter;
}
