# HARDWARE_TEST — manual device checklist (SPEC 7.3)

Created in M0, completed in M8. Fill the `Result` fields per run; keep one dated copy of the table per release candidate (copy this file to `docs/hardware/<version>-<date>.md` and fill the copy).

**Nothing in this file has been run on a device yet.** The cloud container that built M0 to M8 has no phone or emulator; every `Result` cell is empty on purpose. Host-side measurements (Stockfish 16, for ranking settings only) are in `docs/perf/engine_bench_host.md`.

The manual checklist of SPEC 7.3 is sections A to F; sections G and H are the M7 and M8 additions; section I says how to run the automated device test; section J is the performance record sheet.

## Run header

| Field | Value |
|---|---|
| App version / commit | |
| Build (split-per-abi APK, ABI) | |
| Date | |
| Tester | |
| Flutter / NDK / AGP | 3.47.9 / 28.2.13676358 / (see docs/m0/libraries.md) |

## Devices

| ID | Device | Android / API | ABI | Role |
|---|---|---|---|---|
| D1 | Honor LLY-NX1 (primary) | | | Primary |
| E1 | Emulator, API 26 | 8.0 / 26 | x86_64 | Minimum supported |
| E2 | Emulator, latest API | | x86_64 | Latest |

## Checklist

Legend for `Result`: PASS / FAIL / N/A, plus measured values. Add a note for every FAIL.

### A. Analysis performance (D1)

| # | Step | Target | Result | Measured | Notes |
|---|---|---|---|---|---|
| A1 | Normal preset, ~80-ply game, from Analyze tap to last ply labelled | <= 3 min | | time: | |
| A2 | Fast preset, same game | <= 1 min | | time: | |
| A3 | Device temperature before / after Normal run | record | | before: / after: | |
| A4 | Battery drop over the Normal run | record | | start %: / end %: | |
| A5 | Threads / Hash used (Settings > Engine; the defaults are `min(4, cores - 2)` threads and 64 MB) | record | | threads: / hash MB: | |
| A6 | Same Normal run with Settings > Engine > Threads = 1, 2, and the default | record; the default should be the fastest or within 10% of it | | 1: / 2: / default: | Validates the choice in DECISIONS M8. If a lower count is as fast, the phone throttles: lower the default. |
| A7 | Hash 16 MB vs 64 MB vs 256 MB on the Normal run | record; no run should be slower than the 64 MB one by more than noise | | 16: / 64: / 256: | Host data: hash size does not matter at depth 16 (`docs/perf/engine_bench_host.md`). |
| A8 | Deep preset (depth 20) of the same game | record | | time: | Not a target; tells users what to expect. |
| A9 | Cold start to the library with 100 saved games (force-stop, launch, stop the clock when the list shows) | <= 2 s | | time: | Startup does no engine start and no opening-book decode (`app/test/startup_test.dart`). |
| A10 | Scroll the library with 100 saved games | no visible jank | | | The list query reads no PGN text and uses the `games_imported` index. |

### B. Lifecycle and resume

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| B1 | Background the app mid-analysis for 2 min (Honor battery management active), return | Resumes from the last completed ply, no crash | | |
| B2 | Force-stop mid-analysis, reopen | Game shows Resume; resumes from last persisted ply | | |
| B3 | Rotate device during analysis | No restart, no crash, progress kept | | |
| B4 | Rotate device while an explanation is streaming | Stream continues or ends cleanly, text kept | | |
| B5 | Kill engine process / low-memory scenario (if reproducible) | Status `failed`, Retry recreates engine | | |

### C. Import

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| C1 | Share a game from the lichess app (text) | Import screen opens with the PGN | | |
| C2 | Share a game from the lichess app (file) | Imports | | |
| C3 | Share a game from the chess.com app (text) | Imports | | |
| C4 | Share a game from the chess.com app (file) | Imports | | |
| C5 | Open a `.pgn` from the Files app via "Open with" (content URI) | Imports | | |
| C6 | Share plain text that is not PGN | Clear error, no crash | | |
| C7 | Open an oversized file (> 2 MB) | Rejected with cap message | | |

