import 'package:chessground/chessground.dart' show StaticChessboard, StaticChessboardSettings;
import 'package:dartchess/dartchess.dart';
import 'package:material_ui/material_ui.dart';

import 'board_assets.dart';

/// The start position drawn with a board colour scheme and a piece set (the
/// Settings > Appearance preview). Decorative: the tile above it names the
/// choices, so a screen reader skips the picture.
class BoardPreview extends StatelessWidget {
  const BoardPreview({super.key, required this.schemeKey, required this.pieceSetKey, this.size = 144});

  final String schemeKey;
  final String pieceSetKey;
  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: StaticChessboard(
          size: size,
          orientation: Side.white,
          fen: kInitialFEN,
          settings: StaticChessboardSettings(
            colorScheme: boardSchemeFor(schemeKey),
            pieceAssets: pieceAssetsFor(pieceSetKey),
            enableCoordinates: false,
            animationDuration: Duration.zero,
          ),
        ),
      );
}
