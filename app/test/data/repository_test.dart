import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/db.dart';
import 'package:glyph/data/in_memory.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/data/repositories.dart';
import 'package:glyph/data/sqlite_repositories.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:sqlite3/sqlite3.dart';

NewGame newGame({
  String? sourceId,
  GameSource source = GameSource.paste,
  int importedAt = 1000,
  String white = 'Alice',
  Side? userSide,
}) =>
    NewGame(
      source: source,
      sourceId: sourceId,
      pgn: '[White "$white"]\n\n1. e4 e5 *',
      white: white,
      black: 'Bob',
      whiteElo: 1500,
      result: '1-0',
      date: '2026.10.01',
      timeControl: '600+0',
      event: 'Casual',
      variant: GameVariant.chess960,
      startFen: 'brnkqbnr/pppppppp/8/8/8/8/PPPPPPPP/BRNKQBNR w KQkq - 0 1',
      eco: 'C20',
      openingName: 'Kings Pawn',
      userSide: userSide,
      plyCount: 2,
      importedAt: importedAt,
    );

typedef Repos = ({GameRepository games, AnalysisRepository analyses, SettingsRepository settings, LlmCacheRepository cache});

/// Behaviour every implementation of the repositories must have.
void contract(String name, Repos Function() create) {
  group(name, () {
    late Repos r;
    setUp(() => r = create());

    test('idsBySource finds the games already imported from a source (dedupe key)', () async {
      final a = await r.games.save(newGame(sourceId: 'aaaa1111', source: GameSource.lichess));
      final b = await r.games.save(newGame(sourceId: 'https://www.chess.com/game/live/1', source: GameSource.chesscom));
      await r.games.save(newGame(sourceId: 'bbbb2222', source: GameSource.lichess));
      await r.games.save(newGame()); // no source id
      final found = await r.games.idsBySource(GameSource.lichess, ['aaaa1111', 'cccc3333', 'https://www.chess.com/game/live/1']);
      expect(found, {'aaaa1111': a.id});
      expect(await r.games.idsBySource(GameSource.chesscom, ['https://www.chess.com/game/live/1']), {'https://www.chess.com/game/live/1': b.id});
      expect(await r.games.idsBySource(GameSource.lichess, const []), isEmpty);
      expect(await r.games.idsBySource(GameSource.paste, ['aaaa1111']), isEmpty, reason: 'the source is part of the key');
      final many = [for (var i = 0; i < 450; i++) 'id$i'];
      expect(await r.games.idsBySource(GameSource.lichess, many), isEmpty, reason: 'more ids than SQLite binds at once');
    });

    test('save and read back every column', () async {
      final saved = await r.games.save(newGame(sourceId: 'abc', source: GameSource.lichess, userSide: Side.black));
      expect(saved.duplicate, isFalse);
      final g = (await r.games.get(saved.id))!;
      expect(g.id, saved.id);
      expect(g.source, GameSource.lichess);
      expect(g.sourceId, 'abc');
      expect(g.white, 'Alice');
      expect(g.black, 'Bob');
      expect(g.whiteElo, 1500);
      expect(g.blackElo, isNull);
      expect(g.variant, GameVariant.chess960);
      expect(g.startFen, startsWith('brnkqbnr'));
      expect(g.userSide, Side.black);
      expect(g.plyCount, 2);
      expect(g.analysisStatus, isNull);
      expect(g.completedPlies, 0);
      expect(await r.games.get(999), isNull);
    });

    test('list is newest first', () async {
      final a = await r.games.save(newGame(importedAt: 1, white: 'old'));
      final b = await r.games.save(newGame(importedAt: 3, white: 'new'));
      final c = await r.games.save(newGame(importedAt: 3, white: 'same-time-later'));
      expect((await r.games.list()).map((g) => g.id), [c.id, b.id, a.id]);
    });

    test('list carries everything a card shows (the movetext may be left out), get has the PGN', () async {
      final saved = await r.games.save(newGame(sourceId: 'abc', source: GameSource.lichess, userSide: Side.white));
      final listed = (await r.games.list()).single;
      final full = (await r.games.get(saved.id))!;
      expect(full.pgn, contains('1. e4 e5'));
      expect(listed.id, full.id);
      expect(listed.white, full.white);
      expect(listed.black, full.black);
      expect(listed.result, full.result);
      expect(listed.date, full.date);
      expect(listed.eco, full.eco);
      expect(listed.openingName, full.openingName);
      expect(listed.userSide, full.userSide);
      expect(listed.plyCount, full.plyCount);
      expect(listed.sourceId, full.sourceId);
    });

    test('deleteAll removes every game with its analysis, lines, labels and saved texts; clear empties cache and settings', () async {
      final a = (await r.games.save(newGame(sourceId: 'a', source: GameSource.lichess))).id;
      final b = (await r.games.save(newGame())).id;
      await r.analyses.upsert(AnalysisRecord(
        gameId: a, engine: 'e', depth: 12, multipv: 2, status: AnalysisStatus.completed, completedPlies: 3, updatedAt: 1));
      await r.analyses.putPositionLines(a, 0, [PositionLineRecord(gameId: a, ply: 0, rank: 1, scoreCp: 10, depth: 12, pvUci: 'e2e4')]);
      await r.analyses.putLabels(a, [MoveLabelRecord(gameId: a, ply: 1, label: MoveLabel.best)]);
      await r.cache.put(CachedLlmText(key: 'k1', kind: PromptKind.move, content: 'x', model: 'm', createdAt: 1, gameId: a));
      await r.cache.put(CachedLlmText(key: 'k2', kind: PromptKind.move, content: 'y', model: 'm', createdAt: 2, gameId: b));
      await r.settings.set('x', '1');
      expect(await r.games.deleteAll(), 2);
      expect(await r.games.list(), isEmpty);
      expect(await r.analyses.get(a), isNull);
      expect(await r.analyses.positionLines(a), isEmpty);
      expect(await r.analyses.labels(a), isEmpty);
      expect(await r.cache.count(), 0);
      expect(await r.settings.get('x'), '1', reason: 'deleteAll only touches games');
      await r.cache.put(CachedLlmText(key: 'k3', kind: PromptKind.summary, content: 'z', model: 'm', createdAt: 3));
      expect(await r.cache.clear(), 1);
      expect(await r.cache.count(), 0);
      await r.settings.clear();
      expect(await r.settings.get('x'), isNull);
    });

    test('dedupe on (source, source_id)', () async {
      final first = await r.games.save(newGame(sourceId: 'g1', source: GameSource.lichess));
      final again = await r.games.save(newGame(sourceId: 'g1', source: GameSource.lichess, white: 'changed'));
      expect(again.duplicate, isTrue);
      expect(again.id, first.id);
      expect((await r.games.get(first.id))!.white, 'Alice', reason: 'existing row untouched');
      // Same id on another source is a different game.
      final other = await r.games.save(newGame(sourceId: 'g1', source: GameSource.chesscom));
      expect(other.duplicate, isFalse);
      expect(await r.games.list(), hasLength(2));
    });

    test('local games (null source_id) are never duplicates', () async {
      final a = await r.games.save(newGame());
      final b = await r.games.save(newGame());
      expect(a.id, isNot(b.id));
      expect(b.duplicate, isFalse);
    });

    test('setUserSide', () async {
      final id = (await r.games.save(newGame())).id;
      await r.games.setUserSide(id, Side.white);
      expect((await r.games.get(id))!.userSide, Side.white);
      await r.games.setUserSide(id, null);
      expect((await r.games.get(id))!.userSide, isNull);
    });

    test('pauseInterrupted: rows left running by a killed process become paused', () async {
      AnalysisRecord rec(int id, AnalysisStatus status) => AnalysisRecord(
            gameId: id,
            engine: 'Stockfish',
            depth: 16,
            multipv: 2,
            status: status,
            completedPlies: 7,
            updatedAt: 1,
          );
      final running = (await r.games.save(newGame(white: 'r'))).id;
      final done = (await r.games.save(newGame(white: 'd'))).id;
      final cancelled = (await r.games.save(newGame(white: 'c'))).id;
      await r.analyses.upsert(rec(running, AnalysisStatus.running));
      await r.analyses.upsert(rec(done, AnalysisStatus.completed));
      await r.analyses.upsert(rec(cancelled, AnalysisStatus.cancelled));
      expect(await r.analyses.pauseInterrupted(updatedAt: 99), 1);
      final a = (await r.analyses.get(running))!;
      expect((a.status, a.completedPlies, a.updatedAt), (AnalysisStatus.paused, 7, 99));
      expect((await r.analyses.get(done))!.status, AnalysisStatus.completed);
      expect((await r.analyses.get(cancelled))!.status, AnalysisStatus.cancelled);
      expect(await r.analyses.pauseInterrupted(updatedAt: 100), 0);
    });

    test('analysis summary shows up on the game', () async {
      final id = (await r.games.save(newGame())).id;
      await r.analyses.upsert(AnalysisRecord(
        gameId: id,
        engine: 'Stockfish 19 light',
        depth: 16,
        multipv: 2,
        status: AnalysisStatus.running,
        completedPlies: 1,
        updatedAt: 5,
      ));
      var g = (await r.games.get(id))!;
      expect((g.analysisStatus, g.completedPlies), (AnalysisStatus.running, 1));
      expect(g.analysisProgress, closeTo(1 / 3, 1e-9), reason: '1 of 3 positions (2 plies)');
      final done = (await r.analyses.get(id))!.copyWith(
        status: AnalysisStatus.completed,
        completedPlies: 2,
        whiteAccuracy: 91.5,
        blackAccuracy: 78.25,
        updatedAt: 9,
      );
      await r.analyses.upsert(done);
      g = (await r.games.list()).single;
      expect(g.analysisStatus, AnalysisStatus.completed);
      expect((g.whiteAccuracy, g.blackAccuracy), (91.5, 78.25));
      expect((await r.analyses.get(id))!.updatedAt, 9);
      expect(await r.analyses.get(12345), isNull);
    });

    test('position lines: per-ply replace, ordered', () async {
      final id = (await r.games.save(newGame())).id;
      PositionLineRecord line(int ply, int rank, {int? cp, int? mate, String pv = 'e2e4 e7e5'}) =>
          PositionLineRecord(gameId: id, ply: ply, rank: rank, scoreCp: cp, scoreMate: mate, depth: 16, pvUci: pv);
      await r.analyses.putPositionLines(id, 1, [line(1, 2, cp: -10), line(1, 1, cp: 20)]);
      await r.analyses.putPositionLines(id, 0, [line(0, 1, mate: 3)]);
      await r.analyses.putPositionLines(id, 1, [line(1, 1, cp: 33), line(1, 2, cp: -5)]);
      final lines = await r.analyses.positionLines(id);
      expect(lines.map((l) => (l.ply, l.rank, l.scoreCp, l.scoreMate)), [
        (0, 1, null, 3),
        (1, 1, 33, null),
        (1, 2, -5, null),
      ]);
    });

    test('position lines from a ply on: only the tail, same order', () async {
      final id = (await r.games.save(newGame())).id;
      final other = (await r.games.save(newGame(sourceId: 'other'))).id;
      PositionLineRecord line(int game, int ply, int rank) =>
          PositionLineRecord(gameId: game, ply: ply, rank: rank, scoreCp: ply * 10 + rank, depth: 16, pvUci: 'e2e4');
      for (var ply = 0; ply < 5; ply++) {
        await r.analyses.putPositionLines(id, ply, [line(id, ply, 2), line(id, ply, 1)]);
      }
      await r.analyses.putPositionLines(other, 3, [line(other, 3, 1)]);
      expect((await r.analyses.positionLines(id)), hasLength(10));
      expect((await r.analyses.positionLines(id, fromPly: 0)), hasLength(10));
      final tail = await r.analyses.positionLines(id, fromPly: 3);
      expect(tail.map((l) => (l.ply, l.rank)), [(3, 1), (3, 2), (4, 1), (4, 2)]);
      expect(await r.analyses.positionLines(id, fromPly: 5), isEmpty);
      expect((await r.analyses.positionLines(other, fromPly: 3)).single.gameId, other);
    });

    test('savePosition: lines and completed_plies move together; terminal rows keep NULL scores', () async {
      final id = (await r.games.save(newGame())).id;
      await r.analyses.upsert(AnalysisRecord(
        gameId: id,
        engine: 'Stockfish 19 light',
        depth: 12,
        multipv: 2,
        status: AnalysisStatus.running,
        updatedAt: 1,
      ));
      PositionLineRecord line(int ply, int rank, {int? cp, int? mate, int depth = 12, String pv = 'e2e4'}) =>
          PositionLineRecord(gameId: id, ply: ply, rank: rank, scoreCp: cp, scoreMate: mate, depth: depth, pvUci: pv);
      await r.analyses.savePosition(id, 0, [line(0, 1, cp: 20), line(0, 2, cp: 5)], completedPlies: 1, updatedAt: 10);
      await r.analyses.savePosition(id, 1, [line(1, 1, cp: -7), line(1, 2, mate: -3)], completedPlies: 2, updatedAt: 11);
      await r.analyses.savePosition(id, 2, [line(2, 1, depth: 0, pv: '')], completedPlies: 3, updatedAt: 12);
      // Re-saving a ply replaces its lines.
      await r.analyses.savePosition(id, 0, [line(0, 1, cp: 22), line(0, 2, cp: 6)], completedPlies: 3, updatedAt: 13);

      final a = (await r.analyses.get(id))!;
      expect((a.completedPlies, a.updatedAt, a.status), (3, 13, AnalysisStatus.running));
      final lines = await r.analyses.positionLines(id);
      expect(lines.map((l) => (l.ply, l.rank, l.scoreCp, l.scoreMate, l.depth)), [
        (0, 1, 22, null, 12),
        (0, 2, 6, null, 12),
        (1, 1, -7, null, 12),
        (1, 2, null, -3, 12),
        (2, 1, null, null, 0),
      ]);
      expect(lines.last.pvUci, '');
    });

    test('labels round trip', () async {
      final id = (await r.games.save(newGame())).id;
      await r.analyses.putLabels(id, [
        MoveLabelRecord(gameId: id, ply: 2, label: MoveLabel.blunder, epLoss: 0.31, winBefore: 80, winAfter: 20, bestUci: 'g1f3'),
        MoveLabelRecord(gameId: id, ply: 1, label: MoveLabel.book),
      ]);
      await r.analyses.putLabels(id, [MoveLabelRecord(gameId: id, ply: 1, label: MoveLabel.best)]);
      final labels = await r.analyses.labels(id);
      expect(labels.map((l) => (l.ply, l.label)), [(1, MoveLabel.best), (2, MoveLabel.blunder)]);
      expect(labels.last.bestUci, 'g1f3');
      expect(labels.last.epLoss, 0.31);
      expect(labels.first.epLoss, isNull);
    });

    test('saveReview: guarded atomic write of labels + accuracies only', () async {
      final id = (await r.games.save(newGame())).id;
      final label = MoveLabelRecord(gameId: id, ply: 1, label: MoveLabel.best);
      AnalysisRecord row(AnalysisStatus s, int at) => AnalysisRecord(
          gameId: id, engine: 'e', depth: 12, multipv: 2, status: s, completedPlies: 3, updatedAt: at);

      expect(
        await r.analyses.saveReview(id, expectedUpdatedAt: 5, labels: [label], whiteAccuracy: 90, blackAccuracy: 80),
        isFalse,
        reason: 'no row',
      );
      expect(await r.analyses.get(id), isNull, reason: 'a missing row is not resurrected');

      await r.analyses.upsert(row(AnalysisStatus.completed, 5));
      expect(await r.analyses.saveReview(id, expectedUpdatedAt: 5, labels: [label], whiteAccuracy: 90, blackAccuracy: 80), isTrue);
      var a = (await r.analyses.get(id))!;
      expect((a.whiteAccuracy, a.blackAccuracy, a.status, a.updatedAt, a.completedPlies, a.engine), (90, 80, AnalysisStatus.completed, 5, 3, 'e'));
      expect(await r.analyses.labels(id), hasLength(1));

      // Stale snapshot (updated_at moved on): nothing is written.
      await r.analyses.upsert(row(AnalysisStatus.completed, 6));
      final other = MoveLabelRecord(gameId: id, ply: 2, label: MoveLabel.blunder);
      expect(await r.analyses.saveReview(id, expectedUpdatedAt: 5, labels: [other], whiteAccuracy: 1, blackAccuracy: 2), isFalse);
      expect((await r.analyses.labels(id)).map((l) => l.ply), [1]);
      expect((await r.analyses.get(id))!.whiteAccuracy, isNull, reason: 'the upsert replaced the row; the stale review changed nothing');

      // Not completed any more: nothing is written.
      await r.analyses.upsert(row(AnalysisStatus.running, 6));
      expect(await r.analyses.saveReview(id, expectedUpdatedAt: 6, labels: [other], whiteAccuracy: 1, blackAccuracy: 2), isFalse);
      expect((await r.analyses.get(id))!.status, AnalysisStatus.running);
      expect((await r.analyses.labels(id)).map((l) => l.ply), [1]);
    });

    test('delete cascades to analysis, lines and labels (only for that game)', () async {
      final a = (await r.games.save(newGame())).id;
      final b = (await r.games.save(newGame())).id;
      for (final id in [a, b]) {
        await r.analyses.upsert(AnalysisRecord(
            gameId: id, engine: 'e', depth: 12, multipv: 2, status: AnalysisStatus.completed, updatedAt: 1));
        await r.analyses.putPositionLines(id, 0, [PositionLineRecord(gameId: id, ply: 0, rank: 1, scoreCp: 1, depth: 12, pvUci: 'e2e4')]);
        await r.analyses.putLabels(id, [MoveLabelRecord(gameId: id, ply: 1, label: MoveLabel.best)]);
      }
      await r.games.delete(a);
      expect(await r.games.get(a), isNull);
      expect(await r.analyses.get(a), isNull);
      expect(await r.analyses.positionLines(a), isEmpty);
      expect(await r.analyses.labels(a), isEmpty);
      expect(await r.analyses.get(b), isNotNull);
      expect(await r.analyses.positionLines(b), hasLength(1));
      expect(await r.analyses.labels(b), hasLength(1));
      await r.games.delete(a); // deleting again is a no-op
    });

    test('analysis rows need an existing game', () async {
      await expectLater(
        r.analyses.upsert(AnalysisRecord(
            gameId: 77, engine: 'e', depth: 12, multipv: 2, status: AnalysisStatus.running, updatedAt: 1)),
        throwsA(anything),
      );
    });

    test('clear removes analysis data but keeps the game', () async {
      final id = (await r.games.save(newGame())).id;
      await r.analyses.upsert(AnalysisRecord(
          gameId: id, engine: 'e', depth: 12, multipv: 2, status: AnalysisStatus.completed, updatedAt: 1));
      await r.analyses.putLabels(id, [MoveLabelRecord(gameId: id, ply: 1, label: MoveLabel.best)]);
      await r.analyses.clear(id);
      expect(await r.analyses.get(id), isNull);
      expect(await r.analyses.labels(id), isEmpty);
      expect(await r.games.get(id), isNotNull);
      expect((await r.games.get(id))!.analysisStatus, isNull);
    });

    CachedLlmText entry(String key, {int? gameId, int createdAt = 1, String content = 'text', PromptKind kind = PromptKind.move}) =>
        CachedLlmText(key: key, kind: kind, content: content, model: 'gpt', createdAt: createdAt, gameId: gameId);

    test('llm cache: get, replace on the same key (Regenerate), kinds', () async {
      expect(await r.cache.get('k'), isNull);
      await r.cache.put(entry('k', content: 'first'));
      await r.cache.put(entry('s', kind: PromptKind.summary, content: 'sum'));
      expect((await r.cache.get('k'))!.content, 'first');
      expect((await r.cache.get('s'))!.kind, PromptKind.summary);
      await r.cache.put(entry('k', content: 'second', createdAt: 9));
      final k = (await r.cache.get('k'))!;
      expect(k.content, 'second');
      expect(k.createdAt, 9);
      expect(k.model, 'gpt');
      expect(await r.cache.count(), 2);
    });

    test('llm cache: trimmed to the newest entries', () async {
      for (var i = 0; i < 8; i++) {
        await r.cache.put(entry('k$i', createdAt: i), maxEntries: 5);
      }
      expect(await r.cache.count(), 5);
      expect(await r.cache.get('k2'), isNull);
      expect(await r.cache.get('k3'), isNotNull);
      expect(await r.cache.get('k7'), isNotNull);
    });

    test('llm cache: deleting a game, or clearing its analysis, removes its entries only', () async {
      final a = (await r.games.save(newGame(sourceId: 'a'))).id;
      final b = (await r.games.save(newGame(sourceId: 'b'))).id;
      await r.cache.put(entry('a1', gameId: a));
      await r.cache.put(entry('a2', gameId: a));
      await r.cache.put(entry('b1', gameId: b));
      await r.cache.put(entry('orphan'));
      expect(await r.cache.deleteForGame(a), 2);
      expect(await r.cache.get('a1'), isNull);
      expect(await r.cache.get('b1'), isNotNull);

      await r.analyses.clear(b); // Re-analyse: the lines change, so does the text
      expect(await r.cache.get('b1'), isNull);
      expect(await r.cache.get('orphan'), isNotNull);

      await r.cache.put(entry('b2', gameId: b));
      await r.games.delete(b);
      expect(await r.cache.get('b2'), isNull);
      expect(await r.cache.get('orphan'), isNotNull);
    });

    test('llm cache: nothing is saved for a game that does not exist (deleted while the answer streamed)', () async {
      final a = (await r.games.save(newGame(sourceId: 'a'))).id;
      await r.games.delete(a);
      await r.cache.put(entry('late', gameId: a));
      expect(await r.cache.get('late'), isNull);
      expect(await r.cache.count(), 0);
      await r.cache.put(entry('free')); // no owner is fine
      expect(await r.cache.count(), 1);
    });

    test('game ids are never reused after a delete', () async {
      final a = (await r.games.save(newGame(sourceId: 'a'))).id;
      final b = (await r.games.save(newGame(sourceId: 'b'))).id;
      await r.games.delete(b);
      final c = (await r.games.save(newGame(sourceId: 'c'))).id;
      expect(c, greaterThan(b));
      await r.games.delete(c);
      await r.games.delete(a);
      final d = (await r.games.save(newGame(sourceId: 'd'))).id;
      expect(d, greaterThan(c));
    });

    test('settings', () async {
      expect(await r.settings.get('k'), isNull);
      await r.settings.set('k', 'v1');
      await r.settings.set('k', 'v2');
      expect(await r.settings.get('k'), 'v2');
      await r.settings.remove('k');
      expect(await r.settings.get('k'), isNull);
    });
  });
}

