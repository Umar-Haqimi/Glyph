import 'package:dartchess/dartchess.dart';

import 'game.dart';

/// Navigates the positions of a game. Only the mainline is implemented; a
/// variation-aware cursor can implement the same interface later.
abstract interface class PositionCursor {
  /// Current ply: 0 = start position, `game.plyCount` = final position.
  int get ply;
  int get length;
  bool get canBack;
  bool get canForward;

  Position get position;

  /// The move that led to the current position (null at the start).
  Move? get lastMove;

  void goTo(int ply);
  void next();
  void back();
  void first();
  void last();
}

class MainlineCursor implements PositionCursor {
  MainlineCursor(this.game, {int ply = 0})
      : _positions = [game.startPosition()],
        _moves = [null] {
    goTo(ply);
  }

  final Game game;
  final List<Position> _positions;
  final List<Move?> _moves;
  int _ply = 0;

  @override
  int get ply => _ply;

  @override
  int get length => game.plyCount;

  @override
  bool get canBack => _ply > 0;

  @override
  bool get canForward => _ply < length;

  @override
  Position get position => _positions[_ply];

  @override
  Move? get lastMove => _moves[_ply];

  @override
  void goTo(int ply) {
    final target = ply.clamp(0, length);
    // Positions are computed lazily and cached; Position is immutable.
    while (_positions.length <= target) {
      final move = Move.parse(game.plies[_positions.length - 1].uci);
      if (move == null) {
        throw StateError('Invalid stored move ${game.plies[_positions.length - 1].uci}');
      }
      _positions.add(_positions.last.play(move));
      _moves.add(move);
    }
    _ply = target;
  }

  @override
  void next() => goTo(_ply + 1);

  @override
  void back() => goTo(_ply - 1);

  @override
  void first() => goTo(0);

  @override
  void last() => goTo(length);
}
