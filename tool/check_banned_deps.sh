#!/usr/bin/env bash
# Fails if pubspec.lock pulls in Firebase or Google ads (SPEC section 6: no telemetry).
# Checks every pubspec.lock in the repo (the workspace root has the shared one).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mapfile -t LOCKS < <(find "$ROOT" -name pubspec.lock -not -path '*/.dart_tool/*' -not -path '*/build/*' -not -path '*/node_modules/*')
[[ ${#LOCKS[@]} -gt 0 ]] || { echo "no pubspec.lock found; run flutter pub get" >&2; exit 2; }

status=0
for lock in "${LOCKS[@]}"; do
  if grep -nE '^  (firebase_[A-Za-z0-9_]*|google_mobile_ads):' "$lock"; then
    echo "FAIL: banned dependency in $lock" >&2
    status=1
  else
    echo "OK   ${lock#"$ROOT"/}: no firebase_* or google_mobile_ads"
  fi
done
exit $status
