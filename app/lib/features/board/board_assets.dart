import 'package:chessground/chessground.dart' show ChessboardColorScheme, PieceAssets, PieceSet;

/// The ONLY place app code may name chessground piece sets and board colour
/// schemes.
///
/// `third_party/chessground` is a trimmed copy (see its NOTICE and
/// `tool/vendor_chessground.sh`): only the `cburnett` piece set and the
/// allow-listed board images exist. The package's `PieceSet` enum and the
/// `ChessboardColorScheme` constants still list everything upstream ships, so
/// `PieceSet.merida` or `ChessboardColorScheme.horsey` compile and then fail
/// with a missing asset at run time. `test/hygiene_test.dart` fails if any
/// other file under `lib/` mentions `PieceSet` or `ChessboardColorScheme`;
/// the M8 appearance picker chooses from [selectableBoardSchemes] (and, if
/// more piece sets are ever vendored, from a map added here), never from the
/// package's enum.

/// The piece set of the board (free `cburnett`, SPEC trap 15).
const PieceAssets boardPieceAssets = PieceSet.cburnettAssets;

/// The default board colours.
const ChessboardColorScheme defaultBoardColorScheme = ChessboardColorScheme.brown;

/// Every colour scheme whose assets are vendored (all upstream schemes but
/// `horsey`, whose images are not licensed for redistribution). A test checks
/// that each image they name exists in `third_party/chessground`.
const Map<String, ChessboardColorScheme> selectableBoardSchemes = {
  'brown': ChessboardColorScheme.brown,
  'blue': ChessboardColorScheme.blue,
  'green': ChessboardColorScheme.green,
  'ic': ChessboardColorScheme.ic,
  'blue2': ChessboardColorScheme.blue2,
  'blue3': ChessboardColorScheme.blue3,
  'blueMarble': ChessboardColorScheme.blueMarble,
  'canvas': ChessboardColorScheme.canvas,
  'greenPlastic': ChessboardColorScheme.greenPlastic,
  'grey': ChessboardColorScheme.grey,
  'leather': ChessboardColorScheme.leather,
  'maple': ChessboardColorScheme.maple,
  'maple2': ChessboardColorScheme.maple2,
  'marble': ChessboardColorScheme.marble,
  'metal': ChessboardColorScheme.metal,
  'newspaper': ChessboardColorScheme.newspaper,
  'olive': ChessboardColorScheme.olive,
  'pinkPyramid': ChessboardColorScheme.pinkPyramid,
  'purple': ChessboardColorScheme.purple,
  'purpleDiag': ChessboardColorScheme.purpleDiag,
  'wood': ChessboardColorScheme.wood,
  'wood2': ChessboardColorScheme.wood2,
  'wood3': ChessboardColorScheme.wood3,
  'wood4': ChessboardColorScheme.wood4,
};
