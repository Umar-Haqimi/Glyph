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

typedef Repos = ({GameRepository games, AnalysisRepository analyses, SettingsRepository settings});

/// Behaviour every implementation of the repositories must have.
void contract(String name, Repos Function() create) {
  group(name, () {
    late Repos r;
    setUp(() => r = create());

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
    );
  });

  contract('SQLite repositories (in-memory database)', () {
    final db = Db.inMemory();
    addTearDown(db.close);
    return (
      games: SqliteGameRepository(db),
      analyses: SqliteAnalysisRepository(db),
      settings: SqliteSettingsRepository(db),
    );
  });

  group('Db', () {
    test('creates the SPEC 5.4 schema at user_version 1', () {
      final db = Db.inMemory();
      addTearDown(db.close);
      expect(db.raw.userVersion, 1);
      expect(Db.schemaVersion, 1);
      final tables = db.raw
          .select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name")
          .map((r) => r['name'])
          .toList();
      expect(tables, ['analyses', 'games', 'llm_cache', 'move_labels', 'position_lines', 'settings']);
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
      expect(cols('llm_cache'), ['key', 'kind', 'content', 'model', 'created_at']);
      expect(cols('settings'), ['key', 'value']);
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
      expect(db.raw.userVersion, 1);
      expect((await SqliteGameRepository(db).get(id))!.white, 'Alice');
    });

    test('migrations run from the stored version and a newer database is refused', () {
      final dir = Directory.systemTemp.createTempSync('glyph_db_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = '${dir.path}/glyph.db';
      final raw = sqlite3.open(path)..userVersion = 99;
      raw.close();
      expect(() => Db.open(path), throwsStateError);
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
      expect(raw.userVersion, 1);
      expect(raw.select("SELECT name FROM sqlite_master WHERE name = 'extra'"), isEmpty);
      // A later, fixed migration then applies from version 1.
      final fixed = [...Db.migrations, (Database db) => db.execute('CREATE TABLE extra (x)')];
      final db = Db.open(path, migrations: fixed);
      addTearDown(db.close);
      expect(db.raw.userVersion, 2);
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
