# ASSETS — licence audit of everything Glyph ships (SPEC trap 15, F20)

Glyph is **GPL-3.0-or-later** (`LICENSE`). An open-source (F-Droid style) build must not ship a non-free graphic, font or data file, and every asset must be redistributable under the GPL. This file is the audit; the same list is in code (`app/lib/features/about/asset_licences.dart`, shown on the About screen and registered with Flutter's licence page), and `app/test/features/asset_licences_test.dart` fails when the code, this document, the files on disk and the vendoring allow-list disagree. Pub packages are not listed here: each brings its `LICENSE`, which Flutter's licence page shows, and `tool/check_banned_deps.sh` keeps analytics and ad SDKs out (see `DECISIONS.md`, M0 section 3.5, for the package licences).

How this was audited (M8, 2026-11-04):

1. `find` over `app/assets`, `third_party/chessground/assets`, `app/android/app/src/main/res` and the APK contents (`unzip -l`) for files that are not code.
2. Licences of the chessground assets, **verified against upstream on 2026-11-04** (M8 review; fetched read-only with curl from `raw.githubusercontent.com`):
   - <https://raw.githubusercontent.com/lichess-org/lila/master/COPYING.md> (SHA-256 of the file as fetched `ad0355db9ccd9ec049120945b356ff40c7c868d719a961732868bd5f5306cbba`), table "Exceptions (free)": `public/piece/cburnett` GPLv2+ (Colin M. L. Burnett); `public/piece/merida` GPLv2+ (Armando Hernandez Marroquin); `public/piece/mpchess` GPL v3+ (Maxime Chupin; the table's "GPL3v3+" is a typo for GPLv3+); `public/piece/rhosgfx` CC0 1.0 (RhosGFX); `public/images/board` AGPLv3+ (the lila authors and pirouetti). The same four piece directories exist upstream (`public/piece/<set>/wK.svg` returned HTTP 200).
   - The chessground board files exist upstream under `public/images/board/` for every kept board, as `.jpg` or `.png` (chessground ships the PNGs as `.webp`): blue-marble, blue2, blue3, canvas2, green-plastic, grey, leather, maple, maple2, marble, metal, olive, pink-pyramid, purple-diag, purple, wood, wood2, wood3, wood4 (HTTP 200 each).
   - **Not found upstream:** `newspaper` (neither `.webp`, `.png`, `.jpg` nor `.svg` in `public/images/board/`, and no row in COPYING.md). Its licence cannot be confirmed, so the file was **removed** (and the colour scheme is no longer selectable).
   - **Unreferenced:** `ncf-board.webp` (128 bytes; no colour scheme of chessground 11.0.0 uses it, and COPYING.md has no row for it) was shipped unlisted; **removed** through the allow-list.
   - The vendored package itself: <https://raw.githubusercontent.com/lichess-org/flutter-chessground/main/LICENSE> is the GNU GPL version 3 (the repository README makes no per-asset licence statement, so the lila table above is the authority for the artwork).
   - The `openings` data: <https://raw.githubusercontent.com/lichess-org/chess-openings/master/README.md> states "As a collection of facts, this data set is in the public domain" and applies the CC0 Public Domain Dedication.
   - Stockfish: <https://raw.githubusercontent.com/official-stockfish/Stockfish/master/Copying.txt> is the GNU GPL version 3.
   - The network's training data: the Stockfish `README.md` shipped in `multistockfish_light` 0.1.0 (`ios/multistockfish_light/Sources/multistockfish_light/StockfishLight/README.md`, "Acknowledgements", lines 125-126) says Stockfish "uses neural networks trained on data provided by the Leela Chess Zero project, which is made available under the Open Database License (ODbL)". See `nnue-training-data` below.
3. Everything not on the free list was removed: see "Removed".

## Shipped

### `piece-cburnett` Cburnett chess pieces
- Licence: GNU GPL, version 2 or later (SPDX `GPL-2.0-or-later`)
- Author: Colin M. L. Burnett
- Source: chessground 11.0.0, `assets/piece_sets/cburnett` (lichess.org)
- Files: `third_party/chessground/assets/piece_sets/cburnett/`
- Default piece set.

### `piece-merida` Merida chess pieces
- Licence: GNU GPL, version 2 or later (SPDX `GPL-2.0-or-later`)
- Author: Armando Hernandez Marroquin
- Source: chessground 11.0.0, `assets/piece_sets/merida` (lichess.org)
- Files: `third_party/chessground/assets/piece_sets/merida/`

### `piece-mpchess` MP Chess pieces
- Licence: GNU GPL, version 3 or later (SPDX `GPL-3.0-or-later`)
- Author: Maxime Chupin
- Source: chessground 11.0.0, `assets/piece_sets/mpchess` (lichess.org)
- Files: `third_party/chessground/assets/piece_sets/mpchess/`

### `piece-rhosgfx` RHOS chess pieces
- Licence: Creative Commons CC0 1.0 (SPDX `CC0-1.0`)
- Author: Rhosgfx
- Source: chessground 11.0.0, `assets/piece_sets/rhosgfx` (lichess.org)
- Files: `third_party/chessground/assets/piece_sets/rhosgfx/`

### `board-images` Board textures (wood, marble, metal, ...)
- Licence: GNU AGPL, version 3 or later (SPDX `AGPL-3.0-or-later`); an AGPL-3.0 work can be combined with a GPL-3.0 one (GPL-3.0 section 13 and AGPL-3.0 section 13)
- Author: the lichess.org authors and Pirouetti (`lila/COPYING.md:38`)
- Source: chessground 11.0.0, `assets/boards` (lichess.org); 19 images (wood, marble, metal, leather, ...); upstream: lila `COPYING.md`, row `public/images/board` (verified 2026-11-04, see Audit step 2)
- Files: `third_party/chessground/assets/boards/`
- The solid colour boards (brown, blue, green, IC) are drawn in code and need no file.

### `openings` Opening names and positions
- Licence: Creative Commons CC0 1.0 (SPDX `CC0-1.0`)
- Author: the lichess.org contributors (lichess-org/chess-openings)
- Source: <https://github.com/lichess-org/chess-openings> at commit 3fd6ce9, converted to `epd<TAB>eco<TAB>name` rows by `tool/build_openings.dart`; SHA-256 recorded in `openings.tsv.sha256` and checked by a test.
- Files: `app/assets/openings.tsv`, `app/assets/openings.tsv.sha256`

### `stockfish` Stockfish 19 (chess engine)
- Licence: GNU GPL, version 3 or later (SPDX `GPL-3.0-or-later`)
- Author: The Stockfish developers (see the AUTHORS file of Stockfish)
- Source: <https://stockfishchess.org>; built from source into `libmultistockfish_light.so` by the `multistockfish` plugin (lichess.org, GPL-3.0)
- The APK also contains `libmultistockfish_chess.so` (Stockfish without a network) and `libmultistockfish_variant.so` (Fairy-Stockfish, GPL-3.0). Glyph starts only the light engine; the other two are in the APK because the plugin links them (about 3.4 MB per ABI; see `DECISIONS.md` M0 3.2 for the untested option of excluding them).

### `nnue` Stockfish network nn-61e7af4bb97d.nnue (about 1.1 MB)
- Licence: GNU GPL, version 3 or later, with the engine (SPDX `GPL-3.0-or-later`)
- Author: The Stockfish project (network file), repackaged by the multistockfish authors
- Source: `multistockfish_light` 0.1.0, compiled into `libmultistockfish_light.so`; the file sits in the Stockfish source tree of that package under its GPL-3.0 `LICENSE`.
- Provenance (verified 2026-11-04): the Stockfish README in the package states the network is trained on Leela Chess Zero data under the ODbL; credited in the next entry, in the About screen and on Flutter's licence page.

### `nnue-training-data` Leela Chess Zero training data (the Stockfish network is trained on it)
- Licence: Open Database License 1.0 (SPDX `ODbL-1.0`)
- Author: The Leela Chess Zero project
- Source: <https://storage.lczero.org/files/training_data>; licence text <https://opendatacommons.org/licenses/odbl/odbl-10.txt>; statement in the Acknowledgements of the Stockfish README shipped in `multistockfish_light` 0.1.0.
- The data itself is **not shipped**. The ODbL asks that works produced from the data carry a notice that the data was used and under which licence; this entry (About screen and licence page) is that notice. The trained network (`nnue` above) is a Produced Work and stays under the engine's GPL-3.0.

### `sqlite` SQLite (libsqlite3.so)
- Licence: public domain (SPDX `blessing`)
- Author: D. Richard Hipp and the SQLite developers
- Source: prebuilt library downloaded and checksum-verified by the `sqlite3` package build hook (`DECISIONS.md` M0 section 8)

### `badges` Move badges (!!, !, ?!, ?, ??, star, tick, book, arrow, cross)
- Licence: GNU GPL, version 3 or later (SPDX `GPL-3.0-or-later`)
- Author: The Glyph authors
- Source: <https://github.com/Umar-Haqimi/Glyph>
- Files: `app/lib/features/board/move_badge.dart`
- Drawn in code (text glyphs and `CustomPainter` paths); there are no badge image files.

### `launcher-icon` Launcher icon
- Licence: GNU GPL, version 3 or later (SPDX `GPL-3.0-or-later`)
- Author: The Glyph authors
- Source: <https://github.com/Umar-Haqimi/Glyph>
- Files: `app/android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`, `app/android/app/src/main/res/drawable/ic_launcher_foreground.xml`, `app/android/app/src/main/res/values/ic_launcher_background.xml`
- An adaptive icon of two vector shapes ("!!"). It replaces the Flutter template's PNG icons (found in the audit: the template's own artwork, removed). minSdk is 26, so an adaptive icon is always available.

