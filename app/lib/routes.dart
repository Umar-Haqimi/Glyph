import 'package:material_ui/material_ui.dart';

import 'features/about/about_screen.dart';
import 'features/board/board_screen.dart';
import 'features/library/library_screen.dart';
import 'features/report/report_screen.dart';
import 'features/settings/llm_settings_screen.dart';
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
  static const String llmSettings = '/settings/llm';

  /// The route for a known name; `null` for any other (an unknown name never
  /// builds a screen of its own: see [onUnknownRoute]).
  static Route<void>? onGenerateRoute(RouteSettings settings) {
    final WidgetBuilder? builder = switch (settings.name) {
      library => (_) => const LibraryScreen(),
      board => (_) => BoardScreen(gameId: settings.arguments as int?),
      report => (_) => ReportScreen(gameId: settings.arguments as int?),
      Routes.settings => (_) => const SettingsScreen(),
      about => (_) => const AboutScreen(),
      llmSettings => (_) => const LlmSettingsScreen(),
      _ => null,
    };
    if (builder == null) return null;
    return MaterialPageRoute<void>(builder: builder, settings: settings);
  }

  /// An unknown name (an intent URI must never become a route; the manifest
  /// also turns Flutter deep linking off). It must not stack a second Library:
  /// on top of other routes it is an invisible page that removes itself at once;
  /// as the very first route there is nothing to remove, so the Library shows.
  static Route<void> onUnknownRoute(RouteSettings settings) => _UnknownRoute(settings);
}

class _UnknownRoute extends PageRouteBuilder<void> {
  _UnknownRoute(RouteSettings settings)
      : super(
          settings: settings,
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (context, _, _) => _SelfPop(first: !Navigator.of(context).canPop()),
        );
}

class _SelfPop extends StatefulWidget {
  const _SelfPop({required this.first});

  final bool first;

  @override
  State<_SelfPop> createState() => _SelfPopState();
}

class _SelfPopState extends State<_SelfPop> {
  @override
  void initState() {
    super.initState();
    if (!widget.first) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  Widget build(BuildContext context) => widget.first ? const LibraryScreen() : const SizedBox.shrink();
}
