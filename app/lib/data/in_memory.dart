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
  final Map<String, CachedLlmText> llmCache = {};
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

  @override
  Future<Map<String, int>> idsBySource(GameSource source, Iterable<String> sourceIds) async {
    final wanted = sourceIds.toSet();
    return {
      for (final e in store.games.entries)
        if (e.value.source == source && e.value.sourceId != null && wanted.contains(e.value.sourceId)) e.value.sourceId!: e.key,
    };
  }

  GameRecord _record(int id, NewGame g, {bool withPgn = true}) {
    final a = store.analyses[id];
    return GameRecord.from(
      id,
      g,
      analysisStatus: a?.status,
      completedPlies: a?.completedPlies ?? 0,
      whiteAccuracy: a?.whiteAccuracy,
      blackAccuracy: a?.blackAccuracy,
      pgn: withPgn ? null : '',
    );
  }

  /// Like the SQLite implementation, the list rows carry no movetext (`pgn`
  /// is empty): a screen that needs the PGN must call [get]. A fake that
  /// returned it would hide that mistake in tests.
  @override
  Future<List<GameRecord>> list() async {
    final out = [for (final e in store.games.entries) _record(e.key, e.value, withPgn: false)];
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
    store.llmCache.removeWhere((_, v) => v.gameId == id);
  }

  @override
  Future<int> deleteAll() async {
    final n = store.games.length;
    store.games.clear();
    store.analyses.clear();
    store.lines.clear();
    store.labels.clear();
    store.llmCache.removeWhere((_, v) => v.gameId != null);
    return n;
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
  Future<List<PositionLineRecord>> positionLines(int gameId, {int fromPly = 0}) async {
    final out = [for (final e in store.lines.entries) if (e.key.$1 == gameId && e.key.$2 >= fromPly) e.value];
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
  Future<bool> saveReview(
    int gameId, {
    required int expectedUpdatedAt,
    required List<MoveLabelRecord> labels,
    double? whiteAccuracy,
    double? blackAccuracy,
  }) async {
    final a = store.analyses[gameId];
    if (a == null || a.status != AnalysisStatus.completed || a.updatedAt != expectedUpdatedAt) return false;
    for (final l in labels) {
      store.labels[(gameId, l.ply)] = l;
    }
    store.analyses[gameId] = AnalysisRecord(
      gameId: a.gameId,
      engine: a.engine,
      depth: a.depth,
      multipv: a.multipv,
      status: a.status,
      completedPlies: a.completedPlies,
      whiteAccuracy: whiteAccuracy,
      blackAccuracy: blackAccuracy,
      updatedAt: a.updatedAt,
    );
    return true;
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
    store.llmCache.removeWhere((_, v) => v.gameId == gameId);
  }
}

class InMemoryLlmCacheRepository implements LlmCacheRepository {
  InMemoryLlmCacheRepository([InMemoryStore? store]) : store = store ?? InMemoryStore();

  final InMemoryStore store;

  @override
  Future<CachedLlmText?> get(String key) async => store.llmCache[key];

  @override
  Future<void> put(CachedLlmText entry, {int maxEntries = LlmCacheRepository.defaultMaxEntries}) async {
    final gameId = entry.gameId;
    if (gameId != null && !store.games.containsKey(gameId)) return; // same guard as the SQLite foreign key
    store.llmCache.remove(entry.key);
    store.llmCache[entry.key] = entry;
    final byAge = store.llmCache.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final old in byAge.skip(maxEntries)) {
      store.llmCache.remove(old.key);
    }
  }

  @override
  Future<int> deleteForGame(int gameId) async {
    final before = store.llmCache.length;
    store.llmCache.removeWhere((_, v) => v.gameId == gameId);
    return before - store.llmCache.length;
  }

  @override
  Future<int> count() async => store.llmCache.length;

  @override
  Future<int> clear() async {
    final n = store.llmCache.length;
    store.llmCache.clear();
    return n;
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

  @override
  Future<void> clear() async => _values.clear();
}
