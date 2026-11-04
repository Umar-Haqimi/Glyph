import 'package:chessground/chessground.dart' show Arrow, CustomShape, Shape, StaticChessboard, StaticChessboardSettings;
import 'package:dartchess/dartchess.dart';
import 'package:glyph_core/glyph_core.dart' show MoveLabel;
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'board_assets.dart';
import 'move_badge.dart';

/// A badge to draw on a square of the board.
class BoardBadge {
  const BoardBadge({required this.square, required this.label, required this.spokenMove});

  final Square square;
  final MoveLabel label;

  /// The move the badge belongs to, in words for a screen reader (not part of
  /// the identity: the same label on the same square is the same badge).
  final String spokenMove;

  @override
  bool operator ==(Object other) => other is BoardBadge && other.square == square && other.label == label;

  @override
  int get hashCode => Object.hash(square, label);
}

/// A best-move arrow on the board (already in drawn squares: a castling move
/// points at the king's destination, see `displaySquares`).
class BoardArrow {
  const BoardArrow({required this.from, required this.to});

  final Square from;
  final Square to;

  @override
  bool operator ==(Object other) => other is BoardArrow && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// The view-only board of the analysis screen (SPEC section 4): last-move
/// highlight, Glyph's own badge on the destination square of the current
/// move, the best-move arrow, coordinates. Built on chessground's
/// `StaticChessboard`; only the free piece sets and boards of `board_assets.dart` (SPEC trap 15).
///
/// Pieces glide for one ply and jump when [animate] is false (SPEC section 4:
/// "none when jumping more than 1 ply").
class AnalysisBoard extends StatelessWidget {
  const AnalysisBoard({
    super.key,
    required this.size,
    required this.fen,
    required this.orientation,
    this.lastMove,
    this.badge,
    this.arrow,
    this.animate = true,
    required this.semanticsLabel,
    this.boardScheme = defaultBoardSchemeKey,
    this.pieceSet = defaultPieceSetKey,
  });

  final double size;
  final String fen;
  final Side orientation;
  final NormalMove? lastMove;
  final BoardBadge? badge;
  final BoardArrow? arrow;
  final bool animate;

  /// What a screen reader says for the whole board (position, last move,
  /// label, orientation).
  final String semanticsLabel;

  /// Keys of the allow-lists in `board_assets.dart` (Settings > Appearance).
  final String boardScheme;
  final String pieceSet;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final scheme = Theme.of(context).colorScheme;
    final badge = this.badge;
    final arrow = this.arrow;
    // The system "remove animations" setting: no glide, no pop-in.
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final shapes = <Shape>{
      if (arrow != null)
        Arrow(color: scheme.primary.withValues(alpha: 0.85), orig: arrow.from, dest: arrow.to),
      if (badge != null) _badgeShape(context, l10n, badge, reduceMotion),
    };
    return Semantics(
      container: true,
      label: semanticsLabel,
      image: true,
      child: StaticChessboard(
        size: size,
        orientation: orientation,
        fen: fen,
        lastMove: lastMove,
        shapes: shapes,
        settings: StaticChessboardSettings(
          colorScheme: boardSchemeFor(boardScheme),
          pieceAssets: pieceAssetsFor(pieceSet),
          enableCoordinates: true,
          animationDuration: animate && !reduceMotion ? const Duration(milliseconds: 150) : Duration.zero,
        ),
      ),
    );
  }

  Shape _badgeShape(BuildContext context, AppLocalizations l10n, BoardBadge badge, bool reduceMotion) {
    return CustomShape(
      orig: badge.square,
      child: Align(
        alignment: Alignment.topRight,
        child: FractionallySizedBox(
          widthFactor: 0.52,
          heightFactor: 0.52,
          child: TweenAnimationBuilder<double>(
            key: ValueKey(badge),
            tween: Tween(begin: 0, end: 1),
            duration: reduceMotion ? Duration.zero : popInDuration,
            curve: Curves.easeOutBack,
            builder: (context, t, child) => Transform.scale(scale: t.clamp(0.0, 1.2), child: child),
            child: Semantics(
              label: l10n.boardBadgeOn(labelName(l10n, badge.label), badge.spokenMove),
              image: true,
              child: LayoutBuilder(
                builder: (context, c) => MoveBadge(
                  label: badge.label,
                  size: c.biggest.shortestSide,
                  outlined: true,
                  excludeSemantics: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
