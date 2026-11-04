import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/placeholder_body.dart';

/// Opens the Explain sheet (SPEC section 4, screen 5). Placeholder in M1.
Future<void> showExplainSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const ExplainSheet(),
  );
}

class ExplainSheet extends StatelessWidget {
  const ExplainSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(l10n.explainTitle, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 120, child: PlaceholderBody()),
        ],
      ),
    );
  }
}
