import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';

import 'app.dart';
import 'data/db.dart';
import 'data/providers.dart';
import 'data/sqlite_repositories.dart';
import 'engine/engine_providers.dart';
import 'features/about/asset_licences.dart';
import 'features/errors/failure_text.dart';
import 'features/errors/recovery.dart';
import 'features/settings/appearance_settings.dart';
import 'features/settings/explain_settings.dart';
import 'l10n/app_localizations.dart';
import 'platform/app_log.dart';
import 'platform/online_http.dart';
import 'platform/secret_store.dart';
import 'theme/app_theme.dart';

/// Where the games database lives (`getApplicationSupportDirectory()/glyph.db`).
Future<String> defaultDatabasePath() async => '${(await getApplicationSupportDirectory()).path}/glyph.db';

/// Deletes the database file and its WAL / SHM companions.
Future<void> deleteDatabaseFiles(String path) async {
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final f = File('$path$suffix');
    if (f.existsSync()) await f.delete();
  }
}

/// Opens the database, migrates it and applies the crash recovery for rows a
/// killed process left `running`.
Future<Db> openAppDb(String path) async {
  final db = Db.open(path);
  try {
    // No job runs yet, so any `running` row belongs to a killed process: make
    // it `paused` (Resume continues at completed_plies).
    await SqliteAnalysisRepository(db).pauseInterrupted(updatedAt: DateTime.now().millisecondsSinceEpoch);
  } on Object {
    db.close();
    rethrow;
  }
  return db;
}

/// The root of the app. The first frame is a plain background (the process
/// shows the launch window until then); the database opens after it, so a
/// slow open or migration never delays the first frame, and a database that
/// cannot be opened shows the recovery screen instead of a crash.
class Bootstrap extends StatefulWidget {
  const Bootstrap({super.key, this.databasePath = defaultDatabasePath, this.open = openAppDb, this.deleteFiles = deleteDatabaseFiles});

  final Future<String> Function() databasePath;
  final Future<Db> Function(String path) open;
  final Future<void> Function(String path) deleteFiles;

  @override
  State<Bootstrap> createState() => _BootstrapState();
}

enum _Phase { opening, ready, failed, resetFailed }

class _BootstrapState extends State<Bootstrap> {
  _Phase _phase = _Phase.opening;
  Db? _db;
  AppearanceSettings? _appearance;
  String? _path;

  @override
  void initState() {
    super.initState();
    // Cheap (a closure is registered); the texts are built only when the
    // licence page is opened.
    registerAssetLicences();
    unawaited(_open());
  }

  @override
  void dispose() {
    _db?.close();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() => _phase = _Phase.opening);
    try {
      final path = _path ??= await widget.databasePath();
      final db = await widget.open(path);
      // The stored theme is read before the first real frame (no flash).
      final appearance = await AppearanceSettings.load(SqliteSettingsRepository(db));
      if (!mounted) {
        db.close();
        return;
      }
      setState(() {
        _db = db;
        _appearance = appearance;
        _phase = _Phase.ready;
      });
    } on Object catch (e) {
      AppLog.warning('Opening the database failed', e);
      if (mounted) setState(() => _phase = _Phase.failed);
    }
  }

  Future<void> _reset() async {
    try {
      final path = _path ??= await widget.databasePath();
      await widget.deleteFiles(path);
    } on Object catch (e) {
      AppLog.warning('Deleting the database failed', e);
      if (mounted) setState(() => _phase = _Phase.resetFailed);
      return;
    }
    await _open();
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.opening:
        return const _OpeningBackground();
      case _Phase.failed:
      case _Phase.resetFailed:
        return StartupErrorApp(resetFailed: _phase == _Phase.resetFailed, onRetry: _open, onReset: _reset);
      case _Phase.ready:
        final db = _db!;
        final analyses = SqliteAnalysisRepository(db);
        return ProviderScope(
          overrides: [
            gameRepositoryProvider.overrideWithValue(SqliteGameRepository(db)),
            analysisRepositoryProvider.overrideWithValue(analyses),
            settingsRepositoryProvider.overrideWithValue(SqliteSettingsRepository(db)),
            llmCacheRepositoryProvider.overrideWithValue(SqliteLlmCacheRepository(db)),
            secretStoreProvider.overrideWithValue(const FlutterSecretStore()),
            onlineCacheProvider.overrideWithValue(SqliteOnlineCache(db)),
            initialAppearanceProvider.overrideWithValue(_appearance),
          ],
          child: const EngineReloadGuard(child: GlyphApp()),
        );
    }
  }
}

/// What shows before the database is open: the window background, no widgets
/// of the app (nothing to flash).
class _OpeningBackground extends StatelessWidget {
  const _OpeningBackground();

  @override
  Widget build(BuildContext context) {
    // The colour of the launch window (styles.xml: `?android:colorBackground`),
    // so there is no flash when the first Flutter frame replaces it.
    final dark = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    return ColoredBox(color: dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF));
  }
}

/// The recovery screen when the database cannot be opened: Try again, or
/// delete the database and start fresh (after a confirmation).
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({super.key, required this.onRetry, required this.onReset, this.resetFailed = false});

  final VoidCallback onRetry;
  final Future<void> Function() onReset;
  final bool resetFailed;

  @override
  Widget build(BuildContext context) {
    final themes = buildThemes();
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      theme: themes.light,
      darkTheme: themes.dark,
      localizationsDelegates: [AppLocalizations.delegate, ...GlobalMaterialLocalizations.delegates],
      supportedLocales: AppLocalizations.supportedLocales,
      home: _StartupErrorScreen(onRetry: onRetry, onReset: onReset, resetFailed: resetFailed),
    );
  }
}

class _StartupErrorScreen extends StatelessWidget {
  const _StartupErrorScreen({required this.onRetry, required this.onReset, required this.resetFailed});

  final VoidCallback onRetry;
  final Future<void> Function() onReset;
  final bool resetFailed;

  Future<void> _confirmReset(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.startupDbResetConfirmTitle),
        content: Text(l10n.startupDbResetConfirmBody),
        actions: [
          TextButton(
            key: const Key('startup-reset-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            key: const Key('startup-reset-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.startupDbReset),
          ),
        ],
      ),
    );
    if (ok == true) await onReset();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(header: true, container: true, child: Text(l10n.startupDbTitle, style: theme.textTheme.headlineSmall)),
                const SizedBox(height: 12),
                Semantics(liveRegion: true, child: Text(appFailureText(l10n, AppFailure.databaseOpen))),
                if (resetFailed) ...[
                  const SizedBox(height: 12),
                  Text(
                    l10n.startupDbResetFailed,
                    key: const Key('startup-reset-failed'),
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(key: const Key('startup-retry'), onPressed: onRetry, child: Text(l10n.startupDbRetry)),
                const SizedBox(height: 12),
                OutlinedButton(
                  key: const Key('startup-reset'),
                  onPressed: () => _confirmReset(context),
                  child: Text(l10n.startupDbReset),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
