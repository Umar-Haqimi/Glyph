import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../platform/app_log.dart';
import '../../platform/online_http.dart';
import '../../platform/shared_exports.dart';
import '../explain/summary_controller.dart';
import '../library/library_controller.dart';
import 'account_settings.dart';
import 'appearance_settings.dart';
import 'engine_settings.dart';
import 'explain_settings.dart';

/// Some of what "Delete all data" had to remove could not be removed. The rest
/// was removed; running the action again retries the failed parts.
class DataManagementException implements Exception {
  const DataManagementException(this.failedSteps);

  final List<String> failedSteps;

  @override
  String toString() => 'DataManagementException(${failedSteps.join(', ')})';
}

/// The Settings > Data actions (SPEC F19 "data management").
///
/// * **Clear saved explanations** empties `llm_cache` (explanations and
///   summaries); they are generated again on demand.
/// * **Clear online cache** empties `http_cache` (the chess.com `ETag` copies).
/// * **Delete all data** removes every game with its analysis, saved
///   explanations, the online cache, every setting (accounts, model,
///   appearance, engine), every stored API key and the exported PGN file in
///   the cache, and stops running analyses. The app is then as after a fresh
///   install.
///
///   Fail-safe for keys: a key is only ever sendable to the origin it is bound
///   to (`KeyVault`). If the keystore refuses to delete a key, its binding row
///   is kept when the rest of the settings are cleared, so the surviving key
///   can still only go where it was saved for (never to a new address), and
///   the action reports the failure; running it again retries.
class DataManagement {
  DataManagement(this._ref);

  final Ref _ref;

  Future<int> clearExplanations() async {
    final removed = await _ref.read(llmCacheRepositoryProvider).clear();
    // A summary that is shown or streaming belongs to the cache just emptied.
    _ref.invalidate(summaryProvider);
    return removed;
  }

  Future<void> clearOnlineCache() => _ref.read(onlineCacheProvider).clear();

  Future<void> deleteAll() async {
    final failed = <String>[];
    Future<void> step(String name, Future<void> Function() run) async {
      try {
        await run();
      } on Object catch (e) {
        // Type only (AppLog's rule): the message could name a path or a row.
        AppLog.warning('Deleting data failed', e);
        failed.add(name);
      }
    }

    await step('games', () async => _ref.read(libraryProvider.notifier).deleteAllGames());
    await step('explanations', () async => _ref.read(llmCacheRepositoryProvider).clear());
    await step('online cache', () => _ref.read(onlineCacheProvider).clear());
    await step('exported files', () => _ref.read(sharedExportsProvider).clear());
    final keptBindings = <String, String>{};
    await step('keys', () async {
      final store = _ref.read(secretStoreProvider);
      final settings = _ref.read(settingsRepositoryProvider);
      Object? first;
      for (final provider in LlmProvider.values) {
        try {
          await store.delete(provider.slot);
        } on Object catch (e) {
          first ??= e;
          // This key survives: remember where it is bound, so clearing the
          // settings below does not turn it into a key that follows the URL.
          final bound = await settings.get('${SettingsKeys.llmKeyOriginPrefix}${provider.slot}');
          if (bound != null) keptBindings['${SettingsKeys.llmKeyOriginPrefix}${provider.slot}'] = bound;
        }
      }
      if (first != null) throw first;
    });
    // Settings last: the key bindings and everything else go with it.
    await step('settings', () async {
      final settings = _ref.read(settingsRepositoryProvider);
      await settings.clear();
      for (final entry in keptBindings.entries) {
        await settings.set(entry.key, entry.value);
      }
    });

    // Everything that cached a setting reads the (now empty) store again.
    _ref.invalidate(explainSettingsProvider);
    _ref.invalidate(accountSettingsProvider);
    _ref.invalidate(engineSettingsProvider);
    _ref.invalidate(apiKeyStatusProvider);
    _ref.invalidate(cleartextOptInProvider);
    _ref.invalidate(summaryProvider);
    _ref.read(llmEpochProvider.notifier).bump();
    _ref.read(appearanceProvider.notifier).reset();
    if (failed.isNotEmpty) throw DataManagementException(failed);
  }
}

final dataManagementProvider = Provider<DataManagement>(DataManagement.new);
