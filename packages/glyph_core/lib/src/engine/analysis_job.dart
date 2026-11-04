import 'package:dartchess/dartchess.dart';

import '../game/game.dart';
import 'terminal.dart';
import 'uci_parser.dart';

/// Persisted status of an analysis (`analyses.status`).
enum AnalysisStatus { running, paused, cancelled, completed, failed }

/// Why a job failed (SPEC section 4, `AnalysisJob`).
enum AnalysisFailureKind {
  /// The engine could not be created or did not complete its handshake.
  engineUnavailable,

  /// The engine died, rejected input or stopped answering mid-job.
  engineCrashed,
}

/// State machine of one analysis job (SPEC section 4):
///
/// ```
/// idle -> starting -> running(k/N) -> completed
///                          |--> cancelled   (resumable)
///                          |--> paused      (app backgrounded; resumes on foreground)
/// any -> failed(EngineUnavailable | EngineCrashed)   (Retry recreates the engine)
/// ```
///
/// `completed` / `total` count **positions** (plies + 1: the start position is
/// position 0), the same unit as `analyses.completed_plies`.
sealed class AnalysisJobState {
  const AnalysisJobState();

  /// The game being analysed; null for [AnalysisIdle].
  int? get gameId => null;
  int get completed => 0;
  int get total => 0;

  /// A terminal state of a job run (no more progress without a new request).
  bool get isFinished => switch (this) {
        AnalysisCompleted() || AnalysisCancelled() || AnalysisPaused() || AnalysisFailed() => true,
        _ => false,
      };
}

class AnalysisIdle extends AnalysisJobState {
  const AnalysisIdle();

  @override
  String toString() => 'idle';
}

class AnalysisStarting extends AnalysisJobState {
  const AnalysisStarting(this.gameId, {this.total = 0});

  @override
  final int gameId;
  @override
  final int total;

  @override
  String toString() => 'starting($gameId)';
}

class AnalysisRunning extends AnalysisJobState {
  const AnalysisRunning(this.gameId, this.completed, this.total);

  @override
  final int gameId;
  @override
  final int completed;
  @override
  final int total;

  @override
  String toString() => 'running($gameId $completed/$total)';
}

class AnalysisCompleted extends AnalysisJobState {
  const AnalysisCompleted(this.gameId, this.total);

  @override
  final int gameId;
  @override
  final int total;
  @override
  int get completed => total;

  @override
  String toString() => 'completed($gameId)';
}

class AnalysisCancelled extends AnalysisJobState {
  const AnalysisCancelled(this.gameId, this.completed, this.total);

  @override
  final int gameId;
  @override
  final int completed;
  @override
  final int total;

  @override
  String toString() => 'cancelled($gameId $completed/$total)';
}

class AnalysisPaused extends AnalysisJobState {
  const AnalysisPaused(this.gameId, this.completed, this.total);

  @override
  final int gameId;
  @override
  final int completed;
  @override
  final int total;

  @override
  String toString() => 'paused($gameId $completed/$total)';
}

class AnalysisFailed extends AnalysisJobState {
  const AnalysisFailed(this.gameId, this.kind, this.message, this.completed, this.total);

  @override
  final int gameId;
  final AnalysisFailureKind kind;

  /// Technical detail for logs; never shown verbatim in the UI.
  final String message;
  @override
  final int completed;
  @override
  final int total;

  @override
  String toString() => 'failed($gameId $kind: $message)';
}

/// What to analyse and how.
class AnalysisRequest {
  const AnalysisRequest({
    required this.gameId,
    required this.startFen,
    required this.moves,
    required this.depth,
    this.multipv = 2,
    this.threads = 1,
    this.hashMb = 16,
    this.engineName = 'Stockfish',
    this.restart = false,
  });

  /// Builds a request from a parsed game (moves are dartchess UCI).
  factory AnalysisRequest.fromGame(
    int gameId,
    Game game, {
    required int depth,
    int multipv = 2,
    int threads = 1,
    int hashMb = 16,
    String engineName = 'Stockfish',
    bool restart = false,
  }) =>
      AnalysisRequest(
        gameId: gameId,
        startFen: game.startFen,
        moves: [for (final p in game.plies) p.uci],
        depth: depth,
        multipv: multipv,
        threads: threads,
        hashMb: hashMb,
        engineName: engineName,
        restart: restart,
      );

  final int gameId;

  /// Full FEN of the start position (the standard one for ordinary games).
  final String startFen;

  /// The game's moves in dartchess UCI form: castling is king-takes-rook
  /// (`e1h1`), which is exactly what Stockfish accepts with
  /// `UCI_Chess960 = true` (always set; docs/DECISIONS.md).
  final List<String> moves;
  final int depth;
  final int multipv;
  final int threads;
  final int hashMb;