void main() {
  contract('InMemory repositories', () {
    final store = InMemoryStore();
    return (
      games: InMemoryGameRepository(store),
      analyses: InMemoryAnalysisRepository(store),
      settings: InMemorySettingsRepository(),
      cache: InMemoryLlmCacheRepository(store),
    );
  });

  contract('SQLite repositories (in-memory database)', () {
    final db = Db.inMemory();
    addTearDown(db.close);
    return (
      games: SqliteGameRepository(db),
      analyses: SqliteAnalysisRepository(db),
      settings: SqliteSettingsRepository(db),
      cache: SqliteLlmCacheRepository(db),
    );
  });

  group('SqliteOnlineCache', () {
    test('stores an ETag with its body, replaces on put, bounds the table', () async {
      var now = 0;
      final db = Db.inMemory();
      addTearDown(db.close);
      final cache = SqliteOnlineCache(db, maxEntries: 3, nowMs: () => ++now);
      expect(await cache.get('k'), isNull);
      await cache.put('k', const CachedResponse('W/"1"', 'body1'));
      await cache.put('k', const CachedResponse('W/"2"', 'body2'));
      final got = (await cache.get('k'))!;
      expect((got.etag, got.body), ('W/"2"', 'body2'));
      for (var i = 0; i < 5; i++) {
        await cache.put('e$i', CachedResponse('t$i', 'b$i'));
      }
      expect(db.raw.select('SELECT COUNT(*) AS n FROM http_cache').first['n'], 3);
      expect(await cache.get('k'), isNull, reason: 'the oldest entries go first');
      expect(await cache.get('e4'), isNotNull);
    });

    test('clear forgets every entry (Settings > Clear online cache)', () async {
      final db = Db.inMemory();
      addTearDown(db.close);
      final cache = SqliteOnlineCache(db);
      await cache.put('a', const CachedResponse('t', 'b'));
      await cache.put('b', const CachedResponse('t', 'b'));
      await cache.clear();
      expect(await cache.get('a'), isNull);
      expect(db.raw.select('SELECT COUNT(*) AS n FROM http_cache').first['n'], 0);
      final memory = InMemoryOnlineCache();
      await memory.put('a', const CachedResponse('t', 'b'));
      await memory.clear();
      expect(await memory.get('a'), isNull);
    });

    test('a version 3 database upgrades to the latest and keeps its games', () async {
      final path = '${Directory.systemTemp.createTempSync('glyph_db_test').path}/v3.db';
      addTearDown(() => File(path).parent.deleteSync(recursive: true));
      final v3 = Db.open(path, migrations: Db.migrations.take(3).toList());
      final id = (await SqliteGameRepository(v3).save(newGame(sourceId: 'keep'))).id;
      v3.close();
      final db = Db.open(path);
      addTearDown(db.close);
      expect(db.raw.userVersion, Db.schemaVersion);
      expect((await SqliteGameRepository(db).get(id))!.sourceId, 'keep');
      expect(db.raw.select('SELECT COUNT(*) AS n FROM http_cache').first['n'], 0);
    });
  });

  group('Db', () {
    test('creates the SPEC 5.4 schema (plus llm_cache.game_id from M6) at the latest user_version', () {
      final db = Db.inMemory();
      addTearDown(db.close);
      expect(db.raw.userVersion, 5);
      expect(Db.schemaVersion, 5);
      final tables = db.raw
          .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
          .map((r) => r['name'])
          .toList();
      expect(tables, ['analyses', 'games', 'http_cache', 'llm_cache', 'move_labels', 'position_lines', 'settings']);
      List<String> cols(String t) => db.raw.select('PRAGMA table_info($t)').map((r) => r['name'] as String).toList();
      expect(cols('games'), [
        'id', 'source', 'source_id', 'pgn', 'white', 'black', 'white_elo', 'black_elo', 'result', 'date',
        'time_control', 'event', 'variant', 'start_fen', 'eco', 'opening_name', 'user_side', 'ply_count',
        'imported_at',
      ]);
      expect(cols('analyses'), [
        'game_id', 'engine', 'depth', 'multipv', 'status', 'completed_plies', 'white_accuracy',
        'black_accuracy', 'updated_at',
      ]);
      expect(cols('position_lines'), ['game_id', 'ply', 'rank', 'score_cp', 'score_mate', 'depth', 'pv_uci']);
      expect(cols('move_labels'), ['game_id', 'ply', 'label', 'ep_loss', 'win_before', 'win_after', 'best_uci']);
      expect(cols('llm_cache'), ['key', 'kind', 'content', 'model', 'created_at', 'game_id']);
      expect(cols('settings'), ['key', 'value']);
      expect(cols('http_cache'), ['key', 'etag', 'body', 'updated_at']);
    });

    test('M8 indexes exist, the library query and both cache trims use them', () {
      final db = Db.inMemory();
      addTearDown(db.close);
      final indexes = db.raw
          .select("SELECT name FROM sqlite_master WHERE type = 'index' AND name NOT LIKE 'sqlite_%'")
          .map((r) => r['name'])
          .toSet();
      expect(indexes, containsAll(['games_imported', 'llm_cache_created', 'http_cache_updated', 'llm_cache_game']));
      String plan(String sql) => db.raw.select('EXPLAIN QUERY PLAN $sql').map((r) => r['detail']).join(' | ');
      final library = plan('SELECT g.id FROM games g LEFT JOIN analyses a ON a.game_id = g.id ORDER BY g.imported_at DESC, g.id DESC');
      expect(library, contains('games_imported'));
      expect(library, isNot(contains('TEMP B-TREE')), reason: 'no sort step: the index gives the order');
      expect(plan('SELECT key FROM llm_cache ORDER BY created_at DESC'), contains('llm_cache_created'));
      expect(plan('SELECT key FROM http_cache ORDER BY updated_at DESC'), contains('http_cache_updated'));
      // Lines and labels are read by their primary keys.
      expect(plan('SELECT * FROM position_lines WHERE game_id = 1 AND ply >= 3 ORDER BY ply, rank'), contains('sqlite_autoindex_position_lines_1'));
      expect(plan('SELECT * FROM move_labels WHERE game_id = 1 ORDER BY ply'), contains('sqlite_autoindex_move_labels_1'));
    });

    test('a version 4 database upgrades to 5 and keeps its rows', () async {
      final path = '${Directory.systemTemp.createTempSync('glyph_db_test').path}/v4.db';
      addTearDown(() => File(path).parent.deleteSync(recursive: true));
      final v4 = Db.open(path, migrations: Db.migrations.take(4).toList());
      final id = (await SqliteGameRepository(v4).save(newGame(sourceId: 'keep'))).id;
      v4.close();
      final db = Db.open(path);
      addTearDown(db.close);
      expect(db.raw.userVersion, 5);
      expect((await SqliteGameRepository(db).get(id))!.sourceId, 'keep');
    });

    test('foreign keys are on and CHECK constraints hold', () {
      final db = Db.inMemory();
      addTearDown(db.close);
      expect(db.raw.select('PRAGMA foreign_keys').first.values.first, 1);
      expect(() => db.raw.execute("INSERT INTO games (source, pgn, ply_count, imported_at) VALUES ('web','x',1,1)"),
          throwsA(isA<SqliteException>()));
      expect(
          () => db.raw.execute(
              "INSERT INTO analyses (game_id, engine, depth, multipv, status, updated_at) VALUES (1,'e',1,1,'running',1)"),
          throwsA(isA<SqliteException>()),
          reason: 'no such game');
      db.raw.execute("INSERT INTO games (source, pgn, ply_count, imported_at) VALUES ('paste','x',1,1)");
      expect(
          () => db.raw.execute(
              "INSERT INTO position_lines (game_id, ply, rank, depth, pv_uci) VALUES (1,0,3,1,'e2e4')"),
          throwsA(isA<SqliteException>()),
          reason: 'rank must be 1 or 2');
    });

    test('a file database persists and re-opening does not re-migrate', () async {
      final dir = Directory.systemTemp.createTempSync('glyph_db_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/glyph.db';
      var db = Db.open(path);
      final id = (await SqliteGameRepository(db).save(newGame())).id;
      db.close();
      db = Db.open(path);
      addTearDown(db.close);
      expect(db.raw.userVersion, Db.schemaVersion);
      expect((await SqliteGameRepository(db).get(id))!.white, 'Alice');
    });

    test('migrations run from the stored version and a newer database is refused', () {
      final dir = Directory.systemTemp.createTempSync('glyph_db_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/glyph.db';
      final raw = sqlite3.open(path)..userVersion = 99;
      raw.close();
      expect(() => Db.open(path), throwsA(isA<DatabaseTooNewException>().having((e) => (e.found, e.supported), 'versions', (99, Db.schemaVersion))));
    });

    test('a failing migration rolls back and keeps the old version', () {
      final path = '${Directory.systemTemp.createTempSync('glyph_db_test').path}/m.db';
      addTearDown(() => File(path).parent.deleteSync(recursive: true));
      final steps = <void Function(Database)>[
        ...Db.migrations,
        (db) {
          db.execute('CREATE TABLE extra (x)');
          db.execute('CREATE TABLE games (x)'); // already exists -> fails
        },
      ];
      expect(() => Db.open(path, migrations: steps), throwsA(isA<SqliteException>()));
      final raw = sqlite3.open(path);
      addTearDown(raw.close);
      expect(raw.userVersion, Db.schemaVersion);
      expect(raw.select("SELECT name FROM sqlite_master WHERE name = 'extra'"), isEmpty);
      // A later, fixed migration then applies from the stored version.
      final fixed = [...Db.migrations, (Database db) => db.execute('CREATE TABLE extra (x)')];
      final db = Db.open(path, migrations: fixed);
      addTearDown(db.close);
      expect(db.raw.userVersion, Db.schemaVersion + 1);
    });

    test('upgrading a version 1 database (M5) keeps its cached explanations and adds llm_cache.game_id', () {
      final path = '${Directory.systemTemp.createTempSync('glyph_db_test').path}/v1.db';
      addTearDown(() => File(path).parent.deleteSync(recursive: true));
      final v1 = Db.open(path, migrations: [Db.migrations.first]);
      expect(v1.raw.userVersion, 1);
      v1.raw.execute("INSERT INTO llm_cache (key, kind, content, model, created_at) VALUES ('k','move','text','m',5)");
      v1.close();
      final db = Db.open(path);
      addTearDown(db.close);
      expect(db.raw.userVersion, Db.schemaVersion);
      final row = db.raw.select('SELECT * FROM llm_cache').single;
      expect(row['content'], 'text');
      expect(row['game_id'], isNull);
    });

    test('upgrading a version 2 database with data to v3 keeps every row, FKs and indexes, and ids stop being reused', () async {
      final path = '${Directory.systemTemp.createTempSync('glyph_db_test').path}/v2.db';
      addTearDown(() => File(path).parent.deleteSync(recursive: true));
      final v2 = Db.open(path, migrations: Db.migrations.take(2).toList());
      expect(v2.raw.userVersion, 2);
      final games = SqliteGameRepository(v2);
      final a = (await games.save(newGame(sourceId: 'a'))).id;
      final b = (await games.save(newGame(sourceId: 'b', white: 'Carol'))).id;
      final c = (await games.save(newGame(sourceId: 'c'))).id;
      v2.raw.execute('DELETE FROM games WHERE id = $c'); // v2 would hand c out again
      final analyses = SqliteAnalysisRepository(v2);
      await analyses.upsert(
        AnalysisRecord(gameId: b, engine: 'sf', depth: 12, multipv: 2, status: AnalysisStatus.completed, completedPlies: 2, updatedAt: 7),
      );
      await analyses.putLabels(b, [MoveLabelRecord(gameId: b, ply: 1, label: MoveLabel.best)]);
      v2.raw.execute("INSERT INTO position_lines (game_id, ply, rank, depth, pv_uci) VALUES ($b, 0, 1, 12, 'e2e4')");
      v2.raw.execute("INSERT INTO settings VALUES ('keep','me')");
      v2.raw.execute("INSERT INTO llm_cache (key, kind, content, model, created_at, game_id) VALUES ('mine','move','t','m',5,$b)");
      v2.raw.execute("INSERT INTO llm_cache (key, kind, content, model, created_at, game_id) VALUES ('free','move','t','m',5,NULL)");
      v2.raw.execute("INSERT INTO llm_cache (key, kind, content, model, created_at, game_id) VALUES ('orphan','move','t','m',5,99)");
      v2.close();

      final db = Db.open(path);
      addTearDown(db.close);
      expect(db.raw.userVersion, Db.schemaVersion);
      expect(db.raw.select('PRAGMA foreign_keys').first.values.first, 1, reason: 'switched back on after the rebuild');
      expect(db.raw.select('PRAGMA foreign_key_check'), isEmpty);
      // Data survived, ids included.
      expect(db.raw.select('SELECT id FROM games ORDER BY id').map((r) => r['id']), [a, b]);
      expect((await SqliteGameRepository(db).get(b))!.white, 'Carol');
      expect(db.raw.select('SELECT COUNT(*) AS n FROM analyses WHERE game_id = $b').first['n'], 1);
      expect(db.raw.select('SELECT COUNT(*) AS n FROM move_labels WHERE game_id = $b').first['n'], 1);
      expect(db.raw.select('SELECT COUNT(*) AS n FROM position_lines WHERE game_id = $b').first['n'], 1);
      expect(db.raw.select("SELECT value FROM settings WHERE key = 'keep'").single['value'], 'me');
      expect(db.raw.select('SELECT key FROM llm_cache ORDER BY key').map((r) => r['key']), ['free', 'mine'], reason: 'the orphan row is dropped');
      // Indexes and the (source, source_id) uniqueness are back.
      expect(db.raw.select("SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'llm_cache_game'"), isNotEmpty);
      expect((await SqliteGameRepository(db).save(newGame(sourceId: 'a'))).duplicate, isTrue);
      // The children still cascade from the rebuilt games table.
      await SqliteGameRepository(db).delete(b);
      expect(db.raw.select('SELECT COUNT(*) AS n FROM analyses').first['n'], 0);
      expect(db.raw.select('SELECT COUNT(*) AS n FROM move_labels').first['n'], 0);
      expect(db.raw.select('SELECT COUNT(*) AS n FROM position_lines').first['n'], 0);
      expect(db.raw.select("SELECT COUNT(*) AS n FROM llm_cache WHERE key = 'mine'").first['n'], 0);
      // AUTOINCREMENT: the deleted ids (b, and the c that v2 left free) are never reissued.
      final fresh = (await SqliteGameRepository(db).save(newGame(sourceId: 'z'))).id;
      expect(fresh, greaterThan(b));
      final sequence = db.raw.select("SELECT seq FROM sqlite_sequence WHERE name = 'games'").single['seq'] as int;
      expect(sequence, fresh);
    });

    test('transaction rolls back on error', () {
      final db = Db.inMemory();
      addTearDown(db.close);
      expect(
        () => db.transaction(() {
          db.raw.execute("INSERT INTO settings VALUES ('a','1')");
          throw StateError('boom');
        }),
        throwsStateError,
      );
      expect(db.raw.select('SELECT * FROM settings'), isEmpty);
    });
  });
}
