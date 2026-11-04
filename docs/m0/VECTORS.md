# Golden vector generation (spec 7.1)

## Tool versions (M0 machine)
Arch Linux; Stockfish 19 desktop (`$STOCKFISH_PATH`, net nn-1a298aa575a0.nnue 109 MiB); Dart 3.13.7; curl (HTTP/2). Upstream commits: lila 9e780e9, scalachess b73baa5, chess-openings 3fd6ce9, api bbd21a7. `source ~/development/glyph-env.sh` first. Always send UA `Glyph-M0-research (https://github.com/umarh/glyph)`.

## 1. winpercent.json
`cd packages/glyph_core && dart run tool/gen_winpercent.dart` (M4) writes `test/vectors/winpercent.json`: `{cp: -2000..2000 step 50 -> win}` plus mate entries `{"mate": +-1, +-5, +-30 -> win}` using: clamp cp to +-1000; `win = 50 + 50*(2/(1+exp(-0.00368208*cp))-1)`; every mate = +-1000 cp (scalachess eval.scala L95-110). Reference values: win(0)=50, win(15)=51.380429102931544, win(100)=59.10258971916128, win(+-1000)=97.54474363414323 / 2.4552563658567763. Tolerance 1e-9.

## 2. lichess_accuracy/*.ndjson (P0)
`tool/fetch_lichess_vectors.dart`: one request at a time, `sleep 3 s` between, stop on 429 and wait 60 s.
```
curl -sS -A "$UA" -H 'Accept: application/x-ndjson' \
 "https://lichess.org/api/games/user/$USER?max=$N&analysed=true&evals=true&accuracy=true&pgnInJson=true&clocks=true&opening=true&division=true&perfType=$PERF"
```
Candidate users (all verified to return analysed games): `DrNykterstein` (blitz/rapid/classical + chess960), `penguingim1`, `Fins` (blitz, rapid, chess960). Extra: `nihalsarin2004`, `Zhigalko_Sergei`, `lovlas`. Verified pool: 210 games, Python reference port matches all 420 accuracies (max diff 0.4997).
Selection (target >= 32 games, keep game JSON minus pgn if size matters; redact nothing needed beyond optional usernames):
- plies = `moves.split(' ').length` in 20..150; at least 4 in 20-40, 4 in 120-150.
- both colours of the subject user won/lost/drawn: >= 4 each of white-win, black-win, white-loss(black-win by opp), draws (`status=draw`) >= 4, plus 1 `stalemate` (id WHXaoFJJ in pool).
- >= 6 mate endings (`status=mate`; analysis has plies-1 entries), >= 6 with `mate` evals in `analysis`, >= 2 outoftime.
- >= 2 chess960 (`perfType=chess960`, has `initialFen`, no `opening`), of which >= 1 where a side castles (e.g. PXXPWDlC).
- >= 1 game whose first mover is Black is NOT available via API for variants=standard (needs FEN start); cover Black-start by unit tests from lila's AccuracyPercentTest instead.
Test input: `analysis[]` white-POV `eval`/`mate`, prepend initial eval **15 cp**, startColor from `initialFen` (default white). Mate -> +-1000cp. Expected: `players.{white,black}.analysis.accuracy` (int); require `round(glyph) == expected` (spec tolerance +-1 is looser).
Reference implementation (Python) used for validation is described by the pseudocode in algorithms.md 1.3.
**M4 (done):** `dart run tool/fetch_lichess_vectors.dart` (repo root) writes `packages/glyph_core/test/vectors/lichess_accuracy/standard.ndjson` (34) and `chess960.ndjson` (4); `m0_sample.ndjson` holds the 2 M0 games. Lines are trimmed to `{id, variant, speed, status, winner?, initialFen?, plies, moves, analysis:[{eval}|{mate}], accuracy:{white, black}}` (no user names, ratings, titles). The API returns the latest games, so a re-run picks different games; the committed files are the reference. Test: `test/classify/win_percent_accuracy_test.dart` (exact equality after rounding, 80/80).

