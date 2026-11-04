import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/in_memory.dart';
import 'package:glyph/data/repositories.dart';
import 'package:glyph/features/settings/engine_settings.dart';

void main() {
  test('depth presets: Fast 12 / Normal 16 / Deep 20, Normal by default', () {
    expect(DepthPreset.values.map((p) => (p.name, p.depth)), [('fast', 12), ('normal', 16), ('deep', 20)]);
    expect(EngineDefaults.preset, DepthPreset.normal);
    expect(EngineDefaults.hashMb, 64);
    expect(EngineDefaults.multiPv, 2);
  });

  test('threads default to min(4, cores - 2), at least 1', () {
    expect([for (final c in [1, 2, 3, 4, 6, 8, 12, 64]) EngineDefaults.threadsFor(c)], [1, 1, 1, 2, 4, 4, 4, 4]);
  });

  test('settings load: defaults, stored values, garbage ignored', () async {
    var s = await EngineSettings.load(InMemorySettingsRepository(), cores: 8);
    expect((s.preset, s.depth, s.threads, s.hashMb), (DepthPreset.normal, 16, 4, 64));

    s = await EngineSettings.load(
      InMemorySettingsRepository({
        SettingsKeys.engineDepthPreset: 'deep',
        SettingsKeys.engineThreads: '2',
        SettingsKeys.engineHashMb: '128',
      }),
      cores: 8,
    );
    expect((s.depth, s.threads, s.hashMb), (20, 2, 128));

    s = await EngineSettings.load(
      InMemorySettingsRepository({
        SettingsKeys.engineDepthPreset: 'bogus',
        SettingsKeys.engineThreads: '0',
        SettingsKeys.engineHashMb: 'x',
      }),
      cores: 3,
    );
    expect((s.depth, s.threads, s.hashMb), (16, 1, 64));
  });
}
