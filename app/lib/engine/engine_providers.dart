import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../features/library/library_controller.dart';
import '../features/explain/summary_controller.dart';
import '../features/settings/engine_settings.dart';
import '../platform/app_log.dart';
import 'engine_service.dart';
import 'multistockfish_driver.dart';
import 'repository_analysis_store.dart';
import 'review_service.dart';

export '../features/settings/engine_settings.dart' show engineSettingsProvider;

/// How engines are created. Tests override it with `FakeEngineDriver`
/// (`package:glyph_core/testing.dart`).
final engineDriverFactoryProvider = Provider<EngineDriverFactory>((ref) => MultistockfishDriver.create);

/// Timeouts of the pipeline. Tests shorten them.
final pipelineTimeoutsProvider = Provider<PipelineTimeouts>((ref) => const PipelineTimeouts());

/// The app-scoped owner of the single engine. Also listens to the app
/// lifecycle (paused -> release the engine, resumed -> continue).
final engineServiceProvider = Provider<EngineService>((ref) {
  final now = ref.watch(nowMsProvider);
  final service = EngineService(
    driverFactory: ref.watch(engineDriverFactoryProvider),
    store: RepositoryAnalysisStore(
      ref.watch(analysisRepositoryProvider),
      games: ref.watch(gameRepositoryProvider),
    ),
    clock: _FunctionClock(now),
    timeouts: ref.watch(pipelineTimeoutsProvider),
  );
  final observer = _LifecycleObserver(service);
  WidgetsBinding.instance.addObserver(observer);
  ref.onDispose(() {
    WidgetsBinding.instance.removeObserver(observer);
    unawaited(service.dispose());
  });
  return service;
});

class _FunctionClock implements Clock {
  const _FunctionClock(this._now);

  final int Function() _now;

  @override
  int nowMs() => _now();
}

class _LifecycleObserver with WidgetsBindingObserver {
  _LifecycleObserver(this._service);

  final EngineService _service;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
        unawaited(_service.onAppPaused());
      case AppLifecycleState.resumed:
        unawaited(_service.onAppResumed());
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        break;
    }
  }
}

/// Debug-only: wrap the app in this so a hot reload first releases the engine
/// (running engine isolates break hot reload, `multistockfish` README). In a
/// release build `reassemble` is never called.
class EngineReloadGuard extends ConsumerStatefulWidget {
  const EngineReloadGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<EngineReloadGuard> createState() => _EngineReloadGuardState();
}

