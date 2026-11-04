#!/usr/bin/env bash
# Vendors chessground into third_party/chessground with only free-licensed assets
# (SPEC trap 15, docs/DECISIONS.md M0 section 2.5 and M5): cburnett piece set, free boards
# (no horsey). Usage: tool/vendor_chessground.sh [version]  (default 11.0.0, from the pub cache)
set -euo pipefail
VERSION="${1:-11.0.0}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${PUB_CACHE:-$HOME/.pub-cache}/hosted/pub.dev/chessground-$VERSION"
DST="$ROOT/third_party/chessground"
[ -d "$SRC" ] || { echo "missing $SRC (run: flutter pub add chessground:$VERSION in a scratch app)"; exit 1; }
rm -rf "$DST"
mkdir -p "$DST/assets/piece_sets"
cp -r "$SRC/lib" "$SRC/LICENSE" "$SRC/README.md" "$SRC/CHANGELOG.md" "$DST/"
cp -r "$SRC/assets/piece_sets/cburnett" "$DST/assets/piece_sets/"
cp -r "$SRC/assets/boards" "$DST/assets/boards"
rm -f "$DST"/assets/boards/horsey*
# Trimmed pubspec: same dependencies, only the assets that are kept.
cat > "$DST/pubspec.yaml" <<YAML
name: chessground
description: Vendored copy of chessground $VERSION (lichess.org, GPL-3.0) with only free-licensed assets. See docs/DECISIONS.md.
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
    - assets/piece_sets/cburnett/
    - assets/boards/
YAML
