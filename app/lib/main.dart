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
  final analyses = SqliteAnalysisRepository(db);
  // Crash recovery: no job runs yet, so `running` rows were left by a killed
  // process. Make them `paused` (Resume continues at completed_plies).
  await analyses.pauseInterrupted(updatedAt: DateTime.now().millisecondsSinceEpoch);
  runApp(
    ProviderScope(
      overrides: [
        gameRepositoryProvider.overrideWithValue(SqliteGameRepository(db)),
        analysisRepositoryProvider.overrideWithValue(analyses),
        settingsRepositoryProvider.overrideWithValue(SqliteSettingsRepository(db)),
      ],
      child: const EngineReloadGuard(child: GlyphApp()),
    ),
  );
}
