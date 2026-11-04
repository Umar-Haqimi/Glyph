
import 'package:flutter/semantics.dart' show SemanticsNode;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/explain/explain_sheet.dart';
import 'package:glyph/features/explain/streaming_text.dart';
import 'package:glyph/features/settings/explain_settings.dart';
import 'package:glyph/platform/app_log.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';

import '../support/fake_llm.dart';
import '../support/review_fixture.dart';
import '../support/test_app.dart';

const apiKey = 'sk-test-KEY-abcd1234';

Map<String, String> openAiSettings({String model = 'gpt-test', Map<String, String> extra = const {}}) => {
      'llm_provider': 'openai',
      'llm_base_url': 'https://api.openai.com/v1',
      'llm_model': model,
      ...extra,
    };

class Harness {
  Harness(this.tester, this.env, this.llm, this.container);

  final WidgetTester tester;
  final TestEnv env;
  final FakeLlm llm;
  final ProviderContainer container;

  Future<void> settle([int rounds = 6]) => settleBoard(tester, rounds: rounds);

  Future<void> openExplain() async {
    await tester.tap(find.byKey(const Key('explain-button')));
    await settle(16); // the sheet slides in for ~250 ms
  }

  Future<void> closeSheet() async {
    await tester.tapAt(const Offset(10, 10)); // the barrier
    await settle(25);
  }

  String text(String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

  String get answer => tester.widget<Text>(find.descendant(of: find.byKey(const Key('explain-text')), matching: find.byType(Text))).data!;

  bool has(String key) => find.byKey(Key(key)).evaluate().isNotEmpty;

  Future<void> tap(String key) async {
    await tester.tap(find.byKey(Key(key)));
    await settle(20);
  }
}

/// Pumps the board of a completed review at [ply] with an LLM endpoint
/// scripted by `FakeLlm`.
Future<Harness> pumpExplain(
  WidgetTester tester, {
  int ply = 6,
  Map<String, String>? settings,
  Map<String, String>? secrets,
  FakeLlm? llm,
  Side? userSide = Side.black,
  int positions = 9,
}) async {
  final fake = llm ?? FakeLlm();
  final env = TestEnv(
    settings: settings ?? openAiSettings(),
    secrets: secrets ?? {'openai': apiKey},
    llm: fake.client,
  );
  final id = await seedReview(env, userSide: userSide, positions: positions);
  final container = await pumpReview(tester, env, id, initialPly: ply);
  return Harness(tester, env, fake, container);
}

/// A widget test that leaves nothing running: a sheet still open at the end
/// (a stream that never finished) is closed, which cancels its request and
/// its timers.
void explainTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    if (find.byType(ExplainSheet).evaluate().isNotEmpty) {
      await tester.tapAt(const Offset(10, 10));
      await settleBoard(tester, rounds: 25);
    }
  });
}

