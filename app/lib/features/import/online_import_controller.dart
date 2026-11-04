import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';

import '../../data/models.dart';
import '../../data/providers.dart';
import '../../platform/app_log.dart';
import '../../platform/online_http.dart';
import 'import_service.dart';

enum OnlinePhase { idle, loading, done }

/// What the "From lichess" / "From chess.com" screen shows.
class OnlineImportState {
  const OnlineImportState({
    this.phase = OnlinePhase.idle,
    this.username = '',
    this.games = const [],
    this.inLibrary = const {},
    this.selected = const {},
    this.filters = const {},
    this.backoff,
    this.error,
    this.cancelled = false,
    this.skipped = 0,
    this.importing = false,
  });

  final OnlinePhase phase;

  /// The name the games were fetched for.
  final String username;

  /// Newest first, in arrival order.
  final List<OnlineGame> games;

  /// Source id -> game id, for the games that are already in the library.
  final Map<String, int> inLibrary;
  final Set<String> selected;

  /// Speeds to show; empty = all.
  final Set<OnlineSpeed> filters;

  /// While the site said "slow down": the time left before the retry.
  final Duration? backoff;
  final OnlineFetchError? error;
  final bool cancelled;
  final int skipped;
  final bool importing;

  bool get loading => phase == OnlinePhase.loading;

  /// The games the filter chips let through.
  List<OnlineGame> get visible =>
      filters.isEmpty ? games : [for (final g in games) if (filters.contains(g.speed)) g];

  /// Selected games that are shown, not yet in the library: what Import saves.
  List<OnlineGame> get importable => [
        for (final g in visible)
          if (selected.contains(g.sourceId) && !inLibrary.containsKey(g.sourceId)) g,
      ];

  OnlineImportState copyWith({
    OnlinePhase? phase,
    String? username,
    List<OnlineGame>? games,
    Map<String, int>? inLibrary,
    Set<String>? selected,
    Set<OnlineSpeed>? filters,
    Duration? Function()? backoff,
    OnlineFetchError? Function()? error,
    bool? cancelled,
    int? skipped,
    bool? importing,
  }) =>
      OnlineImportState(
        phase: phase ?? this.phase,
        username: username ?? this.username,
        games: games ?? this.games,
        inLibrary: inLibrary ?? this.inLibrary,
        selected: selected ?? this.selected,
        filters: filters ?? this.filters,
        backoff: backoff == null ? this.backoff : backoff(),
        error: error == null ? this.error : error(),
        cancelled: cancelled ?? this.cancelled,
        skipped: skipped ?? this.skipped,
        importing: importing ?? this.importing,
      );
}

/// What an import of the selected games did.
class OnlineImportResult {
  const OnlineImportResult({this.importedIds = const [], this.failed = 0});

  final List<int> importedIds;

  /// Games whose PGN could not be read.
  final int failed;
}

/// Fetches one site's recent games, tracks the selection and imports it. Closing
/// the screen (disposing the provider) cancels a running fetch.
class OnlineImportController extends Notifier<OnlineImportState> {
  OnlineImportController(this.source);

  final OnlineSource source;
  OnlineCancelToken? _token;
  var _run = 0;
  Future<void> _lookups = Future.value();

  GameSource get _gameSource => source == OnlineSource.lichess ? GameSource.lichess : GameSource.chesscom;

  @override
  OnlineImportState build() {
    ref.onDispose(() => _token?.cancel());
    return const OnlineImportState();
  }

  OnlineGamesClient get _client => ref.read(source == OnlineSource.lichess ? lichessClientProvider : chessComClientProvider);

  /// Starts (or restarts) the fetch for [username]. The name must already be
  /// valid; the clients check it again before any request.
  Future<void> fetch(String username) async {
    _token?.cancel();
    final token = _token = OnlineCancelToken();
    final run = ++_run;
    final name = username.trim();
    state = OnlineImportState(phase: OnlinePhase.loading, username: name, filters: state.filters);

    final OnlineFetchOutcome outcome;
    try {
      outcome = await _client.fetchGames(name, cancel: token, onEvent: (event) {
        if (!ref.mounted || run != _run) return;
        switch (event) {
          case OnlineGameReceived(:final game):
            state = state.copyWith(games: [...state.games, game], backoff: () => null);
            _lookup(run);
          case OnlineBackoff(:final remaining):
            state = state.copyWith(backoff: () => remaining);
        }
      });
    } on Object catch (e) {
      AppLog.warning('Fetching online games failed', e);
      if (ref.mounted && run == _run) {
        state = state.copyWith(
          phase: OnlinePhase.done,
          backoff: () => null,
          error: () => const OnlineFetchError(OnlineErrorKind.badResponse),
        );
      }
      return;
    }
    if (!ref.mounted || run != _run) return; // superseded by a newer fetch, or the screen is gone
    state = state.copyWith(
      phase: OnlinePhase.done,
      games: outcome.games,
      backoff: () => null,
      error: () => outcome.error,
      cancelled: outcome.cancelled,
      skipped: outcome.skipped,
    );
    await _lookup(run);
  }

  /// Stops a running fetch (also while it waits out a 429). The games received
  /// so far stay on the list.
  void cancel() => _token?.cancel();

  Future<void> _lookup(int run) {
    return _lookups = _lookups.then((_) async {
      if (!ref.mounted || run != _run) return;
      try {
        final ids = [for (final g in state.games) g.sourceId];
        final found = await ref.read(gameRepositoryProvider).idsBySource(_gameSource, ids);
        if (!ref.mounted || run != _run) return;
        state = state.copyWith(inLibrary: found);
      } on Object catch (e) {
        AppLog.warning('Looking up imported games failed', e);
      }
    });
  }

  void toggle(String sourceId) {
    if (state.inLibrary.containsKey(sourceId)) return;
    final next = {...state.selected};
    if (!next.remove(sourceId)) next.add(sourceId);
    state = state.copyWith(selected: next);
  }

  /// Selects every shown game that is not in the library yet.
  void selectAll() => state = state.copyWith(
        selected: {
          ...state.selected,
          for (final g in state.visible)
            if (!state.inLibrary.containsKey(g.sourceId)) g.sourceId,
        },
      );

  void selectNone() => state = state.copyWith(selected: {});

  void toggleFilter(OnlineSpeed speed) {
    final next = {...state.filters};
    if (!next.remove(speed)) next.add(speed);
    state = state.copyWith(filters: next);
  }

  /// Saves the selected, shown games that are not in the library yet. Each
  /// keeps `(source, source_id)`; the side is the fetched account's (known
  /// from the game), else the configured names' (SPEC F15).
  Future<OnlineImportResult> importSelected() async {
    if (state.importing) return const OnlineImportResult();
    final todo = state.importable;
    state = state.copyWith(importing: true);
    final service = ref.read(importServiceProvider);
    final imported = <int>[];
    var failed = 0;
    try {
      for (final online in todo) {
        final parsed = await parsePgnAsync(online.pgn);
        if (parsed.games.isEmpty) {
          failed++;
          continue;
        }
        final saved = await service.save(
          parsed.games.first,
          _gameSource,
          sourceId: online.sourceId,
          userSide: online.sideOf(state.username),
        );
        if (!saved.duplicate) imported.add(saved.id);
      }
    } finally {
      if (ref.mounted) {
        state = state.copyWith(importing: false, selected: {});
        await _lookup(_run);
      }
    }
    return OnlineImportResult(importedIds: imported, failed: failed);
  }
}

final onlineImportProvider = NotifierProvider.autoDispose.family<OnlineImportController, OnlineImportState, OnlineSource>(
  OnlineImportController.new,
);
