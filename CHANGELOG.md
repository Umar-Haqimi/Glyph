# Changelog

All notable changes to Glyph are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/).

## [0.1.0] - Unreleased (planned 2026-11-04 or later; not tagged yet)

First version. Android only (minSdk 26), GPL-3.0-or-later.

### Added
- Import: paste PGN (live validation, multi-game picker, errors that name the game and ply), open a `.pgn` file, Android Share / "Open with" (text and files), fetch the last 30 games of a lichess or chess.com user.
- On-device analysis with Stockfish 19 (embedded light network) at Fast 12 / Normal 16 / Deep 20, MultiPV 2, per-position persistence, cancel, pause and resume (app backgrounded, killed, or engine crash).
- Move classification: Book, Forced, Brilliant, Great, Best, Excellent, Good, Inaccuracy, Mistake, Miss, Blunder, on lichess's Win% curve with expected-points loss bands; lichess-exact accuracy per player; key moments; opening name.
- Analysis board: badges on the destination square, best-move arrow, Win% eval gauge, top two engine lines, eval graph, move list, swipe/keys/buttons navigation, flip, player strips with clocks, coach card, Key moments sheet, report with label table.
- Explain: streamed, grounded explanation of any move from an OpenAI-compatible endpoint (OpenAI, OpenRouter, Ollama, LM Studio, custom), cached, View prompt, Copy, Regenerate. Optional game summary (casual or coach tone).
- LLM safety: API key in Android Keystore-backed storage and bound to the address it was saved for, `http://` only for private/local addresses and only after a per-address opt-in for sending the key, no names or ratings in prompts.
- Annotated PGN export (NAGs, `[%eval]`, `[%clk]`, `[Annotator "Glyph"]`) through the share sheet.
- Settings: engine, explanations, accounts, appearance (theme, dynamic colour, board colours, four free piece sets), data management. About screen with licences.
- Release hardening: R8, `INTERNET` as the only (non-signature) permission, no backup, no telemetry, `tool/build_release.sh` with mandatory signing.

### Known limitations
- Nothing has been run on a physical device or emulator yet; the checklist is `docs/HARDWARE_TEST.md`. Timings (<= 3 min for 80 plies at Normal), battery, TalkBack, the share/Open-with intents and the Kotlin code at run time are unverified.
- The SSE test vectors for OpenAI, OpenRouter and Ollama are **synthetic** (hand-built from the documented formats); real captures are still to be recorded.
- Most recorded UCI transcripts behind the classification vectors were made with Stockfish 16 (the M0/M3 ones with Stockfish 19); re-recording with Stockfish 19 may move a few borderline labels.
- Classification approximates chess.com's published thresholds on lichess's curve; it does not reproduce chess.com's Game Review.
- Android only; standard chess and Chess960 only; view-only board (no free exploration); English UI only; the source link is copied, not opened.
- The APK also contains two unused engine libraries (`libmultistockfish_chess.so`, `libmultistockfish_variant.so`, about 3.4 MB per ABI).
