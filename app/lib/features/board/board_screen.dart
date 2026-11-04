import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../../widgets/placeholder_body.dart';
import '../explain/explain_sheet.dart';

/// Analysis board. Placeholder in M1 (the real board arrives in M5).
class BoardScreen extends StatelessWidget {
  const BoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.boardTitle)),
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
