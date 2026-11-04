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

  /// Hash sizes the picker offers (MB) on a device that can take them all.
  /// 256 MB is the ceiling lichess mobile uses per engine; the 32-bit ABI of
  /// `multistockfish` allows 2048 at most. See [DeviceProfile.maxHashMb] for
  /// the smaller ceiling of 32-bit / low-memory devices.
  static const List<int> hashOptionsMb = [16, 32, 64, 128, 256];
  static const int maxHashMb = 256;

  /// The hash sizes this device is offered (and the stored value is clamped
  /// to): [hashOptionsMb] up to [maxMb].
  static List<int> hashOptionsFor(int maxMb) => [for (final mb in hashOptionsMb) if (mb <= maxMb) mb];

  /// The most threads this device is offered: `cores - 1` (the UI thread and
  /// the OS keep one core; lichess mobile caps at the same value), at least 1.
  /// The picker, the stored-value clamp and `setThreads` all use this one
  /// number.
  static int maxThreads(int cores) => math.max(1, cores - 1);

  /// Threads the picker offers: 1 up to [maxThreads].
  static List<int> threadOptions(int cores) => [for (var t = 1; t <= maxThreads(cores); t++) t];

  /// Reported in `analyses.engine`.
  static const String engineName = 'Stockfish 19 light';

  /// `min(4, cores - 2)`, at least 1.
  static int threadsFor(int cores) => math.max(1, math.min(4, cores - 2));

  static int get defaultThreads => threadsFor(Platform.numberOfProcessors);
}

/// What the device can take, for the engine's limits. Cheap: one platform
/// string and one small file (`/proc/meminfo`, readable by any app).
abstract final class DeviceProfile {
  /// Below this much RAM the 256 MB hash is not offered (the engine, the
  /// board, the database and Flutter share it; Android may kill the app).
  static const int lowMemoryKb = 3 * 1024 * 1024;

  /// The hash ceiling in MB: 128 on a 32-bit ABI or with less than 3 GB RAM
  /// (or when the memory size cannot be read: the safe side), else 256.
  static int maxHashMb({required bool is32Bit, required int? totalMemKb}) {
    if (is32Bit) return 128;
    if (totalMemKb == null || totalMemKb < lowMemoryKb) return 128;
    return EngineDefaults.maxHashMb;
  }

  /// `MemTotal` of a `/proc/meminfo` text, in kB.
  static int? parseMemTotalKb(String meminfo) {
    final m = RegExp(r'^MemTotal:\s+(\d+)\s*kB', multiLine: true).firstMatch(meminfo);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  /// Dart's version string ends with the target, e.g. `on "android_arm64"`.
  static bool is32BitAbi(String dartVersion) => RegExp(r'"(android_arm|android_ia32|linux_arm|linux_ia32)"').hasMatch(dartVersion);

  static int currentMaxHashMb() {
    int? kb;
    try {
      kb = parseMemTotalKb(File('/proc/meminfo').readAsStringSync());
    } on Object {
      kb = null; // not Linux / unreadable
    }
    return maxHashMb(is32Bit: is32BitAbi(Platform.version), totalMemKb: kb);
  }
}

/// Logical cores of this device (tests override).
final coreCountProvider = Provider<int>((ref) => Platform.numberOfProcessors);

/// The hash ceiling of this device (tests override).
final maxHashMbProvider = Provider<int>((ref) => DeviceProfile.currentMaxHashMb());

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
  static Future<EngineSettings> load(SettingsRepository settings, {int? cores, int? maxHashMb}) async {
    final presetName = await settings.get(SettingsKeys.engineDepthPreset);
    final threads = int.tryParse(await settings.get(SettingsKeys.engineThreads) ?? '');
    final hash = int.tryParse(await settings.get(SettingsKeys.engineHashMb) ?? '');
    final coreCount = cores ?? Platform.numberOfProcessors;
    final hashCap = maxHashMb ?? EngineDefaults.maxHashMb;
    return EngineSettings(
      preset: DepthPreset.values.where((p) => p.name == presetName).firstOrNull ?? EngineDefaults.preset,
      // A stored value from another device (or a hand-edited database) is
      // clamped to what this one can run.
      threads: threads != null && threads >= 1
          ? math.min(threads, EngineDefaults.maxThreads(coreCount))
          : EngineDefaults.threadsFor(coreCount),
      hashMb: hash != null && hash >= 1 ? math.min(hash, hashCap) : math.min(EngineDefaults.hashMb, hashCap),
    );
  }

  EngineSettings copyWith({DepthPreset? preset, int? threads, int? hashMb}) =>
      EngineSettings(preset: preset ?? this.preset, threads: threads ?? this.threads, hashMb: hashMb ?? this.hashMb);
}

/// The engine settings (Settings > Engine, SPEC F19). A change applies to the
/// next job; one that is running keeps the values it started with.
class EngineSettingsNotifier extends AsyncNotifier<EngineSettings> {
  @override
  Future<EngineSettings> build() => _load(ref.watch(settingsRepositoryProvider));

  Future<EngineSettings> _load(SettingsRepository repo) =>
      EngineSettings.load(repo, cores: ref.read(coreCountProvider), maxHashMb: ref.read(maxHashMbProvider));

  Future<void> setPreset(DepthPreset preset) async {
    final current = await future;
    await ref.read(settingsRepositoryProvider).set(SettingsKeys.engineDepthPreset, preset.name);
    state = AsyncData(current.copyWith(preset: preset));
  }

  Future<void> setThreads(int threads) async {
    final current = await future;
    final t = math.min(math.max(1, threads), EngineDefaults.maxThreads(ref.read(coreCountProvider)));
    await ref.read(settingsRepositoryProvider).set(SettingsKeys.engineThreads, '$t');
    state = AsyncData(current.copyWith(threads: t));
  }

  Future<void> setHashMb(int mb) async {
    final current = await future;
    final h = math.min(math.max(1, mb), ref.read(maxHashMbProvider));
    await ref.read(settingsRepositoryProvider).set(SettingsKeys.engineHashMb, '$h');
    state = AsyncData(current.copyWith(hashMb: h));
  }

  /// Forgets the stored choices: preset Normal, threads `min(4, cores - 2)`, 64 MB.
  Future<void> resetToDefaults() async {
    final repo = ref.read(settingsRepositoryProvider);
    await repo.remove(SettingsKeys.engineDepthPreset);
    await repo.remove(SettingsKeys.engineThreads);
    await repo.remove(SettingsKeys.engineHashMb);
    state = AsyncData(await _load(repo));
  }
}

final engineSettingsProvider = AsyncNotifierProvider<EngineSettingsNotifier, EngineSettings>(EngineSettingsNotifier.new);
