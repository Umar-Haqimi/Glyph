import 'package:glyph_core/glyph_core.dart';

import '../data/models.dart';
import '../data/repositories.dart';

/// Adapts [AnalysisRepository] (app records) to the pipeline's [AnalysisStore]
/// (core types).
class RepositoryAnalysisStore implements AnalysisStore {
  RepositoryAnalysisStore(this._repo);

  final AnalysisRepository _repo;

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
  }) async {
    if (clear) await _repo.clear(gameId);
    await _repo.upsert(AnalysisRecord(
      gameId: gameId,
      engine: engine,
      depth: depth,
      multipv: multipv,
      status: AnalysisStatus.running,
      completedPlies: completedPositions,
      updatedAt: nowMs,
    ));
  }

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
    return _repo.savePosition(gameId, ply, rows, completedPlies: ply + 1, updatedAt: nowMs);
  }

  @override
  Future<void> end(int gameId, AnalysisStatus status, {required int nowMs}) async {
    final a = await _repo.get(gameId);
    if (a == null) return;
    await _repo.upsert(a.copyWith(status: status, updatedAt: nowMs));
  }
}
