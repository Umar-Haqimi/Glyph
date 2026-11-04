import 'package:glyph_core/glyph_core.dart';

// Defined in glyph_core (the pipeline writes it); re-exported for the app.
export 'package:glyph_core/glyph_core.dart' show AnalysisStatus;

/// Where a game came from. [name] is the value stored in `games.source`.
enum GameSource { paste, file, share, lichess, chesscom }

/// A game about to be saved (no id yet).
class NewGame {
  const NewGame({
    required this.source,
    this.sourceId,
    required this.pgn,
    this.white,
    this.black,
    this.whiteElo,
    this.blackElo,
    this.result,
    this.date,
    this.timeControl,
    this.event,
    this.variant = GameVariant.standard,
    this.startFen,
    this.eco,
    this.openingName,
    this.userSide,
    required this.plyCount,
    required this.importedAt,
  });

  /// Builds the row for [game]. The opening comes from [book] when it names
  /// one, else from the `ECO`/`Opening` headers.
  factory NewGame.fromGame(
    Game game, {
    required GameSource source,
    String? sourceId,
    required int importedAt,
    BookAnnotation? book,
    Side? userSide,
  }) {
    final opening = book?.opening;
    return NewGame(
      source: source,
      sourceId: sourceId,
      pgn: game.pgn,
      white: game.white,
      black: game.black,
      whiteElo: game.whiteElo,
      blackElo: game.blackElo,
      result: game.result,
      date: game.date,
      timeControl: game.timeControl,
      event: game.event,
      variant: game.variant,
      startFen: game.hasCustomStart ? game.startFen : null,
      eco: opening?.eco ?? game.eco,
      openingName: opening?.name ?? game.openingHeader,
      userSide: userSide,
      plyCount: game.plyCount,
      importedAt: importedAt,
    );
  }

  final GameSource source;
  final String? sourceId;
  final String pgn;
  final String? white;
  final String? black;
  final int? whiteElo;
  final int? blackElo;
  final String? result;
  final String? date;
  final String? timeControl;
  final String? event;
  final GameVariant variant;

  /// Null = standard start position.
  final String? startFen;
  final String? eco;
  final String? openingName;
  final Side? userSide;
  final int plyCount;

  /// Unix epoch milliseconds.
  final int importedAt;
}

/// A saved game plus a summary of its analysis, for the library list.
class GameRecord extends NewGame {
  const GameRecord({
    required this.id,
    required super.source,
    super.sourceId,
    required super.pgn,
    super.white,
    super.black,
    super.whiteElo,
    super.blackElo,
    super.result,
    super.date,
    super.timeControl,
    super.event,
    super.variant,
    super.startFen,
    super.eco,
    super.openingName,
    super.userSide,
    required super.plyCount,
    required super.importedAt,
    this.analysisStatus,
    this.completedPlies = 0,
    this.whiteAccuracy,
    this.blackAccuracy,
  });

  factory GameRecord.from(
    int id,
    NewGame g, {
    AnalysisStatus? analysisStatus,
    int completedPlies = 0,
    double? whiteAccuracy,
    double? blackAccuracy,
  }) =>
      GameRecord(
        id: id,
        source: g.source,
        sourceId: g.sourceId,
        pgn: g.pgn,
        white: g.white,
        black: g.black,
        whiteElo: g.whiteElo,
        blackElo: g.blackElo,
        result: g.result,
        date: g.date,
        timeControl: g.timeControl,
        event: g.event,
        variant: g.variant,
        startFen: g.startFen,
        eco: g.eco,
        openingName: g.openingName,
        userSide: g.userSide,
        plyCount: g.plyCount,
        importedAt: g.importedAt,
        analysisStatus: analysisStatus,
        completedPlies: completedPlies,
        whiteAccuracy: whiteAccuracy,
        blackAccuracy: blackAccuracy,
      );

  final int id;

  /// Null = never analysed.
  final AnalysisStatus? analysisStatus;

