import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/db.dart';
import 'data/providers.dart';
import 'data/sqlite_repositories.dart';
import 'engine/engine_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final dir = await getApplicationSupportDirectory();
  final db = Db.open('${dir.path}/glyph.db');
  runApp(
    ProviderScope(
      overrides: [
        gameRepositoryProvider.overrideWithValue(SqliteGameRepository(db)),
        analysisRepositoryProvider.overrideWithValue(SqliteAnalysisRepository(db)),
        settingsRepositoryProvider.overrideWithValue(SqliteSettingsRepository(db)),
      ],
      child: const EngineReloadGuard(child: GlyphApp()),
    ),
  );
}