  /// Stored in `analyses.engine`.
  final String engineName;

  /// Ignore any stored progress and start from position 0.
  final bool restart;

  /// Number of positions to analyse: start position plus one per move.
  int get totalPositions => moves.length + 1;

  AnalysisRequest copyWith({bool? restart}) => AnalysisRequest(
        gameId: gameId,
        startFen: startFen,
        moves: moves,
        depth: depth,
        multipv: multipv,
        threads: threads,
        hashMb: hashMb,
        engineName: engineName,
        restart: restart ?? this.restart,
      );
}

/// What the store remembers about a game's analysis.
class StoredAnalysis {
  const StoredAnalysis({
    required this.depth,
    required this.multipv,
    required this.completedPositions,
    required this.status,
  });

  final int depth;
  final int multipv;

  /// Positions `0 .. completedPositions - 1` are fully persisted.
  final int completedPositions;
  final AnalysisStatus status;
}

/// The result for one position, ready to persist. Scores are White POV.
class PositionAnalysis {
  const PositionAnalysis({required this.ply, this.lines = const [], this.terminal});

  /// 0 = start position.
  final int ply;

  /// One line per multipv rank (empty for a terminal position).
  final List<EngineLine> lines;

  /// Non-null for positions computed without the engine.
  final Terminal? terminal;
}

/// Persistence port of the pipeline (core is database-free). The app adapts
/// `AnalysisRepository`; tests use [InMemoryAnalysisStore].
abstract interface class AnalysisStore {
  Future<StoredAnalysis?> load(int gameId);

  /// Marks the analysis `running` with [completedPositions] already done. With
  /// [clear] the old lines are deleted first (a fresh start).
  Future<void> begin(
    int gameId, {
    required String engine,
    required int depth,
    required int multipv,
    required int completedPositions,
    required bool clear,
    required int nowMs,
  });

  /// Persists one position and sets `completed_plies = position.ply + 1` in
  /// one transaction. The pipeline awaits this **before** the next `go`.
  Future<void> savePosition(int gameId, PositionAnalysis position, {required int nowMs});

  Future<void> end(int gameId, AnalysisStatus status, {required int nowMs});
}

/// A store that keeps everything in memory (tests, the recorder).
class InMemoryAnalysisStore implements AnalysisStore {
  final Map<int, StoredAnalysis> analyses = {};
  final Map<(int, int), PositionAnalysis> positions = {};

  /// Order in which positions were saved: `(gameId, ply)`.
  final List<(int, int)> saveLog = [];

  @override
  Future<StoredAnalysis?> load(int gameId) async => analyses[gameId];

  @override
  Future<void> begin(
    int gameId, {
    required String engine,
    required int depth,
    required int multipv,
    required int completedPositions,
    required bool clear,
    required int nowMs,
  }) async {
    if (clear) positions.removeWhere((k, _) => k.$1 == gameId);
    analyses[gameId] = StoredAnalysis(
      depth: depth,
      multipv: multipv,
      completedPositions: completedPositions,
      status: AnalysisStatus.running,
    );
  }

  @override
  Future<void> savePosition(int gameId, PositionAnalysis position, {required int nowMs}) async {
    positions[(gameId, position.ply)] = position;
    saveLog.add((gameId, position.ply));
    final a = analyses[gameId]!;
    analyses[gameId] = StoredAnalysis(
      depth: a.depth,
      multipv: a.multipv,
      completedPositions: position.ply + 1,
      status: a.status,
    );
  }

  @override
  Future<void> end(int gameId, AnalysisStatus status, {required int nowMs}) async {
    final a = analyses[gameId]!;
    analyses[gameId] = StoredAnalysis(
      depth: a.depth,
      multipv: a.multipv,
      completedPositions: a.completedPositions,
      status: status,
    );
  }
}

/// Replays [request] with dartchess and returns the position before each move
/// plus the final one (`moves.length + 1` entries). Throws [ArgumentError] on
/// an illegal or malformed move.
List<Position> replayPositions(String startFen, List<String> moves) {
  var pos = Position.setupPosition(
    Rule.chess,
    Setup.parseFen(startFen),
    ignoreImpossibleCheck: true,
  );
  final out = <Position>[pos];
  for (var i = 0; i < moves.length; i++) {
    final uci = moves[i];
    final move = uci.length >= 4 && uci.length <= 5 ? Move.parse(uci) : null;
    if (move == null || !pos.isLegal(move)) {
      throw ArgumentError('Illegal move "$uci" at ply ${i + 1}');
    }
    pos = pos.playUnchecked(move);
    out.add(pos);
  }
  return out;
}
