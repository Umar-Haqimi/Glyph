import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

/// The database file was written by a newer Glyph (its `user_version` is above
/// what this build knows). Opening it would risk damaging data this build does
/// not understand, so it is refused; the fix is to update Glyph. The numbers
/// are not secret, but like every error here only the type is ever logged.
class DatabaseTooNewException implements Exception {
  const DatabaseTooNewException({required this.found, required this.supported});

  final int found;
  final int supported;

  @override
  String toString() => 'DatabaseTooNewException(found: $found, supported: $supported)';
}

/// Why opening the database failed, as far as the user can act on it.
enum DbOpenProblem {
  /// A newer Glyph wrote the file: update Glyph (never delete by reflex).
  newerVersion,

  /// The disk is full (SQLITE_FULL, or ENOSPC from the file system): free some
  /// space and try again.
  diskFull,

  /// Anything else (a damaged file, a locked file, ...).
  other,
}

/// Sorts a failure of [Db.open] / the recovery step after it.
DbOpenProblem classifyDbOpenFailure(Object error) {
  if (error is DatabaseTooNewException) return DbOpenProblem.newerVersion;
  // SQLITE_FULL = 13 (the low byte of every extended code of it too).
  if (error is SqliteException && (error.extendedResultCode & 0xff) == 13) return DbOpenProblem.diskFull;
  // ENOSPC = 28 on Linux / Android; ERROR_DISK_FULL = 112 on Windows.
  if (error is FileSystemException && (error.osError?.errorCode == 28 || error.osError?.errorCode == 112)) {
    return DbOpenProblem.diskFull;
  }
  return DbOpenProblem.other;
}

/// Thin wrapper around a sqlite3 [Database]: foreign keys on, `user_version`
/// migrations, transactions. All SQL in the app is raw SQL (SPEC 5.4).
class Db {
  Db._(this.raw, this._migrations);

  /// Opens (creating and migrating if needed) the database file at [path].
  /// [migrations] defaults to [Db.migrations] (a parameter for tests).
  /// Throws [DatabaseTooNewException] for a file from a newer Glyph. When it
  /// throws, the native handle is closed again: a leaked handle would keep (and
  /// on its later finalisation checkpoint / delete) the WAL files of a database
  /// the app then deletes and recreates.
  factory Db.open(String path, {List<void Function(Database db)>? migrations}) =>
      Db._initOrClose(sqlite3.open(path), migrations ?? Db.migrations);

  /// A fresh in-memory database (tests).
  factory Db.inMemory({List<void Function(Database db)>? migrations}) =>
      Db._initOrClose(sqlite3.openInMemory(), migrations ?? Db.migrations);

  static Db _initOrClose(Database raw, List<void Function(Database db)> migrations) {
    final db = Db._(raw, migrations);
    try {
      db._init();
    } on Object {
      raw.close();
      rethrow;
    }
    return db;
  }

  final Database raw;
  final List<void Function(Database db)> _migrations;

  /// The schema version this build creates. Equals `migrations.length`.
  static int get schemaVersion => migrations.length;

  /// Migration `i` upgrades `user_version` i to i + 1. Never edit a shipped
  /// migration; append a new one.
  static final List<void Function(Database db)> migrations = [_v1, _v2, _v3, _v4, _v5];

  void _init() {
    raw.execute('PRAGMA foreign_keys = ON');
    // Defence in depth: should a second process ever open the file, wait for
    // the lock instead of failing with SQLITE_BUSY. WAL lets readers and the
    // writer overlap (a no-op for in-memory databases).
    raw.execute('PRAGMA busy_timeout = 5000');
    // Refuse a file from a newer Glyph before anything is changed in it (the
    // journal mode below rewrites the file header).
    final target = _migrations.length;
    if (raw.userVersion > target) {
      throw DatabaseTooNewException(found: raw.userVersion, supported: target);
    }
    raw.execute('PRAGMA journal_mode = WAL');
    _migrate();
  }

