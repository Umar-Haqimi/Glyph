/// Expected-points loss of a move (SPEC 2.1): how much of the mover's
/// expected score (0..1) the move gave away compared with the engine's best
/// line, `max(0, (W_best_before - W_after) / 100)`.
///
/// Both Win% values are from the **mover's** point of view (0..100). See
/// [Classifier] for how `W_after` is chosen without depth-inconsistent
/// phantom losses (SPEC trap 3).
abstract final class ExpectedPoints {
  static double loss(double winBestBefore, double winAfter) {
    final l = (winBestBefore - winAfter) / 100;
    return l > 0 ? l : 0;
  }
}