### D. Explain (LLM)

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| D1 | OpenAI endpoint, streamed explanation | Streams, cached on repeat | | |
| D2 | OpenRouter endpoint | Streams | | |
| D3 | Ollama on LAN over `http://` (private address) | Allowed, streams | | Ollama must listen on the LAN: start it with `OLLAMA_HOST=0.0.0.0` (or set it in the service config) and open port 11434 in the computer's firewall; by default it only answers on localhost. LM Studio: turn on "Serve on Local Network". |
| D4 | Public `http://` host | Blocked with the correct copy | | |
| D5 | Wrong key (401), wrong model (404) | Mapped error copy | | |
| D6 | Airplane mode: analysis works | Works | | |
| D7 | Airplane mode: Explain | Shows `offline` state | | |
| D8 | Settings > Explanations > LLM connection: save a key, restart the app, Test connection | Key survives (masked `••••abcd`), test succeeds; "Remove key" empties it | | |
| D9 | `adb logcat` during Explain, Test connection and a failing request | No key, prompt text or provider message in the log | | |
| D10 | Explain on a move, then close the sheet while it streams | Request stops (provider shows the cancelled connection), no crash | | |
| D11 | Rotate the phone while an explanation streams | Text and state survive, no second request | | |
| D12 | TalkBack on the Explain sheet while streaming | Sentences are read as they complete, never repeated; the tail and "Explanation ready." are announced once | | |
| D13 | Game summary: finish an analysis with a key set (auto on), then with auto off | Summary appears on the report by itself / "Summarize game" button; gone when the setting is off | | |
| D14 | Model that rejects `max_tokens` (o-series) with that setting chosen | Copy names `max_tokens` and says which setting to change | | |

### E. Export and interop

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| E1 | Export annotated PGN via share sheet | Share sheet opens, file name sane | | |
| E2 | Import exported PGN into a lichess study ("Import PGN") | Glyphs visible on moves, `[%eval]` accepted | | |
| E3 | Re-import the export into Glyph | Identical mainline, headers, classifications | | |

### F. Accessibility and release checks

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| F1 | TalkBack pass on the board screen | Squares, badges, nav controls announced sensibly | | |
| F2 | Release APK permission check (`tool/check_permissions.sh`) | Only `INTERNET` | | |
| F3 | `adb shell dumpsys package <id>` shows allowBackup false | Confirmed | | |
| F4 | Install on API 26 emulator (E1) and launch | Engine starts, analysis completes | | |
| F5 | Install on latest-API emulator (E2) and launch | Engine starts, analysis completes | | |
| F6 | Clear-text request to LAN host works on API 28+ (E2) | Works | | |

### G. Online import, share intake and export (M7; the release build compiles in the cloud container, but nothing here has run on a device)

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| G1 | `flutter build apk --release --split-per-abi` after M7, then `tool/check_permissions.sh` | Builds (Kotlin `MainActivity` + `ShareIntakeActivity`, `androidx.core` FileProvider); permissions still `INTERNET` + the androidx signature permission only | | |
| G2 | Import > From lichess with a real username (prefilled after Settings > Accounts) | Games stream in, speed chips filter, select two, Import: both in the library with the source "lichess" and the right side ("You") | | |
| G3 | Import > From chess.com, a user with games in several months | 30 newest games, variants (bughouse, crazyhouse) absent, import works; fetch again right away is quick (ETag 304) | | |
| G4 | Fetch twice for the same user, import, fetch again | Imported games show "In your library" and cannot be selected | | |
| G5 | Provoke a lichess 429 (fetch repeatedly) or throttle with a proxy | "Lichess asked us to slow down. Retrying in N s." counts down from 60; Cancel stops it at once; without Cancel the fetch resumes by itself | | |
| G6 | Airplane mode, then Fetch | "No connection."; a wrong username gives "has no user with that name" | | |
| G7 | lichess app: share a game as text (PGN) while Glyph is closed, then while it is open and in the background | Glyph opens on the game picker (no duplicate task, no replay when reopening from recents); Save opens the board | | |
| G8 | chess.com app: share a game (text) | Same; the preamble text before the PGN is ignored | | |
| G9 | Share a lichess / chess.com **link** to Glyph | Dialog says links are not imported and points to From lichess / From chess.com; nothing is fetched | | |
| G10 | Files app: open a `.pgn` with Glyph ("Open with"), also from Downloads and from a mail attachment; share a `.pgn` from Files | Opens the picker; a 3 MB file shows "larger than 2 MB" without freezing | | |
| G11 | Board > menu > Export PGN, and the card menu in the library | Share sheet shows a `.pgn` attachment named `White_vs_Black_date.pgn`; pick Gmail / Drive / lichess: content arrives, no storage permission prompt | | |
| G12 | Paste the exported PGN into a lichess study ("Import PGN") | See E2; plus `adb shell run-as my.umarh.glyph ls cache/shared_pgn` holds only the last export | | |
| G13 | TalkBack on the online list and the share screens | Each game is one checkbox reading players, details, selected state; the status line is announced when it changes | | |
| G14 | Share a game as text from another app while Glyph is already running in its own task (Glyph in recents, then lichess app > Share > Glyph) | Glyph comes to the front with the picker; `adb shell dumpsys activity activities` shows ONE `MainActivity` and one task for `my.umarh.glyph`; `adb shell ps` shows one process; logcat has one `main()`, one Stockfish process (`pidof stockfish` / `ps -A | grep libstockfish`) | | |
| G15 | Force-stop Glyph, then share a PGN text / open a `.pgn` (cold start) | Glyph starts in its own task and shows the picker once; Back leaves to the sender, not to a blank Glyph; opening Glyph from recents afterwards does not show the picker again | | |
| G16 | Share to Glyph, leave it on the picker, `adb shell am kill my.umarh.glyph`, reopen from recents | Glyph restores to the library or board; the old share is NOT delivered again (no second picker, no duplicate import) | | |
| G17 | Stalled provider: `.pgn` from a provider that never answers (e.g. a cloud-backed Files entry with airplane mode on, or a test provider that sleeps) | After about 0.5 s "Reading the shared file..." appears; after 15 s a dialog says reading took too long; a normal share made right afterwards works at once | | |
| G18 | Deep-link data ignored: `adb shell am start -a android.intent.action.VIEW -d "content://x/y.pgn" -n my.umarh.glyph/.MainActivity`, `... -d "file:///sdcard/a.pgn" -a android.intent.action.VIEW my.umarh.glyph`, and `-d "/board" -n my.umarh.glyph/.MainActivity` | Nothing imports and no screen opens or stacks (explicit intents without the in-process token are ignored; `file:` is never offered Glyph in Open with); also a content URI of Glyph's own provider (`content://my.umarh.glyph.fileprovider/...`) via `ShareIntakeActivity` is dropped | | |
| G19 | Export PGN: the share sheet | Glyph itself is not listed as a target; a 300 KB PGN still shares as a file (no text body) | | |

