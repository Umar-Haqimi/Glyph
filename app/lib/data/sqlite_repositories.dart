import 'package:glyph_core/glyph_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'db.dart';
import 'models.dart';
import 'repositories.dart';

class SqliteGameRepository implements GameRepository {
  SqliteGameRepository(this._db);

  final Db _db;

  static const _select = '''
SELECT g.*, a.status AS a_status, a.completed_plies AS a_done,
       a.white_accuracy AS a_white, a.black_accuracy AS a_black
FROM games g LEFT JOIN analyses a ON a.game_id = g.id''';

  @override
  Future<SaveResult> save(NewGame g) async {
    return _db.transaction(() {
      if (g.sourceId != null) {
        final existing = _db.raw.select(
          'SELECT id FROM games WHERE source = ? AND source_id = ?',
          [g.source.name, g.sourceId],
        );
        if (existing.isNotEmpty) return SaveResult(existing.first['id'] as int, duplicate: true);
      }
      _db.raw.execute('''
INSERT INTO games (source, source_id, pgn, white, black, white_elo, black_elo, result, date,
  time_control, event, variant, start_fen, eco, opening_name, user_side, ply_count, imported_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)''', [
        g.source.name,
        g.sourceId,
        g.pgn,
        g.white,
        g.black,
        g.whiteElo,
        g.blackElo,
        g.result,
        g.date,
        g.timeControl,
        g.event,
        g.variant.name,
        g.startFen,
        g.eco,
        g.openingName,
        g.userSide?.name,
        g.plyCount,
        g.importedAt,
      ]);
      return SaveResult(_db.raw.lastInsertRowId, duplicate: false);
    });
  }

  GameRecord _fromRow(Row r) => GameRecord(
        id: r['id'] as int,
        source: GameSource.values.byName(r['source'] as String),
        sourceId: r['source_id'] as String?,
        pgn: r['pgn'] as String,
        white: r['white'] as String?,
        black: r['black'] as String?,
        whiteElo: r['white_elo'] as int?,
        blackElo: r['black_elo'] as int?,
        result: r['result'] as String?,
        date: r['date'] as String?,
        timeControl: r['time_control'] as String?,
        event: r['event'] as String?,
        variant: GameVariant.values.byName(r['variant'] as String),
        startFen: r['start_fen'] as String?,
        eco: r['eco'] as String?,
        openingName: r['opening_name'] as String?,
        userSide: switch (r['user_side'] as String?) {
          'white' => Side.white,
          'black' => Side.black,
          _ => null,
        },
        plyCount: r['ply_count'] as int,
        importedAt: r['imported_at'] as int,
        analysisStatus: (r['a_status'] as String?) == null
            ? null
            : AnalysisStatus.values.byName(r['a_status'] as String),
        completedPlies: (r['a_done'] as int?) ?? 0,
        whiteAccuracy: (r['a_white'] as num?)?.toDouble(),
        blackAccuracy: (r['a_black'] as num?)?.toDouble(),
      );

  @override
  Future<List<GameRecord>> list() async => [
        for (final r in _db.raw.select('$_select ORDER BY g.imported_at DESC, g.id DESC')) _fromRow(r),
      ];

  @override
  Future<GameRecord?> get(int id) async {
    final rows = _db.raw.select('$_select WHERE g.id = ?', [id]);
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<void> delete(int id) async {
    _db.transaction(() {
      _db.raw.execute('DELETE FROM llm_cache WHERE game_id = ?', [id]);
      _db.raw.execute('DELETE FROM games WHERE id = ?', [id]);
    });
  }

  @override
  Future<void> setUserSide(int id, Side? side) async =>
      _db.raw.execute('UPDATE games SET user_side = ? WHERE id = ?', [side?.name, id]);
}

class SqliteAnalysisRepository implements AnalysisRepository {
  SqliteAnalysisRepository(this._db);

  final Db _db;

