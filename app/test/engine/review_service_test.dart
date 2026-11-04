import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/db.dart';
import 'package:glyph/data/in_memory.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/data/repositories.dart';
import 'package:glyph/data/sqlite_repositories.dart';
import 'package:glyph/engine/repository_analysis_store.dart';
import 'package:glyph/engine/review_service.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:glyph_core/testing.dart';

const _dir = '../packages/glyph_core/test/vectors/uci_transcripts';

Transcript transcript(String name) => Transcript.parse(File('$_dir/$name.txt').readAsStringSync());

TranscriptGame game(String name) =>
    parseTranscriptGames(File('$_dir/games.json').readAsStringSync()).firstWhere((g) => g.name == name);

OpeningBook book() => OpeningBook.parseTsv(File('assets/openings.tsv').readAsStringSync());

class Env {
  Env.sqlite() {
    final db = Db.inMemory();
    games = SqliteGameRepository(db);
    analyses = SqliteAnalysisRepository(db);
    settings = SqliteSettingsRepository(db);
  }

  Env.memory() {
    final store = InMemoryStore();
    games = InMemoryGameRepository(store);
    analyses = InMemoryAnalysisRepository(store);
    settings = InMemorySettingsRepository();
  }

  late final GameRepository games;
  late final AnalysisRepository analyses;
  late final SettingsRepository settings;

  ReviewService review() => ReviewService(games: games, analyses: analyses, settings: settings, book: () async => book());

  /// Saves the transcript game and analyses it through the real pipeline and
  /// the app's store adapter, as the EngineService would.
  Future<int> analysed(String name) async {
    final g = game(name);
    final id = (await games.save(NewGame(source: GameSource.paste, pgn: g.toPgn(), plyCount: g.moves.length, importedAt: 1))).id;
    final pipeline = AnalysisPipeline(
      createDriver: () async => FakeEngineDriver(transcript(name)),
      store: RepositoryAnalysisStore(analyses, games: games),
    );
    final result = await pipeline.analyze(AnalysisRequest(
      gameId: id,
      startFen: g.startFen,
      moves: g.moves,
      depth: 16,
      multipv: 2,
      threads: 1,
      hashMb: 16,
    ));
    await pipeline.dispose();
    expect(result, isA<AnalysisCompleted>());
    return id;
  }
}

void main() {
  for (final (kind, make) in [('SQLite', Env.sqlite), ('in-memory', Env.memory)]) {
    group('ReviewService ($kind repositories)', () {
      test('labels and accuracy of the Opera game survive the store round trip', () async {
        final env = make();
        final id = await env.analysed('mate_opera');
        final review = await env.review().classify(id);
        expect(review, isNotNull);

        final labels = await env.analyses.labels(id);
        expect(labels, hasLength(33));
        final byPly = {for (final l in labels) l.ply: l};
        expect(byPly[1]!.label, MoveLabel.book);
        expect(byPly[25]!.label, MoveLabel.brilliant, reason: '13.Rxd7!');
        expect(byPly[32]!.label, MoveLabel.forced);
        expect(byPly[33]!.label, MoveLabel.best, reason: '17.Rd8# (terminal marker row in the store)');
        expect(byPly[33]!.bestUci, 'd1d8');
        expect(byPly[23]!.epLoss, 0, reason: 'O-O-O = line 1');
        expect(byPly[12]!.winBefore! - byPly[12]!.winAfter!, closeTo(byPly[12]!.epLoss! * 100, 1e-9));

        // Same labels as the core computes straight from the transcript.
        final g = game('mate_opera');
        final direct = review!.moves;
        expect([for (final l in labels) l.label], [for (final m in direct) m!.label]);
        expect(direct, hasLength(g.moves.length));

        final a = (await env.analyses.get(id))!;
        expect(a.status, AnalysisStatus.completed);
        expect(a.whiteAccuracy, closeTo(review.accuracy.white!, 1e-9));
        expect(a.blackAccuracy, closeTo(review.accuracy.black!, 1e-9));
        expect(a.whiteAccuracy!, greaterThan(a.blackAccuracy!));
        final record = (await env.games.get(id))!;
        expect(record.whiteAccuracy, a.whiteAccuracy);
      });

      test('P0: mirrored blunder games get the same label for the blunder', () async {
        final env = make();
        final w = await env.analysed('p0_blunder_white');
        final b = await env.analysed('p0_blunder_black');
        await env.review().classify(w);
        await env.review().classify(b);
        final lw = await env.analyses.labels(w);
        final lb = await env.analyses.labels(b);
        expect(lw[5].label, MoveLabel.blunder);
        expect(lb[5].label, MoveLabel.blunder);
        expect(lw[6].label, MoveLabel.best);
        expect(lb[6].label, MoveLabel.best);
      });

      test('unfinished analyses and games without stored lines are left alone', () async {
        final env = make();
        final id = (await env.games.save(const NewGame(source: GameSource.paste, pgn: '1. e4 e5 *', plyCount: 2, importedAt: 1))).id;
        expect(await env.review().classify(id), isNull, reason: 'no analysis');
        await env.analyses.upsert(AnalysisRecord(
          gameId: id,
          engine: 'x',
          depth: 16,
          multipv: 2,
          status: AnalysisStatus.completed,
          completedPlies: 3,
          whiteAccuracy: 42,
          updatedAt: 1,
        ));
        expect(await env.review().classify(id), isNull, reason: 'no lines stored');
        expect((await env.analyses.get(id))!.whiteAccuracy, 42, reason: 'nothing overwritten');
        expect(await env.analyses.labels(id), isEmpty);
      });

      test('ensureClassified only classifies a completed game whose labels are missing', () async {
        final env = make();
        final id = await env.analysed('p0_blunder_white');
        final service = env.review();
        expect(await service.ensureClassified(id), isTrue);
        expect(await env.analyses.labels(id), hasLength(7));
        expect(await service.ensureClassified(id), isFalse);
        expect(await service.ensureClassified(999), isFalse);
      });

      test('reclassifyIfStale re-labels completed games once per classifier version', () async {
        final env = make();
        final id = await env.analysed('p0_blunder_white');
        final service = env.review();
        expect(await service.reclassifyIfStale(), 1);
        expect(await env.settings.get(SettingsKeys.classifierVersion), '${ClassifierConfig.standard.version}');
        expect(await env.analyses.labels(id), hasLength(7));
        expect(await service.reclassifyIfStale(), 0);

        // A new classifier version re-labels from the stored lines.
        final strict = ReviewService(
          games: env.games,
          analyses: env.analyses,
          settings: env.settings,
          book: () async => OpeningBook(const {}),
          config: const ClassifierConfig(version: 2),
        );
        expect(await strict.reclassifyIfStale(), 1);
        expect((await env.analyses.labels(id)).first.label, isNot(MoveLabel.book), reason: 'no book in this one');
        expect(await env.settings.get(SettingsKeys.classifierVersion), '2');
      });
    });
  }
}