### `material-icons` Material Icons font
- Licence: Apache License 2.0 (SPDX `Apache-2.0`)
- Author: Google
- Source: bundled by Flutter (`MaterialIcons-Regular.otf`); a release build keeps only the glyphs the app uses (icon tree shaking).
- The app ships no other font; text uses the system font.

## Removed (not shipped, by the vendoring allow-list in `tool/vendor_chessground.sh`)

chessground 11.0.0 declares about 40 piece sets and 24 board images as package assets, so a plain dependency would copy ~18 MB of mostly non-free artwork into every APK. Glyph vendors the package into `third_party/chessground` (GPL-3.0, with a `NOTICE` of the modifications) and keeps only the allow-list above.

| Class | Sets | Reason |
|---|---|---|
| Non-commercial (CC BY-NC-SA) | horsey, california, caliente, maestro, fresca, cardinal, icpieces, gioco, tatiana, staunty, dubrovny, anarcandy, disguised, cooke, monarchy, xkcd | not free software licences |
| Non-free / no-derivatives / freeware | alpha, chess7, companion, leipzig, reillycraig, riohacha, shahi-ivory-brown | lila marks them non-free; shahi-ivory-brown carries a no-modification licence |
| Licence not verified | kosal, governor, symmetric, totoy | absent from or ambiguous in lila `COPYING.md` |
| Board images, not shipped | `newspaper.webp` (licence not found upstream), `ncf-board.webp` (used by no colour scheme, no licence row) | removed in the M8 review |
| Free, but not needed | chessnut (Apache-2.0), letter, pirouetti, pixel, fantasy, spatial, celtic, shapes, kiwen-suwi, firi | left out to keep the APK small and the attribution list short; can be added by extending the allow-list, this document and `asset_licences.dart` |
| Board images (non-free) | `horsey` board (`horsey.jpg`, `horsey.last-move.webp`, `horsey.selected.webp`) | belongs to the NC horsey set |

The Dart code of chessground is unchanged, so the package's `PieceSet` enum still names the removed sets. App code reaches piece sets and board colours only through `app/lib/features/board/board_assets.dart` (allow-list maps); a hygiene test fails if any other file names them, and a test checks that every image the allow-lists name exists on disk and that every removed set is really gone.

## Not assets

- No sound files. "Move sounds" plays Android's system click (`SystemSound`).
- No images in `app/assets` besides the data file above; no web fonts; no analytics or crash-reporting SDK (`tool/check_banned_deps.sh`).
