import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/providers.dart';
import '../../engine/engine_providers.dart';
import '../../platform/app_log.dart';
import '../settings/explain_settings.dart';
import 'generation.dart';

/// The game summary of one game (SPEC F12). Auto-dispose, but held alive while
/// a request is being prepared or streamed: an automatic summary started when
/// the analysis completes keeps running with no report open, and a finished one
/// is simply read from the cache again when the report opens (`loadCached`),
/// so no stale text outlives its inputs.
///
/// The state goes back to idle when the inputs change: the explanation
/// settings (model, endpoint, language, tone, audience, token limit), the API
/// key or where it may be sent ([llmEpochProvider]), a re-analysis, and the
/// game being deleted (the library invalidates the provider, which aborts the
/// request). Its request is its own and never blocks anything.
class SummaryNotifier extends Notifier<GenerationState> {
  SummaryNotifier(this.gameId);

  final int gameId;
  late GenerationRunner _runner;

  /// Bumped by every user-visible start, [cancel] and reset: a preparation that
  /// finds another number after an await was superseded or stopped and must
  /// not go on to send a request.
  int _token = 0;
  bool _inFlight = false;

  @override
  GenerationState build() {
    _runner = GenerationRunner(
      client: ref.watch(llmClientProvider),
      cache: ref.watch(llmCacheRepositoryProvider),
      nowMs: ref.watch(nowMsProvider),
      onChange: (s) => state = s,
    );
    ref.onDispose(_runner.dispose);
    ref.listen<AsyncValue<ExplainSettings>>(explainSettingsProvider, (previous, next) {
      final before = previous?.value;
      final after = next.value;
      if (before != null && after != null && _signature(before) != _signature(after)) _reset();
    });
    ref.listen<int>(llmEpochProvider, (_, _) => _reset());
    return const GenerationState.idle();
  }

  /// Everything a summary depends on that the settings hold.
  static Object _signature(ExplainSettings s) =>
      (s.provider, s.baseUrl, s.model, s.tokenMode, s.tokenValue, s.language, s.tone, s.audience, s.summaryEnabled);

  /// Drops whatever is shown or running and goes back to idle.
  void _reset() {
    _token++;
    _inFlight = false;
    _runner.reset(const GenerationState.idle());
  }

  /// Shows a saved summary, if there is one for the current settings and
  /// analysis; asks nothing. Anything else leaves the state idle (never the
  /// text of an earlier configuration).
  Future<void> loadCached() => _prepare(onlyCache: true);

  /// After the analysis completed: summarises when the toggle and the
  /// automatic setting are on and a model is configured; a saved summary is
  /// reused. Silent when something is missing (the report then offers the
  /// button).
  Future<void> autoGenerate() => _prepare(onlyCache: false, silentIfNotReady: true, autoOnly: true);

  /// The "Summarize game" button.
  Future<void> generate() => _prepare(onlyCache: false);

  /// Regenerate: a fresh answer replacing the saved one.
  Future<void> regenerate() => _prepare(onlyCache: false, regenerate: true);

  /// Stop: also while the request is still being prepared.
  void cancel() {
    _token++;
    _inFlight = false;
    _runner.cancel();
  }

  Future<void> _prepare({
    required bool onlyCache,
    bool regenerate = false,
    bool silentIfNotReady = false,
    bool autoOnly = false,
  }) async {
    if (!ref.mounted) return;
    // One request at a time, including the time before it is sent.
    if ((_inFlight || _runner.state.busy) && !regenerate) return;
    final link = ref.keepAlive(); // released below; held while preparing and streaming
    final token = ++_token;
    _inFlight = true;
    bool stale() => !ref.mounted || token != _token;
    final quiet = onlyCache || silentIfNotReady;
    try {
      if (!quiet) _runner.reset(const GenerationState.connecting());
      final settings = await ref.read(explainSettingsProvider.future);
      if (stale()) return;
      if (!settings.summaryEnabled || (autoOnly && !settings.summaryAuto)) {
        if (onlyCache) _runner.reset(const GenerationState.idle());
        return;
      }
      final vault = ref.read(keyVaultProvider);
      final readiness = await checkReadiness(settings, vault);
      if (stale()) return;
      if (!readiness.ready) {
        if (onlyCache) {
          _runner.reset(const GenerationState.idle());
        } else if (!silentIfNotReady) {
          _runner.reset(GenerationState.notConfigured(readiness.problem!));
        }
        return;
      }
      final loaded = await ref.read(reviewServiceProvider).load(gameId);
      if (stale()) return;
      if (loaded == null) {
        if (onlyCache) {
          _runner.reset(const GenerationState.idle());
        } else if (!silentIfNotReady) {
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
        final hit = await ref.read(llmCacheRepositoryProvider).get(key);
        if (stale()) return;
        _runner.reset(
          hit == null
              ? const GenerationState.idle() // a cache miss shows nothing from before
              : GenerationState(phase: GenerationPhase.done, text: hit.content, request: request, fromCache: true),
        );
        return;
      }
      // The key is looked up for the same settings snapshot that produced
      // `config`, not for whatever the settings are by the time it is read.
      await _runner.run(
        request: request,
        readApiKey: ref.read(keyReaderForProvider)(settings),
        cacheKey: key,
        kind: PromptKind.summary,
        gameId: gameId,
        useCache: !regenerate,
      );
    } on Object catch (e) {
      AppLog.warning('Preparing the game summary failed', e);
      if (!stale() && !quiet) {
        _runner.reset(const GenerationState(phase: GenerationPhase.failed, error: LlmError(LlmErrorKind.notAnalysed)));
      }
    } finally {
      if (token == _token) _inFlight = false;
      link.close();
    }
  }
}

final summaryProvider = NotifierProvider.autoDispose.family<SummaryNotifier, GenerationState, int>(SummaryNotifier.new);