class _EngineReloadGuardState extends ConsumerState<EngineReloadGuard> {
  @override
  void reassemble() {
    super.reassemble();
    if (kDebugMode) unawaited(ref.read(engineServiceProvider).releaseForHotReload());
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Labels and accuracy from finished analyses (M4). Tests override the
/// repositories and the opening book, not this.
final reviewServiceProvider = Provider<ReviewService>((ref) {
  return ReviewService(
    games: ref.watch(gameRepositoryProvider),
    analyses: ref.watch(analysisRepositoryProvider),
    settings: ref.watch(settingsRepositoryProvider),
    book: () => ref.read(openingBookProvider.future),
  );
});

/// Job state for the UI. Exposes the one running job (or the last finished
/// one) of the [EngineService]; filter on `state.gameId` to show a game.
class AnalysisJobNotifier extends Notifier<AnalysisJobState> {
  late EngineService _service;

  /// Games whose queued (never started) job was cancelled in this session,
  /// so the UI can show "cancelled" instead of waiting for a start.
  final Set<int> _cancelledWhileQueued = {};

  late ReviewService _review;

  @override
  AnalysisJobState build() {
    _service = ref.watch(engineServiceProvider);
    _review = ref.watch(reviewServiceProvider);
    final sub = _service.states.listen(_onState);
    ref.onDispose(sub.cancel);
    return _service.state;
  }

  void _onState(AnalysisJobState s) {
    final previous = state;
    state = s;
    final id = s.gameId;
    // A job just began for this game (a fresh start throws the old rows away,
    // a resume flips the stored status to `running`): the stored game record
    // the board holds is out of date.
    if (id != null && s is AnalysisRunning && !(previous is AnalysisRunning && previous.gameId == id)) {
      ref.invalidate(gameProvider(id));
      // The lines (and so the facts a summary is built from) are about to
      // change: a summary shown or streaming for the old analysis goes.
      ref.invalidate(summaryProvider(id));
    }
    if (id != null && s.isFinished) {
      if (s is AnalysisCompleted) {
        // Label the moves and compute accuracy before telling the UI.
        unawaited(
          _review
              .classify(id)
              .then((review) {
                // The analysis is done and labelled: start the automatic game
                // summary in the background (SPEC F12). It has its own
                // request and a failure only shows in the report.
                if (review == null || !ref.mounted) return;
                try {
                  unawaited(ref.read(summaryProvider(id).notifier).autoGenerate());
                } on Object catch (e) {
                  AppLog.warning('Starting the game summary failed', e);
                }
              }, onError: (Object e) => AppLog.warning('Classifying a finished analysis failed', e))
              .whenComplete(() => _refresh(id)),
        );
      } else {
        _refresh(id);
      }
    }
  }

  /// The stored summary changed: refresh whoever shows it.
  void _refresh(int id) {
    if (!ref.mounted) return;
    ref.invalidate(gameProvider(id));
    ref.invalidate(reviewDoneProvider(id));
    if (ref.exists(libraryProvider)) unawaited(ref.read(libraryProvider.notifier).refresh());
  }

  bool isQueued(int gameId) => _service.isQueued(gameId);

  /// The game's job is running, paused for the background, or queued.
  bool isActive(int gameId) => _service.isActive(gameId);

  bool wasCancelledWhileQueued(int gameId) => _cancelledWhileQueued.contains(gameId);

  /// Starts (or resumes, from the stored `completed_plies`) the analysis of
  /// [game]. [restart] throws the stored progress away; [depth] overrides the
  /// depth of the engine settings for this job ("Re-analyse at depth…"). A
  /// game whose stored PGN cannot be read ends in `failed(invalidGame)` right
  /// away.
  Future<void> analyse(GameRecord game, {bool restart = false, int? depth}) async {
    _cancelledWhileQueued.remove(game.id);
    if (restart) ref.invalidate(summaryProvider(game.id));
    final AnalysisRequest request;
    try {
      final settings = await ref.read(engineSettingsProvider.future);
      final parsed = parsePgn(game.pgn);
      if (parsed.games.isEmpty) {
        _failInvalid(game, 'the stored PGN has no readable game');
        return;
      }
      request = AnalysisRequest.fromGame(
        game.id,
        parsed.games.first,
        depth: depth ?? settings.depth,
        multipv: EngineDefaults.multiPv,
        threads: settings.threads,
        hashMb: settings.hashMb,
        engineName: EngineDefaults.engineName,
        restart: restart,
      );
    } catch (e) {
      // Settings could not be read: offer Retry rather than spin forever.
      state = AnalysisFailed(game.id, AnalysisFailureKind.engineUnavailable, '$e', 0, game.plyCount + 1);
      return;
    }
    _service.enqueue(request);
  }

  void _failInvalid(GameRecord game, String message) {
    // Only the UI state: there is no job, so nothing is written.
    state = AnalysisFailed(game.id, AnalysisFailureKind.invalidGame, message, 0, game.plyCount + 1);
  }

  Future<void> cancel(int gameId) {
    if (_service.isQueued(gameId)) _cancelledWhileQueued.add(gameId);
    return _service.cancel(gameId);
  }
}

final analysisJobProvider = NotifierProvider<AnalysisJobNotifier, AnalysisJobState>(AnalysisJobNotifier.new);

/// Game ids waiting in the engine queue; rebuilds whoever shows "Queued".
class AnalysisQueueNotifier extends Notifier<List<int>> {
  @override
  List<int> build() {
    final service = ref.watch(engineServiceProvider);
    final sub = service.queueChanges.listen((ids) => state = ids);
    ref.onDispose(sub.cancel);
    return service.queuedGameIds;
  }
}

final analysisQueueProvider = NotifierProvider<AnalysisQueueNotifier, List<int>>(AnalysisQueueNotifier.new);

/// Makes sure a completed game has its labels and accuracy (classifies it if
/// they are missing, e.g. after a kill between the last ply and the review),
/// then completes. The board watches it; M5 will read the labels.
/// The value is true when it had to classify (the stored game changed).
final reviewDoneProvider = FutureProvider.family<bool, int>(
  (ref, gameId) => ref.watch(reviewServiceProvider).ensureClassified(gameId),
);

/// Runs once per app session (the library watches it): re-labels every
/// analysed game when `ClassifierConfig.version` changed since the labels
/// were stored (SPEC 5.4).
final classifierUpkeepProvider = FutureProvider<int>((ref) async {
  final n = await ref.watch(reviewServiceProvider).reclassifyIfStale();
  if (n > 0 && ref.exists(libraryProvider)) unawaited(ref.read(libraryProvider.notifier).refresh());
  return n;
});
