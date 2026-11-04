import 'package:material_ui/material_ui.dart';

import 'features/about/about_screen.dart';
import 'features/board/board_screen.dart';
import 'features/library/library_screen.dart';
import 'features/report/report_screen.dart';
import 'features/settings/settings_screen.dart';

/// Named routes. Plain Navigator, no routing package.
///
/// The import sheet and the Explain sheet are modal bottom sheets, opened with
/// `showImportSheet` and `showExplainSheet`, so they have no route here.
abstract final class Routes {
  static const String library = '/';
  static const String board = '/board';
  static const String report = '/report';
  static const String settings = '/settings';
  static const String about = '/about';

  static Route<void> onGenerateRoute(RouteSettings settings) {
    final WidgetBuilder builder = switch (settings.name) {
      library => (_) => const LibraryScreen(),
      board => (_) => const BoardScreen(),
      report => (_) => const ReportScreen(),
      Routes.settings => (_) => const SettingsScreen(),
      about => (_) => const AboutScreen(),
      _ => (_) => const LibraryScreen(),
    };
    return MaterialPageRoute<void>(builder: builder, settings: settings);
  }
}
