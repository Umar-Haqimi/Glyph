import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/features/explain/generation.dart';
import 'package:glyph/features/explain/summary_controller.dart';
import 'package:glyph/features/settings/explain_settings.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_llm.dart';
import '../support/review_fixture.dart';
import '../support/test_app.dart';

const apiKey = 'sk-test-KEY-abcd1234';

Map<String, String> configured({Map<String, String> extra = const {}}) => {
      'llm_provider': 'openai',
      'llm_base_url': 'https://api.openai.com/v1',
      'llm_model': 'gpt-test',
      ...extra,
    };

class Report {
  Report(this.tester, this.env, this.llm, this.container, this.id);

  final WidgetTester tester;
  final TestEnv env;
  final FakeLlm llm;
  final ProviderContainer container;
  final int id;

  Future<void> settle([int rounds = 8]) => settleBoard(tester, rounds: rounds);

  Future<void> openReport() async {
    await tester.tap(find.byKey(const Key('open-report')));
    await settle(25);
  }

  String text(String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  bool has(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

  String get summary => tester.widget<Text>(find.descendant(of: find.byKey(const Key('summary-text')), matching: find.byType(Text))).data!;

  Future<void> tap(String key) async {
    final f = find.byKey(Key(key));
    await tester.ensureVisible(f);
    await settle(4);
    await tester.tap(f);
    await settle(20);
  }

  GenerationState get state => container.read(summaryProvider(id));
}

Future<Report> pumpReport(
  WidgetTester tester, {
  Map<String, String>? settings,
  Map<String, String>? secrets,
  FakeLlm? llm,
  Side? userSide = Side.white,
  bool open = true,
}) async {
  final fake = llm ?? FakeLlm();
  final env = TestEnv(settings: settings ?? configured(), secrets: secrets ?? {'openai': apiKey}, llm: fake.client);
  final id = await seedReview(env, userSide: userSide);
  final container = await pumpReview(tester, env, id);
  final r = Report(tester, env, fake, container, id);
  if (open) await r.openReport();
  return r;
}

/// A widget test that leaves nothing running (an open stream is cancelled).
void reportTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    // A summary request that is still open: stop it so no timer outlives the test.
    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    container.read(summaryProvider(1).notifier).cancel();
    await tester.pump(const Duration(milliseconds: 50));
  });
}

