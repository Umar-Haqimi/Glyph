import 'dart:io';

import 'package:chessground/chessground.dart' show ChessboardColorScheme, ImageChessboardBackground, PieceSet;
import 'package:flutter/painting.dart' show AssetImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/board/board_assets.dart';

/// `assetName` of an image of the vendored chessground, as a file.
File _file(AssetImage image) => File('../third_party/chessground/${image.assetName}');

void main() {
  test('the piece set of the board is cburnett and every piece image exists', () {
    expect(boardPieceAssets, PieceSet.cburnettAssets);
    expect(boardPieceAssets, hasLength(12));
    for (final image in boardPieceAssets.values) {
      expect(_file(image).existsSync(), isTrue, reason: image.assetName);
    }
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
    expect(_file(PieceSet.merida.assets.values.first).existsSync(), isFalse);
  });
}
