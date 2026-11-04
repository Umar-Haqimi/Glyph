import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../board/board_data.dart';
import '../board/board_format.dart';
import '../board/move_badge.dart';
import '../board/spoken_move.dart';
import 'explain_controller.dart';
import 'generation.dart';
import 'generation_view.dart';

/// Opens the Explain sheet for move [ply] (1-based) of game [gameId]
/// (SPEC F11, screen 5). The request starts at once and is cancelled when the
/// sheet closes.
Future<void> showExplainSheet(BuildContext context, {required int gameId, required int ply}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
    builder: (_) => ExplainSheet(gameId: gameId, ply: ply),
  );
}

class ExplainSheet extends ConsumerWidget {
  const ExplainSheet({super.key, required this.gameId, required this.ply});

  final int gameId;
  final int ply;

  ExplainArgs get _args => ExplainArgs(gameId, ply);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(explainProvider(_args));
    final notifier = ref.read(explainProvider(_args).notifier);
    final data = ref.watch(boardDataProvider(gameId)).value;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data != null) _Header(data: data, ply: ply) else Text(l10n.explainTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Flexible(
            child: SingleChildScrollView(
              child: GenerationView(
                keyPrefix: 'explain',
                state: state,
                announceSavedText: true,
                disclaimer: l10n.explainDisclaimer,
                onStop: notifier.cancel,
                onRegenerate: notifier.regenerate,
                onRetry: notifier.retry,
                onOpenSettings: () => _openSettings(context),
                onViewPrompt: () => _viewPrompt(context, state),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openSettings(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.pushNamed(Routes.llmSettings);
  }

  void _viewPrompt(BuildContext context, GenerationState state) {
    final request = state.request;
    if (request == null) return;
    showDialog<void>(context: context, builder: (_) => PromptDialog(request: request));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.data, required this.ply});

  final BoardData data;
  final int ply;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final played = data.plyAt(ply);
    if (played == null) return Text(l10n.explainTitle, style: theme.textTheme.titleLarge);
    final before = data.positionBefore(ply);
    final mover = before.turn;
    final label = data.moveAt(ply)?.label;
    final isUser = data.userSide == mover;
    final nth = l10n.explainOrdinal(before.fullmoves, _suffix(before.fullmoves));
    final subtitle = isUser
        ? l10n.explainHeaderYou(nth)
        : l10n.explainHeaderSide(mover == Side.white ? l10n.sideWhite : l10n.sideBlack, nth);
    final title = formatMove(before, played.san);
    final spoken = spokenMove(l10n, before, played.san);
    return Semantics(
      container: true,
      header: true,
      label: l10n.coachCardTitle(spoken, label == null ? subtitle : labelName(l10n, label)),
      excludeSemantics: true,
      child: Row(
        children: [
          if (label != null) ...[MoveBadge(label: label, size: 36, excludeSemantics: true), const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, key: const Key('explain-title'), style: theme.textTheme.titleLarge),
                Text(subtitle, key: const Key('explain-subtitle'), style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// English ordinal suffix key for the ARB select (st, nd, rd, other).
  static String _suffix(int n) {
    final mod100 = n % 100;
    if (mod100 >= 11 && mod100 <= 13) return 'other';
    return switch (n % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'other',
    };
  }
}

/// "View prompt" (SPEC F11): shows exactly what is sent. The API key is a
/// header, added by the client, so it cannot appear here.
class PromptDialog extends StatelessWidget {
  const PromptDialog({super.key, required this.request});

  final LlmRequest request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final mono = theme.textTheme.bodySmall?.copyWith(fontFamily: 'monospace');
    final json = request.toJson();
    final parameters = {for (final e in json.entries) if (e.key != 'messages') e.key: e.value};
    Widget section(String title, String body, Key key) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(padding: const EdgeInsets.only(top: 12, bottom: 4), child: Text(title, style: theme.textTheme.titleSmall)),
            SelectableText(body, key: key, style: mono),
          ],
        );
    final system = request.messages.where((m) => m.role == ChatRole.system).map((m) => m.content).join('\n');
    final user = request.messages.where((m) => m.role == ChatRole.user).map((m) => m.content).join('\n');
    return AlertDialog(
      key: const Key('prompt-dialog'),
      title: Text(l10n.explainPromptTitle),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.explainPromptNote, style: theme.textTheme.bodySmall),
              section(l10n.explainPromptRequest, _pretty(parameters), const Key('prompt-request')),
              section(l10n.explainPromptSystem, system, const Key('prompt-system')),
              section(l10n.explainPromptUser, user, const Key('prompt-user')),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          key: const Key('prompt-copy'),
          onPressed: () => Clipboard.setData(ClipboardData(text: request.prettyBody())),
          child: Text(l10n.explainPromptCopy),
        ),
        TextButton(
          key: const Key('prompt-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.explainClose),
        ),
      ],
    );
  }

  static String _pretty(Map<String, Object?> m) =>
      [for (final e in m.entries) '${e.key}: ${e.value}'].join('\n');
}