void main() {
  group('the report block', () {
    reportTest('with automatic summaries off the block offers a button; nothing is requested until it is tapped', (tester) async {
      final r = await pumpReport(tester, settings: configured(extra: {'summary_auto': '0'}));
      expect(r.has('summary-card'), isTrue);
      expect(find.text(l10n.summaryTitle), findsOneWidget);
      expect(r.has('summary-button'), isTrue);
      expect(r.llm.requests, isEmpty);
    });

    reportTest('hidden entirely when the summary setting is off', (tester) async {
      final r = await pumpReport(tester, settings: configured(extra: {'summary_enabled': '0'}));
      expect(r.has('summary-card'), isFalse);
      expect(find.text(l10n.summaryTitle), findsNothing);
      expect(find.text(l10n.summaryButton), findsNothing);
      expect(r.llm.requests, isEmpty);
    });

    reportTest('the Summarize button streams the recap, shows the footer, and saves it', (tester) async {
      final r = await pumpReport(tester, settings: configured(extra: {'summary_auto': '0'}));
      await r.tap('summary-button');
      expect(r.llm.requests, hasLength(1));
      expect(r.text('summary-status-text'), l10n.explainStatusConnecting);
      r.llm.send('You played a tidy opening. ');
      await r.settle();
      expect(r.summary, 'You played a tidy opening. ');
      expect(r.text('summary-status-text'), l10n.explainStatusStreaming);
      r.llm.send('Then the game got sharp.');
      await r.llm.finish();
      await r.settle();
      expect(r.summary, 'You played a tidy opening. Then the game got sharp.');
      expect(r.text('summary-status-text'), l10n.explainStatusDone);
      expect(r.text('summary-disclaimer'), 'AI summary from Stockfish data · may contain mistakes · gpt-test');
      expect(r.has('summary-regenerate'), isTrue);
      expect(r.has('summary-copy'), isTrue);
      expect(r.has('summary-button'), isFalse);
      expect(r.env.store.llmCache.values.single.kind, PromptKind.summary);
      expect(r.env.store.llmCache.values.single.gameId, r.id);
    });

    reportTest('the request is the summary prompt: engine facts only, no names, key in the header', (tester) async {
      final r = await pumpReport(tester, settings: configured(extra: {'summary_auto': '0'}), userSide: Side.black);
      await r.tap('summary-button');
      final req = r.llm.last;
      expect(req.headers['Authorization'], 'Bearer $apiKey');
      expect(req.body, isNot(contains(apiKey)));
      for (final leaked in ['Alice', 'Bob', '1500', '1400']) {
        expect(req.body, isNot(contains(leaked)), reason: leaked);
      }
      final facts = req.facts;
      expect(facts['userSide'], 'black');
      expect(facts['tone'], 'casual');
      expect(facts.keys, containsAll(['result', 'ending', 'accuracy', 'labelCounts', 'keyMoments', 'whiteWinChanceEvery5Plies', 'language']));
      expect(req.messages.first['content'], contains('2 to 4 friendly sentences'));
    });

    reportTest('a saved summary shows again when the report is opened, without a request', (tester) async {
      final r = await pumpReport(tester, settings: configured(extra: {'summary_auto': '0'}));
      await r.tap('summary-button');
      r.llm.send('A saved recap.');
      await r.llm.finish();
      await r.settle();
      // Leave and come back: the summary state survives, and so does the cache.
      await tester.pageBack();
      await r.settle(25);
      r.container.invalidate(summaryProvider(r.id));
      await r.openReport();
      expect(r.summary, 'A saved recap.');
      expect(r.has('summary-saved'), isTrue);
      expect(r.llm.requests, hasLength(1));
    });

    reportTest('Regenerate replaces the summary; Stop keeps the text so far', (tester) async {
      final r = await pumpReport(tester, settings: configured(extra: {'summary_auto': '0'}));
      await r.tap('summary-button');
      r.llm.send('First recap.');
      await r.llm.finish();
      await r.settle();
      await r.tap('summary-regenerate');
      expect(r.llm.requests, hasLength(2));
      r.llm.send('Half of the new ');
      await r.settle();
      await r.tap('summary-stop');
      expect(r.text('summary-status-text'), l10n.explainStatusCancelled);
      expect(r.summary, 'Half of the new ');
      expect(r.llm.cancelled, greaterThanOrEqualTo(1));
    });

    reportTest('tone changes the prompt and the saved summary is not reused', (tester) async {
      final r = await pumpReport(tester, settings: configured(extra: {'summary_auto': '0'}));
      await r.tap('summary-button');
      r.llm.send('Casual recap.');
      await r.llm.finish();
      await r.settle();
      await r.container.read(explainSettingsProvider.notifier).setTone(ExplainTone.coach);
      r.container.invalidate(summaryProvider(r.id));
      await tester.pageBack();
      await r.settle(25);
      await r.openReport();
      expect(r.has('summary-button'), isTrue, reason: 'the coach-tone summary does not exist yet');
      await r.tap('summary-button');
      expect(r.llm.requests, hasLength(2));
      expect(r.llm.last.messages.first['content'], contains('4 to 6 sentences'));
      expect(r.llm.last.facts['tone'], 'coach');
    });

    reportTest('failures show the error with Retry', (tester) async {
      final llm = FakeLlm()..error(429, {'message': 'slow down', 'code': 'rate_limit_exceeded'});
      final r = await pumpReport(tester, llm: llm, settings: configured(extra: {'summary_auto': '0'}));
      await r.tap('summary-button');
      expect(r.text('summary-status-text'), 'Rate limited. Try again in a moment.');
      llm.ok();
      await r.tap('summary-retry');
      r.llm.send('Fine now.');
      await r.llm.finish();
      await r.settle();
      expect(r.summary, 'Fine now.');
    });

    reportTest('no model yet: tapping Summarize shows the set-up card', (tester) async {
      final r = await pumpReport(tester, settings: {});
      await r.tap('summary-button');
      expect(r.has('summary-setup'), isTrue);
      expect(r.llm.requests, isEmpty);
    });

    reportTest('while the analysis is not complete the block says so and offers nothing', (tester) async {
      final fake = FakeLlm();
      final env = TestEnv(settings: configured(), secrets: {'openai': apiKey}, llm: fake.client);
      final id = await seedReview(env, status: AnalysisStatus.paused, labels: false, positions: 5);
      await pumpReview(tester, env, id);
      await tester.tap(find.byKey(const Key('open-report')));
      await settleBoard(tester, rounds: 25);
      expect(find.byKey(const Key('summary-waiting')), findsOneWidget);
      expect(find.byKey(const Key('summary-button')), findsNothing);
      expect(fake.requests, isEmpty);
    });
  });

  group('automatic summary', () {
    Future<(ProviderContainer, TestEnv, FakeLlm, int)> setup(
      WidgetTester tester, {
      Map<String, String>? settings,
      Map<String, String>? secrets,
    }) async {
      final llm = FakeLlm();
      final env = TestEnv(settings: settings ?? configured(), secrets: secrets ?? {'openai': apiKey}, llm: llm.client);
      final id = await seedReview(env, userSide: Side.white);
      final container = await pumpReview(tester, env, id);
      return (container, env, llm, id);
    }

    reportTest('autoGenerate requests a summary when the setting, the auto setting and a model are all there', (tester) async {
      final (container, env, llm, id) = await setup(tester);
      unawaited(container.read(summaryProvider(id).notifier).autoGenerate());
      await settleBoard(tester, rounds: 10);
      expect(llm.requests, hasLength(1));
      llm.send('Automatic recap.');
      await llm.finish();
      await settleBoard(tester, rounds: 10);
      expect(container.read(summaryProvider(id)).text, 'Automatic recap.');
      expect(container.read(summaryProvider(id)).phase, GenerationPhase.done);
      expect(env.store.llmCache.values.single.kind, PromptKind.summary);

      // A second automatic pass reuses the saved summary: no new request.
      container.invalidate(summaryProvider(id));
      unawaited(container.read(summaryProvider(id).notifier).autoGenerate());
      await settleBoard(tester, rounds: 10);
      expect(llm.requests, hasLength(1));
      expect(container.read(summaryProvider(id)).fromCache, isTrue);
    });

    for (final (name, settings, secrets) in [
      ('the automatic setting is off', {'summary_auto': '0'}, <String, String>{'openai': apiKey}),
      ('the summary setting is off', {'summary_enabled': '0'}, <String, String>{'openai': apiKey}),
      ('there is no key for a public server', <String, String>{}, <String, String>{}),
    ]) {
      reportTest('autoGenerate stays silent when $name', (tester) async {
        final (container, _, llm, id) = await setup(
          tester,
          settings: configured(extra: settings),
          secrets: secrets,
        );
        unawaited(container.read(summaryProvider(id).notifier).autoGenerate());
        await settleBoard(tester, rounds: 10);
        expect(llm.requests, isEmpty);
        expect(container.read(summaryProvider(id)).phase, GenerationPhase.idle, reason: 'no error: the report offers the button');
      });
    }

    reportTest('it starts when the analysis completes, without any report open', (tester) async {
      final llm = FakeLlm();
      final env = TestEnv(settings: configured(), secrets: {'openai': apiKey}, llm: llm.client);
      final saved = await env.games.save(NewGame(
        source: GameSource.paste,
        pgn: reviewPgn,
        white: 'Alice',
        black: 'Bob',
        plyCount: 8,
        importedAt: 1,
      ));
      final container = await pumpReview(tester, env, saved.id);
      await settleBoard(tester, rounds: 80);
      expect((await env.analyses.get(saved.id))?.status, AnalysisStatus.completed);
      expect(llm.requests, hasLength(1), reason: 'the summary was asked for right after the analysis completed');
      expect(llm.last.messages.first['content'], contains('You recap a finished chess game'));
      llm.send('Done automatically.');
      await llm.finish();
      await settleBoard(tester, rounds: 10);
      expect(container.read(summaryProvider(saved.id)).text, 'Done automatically.');
    });

    reportTest('a failure of the automatic summary shows in the report, with Retry, and never blocks', (tester) async {
      final llm = FakeLlm()..error(500, {'message': 'oops', 'type': 'server_error'});
      final env = TestEnv(settings: configured(), secrets: {'openai': apiKey}, llm: llm.client);
      final id = await seedReview(env);
      final container = await pumpReview(tester, env, id);
      unawaited(container.read(summaryProvider(id).notifier).autoGenerate());
      await settleBoard(tester, rounds: 10);
      expect(container.read(summaryProvider(id)).phase, GenerationPhase.failed);
      await tester.tap(find.byKey(const Key('open-report')));
      await settleBoard(tester, rounds: 25);
      expect(find.byKey(const Key('summary-retry')), findsOneWidget);
    });
  });
}
