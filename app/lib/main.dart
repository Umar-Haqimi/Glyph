import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'bootstrap.dart';
import 'platform/error_hooks.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  installErrorHooks();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // The first frame is drawn at once; the database opens inside [Bootstrap].
  runApp(const Bootstrap());
}
