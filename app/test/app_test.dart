import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/explain/explain_sheet.dart';
import 'package:glyph/routes.dart';
import 'package:material_ui/material_ui.dart';

import 'support/test_app.dart';

final _l10n = l10n;

Future<void> _pump(WidgetTester tester) => TestEnv().pump(tester);

void main() {
  testWidgets('library shows empty state and import FAB', (tester) async {
    await _pump(tester);
    expect(find.text(_l10n.libraryEmptyTitle), findsOneWidget);
    expect(find.text(_l10n.libraryEmptyAction), findsOneWidget);
    expect(find.text(_l10n.libraryImportFab), findsOneWidget);
  });

  testWidgets('import FAB opens the sheet with the four sources', (tester) async {
    await _pump(tester);
    await tester.tap(find.text(_l10n.libraryImportFab));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.importPastePgn), findsOneWidget);
    expect(find.text(_l10n.importOpenFile), findsOneWidget);
    expect(find.text(_l10n.importFromLichess), findsOneWidget);
    expect(find.text(_l10n.importFromChessCom), findsOneWidget);
  });

  testWidgets('board -> report and explain placeholders', (tester) async {
    await _pump(tester);
    tester.state<NavigatorState>(find.byType(Navigator)).pushNamed(Routes.board);
    await tester.pumpAndSettle();
    expect(find.text(_l10n.boardTitle), findsOneWidget);
    expect(find.text(_l10n.placeholderComingSoon), findsOneWidget);

    await tester.tap(find.text(_l10n.boardExplain));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(ExplainSheet),
        matching: find.text(_l10n.explainTitle),
      ),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet via the barrier
    await tester.pumpAndSettle();

    await tester.tap(find.text(_l10n.boardReport));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.reportTitle), findsOneWidget);
  });

  testWidgets('settings -> about, and the theme mode setting works', (tester) async {
    await _pump(tester);
    await tester.tap(find.byTooltip(_l10n.settingsTooltip));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.settingsAppearance), findsOneWidget);

    await tester.tap(find.text(_l10n.settingsThemeDark));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);

    await tester.tap(find.text(_l10n.settingsAbout));
    await tester.pumpAndSettle();
    expect(find.text(_l10n.aboutLicenseNotice), findsOneWidget);
  });
}
