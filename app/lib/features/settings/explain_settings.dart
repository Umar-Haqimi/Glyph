import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../platform/llm_http.dart';
import '../../platform/secret_store.dart';
import 'key_vault.dart';

/// The provider presets of SPEC F13. A preset only prefills the base URL (and
/// picks the slot of the stored API key); everything is OpenAI-compatible.
enum LlmProvider {
  openai('https://api.openai.com/v1'),
  openrouter('https://openrouter.ai/api/v1'),
  ollama('http://localhost:11434/v1'),
  lmstudio('http://localhost:1234/v1'),
  custom('');

  const LlmProvider(this.defaultBaseUrl);

  /// Prefilled base URL ("localhost" is the phone itself: for Ollama /
  /// LM Studio on a computer the user enters its LAN address).
  final String defaultBaseUrl;

  /// Key slot in the secret store.
  String get slot => name;

  /// A named hosted service: its base URL is fixed (to change it, use
  /// Custom), so the key stored for it can only ever go to that service.
  bool get hosted => this == openai || this == openrouter;

  static LlmProvider fromName(String? name) =>
      LlmProvider.values.where((p) => p.name == name).firstOrNull ?? LlmProvider.openai;
}

/// Everything under Settings > Explanations (SPEC F12, F13, F14), none of it
/// secret. The API key is not here.
class ExplainSettings {
  const ExplainSettings({
    this.provider = LlmProvider.openai,
    String? baseUrl,
    this.model = '',
    this.tokenMode = TokenLimitMode.none,
    this.tokenValue = 1024,
    this.language = '',
    this.tone = ExplainTone.casual,
    this.audience = ExplainAudience.club,
    this.summaryEnabled = true,
    this.summaryAuto = true,
  }) : baseUrl = baseUrl ?? '';

  final LlmProvider provider;
  final String baseUrl;
  final String model;
  final TokenLimitMode tokenMode;
  final int tokenValue;

  /// Free-text override; empty = match the app language.
  final String language;
  final ExplainTone tone;
  final ExplainAudience audience;
  final bool summaryEnabled;
  final bool summaryAuto;

  LlmConfig get config => LlmConfig(
        baseUrl: baseUrl,
        model: model.trim(),
        tokenLimitMode: tokenMode,
        tokenLimit: tokenValue,
      );

  /// The prompt preferences; [appLanguage] is the English name of the app
  /// language (used when no override is set).
  ExplainPrefs prefs(String appLanguage) => ExplainPrefs(
        language: language.trim().isEmpty ? appLanguage : language.trim(),
        tone: tone,
        audience: audience,
      );

  ExplainSettings copyWith({
    LlmProvider? provider,
    String? baseUrl,
    String? model,
    TokenLimitMode? tokenMode,
    int? tokenValue,
    String? language,
    ExplainTone? tone,
    ExplainAudience? audience,
    bool? summaryEnabled,
    bool? summaryAuto,
  }) =>
      ExplainSettings(
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        tokenMode: tokenMode ?? this.tokenMode,
        tokenValue: tokenValue ?? this.tokenValue,
        language: language ?? this.language,
        tone: tone ?? this.tone,
        audience: audience ?? this.audience,
        summaryEnabled: summaryEnabled ?? this.summaryEnabled,
        summaryAuto: summaryAuto ?? this.summaryAuto,
      );

  static Future<ExplainSettings> load(SettingsRepository repo) async {
    var provider = LlmProvider.fromName(await repo.get(SettingsKeys.llmProvider));
    final storedUrl = await repo.get(SettingsKeys.llmBaseUrl);
    if (provider.hosted && storedUrl != null) {
      // Settings saved when the field of a hosted preset was still editable:
      // a different address is a custom endpoint, and the preset's key must
      // not follow it there.
      if (BaseUrlPolicy.check(storedUrl).normalized != BaseUrlPolicy.check(provider.defaultBaseUrl).normalized) {
        provider = LlmProvider.custom;
        await repo.set(SettingsKeys.llmProvider, provider.name);
      }
    }
    final tokenValue = int.tryParse(await repo.get(SettingsKeys.llmTokenValue) ?? '');
    return ExplainSettings(
      provider: provider,
      baseUrl: storedUrl ?? provider.defaultBaseUrl,
      model: await repo.get(SettingsKeys.llmModel) ?? '',
      tokenMode: TokenLimitMode.fromName(await repo.get(SettingsKeys.llmTokenMode)),
      tokenValue: tokenValue != null && tokenValue > 0 ? tokenValue : 1024,
      language: await repo.get(SettingsKeys.explainLanguage) ?? '',
      tone: ExplainTone.fromName(await repo.get(SettingsKeys.explainTone)),
      audience: ExplainAudience.fromName(await repo.get(SettingsKeys.explainAudience)),
      summaryEnabled: (await repo.get(SettingsKeys.summaryEnabled)) != '0',
      summaryAuto: (await repo.get(SettingsKeys.summaryAuto)) != '0',
    );
  }
}

