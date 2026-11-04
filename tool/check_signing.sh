#!/usr/bin/env bash
# Verifies the signature of release APKs with apksigner and, when
# GLYPH_REQUIRE_SIGNING=1, fails if an APK is signed with the Android debug key
# ("CN=Android Debug"): the Gradle fallback to the debug key must never be
# distributed. Without GLYPH_REQUIRE_SIGNING it only reports the signer.
#
# Usage: tool/check_signing.sh [apk ...]
#   Default: app/build/app/outputs/flutter-apk/app-*-release.apk
# Env:    APKSIGNER (default: apksigner on PATH, else the newest
#         $ANDROID_HOME/build-tools/*/apksigner)
#         GLYPH_REQUIRE_SIGNING=1  fail on a debug-signed or unverifiable APK
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
APKSIGNER="${APKSIGNER:-}"
if [[ -z "$APKSIGNER" ]] && command -v apksigner >/dev/null 2>&1; then
  APKSIGNER="$(command -v apksigner)"
fi
if [[ -z "$APKSIGNER" ]]; then
  APKSIGNER="$(ls -1d "$SDK"/build-tools/*/apksigner 2>/dev/null | sort -V | tail -n 1 || true)"
fi
[[ -n "$APKSIGNER" && -x "$APKSIGNER" ]] || { echo "apksigner not found (set APKSIGNER)" >&2; exit 2; }

if [[ $# -gt 0 ]]; then
  APKS=("$@")
else
  shopt -s nullglob
  APKS=("$ROOT"/app/build/app/outputs/flutter-apk/app-*-release.apk)
fi
[[ ${#APKS[@]} -gt 0 ]] || { echo "no release APKs found; build first" >&2; exit 2; }

status=0
for apk in "${APKS[@]}"; do
  if ! out="$("$APKSIGNER" verify --print-certs "$apk" 2>&1)"; then
    echo "FAIL $(basename "$apk"): apksigner could not verify the signature" >&2
    status=1
    continue
  fi
  dn="$(grep -m1 'certificate DN:' <<<"$out" || true)"
  if grep -q 'CN=Android Debug' <<<"$out"; then
    if [[ "${GLYPH_REQUIRE_SIGNING:-0}" == "1" ]]; then
      echo "FAIL $(basename "$apk"): signed with the Android debug key (GLYPH_REQUIRE_SIGNING=1)" >&2
      status=1
    else
      echo "WARN $(basename "$apk"): signed with the Android debug key; for testing only" >&2
    fi
  else
    echo "OK   $(basename "$apk"): ${dn:-signer verified}"
  fi
done
exit $status
