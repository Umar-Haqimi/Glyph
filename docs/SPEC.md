# SPEC — "Glyph": on-device Stockfish game review for Android, with LLM-written move explanations

> **Working name:** Glyph (after chess annotation glyphs: `!!`, `!`, `?!`, `?`, `??`). Rename freely. Application ID: `my.umarh.glyph`.
>
> This document is the **single source of truth** for an autonomous build by Claude Code. Build it milestone by milestone (section 8) without coming back to ask questions. Where something is unspecified, pick the simplest option consistent with this spec and record it in `docs/DECISIONS.md`.
>
> **Precedence rule:** when this spec and an upstream source disagree (lichess `lila`, `lichess-org/mobile`, `chessground`, `dartchess`, `dart-multistockfish`, Stockfish, the OpenAI API docs), **upstream source code wins**. Record the discrepancy and the file/line reference in `docs/DECISIONS.md`.

---

## 1. What we're building

Glyph is an open-source Android app for reviewing chess games. It imports games (PGN paste, `.pgn` files, Android share, or by lichess/chess.com username), runs **Stockfish on the device** over every position, labels each move with a move classification (Brilliant, Great, Best, … Blunder, Miss), and shows the result on a lichess-style analysis board. When the user wants to know *why* a move got its label, an **"Explain" button** sends engine-computed facts to a user-configured, OpenAI-compatible LLM, which streams back a short, plain-language explanation. An optional game summary gives a casual or coach-style recap of the whole game.

**The core design rule (non-negotiable): the engine judges, the LLM narrates.** The LLM is never asked to evaluate a position or invent variations. It only gets numbers, lines and facts computed by Stockfish and by deterministic code.

Main capabilities:
1. **Import**: paste PGN, open/share `.pgn` files and PGN text, fetch recent games by lichess or chess.com username.
2. **Review**: full-game Stockfish analysis on device, with a classification per move, accuracy per player and key moments.
3. **Analysis board**: lichess-inspired board with move badges, eval bar, engine lines, eval graph and move navigation.
4. **Explain**: grounded, streamed LLM explanation of any single move, cached locally.
5. **Game summary** (toggleable): a casual or coach-tone LLM recap of the game.
6. **Export**: share an annotated PGN (NAGs + `[%eval]` comments) that opens in lichess.

**Platform:** Android only (minSdk 26), Flutter (latest stable, ≥ 3.47), Material 3. Keep the core free of Android specifics so iOS stays possible later (`multistockfish` supports iOS).

**Interop requirement (non-negotiable):**
- **Import:** PGN exported by lichess.org (web export, API, mobile app share) and chess.com (download, API, mobile app share) must import with **no loss of mainline moves or standard headers**, including files with `[%clk]`/`[%eval]` comments, NAGs, variations and multiple games.
- **Export:** Glyph's annotated PGN must (a) re-import into Glyph with identical mainline, headers and classifications reconstructible, and (b) import into a lichess study ("Import PGN") with NAG glyphs shown on moves and `[%eval]` values accepted.

**Non-goals (v1):**
- Playing games, puzzles, accounts/OAuth, any server-side component. The app talks only to lichess/chess.com public APIs and the user's LLM endpoint.
- Variants other than standard chess and Chess960 (crazyhouse etc. → clear "not supported" error).
- Free exploration on the board (playing your own side lines with live engine eval). **Leave a clean extension point**: the board screen must take a `PositionCursor` abstraction, not a raw mainline index, so variations can be added later (N2).
- Downloading the full-size Stockfish net (N3). v1 ships the embedded light net.
- Board-photo/screenshot scanning, cloud analysis, iOS builds, tablet/landscape polish (N4).
- Using chess.com's trademarks, icons or exact proprietary model. Glyph has its *own* classification badges and calls the feature "move classification", never "chess.com review".

---

## 2. Critical technical facts (read before designing)

### 2.1 How the underlying thing works

**Pipeline**
```
PGN text ─► parse (dartchess) ─► mainline positions P0..PN (+ start FEN, variant)
        ─► Stockfish per position (MultiPV 2, fixed depth, full move history)
        ─► scores normalized to WHITE point of view ─► Win% per position
        ─► per-move: expected-points loss + special rules ─► classification
        ─► accuracy per player (lichess algorithm) ─► key moments
        ─► (on demand) prompt builder ─► OpenAI-compatible Chat Completions (SSE stream)
```