/// Loads and saves [ExplainSettings]. Every setter updates the state first and
/// then persists, so typing in a text field never waits for the database.
class ExplainSettingsNotifier extends AsyncNotifier<ExplainSettings> {
  late SettingsRepository _repo;

  @override
  Future<ExplainSettings> build() {
    _repo = ref.watch(settingsRepositoryProvider);
    return ExplainSettings.load(_repo);
  }

  Future<void> _update(ExplainSettings next, Map<String, String?> writes) async {
    state = AsyncData(next);
    for (final MapEntry(:key, :value) in writes.entries) {
      if (value == null) {
        await _repo.remove(key);
      } else {
        await _repo.set(key, value);
      }
    }
  }

  Future<ExplainSettings> get _current => future;

  /// Choosing a preset prefills its base URL and clears the model name
  /// (model names differ per provider).
  Future<void> setProvider(LlmProvider provider) async {
    final s = await _current;
    if (provider == s.provider) return;
    final url = provider == LlmProvider.custom ? s.baseUrl : provider.defaultBaseUrl;
    await _update(
      s.copyWith(provider: provider, baseUrl: url, model: ''),
      {SettingsKeys.llmProvider: provider.name, SettingsKeys.llmBaseUrl: url, SettingsKeys.llmModel: ''},
    );
  }

  /// A hosted preset's address is fixed: any other address makes the
  /// connection Custom (with its own, empty key slot).
  Future<void> setBaseUrl(String value) async {
    final s = await _current;
    if (s.provider.hosted && BaseUrlPolicy.check(value).normalized != BaseUrlPolicy.check(s.provider.defaultBaseUrl).normalized) {
      await _update(
        s.copyWith(provider: LlmProvider.custom, baseUrl: value),
        {SettingsKeys.llmProvider: LlmProvider.custom.name, SettingsKeys.llmBaseUrl: value},
      );
      return;
    }
    await _update(s.copyWith(baseUrl: value), {SettingsKeys.llmBaseUrl: value});
  }

  Future<void> setModel(String value) async {
    final s = await _current;
    await _update(s.copyWith(model: value), {SettingsKeys.llmModel: value});
  }

  Future<void> setTokenMode(TokenLimitMode mode) async {
    final s = await _current;
    await _update(s.copyWith(tokenMode: mode), {SettingsKeys.llmTokenMode: mode.name});
  }

  Future<void> setTokenValue(int value) async {
    final s = await _current;
    await _update(s.copyWith(tokenValue: value), {SettingsKeys.llmTokenValue: '$value'});
  }

  Future<void> setLanguage(String value) async {
    final s = await _current;
    final text = value.trim();
    await _update(s.copyWith(language: text), {SettingsKeys.explainLanguage: text.isEmpty ? null : text});
  }

  Future<void> setTone(ExplainTone tone) async {
    final s = await _current;
    await _update(s.copyWith(tone: tone), {SettingsKeys.explainTone: tone.name});
  }

  Future<void> setAudience(ExplainAudience audience) async {
    final s = await _current;
    await _update(s.copyWith(audience: audience), {SettingsKeys.explainAudience: audience.name});
  }

  Future<void> setSummaryEnabled(bool value) async {
    final s = await _current;
    await _update(s.copyWith(summaryEnabled: value), {SettingsKeys.summaryEnabled: value ? '1' : '0'});
  }

  Future<void> setSummaryAuto(bool value) async {
    final s = await _current;
    await _update(s.copyWith(summaryAuto: value), {SettingsKeys.summaryAuto: value ? '1' : '0'});
  }
}

