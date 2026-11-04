import 'dart:convert';
import 'dart:io';

import 'package:dartchess/dartchess.dart' hide File;
import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import '../support/review.dart';
import '../support/transcripts.dart';

const snapshotDir = 'test/vectors/prompts';

/// Compares [actual] with test/vectors/prompts/[name]; run with
/// `UPDATE_SNAPSHOTS=1 dart test test/llm/prompt_builder_test.dart` to rewrite
/// the files after an intended change (and bump `PromptBuilder.version`).
void expectSnapshot(String name, String actual) {
  final file = File('$snapshotDir/$name');
  if (Platform.environment['UPDATE_SNAPSHOTS'] == '1') {
    file.writeAsStringSync(actual);
    return;
  }
  expect(file.existsSync(), isTrue, reason: 'missing snapshot $name (run with UPDATE_SNAPSHOTS=1)');
  expect(actual, file.readAsStringSync(), reason: 'prompt snapshot $name changed: bump PromptBuilder.version and update it');
}

String render(PromptBundle b) =>
    '${[for (final m in b.messages) '=== ${m.role.name} ===\n${m.content}'].join('\n\n').trimRight()}\n';

/// Names, ratings and the like that must never reach a prompt.
const identifying = {
  'White': 'Magnus_the_Great',
  'Black': 'DrSecretUser99',
  'WhiteElo': '2863',
  'BlackElo': '2701',
  'Event': 'Titled Tuesday Blitz Arena',
  'Site': 'https://lichess.org/AbCdEfGh',
  'Date': '2026.10.23',
  'UTCDate': '2026.10.23',
  'TimeControl': '180+2',
  'Termination': 'DrSecretUser99 resigned',
};

class Fixture {
  Fixture(this.game, this.lines, this.moves, this.book);

  final Game game;
  final Map<int, List<EngineLine>> lines;
  final List<ClassifiedMove?> moves;
  final BookAnnotation book;
}

Future<Fixture> fixture(String name, {Transcript? transcript, bool withBook = false, String result = '*'}) async {
  final g = transcriptGame(name);
  final lines = transcript == null
      ? await analyseFromTranscript(name, startFen: g.startFen, moves: g.moves)
      : await analyseWith(transcript, startFen: g.startFen, moves: g.moves, label: name);
  final base = gameFrom(g.startFen, g.moves);
  final game = Game(headers: identifying, startFen: g.startFen, variant: GameVariant.standard, plies: base.plies, result: result, pgn: '');
  final book = withBook ? realOpeningBook().annotate(game) : BookAnnotation.none;
  final moves = const Classifier().classify(startFen: g.startFen, moves: g.moves, lines: lines, bookPlies: book.bookPlies);
  return Fixture(game, lines, moves, book);
}

PromptBundle moveBundle(Fixture f, int ply, {Side? userSide, ExplainPrefs prefs = const ExplainPrefs()}) => PromptBuilder.move(
      game: f.game,
      ply: ply,
      move: f.moves[ply - 1]!,
      lines: f.lines,
      book: f.book,
      userSide: userSide,
      prefs: prefs,
    );

Map<String, dynamic> userJson(PromptBundle b) => jsonDecode(b.messages.last.content) as Map<String, dynamic>;

int firstPly(Fixture f, MoveLabel label) => f.moves.indexWhere((m) => m?.label == label) + 1;

Iterable<String> stringsOf(Object? v) sync* {
  if (v is String) yield v;
  if (v is List) {
    for (final e in v) {
      yield* stringsOf(e);
    }
  }
  if (v is Map) {
    for (final e in v.values) {
      yield* stringsOf(e);
    }
  }
}