## 3. uci_transcripts/*.txt
`tool/record_transcripts.dart` using ProcessEngineDriver; session:
```
uci; setoption name Threads value 1; setoption name Hash value 16; setoption name MultiPV value 2;
setoption name UCI_Chess960 value <false|true>; isready; ucinewgame; isready
per ply i: position fen <startFen> moves <m1..mi> ; go depth 16 ; (record every line up to and including bestmove)
```
Record raw stdout verbatim plus a header comment (`# stockfish 19, nn-1a298aa575a0, threads=1 hash=16 multipv=2 depth=16, fen, moves`). Moves must be in the notation of the mode (std `e1g1`; 960 `e1h1`), else SF prints `CRITICAL ERROR ... Illegal move`. Never send `go` for mate/stalemate positions (SF gives `info depth 0 score cp 0` + `bestmove (none)`). Notable fixtures:
- Castling best: `r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 5` depth 14 -> `bestmove e1g1` (std) / `e1h1` (960).
- Mate: `6k1/5ppp/8/8/8/8/5PPP/3R2K1 w - - 0 1` -> `score mate 1 ... pv d1d8`, multipv 2 `cp 668`.
- Terminal: `7k/5Q2/6K1/8/8/8/8/8 b` (mate), `7k/5Q2/8/6K1/8/8/8/8 b` (stalemate).
Determinism: use Threads=1; node counts are stable on the same binary/hash.
**M4:** 19 more games were appended to `games.json` (classification vectors, P0 pair `p0_blunder_white`/`p0_blunder_black`, two lichess games incl. Chess960) and recorded in the cloud container with **Stockfish 16** (`STOCKFISH_PATH=/usr/games/stockfish dart run tool/record_transcripts.dart`), since no SF19 binary was available there. Re-record them with SF19 (`dart run tool/record_transcripts.dart <names> `) on the dev machine and re-check `test/vectors/classify/*.json`.

## 3b. classify/*.json (M4)
`packages/glyph_core/test/vectors/classify/<label>.json`: arrays of `{name, transcript, startFen, moves, ply, expectedLabel, note}` (+ optional `book`, `variant`, `epLoss`, `sacrifice`). `moves` is SAN up to and including `ply`, a prefix of the transcript game. To add a case: add the game to `games.json`, record it, run the classifier on it (e.g. a temporary test printing `reviewGame(...).moves`), and add the case with a note explaining the numbers.

## 4. SSE captures (sse/)

**Status (M6): the committed vectors are SYNTHETIC, not captures.** No API keys were available in M0-M6, so `packages/glyph_core/test/vectors/sse/` holds hand-built files that reproduce each provider's *documented* streaming format: OpenAI chat completion chunks (role chunk, `finish_reason`, `stream_options.include_usage` chunk with empty `choices`, `length`, an `{"error": ...}` event mid-stream), OpenRouter (`: OPENROUTER PROCESSING` comment lines, `provider` / `native_finish_reason`, usage chunk, the mid-stream error chunk with `finish_reason: "error"`), Ollama / LM Studio `/v1` (plain chunks, a thinking model's `reasoning` deltas), a CRLF / multi-line `data:` / lone-CR / `id` `event` `retry` stress file, and the HTTP error bodies of OpenAI (401, 404 model, 429 rate, 429 quota, 400 `unsupported_parameter`, 400 `unsupported_value`, 500, 503 HTML), OpenRouter (401, 402, 400 invalid model, 429) and Ollama (404 model, 404 wrong path). Every file carries a marker (`: SYNTHETIC vector ...` in streams, `x-glyph-synthetic: true` in the `.http` files), `manifest.json` has a `"synthetic"` flag per vector (the top-level flag means "any synthetic"), and a test fails if a flagged vector lacks the marker (and if an unflagged one has it or is not redacted). `packages/glyph_core/tool/gen_sse_fixtures.dart` regenerates them (`dart run tool/gen_sse_fixtures.dart`).

