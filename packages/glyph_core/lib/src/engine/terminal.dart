import 'package:dartchess/dartchess.dart';

/// Why a position needs no engine.
enum TerminalKind { checkmate, stalemate, insufficientMaterial }

/// A position the game is already over in: it is computed here and **never
/// sent to the engine** (SPEC trap 4; Stockfish 19 answers `bestmove (none)`
/// for mate and stalemate and would still search a bare K v K).
///
/// ### Scoring rule
///
/// * [TerminalKind.checkmate]: decisive; the side that is **not** to move
///   (the side that just moved) won. [whiteWinPercent] reports the certain
///   result, 100 / 0. The classifier and accuracy (M4) instead score a
///   checkmate like a mate score, `WinPercent.mateWin` (97.54 / 2.46, the
///   scalachess ±1000 cp rule), so a mating move and a mate-in-1 line agree
///   and accuracy matches lichess (docs/DECISIONS.md, M4).
/// * [TerminalKind.stalemate] and [TerminalKind.insufficientMaterial]: draw,
///   Win% 50 (equivalent to cp 0).
///
/// Persistence: a terminal position is stored as one `position_lines` row
/// (rank 1) with `score_cp` and `score_mate` both NULL, depth 0 and an empty
/// `pv_uci` (SPEC 5.4: "both NULL for terminal"). To score it again, rebuild
/// the position from the FEN and call [detectTerminal]; [whiteWinPercent]
/// then gives the number.
class Terminal {
  const Terminal(this.kind, {this.winner});

  final TerminalKind kind;

  /// The side that delivered mate; null for draws.
  final Side? winner;

  bool get isDecisive => winner != null;

  /// Win% for White, 0..100: 100 / 0 for a decisive result, 50 for a draw.
  double get whiteWinPercent => switch (winner) {
        Side.white => 100,
        Side.black => 0,
        null => 50,
      };

  @override
  String toString() => 'Terminal($kind, winner: $winner)';
}

/// Returns the terminal state of [position] (checkmate, stalemate or
/// insufficient material), or null when the game goes on. Threefold repetition
/// and the 50-move rule are **not** terminal here: the engine sees them
/// through the move history (SPEC trap 9) and the classifier tracks them.
Terminal? detectTerminal(Position position) {
  if (position.isCheckmate) return Terminal(TerminalKind.checkmate, winner: position.turn.opposite);
  if (position.isStalemate) return const Terminal(TerminalKind.stalemate);
  if (position.isInsufficientMaterial) return const Terminal(TerminalKind.insufficientMaterial);
  return null;
}
