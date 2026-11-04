import 'package:flutter_test/flutter_test.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_llm.dart';
import '../support/test_app.dart';

const secret = 'sk-live-ABCDEFGH-wxyz';

Future<void> openSettings(WidgetTester tester, TestEnv env) async {
  await env.pump(tester);
  await tester.tap(find.byTooltip(l10n.settingsTooltip));
  await tester.pumpAndSettle();
}

Future<void> openLlm(WidgetTester tester, TestEnv env) async {
  await openSettings(tester, env);
  await tester.tap(find.byKey(const Key('settings-llm')));
  await tester.pumpAndSettle();
}

Future<void> tapKey(WidgetTester tester, String key) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> typeInto(WidgetTester tester, String key, String text) async {
  final f = find.byKey(Key(key));
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.enterText(f, text);
  await tester.pumpAndSettle();
}

String shown(WidgetTester tester, String key) => tester.widget<Text>(find.byKey(Key(key))).data!;

String fieldText(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

void main() {
  group('LLM connection screen', () {
    testWidgets('defaults: OpenAI preset with its base URL, model empty (SPEC section 10)', (tester) async {
      final env = TestEnv();
      await openLlm(tester, env);
      expect(find.text(l10n.llmTitle), findsWidgets);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('llm-provider-openai'))).selected, isTrue);
      expect(fieldText(tester, 'llm-base-url'), 'https://api.openai.com/v1');
      expect(fieldText(tester, 'llm-model'), isEmpty);
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('llm-token-none'))).selected, isTrue);
      expect(find.byKey(const Key('llm-token-value')), findsNothing);
      expect(shown(tester, 'llm-key-status'), l10n.llmApiKeyNone);
    });

    testWidgets('presets prefill the base URL and clear the model; all five exist', (tester) async {
      final env = TestEnv(settings: {'llm_model': 'gpt-4o-mini'});
      await openLlm(tester, env);
      expect(fieldText(tester, 'llm-model'), 'gpt-4o-mini');
      const expected = {
        'openrouter': 'https://openrouter.ai/api/v1',
        'ollama': 'http://localhost:11434/v1',
        'lmstudio': 'http://localhost:1234/v1',
        'openai': 'https://api.openai.com/v1',
      };
      for (final MapEntry(key: name, value: url) in expected.entries) {
        await tapKey(tester, 'llm-provider-$name');
        expect(fieldText(tester, 'llm-base-url'), url, reason: name);
        expect(fieldText(tester, 'llm-model'), isEmpty, reason: 'model names differ per provider');
        expect(await env.settings.get('llm_provider'), name);
        expect(await env.settings.get('llm_base_url'), url);
      }
      expect(find.byKey(const Key('llm-provider-custom')), findsOneWidget);
      await tapKey(tester, 'llm-provider-custom');
      expect(await env.settings.get('llm_provider'), 'custom');
      expect(fieldText(tester, 'llm-base-url'), 'https://api.openai.com/v1', reason: 'Custom keeps the current address to edit');
    });

    testWidgets('Ollama and LM Studio show the LAN hint and say a key is optional', (tester) async {
      final env = TestEnv(settings: {'llm_provider': 'ollama', 'llm_base_url': 'http://192.168.1.20:11434/v1'});
      await openLlm(tester, env);
      expect(find.text(l10n.llmBaseUrlLocalHint), findsOneWidget);
      expect(find.byKey(const Key('llm-key-optional')), findsOneWidget);
    });

    testWidgets('a public https server does not claim the key is optional', (tester) async {
      final env = TestEnv();
      await openLlm(tester, env);
      expect(find.byKey(const Key('llm-key-optional')), findsNothing);
    });

    testWidgets('the base URL is validated with the policy, each refusal has its own message', (tester) async {
      final env = TestEnv();
      await openLlm(tester, env);
      await tapKey(tester, 'llm-provider-custom'); // the hosted presets' address is fixed
      Future<void> expectMessage(String url, String message) async {
        await typeInto(tester, 'llm-base-url', url);
        expect(find.text(message), findsOneWidget, reason: url);
        expect(await env.settings.get('llm_base_url'), url.trim(), reason: 'stored as typed; the policy gates the request');
      }

      await expectMessage('', l10n.llmUrlEmpty);
      await expectMessage('not a url', l10n.llmUrlMalformed);
      await expectMessage('ftp://example.com/v1', l10n.llmUrlScheme);
      await expectMessage('https://me:pw@example.com/v1', l10n.llmUrlCredentials);
      await expectMessage('https://example.com/v1?key=abc', l10n.llmUrlQuery);
      await expectMessage('http://api.example.com/v1', 'Plain http:// is only allowed for local network addresses.');
      await typeInto(tester, 'llm-base-url', 'http://192.168.0.7:1234/v1');
      expect(find.text(l10n.llmErrCleartext), findsNothing);
      await typeInto(tester, 'llm-base-url', 'https://example.com');
      expect(find.text(l10n.llmUrlNoVersion), findsOneWidget, reason: 'a warning, not an error');
    });

    testWidgets('model and token limit settings are saved', (tester) async {
      final env = TestEnv();
      await openLlm(tester, env);
      await typeInto(tester, 'llm-model', ' gpt-4o-mini ');
      expect(await env.settings.get('llm_model'), 'gpt-4o-mini');

      await tapKey(tester, 'llm-token-maxCompletionTokens');
      expect(await env.settings.get('llm_token_mode'), 'maxCompletionTokens');
      expect(find.byKey(const Key('llm-token-value')), findsOneWidget);
      await typeInto(tester, 'llm-token-value', '600');
      expect(await env.settings.get('llm_token_value'), '600');
      await tapKey(tester, 'llm-token-maxTokens');
      expect(await env.settings.get('llm_token_mode'), 'maxTokens');
      await tapKey(tester, 'llm-token-none');
      expect(await env.settings.get('llm_token_mode'), 'none');
      expect(find.byKey(const Key('llm-token-value')), findsNothing);
    });
  });

  group('API key', () {
    testWidgets('saving stores it in the secret store only and shows a mask; the field is cleared and obscured', (tester) async {
      final env = TestEnv();
      await openLlm(tester, env);
      expect(tester.widget<TextField>(find.byKey(const Key('llm-api-key'))).obscureText, isTrue);
      await typeInto(tester, 'llm-api-key', secret);
      expect(tester.widget<TextField>(find.byKey(const Key('llm-api-key'))).obscureText, isTrue);
      await tapKey(tester, 'llm-key-save');

      expect(await env.secrets.read('openai'), secret);
      expect(env.secrets.slots, ['openai']);
      expect(shown(tester, 'llm-key-status'), 'Key saved: ••••wxyz');
      expect(fieldText(tester, 'llm-api-key'), isEmpty);
      expect(find.text(secret), findsNothing, reason: 'never shown again');
      expect(find.textContaining('ABCDEFGH'), findsNothing);

      // Nowhere else: not in the settings table, not in the cache.
      for (final MapEntry(key: k, value: v) in env.store.settings.entries) {
        expect(k, isNot(contains('key')));
        expect(v, isNot(contains(secret)));
        expect(v, isNot(contains('ABCDEFGH')));
      }
      expect(env.store.llmCache, isEmpty);
    });

    testWidgets('the key can be revealed while typing and hidden again', (tester) async {
      final env = TestEnv();
      await openLlm(tester, env);
      await tapKey(tester, 'llm-key-visibility');
      expect(tester.widget<TextField>(find.byKey(const Key('llm-api-key'))).obscureText, isFalse);
      await tapKey(tester, 'llm-key-visibility');
      expect(tester.widget<TextField>(find.byKey(const Key('llm-api-key'))).obscureText, isTrue);
    });

    testWidgets('Remove deletes the key', (tester) async {
      final env = TestEnv(secrets: {'openai': secret});
      await openLlm(tester, env);
      expect(shown(tester, 'llm-key-status'), contains('wxyz'));
      await tapKey(tester, 'llm-key-remove');
      expect(await env.secrets.read('openai'), isNull);
      expect(shown(tester, 'llm-key-status'), l10n.llmApiKeyNone);
      expect(find.byKey(const Key('llm-key-remove')), findsNothing);
      expect(find.text(l10n.llmApiKeyRemoved), findsOneWidget);
    });

    testWidgets('each provider has its own key slot', (tester) async {
      final env = TestEnv(secrets: {'openai': secret});
      await openLlm(tester, env);
      await tapKey(tester, 'llm-provider-openrouter');
      expect(shown(tester, 'llm-key-status'), l10n.llmApiKeyNone);
      await typeInto(tester, 'llm-api-key', 'or-key-1234567890-QRST');
      await tapKey(tester, 'llm-key-save');
      expect(shown(tester, 'llm-key-status'), contains('QRST'));
      await tapKey(tester, 'llm-provider-openai');
      expect(shown(tester, 'llm-key-status'), contains('wxyz'));
      expect(await env.secrets.read('openrouter'), 'or-key-1234567890-QRST');
      expect(await env.secrets.read('openai'), secret);
    });

    testWidgets('a key with characters that cannot go into a header is refused; surrounding blanks are trimmed', (tester) async {
      final env = TestEnv();
      await openLlm(tester, env);
      await typeInto(tester, 'llm-api-key', 'sk-éé-nope');
      await tapKey(tester, 'llm-key-save');
      expect(find.text(l10n.llmApiKeyInvalid), findsOneWidget);
      expect(await env.secrets.read('openai'), isNull);

      await typeInto(tester, 'llm-api-key', 'sk-fine-key-1234');
      expect(find.text(l10n.llmApiKeyInvalid), findsNothing, reason: 'the message clears when typing');
      await tapKey(tester, 'llm-key-save');
      expect(await env.secrets.read('openai'), 'sk-fine-key-1234');

      await typeInto(tester, 'llm-api-key', '');
      await tapKey(tester, 'llm-key-save');
      expect(await env.secrets.read('openai'), 'sk-fine-key-1234', reason: 'an empty field does not erase the key');
    });
  });

  group('the key follows its address (M6 review)', () {
    bool readOnly(WidgetTester tester) => tester.widget<TextField>(find.byKey(const Key('llm-base-url'))).readOnly;

    testWidgets('the address of OpenAI and OpenRouter is locked; Custom (and the local presets) can be edited', (tester) async {
      final env = TestEnv(secrets: {'openai': secret});
      await openLlm(tester, env);
      expect(readOnly(tester), isTrue);
      expect(find.text(l10n.llmBaseUrlLocked), findsOneWidget);
      await tapKey(tester, 'llm-provider-openrouter');
      expect(readOnly(tester), isTrue);
      await tapKey(tester, 'llm-provider-ollama');
      expect(readOnly(tester), isFalse);
      await tapKey(tester, 'llm-provider-custom');
      expect(readOnly(tester), isFalse);
      await tapKey(tester, 'llm-provider-openai');
      expect(readOnly(tester), isTrue);
      expect(find.text(l10n.llmBaseUrlLocked), findsOneWidget);
    });

    testWidgets('a key saved for one address is not sent to another: the screen says so; saving again binds it here', (tester) async {
      final llm = FakeLlm()
        ..failWith = (status: 200, body: '{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}', contentType: 'application/json');
      final env = TestEnv(settings: {'llm_provider': 'custom', 'llm_base_url': 'https://a.example/v1', 'llm_model': 'm'}, llm: llm.client);
      await openLlm(tester, env);
      await typeInto(tester, 'llm-api-key', secret);
      await tapKey(tester, 'llm-key-save');
      expect(find.byKey(const Key('llm-key-other-origin')), findsNothing);
      await tapKey(tester, 'llm-test');
      expect(llm.last.headers['Authorization'], 'Bearer $secret');

      await typeInto(tester, 'llm-base-url', 'https://b.example/v1');
      expect(shown(tester, 'llm-key-other-origin'), l10n.llmKeyOtherOrigin('https://a.example:443', 'https://b.example:443'));
      await tapKey(tester, 'llm-test');
      expect(llm.last.uri.host, 'b.example');
      expect(llm.last.headers['Authorization'], isNull, reason: 'Test connection follows the same rules');

      await typeInto(tester, 'llm-api-key', secret);
      await tapKey(tester, 'llm-key-save');
      expect(find.byKey(const Key('llm-key-other-origin')), findsNothing);
      await tapKey(tester, 'llm-test');
      expect(llm.last.headers['Authorization'], 'Bearer $secret');
    });

    testWidgets('a key cannot be saved before there is a valid address', (tester) async {
      final env = TestEnv(settings: {'llm_provider': 'custom', 'llm_base_url': ''});
      await openLlm(tester, env);
      await typeInto(tester, 'llm-api-key', secret);
      await tapKey(tester, 'llm-key-save');
      expect(find.text(l10n.llmApiKeyNeedsUrl), findsOneWidget);
      expect(env.secrets.slots, isEmpty);
    });

    testWidgets('http: the switch is off by default, stored per origin, and the key is only sent once it is on', (tester) async {
      final llm = FakeLlm()
        ..failWith = (status: 200, body: '{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}', contentType: 'application/json');
      final env = TestEnv(
        settings: {'llm_provider': 'ollama', 'llm_base_url': 'http://192.168.1.20:11434/v1', 'llm_model': 'm'},
        llm: llm.client,
      );
      await openLlm(tester, env);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('llm-cleartext-key'))).value, isFalse);
      await typeInto(tester, 'llm-api-key', secret);
      await tapKey(tester, 'llm-key-save');
      expect(find.byKey(const Key('llm-key-cleartext-blocked')), findsOneWidget);
      await tapKey(tester, 'llm-test');
      expect(llm.last.headers['Authorization'], isNull);

      await tapKey(tester, 'llm-cleartext-key');
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('llm-cleartext-key'))).value, isTrue);
      expect(await env.settings.get('llm_cleartext_origins'), 'http://192.168.1.20:11434');
      expect(find.byKey(const Key('llm-key-cleartext-blocked')), findsNothing);
      await tapKey(tester, 'llm-test');
      expect(llm.last.headers['Authorization'], 'Bearer $secret');

      await typeInto(tester, 'llm-base-url', 'http://192.168.1.21:11434/v1');
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('llm-cleartext-key'))).value, isFalse, reason: 'another origin, not allowed');
      expect(find.byKey(const Key('llm-key-other-origin')), findsOneWidget);
    });

    testWidgets('an https address has no such switch', (tester) async {
      final env = TestEnv();
      await openLlm(tester, env);
      expect(find.byKey(const Key('llm-cleartext-key')), findsNothing);
    });
  });

  group('Test connection', () {
    testWidgets('success: sends a tiny non-streamed request with the key and reports it', (tester) async {
      final llm = FakeLlm();
      final env = TestEnv(
        settings: {'llm_provider': 'openai', 'llm_base_url': 'https://api.openai.com/v1', 'llm_model': 'gpt-4o-mini'},
        secrets: {'openai': secret},
        llm: llm.client,
      );
      await openLlm(tester, env);
      // The request stays open while the test button shows its spinner, which
      // never settles: pump by hand.
      await tester.ensureVisible(find.byKey(const Key('llm-test')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('llm-test')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text(l10n.llmTesting), findsOneWidget);
      // The fake answers a non-streamed completion as one JSON body.
      expect(llm.requests, hasLength(1));
      final r = llm.last;
      expect(r.json['stream'], false);
      expect(r.json['model'], 'gpt-4o-mini');
      expect(r.headers['Authorization'], 'Bearer $secret');
      expect(r.body, isNot(contains(secret)));
      llm.last.controller!.add(
        '{"choices":[{"index":0,"message":{"role":"assistant","content":"OK"},"finish_reason":"stop"}]}'.codeUnits,
      );
      await llm.last.controller!.close();
      await tester.pumpAndSettle();
      expect(shown(tester, 'llm-test-result'), l10n.llmTestOk);
    });

    testWidgets('failure: wrong key shows the unauthorized copy and the provider message', (tester) async {
      final llm = FakeLlm()..error(401, {'message': 'Incorrect API key provided: $secret', 'code': 'invalid_api_key'});
      final env = TestEnv(
        settings: {'llm_provider': 'openai', 'llm_base_url': 'https://api.openai.com/v1', 'llm_model': 'gpt-4o-mini'},
        secrets: {'openai': secret},
        llm: llm.client,
      );
      await openLlm(tester, env);
      await tapKey(tester, 'llm-test');
      expect(shown(tester, 'llm-test-result'), 'Your API key was rejected.');
      expect(shown(tester, 'llm-test-detail'), isNot(contains(secret)));
      expect(find.textContaining(secret), findsNothing);
    });

    testWidgets("failure: model not found names the model; no model asks for one; a blocked URL says why", (tester) async {
      final llm = FakeLlm()..error(404, {'message': 'model not found', 'code': 'model_not_found'});
      final env = TestEnv(
        settings: {'llm_provider': 'openai', 'llm_base_url': 'https://api.openai.com/v1', 'llm_model': 'gpt-9'},
        secrets: {'openai': secret},
        llm: llm.client,
      );
      await openLlm(tester, env);
      await tapKey(tester, 'llm-test');
      expect(shown(tester, 'llm-test-result'), "Model 'gpt-9' isn't available on this endpoint.");

      await typeInto(tester, 'llm-model', '');
      await tapKey(tester, 'llm-test');
      expect(shown(tester, 'llm-test-result'), l10n.llmErrNoModel);

      await tapKey(tester, 'llm-provider-custom');
      await typeInto(tester, 'llm-model', 'gpt-9');
      await typeInto(tester, 'llm-base-url', 'http://example.com/v1');
      final before = llm.requests.length;
      await tapKey(tester, 'llm-test');
      expect(shown(tester, 'llm-test-result'), l10n.llmErrCleartext);
      expect(llm.requests.length, before, reason: 'refused before any request');
    });

    testWidgets('offline', (tester) async {
      final env = TestEnv(settings: {'llm_model': 'm'}, secrets: {'openai': secret});
      await openLlm(tester, env);
      await tapKey(tester, 'llm-test');
      expect(shown(tester, 'llm-test-result'), l10n.llmErrOffline);
    });
  });

  group('Settings > Explanations', () {
    testWidgets('the section lists the connection state, language, tone, audience and the two summary switches', (tester) async {
      final env = TestEnv();
      await openSettings(tester, env);
      expect(find.text(l10n.settingsExplanations), findsOneWidget);
      expect(find.text(l10n.settingsLlmNotSet), findsOneWidget);
      expect(find.text(l10n.settingsLanguageMatchApp), findsOneWidget);
      expect(tester.widget<SegmentedButton<ExplainTone>>(find.byKey(const Key('settings-tone'))).selected, {ExplainTone.casual});
      expect(tester.widget<SegmentedButton<ExplainAudience>>(find.byKey(const Key('settings-audience'))).selected, {ExplainAudience.club});
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('settings-summary'))).value, isTrue, reason: 'on by default (F12)');
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('settings-summary-auto'))).value, isTrue);
    });

    testWidgets('the connection tile shows provider and model once set', (tester) async {
      final env = TestEnv(settings: {'llm_provider': 'openrouter', 'llm_model': 'openai/gpt-4o-mini'});
      await openSettings(tester, env);
      expect(find.text('OpenRouter · openai/gpt-4o-mini'), findsOneWidget);
    });

    testWidgets('language: free text override and back to the app language', (tester) async {
      final env = TestEnv();
      await openSettings(tester, env);
      await tapKey(tester, 'settings-language');
      await tester.enterText(find.byKey(const Key('settings-language-field')), 'Bahasa Melayu');
      await tapKey(tester, 'settings-language-save');
      await tester.pumpAndSettle();
      expect(await env.settings.get('explain_language'), 'Bahasa Melayu');
      expect(find.text('Bahasa Melayu'), findsOneWidget);

      await tapKey(tester, 'settings-language');
      await tapKey(tester, 'settings-language-app');
      await tester.pumpAndSettle();
      expect(await env.settings.get('explain_language'), isNull);
      expect(find.text(l10n.settingsLanguageMatchApp), findsOneWidget);
    });

    testWidgets('tone, audience and the summary switches are saved', (tester) async {
      final env = TestEnv();
      await openSettings(tester, env);
      await tester.tap(find.text(l10n.toneCoach));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.audienceAdvanced));
      await tester.pumpAndSettle();
      expect(await env.settings.get('explain_tone'), 'coach');
      expect(await env.settings.get('explain_audience'), 'advanced');

      await tapKey(tester, 'settings-summary-auto');
      expect(await env.settings.get('summary_auto'), '0');
      await tapKey(tester, 'settings-summary');
      expect(await env.settings.get('summary_enabled'), '0');
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('settings-summary-auto'))).onChanged, isNull, reason: 'nothing to automate when the summary is off');
    });
  });

  testWidgets('the API key field disables suggestions and personalised learning', (tester) async {
    final env = TestEnv();
    await openLlm(tester, env);
    final field = tester.widget<TextField>(find.byKey(const Key('llm-api-key')));
    expect(field.autocorrect, isFalse);
    expect(field.enableSuggestions, isFalse);
    expect(field.enableIMEPersonalizedLearning, isFalse);
    expect(field.keyboardType, TextInputType.visiblePassword);
    expect(field.autofillHints, anyOf(isNull, isEmpty));
  });
}
