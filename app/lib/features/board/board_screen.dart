import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/providers.dart';
import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../../widgets/placeholder_body.dart';
import '../explain/explain_sheet.dart';

/// Analysis board. Placeholder until M5; it already knows which game it shows.
class BoardScreen extends ConsumerWidget {
  const BoardScreen({super.key, this.gameId});

  final int? gameId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final id = gameId;
    final game = id == null ? null : ref.watch(gameProvider(id)).value;
    final title = game == null
        ? l10n.boardTitle
        : l10n.boardTitleGame(
            game.white ?? l10n.libraryUnknownPlayer,
            game.black ?? l10n.libraryUnknownPlayer,
          );
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: const PlaceholderBody(),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed(Routes.report),
                child: Text(l10n.boardReport),
              ),
              FilledButton.tonal(
                onPressed: () => showExplainSheet(context),
                child: Text(l10n.boardExplain),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