`test/llm/sse_vectors_test.dart` feeds every stream whole, split at **every** byte boundary, 200 random multi-chunk splits, byte by byte, and through `LlmClient` in 7-byte chunks; it checks the decoded text, the finish reason and the error kind from `manifest.json`, and maps every `.http` file with `ErrorMapper`. Real captures replace the synthetic files one by one: save the capture under the same file name and keep the manifest entry (text / finish reason / error kind) in step with what the real answer says.

**Capture commands (left for the user to run).** Use a throwaway key from the environment; redact with sed before saving. Never commit raw files.
```
# OpenAI
curl -N -sS https://api.openai.com/v1/chat/completions -H "Authorization: Bearer $OPENAI_API_KEY" -H 'Content-Type: application/json' \
 -d '{"model":"gpt-4o-mini","stream":true,"messages":[{"role":"user","content":"Say hi in 5 words."}]}' > sse/openai_ok.raw
# OpenRouter
curl -N -sS https://openrouter.ai/api/v1/chat/completions -H "Authorization: Bearer $OPENROUTER_API_KEY" -H 'Content-Type: application/json' \
 -d '{"model":"openai/gpt-4o-mini","stream":true,"messages":[...]}' > sse/openrouter_ok.raw   # includes ": OPENROUTER PROCESSING" comment lines
# Ollama (no key)
curl -N -sS http://localhost:11434/v1/chat/completions -H 'Content-Type: application/json' -d '{"model":"llama3.2","stream":true,"messages":[...]}' > sse/ollama_ok.raw
```
With `stream_options` add `"stream_options":{"include_usage":true}` for the usage chunk. Error bodies: 401 (bad key), 404 (unknown model), 429, 400 `unsupported_parameter` (send `max_tokens` to an o-series model) -> `curl -sS -i ... > sse/<name>.http` (keep status line + headers + body; the test reads the status from the first line and the body after the blank line). Redaction: `sed -E -i 's/(sk-[A-Za-z0-9_-]+|sk-or-[A-Za-z0-9_-]+)/REDACTED/g; s/(org|proj)-[A-Za-z0-9]+/\1-REDACTED/g; s/"(system_fingerprint|id)":"[^"]*"/"\1":"X"/g'` and `grep -ciE 'sk-|bearer'` must print 0. Ollama needs a local model; the others need keys.

## 5. Other fixtures from M0
- `docs/m0/lichess_sample.ndjson`, `docs/m0/chesscom_sample.json` (real, trimmed).
- Openings: `tool/build_openings.dart` replays `~/development/upstream/chess-openings/{a..e}.tsv` pgn column with dartchess 0.14, outputs `epd\teco\tname` (EPD = first 4 fields of `Position.fen`, legal-ep only). Expect 3865 rows, 0 duplicate EPDs, 15 with ep square. Probe script used: scratchpad `openings_probe/bin/gen.dart`.

## 6. PGN fixtures (M2)
`packages/glyph_core/test/vectors/pgn/`: real data from `docs/m0/lichess_sample.ndjson` (`lichess_api_export.pgn`, `chess960_fen.pgn`, `crlf_bom.pgn`) and `docs/m0/chesscom_sample.json` (`chesscom_download_clk.pgn`, `chesscom_app_share.pgn` with a share-text preamble, `illegal_move_*.pgn` = the 37-move game with 14. Bxc4 replaced by 14. Nxe5); synthetic: `fifty_games.pgn`, `no_blank_lines.pgn`, `lichess_app_share.pgn`, `crazyhouse*.pgn`, `zero_moves.pgn`, regenerated by `cd packages/glyph_core && dart run tool/gen_pgn_fixtures.dart` (fixed seed); `variations_nags_nested.pgn` is hand-written. Oversize (2 MB + 1 byte), 501 games, 1001 plies and 4 KB comments are generated inside `test/pgn_vectors_test.dart`.

