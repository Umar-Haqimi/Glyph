import 'package:dartchess/dartchess.dart' show Side;

import 'classifier.dart';
import 'move_label.dart';

/// A move worth jumping to (SPEC F9): every Brilliant, Great, Miss, Mistake
/// and Blunder, for both sides.
class KeyMoment {
  const KeyMoment({
    required this.ply,
    required this.side,
    required this.label,
    this.winBefore,
    this.winAfter,
    this.bestUci,
  });

  final int ply;
  final Side side;
  final MoveLabel label;

  /// Mover POV, as in [ClassifiedMove].
  final double? winBefore;
  final double? winAfter;
  final String? bestUci;

  /// Win% the move changed for the mover (positive = it lost that much).
  double get swing => (winBefore ?? 0) - (winAfter ?? 0);

  @override
  String toString() => 'KeyMoment($ply ${side.name} ${label.name})';
}

abstract final class KeyMoments {
  /// Labels that make a key moment.
  static const labels = {
    MoveLabel.brilliant,
    MoveLabel.great,
    MoveLabel.miss,
    MoveLabel.mistake,
    MoveLabel.blunder,
  };

  /// All key moments in ply order.
  static List<KeyMoment> of(Iterable<ClassifiedMove?> moves) => [
        for (final m in moves)
          if (m != null && labels.contains(m.label))
            KeyMoment(
              ply: m.ply,
              side: m.side,
              label: m.label,
              winBefore: m.winBefore,
              winAfter: m.winAfter,
              bestUci: m.bestUci,
            ),
      ];

  /// Moments of one side.
  static List<KeyMoment> ofSide(Iterable<KeyMoment> moments, Side side) =>
      [for (final m in moments) if (m.side == side) m];

  /// At most [limit] moments for the game summary (SPEC 5.5: <= 8), the
  /// Brilliant and Great moves first, then the biggest Win% losses; the
  /// result is returned in ply order.
  static List<KeyMoment> mostSignificant(List<KeyMoment> moments, {int limit = 8}) {
    final ranked = [...moments]..sort((a, b) {
        final byWeight = _weight(b).compareTo(_weight(a));
        return byWeight != 0 ? byWeight : a.ply.compareTo(b.ply);
      });
    return ranked.take(limit).toList()..sort((a, b) => a.ply.compareTo(b.ply));
  }

  static double _weight(KeyMoment m) => switch (m.label) {
        MoveLabel.brilliant || MoveLabel.great => 100,
        _ => m.swing,
      };
}