final explainSettingsProvider =
    AsyncNotifierProvider<ExplainSettingsNotifier, ExplainSettings>(ExplainSettingsNotifier.new);

// --- the API key -------------------------------------------------------------

/// Where API keys are stored. `main()` provides the Android keystore backed
/// store; tests provide [InMemorySecretStore].
final secretStoreProvider = Provider<SecretStore>(
  (ref) => throw UnimplementedError('secretStoreProvider must be overridden'),
);

/// Bumped when something changes that decides what a request may carry or
/// where (API key saved or removed, plain-http opt-in): per-game state derived
/// from it (the summary) goes back to idle.
class LlmEpochNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final llmEpochProvider = NotifierProvider<LlmEpochNotifier, int>(LlmEpochNotifier.new);

final keyVaultProvider = Provider<KeyVault>(
  (ref) => KeyVault(ref.watch(secretStoreProvider), ref.watch(settingsRepositoryProvider)),
);

/// Whether a key is stored for the selected provider, and its mask. The
/// state never holds the key: only `••••` and its last four characters, which
/// is all the UI shows (SPEC 6), and the origin it is bound to.
class ApiKeyStatus {
  const ApiKeyStatus.none()
      : mask = null,
        boundOrigin = null;
  const ApiKeyStatus.present(String this.mask, {this.boundOrigin});

  final String? mask;

  /// `scheme://host:port` the key was saved for.
  final String? boundOrigin;

  bool get present => mask != null;

  static String maskOf(String key) {
    final tail = key.length >= 8 ? key.substring(key.length - 4) : '';
    return '••••$tail';
  }
}

/// Why a typed-in key is refused.
enum ApiKeyProblem { empty, invalidCharacters, noValidUrl }

abstract final class ApiKeyRules {
  /// Printable ASCII without spaces: every real key is, and anything else
  /// (a pasted newline, a space, a smart quote) would corrupt the header.
  static ApiKeyProblem? check(String key) {
    if (key.isEmpty) return ApiKeyProblem.empty;
    if (!RegExp(r'^[\x21-\x7E]+$').hasMatch(key)) return ApiKeyProblem.invalidCharacters;
    return null;
  }
}

class ApiKeyNotifier extends AsyncNotifier<ApiKeyStatus> {
  late KeyVault _vault;
  late LlmProvider _provider;

  @override
  Future<ApiKeyStatus> build() async {
    _vault = ref.watch(keyVaultProvider);
    // Only the provider choice matters here: typing in other fields must not
    // re-read the secret store.
    _provider = await ref.watch(explainSettingsProvider.selectAsync((s) => s.provider));
    final baseUrl = ref.read(explainSettingsProvider).value?.baseUrl ?? _provider.defaultBaseUrl;
    final info = await _vault.info(_provider, baseUrl);
    return info.mask == null ? const ApiKeyStatus.none() : ApiKeyStatus.present(info.mask!, boundOrigin: info.boundOrigin);
  }

  /// Stores [raw] (trimmed of surrounding blanks and newlines) for the
  /// selected provider, bound to the origin of the current base URL. Returns
  /// null on success.
  Future<ApiKeyProblem?> save(String raw) async {
    final key = raw.trim();
    final problem = ApiKeyRules.check(key);
    if (problem != null) return problem;
    final settings = await ref.read(explainSettingsProvider.future);
    if (!await _vault.save(_provider, settings.baseUrl, key)) return ApiKeyProblem.noValidUrl;
    state = AsyncData(ApiKeyStatus.present(ApiKeyStatus.maskOf(key), boundOrigin: KeyBinding.originOf(settings.baseUrl)));
    ref.read(llmEpochProvider.notifier).bump();
    return null;
  }

  Future<void> remove() async {
    await _vault.remove(_provider);
    state = const AsyncData(ApiKeyStatus.none());
    ref.read(llmEpochProvider.notifier).bump();
  }
}

final apiKeyStatusProvider = AsyncNotifierProvider<ApiKeyNotifier, ApiKeyStatus>(ApiKeyNotifier.new);

/// The origins the user allowed to receive the key over plain http.
class CleartextOptInNotifier extends AsyncNotifier<Set<String>> {
  @override
  Future<Set<String>> build() => ref.watch(keyVaultProvider).cleartextAllowed();

