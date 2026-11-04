import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../data/models.dart';
import '../data/providers.dart';
import '../features/library/library_controller.dart';
import '../features/settings/engine_settings.dart';
import 'engine_service.dart';
import 'multistockfish_driver.dart';
import 'repository_analysis_store.dart';

/// How engines are created. Tests override it with `FakeEngineDriver`.
final engineDriverFactoryProvider = Provider<EngineDriverFactory>((ref) => MultistockfishDriver.create);

/// Timeouts of the pipeline. Tests shorten them.
final pipelineTimeoutsProvider = Provider<PipelineTimeouts>((ref) => const PipelineTimeouts());

/// The app-scoped owner of the single engine. Also listens to the app
/// lifecycle (paused -> release the engine, resumed -> continue).
final engineServiceProvider = Provider<EngineService>((ref) {
  final now = ref.watch(nowMsProvider);
  final service = EngineService(
    driverFactory: ref.watch(engineDriverFactoryProvider),
    store: RepositoryAnalysisStore(ref.watch(analysisRepositoryProvider)),
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

/// The engine settings (depth preset, threads, hash).
final engineSettingsProvider = FutureProvider<EngineSettings>(
  (ref) => EngineSettings.load(ref.watch(settingsRepositoryProvider)),
);

/// Job state for the UI. Exposes the one running job (or the last finished
/// one) of the [EngineService]; filter on `state.gameId` to show a game.
class AnalysisJobNotifier extends Notifier<AnalysisJobState> {
  late EngineService _service;

  @override
  AnalysisJobState build() {
    _service = ref.watch(engineServiceProvider);
    final sub = _service.states.listen(_onState);
    ref.onDispose(sub.cancel);
    return _service.state;
  }

  void _onState(AnalysisJobState s) {
    state = s;
    final id = s.gameId;
    if (id != null && s.isFinished) {
      // The stored summary changed: refresh whoever shows it.
      ref.invalidate(gameProvider(id));
      if (ref.exists(libraryProvider)) unawaited(ref.read(libraryProvider.notifier).refresh());
    }
  }

  bool isQueued(int gameId) => _service.isQueued(gameId);

  /// Starts (or resumes, from the stored `completed_plies`) the analysis of
  /// [game]. [restart] throws the stored progress away.
  Future<void> analyse(GameRecord game, {bool restart = false}) async {
    final settings = await ref.read(engineSettingsProvider.future);
    final parsed = parsePgn(game.pgn);
    if (parsed.games.isEmpty) return;
    _service.enqueue(AnalysisRequest.fromGame(
      game.id,
      parsed.games.first,
      depth: settings.depth,
      multipv: EngineDefaults.multiPv,
      threads: settings.threads,
      hashMb: settings.hashMb,
      engineName: EngineDefaults.engineName,
      restart: restart,
    ));
  }

  Future<void> cancel(int gameId) => _service.cancel(gameId);
}

final analysisJobProvider = NotifierProvider<AnalysisJobNotifier, AnalysisJobState>(AnalysisJobNotifier.new);
