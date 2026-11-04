import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'app_log.dart';

/// Where API keys live (SPEC 6): **only** here, never in SQLite, the
/// settings table, logs, the clipboard, exported PGN or "View prompt".
///
/// One slot per provider preset, so switching from OpenAI to OpenRouter and
/// back keeps both keys. A key is read when a request is built and dropped
/// again; callers must not keep it in provider state.
abstract interface class SecretStore {
  /// The key in [slot], or null if there is none (also when the platform
  /// store failed: `flutter_secure_storage` wipes its data when the keystore
  /// key is lost, which must read as "no key", not crash the app).
  Future<String?> read(String slot);

  Future<void> write(String slot, String value);

  Future<void> delete(String slot);
}

/// `flutter_secure_storage` with its default `AndroidOptions()` (AES-GCM data
/// key wrapped by an RSA key in the Android Keystore; docs/DECISIONS.md M0,
/// section 7). Backups are off (`allowBackup=false`), so the wrapped key and
/// the ciphertext never part ways.
class FlutterSecretStore implements SecretStore {
  const FlutterSecretStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  static String _name(String slot) => 'llm_api_key.$slot';

  @override
  Future<String?> read(String slot) async {
    try {
      final value = await _storage.read(key: _name(slot));
      return value == null || value.isEmpty ? null : value;
    } on Object catch (e) {
      AppLog.warning('Reading the API key failed', e); // type only
      return null;
    }
  }

  @override
  Future<void> write(String slot, String value) => _storage.write(key: _name(slot), value: value);

  @override
  Future<void> delete(String slot) async {
    try {
      await _storage.delete(key: _name(slot));
    } on Object catch (e) {
      AppLog.warning('Deleting the API key failed', e);
      rethrow;
    }
  }
}

/// Test double that keeps keys in memory.
class InMemorySecretStore implements SecretStore {
  InMemorySecretStore([Map<String, String>? initial]) : _values = {...?initial};

  final Map<String, String> _values;

  /// For assertions: where the keys are (slot names only).
  Iterable<String> get slots => _values.keys;

  int reads = 0;

  @override
  Future<String?> read(String slot) async {
    reads++;
    return _values[slot];
  }

  @override
  Future<void> write(String slot, String value) async => _values[slot] = value;

  @override
  Future<void> delete(String slot) async => _values.remove(slot);
}
