import 'package:flutter/foundation.dart';

import '../../app_info.dart';

/// What kind of file an [AssetLicence] covers.
enum AssetKind { pieceSet, boardImages, data, engine, network, nativeLibrary, icon, badges, font }

/// One bundled asset (or group of assets) with its licence, author and source:
/// the single list behind the About screen, the Flutter licence page
/// ([registerAssetLicences]) and `docs/ASSETS.md`. `test/features/asset_licences_test.dart`
/// keeps this list, the files on disk, the vendoring allow-list and the
/// document in line (SPEC trap 15: an open-source build must not ship a
/// non-free asset).
class AssetLicence {
  const AssetLicence({
    required this.id,
    required this.name,
    required this.kind,
    required this.spdx,
    required this.licence,
    required this.author,
    required this.source,
    this.paths = const [],
    this.note = '',
  });

  /// Stable key, also the heading key in `docs/ASSETS.md`.
  final String id;
  final String name;
  final AssetKind kind;

  /// SPDX identifier of the licence the asset is used under.
  final String spdx;

  /// Readable licence name.
  final String licence;
  final String author;
  final String source;

  /// Repository-relative files or directories ('/' suffix) the entry covers.
  /// Empty for things that are built into a binary or the OS.
  final List<String> paths;
  final String note;
}

const String _chessground = 'third_party/chessground/assets';

/// Every asset Glyph ships that is not a Dart or Kotlin source file or a pub
/// package (pub packages bring their own `LICENSE`, which Flutter's licence
/// page lists). All are free software licences that allow redistribution under
/// the GPL-3.0-or-later; a build that adds anything else must fail the test.
const List<AssetLicence> assetLicences = [
  AssetLicence(
    id: 'piece-cburnett',
    name: 'Cburnett chess pieces',
    kind: AssetKind.pieceSet,
    spdx: 'GPL-2.0-or-later',
    licence: 'GNU GPL, version 2 or later',
    author: 'Colin M. L. Burnett',
    source: 'chessground 11.0.0, assets/piece_sets/cburnett (lichess.org)',
    paths: ['$_chessground/piece_sets/cburnett/'],
  ),
  AssetLicence(
    id: 'piece-merida',
    name: 'Merida chess pieces',
    kind: AssetKind.pieceSet,
    spdx: 'GPL-2.0-or-later',
    licence: 'GNU GPL, version 2 or later',
    author: 'Armando Hernandez Marroquin',
    source: 'chessground 11.0.0, assets/piece_sets/merida (lichess.org)',
    paths: ['$_chessground/piece_sets/merida/'],
  ),
  AssetLicence(
    id: 'piece-mpchess',
    name: 'MP Chess pieces',
    kind: AssetKind.pieceSet,
    spdx: 'GPL-3.0-or-later',
    licence: 'GNU GPL, version 3 or later',
    author: 'Maxime Chupin',
    source: 'chessground 11.0.0, assets/piece_sets/mpchess (lichess.org)',
    paths: ['$_chessground/piece_sets/mpchess/'],
  ),
  AssetLicence(
    id: 'piece-rhosgfx',
    name: 'RHOS chess pieces',
    kind: AssetKind.pieceSet,
    spdx: 'CC0-1.0',
    licence: 'Creative Commons CC0 1.0 (public domain dedication)',
    author: 'Rhosgfx',
    source: 'chessground 11.0.0, assets/piece_sets/rhosgfx (lichess.org)',
    paths: ['$_chessground/piece_sets/rhosgfx/'],
  ),
  AssetLicence(
    id: 'board-images',
    name: 'Board textures (wood, marble, metal, ...)',
    kind: AssetKind.boardImages,
    spdx: 'AGPL-3.0-or-later',
    licence: 'GNU AGPL, version 3 or later (combinable with the GPL-3.0, section 13)',
    author: 'the lichess.org authors and Pirouetti',
    source: 'chessground 11.0.0, assets/boards (lichess.org, lila COPYING.md); the one board set with a non-commercial licence is left out',
    paths: ['$_chessground/boards/'],
    note: 'The solid colour boards (brown, blue, green, IC) are drawn in code and need no file.',
  ),
  AssetLicence(
    id: 'openings',
    name: 'Opening names and positions',
    kind: AssetKind.data,
    spdx: 'CC0-1.0',
    licence: 'Creative Commons CC0 1.0 (public domain dedication)',
    author: 'the lichess.org contributors (lichess-org/chess-openings)',
    source: 'https://github.com/lichess-org/chess-openings at commit 3fd6ce9, converted by tool/build_openings.dart',
    paths: ['app/assets/openings.tsv', 'app/assets/openings.tsv.sha256'],
  ),
  AssetLicence(
    id: 'stockfish',
    name: 'Stockfish 19 (chess engine)',
    kind: AssetKind.engine,
    spdx: 'GPL-3.0-or-later',
    licence: 'GNU GPL, version 3 or later',
    author: 'The Stockfish developers (see the AUTHORS file of Stockfish)',
    source: 'https://stockfishchess.org, built into libmultistockfish_light.so by the multistockfish plugin (lichess.org, GPL-3.0)',
    note: 'The plugin also ships libmultistockfish_chess.so (Stockfish without a network) and '
        'libmultistockfish_variant.so (Fairy-Stockfish, GPL-3.0). Glyph only starts the light engine; the other two are '
        'in the APK because the plugin links them.',
  ),
  AssetLicence(
    id: 'nnue',
    name: 'Stockfish network nn-61e7af4bb97d.nnue (about 1.1 MB)',
    kind: AssetKind.network,
    spdx: 'GPL-3.0-or-later',
    licence: 'GNU GPL, version 3 or later, with the engine',
    author: 'The Stockfish project (network file), repackaged by the multistockfish authors',
    source: 'multistockfish_light 0.1.0, compiled into libmultistockfish_light.so',
    note: 'Distributed by multistockfish_light inside the Stockfish source tree under that package\'s GPL-3.0 licence.',
  ),
  AssetLicence(
    id: 'sqlite',
    name: 'SQLite (libsqlite3.so)',
    kind: AssetKind.nativeLibrary,
    spdx: 'blessing',
    licence: 'Public domain',
    author: 'D. Richard Hipp and the SQLite developers',
    source: 'prebuilt library downloaded and checksum-verified by the sqlite3 package build hook',
  ),
  AssetLicence(
    id: 'badges',
    name: 'Move badges (!!, !, ?!, ?, ??, star, tick, book, arrow, cross)',
    kind: AssetKind.badges,
    spdx: 'GPL-3.0-or-later',
    licence: 'GNU GPL, version 3 or later',
    author: 'The Glyph authors',
    source: projectUrl,
    paths: ['app/lib/features/board/move_badge.dart'],
    note: 'Drawn in code (text glyphs and CustomPainter paths); no image files.',
  ),
  AssetLicence(
    id: 'launcher-icon',
    name: 'Launcher icon',
    kind: AssetKind.icon,
    spdx: 'GPL-3.0-or-later',
    licence: 'GNU GPL, version 3 or later',
    author: 'The Glyph authors',
    source: projectUrl,
    paths: [
      'app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml',
      'app/android/app/src/main/res/drawable/ic_launcher_foreground.xml',
      'app/android/app/src/main/res/values/ic_launcher_background.xml',
    ],
    note: 'An adaptive icon of two vector shapes ("!!"); it replaces the Flutter template\'s PNG icons.',
  ),
  AssetLicence(
    id: 'material-icons',
    name: 'Material Icons font',
    kind: AssetKind.font,
    spdx: 'Apache-2.0',
    licence: 'Apache License 2.0',
    author: 'Google',
    source: 'bundled by Flutter (MaterialIcons-Regular.otf); only the glyphs the app uses are kept in a release build',
    note: 'The app ships no other font; text uses the system font.',
  ),
];