  /// `analyses.completed_plies`: the number of **positions** fully persisted,
  /// counting the start position as position 0. It runs from 0 to
  /// `plyCount + 1` (a game of N plies has N + 1 positions).
  final int completedPlies;
  final double? whiteAccuracy;
  final double? blackAccuracy;

  /// Positions to analyse: the start position plus one per ply.
  int get totalPositions => plyCount + 1;

  /// Share of positions analysed, 0..1. Exactly 1 only for a completed
  /// analysis; anything unfinished stays strictly below 1 (and below 0.99 in
  /// whole percent: callers floor), so "100%" never shows before the end.
  double get analysisProgress {
    if (analysisStatus == AnalysisStatus.completed) return 1;
    final ratio = (completedPlies / totalPositions).clamp(0.0, 1.0);
    return ratio >= 1 ? 0.99 : ratio;
  }

  /// [analysisProgress] in whole percent, floored (99 at most until done).
  int get analysisPercent => analysisStatus == AnalysisStatus.completed ? 100 : (analysisProgress * 100).floor().clamp(0, 99);

  GameRecord withUserSide(Side? side) => GameRecord(
        id: id,
        source: source,
        sourceId: sourceId,
        pgn: pgn,
        white: white,
        black: black,
        whiteElo: whiteElo,
        blackElo: blackElo,
        result: result,
        date: date,
        timeControl: timeControl,
        event: event,
        variant: variant,
        startFen: startFen,
        eco: eco,
        openingName: openingName,
        userSide: side,
        plyCount: plyCount,
        importedAt: importedAt,
        analysisStatus: analysisStatus,
        completedPlies: completedPlies,
        whiteAccuracy: whiteAccuracy,
        blackAccuracy: blackAccuracy,
      );
}

/// Outcome of [GameRepository.save].
class SaveResult {
  const SaveResult(this.id, {required this.duplicate});

  final int id;

  /// True when a game with the same (source, source_id) already existed; [id]
  /// is then the existing row and nothing was written.
  final bool duplicate;
}

class AnalysisRecord {
  const AnalysisRecord({
    required this.gameId,
    required this.engine,
    required this.depth,
    required this.multipv,
    required this.status,
    this.completedPlies = 0,
    this.whiteAccuracy,
    this.blackAccuracy,
    required this.updatedAt,
  });

  final int gameId;
  final String engine;
  final int depth;
  final int multipv;
  final AnalysisStatus status;
  final int completedPlies;
  final double? whiteAccuracy;
  final double? blackAccuracy;
  final int updatedAt;

  AnalysisRecord copyWith({
    AnalysisStatus? status,
    int? completedPlies,
    double? whiteAccuracy,
    double? blackAccuracy,
    int? updatedAt,
  }) =>
      AnalysisRecord(
        gameId: gameId,
        engine: engine,
        depth: depth,
        multipv: multipv,
        status: status ?? this.status,
        completedPlies: completedPlies ?? this.completedPlies,
        whiteAccuracy: whiteAccuracy ?? this.whiteAccuracy,
        blackAccuracy: blackAccuracy ?? this.blackAccuracy,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// One engine line for a position. Scores are White POV.
class PositionLineRecord {
  const PositionLineRecord({
    required this.gameId,
    required this.ply,
    required this.rank,
    this.scoreCp,
    this.scoreMate,
    required this.depth,
    required this.pvUci,
  });

  final int gameId;
  final int ply;
  final int rank;
  final int? scoreCp;
  final int? scoreMate;
  final int depth;
  final String pvUci;
}

class MoveLabelRecord {
  const MoveLabelRecord({
    required this.gameId,
    required this.ply,
    required this.label,
    this.epLoss,
    this.winBefore,
    this.winAfter,
    this.bestUci,
  });

  final int gameId;
  final int ply;
  final MoveLabel label;
  final double? epLoss;
  final double? winBefore;
  final double? winAfter;
  final String? bestUci;
}