  void _migrate() {
    var version = raw.userVersion;
    final target = _migrations.length;
    while (version < target) {
      // Foreign keys are off while a migration rebuilds tables (the pragma is
      // a no-op inside a transaction, so it is set here): dropping `games`
      // with them on would cascade-delete every child row. Before the commit
      // `foreign_key_check` must come back empty.
      raw.execute('PRAGMA foreign_keys = OFF');
      raw.execute('BEGIN');
      try {
        _migrations[version](raw);
        final violations = raw.select('PRAGMA foreign_key_check');
        if (violations.isNotEmpty) {
          throw StateError('Migration ${version + 1} left ${violations.length} foreign key violations.');
        }
        raw.userVersion = version + 1;
        raw.execute('COMMIT');
      } catch (_) {
        raw.execute('ROLLBACK');
        rethrow;
      } finally {
        raw.execute('PRAGMA foreign_keys = ON');
      }
      version++;
    }
  }

  /// Runs [body] in a transaction (rolled back if it throws).
  T transaction<T>(T Function() body) {
    raw.execute('BEGIN');
    try {
      final result = body();
      raw.execute('COMMIT');
      return result;
    } catch (_) {
      raw.execute('ROLLBACK');
      rethrow;
    }
  }

  void close() => raw.close();
}

void _v1(Database db) {
  db.execute('''
CREATE TABLE games (
  id INTEGER PRIMARY KEY,
  source TEXT NOT NULL CHECK (source IN ('paste','file','share','lichess','chesscom')),
  source_id TEXT,
  pgn TEXT NOT NULL,
  white TEXT, black TEXT, white_elo INTEGER, black_elo INTEGER,
  result TEXT, date TEXT, time_control TEXT, event TEXT,
  variant TEXT NOT NULL DEFAULT 'standard' CHECK (variant IN ('standard','chess960')),
  start_fen TEXT,
  eco TEXT, opening_name TEXT,
  user_side TEXT CHECK (user_side IN ('white','black')),
  ply_count INTEGER NOT NULL,
  imported_at INTEGER NOT NULL,
  UNIQUE (source, source_id)
)''');
  db.execute('''
CREATE TABLE analyses (
  game_id INTEGER PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
  engine TEXT NOT NULL,
  depth INTEGER NOT NULL, multipv INTEGER NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('running','paused','cancelled','completed','failed')),
  completed_plies INTEGER NOT NULL DEFAULT 0,
  white_accuracy REAL, black_accuracy REAL,
  updated_at INTEGER NOT NULL
)''');
  db.execute('''
CREATE TABLE position_lines (
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  ply INTEGER NOT NULL,
  rank INTEGER NOT NULL CHECK (rank IN (1,2)),
  score_cp INTEGER, score_mate INTEGER,
  depth INTEGER NOT NULL,
  pv_uci TEXT NOT NULL,
  PRIMARY KEY (game_id, ply, rank)
)''');
  db.execute('''
CREATE TABLE move_labels (
  game_id INTEGER NOT NULL REFERENCES games(id) ON DELETE CASCADE,
  ply INTEGER NOT NULL,
  label TEXT NOT NULL,
  ep_loss REAL, win_before REAL, win_after REAL,
  best_uci TEXT,
  PRIMARY KEY (game_id, ply)
)''');
  db.execute('''
CREATE TABLE llm_cache (
  key TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('move','summary')),
  content TEXT NOT NULL, model TEXT NOT NULL, created_at INTEGER NOT NULL
)''');
  db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT NOT NULL)');
}

/// M6: `llm_cache.game_id`, so a deleted or re-analysed game takes its cached
/// explanations with it (the SPEC 5.4 table has no owner column).
void _v2(Database db) {
  db.execute('ALTER TABLE llm_cache ADD COLUMN game_id INTEGER');
  db.execute('CREATE INDEX llm_cache_game ON llm_cache (game_id)');
}

