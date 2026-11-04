# HARDWARE_TEST — manual device checklist (SPEC 7.3)

Skeleton created in M0; completed in M8. Fill the `Result` fields per run; keep one dated copy of the table per release candidate.

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
| A5 | Threads / Hash used (from settings or logs) | record | | threads: / hash MB: | |

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
| D3 | Ollama on LAN over `http://` (private address) | Allowed, streams | | |
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

### G. Online import, share intake and export (M7; nothing here could be built or run in the cloud container: no Android SDK)

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

## Sign-off

| Field | Value |
|---|---|
| All PASS or waived | |
| Waivers / known issues | |
| Signed off by / date | |
