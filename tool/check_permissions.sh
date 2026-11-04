#!/usr/bin/env bash
# Asserts that every release APK requests exactly {INTERNET} (SPEC section 6),
# plus the signature-level permission androidx.core adds (allowlisted per
# docs/DECISIONS.md, M0): <applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION.
#
# Usage: tool/check_permissions.sh [apk ...]
#   Default: app/build/app/outputs/flutter-apk/app-*-release.apk
# Env:    APKANALYZER (default: $ANDROID_HOME/cmdline-tools/latest/bin/apkanalyzer)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SDK="${ANDROID_HOME:-${ANDROID_SDK_ROOT:-$HOME/Android/Sdk}}"
APKANALYZER="${APKANALYZER:-$SDK/cmdline-tools/latest/bin/apkanalyzer}"
if [[ ! -x "$APKANALYZER" ]]; then
  APKANALYZER="$HOME/Android/Sdk/cmdline-tools/latest/bin/apkanalyzer"
fi
if [[ ! -x "$APKANALYZER" ]] && command -v apkanalyzer >/dev/null 2>&1; then
  APKANALYZER="$(command -v apkanalyzer)"
fi
[[ -x "$APKANALYZER" ]] || { echo "apkanalyzer not found (set APKANALYZER)" >&2; exit 2; }

APPLICATION_ID="my.umarh.glyph"
ALLOWED_EXACT=("android.permission.INTERNET")
ALLOWED_PATTERN="^${APPLICATION_ID//./\\.}\\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION$"

if [[ $# -gt 0 ]]; then
  APKS=("$@")
else
  shopt -s nullglob
  APKS=("$ROOT"/app/build/app/outputs/flutter-apk/app-*-release.apk)
fi
[[ ${#APKS[@]} -gt 0 ]] || { echo "no release APKs found; build first" >&2; exit 2; }

status=0
for apk in "${APKS[@]}"; do
  perms="$("$APKANALYZER" manifest permissions "$apk" | sort -u)"
  found_internet=0
  bad=()
  while IFS= read -r p; do
    [[ -z "$p" ]] && continue
    if [[ "$p" == "${ALLOWED_EXACT[0]}" ]]; then
      found_internet=1
    elif [[ "$p" =~ $ALLOWED_PATTERN ]]; then
      :
    else
      bad+=("$p")
    fi
  done <<<"$perms"

  if [[ $found_internet -ne 1 ]]; then
    echo "FAIL $(basename "$apk"): android.permission.INTERNET is missing" >&2
    status=1
  fi
  if [[ ${#bad[@]} -gt 0 ]]; then
    echo "FAIL $(basename "$apk"): unexpected permissions: ${bad[*]}" >&2
    status=1
  fi
  if [[ $found_internet -eq 1 && ${#bad[@]} -eq 0 ]]; then
    echo "OK   $(basename "$apk"): $(echo "$perms" | tr '\n' ' ')"
  fi
done
exit $status
