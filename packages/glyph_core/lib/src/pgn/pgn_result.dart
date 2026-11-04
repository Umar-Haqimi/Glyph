import '../game/game.dart';

/// Why a game, or a whole input, could not be imported.
enum PgnIssueKind {
  /// Input larger than `Limits.maxPgnBytes`.
  tooLarge,

  /// No game found in the input.
  noGames,

  /// A move is not legal in the replayed position (game + ply + SAN are set).
  illegalMove,

  /// Variant other than standard chess or Chess960 ([PgnIssue.variant] is set).
  unsupportedVariant,

  /// The `FEN` header could not be parsed.
  invalidFen,

  /// More than `Limits.maxPliesPerGame` plies.
  tooManyPlies,

  /// The game has no moves.
  noMoves,

  /// More than `Limits.maxGamesPerFile` games; the rest are not listed.
  tooManyGames,
}

/// One reason a game was skipped (or the whole input rejected).
class PgnIssue {
  const PgnIssue(
    this.kind, {
    this.gameIndex,
    this.ply,
    this.san,
    this.moveNumber,
    this.isBlackMove = false,
    this.variant,
  });

  final PgnIssueKind kind;

  /// 1-based index of the game in the input, as shown to the user.
  final int? gameIndex;

  /// 1-based ply of the offending move (illegalMove, tooManyPlies).
  final int? ply;

  final String? san;

  /// Full-move number of the offending move, honouring a FEN start.
  final int? moveNumber;
  final bool isBlackMove;

  /// Display name of the unsupported variant.
  final String? variant;

  /// English description. The app localises from [kind] and the fields.
  String get message {
    final g = gameIndex == null ? '' : 'Game $gameIndex, ';
    switch (kind) {
      case PgnIssueKind.tooLarge:
        return 'This file is larger than 2 MB.';
      case PgnIssueKind.noGames:
        return 'No game found.';
      case PgnIssueKind.illegalMove:
        final dots = isBlackMove ? '...' : '';
        return '${g}move $moveNumber$dots ($san): illegal move.';
      case PgnIssueKind.unsupportedVariant:
        return "$variant games aren't supported.";
      case PgnIssueKind.invalidFen:
        return '${g}the starting position (FEN) is invalid.';
      case PgnIssueKind.tooManyPlies:
        return '${g}more than 1000 moves.';
      case PgnIssueKind.noMoves:
        return '${g}no moves.';
      case PgnIssueKind.tooManyGames:
        return 'Only the first 500 games are listed.';
    }
  }

  @override
  String toString() => 'PgnIssue($message)';
}

/// Outcome of importing PGN text.
sealed class PgnParseResult {
  const PgnParseResult();

  /// Games that were imported (empty for [PgnFailed]).
  List<Game> get games;
}

/// Every game in the input is valid.
final class PgnOk extends PgnParseResult {
  const PgnOk(this.games);
  @override
  final List<Game> games;
}

/// Some games are valid, others were skipped ([skipped] says why).
final class PgnPartial extends PgnParseResult {
  const PgnPartial(this.games, this.skipped);
  @override
  final List<Game> games;
  final List<PgnIssue> skipped;
}

/// Nothing could be imported. [issues] holds every reason; [issue] is the first.
final class PgnFailed extends PgnParseResult {
  const PgnFailed(this.issues);
  final List<PgnIssue> issues;
  PgnIssue get issue => issues.first;
  @override
  List<Game> get games => const [];
}
