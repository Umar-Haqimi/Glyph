import 'package:flutter/services.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import 'error_text.dart';
import 'generation.dart';
import 'streaming_text.dart';

/// Everything under the header of the Explain sheet and of the game summary
/// card: the status line, the streamed text, the error with its actions, the
/// action row (Stop / Copy / Regenerate / View prompt) and the footer.
///
/// All keys are prefixed with [keyPrefix] (`explain` or `summary`).
class GenerationView extends StatelessWidget {
  const GenerationView({
    super.key,
    required this.keyPrefix,
    required this.state,
    required this.disclaimer,
    required this.onStop,
    required this.onRegenerate,
    required this.onRetry,
    required this.onOpenSettings,
    this.onViewPrompt,
    this.announceSavedText = false,
  });

  final String keyPrefix;
  final GenerationState state;

  /// Builds the footer from the model name.
  final String Function(String model) disclaimer;
  final VoidCallback onStop;
  final VoidCallback onRegenerate;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;
  final VoidCallback? onViewPrompt;
  final bool announceSavedText;

  Key _key(String name) => Key('$keyPrefix-$name');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final model = state.request?.config.model ?? '';

    if (state.phase == GenerationPhase.notConfigured) {
      return _SetupCard(keyPrefix: keyPrefix, problem: state.missing!, onOpenSettings: onOpenSettings);
    }

    final String status;
    switch (state.phase) {
      case GenerationPhase.connecting:
        status = l10n.explainStatusConnecting;
      case GenerationPhase.streaming:
        status = l10n.explainStatusStreaming;
      case GenerationPhase.done:
        status = l10n.explainStatusDone;
      case GenerationPhase.cancelled:
        status = l10n.explainStatusCancelled;
      case GenerationPhase.failed:
        status = llmErrorText(l10n, state.error!, model: model);
      case GenerationPhase.idle:
      case GenerationPhase.notConfigured:
        status = '';
    }
    final failed = state.phase == GenerationPhase.failed;
    final hasText = state.text.isNotEmpty;
    final streaming = state.phase == GenerationPhase.streaming || state.phase == GenerationPhase.connecting;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // The status line is a live region: "Asking the model...", then the
        // finished / stopped / error message are announced once each.
        Semantics(
          liveRegion: true,
          container: true,
          label: status,
          excludeSemantics: true,
          child: Row(
            key: _key('status'),
            children: [
              if (state.busy)
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              else
                Icon(
                  failed ? Icons.error_outline : Icons.check_circle_outline,
                  size: 18,
                  color: failed ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  key: _key('status-text'),
                  style: theme.textTheme.bodyMedium?.copyWith(color: failed ? theme.colorScheme.error : null),
                ),
              ),
            ],
          ),
        ),
        if (failed && state.error!.detail != null && state.error!.kind != LlmErrorKind.notAnalysed) ...[
          const SizedBox(height: 4),
          Text(
            l10n.explainProviderMessage(state.error!.detail!),
            key: _key('error-detail'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
        if (hasText) ...[
          const SizedBox(height: 12),
          StreamingText(
            key: _key('text'),
            text: state.text,
            streaming: streaming,
            style: theme.textTheme.bodyLarge,
            announceOnShow: announceSavedText,
          ),
        ],
        if (state.cutOff) ...[
          const SizedBox(height: 8),
          Text(l10n.explainCutOff, key: _key('cut-off'), style: theme.textTheme.bodySmall),
        ],
        if (state.filtered) ...[
          const SizedBox(height: 8),
          Text(l10n.explainFiltered, key: _key('filtered'), style: theme.textTheme.bodySmall),
        ],
        if (state.fromCache && state.phase == GenerationPhase.done) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              key: _key('saved'),
              avatar: const Icon(Icons.bookmark_outline, size: 16),
              label: Text(l10n.explainSaved),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (state.busy)
              OutlinedButton.icon(
                key: _key('stop'),
                onPressed: onStop,
                icon: const Icon(Icons.stop_circle_outlined),
                label: Text(l10n.explainStop),
              ),
            if (failed) ...[
              FilledButton.icon(
                key: _key('retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(l10n.explainRetry),
              ),
              if (llmErrorFixableInSettings(state.error!.kind))
                OutlinedButton(
                  key: _key('open-settings'),
                  onPressed: onOpenSettings,
                  child: Text(l10n.explainOpenSettings),
                ),
            ],
            if (hasText && !state.busy)
              OutlinedButton.icon(
                key: _key('copy'),
                onPressed: () => _copy(context, state.text),
                icon: const Icon(Icons.copy_outlined),
                label: Text(l10n.explainCopy),
              ),
            if (!state.busy && !failed && (state.phase == GenerationPhase.done || state.phase == GenerationPhase.cancelled))
              FilledButton.tonalIcon(
                key: _key('regenerate'),
                onPressed: onRegenerate,
                icon: const Icon(Icons.auto_awesome),
                label: Text(l10n.explainRegenerate),
              ),
            if (onViewPrompt != null && state.request != null)
              PopupMenuButton<String>(
                key: _key('menu'),
                tooltip: l10n.explainMenu,
                onSelected: (_) => onViewPrompt!(),
                itemBuilder: (_) => [
                  PopupMenuItem<String>(
                    key: _key('view-prompt'),
                    value: 'prompt',
                    child: Text(l10n.explainViewPrompt),
                  ),
                ],
              ),
          ],
        ),
        if (hasText || state.phase == GenerationPhase.done) ...[
          const SizedBox(height: 8),
          Text(
            disclaimer(model),
            key: _key('disclaimer'),
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Future<void> _copy(BuildContext context, String text) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.maybeOf(context);
    await Clipboard.setData(ClipboardData(text: text));
    messenger?.showSnackBar(SnackBar(content: Text(l10n.explainCopied)));
  }
}

/// "Set up explanations" (SPEC 4, screen 7): shown instead of the answer when
/// no model is configured.
class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.keyPrefix, required this.problem, required this.onOpenSettings});

  final String keyPrefix;
  final LlmErrorKind problem;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Column(
      key: Key('$keyPrefix-setup'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          container: true,
          child: Text(l10n.explainSetupTitle, style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: 8),
        Text(l10n.explainSetupBody, style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        Text(
          llmErrorText(l10n, LlmError(problem)),
          key: Key('$keyPrefix-setup-reason'),
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        FilledButton(
          key: Key('$keyPrefix-setup-action'),
          onPressed: onOpenSettings,
          child: Text(l10n.explainSetupAction),
        ),
      ],
    );
  }
}
