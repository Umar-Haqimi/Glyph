# Host engine benchmark (Stockfish 16, reference only)

Produced by `tool/bench_engine.dart` on 2026-11-04 in the cloud container (4 logical cores, partly shared with other work while it ran; Stockfish 16 from Ubuntu `/usr/games/stockfish`, **not** the on-device Stockfish 19 light net). Game: `packages/glyph_core/test/vectors/pgn/chesscom_download_clk.pgn`, 74 plies (75 positions), MultiPV 2, full move history, `UCI_Chess960 true`. The numbers rank settings against each other; they do not predict a phone. Device runs belong in `docs/HARDWARE_TEST.md` section A.

## Depth 12 (Fast preset)

| Depth | Threads | Hash MB | Game time (s) | ms / position | hashfull (last position, per mille) |
|---|---|---|---|---|---|
| 12 | 1 | 64 | 8.7 | 116 | 11 |
| 12 | 2 | 64 | 7.3 | 97 | 8 |
| 12 | 4 | 64 | 6.6 | 88 | 23 |

## Depth 16 (Normal preset)

| Depth | Threads | Hash MB | Game time (s) | ms / position | hashfull (last position, per mille) |
|---|---|---|---|---|---|
| 16 | 1 | 16 | 41.2 | 550 | 1 |
| 16 | 1 | 64 | 44.6 | 594 | 13 |
| 16 | 1 | 256 | 42.9 | 573 | 12 |
| 16 | 2 | 16 | 34.7 | 462 | 1 |
| 16 | 2 | 64 | 34.7 | 462 | 7 |
| 16 | 2 | 256 | 34.5 | 460 | 15 |
| 16 | 4 | 16 | 30.6 | 408 | 1 |
| 16 | 4 | 64 | 26.8 | 357 | 8 |
| 16 | 4 | 256 | 31.9 | 425 | 18 |
