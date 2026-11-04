import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../errors/failure_text.dart';
import '../errors/recovery.dart';
import '../../platform/app_log.dart';
import '../../widgets/section_header.dart';
import 'data_management.dart';

/// Settings > Data (SPEC F19 "data management"): clear saved explanations,
/// clear the online cache, delete all data (after a confirmation). A failure
/// says so and offers Try again.
class DataSettingsSection extends ConsumerWidget {
  const DataSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.settingsData, padding: const EdgeInsets.fromLTRB(16, 16, 16, 4)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(l10n.settingsDataHelp, style: Theme.of(context).textTheme.bodySmall),
        ),
        ListTile(
          key: const Key('settings-clear-explanations'),
          title: Text(l10n.settingsClearExplanations),
          subtitle: Text(l10n.settingsClearExplanationsSubtitle),
          leading: const Icon(Icons.auto_delete_outlined),
          onTap: () => _clearExplanations(context, ref),
        ),
        ListTile(
          key: const Key('settings-clear-online'),
          title: Text(l10n.settingsClearOnline),
          subtitle: Text(l10n.settingsClearOnlineSubtitle),
          leading: const Icon(Icons.cloud_off_outlined),
          onTap: () => _clearOnline(context, ref),
        ),
        ListTile(
          key: const Key('settings-delete-all'),
          title: Text(l10n.settingsDeleteAll),
          subtitle: Text(l10n.settingsDeleteAllSubtitle),
          leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
          onTap: () => _deleteAll(context, ref),
        ),
      ],
    );
  }

  void _failed(BuildContext context, VoidCallback retry) {
    final l10n = AppLocalizations.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(appFailureText(l10n, AppFailure.dataManagement)),
        action: SnackBarAction(label: l10n.commonRetry, onPressed: retry),
      ));
  }

  void _say(BuildContext context, String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  Future<void> _clearExplanations(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      final n = await ref.read(dataManagementProvider).clearExplanations();
      if (context.mounted) _say(context, l10n.settingsClearExplanationsDone(n));
    } on Object catch (e) {
      AppLog.warning('Clearing the saved explanations failed', e);
      if (context.mounted) _failed(context, () => _clearExplanations(context, ref));
    }
  }

  Future<void> _clearOnline(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(dataManagementProvider).clearOnlineCache();
      if (context.mounted) _say(context, l10n.settingsClearOnlineDone);
    } on Object catch (e) {
      AppLog.warning('Clearing the online cache failed', e);
      if (context.mounted) _failed(context, () => _clearOnline(context, ref));
    }
  }

  Future<void> _deleteAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.settingsDeleteAllTitle),
        content: Text(l10n.settingsDeleteAllBody),
        actions: [
          TextButton(
            key: const Key('delete-all-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('delete-all-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.settingsDeleteAllConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(dataManagementProvider).deleteAll();
      if (context.mounted) _say(context, l10n.settingsDeleteAllDone);
    } on Object catch (e) {
      AppLog.warning('Deleting all data failed', e);
      if (context.mounted) _failed(context, () => _runDeleteAll(context, ref));
    }
  }

  /// Retry after a failure: the user already confirmed.
  Future<void> _runDeleteAll(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context);
    try {
      await ref.read(dataManagementProvider).deleteAll();
      if (context.mounted) _say(context, l10n.settingsDeleteAllDone);
    } on Object catch (e) {
      AppLog.warning('Deleting all data failed', e);
      if (context.mounted) _failed(context, () => _runDeleteAll(context, ref));
    }
  }
}
