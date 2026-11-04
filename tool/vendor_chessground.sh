#!/usr/bin/env bash
# Vendors chessground into third_party/chessground with only free-licensed assets
# (SPEC trap 15, docs/DECISIONS.md M0 section 2.5, M5 and M8, docs/ASSETS.md): an explicit
# allow-list of piece sets and of board images. Everything not listed is NOT copied, so a
# new upstream asset (a new piece set, a new board) can never slip in unreviewed.
# Also writes third_party/chessground/NOTICE (GPL-3.0 section 5a: a modified copy
# must carry a notice of the changes).
# Usage: tool/vendor_chessground.sh [version]  (default 11.0.0, from the pub cache)
set -euo pipefail
VERSION="${1:-11.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/chessground-$VERSION"
DST="$ROOT/third_party/chessground"

# --- Allow-list: the only assets that are kept -------------------------------------
# Left out on purpose (M8 review): ncf-board.webp (no colour scheme uses it, so it would ship
# unreferenced and unlisted) and newspaper.webp (no matching file or licence row in lila's
# public/images/board or COPYING.md, so its licence cannot be confirmed; see docs/ASSETS.md).
# Every set here has a row in docs/ASSETS.md and in app/lib/features/about/asset_licences.dart;
# app/test/features/asset_licences_test.dart fails when the three disagree.
KEEP_PIECE_SETS=(cburnett merida mpchess rhosgfx)
KEEP_BOARDS=(
  blue-marble.jpg blue2.jpg blue3.jpg canvas2.jpg green-plastic.webp grey.jpg
  leather.jpg maple.jpg maple2.jpg marble.jpg metal.jpg
  olive.jpg pink-pyramid.webp purple-diag.webp purple.webp
  wood.jpg wood2.jpg wood3.jpg wood4.jpg
)
# ------------------------------------------------------------------------------------

[ -d "$SRC" ] || { echo "missing $SRC (run: flutter pub add chessground:$VERSION in a scratch app)"; exit 1; }
rm -rf "$DST"
mkdir -p "$DST/assets/piece_sets" "$DST/assets/boards"
cp -r "$SRC/lib" "$SRC/LICENSE" "$SRC/README.md" "$SRC/CHANGELOG.md" "$DST/"
for set in "${KEEP_PIECE_SETS[@]}"; do
  [ -d "$SRC/assets/piece_sets/$set" ] || { echo "allow-listed piece set missing upstream: $set"; exit 1; }
  cp -r "$SRC/assets/piece_sets/$set" "$DST/assets/piece_sets/"
done
for board in "${KEEP_BOARDS[@]}"; do
  [ -f "$SRC/assets/boards/$board" ] || { echo "allow-listed board missing upstream: $board"; exit 1; }
  cp "$SRC/assets/boards/$board" "$DST/assets/boards/"
done

# Trimmed pubspec: same dependencies, only the assets that are kept.
PIECE_ASSET_LINES=""
KEEP_LIST=""
for set in "${KEEP_PIECE_SETS[@]}"; do
  PIECE_ASSET_LINES="${PIECE_ASSET_LINES}    - assets/piece_sets/$set/"$'\n'
  KEEP_LIST="${KEEP_LIST:+$KEEP_LIST, }\`$set\`"
done
PIECE_ASSET_LINES="${PIECE_ASSET_LINES%$'\n'}"
KEEP_CSV="$(IFS=,; echo "${KEEP_PIECE_SETS[*]}")"
cat > "$DST/pubspec.yaml" <<YAML
name: chessground
description: Vendored copy of chessground $VERSION (lichess.org, GPL-3.0) with only free-licensed assets. See NOTICE and docs/DECISIONS.md.
version: $VERSION
repository: https://github.com/lichess-org/flutter-chessground
publish_to: none

environment:
  sdk: '>=3.7.0 <4.0.0'
  flutter: ">=3.29.0"

dependencies:
  dartchess: ^0.14.0
  flutter:
    sdk: flutter
  meta: ^1.18.0

flutter:
  assets:
$PIECE_ASSET_LINES
    - assets/boards/
YAML

cat > "$DST/NOTICE" <<NOTICE
Modified copy of chessground $VERSION

chessground (https://github.com/lichess-org/flutter-chessground, "flutter-chessground")
is Copyright (C) the lichess.org contributors and is licensed under the GNU General
Public License, version 3 (see LICENSE in this directory). This directory is a
MODIFIED copy of the published package chessground $VERSION, vendored by the Glyph
project (GPL-3.0-or-later) and distributed under the same licence (GPL-3.0 section 5a:
prominent notice that the work was modified, and the date of the change).

Changes against the upstream $VERSION release:

1. pubspec.yaml was replaced: the same dependencies, but only the assets listed
   below are declared as Flutter assets.
2. Assets REMOVED (not licensed for redistribution with Glyph, or not needed):
   - every piece set except $KEEP_LIST (assets/piece_sets/<name>/ for all other names);
   - every board image that is not in the allow-list of tool/vendor_chessground.sh,
     in particular the \`horsey\` board images (assets/boards/horsey*), \`ncf-board.webp\`
     (unused) and \`newspaper.webp\` (licence not confirmed).
   The assets that are kept: assets/piece_sets/{$KEEP_CSV}/ and the board images of the
   allow-list in tool/vendor_chessground.sh (assets/boards/).
3. The Dart sources under lib/ are UNCHANGED. Consequently the enum \`PieceSet\` and
   the colour schemes of \`ChessboardColorScheme\` still name assets that are no longer
   present (all piece sets but $KEEP_LIST, \`ChessboardColorScheme.horsey\`). Using
   them would fail at run time with a missing asset. Glyph's app code therefore
   reaches these only through app/lib/features/board/board_assets.dart, and a test
   (app/test/hygiene_test.dart) fails if anything else references them.

Date of this vendoring: see the git history of this directory.
Re-create with: tool/vendor_chessground.sh $VERSION
NOTICE
echo "vendored chessground $VERSION into $DST"
