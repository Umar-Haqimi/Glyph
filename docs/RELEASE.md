# RELEASE — checklist for a tagged build (v0.1.0)

Nothing here has been done yet. Do not tag or publish until every box is ticked. The lead/maintainer decides when to tag.

## 0. Toolchain

- [ ] Flutter 3.47.9 (`.fvmrc`), JDK 21, Android SDK platform 36 + build-tools (for `apksigner`) + cmdline-tools (`apkanalyzer`). `ANDROID_HOME` set. Network access (Gradle, `sqlite3` build hook, NNUE download).
- [ ] Clean tree on the commit to release: `git status` empty; `app/pubspec.yaml` `version: 0.1.0+1` and `app/lib/app_info.dart` `appVersion = '0.1.0'` agree (a test checks it); `CHANGELOG.md` entry dated.

## 1. Create the signing key (once; keep it forever)

```sh
keytool -genkeypair -v -keystore ~/glyph-release.jks -alias glyph -keyalg RSA -keysize 4096 -validity 10000
```
Back it up offline together with the passwords; losing it means users cannot update. Never commit it (`*.jks`, `*.keystore`, `key.properties` are git-ignored).

Tell the build about it, either with environment variables

```sh
export GLYPH_KEYSTORE_FILE=$HOME/glyph-release.jks   # absolute path
export GLYPH_KEYSTORE_PASSWORD=...
export GLYPH_KEY_ALIAS=glyph
export GLYPH_KEY_PASSWORD=...
```
or `app/android/key.properties` (`storeFile` is relative to `app/android/`, `storePassword`, `keyAlias`, `keyPassword`).

## 2. Re-record data that was only synthetic or from another engine

- [ ] **Stockfish 19 transcripts.** The M4 transcripts were recorded with Stockfish 16. With a Stockfish 19 desktop binary: `STOCKFISH_PATH=/path/to/stockfish dart run tool/record_transcripts.dart --force` (without `--force` the tool skips games that already have a transcript, so nothing would be re-recorded; see `docs/m0/VECTORS.md` section 3), then `cd packages/glyph_core && dart test`. If a `classify/*.json` expectation moves, check that the new label is right for the position before updating the vector.
- [ ] **Real SSE captures** for OpenAI, OpenRouter and Ollama plus error bodies, with the `curl` commands and redaction in `docs/m0/VECTORS.md` section 4. Replace the synthetic files one by one:
  1. Save the redacted capture over the file of the same name in `packages/glyph_core/test/vectors/sse/` (it must not contain the word "synthetic"; `grep -ciE 'sk-|bearer'` on it must print 0).
  2. In `manifest.json` set that entry's `"synthetic"` to `false` and fix its expected `text`, `finishReason` / `errorKind` (or `status`, `param`) to what the real answer says. The top-level `"synthetic"` must be `true` while any entry is still synthetic and `false` when none is (the test checks this).
  3. Run `cd packages/glyph_core && dart test test/llm/sse_vectors_test.dart`: entries marked synthetic must carry the marker, real ones must not and must be redacted.
  4. Do not run `tool/gen_sse_fixtures.dart` afterwards: it regenerates all files as synthetic and overwrites the captures.
- [ ] Optional: refresh lichess accuracy vectors (`dart run tool/fetch_lichess_vectors.dart`); the committed files are the reference.

## 3. Checks on the host

```sh
(cd packages/glyph_core && dart analyze && dart test)
(cd app && flutter analyze && flutter test)
```

## 4. Build the signed release

```sh
bash tool/build_release.sh
```
This sets `GLYPH_REQUIRE_SIGNING=1` (fails with no keystore), builds `flutter build apk --release --split-per-abi --split-debug-info=build/symbols`, then runs:

- `tool/check_signing.sh`: `apksigner verify --print-certs`; fails on the Android debug key.
- `tool/check_permissions.sh`: permissions must be exactly `INTERNET` plus `my.umarh.glyph.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`.
- `tool/check_banned_deps.sh`: no Firebase, Play Services, analytics, crash or ads SDK.

