#!/usr/bin/env bash
# Fails when the project pulls in telemetry, analytics, crash reporting, ads or
# Google Play Services (SPEC section 6: "No telemetry"; section 2.3: F-Droid friendly).
#
# Checks, in the tree given as the first argument (default: the repository root):
#   1. every pubspec.lock for banned package names;
#   2. every pubspec.yaml (direct dependencies, so a ban is caught before `pub get`);
#   3. the Android Gradle files and manifests for banned Maven coordinates.
# `tool/check_banned_deps.sh` runs in CI (.github/workflows/ci.yml) and in
# app/test/hygiene_test.dart, which also feeds it planted violations.
set -euo pipefail

ROOT="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"

# Package names (a regex over the name; prefixes end in `_` or are exact).
BANNED_PACKAGES='firebase_[A-Za-z0-9_]*|firebase|cloud_firestore|google_mobile_ads|google_analytics[A-Za-z0-9_]*|sentry|sentry_[A-Za-z0-9_]*|bugsnag_[A-Za-z0-9_]*|instabug_[A-Za-z0-9_]*|datadog_[A-Za-z0-9_]*|appcenter[A-Za-z0-9_]*|amplitude_[A-Za-z0-9_]*|mixpanel_[A-Za-z0-9_]*|segment_[A-Za-z0-9_]*|posthog_[A-Za-z0-9_]*|appsflyer_[A-Za-z0-9_]*|adjust_sdk|onesignal_[A-Za-z0-9_]*|facebook_[A-Za-z0-9_]*|flutter_facebook_[A-Za-z0-9_]*|countly_[A-Za-z0-9_]*|smartlook|uxcam|flutter_uxcam|clarity_flutter|matomo_[A-Za-z0-9_]*|crashlytics|flutter_bugly|umeng_[A-Za-z0-9_]*|in_app_purchase|play_install_referrer|google_play_[A-Za-z0-9_]*|huawei_[A-Za-z0-9_]*'

# Maven coordinates / manifest entries.
BANNED_GRADLE='com\.google\.firebase|com\.google\.android\.gms|play-services|com\.google\.android\.play:|crashlytics|io\.sentry|com\.bugsnag|com\.facebook\.android|com\.appsflyer|com\.adjust|com\.mixpanel|com\.amplitude|com\.segment|com\.posthog|com\.onesignal|com\.datadog|com\.microsoft\.appcenter|com\.huawei\.hms'

status=0
found_any=0

while IFS= read -r lock; do
  found_any=1
  if grep -nE "^  (${BANNED_PACKAGES}):" "$lock"; then
    echo "FAIL: banned dependency in $lock" >&2
    status=1
  else
    echo "OK   ${lock#"$ROOT"/}: no analytics, crash-reporting, ads or Play Services package"
  fi
done < <(find "$ROOT" -name pubspec.lock -not -path '*/.dart_tool/*' -not -path '*/build/*' -not -path '*/node_modules/*')

[[ $found_any -eq 1 ]] || { echo "no pubspec.lock found; run flutter pub get" >&2; exit 2; }

while IFS= read -r spec; do
  # Dependency lines are indented by two spaces: `  name: ^1.2.3` or `  name:`.
  if grep -nE "^  (${BANNED_PACKAGES}):" "$spec"; then
    echo "FAIL: banned dependency declared in $spec" >&2
    status=1
  else
    echo "OK   ${spec#"$ROOT"/}: nothing banned declared"
  fi
done < <(find "$ROOT" -name pubspec.yaml -not -path '*/.dart_tool/*' -not -path '*/build/*' -not -path '*/node_modules/*' -not -path '*/third_party/*')

while IFS= read -r file; do
  # Comments may mention the names (they document the ban).
  if grep -vE '^\s*(//|#)' "$file" | grep -nE "$BANNED_GRADLE"; then
    echo "FAIL: banned Android dependency or manifest entry in $file" >&2
    status=1
  fi
done < <(find "$ROOT" -type f \( -name '*.gradle' -o -name '*.gradle.kts' -o -name 'AndroidManifest.xml' -o -name 'gradle.properties' \) -not -path '*/build/*' -not -path '*/.gradle/*' -not -path '*/node_modules/*' -not -path '*/.dart_tool/*')
[[ $status -eq 0 ]] && echo "OK   Android Gradle files and manifests: no Firebase, Play Services, analytics or crash SDK"

exit $status
