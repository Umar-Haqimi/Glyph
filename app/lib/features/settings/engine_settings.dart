import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/repositories.dart';

/// Analysis depth presets (SPEC F4). MultiPV is always [EngineDefaults.multiPv].
enum DepthPreset {
  fast(12),
  normal(16),
  deep(20);

  const DepthPreset(this.depth);

  final int depth;
}

/// Engine defaults (SPEC F19 / section 10).
abstract final class EngineDefaults {
  static const DepthPreset preset = DepthPreset.normal;
  static const int hashMb = 64;
  static const int multiPv = 2;

  /// Hash sizes the picker offers (MB). 256 MB is the ceiling lichess mobile
  /// uses per engine; the 32-bit ABI of `multistockfish` allows 2048 at most.
  static const List<int> hashOptionsMb = [16, 32, 64, 128, 256];
  static const int maxHashMb = 256;

  /// Threads the picker offers: 1 up to `cores - 1` (the UI thread and the OS
  /// keep one core; lichess mobile caps at the same value), at least 1.
  static List<int> threadOptions(int cores) => [for (var t = 1; t <= math.max(1, cores - 1); t++) t];

  /// Reported in `analyses.engine`.
  static const String engineName = 'Stockfish 19 light';

  /// `min(4, cores - 2)`, at least 1.
  static int threadsFor(int cores) => math.max(1, math.min(4, cores - 2));

  static int get defaultThreads => threadsFor(Platform.numberOfProcessors);
}

/// The engine settings in effect.
class EngineSettings {
  const EngineSettings({
    this.preset = EngineDefaults.preset,
    required this.threads,
    this.hashMb = EngineDefaults.hashMb,
  });

  final DepthPreset preset;
  final int threads;
  final int hashMb;

  int get depth => preset.depth;

  /// Reads the stored values, falling back to the defaults.
  static Future<EngineSettings> load(SettingsRepository settings, {int? cores}) async {
    final presetName = await settings.get(SettingsKeys.engineDepthPreset);
    final threads = int.tryParse(await settings.get(SettingsKeys.engineThreads) ?? '');
    final hash = int.tryParse(await settings.get(SettingsKeys.engineHashMb) ?? '');
    final coreCount = cores ?? Platform.numberOfProcessors;
    return EngineSettings(
      preset: DepthPreset.values.where((p) => p.name == presetName).firstOrNull ?? EngineDefaults.preset,
      // A stored value from another device (or a hand-edited database) is
      // clamped to what this one can run.
      threads: threads != null && threads >= 1
          ? math.min(threads, math.max(1, coreCount))
          : EngineDefaults.threadsFor(coreCount),
      hashMb: hash != null && hash >= 1 ? math.min(hash, EngineDefaults.maxHashMb) : EngineDefaults.hashMb,
    );
  }

  EngineSettings copyWith({DepthPreset? preset, int? threads, int? hashMb}) =>
      EngineSettings(preset: preset ?? this.preset, threads: threads ?? this.threads, hashMb: hashMb ?? this.hashMb);
}

/// The engine settings (Settings > Engine, SPEC F19). A change applies to the
/// next job; one that is running keeps the values it started with.
class EngineSettingsNotifier extends AsyncNotifier<EngineSettings> {
  @override
  Future<EngineSettings> build() => EngineSettings.load(ref.watch(settingsRepositoryProvider));

  Future<void> setPreset(DepthPreset preset) async {
    final current = await future;
    await ref.read(settingsRepositoryProvider).set(SettingsKeys.engineDepthPreset, preset.name);
    state = AsyncData(current.copyWith(preset: preset));
  }

  Future<void> setThreads(int threads) async {
    final current = await future;
    final t = math.max(1, threads);
    await ref.read(settingsRepositoryProvider).set(SettingsKeys.engineThreads, '$t');
    state = AsyncData(current.copyWith(threads: t));
  }

  Future<void> setHashMb(int mb) async {
    final current = await future;
    final h = mb.clamp(1, EngineDefaults.maxHashMb);
    await ref.read(settingsRepositoryProvider).set(SettingsKeys.engineHashMb, '$h');
    state = AsyncData(current.copyWith(hashMb: h));
  }

  /// Forgets the stored choices: preset Normal, threads `min(4, cores - 2)`, 64 MB.
  Future<void> resetToDefaults() async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.remove(SettingsKeys.engineDepthPreset);
    await repo.remove(SettingsKeys.engineThreads);
    await repo.remove(SettingsKeys.engineHashMb);
    state = AsyncData(await EngineSettings.load(repo));
  }
}

final engineSettingsProvider = AsyncNotifierProvider<EngineSettingsNotifier, EngineSettings>(EngineSettingsNotifier.new);
