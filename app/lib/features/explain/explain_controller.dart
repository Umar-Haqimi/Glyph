import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/providers.dart';
import '../../platform/app_log.dart';
import '../board/board_data.dart';
import '../settings/explain_settings.dart';
import 'generation.dart';

/// Which move the sheet explains.
class ExplainArgs {
  const ExplainArgs(this.gameId, this.ply);

  final int gameId;

  /// 1-based ply of the move.
  final int ply;

  @override
  bool operator ==(Object other) => other is ExplainArgs && other.gameId == gameId && other.ply == ply;

  @override
  int get hashCode => Object.hash(gameId, ply);
}

/// The Explain request of one sheet (SPEC F11): builds the grounded prompt
/// from the stored analysis, checks the cache, streams the answer, and
/// cancels when the sheet closes (the provider is auto-disposed with it).
class ExplainNotifier extends Notifier<GenerationState> {
  ExplainNotifier(this.args);

  final ExplainArgs args;
  late GenerationRunner _runner;
  bool _started = false;

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
    if (!_started) {
      _started = true;
      Future.microtask(start);
    }
    return const GenerationState.connecting();
  }

  /// (Re)starts the request. [regenerate] skips the cache and replaces the
  /// saved text with the new answer.
  Future<void> start({bool regenerate = false}) async {
    if (!ref.mounted) return;
    _runner.reset(const GenerationState.connecting());
    try {
      final settings = await ref.read(explainSettingsProvider.future);
      final readiness = await checkReadiness(settings, ref.read(secretStoreProvider));
      if (!ref.mounted) return;
      if (!readiness.ready) {
        _runner.reset(GenerationState.notConfigured(readiness.problem!));
        return;
      }
      final data = await ref.read(boardDataProvider(args.gameId).future);
      if (!ref.mounted) return;
      final bundle = data == null ? null : _buildPrompt(data, settings);
      if (bundle == null) {
        _runner.reset(const GenerationState(phase: GenerationPhase.failed, error: LlmError(LlmErrorKind.notAnalysed)));
        return;
      }
      final config = readiness.config!;
      final request = LlmRequest(config: config, messages: bundle.messages);
      final key = CacheKey.of(bundle, config, classifierVersion: ClassifierConfig.standard.version);
      await _runner.run(request: request, cacheKey: key, kind: PromptKind.move, gameId: args.gameId, useCache: !regenerate);
    } on Object catch (e) {
      AppLog.warning('Preparing the explanation failed', e);
      if (ref.mounted) {
        _runner.reset(const GenerationState(phase: GenerationPhase.failed, error: LlmError(LlmErrorKind.notAnalysed)));
      }
    }
  }

  PromptBundle? _buildPrompt(BoardData data, ExplainSettings settings) {
    final ply = args.ply;
    if (ply < 1 || ply > data.plyCount) return null;
    // The stored labels keep only label, loss and Win%; the prompt also needs
    // the flags (sacrifice, only move, missed mate, punished error), so the
    // game is classified again from the stored lines: the same rules and
    // the same lines give the same labels (docs/PROGRESS.md, notes for M6).
    final classified = const Classifier().classify(
      startFen: data.game.startFen,
      moves: [for (final p in data.game.plies) p.uci],
      lines: data.lines,
      bookPlies: data.book.bookPlies,
    );
    final move = classified[ply - 1];
    if (move == null) return null;
    return PromptBuilder.move(
      game: data.game,
      ply: ply,
      move: move,
      lines: data.lines,
      book: data.book,
      userSide: data.userSide,
      prefs: settings.prefs(ref.read(appLanguageNameProvider)),
    );
  }

  /// Stop (SPEC state `cancelled`): keeps the text so far.
  void cancel() => _runner.cancel();

  /// Regenerate: a new answer, replacing the cached one.
  Future<void> regenerate() => start(regenerate: true);

  /// Retry after a failure (the cache is consulted again: nothing was saved).
  Future<void> retry() => start();
}

final explainProvider = NotifierProvider.autoDispose.family<ExplainNotifier, GenerationState, ExplainArgs>(
  ExplainNotifier.new,
);