bool _registered = false;

/// Adds the licence texts of [assetLicences] (and Glyph's own notice) to
/// Flutter's [LicenseRegistry], so `showLicensePage` lists the bundled assets
/// that no pub package covers. Safe to call more than once.
void registerAssetLicences() {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() async* {
    yield const LicenseEntryWithLineBreaks(
      ['Glyph'],
      'Glyph: on-device Stockfish game review with LLM-written explanations.\n'
      'Copyright (C) the Glyph authors.\n\n'
      'This program is free software: you can redistribute it and/or modify it under the terms of the '
      'GNU General Public License as published by the Free Software Foundation, either version 3 of the '
      'License, or (at your option) any later version.\n\n'
      'This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even '
      'the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public '
      'License for more details (the full text is listed below under the other GPL-3.0 packages and is at '
      'https://www.gnu.org/licenses/gpl-3.0.html).\n\n'
      'Source code: $projectUrl',
    );
    for (final a in assetLicences) {
      yield LicenseEntryWithLineBreaks(
        ['Glyph asset: ${a.name}'],
        '${a.name}\n'
        'Licence: ${a.licence} (${a.spdx})\n'
        'Author: ${a.author}\n'
        'Source: ${a.source}\n'
        '${a.paths.isEmpty ? '' : 'Files: ${a.paths.join(', ')}\n'}'
        '${a.note.isEmpty ? '' : '${a.note}\n'}',
      );
    }
  });
}

/// For tests: forget that the licences were registered (the registry itself
/// keeps its collectors for the process).
@visibleForTesting
void debugResetAssetLicenceRegistration() => _registered = false;
