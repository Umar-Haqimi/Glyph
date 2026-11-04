import 'dart:ui' show Locale, PlatformDispatcher;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../platform/app_log.dart';
import '../../platform/llm_http.dart';
import '../../platform/secret_store.dart';

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
    final provider = LlmProvider.fromName(await repo.get(SettingsKeys.llmProvider));
    final storedUrl = await repo.get(SettingsKeys.llmBaseUrl);
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

  Future<void> setBaseUrl(String value) async {
    final s = await _current;
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

/// Whether a key is stored for the selected provider, and its mask. The
/// state never holds the key: only `••••` and its last four characters, which
/// is all the UI shows (SPEC 6).
class ApiKeyStatus {
  const ApiKeyStatus.none() : mask = null;
  const ApiKeyStatus.present(String this.mask);

  final String? mask;

  bool get present => mask != null;

  static String maskOf(String key) {
    final tail = key.length >= 8 ? key.substring(key.length - 4) : '';
    return '••••$tail';
  }
}

/// Why a typed-in key is refused.
enum ApiKeyProblem { empty, invalidCharacters }

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
  late SecretStore _store;
  late LlmProvider _provider;

  @override
  Future<ApiKeyStatus> build() async {
    _store = ref.watch(secretStoreProvider);
    // Only the provider choice matters here: typing in other fields must not
    // re-read the secret store.
    _provider = await ref.watch(explainSettingsProvider.selectAsync((s) => s.provider));
    final key = await _store.read(_provider.slot);
    return key == null ? const ApiKeyStatus.none() : ApiKeyStatus.present(ApiKeyStatus.maskOf(key));
  }

  /// Stores [raw] (trimmed of surrounding blanks and newlines) for the
  /// selected provider. Returns null on success.
  Future<ApiKeyProblem?> save(String raw) async {
    final key = raw.trim();
    final problem = ApiKeyRules.check(key);
    if (problem != null) return problem;
    await _store.write(_provider.slot, key);
    state = AsyncData(ApiKeyStatus.present(ApiKeyStatus.maskOf(key)));
    return null;
  }

  Future<void> remove() async {
    await _store.delete(_provider.slot);
    state = const AsyncData(ApiKeyStatus.none());
  }
}

final apiKeyStatusProvider = AsyncNotifierProvider<ApiKeyNotifier, ApiKeyStatus>(ApiKeyNotifier.new);

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
/// docs/DECISIONS.md M6). Reads the secret store once, only to see whether a
/// key exists.
Future<LlmReadiness> checkReadiness(ExplainSettings settings, SecretStore store) async {
  final policy = BaseUrlPolicy.check(settings.baseUrl);
  if (!policy.ok) {
    return LlmReadiness.missing(
      policy.problem == BaseUrlProblem.cleartextNotAllowed ? LlmErrorKind.cleartextBlocked : LlmErrorKind.invalidUrl,
    );
  }
  if (settings.model.trim().isEmpty) return const LlmReadiness.missing(LlmErrorKind.noModel);
  if (!BaseUrlPolicy.isLocalHost(policy.uri!.host)) {
    final key = await store.read(settings.provider.slot);
    if (key == null || key.isEmpty) return const LlmReadiness.missing(LlmErrorKind.noKey);
  }
  return LlmReadiness.ready(settings.config);
}

// --- client ------------------------------------------------------------------

/// How a request's HTTP client is made (tests override it).
final httpClientFactoryProvider = Provider<HttpClientFactory>((ref) => createLlmHttpClient);

final llmClientProvider = Provider<LlmClient>((ref) => LlmClient(httpClient: ref.watch(httpClientFactoryProvider)));

/// Reads the key of the selected provider from the secret store **at the
/// moment a request is built**; nothing keeps it afterwards.
final apiKeyReaderProvider = Provider<Future<String?> Function()>((ref) {
  final store = ref.watch(secretStoreProvider);
  return () async {
    try {
      final settings = await ref.read(explainSettingsProvider.future);
      return await store.read(settings.provider.slot);
    } on Object catch (e) {
      AppLog.warning('Reading the API key failed', e);
      return null;
    }
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
