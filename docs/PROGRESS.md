# PROGRESS

## M0 — Research & decisions: done
See `docs/DECISIONS.md`, `docs/m0/`.

## M1 — Skeleton: done

Done:
- Monorepo: Dart pub workspace at the repo root (`pubspec.yaml`, members `packages/glyph_core` and `app`; one shared `pubspec.lock` at the root).
- `packages/glyph_core`: pure Dart, folder layout of SPEC 5.1, `util/limits.dart` (SPEC section 6 caps and timeouts) and `classify/move_label.dart` (the 11 labels), with tests.
- `app/` (`flutter create --org my.umarh --project-name glyph`): application id `my.umarh.glyph`, Kotlin DSL, minSdk 26, compile/target SDK from Flutter 3.47.9 (36).
- Riverpod 3 (`ProviderScope`; theme mode and dynamic-colour providers), `material_ui` imports only, M3 theme + `dynamic_color` + `BadgeColors` ThemeExtension (11 labels, light + dark, WCAG 4.5:1 test).
- Plain `Navigator` routes (no routing package) and placeholder screens: Library, Import sheet, Board, Report, Explain sheet, Settings, About.
- gen-l10n (`lib/l10n/app_en.arb`, generated files git-ignored, rebuilt by `flutter pub get`); no hard-coded UI strings.
- Android: `INTERNET` in the main manifest, `allowBackup=false`, `dataExtractionRules` + `fullBackupContent` excluding everything, `network_security_config` permitting cleartext, R8 minify + shrinkResources, signing from `android/key.properties` or `GLYPH_KEYSTORE_*` env vars with debug-key fallback.
- `LICENSE` (GPL-3.0 text from gnu.org), `.fvmrc` (3.47.9), `tool/check_permissions.sh`, `tool/check_banned_deps.sh`, `.github/workflows/ci.yml`.

Deviations:
- Release APK permissions are `{INTERNET, my.umarh.glyph.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION}`; the second (added by androidx.core) is allowlisted by `check_permissions.sh` as decided in M0.
- `glyph_core` depends on `test: ^1.25.0` (not ^1.33): in a workspace with the app, `flutter_test` pins `test_api 0.7.12`, which caps `test` at 1.31.x.
- `MoveLabel` enum added to `glyph_core` now because `BadgeColors` needs it; M4 should reuse it.
- Share/open-with intent filters from the M0 probe manifest were left out; they belong to M7.
- Empty directories (`app/lib/{engine,data,platform}`, `glyph_core/lib/src/*`) hold `.gitkeep`.

Next (M2): PGN import/export, game model, openings, SQLite + repositories, Library, Paste/File import.
Notes for M2: add `dartchess`, `sqlite3`, `crypto`, `http` to `glyph_core`; the workspace-root `hooks.user_defines.sqlite3` already makes Linux host tests use system libsqlite3. `app/lib/l10n/app_localizations*.dart` are generated; run `flutter pub get` after editing the ARB.
