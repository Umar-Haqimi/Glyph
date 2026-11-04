import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../explain/explain_sheet.dart' show PromptDialog;
import '../explain/generation.dart';
import '../explain/generation_view.dart';
import '../explain/summary_controller.dart';
import '../settings/explain_settings.dart';

/// The game summary block of the report (SPEC F12): hidden entirely when the
/// summary setting is off; otherwise the saved or streaming summary, or a
/// "Summarize game" button when nothing was generated (automatic summaries
/// off, no model yet, or the analysis was finished before this was set up).
class SummaryCard extends ConsumerStatefulWidget {
  const SummaryCard({super.key, required this.gameId, required this.analysisComplete});

  final int gameId;
  final bool analysisComplete;

  @override
  ConsumerState<SummaryCard> createState() => _SummaryCardState();
}

class _SummaryCardState extends ConsumerState<SummaryCard> {
  @override
  void initState() {
    super.initState();
    _showSaved();
  }

  @override
  void didUpdateWidget(SummaryCard old) {
    super.didUpdateWidget(old);
    if (!old.analysisComplete && widget.analysisComplete) _showSaved();
  }

  /// A summary saved earlier shows without a request.
  void _showSaved() {
    if (!widget.analysisComplete) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(summaryProvider(widget.gameId).notifier).loadCached();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final settings = ref.watch(explainSettingsProvider).value;
    if (settings == null || !settings.summaryEnabled) return const SizedBox.shrink();
    final state = ref.watch(summaryProvider(widget.gameId));
    final notifier = ref.read(summaryProvider(widget.gameId).notifier);

    Widget body;
    if (!widget.analysisComplete) {
      body = Text(l10n.summaryWaiting, key: const Key('summary-waiting'), style: theme.textTheme.bodyMedium);
    } else if (state.phase == GenerationPhase.idle) {
      body = Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.tonalIcon(
          key: const Key('summary-button'),
          onPressed: notifier.generate,
          icon: const Icon(Icons.auto_awesome),
          label: Text(l10n.summaryButton),
        ),
      );
    } else {
      body = GenerationView(
        keyPrefix: 'summary',
        state: state,
        disclaimer: l10n.summaryDisclaimer,
        onStop: notifier.cancel,
        onRegenerate: notifier.regenerate,
        onRetry: notifier.generate,
        onOpenSettings: () => Navigator.of(context).pushNamed(Routes.llmSettings),
        onViewPrompt: () {
          final request = state.request;
          if (request != null) showDialog<void>(context: context, builder: (_) => PromptDialog(request: request));
        },
      );
    }
    return Card(
      key: const Key('summary-card'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(header: true, child: Text(l10n.summaryTitle, style: theme.textTheme.titleMedium)),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }
}