  @override
  Future<AnalysisRecord?> get(int gameId) async {
    final rows = _db.raw.select('SELECT * FROM analyses WHERE game_id = ?', [gameId]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return AnalysisRecord(
      gameId: gameId,
      engine: r['engine'] as String,
      depth: r['depth'] as int,
      multipv: r['multipv'] as int,
      status: AnalysisStatus.values.byName(r['status'] as String),
      completedPlies: r['completed_plies'] as int,
      whiteAccuracy: (r['white_accuracy'] as num?)?.toDouble(),
      blackAccuracy: (r['black_accuracy'] as num?)?.toDouble(),
      updatedAt: r['updated_at'] as int,
    );
  }

  @override
  Future<void> upsert(AnalysisRecord a) async {
    _db.raw.execute('''
INSERT INTO analyses (game_id, engine, depth, multipv, status, completed_plies,
  white_accuracy, black_accuracy, updated_at)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
ON CONFLICT(game_id) DO UPDATE SET engine = excluded.engine, depth = excluded.depth,
  multipv = excluded.multipv, status = excluded.status,
  completed_plies = excluded.completed_plies, white_accuracy = excluded.white_accuracy,
  black_accuracy = excluded.black_accuracy, updated_at = excluded.updated_at''', [
      a.gameId,
      a.engine,
      a.depth,
      a.multipv,
      a.status.name,
      a.completedPlies,
      a.whiteAccuracy,
      a.blackAccuracy,
      a.updatedAt,
    ]);
  }

  @override
  Future<void> putPositionLines(int gameId, int ply, List<PositionLineRecord> lines) async {
    _db.transaction(() {
      _db.raw.execute('DELETE FROM position_lines WHERE game_id = ? AND ply = ?', [gameId, ply]);
      final stmt = _db.raw.prepare('''
INSERT INTO position_lines (game_id, ply, rank, score_cp, score_mate, depth, pv_uci)
VALUES (?, ?, ?, ?, ?, ?, ?)''');
      try {
        for (final l in lines) {
          stmt.execute([gameId, ply, l.rank, l.scoreCp, l.scoreMate, l.depth, l.pvUci]);
        }
      } finally {
        stmt.close();
      }
    });
  }

  @override
  Future<void> savePosition(
    int gameId,
    int ply,
    List<PositionLineRecord> lines, {
    required int completedPlies,
    required int updatedAt,
  }) async {
    _db.transaction(() {
      _db.raw.execute('DELETE FROM position_lines WHERE game_id = ? AND ply = ?', [gameId, ply]);
      final stmt = _db.raw.prepare('''
INSERT INTO position_lines (game_id, ply, rank, score_cp, score_mate, depth, pv_uci)
VALUES (?, ?, ?, ?, ?, ?, ?)''');
      try {
        for (final l in lines) {
          stmt.execute([gameId, ply, l.rank, l.scoreCp, l.scoreMate, l.depth, l.pvUci]);
        }
      } finally {
        stmt.close();
      }
      _db.raw.execute(
        'UPDATE analyses SET completed_plies = ?, updated_at = ? WHERE game_id = ?',
        [completedPlies, updatedAt, gameId],
      );
    });
  }

  @override
  Future<List<PositionLineRecord>> positionLines(int gameId, {int fromPly = 0}) async => [
        for (final r in _db.raw.select(
          'SELECT * FROM position_lines WHERE game_id = ? AND ply >= ? ORDER BY ply, rank',
          [gameId, fromPly],
        ))
          PositionLineRecord(
            gameId: gameId,
            ply: r['ply'] as int,
            rank: r['rank'] as int,
            scoreCp: r['score_cp'] as int?,
            scoreMate: r['score_mate'] as int?,
            depth: r['depth'] as int,
            pvUci: r['pv_uci'] as String,
          ),
      ];

  @override
  Future<void> putLabels(int gameId, List<MoveLabelRecord> labels) async {
    _db.transaction(() {
      final stmt = _db.raw.prepare('''
INSERT OR REPLACE INTO move_labels (game_id, ply, label, ep_loss, win_before, win_after, best_uci)
VALUES (?, ?, ?, ?, ?, ?, ?)''');
      try {
        for (final l in labels) {
          stmt.execute([gameId, l.ply, l.label.name, l.epLoss, l.winBefore, l.winAfter, l.bestUci]);
        }
      } finally {
        stmt.close();
      }
    });
  }

  @override
  Future<bool> saveReview(
    int gameId, {
    required int expectedUpdatedAt,
    required List<MoveLabelRecord> labels,
    double? whiteAccuracy,
    double? blackAccuracy,
  }) async =>
      _db.transaction(() {
        // The guard is the first statement: if it matches nothing, no label is written.
        _db.raw.execute(
          '''
UPDATE analyses SET white_accuracy = ?, black_accuracy = ?
WHERE game_id = ? AND status = 'completed' AND updated_at = ?''',
          [whiteAccuracy, blackAccuracy, gameId, expectedUpdatedAt],
        );
        if (_db.raw.updatedRows == 0) return false;
        final stmt = _db.raw.prepare('''
INSERT OR REPLACE INTO move_labels (game_id, ply, label, ep_loss, win_before, win_after, best_uci)
VALUES (?, ?, ?, ?, ?, ?, ?)''');
        try {
          for (final l in labels) {
            stmt.execute([gameId, l.ply, l.label.name, l.epLoss, l.winBefore, l.winAfter, l.bestUci]);
          }
        } finally {
          stmt.close();
        }
        return true;
      });

  @override
  Future<List<MoveLabelRecord>> labels(int gameId) async => [
        for (final r in _db.raw.select('SELECT * FROM move_labels WHERE game_id = ? ORDER BY ply', [gameId]))
          MoveLabelRecord(
            gameId: gameId,
            ply: r['ply'] as int,
            label: MoveLabel.values.byName(r['label'] as String),
            epLoss: (r['ep_loss'] as num?)?.toDouble(),
            winBefore: (r['win_before'] as num?)?.toDouble(),
            winAfter: (r['win_after'] as num?)?.toDouble(),
            bestUci: r['best_uci'] as String?,
          ),
      ];

  @override
  Future<int> pauseInterrupted({required int updatedAt}) async {
    _db.raw.execute(
      "UPDATE analyses SET status = 'paused', updated_at = ? WHERE status = 'running'",
      [updatedAt],
    );
    return _db.raw.updatedRows;
  }

  @override
  Future<void> clear(int gameId) async {
    _db.transaction(() {
      _db.raw.execute('DELETE FROM position_lines WHERE game_id = ?', [gameId]);
      _db.raw.execute('DELETE FROM move_labels WHERE game_id = ?', [gameId]);
      _db.raw.execute('DELETE FROM analyses WHERE game_id = ?', [gameId]);
      // The engine lines are about to change: explanations built on them go.
      _db.raw.execute('DELETE FROM llm_cache WHERE game_id = ?', [gameId]);
    });
  }
}

class SqliteLlmCacheRepository implements LlmCacheRepository {
  SqliteLlmCacheRepository(this._db);

