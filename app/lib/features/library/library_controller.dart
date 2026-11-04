import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../engine/engine_providers.dart';
import '../../engine/engine_service.dart';
import '../explain/summary_controller.dart';

/// The library list. A swipe-to-delete hides the game at once and only deletes
/// it for real when the undo window closes ([commitDelete]).
class LibraryController extends AsyncNotifier<List<GameRecord>> {
  List<GameRecord> _all = const [];
  final Set<int> _pendingDelete = {};
  late EngineService _engine;

  @override
  Future<List<GameRecord>> build() async {
    final repo = ref.read(gameRepositoryProvider);
    // Captured here: Ref.read is not allowed inside onDispose.
    _engine = ref.read(engineServiceProvider);
    final engine = _engine;
    ref.onDispose(() {
      // Make swipes that were never undone permanent when the app tears down.
      for (final id in _pendingDelete.toList()) {
        unawaited(engine.cancel(id).whenComplete(() => repo.delete(id)));
      }
    });
    _all = await repo.list();
    return _visible();
  }

  List<GameRecord> _visible() => [
        for (final g in _all)
          if (!_pendingDelete.contains(g.id)) g,
      ];

  /// Reloads from the repository (after an import or an analysis update).
  Future<void> refresh() async {
    _all = await ref.read(gameRepositoryProvider).list();
    state = AsyncData(_visible());
  }

  /// Hides [id] from the list; call [undoDelete] or [commitDelete] later.
  void requestDelete(int id) {
    _pendingDelete.add(id);
    state = AsyncData(_visible());
  }

  void undoDelete(int id) {
    if (_pendingDelete.remove(id)) state = AsyncData(_visible());
  }

  Future<void> commitDelete(int id) async {
    if (!_pendingDelete.remove(id)) return;
    await _deleteForGood(id);
  }

  /// Deletes [id] at once (the board's "Delete game", after its own
  /// confirmation): the same steps as an undo window that closes.
  Future<void> deleteNow(int id) async {
    await future; // the list is loaded, so the state below is a real list
    _pendingDelete.remove(id);
    await _deleteForGood(id);
    state = AsyncData(_visible());
  }

  Future<void> _deleteForGood(int id) async {
    // Stop its analysis (running or queued) before the rows go away; the
    // pipeline also copes if a write still races the delete.
    // Its summary request goes first (the provider's disposal aborts it), so
    // nothing is saved for, or shown under, a game that no longer exists.
    ref.invalidate(summaryProvider(id));
    await _engine.cancel(id);
    await ref.read(gameRepositoryProvider).delete(id);
    ref.invalidate(summaryProvider(id));
    _all = [
      for (final g in _all)
        if (g.id != id) g,
    ];
  }
}

final libraryProvider = AsyncNotifierProvider<LibraryController, List<GameRecord>>(LibraryController.new);
