import 'package:glyph_core/glyph_core.dart';

import '../../data/repositories.dart';
import '../../platform/app_log.dart';
import '../../platform/secret_store.dart';
import 'explain_settings.dart';

/// Whether the key stored for a provider may be sent to the current endpoint.
enum KeyAvailability {
  /// No key is stored for this provider.
  none,

  /// A key is stored for the origin the endpoint has now (and, for plain
  /// http, the user allowed sending it there): it will be sent.
  usable,

  /// A key is stored, but it was saved for another origin
  /// (scheme + host + port). It is **not** sent; saving the key again binds
  /// it to the current origin.
  otherOrigin,

  /// A key is stored for this origin, but the origin is plain `http://` and
  /// the user has not allowed sending the key over cleartext to it.
  cleartextBlocked,
}

/// The rules that decide where a stored API key may go (SPEC 6, M6 review).
abstract final class KeyBinding {
  /// `scheme://host:port` of a base URL the policy accepts, else null.
  static String? originOf(String baseUrl) {
    final r = BaseUrlPolicy.check(baseUrl);
    return r.ok ? BaseUrlPolicy.origin(r.uri!) : null;
  }

  /// The origin a key with **no stored binding** may be bound to: only a
  /// hosted preset's own fixed origin (OpenAI, OpenRouter). For a provider
  /// whose address the user chooses (Ollama, LM Studio, Custom) there is none:
  /// binding to "whatever the URL is now" would let a key that lost its binding
  /// (a reset, a hand-edited database) be sent to a new host. Such a key is
  /// treated as unbound: it is not sent until it is saved again.
  static String? legacyOrigin(LlmProvider provider, String baseUrl) =>
      provider.hosted ? originOf(provider.defaultBaseUrl) : null;

  static bool isCleartext(String origin) => origin.startsWith('http://');

  static KeyAvailability availability({
    required bool hasKey,
    required String? boundOrigin,
    required String? currentOrigin,
    required Set<String> cleartextAllowed,
  }) {
    if (!hasKey) return KeyAvailability.none;
    if (currentOrigin == null || boundOrigin == null || boundOrigin != currentOrigin) {
      return KeyAvailability.otherOrigin;
    }
    if (isCleartext(currentOrigin) && !cleartextAllowed.contains(currentOrigin)) {
      return KeyAvailability.cleartextBlocked;
    }
    return KeyAvailability.usable;
  }
}

/// A stored key's state for one (provider, base URL) pair; never the key.
class KeyInfo {
  const KeyInfo({required this.mask, required this.boundOrigin, required this.availability});

  const KeyInfo.none()
      : mask = null,
        boundOrigin = null,
        availability = KeyAvailability.none;

  final String? mask;
  final String? boundOrigin;
  final KeyAvailability availability;
}

/// The single gate between the secret store and a request: a key leaves it
/// only for the origin it was saved for, and over plain http only where the
/// user allowed it. Origins are kept in the settings table (they are not
/// secret); the keys stay in the [SecretStore].
class KeyVault {
  KeyVault(this._store, this._settings);

  final SecretStore _store;
  final SettingsRepository _settings;

  static String _originSetting(LlmProvider p) => '${SettingsKeys.llmKeyOriginPrefix}${p.slot}';

  /// Origins the user allowed to receive the key over plain http.
  Future<Set<String>> cleartextAllowed() async {
    final raw = await _settings.get(SettingsKeys.llmCleartextOrigins) ?? '';
    return {for (final line in raw.split('\n')) if (line.trim().isNotEmpty) line.trim()};
  }

  Future<void> setCleartextAllowed(String origin, bool allowed) async {
    final all = await cleartextAllowed();
    if (allowed) {
      all.add(origin);
    } else {
      all.remove(origin);
    }
    if (all.isEmpty) {
      await _settings.remove(SettingsKeys.llmCleartextOrigins);
    } else {
      await _settings.set(SettingsKeys.llmCleartextOrigins, all.toList().join('\n'));
    }
  }

  Future<String?> _boundOrigin(LlmProvider provider, String baseUrl) async {
    final stored = await _settings.get(_originSetting(provider));
    if (stored != null && stored.isNotEmpty) return stored;
    // No binding stored. Only a hosted preset's fixed origin is ever assumed;
    // anything else stays unbound (null: never sent, see [KeyBinding.legacyOrigin]).
    final origin = KeyBinding.legacyOrigin(provider, baseUrl);
    if (origin != null) await _settings.set(_originSetting(provider), origin);
    return origin;
  }

  /// The state of the key of [provider] for an endpoint at [baseUrl].
  Future<KeyInfo> info(LlmProvider provider, String baseUrl) async {
    final key = await _store.read(provider.slot);
    if (key == null || key.isEmpty) return const KeyInfo.none();
    final bound = await _boundOrigin(provider, baseUrl);
    return KeyInfo(
      mask: ApiKeyStatus.maskOf(key),
      boundOrigin: bound,
      availability: KeyBinding.availability(
        hasKey: true,
        boundOrigin: bound,
        currentOrigin: KeyBinding.originOf(baseUrl),
        cleartextAllowed: await cleartextAllowed(),
      ),
    );
  }

  /// The key to put in a request to [baseUrl], or null when there is none or
  /// the rules above say it must not go there. Call this when the request is
  /// built and drop the result.
  Future<String?> keyFor(LlmProvider provider, String baseUrl) async {
    try {
      final key = await _store.read(provider.slot);
      if (key == null || key.isEmpty) return null;
      final bound = await _boundOrigin(provider, baseUrl);
      final availability = KeyBinding.availability(
        hasKey: true,
        boundOrigin: bound,
        currentOrigin: KeyBinding.originOf(baseUrl),
        cleartextAllowed: await cleartextAllowed(),
      );
      return availability == KeyAvailability.usable ? key : null;
    } on Object catch (e) {
      AppLog.warning('Reading the API key failed', e);
      return null;
    }
  }

  /// Stores [key] for [provider], bound to the origin of [baseUrl]. False when
  /// that URL has no acceptable origin (nothing is stored).
  Future<bool> save(LlmProvider provider, String baseUrl, String key) async {
    final origin = KeyBinding.originOf(baseUrl);
    if (origin == null) return false;
    await _store.write(provider.slot, key);
    await _settings.set(_originSetting(provider), origin);
    return true;
  }

  Future<void> remove(LlmProvider provider) async {
    await _store.delete(provider.slot);
    await _settings.remove(_originSetting(provider));
  }
}