Outputs: `app/build/app/outputs/flutter-apk/app-{armeabi-v7a,arm64-v8a,x86_64}-release.apk`. Keep `app/build/symbols/` and `app/build/app/outputs/mapping/release/mapping.txt` privately (do not attach to the release).

- [ ] Decide whether to drop `libmultistockfish_chess.so` / `libmultistockfish_variant.so` (3.4 MB per ABI, untested; `docs/DECISIONS.md` M0 3.2). Default for 0.1.0: keep.
- [ ] Re-check `docs/ASSETS.md` against upstream licences (verified 2026-11-04) and that the About screen matches.

## 5. Device test

- [ ] Install the arm64-v8a APK on the primary phone (Honor LLY-NX1) and an API 26 and a latest-API emulator (x86_64 APK).
- [ ] Run `docs/HARDWARE_TEST.md` sections A to J. Copy it to `docs/hardware/<version>-<date>.md` and fill in results. Gate items: A1 (Normal, ~80 plies <= 3 min), B1/B2 (background, force-stop resume), Explain against OpenAI, OpenRouter and LAN Ollama, public `http://` blocked, airplane mode, exported PGN imported into a lichess study with glyphs, TalkBack pass, `adb logcat` shows no key or prompt.
- [ ] Run the device test: `cd app && flutter test integration_test -d <device>` (HARDWARE_TEST section I).
- [ ] Fix or document every FAIL; update `CHANGELOG.md` "Known limitations" (remove the ones now verified).

## 6. Checksums

```sh
cd app/build/app/outputs/flutter-apk
sha256sum app-armeabi-v7a-release.apk app-arm64-v8a-release.apk app-x86_64-release.apk > SHA256SUMS
sha256sum -c SHA256SUMS
```

## 7. Tag and publish

```sh
git tag -s v0.1.0 -m "Glyph 0.1.0"     # or -a
git push origin v0.1.0
```
The tag push starts `.github/workflows/release.yml`, which is the one publishing path: it checks that the tag matches `app/pubspec.yaml`, builds and signs the APKs, writes `SHA256SUMS` and creates a **draft** GitHub release `v0.1.0` whose notes are the `0.1.0` section of `CHANGELOG.md`. Review the draft (three split APKs plus `SHA256SUMS`, notes) and press **Publish release** yourself. Only if the workflow fails and cannot be fixed, build locally (sections 4 and 6) and create the release by hand with `gh release create v0.1.0 --draft --notes-file <the 0.1.0 section>` and the same four files.

- [ ] Download an attached APK and verify its SHA-256 and `apksigner verify --print-certs`.

## The release workflow

`.github/workflows/release.yml` runs on `v*` tags. Job `build` (read-only token, no persisted credentials): checks the tag against `app/pubspec.yaml` (`${GITHUB_REF_NAME#v}` must equal the version without `+build`), runs the core tests, analyze and widget tests, builds with `tool/build_release.sh`, writes `SHA256SUMS` and uploads the APKs and sums as a workflow artifact. Job `publish` (the only one with `contents: write`): downloads that artifact and creates a **draft** GitHub release with the three APKs, `SHA256SUMS` and the notes cut from that version's `CHANGELOG.md` section. Third-party actions are pinned to full commit SHAs (version in a comment); update them deliberately. Repository secrets it needs:

| Secret | Content |
|---|---|
| `GLYPH_KEYSTORE_BASE64` | `base64 -w0 glyph-release.jks` |
| `GLYPH_KEYSTORE_PASSWORD` | keystore password |
| `GLYPH_KEY_ALIAS` | key alias (`glyph`) |
| `GLYPH_KEY_PASSWORD` | key password |

It does not replace sections 2 and 5: re-recording and the device test are manual. The CHANGELOG heading must be `## [0.1.0] ...` for the notes step to find it.