void main() {
  late List<String> logged;
  setUp(() {
    logged = [];
    AppLog.sink = logged.add;
  });
  tearDown(() {
    AppLog.sink = (line) {};
  });

  group('states', () {
    explainTest('connecting, streaming, done: text grows, footer names the model, Copy and Regenerate appear', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();

      expect(find.byType(ExplainSheet), findsOneWidget);
      expect(h.text('explain-status-text'), l10n.explainStatusConnecting);
      expect(h.has('explain-stop'), isTrue);
      expect(h.has('explain-copy'), isFalse);
      expect(h.llm.requests, hasLength(1));

      h.llm.send('Bc5 ');
      await h.settle();
      expect(h.text('explain-status-text'), l10n.explainStatusStreaming);
      expect(h.answer, 'Bc5 ');

      h.llm.send('lets White castle with a lead.');
      await h.settle();
      expect(h.answer, 'Bc5 lets White castle with a lead.');
      expect(h.has('explain-stop'), isTrue);

      await h.llm.finish();
      await h.settle();
      expect(h.text('explain-status-text'), l10n.explainStatusDone);
      expect(h.answer, 'Bc5 lets White castle with a lead.');
      expect(h.has('explain-stop'), isFalse);
      expect(h.has('explain-copy'), isTrue);
      expect(h.has('explain-regenerate'), isTrue);
      expect(h.text('explain-disclaimer'), l10n.explainDisclaimer('gpt-test'));
      expect(h.text('explain-disclaimer'), 'AI explanation from Stockfish lines · may contain mistakes · gpt-test');
      expect(h.has('explain-saved'), isFalse, reason: 'fresh from the model, not from the cache');
    });

    explainTest('header: badge, "3… Bc5" and "Your 3rd move" for the user, "White\'s 4th move" for the other side', (tester) async {
      final h = await pumpExplain(tester, ply: 6, userSide: Side.black);
      await h.openExplain();
      expect(h.text('explain-title'), '3… Bc5');
      expect(h.text('explain-subtitle'), 'Your 3rd move');
      await h.closeSheet();

      await h.tester.tap(find.byKey(const Key('nav-next'))); // ply 7: White's 4th move, O-O
      await h.settle(12);
      await h.openExplain();
      expect(h.text('explain-title'), '4. O-O');
      expect(h.text('explain-subtitle'), "White's 4th move");
    });

    testWidgets('ordinals: 1st, 2nd, 3rd, 11th, 12th, 13th, 21st', (tester) async {
      expect(l10n.explainOrdinal(1, 'st'), '1st');
      expect(l10n.explainOrdinal(2, 'nd'), '2nd');
      expect(l10n.explainOrdinal(3, 'rd'), '3rd');
      expect(l10n.explainOrdinal(11, 'other'), '11th');
      expect(l10n.explainOrdinal(21, 'st'), '21st');
    });

    explainTest('Stop: state cancelled, the text so far stays, the connection is dropped, Regenerate asks again', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('Half an answer');
      await h.settle();

      await h.tap('explain-stop');
      expect(h.text('explain-status-text'), l10n.explainStatusCancelled);
      expect(h.answer, 'Half an answer');
      expect(h.llm.cancelled, 1, reason: 'the HTTP response stream was cancelled');
      expect(h.has('explain-stop'), isFalse);
      expect(h.has('explain-regenerate'), isTrue);
      expect(h.has('explain-copy'), isTrue);

      await h.tap('explain-regenerate');
      expect(h.llm.requests, hasLength(2));
      h.llm.send('A fresh answer.');
      await h.llm.finish();
      await h.settle();
      expect(h.answer, 'A fresh answer.');
    });

    explainTest('closing the sheet while it streams cancels the request', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('Still writing');
      await h.settle();
      expect(h.llm.cancelled, 0);

      await h.closeSheet();
      expect(find.byType(ExplainSheet), findsNothing);
      expect(h.llm.cancelled, 1);
    });

    explainTest('a stream cut off at the model\'s token limit is shown with a note and is not saved', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('The answer was cut');
      h.llm.sendRaw('${FakeLlm.chunk('', finish: 'length')}data: [DONE]\n\n');
      await h.llm.last.controller!.close();
      await h.settle();
      expect(h.text('explain-cut-off'), l10n.explainCutOff);
      expect(await h.env.cache.count(), 0);
    });
  });

  group('request', () {
    explainTest('grounded prompt: SAN lines, mover-POV numbers, no names; key only in the Authorization header', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      await h.llm.finish();
      await h.settle();

      final r = h.llm.last;
      expect(r.uri.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(r.headers['Authorization'], 'Bearer $apiKey');
      expect(r.json.keys.toSet(), {'model', 'messages', 'stream'});
      expect(r.json['model'], 'gpt-test');
      expect(r.json['stream'], true);
      expect(r.body, isNot(contains(apiKey)));

      final system = r.messages.first;
      expect(system['role'], 'system');
      expect(system['content'], contains('at most 120 words'));
      final facts = r.facts;
      expect(facts['move']['san'], 'Bc5');
      expect(facts['move']['side'], 'black');
      expect(facts['move']['isUserMove'], isTrue);
      expect(facts['fenBefore'], isNotEmpty);
      expect(facts['language'], 'English');
      expect(facts['tone'], 'casual');
      expect(facts['audience'], 'club');
      expect(facts['classification'], isNotNull);
      for (final leaked in ['Alice', 'Bob', '1500', '1400', '300+0']) {
        expect(r.body, isNot(contains(leaked)), reason: leaked);
      }
    });

    explainTest('the token limit parameter is sent only when chosen; temperature never', (tester) async {
      final h = await pumpExplain(
        tester,
        settings: openAiSettings(extra: {'llm_token_mode': 'maxCompletionTokens', 'llm_token_value': '700'}),
      );
      await h.openExplain();
      expect(h.llm.last.json['max_completion_tokens'], 700);
      expect(h.llm.last.json.containsKey('max_tokens'), isFalse);
      expect(h.llm.last.json.containsKey('temperature'), isFalse);
    });

    explainTest('settings change the prompt: language, tone and audience', (tester) async {
      final h = await pumpExplain(
        tester,
        settings: openAiSettings(extra: {'explain_language': 'Bahasa Melayu', 'explain_tone': 'coach', 'explain_audience': 'beginner'}),
      );
      await h.openExplain();
      expect(h.llm.last.facts['language'], 'Bahasa Melayu');
      expect(h.llm.last.facts['tone'], 'coach');
      expect(h.llm.last.facts['audience'], 'beginner');
    });

    explainTest('the key is read for each request and kept nowhere: not in settings, cache, logs or provider state', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      final readsAfterOpen = h.env.secrets.reads;
      h.llm.send('Text.');
      await h.llm.finish();
      await h.settle();

      expect(readsAfterOpen, greaterThan(0));
      for (final value in h.env.store.settings.values) {
        expect(value, isNot(contains(apiKey)));
      }
      for (final entry in h.env.store.llmCache.values) {
        expect(entry.content, isNot(contains(apiKey)));
        expect(entry.key, isNot(contains(apiKey)));
      }
      expect(logged.join('\n'), isNot(contains(apiKey)));
      final status = await h.container.read(apiKeyStatusProvider.future);
      expect(status.mask, '••••1234');
      expect(status.mask, isNot(contains('sk-test')));

      await h.tap('explain-regenerate');
      expect(h.env.secrets.reads, greaterThan(readsAfterOpen), reason: 'read again for the next request');
    });
  });

  group('cache', () {
    explainTest('a saved explanation is shown again without a request; Regenerate replaces it', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('First explanation.');
      await h.llm.finish();
      await h.settle();
      expect(await h.env.cache.count(), 1);
      await h.closeSheet();

      await h.openExplain();
      expect(h.llm.requests, hasLength(1), reason: 'served from the cache');
      expect(h.answer, 'First explanation.');
      expect(h.has('explain-saved'), isTrue);
      expect(h.text('explain-status-text'), l10n.explainStatusDone);

      await h.tap('explain-regenerate');
      expect(h.llm.requests, hasLength(2));
      h.llm.send('Second explanation.');
      await h.llm.finish();
      await h.settle();
      expect(h.answer, 'Second explanation.');
      expect(await h.env.cache.count(), 1, reason: 'same key, replaced');
      await h.closeSheet();

      await h.openExplain();
      expect(h.llm.requests, hasLength(2));
      expect(h.answer, 'Second explanation.');
    });

    explainTest('changing model, language or tone gives a fresh explanation (trap 17)', (tester) async {
      final h = await pumpExplain(tester);
      Future<void> ask() async {
        await h.openExplain();
        if (h.has('explain-stop')) {
          h.llm.send('An answer.');
          await h.llm.finish();
          await h.settle();
        }
        await h.closeSheet();
      }

      await ask();
      expect(h.llm.requests, hasLength(1));
      await ask();
      expect(h.llm.requests, hasLength(1), reason: 'unchanged settings: cached');

      final settings = h.container.read(explainSettingsProvider.notifier);
      await settings.setModel('gpt-other');
      await ask();
      expect(h.llm.requests, hasLength(2), reason: 'model changed');
      expect(h.llm.last.json['model'], 'gpt-other');

      await settings.setLanguage('Bahasa Melayu');
      await ask();
      expect(h.llm.requests, hasLength(3), reason: 'language changed');

      await settings.setTone(ExplainTone.coach);
      await ask();
      expect(h.llm.requests, hasLength(4), reason: 'tone changed');

      await settings.setAudience(ExplainAudience.beginner);
      await ask();
      expect(h.llm.requests, hasLength(5), reason: 'audience changed');

      await settings.setModel('gpt-test');
      await settings.setLanguage('');
      await settings.setTone(ExplainTone.casual);
      await settings.setAudience(ExplainAudience.club);
      await ask();
      expect(h.llm.requests, hasLength(5), reason: 'back to the first settings: the first answer is still cached');
    });

    explainTest('re-analysing the game drops its saved explanations', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('Saved for this game.');
      await h.llm.finish();
      await h.settle();
      expect(h.env.store.llmCache.values.single.gameId, 1);

      await h.env.analyses.clear(1);
      expect(h.env.store.llmCache, isEmpty);
    });
  });

  group('errors: each kind shows its own copy and can be retried', () {
    Future<void> expectError(
      WidgetTester tester, {
      required void Function(FakeLlm llm) setup,
      required String copy,
      String? detailContains,
      bool settingsAction = false,
      Map<String, String>? settings,
    }) async {
      final llm = FakeLlm();
      setup(llm);
      final h = await pumpExplain(tester, llm: llm, settings: settings);
      await h.openExplain();
      expect(h.text('explain-status-text'), copy);
      expect(h.has('explain-retry'), isTrue);
      expect(h.has('explain-open-settings'), settingsAction);
      if (detailContains != null) expect(h.text('explain-error-detail'), contains(detailContains));
      // Retry: the endpoint works now.
      llm.ok();
      await h.tap('explain-retry');
      expect(h.llm.requests, hasLength(2));
      llm.send('Better now.');
      await llm.finish();
      await h.settle();
      expect(h.answer, 'Better now.');
    }

    explainTest('unauthorized (401)', (tester) async {
      await expectError(tester,
          setup: (l) => l.error(401, {'message': 'Incorrect API key provided', 'code': 'invalid_api_key'}),
          copy: l10n.llmErrUnauthorized,
          settingsAction: true,
          detailContains: 'Incorrect API key');
    });

    explainTest("modelNotFound (404): Model 'gpt-test' isn't available", (tester) async {
      await expectError(tester,
          setup: (l) => l.error(404, {'message': 'The model `gpt-test` does not exist', 'code': 'model_not_found'}),
          copy: "Model 'gpt-test' isn't available on this endpoint.",
          settingsAction: true);
    });

    explainTest('rateLimited (429)', (tester) async {
      await expectError(tester,
          setup: (l) => l.error(429, {'message': 'slow down', 'code': 'rate_limit_exceeded'}), copy: 'Rate limited. Try again in a moment.');
    });

    explainTest('quotaExceeded (429 insufficient_quota)', (tester) async {
      await expectError(tester,
          setup: (l) => l.error(429, {'message': 'no credits', 'code': 'insufficient_quota', 'type': 'insufficient_quota'}),
          copy: 'Your account is out of credits.',
          settingsAction: true);
    });

    explainTest("unsupportedParam (400): names the parameter and the setting to change", (tester) async {
      await expectError(tester,
          setup: (l) => l.error(400, {'message': "Unsupported parameter: 'max_tokens'", 'code': 'unsupported_parameter', 'param': 'max_tokens'}),
          copy: "This model rejected 'max_tokens'. Change 'Token limit parameter' in Settings.",
          settingsAction: true,
          settings: openAiSettings(extra: {'llm_token_mode': 'maxTokens'}));
    });

    explainTest('server (5xx) shows the code', (tester) async {
      await expectError(tester,
          setup: (l) => l.error(503, {'message': 'overloaded'}), copy: 'The provider had an error (503).');
    });

    explainTest('offline', (tester) async {
      await expectError(tester, setup: (l) => l.throwOnConnect = http.ClientException('Failed host lookup: api.openai.com'), copy: 'No connection.');
    });

    explainTest('badStream: the connection ends in the middle (the text so far stays visible)', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('Half of it');
      await h.settle();
      await h.llm.cutConnection();
      await h.settle();
      expect(h.text('explain-status-text'), "The response couldn't be read.");
      expect(h.answer, 'Half of it');
      expect(h.has('explain-retry'), isTrue);
    });

    explainTest('timeout: no answer within the first-byte timeout', (tester) async {
      final h = await pumpExplain(tester);
      // The endpoint never answers: replace the scripted response by a hang.
      await h.openExplain();
      expect(h.text('explain-status-text'), l10n.explainStatusConnecting);
      // The stream is open but silent: the 60 s idle timeout fires.
      await tester.pump(const Duration(seconds: 61));
      await h.settle();
      expect(h.text('explain-status-text'), 'The model took too long to respond.');
      expect(h.has('explain-retry'), isTrue);
    });

    explainTest('an error event in the middle of the stream: the text so far plus the provider error', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('Some words. ');
      h.llm.sendRaw('data: {"error":{"message":"Provider disconnected unexpectedly","code":"server_error"}}\n\n');
      await h.settle();
      expect(h.text('explain-status-text'), 'The provider had an error.');
      expect(h.answer, 'Some words. ');
    });

    explainTest('empty answer', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      await h.llm.finish();
      await h.settle();
      expect(h.text('explain-status-text'), l10n.llmErrEmpty);
    });

    explainTest('a move the engine has not reached yet: notAnalysed', (tester) async {
      // Only positions 0..3 analysed: ply 6 has no data.
      final h = await pumpExplain(tester, ply: 3, positions: 3);
      await h.tester.tap(find.byKey(const Key('nav-next')));
      await h.settle(12);
      await h.tester.tap(find.byKey(const Key('nav-next')));
      await h.settle(12);
      await h.openExplain();
      expect(h.text('explain-status-text'), l10n.llmErrNotAnalysed);
      expect(h.llm.requests, isEmpty);
    });
  });

  group('not configured', () {
    explainTest('no model: the set-up card names the providers and opens the LLM settings', (tester) async {
      final h = await pumpExplain(tester, settings: {});
      await h.openExplain();
      expect(h.has('explain-setup'), isTrue);
      expect(find.text(l10n.explainSetupTitle), findsOneWidget);
      expect(find.textContaining('OpenAI'), findsWidgets);
      expect(find.textContaining('OpenRouter'), findsWidgets);
      expect(find.textContaining('Ollama'), findsWidgets);
      expect(h.text('explain-setup-reason'), l10n.llmErrNoModel);
      expect(h.llm.requests, isEmpty);

      await h.tap('explain-setup-action');
      expect(find.byType(ExplainSheet), findsNothing);
      expect(find.text(l10n.llmTitle), findsOneWidget);
    });

    explainTest('a public host without a key: "Add an API key in Settings → Explanations."', (tester) async {
      final h = await pumpExplain(tester, secrets: {});
      await h.openExplain();
      expect(h.text('explain-setup-reason'), 'Add an API key in Settings → Explanations.');
      expect(h.llm.requests, isEmpty);
    });

    explainTest('a key for another provider does not count', (tester) async {
      final h = await pumpExplain(tester, secrets: {'openrouter': apiKey});
      await h.openExplain();
      expect(h.text('explain-setup-reason'), l10n.llmErrNoKey);
    });

    explainTest('plain http:// to a public host is refused with its own copy, before any request', (tester) async {
      final h = await pumpExplain(tester, settings: openAiSettings(extra: {'llm_base_url': 'http://api.example.com/v1'}));
      await h.openExplain();
      expect(h.text('explain-setup-reason'), 'Plain http:// is only allowed for local network addresses.');
      expect(h.llm.requests, isEmpty);
    });

    explainTest('a LAN Ollama over http:// needs no key and is allowed', (tester) async {
      final h = await pumpExplain(
        tester,
        secrets: {},
        settings: {'llm_provider': 'ollama', 'llm_base_url': 'http://192.168.1.20:11434/v1', 'llm_model': 'llama3.2'},
      );
      await h.openExplain();
      expect(h.llm.requests, hasLength(1));
      expect(h.llm.last.uri.toString(), 'http://192.168.1.20:11434/v1/chat/completions');
      expect(h.llm.last.headers.containsKey('Authorization'), isFalse);
      expect(h.llm.last.headers.keys.map((k) => k.toLowerCase()), isNot(contains('authorization')));
    });

    explainTest('an invalid URL', (tester) async {
      final h = await pumpExplain(tester, settings: openAiSettings(extra: {'llm_base_url': 'ftp://x'}));
      await h.openExplain();
      expect(h.text('explain-setup-reason'), l10n.llmErrInvalidUrl);
    });
  });

  group('View prompt, Copy', () {
    explainTest('View prompt shows exactly what was sent, and never the key', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      await h.llm.finish();
      await h.settle();

      await h.tap('explain-menu');
      await h.tap('explain-view-prompt');
      expect(find.byKey(const Key('prompt-dialog')), findsOneWidget);
      final sent = h.llm.last;
      String shown(String key) => tester.widget<SelectableText>(find.byKey(Key(key))).data!;
      expect(shown('prompt-system'), sent.messages.first['content']);
      expect(shown('prompt-user'), sent.messages.last['content']);
      expect(shown('prompt-request'), contains('model: gpt-test'));
      expect(shown('prompt-request'), contains('stream: true'));
      final everything = [shown('prompt-system'), shown('prompt-user'), shown('prompt-request')].join('\n');
      expect(everything, isNot(contains(apiKey)));
      expect(everything, isNot(contains('Bearer')));
      expect(everything, isNot(contains('Alice')));

      await h.tap('prompt-close');
      expect(find.byKey(const Key('prompt-dialog')), findsNothing);
    });

    explainTest('Copy puts the explanation (only) on the clipboard', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('Copy me.');
      await h.llm.finish();
      await h.settle();
      await h.tap('explain-copy');
      expect(copied, ['Copy me.']);
      expect(copied.single, isNot(contains(apiKey)));
    });
  });

  group('accessibility', () {
    explainTest('streaming text is a live region that announces one sentence at a time, the status is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      final announcements = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (message) async {
        final data = (message as Map)['data'] as Map?;
        if (data != null && data['message'] != null) announcements.add(data['message'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));

      final h = await pumpExplain(tester);
      await h.openExplain();

      SemanticsNode node() => tester.getSemantics(find.byKey(const Key('streaming-text-node')));
      SemanticsNode status() => tester.getSemantics(find.byKey(const Key('explain-status')));
      expect(status().label, l10n.explainStatusConnecting);
      expect(status().flagsCollection.isLiveRegion, isTrue);

      h.llm.send('The bishop lets White castle');
      await h.settle();
      expect(node().label, isEmpty, reason: 'no whole sentence yet: nothing is announced');
      expect(node().flagsCollection.isLiveRegion, isTrue);

      h.llm.send(' with an easy game. ');
      await h.settle();
      expect(node().label, 'The bishop lets White castle with an easy game.');

      h.llm.send('Better was d3.');
      await h.settle();
      expect(node().label, 'The bishop lets White castle with an easy game.', reason: 'the unfinished sentence is not announced yet');

      await h.llm.finish();
      await h.settle();
      expect(announcements, contains('Better was d3.'), reason: 'the tail is announced once at the end');
      expect(announcements, isNot(contains('The bishop lets White castle with an easy game.')), reason: 'sentences go through the live region, not announce()');
      expect(node().label, 'The bishop lets White castle with an easy game. Better was d3.');
      expect(node().flagsCollection.isLiveRegion, isFalse, reason: 'finished text is plain text: no repeat');
      expect(status().label, l10n.explainStatusDone);
      handle.dispose();
    });

    explainTest('a saved explanation is announced in full when the sheet opens', (tester) async {
      final handle = tester.ensureSemantics();
      final announcements = <String>[];
      tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, (message) async {
        final data = (message as Map)['data'] as Map?;
        if (data != null && data['message'] != null) announcements.add(data['message'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<dynamic>(SystemChannels.accessibility, null));
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('Saved text.');
      await h.llm.finish();
      await h.settle();
      await h.closeSheet();
      announcements.clear();
      await h.openExplain();
      expect(announcements, ['Saved text.']);
      handle.dispose();
    });

    testWidgets('sentence boundaries', (tester) async {
      expect(StreamingText.sentenceEnd('No boundary yet'), 0);
      expect(StreamingText.sentenceEnd('One. Two'), 5);
      expect(StreamingText.sentenceEnd('Really? Yes! Done'), 13);
      expect(StreamingText.sentenceEnd('Line one\nLine two'), 9);
      expect(StreamingText.sentenceEnd('Ends with a period.'), 0, reason: 'the whitespace after it has not arrived');
      expect(StreamingText.sentenceEnd('Quote "ok." Next'), 12);
    });

    explainTest('buttons are at least 48 dp tall', (tester) async {
      final h = await pumpExplain(tester);
      await h.openExplain();
      h.llm.send('x');
      await h.llm.finish();
      await h.settle();
      for (final key in ['explain-copy', 'explain-regenerate']) {
        final size = tester.getSize(find.byKey(Key(key)));
        expect(size.height, greaterThanOrEqualTo(48), reason: key);
      }
    });
  });

  group('logging', () {
    explainTest('errors are logged by type only: no key, no prompt, no provider message', (tester) async {
      final llm = FakeLlm()..error(401, {'message': 'Incorrect API key provided: $apiKey', 'code': 'invalid_api_key'});
      final h = await pumpExplain(tester, llm: llm);
      await h.openExplain();
      expect(logged.join('\n'), isNot(contains(apiKey)));
      expect(h.text('explain-error-detail'), isNot(contains(apiKey)), reason: 'the provider message is shown with the key removed');
      AppLog.warning('probe', Exception('secret $apiKey in a message'));
      expect(logged.last, 'probe (_Exception)');
    });
  });
}