### H. Hardening (M8)

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| H1 | Install the signed release APK for the device ABI (`tool/build_release.sh`, which also runs `tool/check_signing.sh`: with `GLYPH_REQUIRE_SIGNING=1` it fails for an APK signed with `CN=Android Debug`; then `adb install`) | Installs, launcher icon is the green "!!" adaptive icon (and themed on Android 13+), name "Glyph" | | The first run of the R8-minified build on a phone: also look at H2 to H6 for missing-class crashes. |
| H2 | Release build: Settings > Explanations > LLM connection: save a key, restart the app, Test connection, Remove key | Works (flutter_secure_storage with R8) | | `adb logcat` has no `NoSuchMethod` / `ClassNotFound`. |
| H3 | Release build: Import > Open file (system picker), pick a `.pgn` | Preview opens (file_picker with R8) | | |
| H4 | Release build: share a game from another app (H2 of section G) and export a PGN | Intake and share sheet work | | |
| H5 | Release build: analyse a game | Engine starts, badges fill in | | |
| H6 | Release build: pull `adb logcat -d` after H2 to H5, and once more after provoking failures (airplane mode: Fetch from lichess with a username like `testuser123`, Explain with a wrong key; the H17 corrupt-database start) | No key, PGN, username, URL, SQL or prompt text anywhere. In the release APK Glyph's Dart code writes **nothing** to logcat (`AppLog` uses `developer.log`, a no-op in release; uncaught errors pass through `error_hooks.dart`, type only), so `adb logcat -d \| grep -i -E 'glyph\|testuser123\|sk-\|sqlite\|lichess.org/api'` shows only Android system lines (package install, activity manager) and the engine's own native start-up lines, none containing user data | | A line from Flutter's own handler ("Another exception was thrown", an exception message) would mean `installErrorHooks` is not in effect. |
| H7 | Settings > Engine: change depth preset, threads, hash; analyse a new game | The analysis uses them (Fast finishes sooner; `adb shell top -H` shows the thread count) | | A change applies to the next analysis, not to a running one. |
| H8 | Settings > Appearance: theme system / light / dark; dynamic colour off and on | Applies at once, survives a restart, no white flash at start in dark mode | | |
| H9 | Settings > Appearance: each board colour (23) and piece set (4) | The preview and the board change; every piece image shows (no empty squares) | | A missing piece image would mean an allow-list asset is absent from the APK. |
| H10 | Settings > Appearance: Move sounds on, step through a game with the arrows | One click per single step, none when jumping to the first / last move; silent when Android "touch sounds" is off (the setting's subtitle says so) | | |
| H11 | Settings > Data: Clear saved explanations (cancel first, then confirm), Clear online cache | Clear explanations asks first; messages shown, explanations gone, games kept | | |
| H12 | Export a game (board menu > Export PGN, pick any target, then come back), then Settings > Data: Delete all data (cancel first, then confirm). Check the exported file before and after: `adb shell run-as my.umarh.glyph ls cache/shared_pgn` | Before: one `.pgn` file in `cache/shared_pgn`. After Delete all data: the folder is gone or empty. Library empty, keys gone (Explain asks for setup), settings back to defaults, no crash; an analysis that was running stops. Also: export, then delete that one game (swipe or board menu) and list again: folder empty; export, force-stop and start the app: folder empty | | `shared_pgn` is `Context.cacheDir/shared_pgn`; Dart reaches it through `getTemporaryDirectory()` (the same directory on Android). |
| H13 | Settings > About | Version 0.1.0, GPL notice, source link copies, credits, every asset listed, privacy text; "Open-source licences" shows Glyph, the assets ("Glyph asset: ...") and the packages | | |
| H14 | TalkBack on: Library, Import sheet, Paste, From lichess (results), Settings and every dialog, LLM connection, Board, Key moments, Explain sheet, Report, About | Every control has a name and a state; headings are announced and can be jumped between; reading order matches the screen; dialogs read their title first | | `app/test/features/accessibility_test.dart` checks structure; this checks how it sounds. |
| H15 | Font size at the largest setting plus Display size at the largest (Settings > Display) on a small phone | No clipped or overlapping text on any screen above; everything reachable by scrolling | | The widget tests cover 360x740 at 2.0x. |
| H16 | Dark theme and light theme on every screen; one pass with "Remove animations" on | Text readable; badges legible on both board colours; no motion with animations off | | |
| H17 | Corrupt the database on a test device (`adb shell run-as my.umarh.glyph sh -c 'echo junk > files/glyph.db'`), start the app. Then install an older build over a newer one's data (or set `PRAGMA user_version = 99` on a copy) and start it. | Corrupt file: "Glyph can't open its data" with Try again and Delete the database (the confirmation lists games, analyses, saved explanations, settings incl. LLM configuration, accounts, appearance, API keys); deleting also erases the keys and starts fresh. Newer database: "saved by a newer version of Glyph ... Update Glyph", Try again, and only a small "Delete the data anyway..." behind two confirmations. If the storage is full: "Free some space" and Try again, no delete button. | | |
| H18 | `adb shell run-as my.umarh.glyph ls -R .` after a normal session | No file outside `databases`/`files`/`cache`/`shared_prefs`; no PGN or key in plain text (`grep -r sk- .` finds nothing) | | |

### I. The device integration test

`app/integration_test/engine_device_test.dart` runs the real `multistockfish` engine (Stockfish 19 light net) through `EngineService` and SQLite: a 30-ply game at Fast, every position labelled, eval sign sanity on a known winning position, cancel and resume. It uses tolerant assertions only (SPEC trap 8) and is tagged `device`; plain `flutter test` does not run it.

```
cd app
flutter devices                       # pick an emulator or a phone (USB debugging on)
flutter test integration_test/engine_device_test.dart -d <device id>
# without the pub step: add --no-pub
```

`flutter analyze` compiles it on every CI run, so it cannot rot unnoticed. Expected: all tests pass in under two minutes on a phone; on the x86_64 emulator expect about 1.3 s for a depth-12 position with 4 threads. A failure with `StateError: A light engine is already live` means another Glyph engine is running on the device (force-stop the app and retry).

| # | Step | Expected | Result | Notes |
|---|---|---|---|---|
| I1 | Run the test above on D1 | All tests pass | | |
| I2 | Run it on E1 (API 26 emulator) | All tests pass | | |
| I3 | Run it on E2 (latest API emulator) | All tests pass | | |

### J. Performance record sheet (SPEC 7.3 targets)

| Measure | Target | D1 result | Host reference (Stockfish 16, 4 cores) |
|---|---|---|---|
| ~80-ply game, Normal (depth 16), MultiPV 2 | <= 3 min | | 27 to 45 s for 74 plies depending on threads |
| Same game, Fast (depth 12) | <= 1 min | | 6.6 to 8.7 s |
| Cold start to the library | <= 2 s | | |
| Battery drop over the Normal run | record | | |
| Temperature rise over the Normal run | record | | |

If a target is missed, the knobs are in Settings > Engine (threads, hash) and the defaults in `app/lib/features/settings/engine_settings.dart` (`EngineDefaults`); see `docs/DECISIONS.md`, "M8 decisions", for why the defaults are what they are.

## Sign-off

| Field | Value |
|---|---|
| All PASS or waived | |
| Waivers / known issues | |
| Signed off by / date | |