  Future<void> allow(String origin, bool allowed) async {
    await ref.read(keyVaultProvider).setCleartextAllowed(origin, allowed);
    state = AsyncData(await ref.read(keyVaultProvider).cleartextAllowed());
    ref.read(llmEpochProvider.notifier).bump();
  }
}

final cleartextOptInProvider = AsyncNotifierProvider<CleartextOptInNotifier, Set<String>>(CleartextOptInNotifier.new);

/// Whether the stored key will be sent to the endpoint the settings point to
/// now (derived: no secret store access while typing).
final keyAvailabilityProvider = Provider<KeyAvailability>((ref) {
  final settings = ref.watch(explainSettingsProvider).value;
  final status = ref.watch(apiKeyStatusProvider).value;
  if (settings == null || status == null) return KeyAvailability.none;
  return KeyBinding.availability(
    hasKey: status.present,
    boundOrigin: status.boundOrigin,
    currentOrigin: KeyBinding.originOf(settings.baseUrl),
    cleartextAllowed: ref.watch(cleartextOptInProvider).value ?? const {},
  );
});

// --- readiness ---------------------------------------------------------------

/// Whether a request can be made now; [problem] is the first thing missing.
class LlmReadiness {
  const LlmReadiness.ready(this.config) : problem = null;
  const LlmReadiness.missing(LlmErrorKind this.problem) : config = null;

  final LlmConfig? config;
  final LlmErrorKind? problem;

  bool get ready => problem == null;
}

/// Checks [settings] and the key slot. A key is only required for hosts that
/// are not local / private: Ollama and LM Studio run without one (SPEC F13,
/// docs/DECISIONS.md M6). A key that was saved for another origin (or that may
/// not travel over plain http) counts as no key. Reads the secret store once,
/// only to see whether a usable key exists.
Future<LlmReadiness> checkReadiness(ExplainSettings settings, KeyVault vault) async {
  final policy = BaseUrlPolicy.check(settings.baseUrl);
  if (!policy.ok) {
    return LlmReadiness.missing(
      policy.problem == BaseUrlProblem.cleartextNotAllowed ? LlmErrorKind.cleartextBlocked : LlmErrorKind.invalidUrl,
    );
  }
  if (settings.model.trim().isEmpty) return const LlmReadiness.missing(LlmErrorKind.noModel);
  if (!BaseUrlPolicy.isLocalHost(policy.uri!.host)) {
    final key = await vault.keyFor(settings.provider, settings.baseUrl);
    if (key == null || key.isEmpty) return const LlmReadiness.missing(LlmErrorKind.noKey);
  }
  return LlmReadiness.ready(settings.config);
}

// --- client ------------------------------------------------------------------

/// How a request's HTTP client is made (tests override it).
final httpClientFactoryProvider = Provider<HttpClientFactory>((ref) => createLlmHttpClient);

final llmClientProvider = Provider<LlmClient>((ref) => LlmClient(httpClient: ref.watch(httpClientFactoryProvider)));

/// Reads a key at the moment a request is built; nothing keeps it afterwards.
typedef KeyReader = Future<String?> Function();

/// Makes the key reader of **one settings snapshot**: the provider and base
/// URL that produced a request's config are the ones the key is looked up and
/// checked for, even if the settings change while the request is prepared. The
/// reader returns null when the key was saved for another origin or may not be
/// sent over plain http (see [KeyVault]).
final keyReaderForProvider = Provider<KeyReader Function(ExplainSettings)>((ref) {
  final vault = ref.watch(keyVaultProvider);
  return (ExplainSettings s) {
    final provider = s.provider;
    final baseUrl = s.baseUrl;
    return () => vault.keyFor(provider, baseUrl);
  };
});

// --- explanation language ------------------------------------------------------

/// The English name of a UI language, as the prompt wants it ("answer in
/// {language}"). Only English ships in v1; Malay is planned (N8).
String languageNameOf(Locale locale) => switch (locale.languageCode) {
      'ms' => 'Bahasa Melayu',
      'en' => 'English',
      final code => code,
    };

/// The language the app is shown in (v1: always English, the only supported
/// locale), used when no language override is set.
final appLanguageNameProvider = Provider<String>((ref) {
  const supported = {'en'};
  final device = PlatformDispatcher.instance.locale;
  return languageNameOf(supported.contains(device.languageCode) ? device : const Locale('en'));
});
