# M0 algorithms research (upstream wins over spec)

Upstream snapshots (shallow clones in ~/development/upstream): lila 9e780e9 (2026-11-04), scalachess b73baa5, scalalib 31fc151, api bbd21a7, chess-openings 3fd6ce9. Note: `WinPercent` is NOT in lila; it lives in **scalachess**.

## 1. Win% and accuracy

### 1.1 WinPercent (scalachess `core/src/main/scala/eval.scala`)
- L57 `Cp.CEILING = 1000`; L66-69 `ceiled` clamps cp to [-1000, 1000].
- L107-110 `winningChances(cp) = 2/(1+exp(-0.00368208*cp)) - 1`, clamped [-1,1]. L101-102 `fromCentiPawns(cp) = 50 + 50*winningChances(cp.ceiled)`.
- L95-98 `fromScore`: cp -> fromCentiPawns; **mate N>0 -> fromCentiPawns(+1000); mate N<=0 (incl. Mate(0)=mated) -> fromCentiPawns(-1000); MateGiven -> +1000.** Mate distance is ignored. win(1000)=97.54474363414323, win(-1000)=2.4552563658567763.
- Client `ui/lib/src/ceval/winningChances.ts` (path moved from ui/ceval): L11 MULTIPLIER -0.00368208, L16 clamp +-1000, L18-22 `mate -> cp=(21-min(10,|mate|))*100`, signed. Gives 99.94% for M1, 98.29% for M10+. **Used only for the live client gauge, NOT by the server accuracy.**
- Discrepancy vs spec: spec said "mate N mapped to large cp shrinking with N". True only for the TS client. For accuracy parity (and I recommend Glyph's eval bar too, for consistency with lichess accuracy) use the server rule: all mates = +-1000 cp. Decision for Glyph: use server rule everywhere (single function), keep the TS formula only if a "mate-distance" gauge is wanted.

### 1.2 Per-move accuracy (lila `modules/analyse/src/main/AccuracyPercent.scala` L47-54)
```
accMove(before, after):            // Win% from the MOVER's POV, 0..100
  if after >= before: return 100
  d = before - after
  raw = 103.1668100711649 * exp(-0.04354415386753951 * d) - 3.166924740191411
  return clamp(raw + 1, 0, 100)    // +1 "uncertainty bonus"
```
(L56-74 `fromEvalsAndPov` applies this per player move for insights; it is NOT what the API/game accuracy uses.)

### 1.3 Game accuracy (L79-113 `gameAccuracy`; used by API GameApiV2.scala L324-327 and JsonView.scala L68)
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

### 1.4 Verification
Python port of the above run against 210 real server-analysed games (DrNykterstein, penguingim1, Fins; 147 resign, 23+2 mate (standard+960), 19+2 timeout, 11 draw, 1 stalemate, 10 chess960; 76 with mate evals), initial=15: **all 420 per-player accuracies match lichess's integer within 0.4997 (i.e. identical after rounding).** So +-1 tolerance in the spec is more than enough; use +-0.5 pre-rounding or exact int equality.

### 1.5 Hand-checked examples (win_cp(cp)=50+50*(2/(1+e^(-0.00368208*cp))-1))
- win(0)=50, win(15)=51.380429, win(100)=59.102590, win(-300)=24.887450, win(500)=86.307166, win(+-1000/1500/mate)=97.544744/2.455256.
- accMove(60,50) d=10: 103.16681*e^-0.4354415=66.58-3.167+1 = 64.5798. accMove(51,50)=96.604 (d=1). d=50 -> 9.5278; d>=~73 -> 0.
- Game, white starts, cps [15,-50,15,-40,10] (n=5, ws=2): wp=[51.3804,45.4104,51.3804,46.3246,50.9204]; pair accs W 77.383, B 77.383, W 80.614, B 82.289; windows size 2 so sd=|diff|/2 -> weights 2.985,2.985,2.528,2.298. White: weighted=(77.383*2.985+80.614*2.528)/5.513=78.86; harmonic=2/(1/77.383+1/80.614)=78.96; result **78.91**. Black **79.64**. -> displays 79 / 80.
- cps [15,-900,-900] white start: wp=[51.38,3.51,3.51]; white acc=10.659 (d=47.87), single weight (sd 23.9 clamped 12) -> white 10.66 (test says 10+-5); black pair has after>=before -> 100.
- Real: lichess game Lk80KJQh (docs/m0/lichess_sample.ndjson) white 93 / black 55; PXXPWDlC (chess960) 86 / 78 -- reproduced.
- Test file lila `modules/analyse/src/test/AccuracyPercentTest.scala` (uses tolerance windows, e.g. 50x(-50,15) -> 76+-8) can be ported as extra unit tests.

## 2. chess-openings
- Layout: `a.tsv..e.tsv` (ECO volumes), header `eco\tname\tpgn`; 3865 data rows, 3177 distinct names, 3332 distinct (eco,name). `bin/gen.py` (needs python-chess), `Makefile` -> `dist/{all,a..e}.tsv`; **dist/ is gitignored (not in repo)**; CI artifacts or Parquet mirror (hf.co/datasets/Lichess/chess-openings) only. Dist columns: `eco name pgn uci epd` (gen.py L126).
- pgn column: clean SAN with move numbers (`1. g3 Nc6`), max 36 plies, avg 9.8. Many entries intentionally share a name (transpositions). gen.py errors on duplicate EPD, so **EPD is unique per row** (verified: 0 dups).
- EPD convention: `board.epd()` = first 4 FEN fields; en passant square only when an ep capture is legal (README table). Verified by replaying all rows with dartchess 0.14 (`Position.fen` uses `_legalEpSquare()`, position.dart L128-137; take first 4 fields): 15 rows carry an ep square (e.g. `... w KQkq f6`), no duplicates. So no python needed: build tool = replay pgn with dartchess.
- Licence: CC0 (COPYING.txt); attribution not required, credit anyway.
- Recommended asset: `assets/openings.tsv`, lines `epd\teco\tname` (433 KB raw, ~61 KB deflated inside the APK; no extra gzip needed). Load into `Map<String,(String eco,String name)>` (~3865 entries). Lookup key = first 4 FEN fields of position after the move (dartchess `fen`). Optional `uci` not needed. A binary hash table would be ~63 KB gz too -- not worth it.

## 3. Lichess games export (api `doc/specs/tags/games/api-games-user-username.yaml`, lila `app/controllers/Game.scala` L175-188)
Real request (verified, HTTP 200, `Accept: application/x-ndjson`): `GET /api/games/user/DrNykterstein?max=2&evals=true&accuracy=true&pgnInJson=true&clocks=true&opening=true&division=true&analysed=true&perfType=blitz,rapid,classical`
- Defaults (non-extended): `moves=true tags=true clocks=false evals=false opening=false division=false accuracy=false pgnInJson=false sort=dateDesc`. `accuracy` and `evals` independent; either triggers analysis lookup (`requiresAnalysis`, misc.scala L193). Games without analysis simply lack `analysis`/accuracy. `analysed=true` filters to analysed games.
- Top-level keys seen: id, rated, variant, speed, perf, createdAt, lastMoveAt (ms), status, source, players, [initialFen], [winner], [opening{eco,name,ply}], moves (space SAN string), clocks (centiseconds, one per ply, needs clocks=true), pgn (pgnInJson), analysis[], [arenaTour], clock{initial,increment,totalTime}, division{middle,end}. `opening` absent for chess960 and when unknown. `initialFen` present for non-standard start (chess960 seen with it).
- Per player: `players.white.analysis = {inaccuracy, mistake, blunder, acpl, accuracy (INT, rounded), phases{opening,middlegame,endgame}}`; also `user{name,id,title?,...}`, `rating`, `ratingDiff`, `provisional`. `accuracy` only with `accuracy=true`.
- `analysis[]` (evals=true): one entry per ply AFTER the move, white POV: `{eval:<cp int>}` or `{mate:<int>}`; optional `best` (UCI), `variation` (SAN), `judgment{name,comment}` (only Inaccuracy/Mistake/Blunder). Length = plies, or plies-1 when game ended in checkmate. Initial eval is not included.
- PGN eval comments `[%eval 0.32]` / `[%eval #3]` (pawns, 2 dp), `[%clk h:mm:ss]`, `[Opening]`,`[ECO]`; chess960 pgn has `[Variant "Chess960"][FEN ..][SetUp "1"]`; castling written as `O-O`.
- perfType values: ultraBullet,bullet,blitz,rapid,classical,correspondence,chess960,crazyhouse,antichess,atomic,horde,kingOfTheHill,racingKings,threeCheck (comma separated). `variant` key lowercase (`standard`,`chess960`). Status values seen: resign, mate, outoftime, draw, stalemate.
- Throttle: spec says anonymous 20 games/s; lila Game.scala L67-71 uses 25 anonymous, 30 OAuth. No rate-limit headers observed; 429 -> wait 60 s. Content-Disposition attachment header present; `access-control-allow-origin: *`.
- Sample: docs/m0/lichess_sample.ndjson (2 games, usernames redacted to player_white/player_black, titles/flair removed).

## 4. Chess.com PubAPI (verified 2026-11-04, UA `Glyph-M0-research (https://github.com/umarh/glyph)`)
- `GET /pub/player/hikaru/games/archives` -> `{"archives":[".../games/2014/01", ... ".../games/2026/11"]}` ascending, 155 entries. Headers: `etag: W/"..."` (weak), `last-modified`, `cache-control: public, max-age=60` (archives) / `max-age=5` (month).
- Month `/games/2026/10`: 2.4 MB, 583 games. Conditional GET with `If-None-Match: <etag as sent, incl. W/>` -> **304**. Unknown user -> 404 `{"code":0,"message":"User \"x\" not found."}`.
- Game keys: url (`https://www.chess.com/game/live/<id>`), pgn (with `{[%clk 0:02:59.9]}` comments, tags incl. `[ECO]`, `[ECOUrl]`, `[Termination]`, `[CurrentPosition]`), time_control ("180", "60"), end_time (unix s), rated, accuracies{white,black} (FLOAT, 583/583 present for this user; treat as optional), tcn, uuid, initial_setup (FEN), fen (FINAL position), time_class (bullet/blitz seen; also rapid/daily), rules ("chess" for all; other values e.g. chess960 not observed here), white/black{rating,result,@id,username,uuid}, eco (**a URL, not an ECO code**; code is in the PGN tag), optional `tournament` URL.
- Result strings seen: win, resigned, timeout, checkmated, repetition, insufficient, agreed, timevsinsufficient, abandoned, stalemate.
- Sample: docs/m0/chesscom_sample.json (2 games).

## 5. Stockfish 19 UCI (desktop binary; net nn-1a298aa575a0.nnue is **109 MiB**, spec said ~94 MB)
- Handshake: `uci` -> `id name Stockfish 19`, options, `uciok`. Options of interest: Threads (1..1024), Hash (default 16), MultiPV (1..256), UCI_Chess960 (check), UCI_ShowWDL. `isready` -> `readyok`; `ucinewgame` + `isready` -> another `readyok`. `info string ...` lines (thread count, NNUE net) are emitted after the first isready/go.
- Info line exact format (MultiPV 2, one line per multipv per depth, multipv 1 first):
  `info depth 12 seldepth 21 multipv 1 score cp 20 nodes 41218 nps 368017 hashfull 13 tbhits 0 time 112 pv f3g5 d7d5 e4d5 ...` then `... multipv 2 score cp 17 ...`; ends `bestmove f3g5 ponder d7d5`. Mate: `score mate 1 ... pv d1d8` (positive = side to move mates). No `lowerbound/upperbound` or `currmove` appeared in these short runs; parser must still skip them.
- Terminal positions: checkmate or stalemate -> `info depth 0 score cp 0` + `bestmove (none)` (NOT `mate 0` in SF19); insufficient material (K vs K) still searches (cp 0 at depth 8; ponder lines). Threefold via `position startpos moves ...` 8 plies of knight shuffling: SF returned cp 29 and a normal move at depth 8 (draw by repetition only after the repeated position is reached; history still needed).
- Castling: standard mode emits `e1g1` / `ponder e8g8`; with `UCI_Chess960=true` it emits king-takes-rook `e1h1` / `e8h8`. Test FEN `r1bqk2r/pppp1ppp/2n2n2/2b1p3/2B1P3/3P1N2/PPP2PPP/RNBQK2R w KQkq - 0 5`, depth 14: std `bestmove e1g1 ponder e8g8`, 960 `bestmove e1h1 ponder e8h8`.
- Input is mode-strict: 960 mode + `moves e1g1` -> `info string CRITICAL ERROR: Command ... failed. Reason: Illegal move: e1g1`; standard mode + `e1h1` -> same error. The process stays alive but the position is not set -> must send moves in the notation matching UCI_Chess960 (or never send moves that SF rejects; listen for `CRITICAL ERROR`).

## 6. Spec discrepancies summary
1. Mate -> cp: server uses +-1000 flat (no distance); TS client uses (21-min(10,|m|))*100. Spec guess partly wrong.
2. Per-move formula has "+1" bonus and clamp [0,100]; return 100 if after>=before (spec omitted).
3. Game accuracy: `WinPercent` is in scalachess; window = clamp((plies)/10,2,8); weight sd clamp [0.5,12]; harmonic uses max(1,acc); initial eval 15 cp.
4. Lichess `accuracy` is an integer; chess.com `accuracies` are floats.
5. SF19 net 109 MiB; terminal positions give `cp 0` + `bestmove (none)` not `mate 0`.
6. Chess.com `eco` is a URL; anonymous lichess throttle is 25/s in code vs 20 in docs.
7. dist/ of chess-openings is not committed: Glyph's build tool must generate EPDs itself (feasible with dartchess).