/// M6 review fix: `games.id` becomes `AUTOINCREMENT`, so the id of a deleted
/// game is never handed to a new one (per-game state and caches keyed by id
/// can then never bleed into another game), and `llm_cache.game_id` becomes a
/// real foreign key (`ON DELETE CASCADE`), so no saved text can outlive, or be
/// written for, a game that does not exist.
///
/// SQLite cannot alter either, so both tables are rebuilt (the documented
/// "12 steps": create new, copy, drop old, rename, recreate indexes). The
/// runner switches foreign keys off around the migration and checks
/// `foreign_key_check` before committing. `sqlite_sequence` starts at the
/// highest id in use, which is all the old table could guarantee. Orphan
/// `llm_cache` rows (an unknown `game_id`) are dropped.
void _v3(Database db) {
  db.execute('''
CREATE TABLE games_new (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  source TEXT NOT NULL CHECK (source IN ('paste','file','share','lichess','chesscom')),
  source_id TEXT,
  pgn TEXT NOT NULL,
  white TEXT, black TEXT, white_elo INTEGER, black_elo INTEGER,
  result TEXT, date TEXT, time_control TEXT, event TEXT,
  variant TEXT NOT NULL DEFAULT 'standard' CHECK (variant IN ('standard','chess960')),
  start_fen TEXT,
  eco TEXT, opening_name TEXT,
  user_side TEXT CHECK (user_side IN ('white','black')),
  ply_count INTEGER NOT NULL,
  imported_at INTEGER NOT NULL,
  UNIQUE (source, source_id)
)''');
  db.execute('''
INSERT INTO games_new (id, source, source_id, pgn, white, black, white_elo, black_elo, result, date,
  time_control, event, variant, start_fen, eco, opening_name, user_side, ply_count, imported_at)
SELECT id, source, source_id, pgn, white, black, white_elo, black_elo, result, date,
  time_control, event, variant, start_fen, eco, opening_name, user_side, ply_count, imported_at
FROM games''');
  db.execute('DROP TABLE games');
  db.execute('ALTER TABLE games_new RENAME TO games');

  db.execute('''
CREATE TABLE llm_cache_new (
  key TEXT PRIMARY KEY,
  kind TEXT NOT NULL CHECK (kind IN ('move','summary')),
  content TEXT NOT NULL, model TEXT NOT NULL, created_at INTEGER NOT NULL,
  game_id INTEGER REFERENCES games(id) ON DELETE CASCADE
)''');
  db.execute('''
INSERT INTO llm_cache_new (key, kind, content, model, created_at, game_id)
SELECT key, kind, content, model, created_at, game_id FROM llm_cache
WHERE game_id IS NULL OR game_id IN (SELECT id FROM games)''');
  db.execute('DROP TABLE llm_cache');
  db.execute('ALTER TABLE llm_cache_new RENAME TO llm_cache');
  db.execute('CREATE INDEX llm_cache_game ON llm_cache (game_id)');
}

/// M7: `http_cache`, the `ETag`s of the chess.com archive requests together with
/// the (trimmed) data they stand for, so a 304 can be answered from disk. Holds
/// public game data keyed by request URL; bounded by the repository.
void _v4(Database db) {
  db.execute('''
CREATE TABLE http_cache (
  key TEXT PRIMARY KEY,
  etag TEXT NOT NULL,
  body TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)''');
}

/// M8: indexes for the queries the app runs on every start or every list refresh.
///
/// * `games_imported`: the library lists every game newest import first
///   (`ORDER BY imported_at DESC, id DESC`); without it SQLite sorts the whole
///   table each time.
/// * `llm_cache_created`: `put` trims the cache to the newest rows
///   (`ORDER BY created_at DESC`).
/// * `http_cache_updated`: the same trim for `http_cache`.
///
/// `position_lines` and `move_labels` are read by `(game_id, ply...)`, which
/// their primary keys already cover; `analyses` is keyed by `game_id`.
void _v5(Database db) {
  db.execute('CREATE INDEX games_imported ON games (imported_at DESC, id DESC)');
  db.execute('CREATE INDEX llm_cache_created ON llm_cache (created_at DESC)');
  db.execute('CREATE INDEX http_cache_updated ON http_cache (updated_at DESC)');
}
