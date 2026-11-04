/// Move classification labels (SPEC section 2.1 and 4).
///
/// Declaration order is the display order of the badge set. The classifier
/// precedence (Book, Forced, Brilliant, Great, Miss, Best, ...) is separate and
/// lives with the classifier (M4).
enum MoveLabel {
  brilliant,
  great,
  best,
  excellent,
  good,
  book,
  forced,
  inaccuracy,
  mistake,
  miss,
  blunder,
}
