import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/in_memory.dart';
import 'package:glyph/data/providers.dart';
import 'package:glyph/data/repositories.dart';
import 'package:glyph/features/settings/explain_settings.dart';
import 'package:glyph/features/settings/key_vault.dart';
import 'package:glyph/platform/secret_store.dart';
import 'package:glyph_core/glyph_core.dart';

import '../support/fake_llm.dart';

const key = 'sk-live-ABCDEFGH-wxyz';

void main() {
  late InMemorySecretStore store;
  late InMemorySettingsRepository settings;
  late KeyVault vault;

  setUp(() {
    store = InMemorySecretStore();
    settings = InMemorySettingsRepository();
    vault = KeyVault(store, settings);
  });

  group('a key is bound to the origin it was saved for', () {
    test('it is returned for that origin, however the URL is spelled, and for nothing else', () async {
      expect(await vault.save(LlmProvider.custom, 'https://llm.example.org/v1', key), isTrue);
      for (final same in [
        'https://llm.example.org/v1',
        'HTTPS://LLM.Example.org:443/v1/',
        'https://llm.example.org/other/path',
      ]) {
        expect(await vault.keyFor(LlmProvider.custom, same), key, reason: same);
      }
      for (final other in [
        'https://evil.example.net/v1',
        'https://llm.example.org:8443/v1',
        'https://llm.example.org.evil.net/v1',
        'https://sub.llm.example.org/v1',
        'http://llm.example.org/v1', // other scheme (and refused by the policy anyway)
        '',
        'not a url',
      ]) {
        expect(await vault.keyFor(LlmProvider.custom, other), isNull, reason: other);
      }
      final info = await vault.info(LlmProvider.custom, 'https://evil.example.net/v1');
      expect(info.availability, KeyAvailability.otherOrigin);
      expect(info.boundOrigin, 'https://llm.example.org:443');
      expect(info.mask, '••••wxyz');
    });

    test('saving again binds the key to the current origin; removing deletes key and binding', () async {
      await vault.save(LlmProvider.custom, 'https://a.example/v1', key);
      expect(await vault.keyFor(LlmProvider.custom, 'https://b.example/v1'), isNull);
      await vault.save(LlmProvider.custom, 'https://b.example/v1', key);
      expect(await vault.keyFor(LlmProvider.custom, 'https://b.example/v1'), key);
      expect(await vault.keyFor(LlmProvider.custom, 'https://a.example/v1'), isNull);
      await vault.remove(LlmProvider.custom);
      expect(store.slots, isEmpty);
      expect(await settings.get('${SettingsKeys.llmKeyOriginPrefix}custom'), isNull);
    });

    test('no key is stored when the URL has no acceptable origin', () async {
      expect(await vault.save(LlmProvider.custom, '', key), isFalse);
      expect(await vault.save(LlmProvider.custom, 'http://example.com/v1', key), isFalse);
      expect(store.slots, isEmpty);
    });

    test('plain http: never by default, only for the origin the user allowed', () async {
      const lan = 'http://192.168.1.20:11434/v1';
      await vault.save(LlmProvider.ollama, lan, key);
      expect(await vault.keyFor(LlmProvider.ollama, lan), isNull, reason: 'default off');
      expect((await vault.info(LlmProvider.ollama, lan)).availability, KeyAvailability.cleartextBlocked);

      await vault.setCleartextAllowed('http://192.168.1.20:11434', true);
      expect(await vault.keyFor(LlmProvider.ollama, lan), key);
      expect(await vault.keyFor(LlmProvider.ollama, 'http://192.168.1.20:11435/v1'), isNull, reason: 'another port is another origin');
      expect(await vault.keyFor(LlmProvider.ollama, 'http://192.168.1.21:11434/v1'), isNull);

      await vault.setCleartextAllowed('http://192.168.1.20:11434', false);
      expect(await vault.keyFor(LlmProvider.ollama, lan), isNull);
      expect(await settings.get(SettingsKeys.llmCleartextOrigins), isNull);
    });

    test('https needs no opt-in', () async {
      await vault.save(LlmProvider.openai, 'https://api.openai.com/v1', key);
      expect(await vault.keyFor(LlmProvider.openai, 'https://api.openai.com/v1'), key);
      expect(await settings.get(SettingsKeys.llmCleartextOrigins), isNull);
    });
  });

  group('keys stored before bindings existed', () {
    test('a hosted preset binds to the preset origin, whatever its URL field was edited to', () async {
      await store.write('openai', key);
      expect(await vault.keyFor(LlmProvider.openai, 'https://evil.example.net/v1'), isNull);
      expect(await settings.get('${SettingsKeys.llmKeyOriginPrefix}openai'), 'https://api.openai.com:443');
      expect(await vault.keyFor(LlmProvider.openai, 'https://api.openai.com/v1'), key);
    });

    test('a key of Custom / Ollama binds to the current URL on first read, then stays there', () async {
      await store.write('custom', key);
      expect(await vault.keyFor(LlmProvider.custom, 'https://mine.example/v1'), key);
      expect(await vault.keyFor(LlmProvider.custom, 'https://other.example/v1'), isNull);
    });

    test('with an unusable URL the key is not sent anywhere', () async {
      await store.write('custom', key);
      expect(await vault.keyFor(LlmProvider.custom, ''), isNull);
    });
  });

  group('hosted presets are locked to their address', () {
    test('settings saved with an edited OpenAI / OpenRouter address load as Custom, and the preset key does not follow', () async {
      final repo = InMemorySettingsRepository({
        SettingsKeys.llmProvider: 'openai',
        SettingsKeys.llmBaseUrl: 'https://evil.example.net/v1',
        SettingsKeys.llmModel: 'm',
      });
      await store.write('openai', key);
      final loaded = await ExplainSettings.load(repo);
      expect(loaded.provider, LlmProvider.custom);
      expect(loaded.baseUrl, 'https://evil.example.net/v1');
      expect(await repo.get(SettingsKeys.llmProvider), 'custom', reason: 'persisted');
      final readiness = await checkReadiness(loaded, KeyVault(store, repo));
      expect(readiness.problem, LlmErrorKind.noKey);

      final same = InMemorySettingsRepository({
        SettingsKeys.llmProvider: 'openrouter',
        SettingsKeys.llmBaseUrl: 'https://openrouter.ai/api/v1/',
      });
      expect((await ExplainSettings.load(same)).provider, LlmProvider.openrouter, reason: 'the same address, spelled differently');
    });

    test('setBaseUrl on a hosted preset switches to Custom', () async {
      final container = ProviderContainer(overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        secretStoreProvider.overrideWithValue(store),
      ]);
      addTearDown(container.dispose);
      final notifier = container.read(explainSettingsProvider.notifier);
      await container.read(explainSettingsProvider.future);
      await notifier.setBaseUrl('https://api.openai.com/v1/');
      expect(container.read(explainSettingsProvider).value!.provider, LlmProvider.openai);
      await notifier.setBaseUrl('https://proxy.example.net/v1');
      final s = container.read(explainSettingsProvider).value!;
      expect(s.provider, LlmProvider.custom);
      expect(s.baseUrl, 'https://proxy.example.net/v1');
      expect(await settings.get(SettingsKeys.llmProvider), 'custom');
    });
  });

  group('requests carry the key only where the rules allow (through the real client)', () {
    ProviderContainer containerFor(FakeLlm llm) {
      final c = ProviderContainer(overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        secretStoreProvider.overrideWithValue(store),
        llmClientProvider.overrideWithValue(llm.client),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    Future<String?> authorizationOf(ProviderContainer c, FakeLlm llm) async {
      final s = await c.read(explainSettingsProvider.future);
      final error = await llm.client.testConnection(s.config, readApiKey: c.read(keyReaderForProvider)(s));
      expect(error, isNull);
      return llm.last.headers['Authorization'];
    }

    FakeLlm okLlm() => FakeLlm()
      ..failWith = (status: 200, body: '{"choices":[{"message":{"content":"OK"},"finish_reason":"stop"}]}', contentType: 'application/json');

    test('Test connection: key for the saved origin goes, key for another origin does not', () async {
      final llm = okLlm();
      final c = containerFor(llm);
      await vault.save(LlmProvider.custom, 'https://a.example/v1', key);
      await settings.set(SettingsKeys.llmProvider, 'custom');
      await settings.set(SettingsKeys.llmModel, 'm');
      await settings.set(SettingsKeys.llmBaseUrl, 'https://a.example/v1');
      expect(await authorizationOf(c, llm), 'Bearer $key');

      await c.read(explainSettingsProvider.notifier).setBaseUrl('https://b.example/v1');
      expect(await authorizationOf(c, llm), isNull);
      expect(llm.last.uri.host, 'b.example', reason: 'the request still goes out, without the key');
      expect(llm.last.body, isNot(contains(key)));
    });

    test('plain http to a LAN server: no Authorization until the user allows that origin', () async {
      final llm = okLlm();
      final c = containerFor(llm);
      await vault.save(LlmProvider.ollama, 'http://192.168.1.20:11434/v1', key);
      await settings.set(SettingsKeys.llmProvider, 'ollama');
      await settings.set(SettingsKeys.llmModel, 'm');
      await settings.set(SettingsKeys.llmBaseUrl, 'http://192.168.1.20:11434/v1');
      expect(await authorizationOf(c, llm), isNull);

      await vault.setCleartextAllowed('http://192.168.1.20:11434', true);
      expect(await authorizationOf(c, llm), 'Bearer $key');
    });

    test('readiness: a key saved for another origin counts as no key on a public server', () async {
      final c = containerFor(FakeLlm());
      await vault.save(LlmProvider.custom, 'https://a.example/v1', key);
      final other = const ExplainSettings(provider: LlmProvider.custom, baseUrl: 'https://b.example/v1', model: 'm');
      expect((await checkReadiness(other, c.read(keyVaultProvider))).problem, LlmErrorKind.noKey);
      final same = other.copyWith(baseUrl: 'https://a.example/v1');
      expect((await checkReadiness(same, c.read(keyVaultProvider))).ready, isTrue);
    });

    test('the reader belongs to its settings snapshot, not to the settings of the moment it runs', () async {
      final llm = okLlm();
      final c = containerFor(llm);
      await vault.save(LlmProvider.openai, 'https://api.openai.com/v1', key);
      await settings.set(SettingsKeys.llmProvider, 'openai');
      final snapshot = await c.read(explainSettingsProvider.future);
      final reader = c.read(keyReaderForProvider)(snapshot);
      await c.read(explainSettingsProvider.notifier).setProvider(LlmProvider.custom);
      await c.read(explainSettingsProvider.notifier).setBaseUrl('https://elsewhere.example/v1');
      expect(await reader(), key, reason: 'still the OpenAI key for the OpenAI config of the snapshot');
      final now = c.read(explainSettingsProvider).value!;
      expect(await c.read(keyReaderForProvider)(now)(), isNull);
    });
  });
}
