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

## Sign-off

| Field | Value |
|---|---|
| All PASS or waived | |
| Waivers / known issues | |
| Signed off by / date | |