**Win% (from lichess).** Lichess turns centipawns into a win chance with:
`Win% = 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1)` (documented at <https://lichess.org/page/accuracy>, implemented in lila `WinPercent` and `ui/ceval/src/winningChances.ts`). Glyph uses this curve for everything: eval bar, classification and accuracy. **Read the source** for the cp clamp and the mate → cp conversion (from memory: cp clamped to ±1000; mate N mapped to a large cp that shrinks with N, but extract the exact code).

**Expected-points loss.** For move *i* played by side S from position Pi:
- `W_best_before` = Win% of the best engine line at Pi, from S's point of view.
- `W_after` = Win% of the position after the played move, from S's point of view (see trap 3 for how to get it consistently).
- `EP_loss = max(0, (W_best_before − W_after) / 100)`.

**Base classification by EP loss.** Chess.com publishes these cutoffs for its expected-points model (<https://support.chess.com/en/articles/8572705>). Glyph uses the same table on top of the lichess Win% curve (chess.com's own curve is rating-dependent and unpublished, so this is an approximation; note that in the README):

| Label | EP loss lower | EP loss upper |
|---|---|---|
| Best | 0.00 | 0.00 (played move = engine top move) |
| Excellent | 0.00 | 0.02 |
| Good | 0.02 | 0.05 |
| Inaccuracy | 0.05 | 0.10 |
| Mistake | 0.10 | 0.20 |
| Blunder | 0.20 | 1.00 |

**Special classifications (Glyph's own rules, applied in this precedence order, first match wins):**
`Book → Forced → Brilliant → Great → Miss → Best → Excellent → Good → Inaccuracy → Mistake → Blunder`

All numeric constants below live in one `ClassifierConfig` class (pure Dart, documented, unit-tested). Piece values: P=1, N=3, B=3, R=5, Q=9.

- **Book**: the game starts from the standard initial position, every previous ply was Book, and the EPD of the position *after* the move is in the bundled openings set. Match by **position (EPD), not move order** (trap 7). Never Book for FEN-start or Chess960 games.
- **Forced**: the position had exactly one legal move. No badge colour emphasis; still counted in accuracy (as lichess does).
- **Brilliant (`!!`)**: all of:
  1. `EP_loss ≤ 0.02` (Best or Excellent);
  2. the move is a **sacrifice** by the SEE rule: after the move, some opponent capture of one of S's pieces has static-exchange gain ≥ 2 for the opponent, **or** the move itself is a capture with SEE ≤ −2 for S (trap 6);
  3. `W_after ≥ 50` (S is not worse after the sacrifice) and `W_best_before ≤ 97` (S wasn't already completely winning);
  4. not Forced.
- **Great (`!`)**: the "only move". All of:
  1. the played move equals the engine's top move;
  2. MultiPV line 2 exists and `W(line1) − W(line2) ≥ 20` Win% points from S's POV;
  3. the outcome bucket changes between line 1 and line 2 (buckets for S: losing < 30, unclear 30–70, winning > 70);
  4. **not** an obvious recapture (the move captures on the square where the opponent's previous move captured) and not Forced.
- **Miss**: S failed to punish an opponent error. Either:
  - (a) the opponent's previous move had `EP_loss ≥ 0.10`, S's move has `EP_loss ≥ 0.10`, and `W_after` ≤ (S's Win% *before* the opponent's error) + 5, so S gave back most of the gift; **or**
  - (b) the best line at Pi is a forced mate for S in ≤ 5, the played move does not keep a forced mate, and `EP_loss ≥ 0.05`.
  - **Exception:** if the move would be a Blunder **and** `W_after < 50`, label it Blunder, not Miss.

**Accuracy.** Per-move and per-game accuracy follow lila `modules/analyse/src/main/AccuracyPercent.scala` exactly. Per move it is roughly `103.1668 * exp(-0.04354 * (Win%_before − Win%_after)) − 3.1669`. Per game it is the average of a volatility-weighted mean and a harmonic mean over sliding windows. Extract the full-precision constants, clamping and windowing from source.

**UCI protocol** (<https://backscattering.de/chess/uci/> and Stockfish docs). Session: `uci` → wait `uciok` → `setoption name Threads value N` / `Hash` / `MultiPV value 2` / `UCI_Chess960 value true|false` → `isready` → wait `readyok`. Per game: `ucinewgame` → `isready`/`readyok`. Per position: `position fen <startFen> moves <m1 … mi>` (**always with history**, trap 9) → `go depth D` → parse `info … multipv k … score cp X | score mate Y … pv …` → `bestmove`.

**Engine package.** `multistockfish` (lichess.org, GPL-3.0, <https://pub.dev/packages/multistockfish>, repo <https://github.com/lichess-org/dart-multistockfish>):
- `StockfishFlavor.light` (default): **Stockfish 19 with an embedded ~1.1 MB NNUE**, no download needed. Glyph v1 uses this.
- `StockfishFlavor.latestNoNNUE`: Stockfish 19 without a net, needs `nnuePath` (for N3).
- API: `await Stockfish.create(flavor:, onStdout:)`, write commands to `stdin`, read lines from `stdout`, `state` is a `ValueListenable<StockfishState>`, `dispose()` sends `quit`.
- **Only one engine per flavor can run at a time**; a second `create()` throws `StateError` (trap 5).
- Running engines interfere with hot reload, so dispose before reloading.

**LLM API.** OpenAI-compatible Chat Completions: `POST {baseUrl}/chat/completions` with `Authorization: Bearer <key>`, body `{model, messages, stream: true}`, response is Server-Sent Events (`data: {json}` lines, terminated by `data: [DONE]`). This one shape works with OpenAI, OpenRouter, Ollama (`http://host:11434/v1`), LM Studio and llama.cpp server. **Do not use the OpenAI Responses API** (not supported by most compatible servers).

**Online sources.**
- Lichess: `GET https://lichess.org/api/games/user/{username}` (spec: <https://github.com/lichess-org/api>), `Accept: application/x-ndjson`, params `max`, `perfType`, `pgnInJson=true`, `clocks`, `evals`, `opening`, `sort`. No auth needed. Anonymous throughput is throttled to 20 games/s. Stream the response. After a 429, wait a full minute.
- Chess.com: `GET https://api.chess.com/pub/player/{username}/games/archives` → list of monthly URLs (ascending) → `GET …/games/{YYYY}/{MM}` → `{games:[{pgn, rules, time_class, white{username,rating,result}, black{…}, end_time, url, …}]}`. Serial requests are unlimited, parallel ones may get 429. Send a recognizable `User-Agent` (app name + repo URL, **not** the user's email). Respect `ETag`/`If-None-Match`. Handle 404 (no user) and 410.

**Openings.** `lichess-org/chess-openings` (<https://github.com/lichess-org/chess-openings>, CC0): `a.tsv`…`e.tsv` with `eco`, `name`, `pgn`. The generated `dist/` adds `uci` and `epd`. A build-time Dart tool converts them into one compact asset (`assets/openings.bin` or `.tsv.gz`) mapping EPD → (eco, name). Upstream advises classifying by walking moves backwards to the last named position. Glyph names the game's opening by the **deepest** Book position reached.

**Things the spec leaves out (extract from upstream, record in `docs/DECISIONS.md` with file/line refs):**
- Exact mate → cp conversion and cp clamp in lila `WinPercent` and `ui/ceval/src/winningChances.ts`.
- Full-precision `AccuracyPercent` constants, the +bonus/clamp logic, `gameAccuracy` window size, weight clamping, and how the start colour / first move is aligned.
- How `dartchess` represents castling internally (king-to-rook?), and the exact functions for UCI ↔ move ↔ SAN conversion, including standard vs Chess960.
- `dartchess` PGN API: multi-game parsing, comments (`[%clk]`, `[%eval]`), NAGs, headers, variations, error reporting (does it report line/ply?).
- `chessground` (current: 10.x, depends on `dartchess` ^0.14) API for **move annotations on a square**, **arrows/shapes**, last-move highlight, non-interactive viewing mode, piece sets and board themes. Check how `lichess-org/mobile` draws annotations and the eval gauge.
- `multistockfish`: whether `stdout` emits exactly one line per event, Threads/Hash limits on mobile, required NDK version, ABIs built.
- Flutter ≥ 3.47 split Material and Cupertino into standalone packages: the exact package/import names and theming APIs to use.
- Lichess export JSON: the field names for per-player accuracy and analysis evals, and which param enables them (for golden vectors, 7.1).
- Chess.com monthly archive: confirm `time_class`, `rules`, `accuracies` are present in real responses.
- A **maintained** Flutter markdown renderer (if none fits, render plain text with simple `**bold**` handling).
- The exact Android manifest/network-security-config changes for the cleartext policy (section 6).
- The piece sets and board themes in `chessground` with **free licences** (section 2.2, trap 15).

### 2.2 ⚠️ Compatibility traps

1. **P0: score perspective.** UCI `score cp/mate` is from the **side to move's** point of view. Storing it raw makes every Black move's eval flip sign, so Black blunders show as brilliancies.
   → Normalize **every** score to White's POV at the parser boundary, in exactly one function (`toWhitePov(score, sideToMove)`). Store White POV in the DB. Convert to mover POV only inside the classifier and prompt builder.
   **P0 test:** the same blunder, mirrored for both colours, must give the same label and mirrored evals.
2. **Castling encoding.** `dartchess` (like `chessops`) may represent castling as king-takes-rook (`e1h1`), while Stockfish in standard mode outputs `e1g1`. A raw string compare of "played move == best move" then fails for every castle, so castling is never "Best" and can be labelled a Mistake.
   → Compare **normalized `Move` objects** (parse engine UCI through `dartchess` with the position), never UCI strings. Set `UCI_Chess960` correctly per game. Test: castling that Stockfish recommends is labelled Best.
3. **Depth-inconsistent loss.** Evaluating Pi's best line and the position after the played move as separate searches gives different numbers even when the played move *is* the best move. Best moves then get small phantom losses ("Excellent" instead of "Best").
   → If the played move equals line 1, `EP_loss = 0` exactly. If it equals line 2, use line 2's score from the same search. Otherwise use the negated score of P(i+1)'s own search. Every position is searched once, at one depth, and results are reused.
4. **UCI output parsing.** Pitfalls: `info` lines with `lowerbound`/`upperbound` (partial scores, **skip them**); `info currmove …` lines with no score; `info string …` lines; lines for different `multipv` values arriving interleaved; `score mate 0` and `bestmove (none)` on terminal positions.
   → Keep the last *exact-bound* score per `multipv` at the highest completed depth; finalize on `bestmove`. **Never send `go` for checkmate/stalemate/insufficient-material positions.** Compute those directly (checkmate → 100/0 for the mating side, draws → 50).
5. **Engine lifecycle.** Only one engine per flavor may exist (`StateError` otherwise). `stop` must be followed by waiting for `bestmove` before the next `go`. `position`/`go` before `readyok` gives undefined results. Hot reload breaks with live isolates.
   → One app-scoped `EngineService` owns the single engine and a serial job queue. Every command sequence is `isready`→`readyok`-synchronised. Cancellation = `stop` + await `bestmove` (2 s timeout → `dispose()` and recreate). Dispose on app pause and in debug before hot reload.
6. **Naive sacrifice detection.** "Material dropped after the move" flags ordinary trades (QxQ, then a recapture) and recaptures as Brilliant.
   → Use static exchange evaluation (SEE) on the position after the move, exactly as defined in 2.1. Must-not tests: a queen trade, a normal recapture and a pawn trade must never be Brilliant.
7. **Book by move sequence.** Matching opening move *strings* misses transpositions (1.Nf3 d5 2.d4 vs 1.d4 d5 2.Nf3).
   → Match EPD of the position after the move (with en passant only if legal, matching upstream's EPD convention). Stop Book at the first non-book ply. Test a transposition.
8. **Desktop vs device net.** Golden vectors recorded with desktop Stockfish 19 (full ~94 MB net) will **not** match the on-device light net (p_hm feature set, ~1.1 MB).
   → Classifier/accuracy tests replay **recorded UCI transcripts** through a fake engine. On-device integration tests use tolerant assertions only (every ply classified, no crash, eval sign sanity). **Never assert exact centipawns from the device engine.**
9. **Lost game history.** `position fen <current>` drops move history, so Stockfish can't see threefold repetition or the 50-move rule. Drawn-by-repetition positions then get evaluated as +3.
   → Always send `position fen <startFen> moves <all moves so far>` (or `position startpos moves …`).
10. **PGN quirks.** Chess.com and lichess add `{[%clk 0:09:58.9]}` and `[%eval]` comments. Files can hold many games, start with a UTF-8 BOM, use CRLF, contain variations, NAGs, `{}` comments with odd characters, `[SetUp "1"][FEN …]`, `[Variant "Chess960"]`, or non-standard variants.
    → Strip the BOM and normalize newlines. Parse multi-game files. Keep the mainline only. Read `%clk` for display. Reject unsupported variants with a clear message. Report illegal moves with game index + ply + SAN.
11. **LLM hallucination.** Sending UCI (`g1f3`) or only an eval number makes models invent lines and pieces.
    → Send **SAN only**, the full FEN, the engine's best line, the **refutation line** (engine PV after the played move), material before/after, hanging pieces (from SEE), and flags. The system prompt forbids moves not in the provided lines. Snapshot-test the prompt.
12. **OpenAI parameter drift.** Newer OpenAI models reject `max_tokens` (they need `max_completion_tokens`), and reasoning models reject a non-default `temperature`, while some compatible servers reject `max_completion_tokens`.
    → **Send neither `temperature` nor any token-limit param by default.** Settings offer "Token limit parameter: none / max_tokens / max_completion_tokens" plus a value. Map a 400 `unsupported_parameter` error to clear copy telling the user which setting to change.
13. **Release build has no network.** Flutter templates declare `INTERNET` only in the debug/profile manifests, so release APKs silently fail every request.
    → Declare `android.permission.INTERNET` in `android/app/src/main/AndroidManifest.xml`. The permission-check script (section 6) asserts it is present in the release APK.
14. **Cleartext LAN LLMs.** Android blocks `http://` by default (API 28+), so `http://192.168.1.5:11434/v1` (Ollama on a homelab) fails with an opaque error.
    → Implement the cleartext policy from section 6 and show specific copy when cleartext is the cause.
15. **Asset licences.** An open-source/F-Droid build must not ship non-free graphics (F-Droid flags the lichess app with a NonFreeAssets anti-feature).
    → Ship only piece sets/boards whose licences are free (e.g. cburnett). List each asset and licence in `docs/DECISIONS.md` and the About screen. Badge icons are Glyph's own vector drawings.
16. **Linear eval bar.** Mapping cp linearly to bar height makes +8 and +20 look identical and small swings invisible.
    → Bar height = White Win% (2.1). Show mate as a full bar plus a `#N` label.
17. **Stale explanation cache.** Caching by FEN+move only serves old text after the user changes model, language or tone.
    → Cache key = `sha256(promptVersion | kind | fenBefore | moveUci | label | model | language | tone | userSide)`. Bump `promptVersion` whenever the prompt template changes.
18. **Personal data to the LLM.** Player names/usernames aren't needed for an explanation.
    → Never send names, ratings, usernames, event names or dates to the LLM. Use "White", "Black" and "you".

### 2.3 Libraries

Record final versions, licences and any fallback taken in `docs/DECISIONS.md`. **All dependencies must be GPL-3.0-compatible and free of Google Play Services/Firebase/analytics** (F-Droid friendly).

| Concern | Library | Licence | Verify early (M0) | First fix → fallback |
|---|---|---|---|---|
| Board UI | [`chessground`](https://pub.dev/packages/chessground) ^10.3 | GPL-3.0 | square annotations, arrows, view-only mode, piece sets | use its API → `Stack` overlay positioned per square |
| Rules / PGN / SAN | [`dartchess`](https://pub.dev/packages/dartchess) (version chessground requires, ^0.14) | GPL-3.0 | multi-game PGN, comments, NAGs, castling repr, Chess960 | its parser → pre-split games on header blocks before parsing |
| Engine | [`multistockfish`](https://pub.dev/packages/multistockfish) ^0.6.1, `StockfishFlavor.light` | GPL-3.0 | builds with current Flutter/NDK, Threads works, per-line stdout | — → [`stockfish_flutter_plus`](https://pub.dev/packages/stockfish_flutter_plus) (GPL-3.0) |
| State | `flutter_riverpod` (as in lichess mobile) | MIT | — | — |
| Database | `sqlite3` + `sqlite3_flutter_libs`, **raw SQL** | MIT | host-side tests work with system libsqlite3 | — → `sqflite` + `sqflite_common_ffi` |
| Secrets | [`flutter_secure_storage`](https://pub.dev/packages/flutter_secure_storage) ^11.2, default `AndroidOptions()` | BSD-3 | backup interaction (section 6) | — |
| HTTP + SSE | `http` (streamed requests; `MockClient` in tests) | BSD-3 | streaming over cleartext/LAN | — |
| Share / open-with | [`receive_sharing_intent`](https://pub.dev/packages/receive_sharing_intent) ^1.9 | verify (Apache-2.0 expected) | shared **text** arrives; `VIEW` content URIs | — → small Kotlin `MethodChannel` in `MainActivity` |
| File picking | `file_picker` (SAF, no storage permission) | MIT | adds no permissions | — |
| Dynamic colour | `dynamic_color` | Apache-2.0 | — | seed colour |
| Eval graph | **custom `CustomPainter`** (no chart lib) | — | — | — |
| Hashing | `crypto` | BSD-3 | — | — |
| Openings data | lichess-org/chess-openings TSV | CC0 | — | — |

---

## 3. Features

### MVP (must ship)

| # | Feature |
|---|---|
| F1 | **Paste PGN** import with live validation, multi-game picker (shows White–Black, result, date, move count) and error messages that name the game and ply |
| F2 | **Open `.pgn`** via the system file picker, and via Android "Open with" / **Share** (both files and plain-text PGN from the lichess and chess.com apps) |
| F3 | **Game library**: saved games with players, result, date, source, analysis status (none / partial % / done), accuracy chips, swipe-to-delete with undo |
| F4 | **On-device analysis**: whole game at a depth preset (Fast 12 / Normal 16 / Deep 20, MultiPV 2), progress, cancel, **resume** after cancel/app kill/background (per-ply results persisted), badges fill in progressively while it runs |
| F5 | **Move classification**: Book, Forced, Brilliant, Great, Best, Excellent, Good, Inaccuracy, Mistake, Miss, Blunder per section 2.1; badge in the move list **and** on the destination square of the current move |
| F6 | **Report card**: accuracy per player (lichess algorithm), per-label count table per player, opening name (ECO + name) |
| F7 | **Board navigation**: tap any move, first/prev/next/last buttons, horizontal swipe below the board, flip board, player strips with name/rating and the clock at that move when `%clk` exists |
| F8 | **Eval bar** (Win%-scaled) plus the top 2 engine lines for the current position from stored analysis, shown in SAN with eval (`+1.3`, `#4`, `-#2`) and depth |
| F9 | **Eval graph** (Win% over plies, tap/drag to jump) with key-moment markers, plus a **Key moments** sheet listing every Brilliant, Great, Miss, Mistake and Blunder for each side |
| F10 | **Coach card** under the board for the current move: badge, label, a deterministic one-liner ("Best was Bd3 (+0.8). After Nxe5, eval is −2.4.") and the **Explain** button (filled tonal for Brilliant/Great/Miss/Inaccuracy/Mistake/Blunder, outlined otherwise; available on every move) |
| F11 | **Explain**: grounded prompt (section 5.4), streamed into a bottom sheet, cancel on close, Regenerate, Copy, "View prompt" (shows the exact JSON sent), cached (trap 17) |
| F12 | **Game summary** (Settings toggle, default **on**; tone **Casual** default / Coach): generated automatically when analysis completes if a key is set, otherwise on tap. Shown in the report card, cached, Regenerate |
| F13 | **LLM settings**: provider presets (OpenAI, OpenRouter, Ollama, LM Studio, Custom) that prefill the base URL; base URL; API key (secure storage, masked, Remove); model name; token-limit param mode + value; **Test connection** (tiny non-streamed request, reports success or a specific error) |
| F14 | **Explanation settings**: language (default "match app language", free-text override, e.g. "Bahasa Melayu"), tone (Casual / Coach), audience level (Beginner / Club / Advanced) |
| F15 | **Your side**: configured lichess and chess.com usernames auto-detect which side the user played (case-insensitive header match, or known from an online import). Per-game manual override. Prompts say "you" for the user's moves; board auto-orients to the user's side |
| F16 | **Fetch from lichess** by username: last 30 finished games streamed in, filter chips by speed, tap to import (dedupe by source + game ID) |
| F17 | **Fetch from chess.com** by username: walk archives newest-first until 30 games, same UI and dedupe |
| F18 | **Export annotated PGN** via the Android share sheet: original headers + `[%eval]` per move + NAGs (Brilliant `$3`, Great `$1`, Inaccuracy `$6`, Mistake `$2`, Blunder `$4`, Miss `$2` + `{Miss}` comment) + an `[Annotator "Glyph"]` header |
| F19 | **Settings (general)**: engine preset, threads (default `min(4, cores−2)`, min 1), hash (default 64 MB); theme (system/light/dark, dynamic colour on/off); board theme and piece set (free-licensed only); move sounds on/off |
| F20 | **About & licences**: version, GPL-3.0-or-later notice, source repository link, Stockfish credit and licence, Flutter `showLicensePage`, asset licence list, privacy summary (what is sent where) |

### Nice-to-have (after MVP, in this order)

| # | Feature |
|---|---|
| N1 | **Explain all key moments**: batch with a confirmation that shows the count, sequential requests, progress, cached |
| N2 | **Free exploration**: play side lines on the board with live engine eval, plus "Explain this line" |
| N3 | **Stronger engine**: optional download of the full Stockfish 19 net (~94 MB) for `latestNoNNUE`, with checksum verification and a Wi-Fi-only toggle |
| N4 | Landscape/tablet two-pane layout |
| N5 | **Follow-up questions** in the Explain sheet (chat grounded in the same facts plus extra engine queries) |
| N6 | Accuracy per phase (opening/middlegame/endgame) using lichess's Divider |
| N7 | Start from FEN / board editor |
| N8 | Malay UI translation (`app_ms.arb`) |
| N9 | Board screenshot scanning (explicitly last) |

---

## 4. UX / Screens

**Style:** Material 3, **dynamic colour** on Android 12+ (seed colour fallback), edge-to-edge, light and dark. Motion: piece moves animate ~150 ms (none when jumping more than 1 ply); badges pop in with a short scale animation as analysis fills them in. Layout inspired by lichess's analysis board, but **not** a clone of lichess branding. If Stitch mockups exist in `docs/design/`, they override the layout details here (not the behaviour).

**Badge set** (Glyph's own vector icons; never colour-only, the glyph text is always visible; colours defined in a `ThemeExtension` with contrast checked in both themes):

| Label | Glyph | Colour role |
|---|---|---|
| Brilliant | `!!` | teal |
| Great | `!` | blue |
| Best | ★ | green |
| Excellent | ✓ (filled) | light green |
| Good | ✓ | grey-green |
| Book | book icon | tan |
| Forced | → | grey |
| Inaccuracy | `?!` | yellow |
| Mistake | `?` | orange |
| Miss | ✕ | magenta |
| Blunder | `??` | red |

### Screens and flows

1. **Library (home).** App bar: "Glyph", settings icon. List of game cards. Empty state: illustration plus "Import your first game" button. FAB **Import** opens the import sheet.
2. **Import sheet**: four rows: *Paste PGN*, *Open file*, *From lichess*, *From chess.com*.
   - Paste: Import → Paste PGN → text field (live validation: "1 game found" / "3 games found" / error) → [if > 1 game] pick a game → Save → **Analysis board** opens and analysis starts.
   - File: Import → Open file → system picker → parse → [pick] → Save → board.
   - Share: other app → Share/Open with → Glyph → parse → [pick] → Save → board.
   - Lichess: Import → From lichess → username (prefilled from settings) → games stream in → filter chips (Bullet/Blitz/Rapid/Classical/Correspondence) → tap → Save → board.
   - Chess.com: same as lichess, with filters Bullet/Blitz/Rapid/Daily.
3. **Analysis board** (portrait, top to bottom):
   - App bar: "White – Black", overflow menu (Flip, Re-analyse at depth…, Export PGN, Set your side, Delete).
   - Thin horizontal **eval gauge** (Win%, White POV) with a numeric label.
   - **Top player strip** (name, rating, clock at this ply).
   - **Board**: full width, view-only in v1, last-move highlight, badge on the destination square, best-move arrow (toggle in overflow).
   - **Bottom player strip.**
   - **Engine lines row** (collapsible): 2 lines in SAN.
   - **Coach card** (F10). For the start position it shows the opening name instead.
   - **Move list**: horizontally scrolling chips `12. Nf3` with badges; the current move is centred automatically.
   - **Bottom bar**: ⏮ ◀ ▶ ⏭, Key moments, Report.
   - While analysis runs, a linear progress bar with "Analysing… 34/82" and a Cancel button sits under the app bar. Navigation stays possible the whole time.
4. **Report** (bottom sheet or expandable card): both players, accuracy rings, count table (labels × White/Black), opening, **eval graph**, **game summary** block (or a "Summarize game" button when auto is off or no key is set; hidden entirely when the summary toggle is off).
5. **Explain sheet**: header (badge, "23… Nxe5", "Black's 23rd move" or "Your 23rd move"), streaming text, small footer "AI explanation from Stockfish lines · may contain mistakes · {model}", actions Copy / Regenerate / overflow "View prompt".
6. **Settings**: Engine · Explanations (LLM connection, language, tone, audience, game summary on/off, auto-summary on/off) · Accounts (lichess username, chess.com username) · Appearance · About.
7. **First run**: no onboarding wall. Everything except Explain/Summary works offline. Tapping Explain with no key opens a short "Set up explanations" sheet linking to LLM settings and naming the providers.

### Shared components and state machines

**AnalysisJob**: `idle → starting → running(ply k/N) → completed`. Also: `running → cancelled` (resumable), `running → paused` (app backgrounded; resumes from the last persisted ply on foreground), `any → failed(EngineUnavailable | EngineCrashed)` (Retry recreates the engine).

**ExplainRequest**: `idle → connecting → streaming → done`; `→ cancelled` (sheet closed); `→ failed(kind)`. Error kinds, each with its own copy:
- `noKey`: "Add an API key in Settings → Explanations."
- `unauthorized` (401): "Your API key was rejected."
- `modelNotFound` (404 or model error): "Model '{model}' isn't available on this endpoint."
- `rateLimited` (429): "Rate limited. Try again in a moment."
- `quotaExceeded` (429 `insufficient_quota`): "Your account is out of credits."
- `unsupportedParam` (400 `unsupported_parameter`): "This model rejected '{param}'. Change 'Token limit parameter' in Settings."
- `cleartextBlocked`: "Plain http:// is only allowed for local network addresses."
- `offline`: "No connection."
- `timeout`: "The model took too long to respond."
- `server` (5xx): "The provider had an error ({code})."
- `badStream`: "The response couldn't be read."

**OnlineFetch**: `idle → loading(n received) → loaded | empty | failed(userNotFound | rateLimited | offline | server)`. For a lichess 429: "Lichess asked us to slow down. Retrying in 60 s." (with automatic retry).

**PgnParseResult**: `ok(games)` | `partial(games, skipped: [(index, reason)])` | `failed(reason, gameIndex?, ply?, san?)`. Copy examples: "Game 2, move 14 (Nxe5): illegal move." · "Crazyhouse games aren't supported." · "This file is larger than 2 MB."

**Localization:** every user-facing string lives in `lib/l10n/app_en.arb` (Flutter gen-l10n). No hard-coded UI strings. Prompt templates stay in code (versioned) and get the explanation language as a parameter. Leave room for `app_ms.arb` (N8).

**Accessibility:** badges have semantic labels ("Blunder"). Squares and moves are announced in SAN. Touch targets are ≥ 48 dp. The eval gauge has a text alternative.

---

## 5. Architecture

### 5.1 Layout

```
glyph/
├─ packages/glyph_core/            # PURE DART — no Flutter imports. `dart test` runs on host.
│  └─ lib/src/
│     ├─ pgn/          # import, normalize (BOM/CRLF), multi-game split, header model, %clk parse, export w/ NAG+%eval
│     ├─ game/         # Game, Ply, PositionCursor (mainline now, variations later), side detection
│     ├─ engine/       # UciParser, Score (WhitePov), EngineDriver (interface), AnalysisPipeline, AnalysisJob
│     ├─ classify/     # WinPercent, ExpectedPoints, See (static exchange), Classifier, ClassifierConfig, Accuracy, KeyMoments
│     ├─ openings/     # OpeningBook (EPD → eco/name), asset decoder
│     ├─ llm/          # PromptBuilder (move + summary), LlmClient, SseDecoder, ErrorMapper, BaseUrlPolicy, CacheKey
│     ├─ online/       # LichessClient (NDJSON stream), ChessComClient (archives)
│     └─ util/         # Result types, caps/limits, clock abstraction
├─ app/                            # Flutter application (my.umarh.glyph)
│  ├─ lib/
│  │  ├─ engine/       # MultistockfishDriver implements EngineDriver; EngineService (single owner, job queue, lifecycle)
│  │  ├─ data/         # Db (sqlite3, raw SQL, migrations), GameRepository, AnalysisRepository, LlmCacheRepository,
│  │  │                # SettingsRepository, SecretStore (flutter_secure_storage)
│  │  ├─ features/     # library/, import/, board/, report/, explain/, settings/, about/  (widgets + Riverpod notifiers)
│  │  ├─ theme/        # M3 theme, dynamic colour, BadgeColors ThemeExtension, board themes
│  │  ├─ platform/     # share/open-with intake, file picker
│  │  └─ l10n/
│  ├─ assets/          # openings asset, badge SVGs, free piece sets (if not from chessground)
│  ├─ integration_test/  # device-only tests (tagged)
│  └─ android/
├─ tool/                           # dev-machine scripts (Dart): build_openings.dart, record_transcripts.dart,
│                                  # fetch_lichess_vectors.dart, capture_sse.sh, check_permissions.sh
└─ docs/  DECISIONS.md PROGRESS.md VECTORS.md HARDWARE_TEST.md PRIVACY.md design/
```

`dartchess` and `http` are pure Dart, so the whole chess/engine/classification/LLM/online logic is host-testable.

### 5.2 Interfaces (decouple I/O from logic)

- `EngineDriver { Stream<String> get lines; void send(String cmd); Future<void> dispose(); }`. Implementations: `MultistockfishDriver` (device), `ProcessEngineDriver` (host, runs a desktop `stockfish` binary from `STOCKFISH_PATH`; used only by `tool/record_transcripts.dart` and env-gated tests), `FakeEngineDriver` (replays recorded transcripts keyed by the exact `position …` + `go …` commands; fails loudly on unknown keys).
- `LlmClient` takes an injected `http.Client` (`MockClient` in tests).
- `SecretStore`, `SettingsStore`, `GameRepository`, `Clock` are interfaces with in-memory fakes.

### 5.3 Layering, concurrency, versions

- **Layering:** Widgets → Riverpod notifiers (UI state only) → use cases in `glyph_core` (`ImportPgn`, `AnalyzeGame`, `ClassifyGame`, `ComputeAccuracy`, `BuildMovePrompt`, `ExplainMove`, `SummarizeGame`, `FetchLichessGames`, `FetchChessComGames`, `ExportAnnotatedPgn`) → repositories.
- **Engine concurrency:** exactly one `EngineService` (app-scoped provider) owns the single engine. Jobs run serially. Each completed ply is written in its own transaction **before** the next `go`. Cancellation: `stop` → await `bestmove` (2 s timeout → dispose + recreate). `AppLifecycleState.paused` → cancel the current search, dispose the engine, mark the job `paused`. On resume, recreate and continue from `completed_plies`.
- **Isolates:** PGN parsing of inputs > 100 KB and the openings asset decode run in `Isolate.run`.
- **LLM:** one in-flight request per sheet. Closing the sheet cancels the stream subscription and closes the client. Summary generation uses its own request and never blocks the UI.
- **Versions:** Flutter latest stable ≥ 3.47 (pin it in `.fvmrc` and in CI), Dart ≥ 3.13. `minSdk 26`, `compileSdk`/`targetSdk` = newest API supported by the pinned Flutter (record it). NDK as required by `multistockfish`. ABIs: `arm64-v8a`, `armeabi-v7a`, `x86_64` (emulator). Release = split APKs per ABI. Gradle Kotlin DSL.

### 5.4 Data model (SQLite, raw SQL, `PRAGMA foreign_keys=ON`, `user_version` migrations)

```sql
CREATE TABLE games (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL CHECK (source IN ('paste','file','share','lichess','chesscom')),
  source_id TEXT,                         -- lichess game id / chess.com url; NULL for local
  pgn TEXT NOT NULL,                      -- original PGN as imported (normalized newlines)
  white TEXT, black TEXT, white_elo INTEGER, black_elo INTEGER,
  result TEXT, date TEXT, time_control TEXT, event TEXT,
  variant TEXT NOT NULL DEFAULT 'standard' CHECK (variant IN ('standard','chess960')),
  start_fen TEXT,                         -- NULL = standard start
  eco TEXT, opening_name TEXT,
  user_side TEXT CHECK (user_side IN ('white','black')),
  ply_count INTEGER NOT NULL,
  imported_at INTEGER NOT NULL,
  UNIQUE (source, source_id)
);
CREATE TABLE analyses (
  game_id INTEGER PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
  engine TEXT NOT NULL,                   -- e.g. "Stockfish 19 light"
  depth INTEGER NOT NULL, multipv INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('running','paused','cancelled','completed','failed')),
  completed_plies INTEGER NOT NULL DEFAULT 0,
  white_accuracy REAL, black_accuracy REAL,
  updated_at INTEGER NOT NULL
);
CREATE TABLE position_lines (             -- one row per (position, multipv line); scores WHITE POV
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  ply INTEGER NOT NULL,                   -- 0 = start position
  rank INTEGER NOT NULL CHECK (rank IN (1,2)),
  score_cp INTEGER, score_mate INTEGER,   -- exactly one non-NULL, or both NULL for terminal
  depth INTEGER NOT NULL,
  pv_uci TEXT NOT NULL,                   -- space-separated
  PRIMARY KEY (game_id, ply, rank)
);
CREATE TABLE move_labels (
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  ply INTEGER NOT NULL,                   -- move that LEADS to position `ply`
  label TEXT NOT NULL,
  ep_loss REAL, win_before REAL, win_after REAL,   -- mover POV
  best_uci TEXT,
  PRIMARY KEY (game_id, ply)
);
CREATE TABLE llm_cache (
  key TEXT PRIMARY KEY,                   -- see trap 17
  kind TEXT NOT NULL CHECK (kind IN ('move','summary')),
  content TEXT NOT NULL, model TEXT NOT NULL, created_at INTEGER NOT NULL
);
CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL);   -- never secrets
```
Labels are recomputed from `position_lines` whenever `ClassifierConfig` changes (store `classifier_version` in `settings`).

### 5.5 Prompts (versioned templates in `glyph_core/llm`, snapshot-tested)

**Move explanation**: system message (rules) + one user message containing this JSON (all evals in **mover POV**, all moves in **SAN**):
```json
{
  "move": {"san": "Nxe5", "moveNumber": 12, "side": "white", "isUserMove": true},
  "classification": "blunder",
  "fenBefore": "r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4",
  "winChanceBefore": 54.1, "winChanceAfter": 18.7,
  "evalBefore": "+0.3", "evalAfter": "-2.1",
  "bestMove": {"san": "d3", "line": ["d3", "Bc5", "O-O", "d6"], "eval": "+0.3"},
  "secondBest": {"san": "Nc3", "line": ["Nc3", "Nxe4", "Nxe4", "d5"], "eval": "+0.1"},
  "refutation": ["Nxe5", "Nxe5", "d4", "Nxc4"],
  "material": {"before": 0, "afterRefutation": -3},
  "hangingAfterMove": ["bishop on c4"],
  "flags": {"sacrifice": false, "onlyMove": false, "missedMateIn": null, "opponentErrorPunished": false},
  "opening": "Italian Game: Two Knights Defense",
  "phase": "opening",
  "audience": "club", "tone": "casual", "language": "English"
}
```
System rules (must appear verbatim in intent): explain *why* the move earned its label in ≤ 120 words; use **only** the moves in `bestMove.line`, `secondBest.line` and `refutation`; never invent variations or claim pieces/squares not consistent with `fenBefore`; name a tactical motif only if a provided line demonstrates it; speak to the user as "you" when `isUserMove`, otherwise say "White"/"Black"; end with one short sentence starting "Better was…" when the label is Inaccuracy or worse; plain text, no headings; answer in `language`.

`hangingAfterMove` and `material` are computed deterministically (SEE + material count along the refutation), never by the LLM.

**Game summary**: payload = result + termination, opening, user side (or null), accuracies, label counts per side, ≤ 8 key moments (moveNumber, side, san, label, winBefore→winAfter, best san), and the Win% trajectory sampled every 5 plies. Tone **Casual**: 2–4 friendly sentences in second person, e.g. "You saw your chance for the win with a nice tactic and you took it!" Tone **Coach**: 4–6 sentences ending with 1–2 concrete takeaways. Same grounding rule: mention only the provided moves.

---

## 6. Security requirements

- [ ] **Permissions:** the release APK requests **exactly** `android.permission.INTERNET`. Any permission merged in by plugins (e.g. `ACCESS_NETWORK_STATE`, storage, `READ_MEDIA_*`) is removed with `tools:node="remove"` unless `docs/DECISIONS.md` justifies it. Verified by `tool/check_permissions.sh` (runs `apkanalyzer manifest permissions` or `aapt2 dump permissions` on the release APK and diffs against an allowlist), run in CI.
- [ ] **API key storage:** only in `flutter_secure_storage` (default `AndroidOptions()`). It is **never** written to SQLite, settings, logs, the clipboard, exported PGN, crash output or "View prompt". The UI shows only `••••abcd`. "Remove key" deletes it.
- [ ] **Key lifetime:** read from the secure store per request and never held in Riverpod state. (Dart strings can't be zeroed. Minimizing lifetime is the mitigation, documented in the threat model.)
- [ ] **Backups:** `android:allowBackup="false"`, plus `dataExtractionRules` excluding everything (avoids the secure-storage key-unwrap failure after restore and keeps the key off cloud backups).
- [ ] **Logging:** one logging wrapper. Release builds log nothing below warning. Headers and request bodies are never logged. A unit test greps `lib/` and `packages/` for `print(` and for logging of `Authorization`.
- [ ] **Network policy:** lichess/chess.com URLs are hard-coded `https://`. The user's LLM base URL may be `https://` anywhere, or `http://` **only** if the host is `localhost`, `127.0.0.0/8`, `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16`, `100.64.0.0/10` (Tailscale/CGNAT) or ends in `.local`/`.lan`. Enforced in `BaseUrlPolicy` (unit-tested) before any request. The network security config permits cleartext so the policy above is the gate. Record that decision.
- [ ] **No personal data to the LLM** (trap 18). `docs/PRIVACY.md` lists exactly which fields go to which host.
- [ ] **No telemetry:** no analytics, crash reporting, Firebase or Play Services. CI fails if `pubspec.lock` contains `firebase_` or `google_mobile_ads`.
- [ ] **DoS caps on untrusted input** (constants in `glyph_core/util/limits.dart`, each with a test): PGN input ≤ 2 MB; ≤ 500 games listed per file; ≤ 1000 plies per game; any single comment ≤ 4 KB (truncated); online fetch ≤ 50 games; NDJSON line ≤ 1 MB; LLM stream ≤ 32 KB (then stop and mark truncated); timeouts: connect 15 s, first byte 60 s (reasoning models), total 180 s.
- [ ] **Output safety:** LLM text is rendered as plain text (or sanitized markdown with links disabled). No WebView.
- [ ] **Integrity:** the openings asset has a SHA-256 recorded at build time and checked in a test. (N3: downloaded nets must match a pinned SHA-256 before use.)
- [ ] **Screen capture:** no `FLAG_SECURE` (nothing sensitive is displayed; the key is masked). Stated explicitly.
- [ ] **Release hardening:** R8/minify + `shrinkResources` on. Signing from `key.properties`/env vars, never committed (`.gitignore` covers them). `--split-debug-info` symbols kept out of the APK.
- [ ] **Licence compliance:** `LICENSE` = GPL-3.0-or-later. About screen links the source repo and lists Stockfish (GPL-3.0) and all assets with their licences.

---

## 7. Testing strategy

**This section decides whether the app actually works.** Classification and accuracy are only trustworthy if they're pinned by golden vectors.

### 7.1 Golden test vectors (most important)

All vectors live in `packages/glyph_core/test/vectors/` and are generated on the developer's machine (Arch Linux; `stockfish` 19 from the distro or the official release). `docs/VECTORS.md` gives the exact commands, tool versions and engine settings used.

1. **`winpercent.json`**: cp → Win% for cp ∈ {−2000…2000 step 50} plus mate values, computed from the formula and constants extracted from lila (M0). Tolerance 1e-9.
2. **P0-level interop: `lichess_accuracy/*.ndjson`.** 30+ real, server-analysed lichess games exported with evals and per-player accuracy via `tool/fetch_lichess_vectors.dart` (lengths 20–150 plies, both colours, wins/draws/losses, mate endings, one Chess960). Feed **lichess's own evals** into Glyph's `Accuracy` → must equal lichess's reported accuracy per player within **±1** (rounding).
3. **`uci_transcripts/*.txt`**: raw engine output recorded by `tool/record_transcripts.dart` using `ProcessEngineDriver` (Threads=1, Hash=16, MultiPV=2, `go depth 16`, full move history). Replayed by `FakeEngineDriver`.
4. **`classify/*.json`**: `{name, startFen, moves, ply, expectedLabel, note}` evaluated through recorded transcripts. Required coverage (≥ 3 cases per label plus these named cases):
   - **P0:** a mirrored blunder pair (White version and Black version) → same label, mirrored evals.
   - Castling recommended by the engine → **Best** (trap 2).
   - Played == line 1 → EP loss exactly 0 (trap 3).
   - Queen trade, normal recapture, pawn trade → **not** Brilliant (trap 6).
   - A known sacrificial combination → Brilliant. A sacrifice in an already-winning (> 97%) position → not Brilliant.
   - Only-move defence → Great. Obvious recapture that is the only move → **not** Great.
   - Opponent blunders a piece, user doesn't take → Miss. Missed mate-in-2 → Miss. Missed punish that drops below 50% → Blunder.
   - Mate-in-1 delivered → Best. Final checkmating move handled with no engine call.
   - Stalemating from a winning position → Blunder.
   - Threefold-repetition draw from a winning position → Blunder (trap 9: requires history).
   - Promotion (`e7e8q`), underpromotion, en passant.
   - Forced (single legal move).
   - Book: contiguous book prefix; transposition into book → Book; FEN-start game → no Book.
5. **`pgn/`**: chess.com download with `%clk`; chess.com app share text; lichess API export with `%eval`/`%clk`/opening; lichess app share; 50-game file; Chess960 with `[FEN]`; CRLF + BOM; variations + NAGs + nested-brace comments; illegal move (expect game/ply/SAN error); crazyhouse (expect rejection); 0-move game; 2 MB + 1 byte (expect rejection). Round-trip: import → export → import gives an identical mainline and headers.
6. **`sse/`**: real streams captured with `curl -N` (commands in `docs/VECTORS.md`; keys redacted from saved files) from OpenAI, OpenRouter and Ollama, plus error bodies (401, 404 model, 429, 400 `unsupported_parameter`). Tests feed each stream split at **every** byte boundary (or 200 random splits for long files) and assert identical decoded text and error mapping.

### 7.2 Other tests

- `UciParser` units: bounds skipped, `currmove`/`info string` ignored, interleaved multipv, `mate 0`, `bestmove (none)`.
- `AnalysisPipeline`: cancel mid-search (`stop` → `bestmove`), resume from `completed_plies`, engine crash → `failed` → retry recreates, terminal positions never reach the engine, `position … moves …` always includes history (assert on the sent commands).
- `See` units (classic SEE test positions).
- `PromptBuilder` snapshot tests: SAN only (regex rejects UCI-looking tokens), no names/ratings, mover-POV numbers, `promptVersion` present.
- `CacheKey`: changes when any input changes.
- `BaseUrlPolicy`: allowed/blocked matrix; URL normalization (trailing slash, missing `/v1` warning).
- `ErrorMapper`: each HTTP/error body → the right `ExplainRequest` failure kind.
- `LichessClient`: NDJSON across chunk splits, 429 → 60 s backoff (fake clock), unknown user. `ChessComClient`: newest-first archive walk, stops at 30, 404/410, `If-None-Match` sent on repeat.
- Repositories against in-memory SQLite: migrations, cascade delete, dedupe on `(source, source_id)`.
- Widget tests: library empty/list states; board shows badges and navigates; coach card; Explain sheet through every state with a fake client; settings key masking; summary hidden when the toggle is off.
- **Device-only** `integration_test/` tagged `@Tags(['device'])` and skipped in CI: real `multistockfish` analyses a 30-ply game at Fast → every ply labelled, no exceptions, eval sign sanity on a known winning position, cancel/resume works.
- `tool/check_permissions.sh` in CI on the release APK.

### 7.3 Manual device checklist (`docs/HARDWARE_TEST.md`)

Primary device: the developer's Honor LLY-NX1. Also an emulator at API 26 and one at the latest API. Checklist:
- Normal-preset analysis of an ~80-ply game; record the time (**target ≤ 3 min**, Fast ≤ 1 min), device temperature and battery drop.
- Background mid-analysis for 2 min (Honor battery management is aggressive) → returns, resumes from the last ply.
- Force-stop mid-analysis → reopen → Resume.
- Rotate during analysis and while streaming an explanation.
- Share a game from the lichess app and from the chess.com app (text and file) → imports.
- Open a `.pgn` from the Files app via "Open with".
- Explain with OpenAI, OpenRouter, and Ollama on the LAN over `http://` (allowed) and over a public `http://` host (blocked with the right copy).
- Airplane mode: analysis works, Explain shows `offline`.
- Exported PGN imports into a lichess study with glyphs visible.
- TalkBack pass on the board screen.

---

## 8. Build plan / milestones for Claude Code

**Rule:** work milestone by milestone. At the end of each milestone:
`(cd packages/glyph_core && dart test) && (cd app && flutter analyze && flutter test && flutter build apk --release --split-per-abi)` passes, all tests are green, commit with a clear message (`M3: engine pipeline with resume/cancel`), and update `docs/PROGRESS.md` (done, deviations, next).

**M0 — Research & decisions.** *Goal: remove every unknown before writing app code.*
- Clone and read: `lichess-org/lila` (WinPercent, AccuracyPercent, winningChances.ts), `lichess-org/mobile` (analysis screen, engine evaluation service, annotations, eval gauge), `lichess-org/flutter-chessground`, `lichess-org/dartchess`, `lichess-org/dart-multistockfish`, `lichess-org/chess-openings`, `lichess-org/api` (games export spec).
- Fill **every** item from "Things the spec leaves out" (2.1) into `docs/DECISIONS.md` with file/line references.
- Verify each library's "verify early" items (2.3); choose fallbacks where needed.
- Confirm the Flutter stable version, Material package split, compile/target SDK and NDK, and pin them.
- Write `docs/VECTORS.md` (commands for 7.1) and the skeleton of `docs/HARDWARE_TEST.md`.
- **Stop and report** if: `multistockfish` can't build with the pinned Flutter/NDK and the fallback can't either; `chessground` lacks annotations *and* an overlay is impossible; or any required dependency is GPL-incompatible.

**M1 — Skeleton.** *Goal: an installable, empty, correctly configured app.*
Monorepo layout (5.1); `flutter create --org my.umarh --project-name glyph app`; `glyph_core` package; Riverpod; M3 theme + dynamic colour + `BadgeColors`; routes with placeholder screens; gen-l10n; `LICENSE` (GPL-3.0-or-later); `INTERNET` in the main manifest; `allowBackup=false` + extraction rules; `tool/check_permissions.sh`; GitHub Actions CI (core tests, analyze, widget tests, release build, permission check, banned-deps check); `.fvmrc`.

**M2 — PGN, games, library.** *Goal: games get in and are stored.*
`pgn/` import + normalization + caps + export (NAG/%eval); `game/` model + `PositionCursor` + side detection; `tool/build_openings.dart` → openings asset + `OpeningBook`; SQLite schema + migrations + repositories; Library screen; Paste and File import flows (F1, F2-file, F3). PGN golden vectors green.

**M3 — Engine & analysis pipeline.** *Goal: every position is analysed reliably on device.*
`UciParser`, `Score` (White POV), `EngineDriver` + `FakeEngineDriver` + `ProcessEngineDriver`; `tool/record_transcripts.dart` and recorded transcripts; `MultistockfishDriver`; `EngineService` (single owner, queue, lifecycle, crash recovery); `AnalysisPipeline` with per-ply persistence, cancel, pause/resume, progress stream (F4).

**M4 — Classification & accuracy.** *Goal: labels and accuracy match the golden vectors.*
`WinPercent`, `ExpectedPoints`, `See`, `Classifier` + `ClassifierConfig`, `Accuracy`, `KeyMoments`, opening naming. `winpercent.json`, **lichess accuracy (P0)** and the full `classify/` set green (F5, F6 data).

**M5 — Analysis board UI.** *Goal: the review experience, without LLM.*
Board with square badges and best-move arrow; move list; navigation and swipe; flip; player strips with clocks; eval gauge; engine lines; eval graph with markers; Key moments sheet; coach card with deterministic one-liner; report card; progressive badge fill during analysis; auto-orientation from the user's side (F7–F10, F6 UI, F15 detection).

**M6 — LLM explanations & summary.** *Goal: grounded, streamed, cached explanations.*
LLM settings + presets + secure storage + Test connection (F13); explanation settings (F14); `BaseUrlPolicy`; `LlmClient` + `SseDecoder` + `ErrorMapper` (SSE vectors green); `PromptBuilder` (move + summary) with snapshot tests; Explain sheet with all states, View prompt, Copy, Regenerate (F11); cache (trap 17); game summary toggle, auto-generation after analysis and Regenerate (F12).

**M7 — Online import, sharing, export.** *Goal: games come from everywhere and go back out.*
`LichessClient` (NDJSON, 429 backoff) and `ChessComClient` (archives, ETag) + UIs (F16, F17); share/open-with intake for text and files (F2); account usernames settings (F15); annotated PGN export via the share sheet (F18).

**M8 — Hardening.** *Goal: robust, private, releasable.*
All error copy wired; DoS caps verified; no-log/banned-deps tests; accessibility pass; performance tuning toward the 7.3 targets (threads/hash defaults recorded); R8 release config and signing via env; asset licence audit (trap 15); About & licences screen (F20); general settings (F19); `docs/PRIVACY.md`; device integration test passes locally; `docs/HARDWARE_TEST.md` complete.

**M9 — Docs & release.** *Goal: a stranger can build and use it.*
`README.md`: what it is (screenshots), features, how classification works (and that it approximates, not copies, chess.com), LLM provider setup (OpenAI, OpenRouter, Ollama/LM Studio on LAN), privacy summary, build steps (Flutter version, NDK, `flutter build apk --split-per-abi`), interop table (lichess/chess.com import, lichess study export), threat model summary, licence and credits. `CHANGELOG.md`; tag `v0.1.0`; GitHub release with split APKs.

---

## 9. Acceptance criteria

- [ ] `dart test` (core), `flutter analyze`, `flutter test` and `flutter build apk --release --split-per-abi` all pass in CI.
- [ ] **P0:** mirrored White/Black blunder vectors produce identical labels.
- [ ] **P0:** Glyph's accuracy matches lichess's on all `lichess_accuracy` vectors within ±1.
- [ ] Every `classify/` vector passes, including castling = Best, trades ≠ Brilliant, recapture ≠ Great, repetition draw detected.
- [ ] A PGN from each of: lichess web export, lichess API, lichess app share, chess.com download, chess.com app share imports with the full mainline (manual + golden tests).
- [ ] Exported annotated PGN re-imports into Glyph identically and shows glyphs in a lichess study (manual).
- [ ] An ~80-ply game analyses on the primary device at Normal in ≤ 3 min. Cancel, background and force-stop all resume correctly (manual, 7.3).
- [ ] Explain streams successfully against OpenAI, OpenRouter and LAN Ollama. Each error kind in section 4 is reachable in tests and shows its copy.
- [ ] Changing model, language or tone produces a fresh explanation (cache key test).
- [ ] Game summary: on by default, auto-generates after analysis when a key exists, disappears entirely when toggled off.
- [ ] The app is fully usable offline except Explain/Summary/online import.
- [ ] Release APK permissions are exactly `{INTERNET}` (`tool/check_permissions.sh`).
- [ ] The API key never appears in SQLite, settings, logs or "View prompt" (test + manual `adb logcat` check during an Explain).
- [ ] No player names/usernames are present in any prompt (snapshot tests).
- [ ] `http://` LLM URLs work for private-range hosts and are blocked with clear copy for public hosts.
- [ ] Every oversized-input cap in section 6 has a passing test.
- [ ] About screen shows GPL notice, source link, Stockfish credit and asset licences. `pubspec.lock` has no Firebase/ads/analytics.
- [ ] `docs/DECISIONS.md`, `docs/PROGRESS.md`, `docs/VECTORS.md`, `docs/HARDWARE_TEST.md`, `docs/PRIVACY.md` and `README.md` exist and are complete.

---

## 10. Open questions (defaults chosen; override freely)

| Question | Default |
|---|---|
| App name / application ID | "Glyph" / `my.umarh.glyph` |
| Licence | GPL-3.0-or-later (required by Stockfish, chessground, dartchess) |
| Distribution | GitHub Releases (split APKs); F-Droid-friendly but not submitted in v1 |
| Platform scope | Android only, minSdk 26; core kept platform-agnostic for a future iOS build |
| Engine | `multistockfish` light flavor (Stockfish 19, ~1.1 MB embedded net); full net is N3 |
| Depth presets | Fast 12 / Normal 16 (default) / Deep 20, MultiPV 2 |
| Threads / hash | `min(4, cores−2)` (min 1) / 64 MB |
| Classification thresholds | Chess.com's published EP table on the lichess Win% curve; special-rule constants in `ClassifierConfig` as in 2.1 |
| Accuracy | Lichess `AccuracyPercent` algorithm, exactly |
| State management / DB | Riverpod / `sqlite3` with raw SQL |
| LLM API shape | OpenAI-compatible Chat Completions with SSE; no Responses API |
| Default provider preset | OpenAI (`https://api.openai.com/v1`), model field empty until the user fills it |
| Token-limit param | None sent by default; `temperature` never sent |
| Explain availability | Every move; emphasized on Brilliant/Great/Miss/Inaccuracy/Mistake/Blunder |
| Game summary | On by default, Casual tone, auto-generates after analysis when a key is set |
| Explanation language | Matches app language (English); free-text override |
| Cleartext HTTP | Allowed only to localhost/private/Tailscale ranges and `.local`/`.lan` hosts |
| Online fetch size | Last 30 games per username |
| Board view in v1 | View-only (no free exploration; N2) |
| Badge design | Glyph's own icons using standard NAG glyphs, colours per section 4 |
| UI languages | English only in v1; Malay planned (N8) |
| Telemetry | None |
