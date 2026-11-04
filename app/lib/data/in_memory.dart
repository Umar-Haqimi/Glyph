import 'package:glyph_core/glyph_core.dart';

import 'models.dart';
import 'repositories.dart';

/// In-memory fakes of the repositories, with the same semantics as the SQLite
/// ones (dedupe on (source, sourceId), cascade delete).
class InMemoryStore {
  final Map<int, NewGame> games = {};
  final Map<int, AnalysisRecord> analyses = {};
  final Map<(int, int, int), PositionLineRecord> lines = {};
  final Map<(int, int), MoveLabelRecord> labels = {};
  final Map<String, String> settings = {};
  int nextId = 1;
}

class InMemoryGameRepository implements GameRepository {
  InMemoryGameRepository([InMemoryStore? store]) : store = store ?? InMemoryStore();

  final InMemoryStore store;

  @override
  Future<SaveResult> save(NewGame game) async {
    if (game.sourceId != null) {
      for (final e in store.games.entries) {
        if (e.value.source == game.source && e.value.sourceId == game.sourceId) {
          return SaveResult(e.key, duplicate: true);
        }
      }
    }
    final id = store.nextId++;
    store.games[id] = game;
    return SaveResult(id, duplicate: false);
  }

  GameRecord _record(int id, NewGame g) {
    final a = store.analyses[id];
    return GameRecord.from(
      id,
      g,
      analysisStatus: a?.status,
      completedPlies: a?.completedPlies ?? 0,
      whiteAccuracy: a?.whiteAccuracy,
      blackAccuracy: a?.blackAccuracy,
    );
  }

  @override
  Future<List<GameRecord>> list() async {
    final out = [for (final e in store.games.entries) _record(e.key, e.value)];
    out.sort((a, b) {
      final c = b.importedAt.compareTo(a.importedAt);
      return c != 0 ? c : b.id.compareTo(a.id);
    });
    return out;
  }

  @override
  Future<GameRecord?> get(int id) async {
    final g = store.games[id];
    return g == null ? null : _record(id, g);
  }

  @override
  Future<void> delete(int id) async {
    store.games.remove(id);
    store.analyses.remove(id);
    store.lines.removeWhere((k, _) => k.$1 == id);
    store.labels.removeWhere((k, _) => k.$1 == id);
  }

  @override
  Future<void> setUserSide(int id, Side? side) async {
    final g = store.games[id];
    if (g == null) return;
    store.games[id] = _record(id, g).withUserSide(side);
  }
}

class InMemoryAnalysisRepository implements AnalysisRepository {
  InMemoryAnalysisRepository(this.store);

  final InMemoryStore store;

  void _requireGame(int gameId) {
    if (!store.games.containsKey(gameId)) {
      throw StateError('FOREIGN KEY constraint failed: no game $gameId');
    }
  }

  @override
  Future<AnalysisRecord?> get(int gameId) async => store.analyses[gameId];

  @override
  Future<void> upsert(AnalysisRecord analysis) async {
    _requireGame(analysis.gameId);
    store.analyses[analysis.gameId] = analysis;
  }

  @override
  Future<void> putPositionLines(int gameId, int ply, List<PositionLineRecord> lines) async {
    _requireGame(gameId);
    store.lines.removeWhere((k, _) => k.$1 == gameId && k.$2 == ply);
    for (final l in lines) {
      store.lines[(gameId, ply, l.rank)] = l;
    }
  }

  @override
  Future<void> savePosition(
    int gameId,
    int ply,
    List<PositionLineRecord> lines, {
    required int completedPlies,
    required int updatedAt,
  }) async {
    _requireGame(gameId);
    final a = store.analyses[gameId];
    if (a == null) throw StateError('no analysis row for game $gameId');
    await putPositionLines(gameId, ply, lines);
    store.analyses[gameId] = a.copyWith(completedPlies: completedPlies, updatedAt: updatedAt);
  }

  @override
  Future<List<PositionLineRecord>> positionLines(int gameId) async {
    final out = [for (final e in store.lines.entries) if (e.key.$1 == gameId) e.value];
    out.sort((a, b) => a.ply != b.ply ? a.ply.compareTo(b.ply) : a.rank.compareTo(b.rank));
    return out;
  }

  @override
  Future<void> putLabels(int gameId, List<MoveLabelRecord> labels) async {
    _requireGame(gameId);
    for (final l in labels) {
      store.labels[(gameId, l.ply)] = l;
    }
  }

  @override
  Future<List<MoveLabelRecord>> labels(int gameId) async {
    final out = [for (final e in store.labels.entries) if (e.key.$1 == gameId) e.value];
    out.sort((a, b) => a.ply.compareTo(b.ply));
    return out;
  }

  @override
  Future<int> pauseInterrupted({required int updatedAt}) async {
    var n = 0;
    for (final e in store.analyses.entries.toList()) {
      if (e.value.status == AnalysisStatus.running) {
        store.analyses[e.key] = e.value.copyWith(status: AnalysisStatus.paused, updatedAt: updatedAt);
        n++;
      }
    }
    return n;
  }

  @override
  Future<void> clear(int gameId) async {
    store.analyses.remove(gameId);
    store.lines.removeWhere((k, _) => k.$1 == gameId);
    store.labels.removeWhere((k, _) => k.$1 == gameId);
  }
}

class InMemorySettingsRepository implements SettingsRepository {
  InMemorySettingsRepository([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);
}
