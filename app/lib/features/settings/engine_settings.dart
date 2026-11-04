import 'dart:io';
import 'dart:math' as math;

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
    return EngineSettings(
      preset: DepthPreset.values.where((p) => p.name == presetName).firstOrNull ?? EngineDefaults.preset,
      threads: threads != null && threads >= 1
          ? threads
          : (cores == null ? EngineDefaults.defaultThreads : EngineDefaults.threadsFor(cores)),
      hashMb: hash != null && hash >= 1 ? hash : EngineDefaults.hashMb,
    );
  }
}