void main() {
  late Fixture blunder;
  late Fixture fried;
  late Fixture opera;
  setUpAll(() async {
    blunder = await fixture('p0_blunder_white');
    fried = await fixture('blunder_white');
    opera = await fixture('mate_opera', withBook: true, result: '1-0');
  });

  group('move prompt', () {
    test('snapshot: a blunder by Black, explained to Black (isUserMove)', () {
      final ply = firstPly(blunder, MoveLabel.blunder);
      expect(ply, greaterThan(0));
      expectSnapshot('move_blunder_user.txt', render(moveBundle(blunder, ply, userSide: Side.black)));
    });

    test('snapshot: the same move seen from White, beginner / coach / Bahasa Melayu', () {
      final ply = firstPly(blunder, MoveLabel.blunder);
      final b = moveBundle(
        blunder,
        ply,
        userSide: Side.white,
        prefs: const ExplainPrefs(language: 'Bahasa Melayu', tone: ExplainTone.coach, audience: ExplainAudience.beginner),
      );
      expectSnapshot('move_blunder_opponent_other_prefs.txt', render(b));
      final json = userJson(b);
      expect(json['move']['isUserMove'], isFalse);
      expect(json['language'], 'Bahasa Melayu');
      expect(json['tone'], 'coach');
      expect(json['audience'], 'beginner');
    });

    test('snapshot: a book move with the opening name', () {
      expectSnapshot('move_book_opera.txt', render(moveBundle(opera, 2, userSide: Side.black)));
    });

    test('snapshot: the mating move', () {
      expectSnapshot('move_mate_opera.txt', render(moveBundle(opera, opera.game.plyCount, userSide: Side.white)));
    });

    test('the system message carries the rules of SPEC 5.5', () {
      final system = moveBundle(blunder, 3).messages.first;
      expect(system.role, ChatRole.system);
      for (final phrase in [
        'at most 120 words',
        'bestMove.line, secondBest.line and refutation',
        'Never invent variations',
        'consistent with fenBefore',
        'tactical motif',
        'only if one of the provided lines demonstrates it',
        'speak to the player as "you"',
        'Better was',
        'Plain text only',
        '"language"',
      ]) {
        expect(system.content, contains(phrase));
      }
    });

    test('SAN only: no UCI-looking token anywhere but inside the FEN', () {
      final uci = RegExp(r'\b[a-h][1-8][a-h][1-8][qrbn]?\b');
      for (final f in [blunder, fried, opera]) {
        for (var ply = 1; ply <= f.game.plyCount; ply++) {
          if (f.moves[ply - 1] == null) continue;
          final json = userJson(moveBundle(f, ply));
          for (final entry in json.entries) {
            if (entry.key == 'fenBefore') continue;
            for (final s in stringsOf(entry.value)) {
              expect(uci.hasMatch(s), isFalse, reason: 'ply $ply ${entry.key}: "$s"');
            }
          }
        }
      }
    });

    test('castling is written O-O, never e1g1 or e1h1', () async {
      final f = await fixture('italian_castle');
      final castle = f.game.plies.indexWhere((p) => p.san == 'O-O') + 1;
      final json = userJson(moveBundle(f, castle));
      expect(json['move']['san'], 'O-O');
      expect((json['refutation'] as List).first, 'O-O');
      final text = jsonEncode(json);
      expect(text, isNot(contains('e1h1')));
      expect(text, isNot(contains('e1g1')));
    });

    test('no names, ratings, sites, dates, event names or time controls reach the prompt', () {
      for (final f in [blunder, opera]) {
        for (var ply = 1; ply <= f.game.plyCount; ply += 3) {
          if (f.moves[ply - 1] == null) continue;
          final text = moveBundle(f, ply, userSide: Side.white).messages.map((m) => m.content).join('\n');
          for (final value in identifying.values) {
            expect(text, isNot(contains(value)), reason: 'ply $ply leaks "$value"');
          }
          for (final fragment in ['Magnus', 'DrSecret', '2863', '2701', 'lichess.org', 'Titled', '2026.10']) {
            expect(text, isNot(contains(fragment)), reason: fragment);
          }
        }
      }
    });

    test('every number is from the mover\'s point of view: the mirrored game gives the same facts', () async {
      final mirrored = mirrorTranscript(loadTranscript('p0_blunder_white'));
      final g = transcriptGame('p0_blunder_white');
      // The mirrored game: same plies with colours and ranks flipped.
      final mirrorMoves = g.moves.map(mirrorUci).toList();
      final lines = await analyseWith(mirrored, startFen: mirrorFen(g.startFen), moves: mirrorMoves, label: 'mirror');
      final base = gameFrom(mirrorFen(g.startFen), mirrorMoves);
      final game = Game(headers: identifying, startFen: base.startFen, variant: GameVariant.standard, plies: base.plies, result: '*', pgn: '');
      final classified = const Classifier().classify(startFen: game.startFen, moves: mirrorMoves, lines: lines);
      final mirror = Fixture(game, lines, classified, BookAnnotation.none);

      var compared = 0;
      for (var ply = 1; ply <= blunder.game.plyCount; ply++) {
        final a = userJson(moveBundle(blunder, ply, userSide: Side.white));
        final b = userJson(moveBundle(mirror, ply, userSide: Side.black));
        expect(b['move']['side'], a['move']['side'] == 'white' ? 'black' : 'white', reason: 'ply $ply');
        expect(b['move']['isUserMove'], a['move']['isUserMove'], reason: 'ply $ply');
        for (final key in ['classification', 'winChanceBefore', 'winChanceAfter', 'evalBefore', 'evalAfter', 'material', 'flags', 'phase']) {
          expect(b[key], a[key], reason: 'ply $ply $key');
        }
        expect((b['refutation'] as List).length, (a['refutation'] as List).length, reason: 'ply $ply');
        expect((b['bestMove']?['line'] as List?)?.length, (a['bestMove']?['line'] as List?)?.length, reason: 'ply $ply');
        compared++;
      }
      expect(compared, blunder.game.plyCount);
    });

    test('a blunder shows a falling eval and win chance for the mover, and the engine\'s better line', () {
      final ply = firstPly(blunder, MoveLabel.blunder);
      final mover = blunder.moves[ply - 1]!.side;
      final json = userJson(moveBundle(blunder, ply));
      expect(json['move']['side'], mover.name);
      expect(json['winChanceAfter'] as double, lessThan((json['winChanceBefore'] as double) - 20));
      expect(json['classification'], 'blunder');
      expect(json['bestMove'], isNotNull);
      expect(json['bestMove']['line'], isNotEmpty);
      expect(json['bestMove']['san'], json['bestMove']['line'][0]);
      expect((json['refutation'] as List).first, json['move']['san']);
      expect((json['refutation'] as List).length, lessThanOrEqualTo(PromptBuilder.linePlies));
    });

    test('lines hold at most linePlies moves and are legal continuations of fenBefore', () {
      for (var ply = 1; ply <= blunder.game.plyCount; ply++) {
        final json = userJson(moveBundle(blunder, ply));
        Position pos = Chess.fromSetup(Setup.parseFen(json['fenBefore'] as String));
        for (final san in (json['bestMove']['line'] as List).cast<String>()) {
          final move = pos.parseSan(san);
          expect(move, isNotNull, reason: 'ply $ply best line move $san');
          pos = pos.play(move!);
        }
      }
    });

    test('a sacrifice is flagged (and a brilliant move is not a blunder)', () {
      final ply = firstPly(fried, MoveLabel.brilliant);
      expect(ply, greaterThan(0));
      final json = userJson(moveBundle(fried, ply));
      expect(json['flags']['sacrifice'], isTrue);
      expect(json['classification'], 'brilliant');
    });

    test('flags come from the classifier: sacrifice, only move, missed mate, punished error', () async {
      final mate2 = await fixture('missed_mate2');
      final miss = mate2.moves.indexWhere((m) => m?.missedMateIn != null) + 1;
      if (miss > 0) {
        final flags = userJson(moveBundle(mate2, miss))['flags'] as Map<String, dynamic>;
        expect(flags['missedMateIn'], mate2.moves[miss - 1]!.missedMateIn);
      }
      for (final f in [blunder, fried, mate2, opera]) {
        for (var ply = 1; ply <= f.game.plyCount; ply++) {
          final m = f.moves[ply - 1];
          if (m == null) continue;
          final flags = userJson(moveBundle(f, ply))['flags'] as Map<String, dynamic>;
          expect(flags['sacrifice'], m.sacrifice);
          expect(flags['onlyMove'], m.onlyMove);
          expect(flags['missedMateIn'], m.missedMateIn);
          expect(flags['opponentErrorPunished'], m.punishedOpponentError);
        }
      }
    });

    test('material and hanging pieces are computed by code', () async {
      final f = await fixture('miss_hanging_knight');
      var sawHanging = false;
      for (var ply = 1; ply <= f.game.plyCount; ply++) {
        final json = userJson(moveBundle(f, ply));
        final material = json['material'] as Map<String, dynamic>;
        expect(material['before'], isA<int>());
        expect(material['afterRefutation'], isA<int>());
        for (final h in (json['hangingAfterMove'] as List).cast<String>()) {
          expect(h, matches(RegExp(r'^(pawn|knight|bishop|rook|queen) on [a-h][1-8]$')));
          sawHanging = true;
        }
      }
      expect(sawHanging, isTrue, reason: 'Nd4 Nxd4 style positions leave something hanging');
      // First move: material level before; the engine line keeps it level.
      expect(userJson(moveBundle(f, 1))['material']['before'], 0);
    });

    test('the opening name appears only from the ply that reaches it', () {
      final withName = opera.book;
      expect(withName.opening, isNotNull);
      final reached = withName.openingPly!;
      for (var ply = 1; ply <= opera.game.plyCount; ply++) {
        final name = userJson(moveBundle(opera, ply))['opening'];
        expect(name, ply >= reached ? withName.opening!.name : isNull, reason: 'ply $ply');
      }
    });

    test('the game phase is deterministic: opening, middlegame, endgame', () {
      final phases = {for (var p = 1; p <= opera.game.plyCount; p++) userJson(moveBundle(opera, p))['phase']};
      expect(phases, containsAll(['opening', 'middlegame']));
      expect(phases, everyElement(isIn(['opening', 'middlegame', 'endgame'])));
    });

    test('a mating move: evalAfter says checkmate and there is no continuation', () {
      final json = userJson(moveBundle(opera, opera.game.plyCount));
      expect(json['evalAfter'], 'checkmate');
      expect(json['refutation'], ['Rd8#']);
      expect(json['move']['san'], 'Rd8#');
    });

    test('isUserMove is false without a user side and for the other side', () {
      final ply = 3; // White's second move
      expect(userJson(moveBundle(blunder, ply))['move']['isUserMove'], isFalse);
      expect(userJson(moveBundle(blunder, ply, userSide: Side.black))['move']['isUserMove'], isFalse);
      expect(userJson(moveBundle(blunder, ply, userSide: Side.white))['move']['isUserMove'], isTrue);
    });

    test('the bundle carries what the cache key needs', () {
      final b = moveBundle(blunder, 7, userSide: Side.white);
      expect(b.kind, PromptKind.move);
      expect(b.moveUci, blunder.game.plies[6].uci);
      expect(b.fenBefore, userJson(b)['fenBefore']);
      expect(b.label, blunder.moves[6]!.label.name);
      expect(b.userSide, 'white');
      expect(moveBundle(blunder, 7).userSide, 'none');
    });

    test('building is deterministic', () {
      expect(render(moveBundle(blunder, 6)), render(moveBundle(blunder, 6)));
    });
  });

  group('game summary prompt', () {
    GameReview reviewOf(Fixture f) => GameReview(
          moves: f.moves,
          accuracy: const GameAccuracy(white: 93.4, black: 54.6),
          keyMoments: KeyMoments.of(f.moves),
          book: f.book,
          classifierVersion: 1,
        );

    PromptBundle summaryBundle(Fixture f, {Side? userSide, ExplainPrefs prefs = const ExplainPrefs()}) =>
        PromptBuilder.summary(game: f.game, review: reviewOf(f), lines: f.lines, userSide: userSide, prefs: prefs);

    test('snapshot: casual tone for the user as White', () {
      expectSnapshot('summary_opera_casual.txt', render(summaryBundle(opera, userSide: Side.white)));
    });

    test('snapshot: coach tone, no user side', () {
      expectSnapshot(
        'summary_opera_coach.txt',
        render(summaryBundle(opera, prefs: const ExplainPrefs(tone: ExplainTone.coach, audience: ExplainAudience.advanced))),
      );
    });

    test('payload: result, ending, accuracy, counts, at most 8 key moments, trajectory every 5 plies', () {
      final b = summaryBundle(opera, userSide: Side.white);
      final json = userJson(b);
      expect(json['result'], '1-0');
      expect(json['userResult'], 'won');
      expect(json['ending'], 'checkmate');
      expect(json['plyCount'], opera.game.plyCount);
      expect(json['accuracy'], {'white': 93, 'black': 55});
      expect(json['userSide'], 'white');
      expect((json['keyMoments'] as List).length, lessThanOrEqualTo(8));
      final plies = opera.game.plyCount;
      expect((json['whiteWinChanceEvery5Plies'] as List).length, (plies ~/ 5) + 1 + (plies % 5 == 0 ? 0 : 1));
      expect((json['labelCounts'] as Map).keys, ['white', 'black']);
      expect(b.kind, PromptKind.summary);
      expect(b.fenBefore, isEmpty);
    });

    test('key moments are SAN with a best move, never UCI', () {
      final json = userJson(summaryBundle(opera));
      final uci = RegExp(r'\b[a-h][1-8][a-h][1-8][qrbn]?\b');
      for (final m in (json['keyMoments'] as List).cast<Map<String, dynamic>>()) {
        expect(uci.hasMatch(m['san'] as String), isFalse);
        if (m['bestMove'] != null) expect(uci.hasMatch(m['bestMove'] as String), isFalse);
        expect(m.keys, containsAll(['moveNumber', 'side', 'san', 'label', 'winChanceBefore', 'winChanceAfter', 'bestMove']));
      }
    });

    test('no names, ratings, sites or dates; the raw Termination header is not used', () {
      final text = summaryBundle(opera, userSide: Side.black).messages.map((m) => m.content).join('\n');
      for (final value in identifying.values) {
        expect(text, isNot(contains(value)));
      }
      expect(text, isNot(contains('resigned')));
    });

    test('the tone changes the system message (2-4 friendly sentences vs 4-6 with takeaways)', () {
      expect(PromptBuilder.summarySystemPrompt(ExplainTone.casual), contains('2 to 4 friendly sentences'));
      expect(PromptBuilder.summarySystemPrompt(ExplainTone.coach), contains('4 to 6 sentences'));
      expect(PromptBuilder.summarySystemPrompt(ExplainTone.coach), contains('takeaways'));
      for (final t in ExplainTone.values) {
        expect(PromptBuilder.summarySystemPrompt(t), contains('Mention only moves that appear in keyMoments'));
      }
    });

    test('ending and userResult variants', () async {
      final stale = await fixture('stalemate', result: '1/2-1/2');
      expect(userJson(summaryBundle(stale, userSide: Side.white))['ending'], 'stalemate');
      expect(userJson(summaryBundle(stale, userSide: Side.white))['userResult'], 'drew');
      expect(userJson(summaryBundle(opera, userSide: Side.black))['userResult'], 'lost');
      expect(userJson(summaryBundle(opera))['userResult'], isNull);
      final resign = await fixture('blunder_white', result: '0-1');
      expect(userJson(summaryBundle(resign))['ending'], 'resignation or time');
      final unfinished = await fixture('blunder_white');
      expect(userJson(summaryBundle(unfinished))['ending'], 'unfinished');
    });
  });
}
