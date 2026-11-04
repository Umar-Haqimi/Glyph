# DECISIONS

Consolidated from M0 research. Upstream source wins over the spec; discrepancies are recorded here. Details: docs/m0/algorithms.md, docs/m0/libraries.md.

## Part A: algorithms
## M0 algorithms research (upstream wins over spec)

Upstream snapshots (shallow clones in ~/development/upstream): lila 9e780e9 (2026-11-04), scalachess b73baa5, scalalib 31fc151, api bbd21a7, chess-openings 3fd6ce9. Note: `WinPercent` is NOT in lila; it lives in **scalachess**.

### 1. Win% and accuracy

#### 1.1 WinPercent (scalachess `core/src/main/scala/eval.scala`)
- L57 `Cp.CEILING = 1000`; L66-69 `ceiled` clamps cp to [-1000, 1000].
- L107-110 `winningChances(cp) = 2/(1+exp(-0.00368208*cp)) - 1`, clamped [-1,1]. L101-102 `fromCentiPawns(cp) = 50 + 50*winningChances(cp.ceiled)`.
- L95-98 `fromScore`: cp -> fromCentiPawns; **mate N>0 -> fromCentiPawns(+1000); mate N<=0 (incl. Mate(0)=mated) -> fromCentiPawns(-1000); MateGiven -> +1000.** Mate distance is ignored. win(1000)=97.54474363414323, win(-1000)=2.4552563658567763.
- Client `ui/lib/src/ceval/winningChances.ts` (path moved from ui/ceval): L11 MULTIPLIER -0.00368208, L16 clamp +-1000, L18-22 `mate -> cp=(21-min(10,|mate|))*100`, signed. Gives 99.94% for M1, 98.29% for M10+. **Used only for the live client gauge, NOT by the server accuracy.**
- Discrepancy vs spec: spec said "mate N mapped to large cp shrinking with N". True only for the TS client. For accuracy parity (and I recommend Glyph's eval bar too, for consistency with lichess accuracy) use the server rule: all mates = +-1000 cp. Decision for Glyph: use server rule everywhere (single function), keep the TS formula only if a "mate-distance" gauge is wanted.

#### 1.2 Per-move accuracy (lila `modules/analyse/src/main/AccuracyPercent.scala` L47-54)
```
accMove(before, after):            // Win% from the MOVER's POV, 0..100
  if after >= before: return 100
  d = before - after
  raw = 103.1668100711649 * exp(-0.04354415386753951 * d) - 3.166924740191411
  return clamp(raw + 1, 0, 100)    // +1 "uncertainty bonus"
```
(L56-74 `fromEvalsAndPov` applies this per player move for insights; it is NOT what the API/game accuracy uses.)

#### 1.3 Game accuracy (L79-113 `gameAccuracy`; used by API GameApiV2.scala L324-327 and JsonView.scala L68)
Input: `cps` = white-POV evals of [initial position] + after each ply (length n = plies+1). Mates map to +-Int.MaxValue-ish (`forceAsCp`, tree/eval.scala L7-13) which `ceiled` turns into +-1000. Missing eval = None.
```
wp[i] = winCp(cps[i])                       // white POV, clamp +-1000
ws    = clamp((n-1) ~/ 10, 2, 8)            // integer division; n-1 = number of plies
windows = (min(ws,n) - 2 copies of wp[0..ws))  ++  sliding windows of size ws over wp (all n-ws+1; if n<ws one window = whole list)
   // => exactly n-1 windows, window k belongs to pair (wp[k],wp[k+1])
weight[k] = windows[k] has no None ? clamp(populationStdDev(windows[k]), 0.5, 12) : none
for pair i in 0..n-2:                        // move i is made by startColor if i even
  mover = (i even) == startWhite ? white : black
  acc = mover==white ? accMove(wp[i], wp[i+1]) : accMove(wp[i+1], wp[i])   // black: flipped, loss = white gain
  skip if wp[i], wp[i+1] or weight is None
per colour: weightedMean = sum(acc*w)/sum(w)            (None if sum w == 0)
            harmonic     = count / sum(1/max(1,acc))    (Maths.harmonicMean, scalalib Maths.scala L22-24)
            result       = (weightedMean + harmonic)/2
```
Returns None unless BOTH colours have >=1 move (so a 1-ply game -> None). popStdDev = sqrt(sum((x-mean)^2)/count) (Maths.scala L63-68, population not sample). Displayed value = `Math.round` (floor(x+0.5)) to int (scalalib model.scala `Percent.toInt`).
- **Alignment / start:** pair i=0 is the first move by `startColor` (= colour to move at start ply; Black for FEN-start with b to move). Initial eval = `analysis.initialScore` or legacy **+15 cp** if absent (tree/eval.scala L30, Analysis.scala L52). The API does **not export the initial eval**, so for vectors use 15 cp.
- **Mates:** eval entries are white-POV `{"mate": m}`; m>0 white mates, m<0 black mates; map to +1000/-1000. For mating games the `analysis` array has plies-1 entries (final checkmate ply omitted, `makeInfos` "ambiguousEnd" in fishnet/AnalysisBuilder.scala); feed arrays as-is.
- Glyph-specific: own engine evals for a terminal checkmate position: score = win for mover (+-1000 cp); include it (it only adds a 100 for the mating side).

#### 1.4 Verification
Python port of the above run against 210 real server-analysed games (DrNykterstein, penguingim1, Fins; 147 resign, 23+2 mate (standard+960), 19+2 timeout, 11 draw, 1 stalemate, 10 chess960; 76 with mate evals), initial=15: **all 420 per-player accuracies match lichess's integer within 0.4997 (i.e. identical after rounding).** So +-1 tolerance in the spec is more than enough; use +-0.5 pre-rounding or exact int equality.

#### 1.5 Hand-checked examples (win_cp(cp)=50+50*(2/(1+e^(-0.00368208*cp))-1))
- win(0)=50, win(15)=51.380429, win(100)=59.102590, win(-300)=24.887450, win(500)=86.307166, win(+-1000/1500/mate)=97.544744/2.455256.
- accMove(60,50) d=10: 103.16681*e^-0.4354415=66.58-3.167+1 = 64.5798. accMove(51,50)=96.604 (d=1). d=50 -> 9.5278; d>=~73 -> 0.
- Game, white starts, cps [15,-50,15,-40,10] (n=5, ws=2): wp=[51.3804,45.4104,51.3804,46.3246,50.9204]; pair accs W 77.383, B 77.383, W 80.614, B 82.289; windows size 2 so sd=|diff|/2 -> weights 2.985,2.985,2.528,2.298. White: weighted=(77.383*2.985+80.614*2.528)/5.513=78.86; harmonic=2/(1/77.383+1/80.614)=78.96; result **78.91**. Black **79.64**. -> displays 79 / 80.
- cps [15,-900,-900] white start: wp=[51.38,3.51,3.51]; white acc=10.659 (d=47.87), single weight (sd 23.9 clamped 12) -> white 10.66 (test says 10+-5); black pair has after>=before -> 100.
- Real: lichess game Lk80KJQh (docs/m0/lichess_sample.ndjson) white 93 / black 55; PXXPWDlC (chess960) 86 / 78 -- reproduced.
- Test file lila `modules/analyse/src/test/AccuracyPercentTest.scala` (uses tolerance windows, e.g. 50x(-50,15) -> 76+-8) can be ported as extra unit tests.

### 2. chess-openings
- Layout: `a.tsv..e.tsv` (ECO volumes), header `eco\tname\tpgn`; 3865 data rows, 3177 distinct names, 3332 distinct (eco,name). `bin/gen.py` (needs python-chess), `Makefile` -> `dist/{all,a..e}.tsv`; **dist/ is gitignored (not in repo)**; CI artifacts or Parquet mirror (hf.co/datasets/Lichess/chess-openings) only. Dist columns: `eco name pgn uci epd` (gen.py L126).
- pgn column: clean SAN with move numbers (`1. g3 Nc6`), max 36 plies, avg 9.8. Many entries intentionally share a name (transpositions). gen.py errors on duplicate EPD, so **EPD is unique per row** (verified: 0 dups).
- EPD convention: `board.epd()` = first 4 FEN fields; en passant square only when an ep capture is legal (README table). Verified by replaying all rows with dartchess 0.14 (`Position.fen` uses `_legalEpSquare()`, position.dart L128-137; take first 4 fields): 15 rows carry an ep square (e.g. `... w KQkq f6`), no duplicates. So no python needed: build tool = replay pgn with dartchess.
- Licence: CC0 (COPYING.txt); attribution not required, credit anyway.
- Recommended asset: `assets/openings.tsv`, lines `epd\teco\tname` (433 KB raw, ~61 KB deflated inside the APK; no extra gzip needed). Load into `Map<String,(String eco,String name)>` (~3865 entries). Lookup key = first 4 FEN fields of position after the move (dartchess `fen`). Optional `uci` not needed. A binary hash table would be ~63 KB gz too -- not worth it.

### 3. Lichess games export (api `doc/specs/tags/games/api-games-user-username.yaml`, lila `app/controllers/Game.scala` L175-188)
Real request (verified, HTTP 200, `Accept: application/x-ndjson`): `GET /api/games/user/DrNykterstein?max=2&evals=true&accuracy=true&pgnInJson=true&clocks=true&opening=true&division=true&analysed=true&perfType=blitz,rapid,classical`
- Defaults (non-extended): `moves=true tags=true clocks=false evals=false opening=false division=false accuracy=false pgnInJson=false sort=dateDesc`. `accuracy` and `evals` independent; either triggers analysis lookup (`requiresAnalysis`, misc.scala L193). Games without analysis simply lack `analysis`/accuracy. `analysed=true` filters to analysed games.
- Top-level keys seen: id, rated, variant, speed, perf, createdAt, lastMoveAt (ms), status, source, players, [initialFen], [winner], [opening{eco,name,ply}], moves (space SAN string), clocks (centiseconds, one per ply, needs clocks=true), pgn (pgnInJson), analysis[], [arenaTour], clock{initial,increment,totalTime}, division{middle,end}. `opening` absent for chess960 and when unknown. `initialFen` present for non-standard start (chess960 seen with it).
- Per player: `players.white.analysis = {inaccuracy, mistake, blunder, acpl, accuracy (INT, rounded), phases{opening,middlegame,endgame}}`; also `user{name,id,title?,...}`, `rating`, `ratingDiff`, `provisional`. `accuracy` only with `accuracy=true`.
- `analysis[]` (evals=true): one entry per ply AFTER the move, white POV: `{eval:<cp int>}` or `{mate:<int>}`; optional `best` (UCI), `variation` (SAN), `judgment{name,comment}` (only Inaccuracy/Mistake/Blunder). Length = plies, or plies-1 when game ended in checkmate. Initial eval is not included.
- PGN eval comments `[%eval 0.32]` / `[%eval #3]` (pawns, 2 dp), `[%clk h:mm:ss]`, `[Opening]`,`[ECO]`; chess960 pgn has `[Variant "Chess960"][FEN ..][SetUp "1"]`; castling written as `O-O`.
- perfType values: ultraBullet,bullet,blitz,rapid,classical,correspondence,chess960,crazyhouse,antichess,atomic,horde,kingOfTheHill,racingKings,threeCheck (comma separated). `variant` key lowercase (`standard`,`chess960`). Status values seen: resign, mate, outoftime, draw, stalemate.
- Throttle: spec says anonymous 20 games/s; lila Game.scala L67-71 uses 25 anonymous, 30 OAuth. No rate-limit headers observed; 429 -> wait 60 s. Content-Disposition attachment header present; `access-control-allow-origin: *`.
- Sample: docs/m0/lichess_sample.ndjson (2 games, usernames redacted to player_white/player_black, titles/flair removed).

### 4. Chess.com PubAPI (verified 2026-11-04, UA `Glyph-M0-research (https://github.com/umarh/glyph)`)
- `GET /pub/player/hikaru/games/archives` -> `{"archives":[".../games/2014/01", ... ".../games/2026/11"]}` ascending, 155 entries. Headers: `etag: W/"..."` (weak), `last-modified`, `cache-control: public, max-age=60` (archives) / `max-age=5` (month).
- Month `/games/2026/10`: 2.4 MB, 583 games. Conditional GET with `If-None-Match: <etag as sent, incl. W/>` -> **304**. Unknown user -> 404 `{"code":0,"message":"User \"x\" not found."}`.
- Game keys: url (`https://www.chess.com/game/live/<id>`), pgn (with `{[%clk 0:02:59.9]}` comments, tags incl. `[ECO]`, `[ECOUrl]`, `[Termination]`, `[CurrentPosition]`), time_control ("180", "60"), end_time (unix s), rated, accuracies{white,black} (FLOAT, 583/583 present for this user; treat as optional), tcn, uuid, initial_setup (FEN), fen (FINAL position), time_class (bullet/blitz seen; also rapid/daily), rules ("chess" for all; other values e.g. chess960 not observed here), white/black{rating,result,@id,username,uuid}, eco (**a URL, not an ECO code**; code is in the PGN tag), optional `tournament` URL.
- Result strings seen: win, resigned, timeout, checkmated, repetition, insufficient, agreed, timevsinsufficient, abandoned, stalemate.
- Sample: docs/m0/chesscom_sample.json (2 games).

### 5. Stockfish 19 UCI (desktop binary; net nn-1a298aa575a0.nnue is **109 MiB**, spec said ~94 MB)
- Handshake: `uci` -> `id name Stockfish 19`, options, `uciok`. Options of interest: Threads (1..1024), Hash (default 16), MultiPV (1..256), UCI_Chess960 (check), UCI_ShowWDL. `isready` -> `readyok`; `ucinewgame` + `isready` -> another `readyok`. `info string ...` lines (thread count, NNUE net) are emitted after the first isready/go.
- Info line exact format (MultiPV 2, one line per multipv per depth, multipv 1 first):
  `info depth 12 seldepth 21 multipv 1 score cp 20 nodes 41218 nps 368017 hashfull 13 tbhits 0 time 112 pv f3g5 d7d5 e4d5 ...` then `... multipv 2 score cp 17 ...`; ends `bestmove f3g5 ponder d7d5`. Mate: `score mate 1 ... pv d1d8` (positive = side to move mates). No `lowerbound/upperbound` or `currmove` appeared in these short runs; parser must still skip them.
- Terminal positions: checkmate or stalemate -> `info depth 0 score cp 0` + `bestmove (none)` (NOT `mate 0` in SF19); insufficient material (K vs K) still searches (cp 0 at depth 8; ponder lines). Threefold via `position startpos moves ...` 8 plies of knight shuffling: SF returned cp 29 and a normal move at depth 8 (draw by repetition only after the repeated position is reached; history still needed).
- Castling: standard mode emits `e1g1` / `ponder e8g8`; with `UCI_Chess960=true` it emits king-takes-rook `e1h1` / `e8h8`. Test FEN `r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 5`, depth 14: std `bestmove e1g1 ponder e8g8`, 960 `bestmove e1h1 ponder e8h8`.
- Input is mode-strict: 960 mode + `moves e1g1` -> `info string CRITICAL ERROR: Command ... failed. Reason: Illegal move: e1g1`; standard mode + `e1h1` -> same error. The process stays alive but the position is not set -> must send moves in the notation matching UCI_Chess960 (or never send moves that SF rejects; listen for `CRITICAL ERROR`).

### 6. Spec discrepancies summary
1. Mate -> cp: server uses +-1000 flat (no distance); TS client uses (21-min(10,|m|))*100. Spec guess partly wrong.
2. Per-move formula has "+1" bonus and clamp [0,100]; return 100 if after>=before (spec omitted).
3. Game accuracy: `WinPercent` is in scalachess; window = clamp((plies)/10,2,8); weight sd clamp [0.5,12]; harmonic uses max(1,acc); initial eval 15 cp.
4. Lichess `accuracy` is an integer; chess.com `accuracies` are floats.
5. SF19 net 109 MiB; terminal positions give `cp 0` + `bestmove (none)` not `mate 0`.
6. Chess.com `eco` is a URL; anonymous lichess throttle is 25/s in code vs 20 in docs.
7. dist/ of chess-openings is not committed: Glyph's build tool must generate EPDs itself (feasible with dartchess).

## Part B: libraries
## M0 — Libraries research (dartchess, chessground, multistockfish, build probe)

Researched 2026-11-04 against: Flutter 3.47.9 / Dart 3.13.7, upstream clones in `~/development/upstream/` (dartchess `c839a7f`, flutter-chessground `083e343`, dart-multistockfish `fd8dcea`, mobile `5bd273a`, lila `2026-11-04`), pub.dev packages as resolved in the probe app (`~/development/scratch/m0/probe`, pure-Dart experiments in `~/development/scratch/m0/core_probe`). Per the precedence rule, upstream source wins over the spec; every discrepancy is flagged **[SPEC≠UPSTREAM]**.

Paths below are relative to the upstream clone named at the start of the reference, e.g. `dartchess/lib/src/pgn.dart:123` = `~/development/upstream/dartchess/lib/src/pgn.dart` line 123.

### 0. Headline findings

1. **No STOP condition hit.** `multistockfish` builds with Flutter 3.47.9 / NDK 28.2.13676358 (see section 3), chessground has a public annotation API plus an overlay path, and every dependency is GPL-3-compatible.
2. **[SPEC≠UPSTREAM] chessground is 11.0.0 now (not 10.x).** Needs `dartchess ^0.14.0` (same as 10.3). 11.0.0 only changes brightness/contrast filter handling (`flutter-chessground/CHANGELOG.md` "11.0.0"). Use `chessground: ^11.0.0`.
3. **[SPEC≠UPSTREAM] `sqlite3_flutter_libs` is obsolete.** `sqlite3` 3.x bundles SQLite through build hooks; `sqlite3_flutter_libs 0.6.0+eol` is an empty shim (its README: "obsolete after upgrading ... remove this package"). Drop it from the dependency list.
4. **[SPEC≠UPSTREAM] dartchess has no `Position.parseUci`/`makeUci`.** Use `Move.parse(uci)` / `NormalMove.fromUci` and `Move.uci`; both throw `RangeError` on short garbage input, so length-guard first.
5. **dartchess PGN parser has no error reporting at all** (invalid tokens silently skipped) and its multi-game splitter is a naive regex that merges games not separated by a blank line and splits on `\n\n[` inside comments. Glyph needs its own pre-splitter (the spec's fallback) plus SAN replay for illegal-move errors.
6. **Castling is king-to-rook in dartchess** (`e1h1`), and `UCI_Chess960` decides what Stockfish accepts and emits. Verified against the Stockfish 19 binary: in non-960 mode `position ... moves e1h1` is **silently ignored** (position unchanged). Decision: always set `UCI_Chess960=true` (lichess mobile does exactly this, `mobile/lib/src/model/engine/engine.dart:462-467`).
7. **`material_ui` / Flutter 3.47:** `package:flutter/material.dart` still exists in the 3.47.9 framework, but the standalone `material_ui` package is the forward path, lichess mobile already imports it, and `dynamic_color 2.1.0` returns `material_ui` types. Use `material_ui` consistently (section 4).
8. **Build-time network access is required** for: `sqlite3` (downloads prebuilt `libsqlite3` from GitHub releases through build hooks) and `multistockfish_light` (CMake `file(DOWNLOAD ...)` of the 1.1 MB NNUE from tests.stockfishchess.org, although the file is also vendored in the pub package). Matters for F-Droid-style offline builds (section 3.7).
9. **chessground bundles ~40 piece sets and ~24 boards as package assets**, most under non-free licences (trap 15). The pub package pubspec lists them all, so a plain dependency ships all of them (section 2.5). See the decision there.

---

### 1. dartchess 0.14.0 (GPL-3.0)

Version required by chessground 11.0.0 and 10.3.0: `dartchess: ^0.14.0` (`flutter-chessground/pubspec.yaml:dependencies`). Resolved: **0.14.0** (published 2026-09-29). Dependencies are minimal (`meta`).

#### 1.1 Castling representation

- `Position.legalMoves` returns castling as **king-to-rook** (`position.dart:940-968`, `_castlingMove` returns `SquareSet.fromSquare(rook)`). Verified: after `1.e4 e5 2.Nf3 Nc6 3.Bc4 Bc5`, `legalMoves[e1] = [f1, h1, e2]`.
- `Position.parseSan('O-O')` returns `NormalMove(king, rook)` = `e1h1` (`position.dart:324-335`).
- `Position.isLegal(move)` accepts **both** forms: `legalMoves.has(t) || legalMoves.has(normalizeMove(move).to)` (`position.dart:238-258`). Verified: `isLegal(e1g1)` and `isLegal(e1h1)` both true.
- `Position.normalizeMove(NormalMove)` converts king-two-squares to king-to-rook (`position.dart:655-668`, def. at `:659`, doc: "The normalized form of a castling move is the king-to-rook move"). Detection is `_getCastlingSide` (`position.dart:985-1000`): the moved piece is the king and either `|to-from| == 2` or `to` is an own piece.
- `playUnchecked` / `makeSan` accept both forms and give identical results (verified: same FEN, SAN `O-O`).
- `makeLegalMoves(pos)` in `utils.dart:7-35` returns the destination map with **both** representations by default (`includeAlternateCastlingMoves: true`, only for kings on the e-file). This is for chessground's `validMoves`, not for engine comparison.
- Chess960: `b1g1` is not legal for a king on b1; only `b1h1`/`b1a1` are (verified with `4k3/8/8/8/8/8/8/RK5R w AH - 0 1`). King-two-squares is therefore impossible to interpret in 960, which is another reason to always use 960 notation toward the engine.

#### 1.2 UCI <-> Move <-> SAN

| Need | API (file:line) | Notes |
|---|---|---|
| UCI string -> `Move` | `Move.parse(String)` `models.dart:487-507` (returns `null` on bad input, but **throws `RangeError`** for strings shorter than 2 chars because it indexes `str[1]`; verified `Move.parse('e')`); `NormalMove.fromUci` `models.dart:540-551` (throws `RangeError` for `'zz'`, `FormatException` only for well-formed-length bad squares) | Guard: `uci.length == 4 || 5` before calling. |
| `Move` -> UCI | `Move.uci` (`models.dart:487`, `NormalMove.uci` `:571`, `DropMove.uci` `:616`) | Raw; castling stays whatever form the `Move` holds. |
| UCI -> SAN (checked) | `pos.makeSan(move)` returns `(Position, String)`; `pos.toSan(move)` is `@Deprecated` (`position.dart:618-652`) | Throws `PlayException` if illegal. Adds `+`/`#` (`#` only when `outcome.winner != null`). |
| SAN -> `Move` | `pos.parseSan(String)` `position.dart:281-523` | `null` if illegal/unparseable. Strips `+ # ! ?` suffixes (verified `e4+`, `e4!?`). Disambiguation and promotion (`e8=Q`) supported. |
| Play | `pos.play(move)` (throws `PlayException`), `pos.playUnchecked(move)` (`position.dart:526-606`) | |
| Compare engine move to played move | `pos.normalizeMove(engineMove as NormalMove) == playedMove` (both normalized) | Spec trap 2. With `UCI_Chess960=true` the engine already emits king-to-rook, so `Move.parse(engineUci)` directly equals the dartchess castling move. |
| EPD/FEN | see 1.3 | |

Promotion: `NormalMove.promotion` is a `Role`; `isLegal` rejects `promotion == pawn`, `king` (non-antichess), and promotions that are not pawn-to-backrank (`position.dart:240-246`).

#### 1.3 FEN / EPD / en passant

- No EPD helper exists (`constants.dart` has `kInitialEPD` only). Derive EPD as the first four space-separated fields of `pos.fen`.
- **`Position.fen` reports the en passant square only when an en passant capture is fully legal** (`position.dart:128-139` uses `_legalEpSquare()`, `:1010`). Verified: after `1.e4` from the start position FEN has `-` (no capturing pawn), after `1.e4 a6 2.e5 d5` it has `d6`. This matches spec trap 7 ("en passant only if legal") and lichess's chess-openings `epd` convention, so `pos.fen.split(' ').take(4).join(' ')` is the book key. Re-verify against the generated openings `epd` column in M2 (mismatch on a few ep positions would otherwise hide transposition hits).
- `pos.epSquareOf(EnPassantMode.legal | pseudoLegal | always)` (`position.dart:267-279`, `models.dart:33-47`, new in 0.14.0) gives the three conventions explicitly.
- `Setup.parseFen(fen)` (`setup.dart:33-166`) is lenient: missing fields default, accepts `_` as separators, throws `FenException(IllegalFenCause...)` (`models.dart:629-669`). It keeps whatever ep square the FEN contains; `Position.setupPosition(rule, setup)` / `Chess.fromSetup(setup)` throws `PositionSetupException(IllegalSetupCause...)` for illegal positions (`models.dart:685-720`, `position.dart:672-698`).
- Castling in FEN output: `KQkq` for outermost rooks, file letters otherwise (`setup.dart:352-372`, X-FEN). Parsing accepts `KQkq` and Shredder letters (`setup.dart:305-338`). Verified round trip of a Chess960 FEN `HFhf` -> `KQkq` (equivalent here).
- `Position.initialPosition(Rule.chess)`, `Chess.initial`, `kInitialFEN` exist. `Position.ply`, `halfmoves`, `fullmoves` getters.
- **Zobrist** (new in 0.14.0): `pos.zobristHash({mode = EnPassantMode.legal})` in `zobrist.dart:20-26`, Polyglot-compatible for standard chess, excludes halfmove/fullmove clocks. This is the cheapest repetition key (see 1.7).

#### 1.4 PGN API (`pgn.dart`)

- Types: `PgnGame<T extends PgnNodeData>` with `headers` (`Map<String,String>`), `comments` (game-level `{}` before the first move), `moves` (a root `PgnNode` holding `children`). `PgnNodeData{san, startingComments, comments, nags}`. `PgnChildNode.data` is mutable.
- Single game: `PgnGame.parsePgn(pgn, {initHeaders})` (`pgn.dart:100-117`); multi-game: **`PgnGame.parseMultiGamePgn`** (`:123-142`); lazy header-only list: `parseMultiGameLazy` returning `PgnLazyGame{headers, rawPgn}` and `toPgnGame()` (`:144-166`, `:952-962`).
- **Default headers are injected** (`defaultHeaders()`: Event/Site/Date/Round/White/Black `?`, Result `*`). Pass `initHeaders: PgnGame.emptyHeaders` so "missing" stays distinguishable from "?" (verified; otherwise a headerless game reports `Event: ?`).
- **Multi-game splitting is `pgn.split(RegExp(r'\n\s+(?=\[)'))`** (`pgn.dart:125`, `:146`). Consequences (verified by experiment):
  - Games separated by a single `\n` (no blank line) are **merged into one game** (`[Event A]...1-0\n[Event B]...` -> 1 game).
  - A `{...}` comment containing a blank line followed by `[` is **split in the middle** (3 games from 2).
  - CRLF with blank lines and a leading BOM work (BOM is stripped per chunk, `pgn.dart:771-772`).
  - Fix (spec fallback): pre-split in `glyph_core` with a small state machine that tracks `{}`/`;` comments and only starts a game at a line beginning with `[` when the previous non-blank content was a result token (`1-0`, `0-1`, `1/2-1/2`, `*`) or start of file; then call `parsePgn` per chunk. Cap at 500 games / 2 MB before splitting.
- **Single-game parser** (`_PgnParser`, `pgn.dart:698-950`): line based; strips `\r` before `\n` (`:744-759`) but not lone `\r` (a lone-CR file becomes one line; verified it still parsed because the whole thing is processed as a single line). Headers via regex `^\s*\[([A-Za-z0-9][A-Za-z0-9_+#=:-]*)\s+"((?:[^"\\]|\\"|\\\\)*)"\]` (`pgn.dart:790`). Movetext tokenizer is a single regex (`pgn.dart:817`); **anything that does not match is skipped silently** (this is the "error reporting" answer: **none**, no line/ply, never throws). `%` escape lines and `;` comments are dropped. Null moves `--`, `Z0`, `0000` -> `--`; `0-0`/`0-0-0` -> `O-O`/`O-O-O`.
- **Illegal moves are only detected on replay**: `pos.parseSan(node.san) == null`. Report `game index + ply + SAN` ourselves (spec trap 10). Tokenizer also accepts arbitrary junk that looks like a move (e.g. a stray `a1`), and `parsePgn` returns an empty tree for input without any header or move.
- **Comments:** `{...}` may span lines; the first `}` closes it, so **nested braces are not supported** (verified: `{a { nested } e4 trailing}` leaves ` e4 trailing}` as movetext and `e4` becomes a bogus move). Lichess/chess.com do not emit nested braces; sanitize on import only if a test vector needs it.
- **Comment helpers:** `PgnComment.fromPgn(String)` (`pgn.dart:537-597`) extracts `[%clk h:mm:ss(.fff)]`, `[%emt ...]`, `[%eval 0.17|#-3(,depth)]`, `[%cal ...]`, `[%csl ...]` and leaves the rest as `text`. Verified formats: `[%clk 0:09:58.9]`, `[%clk 1:23:45.67]`, `[%eval 0.17]`, `[%eval #-3]`, `[%eval -0.5,18]`, `[%eval 12]`, `[%eval .5]`, combined `[%clk ..] [%eval ..] hi` -> text `hi`. Limits: clk hours `\d{1,5}`, seconds fraction max 3 digits (a 4+ digit fraction will not match and stays in `text`); eval pawns `\d{1,5}` or `\d{0,5}\.\d{1,2}` (more than 2 decimals will not match); eval is a `PgnEvaluation{pawns, mate, depth, evalType}`.
- `PgnComment.makeComment()` (`:599-616`) emits `text`, `[%csl]`, `[%cal]`, `[%eval x.xx(,d)]`, `[%emt]`, `[%clk]` in that order; pawns formatted `toStringAsFixed(2)`; mate as `#N`.
- **NAGs:** parsed as `$n` and also `! ? !! ?? !? ?!` suffix glyphs -> NAG 1..6 (`pgn.dart:826-842`), stored in `PgnNodeData.nags` as `List<int>`; emitted as `$n` by `makePgn`.
- **Variations:** `(` pushes a new frame whose parent is the same node, so alternatives are extra `children` entries; **`children[0]` is always the mainline**. Walk the mainline with `game.moves.mainline()` (`pgn.dart:326-334`, yields `PgnNodeData`) or iterate `children.first`. `PgnNode.transform` (`:339-368`) maps a tree with context (use it to attach positions/evals).
- **Emitting PGN:** `PgnGame.makePgn()` (`:186-300`). Build `PgnChildNode(PgnNodeData(san:, nags:[1], comments:[PgnComment(eval:, clock:, text:).makeComment()]))` and append to `moves.children` / `child.children`. Verified output: `1. e4 $1 { hi [%eval 0.30] [%clk 0:05:03.2] } 1... e5 $4 *`. Notes: `_safeComment` strips `}` from comment text (`:679`); header values are escaped; headers are written in map order (use `LinkedHashMap`, i.e. the default `{}`), Seven Tag Roster order is the caller's job; a game result comes from `headers['Result']` via `Outcome.fromPgn`; `FEN` header controls the starting ply/move number (`_getPlyFromSetup`, `:682`).
- **Headers / variants:** `PgnGame.startingPosition(headers, {ignoreImpossibleCheck})` (`:169-184`) uses `Rule.fromPgn(headers['Variant'])` (`models.dart:744-800`) then `Position.setupPosition(rule, Setup.parseFen(FEN))`. **`Rule.fromPgn` maps `Chess960`, `Chess 960`, `Fischerandom`, `From Position`, `Standard`, `Wild/*` all to `Rule.chess`**, unknown values return `null` (-> `PositionSetupException.variant`), and Crazyhouse/KOTH/3-check/Antichess/Atomic/Horde/Racing Kings map to their `Rule`. So: (a) detect 960 yourself from `Variant` (case-insensitive `chess960|chess 960|fischerandom|fischerrandom|fischer random`) to set `UCI_Chess960`/UI flag (with always-960 notation it only matters for display and Book disabling), (b) reject any `rule != Rule.chess` and any `null` rule with "variant not supported", (c) `SetUp "1"` + `FEN` is handled via the `FEN` header alone.
- Verified: `PgnGame.startingPosition({'Variant':'Crazyhouse'})` succeeds (returns a Crazyhouse position), `{'Variant':'Foo'}` throws `PositionSetupException: variant`, `{'FEN':'garbage'}` throws `FenException: board`.

#### 1.5 Game-state API (`position.dart`)

- `Position.legalMoves` -> `Map<Square, SquareSet>` (`:193-201`), `legalMovesOf(square)`, `hasSomeLegalMoves`, `isLegal`.
- `isCheck` (`:141`), `isCheckmate` (`:151`), `isStalemate` (`:155`), `isGameOver` (`:147`), `outcome` -> `Outcome?` (`:159-170`; `Outcome(winner: Side?)`, `Outcome.draw`).
- `isInsufficientMaterial` (`:172`) = **both** sides lack winning material (`hasInsufficientMaterial(side)` `:217-236`). Verified: K+B v K true, K+N v K true, K+N v K+N **false**, same-colour K+B v K+B true, opposite-colour bishops false, K+B v K+N false. This matches lichess's rule; no 'dead position' search.
- `isCheckmate`/`isStalemate` are the only terminal checks; none are evaluated for threefold/50-move.
- `checkers`, `kingAttackers(square, attacker, {occupied})` (`:206-215`) are public and useful for SEE.

#### 1.6 Repetition / 50-move / SEE

- **No repetition tracking** and **no draw-by-rule helpers**. `Position.halfmoves` exists (the 50-move counter), so `halfmoves >= 100` is the caller's check. Use `zobristHash()` (section 1.3) per ply to detect threefold in `glyph_core` (and still send full history to the engine, trap 9).
- **No SEE helper.** Public building blocks in `attacks.dart`: `kingAttacks`, `knightAttacks`, `pawnAttacks(side, sq)`, `bishopAttacks/rookAttacks/queenAttacks(sq, occupied)`, `between`, `ray`, plus `Board` piece sets (`board.dart`) and `Position.kingAttackers`. SEE must be written in `glyph_core` (M4) from `Board` and attack sets, using x-ray updates after each capture and legality via pins (`_sliderBlockers` is private; approximate pins with king-attack check on the resulting position when needed).

#### 1.7 Misc

- Return types are plain Dart collections since 0.13.0 (no `fast_immutable_collections`).
- `Position` is immutable; `Chess.initial` is typed `Chess`, so declare variables as `Position` when reassigning (compile error seen in the probe test otherwise).
- `Position.toSan` is deprecated -> use `makeSan(move).$2`.

---

### 2. chessground 11.0.0 (GPL-3.0)

Resolved: **11.0.0** (published 2026-10-28; `sdk >=3.7.0`, `flutter >=3.29.0`, deps `dartchess ^0.14.0`, `meta ^1.18.0`; `material_ui: any` is a **dev** dependency only). **[SPEC≠UPSTREAM]** spec says 10.x. 10.3.0 "Removed dependency on Flutter's material library" and already needs dartchess 0.14.0, so both work with the 3.47 split; 11.0.0 is current and what lichess mobile uses (`mobile/pubspec.yaml:chessground: ^11.0.0`). Breaking changes 10 -> 11 only: `brightness` now applies to the board background only; `BrightnessHueFilter` renamed `ColorAdjustFilter` (`CHANGELOG.md`).

#### 2.1 Widgets and driving model (differs from the pre-10 API)

- `Chessboard` (interactive) requires a `ChessboardController(game: GameData(...))`; call `controller.updatePosition(GameData, {animate, resetPremove})` per ply (`lib/src/widgets/board_controller.dart:41,270`; README "Interactive board"). `GameData{fen, playerSide, sideToMove, validMoves, lastMove, kingSquareInCheck, validDropSquares}` (`models.dart:23-55`).
- `StaticChessboard({size, orientation, fen, lastMove, settings, shapes, squareHighlights, onTouchedSquare})` (`widgets/static_board.dart:36-53`): non-interactive, animates on FEN change, optimized for lists. **It has no `annotations` parameter.**
- View-only/non-interactive: use `StaticChessboard`, or `Chessboard` driven with `playerSide: PlayerSide.none` (`board.dart:42-45` doc comment; `controller.interactive == false`). `onTouchedSquare` still fires on non-interactive boards, usable for tap-to-select-square.

#### 2.2 Square annotations / badges

- `Annotation({required String symbol, required Color color, Duration? duration})` (`models.dart:96-122`); "Two letters max" text in a coloured circle. Passed as `Chessboard(annotations: Map<Square, Annotation>)` (`board.dart:54,87`). Rendered by `BoardAnnotation` (`widgets/board_annotation.dart:57-100`): a circle of `0.48 * squareSize`, placed at the **top-right corner** of the destination square (shifted inward on the board's right edge), 150 ms scale-in, `Text(symbol)` white `FontWeight.w800`. Only text glyphs; no icons, no custom child.
- **Dedicated "badge on destination square" API exists** (`Annotation` on `Chessboard`), but only for text symbols and not on `StaticChessboard`.
- lichess mobile usage: NAG -> symbol/colour table `mobile/lib/src/widgets/pgn.dart:43-90` (`_nagAnnotations`, `makeAnnotation(nags)`), applied in `mobile/lib/src/view/analysis/analysis_board.dart:236-245` (`boardAnnotations = {sanMove.move.to: annotation}`, passed at `:284`). For castling it maps king-to-rook UCI to the king's real destination with `altCastles` (`mobile/lib/src/model/common/chess.dart:60`: `{'e1a1':'e1c1','e1h1':'e1g1','e8a8':'e8c8','e8h8':'e8g8'}`; `kingTakesRookCastles` and `normalizeUci` at `:63-67`). **Glyph must do the same**: with dartchess castling `e1h1` the badge belongs on `g1`, not on the rook square.
- **Cleanest way to get Glyph's own vector badges (spec: "Badge icons are Glyph's own vector drawings"):** `CustomShape({orig, child, scale = 1.0})` (added in 10.2.0, `models.dart:322-359`, rendered in `widgets/shape.dart:80-89`) draws any widget, centered, in a box of `scale * squareSize` on `orig` inside `Chessboard`/`StaticChessboard(shapes: {...})`. A corner badge is `CustomShape(orig: dest, child: Align(alignment: Alignment.topRight, child: FractionallySizedBox(widthFactor: .48, heightFactor: .48, child: BadgeIcon(...))))`. This compiled in the probe (`StaticChessboard` + `CustomShape`). `CustomShape` is wrapped in `IgnorePointer` and is clipped to the board, so a corner badge on the h-file is still inside the board. Overlay fallback if ever needed: a `Stack` over the board using `left = file*sq`, `top = (7-rank)*sq` (mirror for Black orientation), what `ChessboardGeometry.squareOffset` does internally (`widgets/geometry.dart`, not exported).
- Spec 2.3 "square annotations -> use its API; fallback Stack overlay": **API exists; use `CustomShape` for icon badges (no overlay needed)**. Use `Annotation` only if text glyphs (`!!`, `?`) are acceptable.

#### 2.3 Arrows, shapes, last move

- `Shape` (sealed, `models.dart:125`): `Circle{color, orig, scale}`, `Arrow{color, orig, dest, scale}` (`orig != dest` asserted), `PieceShape`, `CustomShape`. Passed as `shapes: Set<Shape>` on both widgets. `Arrow.scale` in (0,1] scales width; width = 1/4 square at 1.0. Best-move arrow in lichess mobile: `analysis_board.dart:176,240` (`_bestMoveShapes`). For castling arrows use the king's real destination (see `altCastles`).
- Last-move highlight: `ChessboardSettings.showLastMove` / `StaticChessboardSettings.showLastMove` (`board_settings.dart:94,155`), driven by `GameData.lastMove` / `StaticChessboard.lastMove`; colour from `ChessboardColorScheme.lastMove` (a `HighlightDetails`). A king-to-rook castling `Move` highlights king and rook squares; pass the normalized king-two-squares move for display (`Move.parse(altCastles[uci]!)`).
- `squareHighlights: Map<Square, SquareHighlight>` on `StaticChessboard` for per-square tints.
- `DrawShapeOptions` lets the user draw shapes with two fingers (disable for review: `drawShape: DrawShapeOptions(enable: false)`).
- Other settings: `border`, `borderRadius`, `boxShadow`, `brightness`/`contrast`/`hue`, `enableCoordinates`, `animationDuration` (250/200 ms), `blindfoldMode`, `pieceOrientationBehavior`.

#### 2.4 Piece sets and board themes

- `PieceSet` enum with 40+ entries and `assets` (`lib/src/piece_set.dart:8-49`). **Default piece set is `PieceSet.cburnettAssets`** (`board_settings.dart:84,355`); default board is `ChessboardColorScheme.brown` (a solid colour theme, no image; `:83,354`).
- Board themes: static consts in `lib/src/board_color_scheme.dart` (`brown, blue, green, ic` are solid colours; `blue2, blue3, blueMarble, canvas, greenPlastic, grey, horsey, leather, maple, maple2, marble, metal, newspaper, olive, pinkPyramid, purple, purpleDiag, wood, wood2, wood3, wood4` use JPG/WebP backgrounds from `assets/boards/`).
- Images load through `ChessgroundImages` (singleton cache, README "Piece image cache"); pre-load with `ChessgroundImages.instance.loadAll(PieceSet.cburnettAssets)` to avoid invisible pieces on the first frame.

#### 2.5 Licences of bundled piece sets and boards (trap 15)

chessground itself is GPL-3.0 and ships **no per-asset licence file** (only `assets/piece_sets/shahi-ivory-brown/LICENSE.txt`). The authoritative table is lila's `COPYING.md` (`lila/COPYING.md:20-99`); `mobile/COPYING.md:29-30` adds only the learn-pieces. Mapping to the chessground directories (`flutter-chessground/assets/piece_sets/*`):

| Licence class | Sets (chessground dir name) | Ship? |
|---|---|---|
| Free, GPL-3-compatible | `cburnett` (GPLv2+), `merida` (GPLv2+), `mpchess` (GPLv3+), `chessnut` (Apache-2.0), `letter`, `pirouetti`, `pixel` (AGPLv3+), `rhosgfx` (CC0), `fantasy`, `spatial`, `celtic` (MIT), `shapes` (CC BY-SA 4.0), `kiwen-suwi`, `firi` (CC BY 4.0) | yes (attribution on About screen for CC/MIT/Apache) |
| Non-commercial (CC BY-NC-SA 4.0 / 2.5) | `horsey`, `california`, `caliente`, `maestro`, `fresca`, `cardinal`, `icpieces`, `gioco`, `tatiana`, `staunty`, `dubrovny`, `anarcandy`, `disguised`, `cooke`, `monarchy`, `xkcd` | **no** |
| Non-free / "freeware" / unlicensed (lila "Exceptions (non-free)") | `alpha`, `chess7`, `companion`, `leipzig`, `reillycraig`, `riohacha`, `shahi-ivory-brown` (no-derivatives) | **no** |
| Not listed in lila COPYING.md (licence unknown) | `kosal`, `governor`, `symmetric` (present in chessground, absent from lila), `totoy` (listed under "non-free" heading but marked CC BY 4.0) | **no** until verified |

Boards: lila `public/images/board` is "the lila authors and pirouetti, AGPLv3+" (`lila/COPYING.md:38`), so the image boards are free; **exclude the `horsey` board** (belongs to the NC horsey set; `horsey.jpg`, `horsey.last-move.webp`, `horsey.selected.webp` in `assets/boards/`). Solid-colour schemes need no image at all.

**Problem: all assets ship regardless of what Glyph uses.** The pub package's `pubspec.yaml` `flutter: assets:` lists every set directory, so a plain `chessground` dependency copies ~18 MB (41 piece sets + 24 boards, including the non-free ones) into `flutter_assets/packages/chessground/`. Flutter has no way for an app to exclude a dependency's declared assets. F-Droid's scanner flags non-free assets by content, not by use.

**Decision (recommended):** vendor chessground 11.0.0 as a path dependency (`third_party/chessground`, keeps its GPL-3.0 `LICENSE`) with the `pubspec.yaml` asset list trimmed to the allowed sets and the unwanted files deleted from `assets/`. No Dart code change is needed because assets are referenced by name only when selected. Probe copy at `~/development/scratch/m0/chessground_trim` (cburnett only + non-horsey boards = 2.3 MB vs 18 MB); APK effect measured in section 3.9. Track upstream with a small script (`tool/vendor_chessground.sh`) that re-applies the trim.

---

### 3. multistockfish 0.6.1 and the build probe

#### 3.1 Package layout and API

`multistockfish 0.6.1` (published 2026-09-29, GPL-3.0, Flutter plugin, Android + iOS) is a thin Dart layer over three native packages that it **always depends on**: `multistockfish_light 0.1.0`, `multistockfish_chess 0.6.0`, `multistockfish_variant 0.4.0` (`dart-multistockfish/pkgs/multistockfish/pubspec.yaml`). Engine is Stockfish 19.

- `Stockfish.create({flavor = StockfishFlavor.light, variant, nnuePath, onStdout})` -> `Future<Stockfish>`; completes when ready (after the plugin's own `uci` handshake) (`pkgs/multistockfish/lib/src/stockfish.dart:82-120`). `stdin = 'cmd'` setter (throws `StateError` unless `state == ready`, `:200-210`), `Stream<String> stdout` (broadcast), `ValueListenable<StockfishState> state`, `diagnostics`, `dispose()` (sends `quit`, waits, frees slot).
- Flavors (`stockfish_flavor.dart`): `light` (SF19 + embedded ~1.1 MB p_hm net), `latestNoNNUE` (needs `nnuePath`, `Stockfish.latestNNUE = 'nn-1a298aa575a0.nnue'`), `variant` (Fairy-Stockfish).
- **One engine per flavor**: second `create()` of a live flavor throws `StateError` ("A light engine is already live. Dispose it before creating another one of the same flavor."). Verified on device (emulator log below). Different flavors can coexist. An engine that exits on its own releases its slot.
- **Hot reload**: two isolates per engine; dispose before reload (README "Quit / Hot reload").
- **stdout = exactly one line per event.** Reader splits native chunks on `\n` (`stockfish.dart:842-868`) and delivers each line separately via `onStdout`/`stdout`; no `\n` or `\r` inside a line (verified: 0 of 29 lines contained one). Lines arrive in batches internally, but each is a separate stream event. Because the stream is broadcast, a listener attached after `create()` misses the banner/`uciok`; use `onStdout` for the whole life (as lichess mobile does, `mobile/lib/src/model/engine/engine_transport.dart:77-83`).
- Options (verified from the engine's `option name` lines on device): `Threads` default 1 min 1 **max 1024**, `Hash` default 16 min 1 **max 2048** on the tested x86_64 build (`MaxHashMB = Is64Bit ? 33554432 : 2048`; `-DIS_64BIT` is only set for arm64-v8a in the CMakeLists, so 32-bit-style limits apply on other ABIs), `MultiPV` 1..256, `UCI_Chess960` default false. `MaxThreads = max(1024, 4*hw_concurrency)` (`StockfishLight/src/engine.cpp:51`). Real limit is device memory/cores: lichess mobile caps threads at `Platform.numberOfProcessors - 1` (`mobile/lib/src/model/engine/engine_utils.dart:12`) and Hash at 256 MB per engine (`engine_budget.dart:11`, min 16). Send `Threads` **before** `Hash` (changing Threads reallocates the table at the current Hash, `engine.dart:455-460`).
- **Threads works**: `setoption Threads 4` + `Hash 64` + `MultiPV 2`, `go depth 12` on the API 36 x86_64 emulator (4 cores) returned depth-12 lines for both multipv in 1.3 s (`nps 188331`), `bestmove g8f6 ponder f1e1`. Per-line stdout verified.
- **Illegal move in `position ... moves`**: with `UCI_Chess960=false`, `moves ... e1h1` is silently dropped on host Stockfish 19 (`d` printed no `Fen:`), and in the plugin the following `isready` never returned `readyok` within 60 s (engine stalled; probe self-test log stopped there). Never send a move that is not legal in the current notation; always use `UCI_Chess960=true` and king-to-rook castling (section 1.1) and keep the `isready` timeout + recreate rule (trap 5).

#### 3.2 Native build

- Built by Gradle/AGP CMake, no prebuilt binaries: each of the three plugins has `android/CMakeLists.txt` compiling vendored Stockfish C++ (`multistockfish_light/android/CMakeLists.txt`, sources under `ios/multistockfish_light/Sources/...`), `-O3`, arm64 gets `-DUSE_NEON=8 -DIS_64BIT -DUSE_POPCNT`, 16 KB page size link flag (`-Wl,-z,max-page-size=16384`, OK for Android 15/16).
- ABIs: `abiFilters 'arm64-v8a', 'armeabi-v7a', 'x86_64'` (`android/build.gradle:55`). Release APK per ABI contains `libmultistockfish_light.so` (2.7 MB arm64), `libmultistockfish_chess.so` (1.6 MB), `libmultistockfish_variant.so` (1.8 MB). Unused chess/variant libs cost ~3.4 MB per ABI; untested option: `packaging { jniLibs { excludes += ["**/libmultistockfish_chess.so", "**/libmultistockfish_variant.so"] } }`.
- Plugin `minSdk = 21`, `compileSdk = 35`, plugin AGP classpath 8.7.3, `ndkVersion = android.ndkVersion`.
- **The light flavor's build does `file(DOWNLOAD https://tests.stockfishchess.org/api/nn/nn-61e7af4bb97d.nnue ...)` with a pinned SHA-256** (`CMakeLists.txt:56-57`) although the same net is vendored at `ios/multistockfish_light/Sources/multistockfish_light/nnue/nn-61e7af4bb97d.nnue` in the pub package. The first build needs network; for hermetic/F-Droid builds patch it (vendor `multistockfish_light` and replace with `file(COPY ...)`/`configure_file`). Not blocking.
- Required NDK: Flutter's default `28.2.13676358` (`packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt:42`). Only NDK 28.2.13676358 and CMake 3.22.1 ended up in `~/Android/Sdk` (Gradle auto-installed CMake 3.22.1 and platform android-35).

#### 3.3 Probe app and build results (PROVEN)

`~/development/scratch/m0/probe` (`flutter create --org my.umarh --platforms android`, minSdk 26) with chessground, dartchess, multistockfish, flutter_riverpod, sqlite3 (+ sqlite3_flutter_libs), flutter_secure_storage, http, receive_sharing_intent, file_picker, dynamic_color, crypto, material_ui, flutter_localizations/intl.

`flutter build apk --release --split-per-abi` succeeded (log `build3.log`: 38.6 MB arm64, 34.5 MB armeabi-v7a, 40.2 MB x86_64 with stock chessground; `build4.log`: 26.8 / 22.7 / 28.4 MB with the trimmed chessground). First cold build ~9 min plus automatic SDK component installs; warm builds 2-4.5 min. On-device run: x86_64 release APK on the API 36 emulator (`Small_Phone`) created the light engine, ran searches, StateError on second create, secure-storage and sqlite paths compiled (engine self-test only was exercised at runtime).

Toolchain actually used:

| Item | Value |
|---|---|
| Flutter / Dart | 3.47.9 / 3.13.7 (lichess mobile pins 3.47.8) |
| AGP / Gradle / Kotlin plugin | 9.1.0 / 9.3.1 / 2.4.0 (`android/settings.gradle.kts`, `gradle-wrapper.properties`) |
| `android.newDsl=false`, `android.builtInKotlin=false` | set by the 3.47 template in `gradle.properties` |
| compileSdk | template default 36 (`flutter.compileSdkVersion`), **must be 37** (see 3.4) |
| targetSdk / minSdk | 36 (template default; effective in APK) / 26 (set) |
| NDK / CMake | 28.2.13676358 / 3.22.1 |
| JDK used by Gradle | Android Studio JBR (Java 25 per `flutter doctor`); sources target Java 17 |
| ABIs | arm64-v8a, armeabi-v7a, x86_64 |
| `extractNativeLibs` | false (libs stored uncompressed, page-aligned) |

#### 3.4 Conflicts and required fixes found by the build

1. **`receive_sharing_intent 1.9.0` requires compileSdk 37** (`android/build.gradle: compileSdk 37`); first build failed in `:app:checkReleaseAarMetadata`: "requires ... compile against version 37 or later ... maximum recommended compile SDK version for AGP 9.1.0 is 36". Fix that worked: `compileSdk = 37` in `app/build.gradle.kts` + `android.suppressUnsupportedCompileSdk=37` in `gradle.properties` (platform `android-37.0` is installed). This ties the app to an unsupported-by-AGP compileSdk (see section 5 recommendation).
2. No dartchess/chessground version conflict: chessground 11.0.0 and the lichess stack all use dartchess 0.14.0.
3. `flutter_riverpod 3.4.3` resolved (3.x line; `riverpod 3.4.3`, `state_notifier 1.0.0` transitive); is a major version above what the spec era assumed; only compile-checked (`ProviderScope`) in the probe, so check the 3.x provider API when writing M1.
4. No firebase_/Play Services: `pubspec.lock` has no `firebase_`/`google_mobile_ads`; release `dex packages` contains no `gms`/`firebase` classes; Gradle `releaseRuntimeClasspath` has no `com.google.android.gms`/`com.google.firebase`. Non-AndroidX third-party Android deps: `com.google.android.material:material:1.7.0` (from dynamic_color, Apache-2.0, not Play Services), `com.google.crypto.tink:tink-android:1.23.0` + `gson` (flutter_secure_storage), `com.getkeepsafe.relinker` (android_file_picker).

#### 3.5 Resolved versions (probe `pubspec.lock`)

| Package | Version | Licence |
|---|---|---|
| chessground | 11.0.0 | GPL-3.0 |
| dartchess | 0.14.0 | GPL-3.0 |
| multistockfish / _light / _chess / _variant | 0.6.1 / 0.1.0 / 0.6.0 / 0.4.0 | GPL-3.0 (Stockfish GPL-3.0) |
| flutter_riverpod / riverpod | 3.4.3 / 3.4.3 | MIT |
| sqlite3 | 3.8.0 (SQLite 3.54.1 downloaded; system 3.54.0) | MIT (SQLite public domain) |
| sqlite3_flutter_libs | 0.6.0+eol (empty shim; drop) | MIT |
| flutter_secure_storage | 11.2.0 (+ _platform_interface 2.1.1, _linux 3.0.3, _darwin 0.4.3, _web 2.1.1, _windows 4.2.2) | BSD-3-Clause |
| http | 1.6.0 | BSD-3-Clause |
| receive_sharing_intent | 1.9.0 | Apache-2.0 |
| file_picker | 13.3.2 (+ android_file_picker 2.1.3, file_picker_darwin 2.4.2, jni 1.1.2, jni_flutter 1.0.4+1) | MIT (jni: BSD-3) |
| dynamic_color | 2.1.0 | Apache-2.0 |
| crypto | 3.0.8 | BSD-3-Clause |
| material_ui / cupertino_ui | 1.10.0 / 1.1.6 | BSD-3-Clause (Flutter authors) |
| intl / flutter_localizations | 0.20.3 / sdk | BSD-3 |
| Build-hook helpers (transitive): hooks 2.2.0, code_assets 2.1.0, native_toolchain_c 0.19.5 | | BSD-3 |

All licences read from each package's `LICENSE` in `~/.pub-cache`. All are GPL-3.0-compatible (Apache-2.0, MIT, BSD-3 into GPL-3).

#### 3.6 Merged manifest permissions (release APK, `apkanalyzer manifest permissions`)

Identical for all three ABIs, with `INTERNET` declared in the main manifest:

```
android.permission.INTERNET
my.umarh.probe.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION   (<applicationId>.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION)
```

- No plugin injects any other `uses-permission` (no `ACCESS_NETWORK_STATE`, storage or media). `file_picker` (android_file_picker) injects only `<queries>` entries (`GET_CONTENT`, `OPEN_DOCUMENT`, `OPEN_DOCUMENT_TREE`, `CREATE_DOCUMENT`), which are not permissions.
- **[SPEC≠UPSTREAM] "exactly INTERNET" is not achievable without a workaround**: `androidx.core` adds a signature-level `<permission>` plus matching `<uses-permission>` named `${applicationId}.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (protectionLevel signature, used by `ContextCompat.registerReceiver` for non-exported receivers on API < 33). Recommended: allowlist it in `tool/check_permissions.sh` (match `^${APPLICATION_ID}\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION$`) and record it in DECISIONS.md. If the spec's letter must be met, remove it with `tools:node="remove"` on both the `<permission>` and `<uses-permission>` of that name, but that makes `ContextCompat` non-exported receivers unreachable on old APIs (untested), so the allowlist is safer.
- `tools:node="remove"` entries needed otherwise: **none**.

#### 3.7 Network access needed at build time

`sqlite3` (hooks download `libsqlite3.<abi>.so` from GitHub releases, SHA-256 verified; cache `.dart_tool/hooks_runner/shared/sqlite3`) and `multistockfish_light` (NNUE download). Gradle/Maven, pub, and SDK component installs as usual. For offline/F-Droid see `sqlite3` `source: source|system` user-defines (section 8) and the CMake patch above.

#### 3.8 Fallback

None needed: `multistockfish` builds and runs. `stockfish_flutter_plus` fallback not exercised.

#### 3.9 Asset trimming result

Trimmed chessground (path dep, cburnett + non-horsey boards): APK contents went from 1917 piece-set files / 24 boards to 48 / 21, arm64 APK 38.6 MB -> 26.8 MB. Vendoring works with no Dart changes.

---

### 4. Flutter 3.47 Material / Cupertino split

- Flutter 3.47.9 still ships `package:flutter/material.dart` and `package:flutter/cupertino.dart` in the framework (files under `packages/flutter/lib/src/material`), **and** the standalone `material_ui 1.10.0` / `cupertino_ui 1.1.6` packages (`environment: sdk ^3.13.0, flutter >=3.47.0`). The `material_ui` README says the package was "previously built directly into the core Flutter framework as `package:flutter/material.dart`", provides `dart fix --apply --code=migrate_design_widgets`, and `MaterialUiCompatibilityBridge` for legacy subtrees. The framework has a data-driven fix (`packages/flutter/lib/fix_data/fix_material/fix_material.yaml`, "Migrate from flutter/material.dart to material_ui/material_ui.dart").
- **Use `import 'package:material_ui/material_ui.dart';`** (re-exports `package:flutter/widgets.dart`; `material_ui.dart:20`). Reasons: lichess mobile itself does (`mobile/lib/src/view/engine/engine_gauge.dart:9`, `mobile/pubspec.yaml: material_ui ^1.0.1, cupertino_ui ^1.0.0`), and `dynamic_color 2.1.0` depends on `material_ui ^1.0.0` and returns **its** `ColorScheme`. Verified: `DynamicColorBuilder` + `package:flutter/material.dart` fails to compile (`argument_type_not_assignable`: `MaterialApp Function(ColorScheme?,ColorScheme?)` vs `Widget Function(...)`, two distinct `ColorScheme` classes). Do not mix the two imports in one app.
- Add `material_ui: ^1.10.0` as a direct dependency (it is only transitive via dynamic_color; chessground has it as a dev dependency). `cupertino_ui` comes transitively; not imported directly.
- Theming APIs compiled in the probe with `material_ui` (no deprecations reported by `flutter analyze`): `ThemeData(useMaterial3: true, colorScheme:, extensions: [...])`, `ColorScheme.fromSeed(seedColor:, brightness:)`, `DynamicColorBuilder(builder: (ColorScheme? light, ColorScheme? dark) => ...)`, `ColorScheme.harmonized()` (dynamic_color extension), `ThemeExtension<T>` with `copyWith`/`lerp`, `Theme.of(context).extension<T>()`, `ColorScheme.surfaceContainer`. `Color.withValues(alpha:)` is the non-deprecated alpha API (used by chessground).
- Localisations: `GlobalMaterialLocalizations.delegates` must come from `material_ui` (README step 2). **gen-l10n's generated `AppLocalizations.localizationsDelegates` references `flutter_localizations`' `GlobalMaterialLocalizations`/`GlobalCupertinoLocalizations` (generated file imports `package:flutter_localizations/flutter_localizations.dart`), i.e. the legacy classes.** Use `localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates]` (material_ui) instead. Probe compiled and ran this way.
- gen-l10n example (compiled): `pubspec.yaml: flutter: generate: true`, deps `flutter_localizations: {sdk: flutter}`, `intl: any`; `l10n.yaml`:

```yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
output-dir: lib/l10n
nullable-getter: false
```
  (`output-dir` is needed to get a real `lib/l10n/` import; `nullable-getter: false` makes `AppLocalizations.of(context)` non-null.) `app_en.arb` with a plural message (`{count, plural, =0{...} =1{...} other{...}}`) generated fine.

---

### 5. Android manifest, network security, sharing

Verified by building the release APK (copy the files from `~/development/scratch/m0/probe/android/app/src/main/AndroidManifest.xml` and `res/xml/{network_security_config,data_extraction_rules,backup_rules}.xml`).

`AndroidManifest.xml` application attributes: `android:allowBackup="false"`, `android:fullBackupContent="@xml/backup_rules"`, `android:dataExtractionRules="@xml/data_extraction_rules"`, `android:networkSecurityConfig="@xml/network_security_config"`, plus `<uses-permission android:name="android.permission.INTERNET"/>` in `src/main` (the template only has it in debug/profile).

`res/xml/network_security_config.xml`:
```xml
<network-security-config>
    <base-config cleartextTrafficPermitted="true">
        <trust-anchors><certificates src="system" /></trust-anchors>
    </base-config>
</network-security-config>
```
(Applies on API 24+; makes `usesCleartextTraffic` unnecessary. `BaseUrlPolicy` is the gate.)

`res/xml/data_extraction_rules.xml` (API 31+): `<data-extraction-rules>` with `<cloud-backup>` and `<device-transfer>`, each excluding `domain` = `root`, `file`, `database`, `sharedpref`, `external` with `path="."`. `res/xml/backup_rules.xml` (API 23-30, `<full-backup-content>`) excludes the same domains. With `allowBackup=false` both are belt-and-braces; the AAPT build accepted them.

Intent filters on `MainActivity` (all `DEFAULT` category; VIEW also `BROWSABLE`), built and present in the merged APK manifest:
1. `SEND` `text/plain` (app share text).
2. `SEND` `application/x-chess-pgn`, `application/vnd.chess-pgn`, `text/x-chess-pgn`.
3. `VIEW` schemes `content` + `file` with those three PGN mime types.
4. `VIEW` schemes `content` + `file`, `mimeType */*`, `host *`, `pathPattern` `.*\\.pgn`, `.*\\..*\\.pgn`, `.*\\..*\\..*\\.pgn` (needed because Files apps usually report `application/octet-stream` or `text/plain`; `pathPattern` works on all APIs, lichess uses `pathSuffix` which is API 31+ only: `mobile/android/app/src/main/AndroidManifest.xml:44-58`, which also uses `fullBackupContent` and no `allowBackup=false`).
Keep `<queries>` PROCESS_TEXT entry from the template. Do not add storage permissions: content URIs grant read access.

#### receive_sharing_intent 1.9.0 (Apache-2.0, published 2026-06-24)

Read source: `android/src/main/kotlin/com/kasem/receive_sharing_intent/ReceiveSharingIntentPlugin.kt:82-146`, `FileDirectory.kt:85-130`.
- Shared **text** (`ACTION_SEND`, `text/plain`) arrives: `path = EXTRA_TEXT`, `type = text` (`toJsonObject`, `:136-148`). Works.
- `VIEW` content URI: only handled as a file when `intent.type != null`; otherwise it is reported as type `url` with the raw `content://` string, which Dart cannot read. When handled, the plugin **copies the whole stream into `cacheDir/<DISPLAY_NAME>`** with no size cap (`FileDirectory.getDataColumn`, `:108-124`) and `File(cacheDir, fileName)` uses the provider-supplied name unsanitised (path traversal via `../` names, name collisions). Conflicts with the spec's 2 MB cap and DoS rules.
- Build compatibility: compiles with AGP 9.1/Gradle 9.3.1/Kotlin 2.4.0 but forces **compileSdk 37** (3.4 item 1), above AGP 9.1's recommended max of 36.
- **Recommendation: use the Kotlin `MethodChannel`/`EventChannel` fallback**, not the plugin. Reference implementation (GPL-3.0, lichess mobile): `mobile/android/app/src/main/kotlin/org/lichess/mobileV2/MainActivity.kt` (reads `ACTION_VIEW` `intent.data` and `ACTION_SEND` `EXTRA_STREAM` with `contentResolver.openInputStream`, serves `getInitialPgn` via MethodChannel and live shares via EventChannel; `onNewIntent` forwards) and Dart side `mobile/lib/src/service/shared_pgn_service.dart`. Glyph should additionally (a) handle `EXTRA_TEXT` for text shares, (b) read at most 2 MB + 1 bytes, (c) UTF-8 decode, (d) never write to disk. This removes the compileSdk 37 requirement and the plugin dependency.

---

### 6. Markdown renderer options (pub.dev, queried 2026-11-04)

| Package | Latest (published) | Licence | Status |
|---|---|---|---|
| flutter_markdown | 0.7.7+1 (2025-05-06) | BSD-3 | **discontinued**, replaced by flutter_markdown_plus |
| flutter_markdown_plus | 1.0.12 (2026-07-10) | BSD-3 | maintained, deps `markdown ^7.3.1`, flutter >=3.27.1 |
| gpt_markdown | 1.4.0 (2026-10-21) | BSD-3 | maintained but pulls `material_ui`, `flutter_svg`, `http`, LaTeX/highlight packages (heavy) |
| markdown_widget | 2.3.2+8 (2025-04-26) | MIT | stale; pulls `url_launcher`, `scroll_to_index` |
| markdown (parser only) | 7.3.1 (2026-03-18) | BSD-3 | maintained (dart-lang) |

**Recommendation: render plain text with simple `**bold**` handling** (a ~30-line `TextSpan` builder in `glyph_core`/app). It adds no dependency, no link or image handling (spec section 6 "links disabled"), and no mixed `flutter/material` vs `material_ui` risk. Fallback if rich text is wanted later: `flutter_markdown_plus ^1.0.12` with `onTapLink: null`, `imageBuilder` returning `SizedBox.shrink()` and `selectable: false`. Not compiled in the probe.

---

### 7. flutter_secure_storage 11.2.0 default behaviour

- Default `const FlutterSecureStorage()` uses `AndroidOptions()` (`lib/options/android_options.dart:50-76`): key wrapping RSA/ECB/OAEPWithSHA-256AndMGF1Padding, data AES/GCM/NoPadding, no biometrics, `resetOnError = true`, `migrateOnAlgorithmChange = true`. Data lives in the app's `SharedPreferences` file `FlutterSecureStorage` (`FlutterSecureStorageConfig.java:16 DEFAULT_PREF_NAME`), wrapped key also in prefs, RSA key in AndroidKeyStore.
- **minSdk 24** (`android/build.gradle: minSdk = 24`), compileSdk `flutter.compileSdkVersion`; 11.0.0 changelog: raised minSdk to 24. Compatible with Glyph's 26. Pulls `tink-android 1.23.0` + `gson`.
- Backup: README "Disabling Auto Backup" says restored backups cause `InvalidKeyException: Failed to unwrap key` because the AndroidKeyStore key is not restored; remedy is `allowBackup="false"` (+ exclude the prefs). With `allowBackup=false` and the empty extraction rules, nothing is backed up or transferred, so the wrapped key and ciphertext never separate. Confirmed in the merged manifest (`android:allowBackup="false"`).
- `resetOnError = true` means on key/cipher failure (e.g. after OS keystore wipe) **all stored values are silently deleted** (`FlutterSecureStorage.java:1044-1067`). Glyph must treat a missing key as "no key configured" and prompt, never crash. Do not rely on the key surviving a factory reset/new device.
- `AndroidOptions.biometric()` requires API 28+; not used.
- No extra permissions injected (plugin manifest is empty).

---

### 8. sqlite3 on host Dart (`dart test`)

- `sqlite3 3.8.0` has **no `sqlite3_flutter_libs` need**. It uses Dart build hooks (`hook/build.dart`). Default `source: sqlite3` **downloads** a precompiled library from the package's GitHub release (SHA-256 checked against `asset_hashes.dart`) into `.dart_tool/hooks_runner/shared/sqlite3/build/`. `doc/hook.md` documents the options.
- Tested in `~/development/scratch/m0/core_probe` (Arch Linux; system `/usr/lib/libsqlite3.so.3.54.0` present; `gcc`/`clang` present): `dart test` with **no config works** (downloaded SQLite 3.54.1, ~24 s first run). Same test with
```yaml
hooks:
  user_defines:
    sqlite3:
      source:
        linux: system
        default: sqlite3
```
  in the **workspace-root** `pubspec.yaml` used the system 3.54.0 offline (works). The per-OS map syntax is supported (changelog 3.6.0 / 3.7.0) and keeps downloads for Android. Note: user-defines are read from the workspace root only.
- For `glyph_core` as a pure-Dart package: `dev_dependencies: test`, dependency `sqlite3: ^3.8.0`, `dart test` runs hooks automatically (prints "Running build hooks..."). Enable `PRAGMA foreign_keys=ON` per connection (`db.execute`). Close with `db.close()` (`dispose()` is deprecated).
- CI: needs network on first run (or the `system` define). Android build uses the downloaded `libsqlite3.so` (1.7 MB per ABI in the APK).
- Fallback `sqflite`+`sqflite_common_ffi` not needed.

## Part C: project-level decisions (orchestrator)
- Toolchain: Flutter 3.47.9 at ~/development/flutter (`source ~/development/glyph-env.sh`), Stockfish 19 desktop at $STOCKFISH_PATH.
- Use chessground 11.0.0 + dartchess 0.14.0 (as resolved in M0), material_ui import, drop sqlite3_flutter_libs.
- Replace receive_sharing_intent with a Kotlin MethodChannel (M7). Vendor a trimmed set of free-licensed piece sets/boards (M5).
- Always set UCI_Chess960=true when talking to the engine (dartchess castling is king-to-rook); convert via dartchess Move objects.
- Existing Android Studio template project was replaced by the Flutter app (backup kept outside the repo).

## M1 decisions
- Dart pub workspace at the repo root; single `pubspec.lock` there (the banned-deps check scans every `pubspec.lock`). `flutter pub get` anywhere in the repo resolves the whole workspace.
- Workspace constraint: `flutter_test` pins `test_api 0.7.12`, so `glyph_core` uses `test: ^1.25.0` (resolves to 1.31.1). Raise when Flutter's pin moves.
- Routing: plain `Navigator` with named routes (`app/lib/routes.dart`), no routing package. Import and Explain are modal bottom sheets.
- `check_permissions.sh` allowlist: `android.permission.INTERNET` plus the regex `^my\.umarh\.glyph\.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION$` (androidx.core, signature-level; M0 section 3.6). Anything else fails the check.
- Release signing reads `android/key.properties` (keys `storeFile`, `storePassword`, `keyAlias`, `keyPassword`) or env `GLYPH_KEYSTORE_FILE`, `GLYPH_KEYSTORE_PASSWORD`, `GLYPH_KEY_ALIAS`, `GLYPH_KEY_PASSWORD`; without them the debug key signs (so CI builds pass; such APKs are not for distribution).
- Badge colours are hand-tuned fixed palettes (not harmonized with the dynamic scheme) so the 4.5:1 glyph contrast stays guaranteed.

## M2 decisions
- **Own PGN pre-splitter** (`glyph_core/src/pgn/pgn_splitter.dart`) instead of dartchess's regex splitter: a tag line after movetext, or a move number after a result token, starts a new game, so games without blank lines are not merged and a blank line plus `[` inside a `{}` comment is not a boundary. It tracks `{}` (with nesting), `;`, `%` lines and `( )`. Result tokens inside variations or comments never end a game. Text before the first game that is not movetext (share-text preambles such as "Check out my game ...") is dropped.
- **Nested braces**: dartchess cannot parse them, so inner `{ }` are rewritten to `( )`; if the outer comment is never closed the first `}` closes it (and nesting is turned off for the rest of the input, which keeps the scan linear). Adjacent comments on one move are merged and the merged comment is capped at 4 KB (UTF-8 safe); merging is also needed because dartchess is quadratic in the number of comments per move (150k tiny comments took 59 s).
- **Result type**: `PgnOk` (every game valid), `PgnPartial` (some games skipped, each with a `PgnIssue`; also used for "more than 500 games", kind `tooManyGames`), `PgnFailed` (no game usable; all issues kept, first one is shown). Game index is 1-based for display; `Game.sourceIndex` is 0-based. 0-move games are skipped with `noMoves`. A `FEN` tag is honoured unless `SetUp "0"`. Variant detection: Chess960 names (`chess960`, `chess 960`, `fischerandom`, ...) by ourselves, everything else through `Rule.fromPgn`; anything but `Rule.chess` or unknown is rejected with "<Variant> games aren't supported.".
- **Core stays localisation-free**: `PgnIssue` carries kind + fields (and an English `message` for tests/logs); the app maps them to `app_en.arb` strings (`pgn_issue_text.dart`). Illegal-move copy is "Game {game}, move {move} ({san}): illegal move." with `14` for White and `14...` for Black, numbering from the FEN's fullmove counter.
- **Size caps**: 2 MB is measured in UTF-8 bytes (`parsePgn` for strings, `parsePgnBytes` for bytes before decoding). The file picker service reads at most 2 MB + 1 byte and reports `tooLarge` without loading the rest. Parsing runs through `Isolate.run` above 100 KB in `parsePgnAsync` / `parsePgnBytesAsync`; the openings asset decodes with `OpeningBook.parseTsvAsync`.
- **Stored PGN** (`games.pgn`) is the sanitised, normalised single-game text produced by the splitter (tags verbatim, movetext re-spaced on one line, `;`/`%` lines and junk dropped, variations kept). It always re-parses to the same game.
- **Ply.san is canonical** (`Position.makeSan`), `Ply.uci` is dartchess's form (castling king-takes-rook). Comments: `%clk` -> `clockMs`, `%eval` -> White-POV `PlyEval` (pawns x 100 rounded, or mate), the rest is `comment` text.
- **Annotated export** emits original headers in file order, adds `Annotator "Glyph"` (replacing an existing value) and a `Result` tag if missing. It does not copy the original free-text comments or NAGs (the stored original PGN keeps them); `%eval` / `%clk` come from the supplied maps, falling back to what was imported. Miss writes `$2 { Miss }`.
- **Openings asset**: `tool/build_openings.dart` (root script; the root workspace pubspec depends on `glyph_core` and `crypto`) replays `a..e.tsv` from chess-openings (3fd6ce9) with dartchess into `app/assets/openings.tsv` (`epd\teco\tname`, 3865 rows, 0 duplicate EPDs, 15 with a legal ep square) and writes `openings.tsv.sha256` in `sha256sum` format. `openings_test.dart` checks the hash, the row/EPD invariants and, when the checkout exists, that the tool reproduces the recorded hash. `OpeningBook`: Book = contiguous prefix of plies whose resulting EPD is listed; the opening name is the deepest listed position anywhere in the game; games with a custom start or Chess960 get neither.
- **SQLite**: one `Db` wrapper (`user_version` migrations are a list; a failing migration rolls back; a database newer than the app is refused). Repositories are async interfaces; `save` dedupes inside a transaction on (source, source_id) when `source_id` is non-null; pasted/file/share games keep `source_id` NULL, so importing the same text twice makes two rows. The DB lives in `getApplicationSupportDirectory()/glyph.db` (`path_provider`, adds no permissions).
- **Library delete**: a swipe hides the card at once; the row is deleted when the 5 s Undo SnackBar closes (or when the provider is disposed). `SnackBar(persist: false)` is required because a SnackBar with an action otherwise never times out.
- **gen-l10n**: `use-escaping` is off by default, so ARB strings use plain apostrophes (`''` would be shown literally).
- **Riverpod 3**: `Ref.read` is forbidden inside `onDispose`; capture dependencies in `build`.
- **Tests**: widget tests override the repositories, the file picker (`FakeFilePicker`), the opening book and the clock; sqlite3 loads under `flutter test` on the host through the system library (workspace-root `hooks.user_defines`).

