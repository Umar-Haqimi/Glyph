import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../engine/engine_providers.dart';
import '../../l10n/app_localizations.dart';

/// Progress of the analysis of one game with Cancel / Resume / Retry
/// (SPEC section 4, board screen). Shows the live job when it belongs to
/// [game], else the stored summary of the game.
class AnalysisProgress extends ConsumerWidget {
  const AnalysisProgress({super.key, required this.game});

  final GameRecord game;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final job = ref.watch(analysisJobProvider);
    final queued = ref.watch(analysisQueueProvider).contains(game.id);
    final notifier = ref.read(analysisJobProvider.notifier);
    final live = job.gameId == game.id ? job : null;
    final total = game.plyCount + 1;

    Widget row(String text, {double? progress, String? actionLabel, VoidCallback? onAction, bool busy = false}) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (busy) LinearProgressIndicator(value: progress),
            Row(
              children: [
                Expanded(child: Text(text, key: const Key('analysis-status'))),
                if (actionLabel != null) TextButton(onPressed: onAction, child: Text(actionLabel)),
              ],
            ),
          ],
        ),
      );
    }

    void start() => notifier.analyse(game);

    switch (live) {
      case AnalysisStarting():
        return row(l10n.analysisStarting, busy: true, actionLabel: l10n.analysisCancel, onAction: () => notifier.cancel(game.id));
      case AnalysisRunning(:final completed, total: final n):
        return row(
          l10n.analysisRunning(completed, n),
          busy: true,
          progress: n == 0 ? null : completed / n,
          actionLabel: l10n.analysisCancel,
          onAction: () => notifier.cancel(game.id),
        );
      case AnalysisCompleted():
        return row(l10n.analysisCompleted);
      case AnalysisCancelled(:final completed, total: final n):
        return row(l10n.analysisCancelled(completed, n), actionLabel: l10n.analysisResume, onAction: start);
      case AnalysisPaused(:final completed, total: final n):
        return row(l10n.analysisPaused(completed, n), actionLabel: l10n.analysisResume, onAction: start);
      case AnalysisFailed(kind: AnalysisFailureKind.invalidGame):
        // Retrying cannot help: the game itself is unreadable.
        return row(l10n.analysisFailedInvalid);
      case AnalysisFailed(:final kind):
        return row(
          kind == AnalysisFailureKind.engineUnavailable ? l10n.analysisFailedUnavailable : l10n.analysisFailedCrashed,
          actionLabel: l10n.analysisRetry,
          onAction: start,
        );
      case AnalysisIdle():
      case null:
        break;
    }

    // No live job for this game: queued, or what the database says.
    if (queued) {
      return row(l10n.analysisQueued, busy: true, actionLabel: l10n.analysisCancel, onAction: () => notifier.cancel(game.id));
    }
    final stored = game.analysisStatus;
    if (stored == null) {
      if (notifier.wasCancelledWhileQueued(game.id)) {
        return row(l10n.analysisCancelled(0, total), actionLabel: l10n.analysisResume, onAction: start);
      }
      // Never analysed: the board is about to start it.
      return row(l10n.analysisStarting, busy: true);
    }
    return switch (stored) {
      AnalysisStatus.completed => row(l10n.analysisCompleted),
      _ => row(
          l10n.analysisIncomplete(game.completedPlies, total),
          actionLabel: l10n.analysisResume,
          onAction: start,
        ),
    };
  }
}
