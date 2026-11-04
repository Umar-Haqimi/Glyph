import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/providers.dart';
import '../../engine/engine_providers.dart';
import '../../platform/app_log.dart';
import '../settings/explain_settings.dart';
import 'generation.dart';

/// The game summary of one game (SPEC F12). Kept alive between screens: an
/// automatic summary started when the analysis completes keeps running with
/// no report open, and shows up there later. Its request is its own and never
/// blocks anything.
class SummaryNotifier extends Notifier<GenerationState> {
  SummaryNotifier(this.gameId);

  final int gameId;
  late GenerationRunner _runner;

  @override
  GenerationState build() {
    _runner = GenerationRunner(
      client: ref.watch(llmClientProvider),
      readApiKey: ref.watch(apiKeyReaderProvider),
      cache: ref.watch(llmCacheRepositoryProvider),
      nowMs: ref.watch(nowMsProvider),
      onChange: (s) => state = s,
    );
    ref.onDispose(_runner.dispose);
    return const GenerationState.idle();
  }

  /// Shows a saved summary, if there is one for the current settings and
  /// analysis; asks nothing.
  Future<void> loadCached() => _prepare(onlyCache: true);

  /// After the analysis completed: summarises when the toggle and the
  /// automatic setting are on and a model is configured; a saved summary is
  /// reused. Silent when something is missing (the report then offers the
  /// button).
  Future<void> autoGenerate() async {
    final settings = await ref.read(explainSettingsProvider.future);
    if (!settings.summaryEnabled || !settings.summaryAuto) return;
    await _prepare(onlyCache: false, silentIfNotReady: true);
  }

  /// The "Summarize game" button.
  Future<void> generate() => _prepare(onlyCache: false);

  /// Regenerate: a fresh answer replacing the saved one.
  Future<void> regenerate() => _prepare(onlyCache: false, regenerate: true);

  void cancel() => _runner.cancel();

  Future<void> _prepare({required bool onlyCache, bool regenerate = false, bool silentIfNotReady = false}) async {
    if (!ref.mounted) return;
    if (_runner.state.busy && !regenerate) return; // one request in flight
    try {
      final settings = await ref.read(explainSettingsProvider.future);
      if (!settings.summaryEnabled) return;
      final readiness = await checkReadiness(settings, ref.read(secretStoreProvider));
      if (!ref.mounted) return;
      if (!readiness.ready) {
        if (!onlyCache && !silentIfNotReady) _runner.reset(GenerationState.notConfigured(readiness.problem!));
        return;
      }
      final loaded = await ref.read(reviewServiceProvider).load(gameId);
      if (!ref.mounted) return;
      if (loaded == null) {
        if (!onlyCache && !silentIfNotReady) {
          _runner.reset(const GenerationState(phase: GenerationPhase.failed, error: LlmError(LlmErrorKind.notAnalysed)));
        }
        return;
      }
      final bundle = PromptBuilder.summary(
        game: loaded.game,
        review: loaded.review,
        lines: loaded.lines,
        userSide: loaded.record.userSide,
        prefs: settings.prefs(ref.read(appLanguageNameProvider)),
      );
      final config = readiness.config!;
      final request = LlmRequest(config: config, messages: bundle.messages);
      final key = CacheKey.of(bundle, config, classifierVersion: ClassifierConfig.standard.version);
      if (onlyCache) {
        if (_runner.state.busy) return;
        final hit = await ref.read(llmCacheRepositoryProvider).get(key);
        if (hit != null && ref.mounted && !_runner.state.busy) {
          _runner.reset(GenerationState(phase: GenerationPhase.done, text: hit.content, request: request, fromCache: true));
        }
        return;
      }
      await _runner.run(request: request, cacheKey: key, kind: PromptKind.summary, gameId: gameId, useCache: !regenerate);
    } on Object catch (e) {
      AppLog.warning('Preparing the game summary failed', e);
      if (ref.mounted && !onlyCache && !silentIfNotReady) {
        _runner.reset(const GenerationState(phase: GenerationPhase.failed, error: LlmError(LlmErrorKind.notAnalysed)));
      }
    }
  }
}

final summaryProvider = NotifierProvider.family<SummaryNotifier, GenerationState, int>(SummaryNotifier.new);
