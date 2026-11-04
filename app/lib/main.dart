import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // The first frame is drawn at once; the database opens inside [Bootstrap].
  runApp(const Bootstrap());
}
