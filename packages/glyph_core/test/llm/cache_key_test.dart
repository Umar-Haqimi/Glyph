import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

import '../support/review.dart';
import '../support/transcripts.dart';

/// SPEC trap 17 / acceptance: changing model, language or tone must produce a
/// fresh explanation; so must anything else that changes the output.
void main() {
  late Game game;
  late Map<int, List<EngineLine>> lines;
  late List<ClassifiedMove?> moves;

  setUpAll(() async {
    final g = transcriptGame('p0_blunder_white');
    lines = await analyseFromTranscript('p0_blunder_white', startFen: g.startFen, moves: g.moves);
    game = gameFrom(g.startFen, g.moves);
    moves = const Classifier().classify(startFen: g.startFen, moves: g.moves, lines: lines);
  });

  const config = LlmConfig(baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini');

  PromptBundle bundle({
    int ply = 6,
    ExplainPrefs prefs = const ExplainPrefs(),
    Side? userSide = Side.black,
    Map<int, List<EngineLine>>? withLines,
    ClassifiedMove? move,
  }) =>
      PromptBuilder.move(
        game: game,
        ply: ply,
        move: move ?? moves[ply - 1]!,
        lines: withLines ?? lines,
        book: BookAnnotation.none,
        userSide: userSide,
        prefs: prefs,
      );

  String key(PromptBundle b, {LlmConfig c = config, int classifier = 2}) => CacheKey.of(b, c, classifierVersion: classifier);

  test('the same inputs give the same key (64 hex characters)', () {
    expect(key(bundle()), key(bundle()));
    expect(key(bundle()), matches(RegExp(r'^[0-9a-f]{64}$')));
  });

  test('every input that can change the text changes the key', () {
    final base = key(bundle());
    final variants = <String, String>{
      'model': key(bundle(), c: const LlmConfig(baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o')),
      'endpoint': key(bundle(), c: const LlmConfig(baseUrl: 'https://openrouter.ai/api/v1', model: 'gpt-4o-mini')),
      'token limit mode': key(bundle(), c: const LlmConfig(baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini', tokenLimitMode: TokenLimitMode.maxTokens)),
      'token limit value': key(
        bundle(),
        c: const LlmConfig(baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini', tokenLimitMode: TokenLimitMode.maxTokens, tokenLimit: 2048),
      ),
      'language': key(bundle(prefs: const ExplainPrefs(language: 'Bahasa Melayu'))),
      'tone': key(bundle(prefs: const ExplainPrefs(tone: ExplainTone.coach))),
      'audience': key(bundle(prefs: const ExplainPrefs(audience: ExplainAudience.beginner))),
      'user side': key(bundle(userSide: Side.white)),
      'no user side': key(bundle(userSide: null)),
      'classifier version': key(bundle(), classifier: 3),
      'other move': key(bundle(ply: 5)),
    };
    for (final MapEntry(key: what, value: k) in variants.entries) {
      expect(k, isNot(base), reason: 'changing the $what must change the key');
    }
    expect(variants.values.toSet().length, variants.length, reason: 'and the variants differ from each other');
  });

  test('a different label for the same move changes the key', () {
    final m = moves[5]!;
    final relabelled = ClassifiedMove(
      ply: m.ply,
      side: m.side,
      uci: m.uci,
      label: MoveLabel.mistake,
      epLoss: m.epLoss,
      winBefore: m.winBefore,
      winAfter: m.winAfter,
      bestUci: m.bestUci,
    );
    expect(key(bundle(move: relabelled)), isNot(key(bundle())));
  });

  test('a re-analysis with other engine lines changes the key (stale text is never served)', () {
    final other = {
      for (final e in lines.entries)
        e.key: [
          for (final l in e.value)
            EngineLine(rank: l.rank, score: const WhiteScore.cp(-35), depth: 20, pv: l.pv),
        ],
    };
    expect(key(bundle(withLines: other)), isNot(key(bundle())));
    // Same lines, re-created objects: same key.
    final same = {for (final e in lines.entries) e.key: [for (final l in e.value) EngineLine(rank: l.rank, score: l.score, depth: l.depth, pv: [...l.pv])]};
    expect(key(bundle(withLines: same)), key(bundle()));
  });

  test('a changed prompt template changes the key even if the version number was forgotten', () {
    final b = bundle();
    final edited = PromptBundle(
      kind: b.kind,
      messages: [ChatMessage(ChatRole.system, '${b.messages.first.content} Be brief.'), b.messages.last],
      fenBefore: b.fenBefore,
      moveUci: b.moveUci,
      label: b.label,
      userSide: b.userSide,
      prefs: b.prefs,
    );
    expect(key(edited), isNot(key(b)));
  });

  test('summary and move keys never collide, and the endpoint is normalised', () {
    final g = transcriptGame('p0_blunder_white');
    final review = GameReview(moves: moves, accuracy: GameAccuracy.none, keyMoments: KeyMoments.of(moves), book: BookAnnotation.none, classifierVersion: 2);
    final summary = PromptBuilder.summary(game: game, review: review, lines: lines, userSide: Side.black, prefs: const ExplainPrefs());
    expect(g.moves, isNotEmpty);
    expect(key(summary), isNot(key(bundle())));
    expect(
      key(bundle(), c: const LlmConfig(baseUrl: ' HTTPS://API.OpenAI.com/v1/ ', model: 'gpt-4o-mini')),
      key(bundle()),
      reason: 'a trailing slash or letter case is not a different endpoint',
    );
  });

  test('the API key is not an input: nothing in the key function can see it', () {
    // CacheKey.of takes the bundle and the config only; the config holds no
    // key and the bundle's messages are the ones View prompt shows.
    final b = bundle();
    final text = b.messages.map((m) => m.content).join();
    expect(text, isNot(contains('sk-')));
    expect(const LlmConfig(baseUrl: 'x', model: 'y').toString(), isNot(contains('sk-')));
  });
}
