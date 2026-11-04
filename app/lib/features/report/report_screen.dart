import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../widgets/placeholder_body.dart';

/// Report card. Placeholder in M1.
class ReportScreen extends StatelessWidget {
  const ReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.reportTitle)),
      body: const PlaceholderBody(),
    );
  }
}
