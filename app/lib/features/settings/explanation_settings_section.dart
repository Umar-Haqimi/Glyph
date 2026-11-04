import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import 'explain_settings.dart';
import 'llm_settings_screen.dart';

/// Settings > Explanations (SPEC section 4 screen 6): LLM connection,
/// language, tone, audience level, game summary on / off, automatic summary.
class ExplanationSettingsSection extends ConsumerWidget {
  const ExplanationSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(explainSettingsProvider).value;
    final notifier = ref.read(explainSettingsProvider.notifier);
    final s = settings ?? const ExplainSettings();
    final connection = settings != null && s.model.trim().isNotEmpty
        ? l10n.settingsLlmSummary(providerName(l10n, s.provider), s.model.trim())
        : l10n.settingsLlmNotSet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(l10n.settingsExplanations, style: theme.textTheme.titleSmall),
        ),
        ListTile(
          key: const Key('settings-llm'),
          title: Text(l10n.settingsLlmConnection),
          subtitle: Text(connection),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).pushNamed(Routes.llmSettings),
        ),
        ListTile(
          key: const Key('settings-language'),
          title: Text(l10n.settingsExplainLanguage),
          subtitle: Text(s.language.isEmpty ? l10n.settingsLanguageMatchApp : s.language),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _editLanguage(context, s.language, notifier),
        ),
        ListTile(title: Text(l10n.settingsTone)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ExplainTone>(
            key: const Key('settings-tone'),
            segments: [
              ButtonSegment(value: ExplainTone.casual, label: Text(l10n.toneCasual)),
              ButtonSegment(value: ExplainTone.coach, label: Text(l10n.toneCoach)),
            ],
            selected: {s.tone},
            onSelectionChanged: (v) => notifier.setTone(v.first),
          ),
        ),
        ListTile(title: Text(l10n.settingsAudience)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<ExplainAudience>(
            key: const Key('settings-audience'),
            segments: [
              ButtonSegment(value: ExplainAudience.beginner, label: Text(l10n.audienceBeginner)),
              ButtonSegment(value: ExplainAudience.club, label: Text(l10n.audienceClub)),
              ButtonSegment(value: ExplainAudience.advanced, label: Text(l10n.audienceAdvanced)),
            ],
            selected: {s.audience},
            onSelectionChanged: (v) => notifier.setAudience(v.first),
          ),
        ),
        SwitchListTile(
          key: const Key('settings-summary'),
          title: Text(l10n.settingsSummary),
          subtitle: Text(l10n.settingsSummarySubtitle),
          value: s.summaryEnabled,
          onChanged: notifier.setSummaryEnabled,
        ),
        SwitchListTile(
          key: const Key('settings-summary-auto'),
          title: Text(l10n.settingsSummaryAuto),
          subtitle: Text(l10n.settingsSummaryAutoSubtitle),
          value: s.summaryAuto,
          onChanged: s.summaryEnabled ? notifier.setSummaryAuto : null,
        ),
      ],
    );
  }

  Future<void> _editLanguage(BuildContext context, String current, ExplainSettingsNotifier notifier) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _LanguageDialog(initial: current),
    );
    if (result != null) await notifier.setLanguage(result);
  }
}

/// The language override dialog. It owns its text controller: disposing it
/// right after `showDialog` returns would break the dialog's closing
/// animation.
class _LanguageDialog extends StatefulWidget {
  const _LanguageDialog({required this.initial});

  final String initial;

  @override
  State<_LanguageDialog> createState() => _LanguageDialogState();
}

class _LanguageDialogState extends State<_LanguageDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AlertDialog(
      title: Text(l10n.settingsLanguageDialogTitle),
      content: TextField(
        key: const Key('settings-language-field'),
        controller: _controller,
        autofocus: true,
        decoration: InputDecoration(labelText: l10n.settingsLanguageOther, hintText: l10n.settingsLanguageHint),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          key: const Key('settings-language-app'),
          onPressed: () => Navigator.of(context).pop(''),
          child: Text(l10n.settingsLanguageMatchApp),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.settingsLanguageCancel)),
        FilledButton(
          key: const Key('settings-language-save'),
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(l10n.settingsLanguageSave),
        ),
      ],
    );
  }
}
