#!/usr/bin/env bash
# Builds the distributable release APKs (one per ABI), checks their permissions, and keeps the
# Dart debug symbols and the R8 mapping out of the APKs (SPEC section 6, "Release hardening").
#
#   GLYPH_KEYSTORE_FILE / GLYPH_KEYSTORE_PASSWORD / GLYPH_KEY_ALIAS / GLYPH_KEY_PASSWORD
#       (or app/android/key.properties) -> the release key. Required here: without it the build
#       fails (GLYPH_REQUIRE_SIGNING=1), so a debug-signed APK cannot be released by accident.
#       Set GLYPH_ALLOW_DEBUG_SIGNING=1 to build a test APK without a keystore.
#
# Output: app/build/app/outputs/flutter-apk/app-<abi>-release.apk
#         app/build/symbols/            (Dart symbols for `flutter symbolize`; keep, do not ship)
#         app/build/app/outputs/mapping/release/mapping.txt  (R8 mapping; keep, do not ship)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/app"

if [[ "${GLYPH_ALLOW_DEBUG_SIGNING:-0}" != "1" ]]; then
  export GLYPH_REQUIRE_SIGNING=1
fi

flutter build apk --release --split-per-abi --split-debug-info=build/symbols

cd "$ROOT"
# With GLYPH_REQUIRE_SIGNING=1 this fails if an APK carries the debug key's signature.
bash tool/check_signing.sh
bash tool/check_permissions.sh
bash tool/check_banned_deps.sh
echo "Release APKs:"
ls -l app/build/app/outputs/flutter-apk/app-*-release.apk
