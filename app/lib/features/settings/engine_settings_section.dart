import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/choice_option.dart';
import '../../widgets/section_header.dart';
import 'engine_settings.dart';

String presetLabel(AppLocalizations l10n, DepthPreset preset) => switch (preset) {
      DepthPreset.fast => l10n.enginePresetFast(preset.depth),
      DepthPreset.normal => l10n.enginePresetNormal(preset.depth),
      DepthPreset.deep => l10n.enginePresetDeep(preset.depth),
    };

/// Settings > Engine (SPEC F19): analysis depth preset, threads, hash. The
/// defaults are chosen per device (`EngineDefaults`, docs/DECISIONS.md M8).
class EngineSettingsSection extends ConsumerWidget {
  const EngineSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(engineSettingsProvider).value;
    final notifier = ref.read(engineSettingsProvider.notifier);
    final coreCount = ref.watch(coreCountProvider);
    final hashOptions = EngineDefaults.hashOptionsFor(ref.watch(maxHashMbProvider));
    final defaultThreads = EngineDefaults.threadsFor(coreCount);
    final threadOptions = EngineDefaults.threadOptions(coreCount);

    String threadsText(int n) =>
        n == defaultThreads ? l10n.settingsEngineThreadsDefault(n) : l10n.settingsEngineThreadsValue(n);
    String hashText(int mb) => mb == EngineDefaults.hashMb ? l10n.settingsEngineHashDefault(mb) : l10n.settingsEngineHashValue(mb);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.settingsEngine, padding: const EdgeInsets.fromLTRB(16, 16, 16, 4)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(l10n.settingsEngineHelp, style: Theme.of(context).textTheme.bodySmall),
        ),
        ListTile(
          key: const Key('settings-engine-preset'),
          title: Text(l10n.settingsEnginePreset),
          subtitle: settings == null ? null : Text(presetLabel(l10n, settings.preset)),
          trailing: const Icon(Icons.chevron_right),
          onTap: settings == null
              ? null
              : () async {
                  final choice = await showChoiceDialog<DepthPreset>(
                    context,
                    title: l10n.settingsEnginePreset,
                    options: [for (final p in DepthPreset.values) (p, presetLabel(l10n, p))],
                    selected: settings.preset,
                    keyPrefix: 'engine-preset',
                  );
                  if (choice != null) await notifier.setPreset(choice);
                },
        ),
        ListTile(
          key: const Key('settings-engine-threads'),
          title: Text(l10n.settingsEngineThreads),
          subtitle: settings == null ? null : Text(threadsText(settings.threads)),
          trailing: const Icon(Icons.chevron_right),
          onTap: settings == null
              ? null
              : () async {
                  final choice = await showChoiceDialog<int>(
                    context,
                    title: l10n.settingsEngineThreads,
                    options: [for (final t in threadOptions) (t, threadsText(t))],
                    selected: settings.threads,
                    keyPrefix: 'engine-threads',
                  );
                  if (choice != null) await notifier.setThreads(choice);
                },
        ),
        ListTile(
          key: const Key('settings-engine-hash'),
          title: Text(l10n.settingsEngineHash),
          subtitle: settings == null ? null : Text(hashText(settings.hashMb)),
          trailing: const Icon(Icons.chevron_right),
          onTap: settings == null
              ? null
              : () async {
                  final choice = await showChoiceDialog<int>(
                    context,
                    title: l10n.settingsEngineHash,
                    options: [
                      for (final mb in {...hashOptions, settings.hashMb}.toList()..sort()) (mb, hashText(mb)),
                    ],
                    selected: settings.hashMb,
                    keyPrefix: 'engine-hash',
                  );
                  if (choice != null) await notifier.setHashMb(choice);
                },
        ),
        ListTile(
          key: const Key('settings-engine-reset'),
          title: Text(l10n.settingsEngineReset),
          subtitle: Text(l10n.settingsEngineResetSubtitle),
          trailing: const Icon(Icons.restart_alt),
          onTap: notifier.resetToDefaults,
        ),
      ],
    );
  }
}
