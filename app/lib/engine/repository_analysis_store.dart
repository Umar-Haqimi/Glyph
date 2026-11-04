import 'package:glyph_core/glyph_core.dart';

import '../data/models.dart';
import '../data/repositories.dart';

/// Adapts [AnalysisRepository] (app records) to the pipeline's [AnalysisStore]
/// (core types).
///
/// When a write fails because the game was deleted (foreign key), and
/// [games] is given, the failure is reported as [GameMissingException] so the
/// pipeline ends the job quietly instead of reporting an engine crash.
class RepositoryAnalysisStore implements AnalysisStore {
  RepositoryAnalysisStore(this._repo, {this.games});

  final AnalysisRepository _repo;

  /// Used to tell "game deleted" apart from other write failures.
  final GameRepository? games;

  Future<T> _write<T>(int gameId, Future<T> Function() op) async {
    try {
      return await op();
    } catch (_) {
      final games = this.games;
      if (games != null && await games.get(gameId) == null) throw GameMissingException(gameId);
      rethrow;
    }
  }

  @override
  Future<StoredAnalysis?> load(int gameId) async {
    final a = await _repo.get(gameId);
    if (a == null) return null;
    return StoredAnalysis(
      depth: a.depth,
      multipv: a.multipv,
      completedPositions: a.completedPlies,
      status: a.status,
    );
  }

  @override
  Future<void> begin(
    int gameId, {
    required String engine,
    required int depth,
    required int multipv,
    required int completedPositions,
    required bool clear,
    required int nowMs,
  }) =>
      _write(gameId, () async {
        // A resume keeps the stored accuracies (M4 fills them in); a fresh
        // start throws everything away.
        final existing = clear ? null : await _repo.get(gameId);
        if (clear) await _repo.clear(gameId);
        await _repo.upsert(AnalysisRecord(
          gameId: gameId,
          engine: engine,
          depth: depth,
          multipv: multipv,
          status: AnalysisStatus.running,
          completedPlies: completedPositions,
          whiteAccuracy: existing?.whiteAccuracy,
          blackAccuracy: existing?.blackAccuracy,
          updatedAt: nowMs,
        ));
      });

  @override
  Future<void> savePosition(int gameId, PositionAnalysis position, {required int nowMs}) {
    final ply = position.ply;
    final rows = position.terminal != null
        // SPEC 5.4: both scores NULL marks a terminal position (see Terminal).
        ? [PositionLineRecord(gameId: gameId, ply: ply, rank: 1, depth: 0, pvUci: '')]
        : [
            for (final l in position.lines)
              PositionLineRecord(
                gameId: gameId,
                ply: ply,
                rank: l.rank,
                scoreCp: l.score.cp,
                scoreMate: l.score.mate,
                depth: l.depth,
                pvUci: l.pv.join(' '),
              ),
          ];
    // completed_plies counts positions: position `ply` done -> ply + 1.
    return _write(gameId, () => _repo.savePosition(gameId, ply, rows, completedPlies: ply + 1, updatedAt: nowMs));
  }

  @override
  Future<void> end(int gameId, AnalysisStatus status, {required int nowMs}) async {
    final a = await _repo.get(gameId);
    if (a == null) return;
    await _repo.upsert(a.copyWith(status: status, updatedAt: nowMs));
  }
}
