import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../../widgets/adaptive_segments.dart';
import '../../widgets/section_header.dart';
import 'explain_settings.dart';
import 'llm_settings_screen.dart';

/// Settings > Explanations (SPEC section 4 screen 6): LLM connection,
/// language, tone, audience level, game summary on / off, automatic summary.
class ExplanationSettingsSection extends ConsumerWidget {
  const ExplanationSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final settings = ref.watch(explainSettingsProvider).value;
    final notifier = ref.read(explainSettingsProvider.notifier);
    final s = settings ?? const ExplainSettings();
    final connection = settings != null && s.model.trim().isNotEmpty
        ? l10n.settingsLlmSummary(providerName(l10n, s.provider), s.model.trim())
        : l10n.settingsLlmNotSet;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.settingsExplanations),
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
          child: AdaptiveSegments<ExplainTone>(
            controlKey: const Key('settings-tone'),
            options: [
              (ExplainTone.casual, l10n.toneCasual),
              (ExplainTone.coach, l10n.toneCoach),
            ],
            selected: s.tone,
            onChanged: notifier.setTone,
          ),
        ),
        ListTile(title: Text(l10n.settingsAudience)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: AdaptiveSegments<ExplainAudience>(
            controlKey: const Key('settings-audience'),
            options: [
              (ExplainAudience.beginner, l10n.audienceBeginner),
              (ExplainAudience.club, l10n.audienceClub),
              (ExplainAudience.advanced, l10n.audienceAdvanced),
            ],
            selected: s.audience,
            onChanged: notifier.setAudience,
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
