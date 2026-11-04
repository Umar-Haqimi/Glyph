import 'dart:io';

import 'package:chessground/chessground.dart' show ChessboardColorScheme, ImageChessboardBackground, PieceSet;
import 'package:flutter/painting.dart' show AssetImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/board/board_assets.dart';

/// `assetName` of an image of the vendored chessground, as a file.
File _file(AssetImage image) => File('../third_party/chessground/${image.assetName}');

void main() {
  test('the default piece set is cburnett and every selectable piece set has all twelve images on disk', () {
    expect(boardPieceAssets, PieceSet.cburnettAssets);
    expect(pieceAssetsFor(null), PieceSet.cburnettAssets);
    expect(pieceAssetsFor('alpha'), PieceSet.cburnettAssets, reason: 'a key that is not on the allow-list falls back');
    expect(selectablePieceSets.keys, ['cburnett', 'merida', 'mpchess', 'rhosgfx']);
    expect(selectablePieceSets, contains(defaultPieceSetKey));
    for (final MapEntry(key: name, value: assets) in selectablePieceSets.entries) {
      expect(assets, hasLength(12), reason: name);
      for (final image in assets.values) {
        expect(_file(image).existsSync(), isTrue, reason: '$name: ${image.assetName}');
        expect(image.assetName, contains('/piece_sets/$name/'), reason: 'the key is the vendored directory');
      }
    }
  });

  test('a board scheme key that is not on the allow-list falls back to the default colours', () {
    expect(boardSchemeFor(null), defaultBoardColorScheme);
    expect(boardSchemeFor('horsey'), defaultBoardColorScheme);
    expect(boardSchemeFor('wood'), ChessboardColorScheme.wood);
    expect(selectableBoardSchemes, contains(defaultBoardSchemeKey));
  });

  test('every selectable board colour scheme only names images that are vendored', () {
    expect(selectableBoardSchemes.values, contains(defaultBoardColorScheme));
    expect(selectableBoardSchemes, hasLength(24));
    var images = 0;
    for (final MapEntry(key: name, value: scheme) in selectableBoardSchemes.entries) {
      final used = <AssetImage>[
        for (final b in [scheme.background, scheme.whiteCoordBackground, scheme.blackCoordBackground])
          if (b is ImageChessboardBackground) b.image,
        ?scheme.lastMove.image,
        ?scheme.selected.image,
      ];
      for (final image in used) {
        images++;
        expect(_file(image).existsSync(), isTrue, reason: '$name: ${image.assetName}');
      }
    }
    expect(images, greaterThan(40), reason: 'the image-backed schemes were really inspected');
  });

  test('the removed ones really are removed: horsey is not selectable and its images are gone', () {
    expect(selectableBoardSchemes.values, isNot(contains(ChessboardColorScheme.horsey)));
    final horsey = ChessboardColorScheme.horsey.background as ImageChessboardBackground;
    expect(_file(horsey.image).existsSync(), isFalse);
    // Piece sets that are not on the allow-list are gone too.
    var removedCount = 0;
    for (final removed in PieceSet.values) {
      if (selectablePieceSets.containsKey(removed.name)) continue;
      removedCount++;
      expect(_file(removed.assets.values.first).existsSync(), isFalse, reason: removed.name);
      expect(selectablePieceSets.values, isNot(contains(removed.assets)), reason: removed.name);
    }
    expect(removedCount, greaterThan(30));
  });
}