  final Db _db;

  @override
  Future<CachedLlmText?> get(String key) async {
    final rows = _db.raw.select('SELECT * FROM llm_cache WHERE key = ?', [key]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return CachedLlmText(
      key: r['key'] as String,
      kind: PromptKind.values.byName(r['kind'] as String),
      content: r['content'] as String,
      model: r['model'] as String,
      createdAt: r['created_at'] as int,
      gameId: r['game_id'] as int?,
    );
  }

  @override
  Future<void> put(CachedLlmText e, {int maxEntries = LlmCacheRepository.defaultMaxEntries}) async {
    _db.transaction(() {
      _db.raw.execute(
        'INSERT INTO llm_cache (key, kind, content, model, created_at, game_id) VALUES (?, ?, ?, ?, ?, ?) '
        'ON CONFLICT(key) DO UPDATE SET kind = excluded.kind, content = excluded.content, '
        'model = excluded.model, created_at = excluded.created_at, game_id = excluded.game_id',
        [e.key, e.kind.name, e.content, e.model, e.createdAt, e.gameId],
      );
      _db.raw.execute(
        'DELETE FROM llm_cache WHERE key IN '
        '(SELECT key FROM llm_cache ORDER BY created_at DESC, rowid DESC LIMIT -1 OFFSET ?)',
        [maxEntries],
      );
    });
  }

  @override
  Future<int> deleteForGame(int gameId) async {
    _db.raw.execute('DELETE FROM llm_cache WHERE game_id = ?', [gameId]);
    return _db.raw.updatedRows;
  }

  @override
  Future<int> count() async => _db.raw.select('SELECT COUNT(*) AS n FROM llm_cache').first['n'] as int;
}

class SqliteSettingsRepository implements SettingsRepository {
  SqliteSettingsRepository(this._db);

  final Db _db;

  @override
  Future<String?> get(String key) async {
    final rows = _db.raw.select('SELECT value FROM settings WHERE key = ?', [key]);
    return rows.isEmpty ? null : rows.first['value'] as String;
  }

  @override
  Future<void> set(String key, String value) async => _db.raw.execute(
        'INSERT INTO settings (key, value) VALUES (?, ?) '
        'ON CONFLICT(key) DO UPDATE SET value = excluded.value',
        [key, value],
      );

  @override
  Future<void> remove(String key) async => _db.raw.execute('DELETE FROM settings WHERE key = ?', [key]);
}
