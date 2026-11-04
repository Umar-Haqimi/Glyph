import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/providers.dart';
import '../../data/repositories.dart';
import '../../l10n/app_localizations.dart';
import '../../routes.dart';
import '../library/game_text.dart';
import 'online_import_controller.dart';
import 'online_text.dart';

/// Import > From lichess / From chess.com (SPEC F16, F17): a username (prefilled
/// from Settings > Accounts), the recent games streamed in with speed filters,
/// a multi-select list that marks games already in the library, Import.
class OnlineImportScreen extends ConsumerStatefulWidget {
  const OnlineImportScreen({super.key, required this.source});

  final OnlineSource source;

  @override
  ConsumerState<OnlineImportScreen> createState() => _OnlineImportScreenState();
}

class _OnlineImportScreenState extends ConsumerState<OnlineImportScreen> {
  final _controller = TextEditingController();
  var _edited = false;

  OnlineSource get _source => widget.source;

  bool get _valid => _source == OnlineSource.lichess
      ? Usernames.isValidLichess(_controller.text.trim())
      : Usernames.isValidChessCom(_controller.text.trim());

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final key = _source == OnlineSource.lichess ? SettingsKeys.lichessUsername : SettingsKeys.chessComUsername;
    final saved = await ref.read(settingsRepositoryProvider).get(key);
    if (!mounted || _edited || saved == null) return;
    setState(() => _controller.text = saved);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fetch() {
    if (!_valid) return;
    FocusScope.of(context).unfocus();
    ref.read(onlineImportProvider(_source).notifier).fetch(_controller.text);
  }

  Future<void> _import() async {
    final l10n = AppLocalizations.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(onlineImportProvider(_source).notifier).importSelected();
    if (!mounted) return;
    if (result.importedIds.length == 1 && result.failed == 0) {
      // One game: straight to the board, where its analysis starts.
      await navigator.pushReplacementNamed(Routes.board, arguments: result.importedIds.single);
      return;
    }
    if (result.importedIds.isEmpty && result.failed == 0) return; // nothing new was saved
    navigator.pop();
    messenger.showSnackBar(SnackBar(
      content: Text(result.failed == 0
          ? l10n.onlineImported(result.importedIds.length)
          : l10n.onlineImportedSome(result.importedIds.length, result.failed)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(onlineImportProvider(_source));
    final controller = ref.read(onlineImportProvider(_source).notifier);
    final theme = Theme.of(context);
    final invalid = _controller.text.trim().isNotEmpty && !_valid;
    final title = _source == OnlineSource.lichess ? l10n.onlineTitleLichess : l10n.onlineTitleChessCom;
    final visible = state.visible;
    final status = _statusText(l10n, state);

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              // Everything scrolls together: with large text the form, the
              // chips and the toolbar alone fill a small phone.
              child: CustomScrollView(
                key: const Key('onlineList'),
                slivers: [
                  SliverToBoxAdapter(child: _header(context, l10n, theme, state, controller, status, invalid, visible)),
                  if (visible.isEmpty && state.games.isNotEmpty)
                    SliverFillRemaining(hasScrollBody: false, child: Center(child: Text(l10n.onlineNoMatch)))
                  else
                    SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, i) {
                        final game = visible[i];
                        return _GameTile(
                          game: game,
                          source: _source,
                          selected: state.selected.contains(game.sourceId),
                          inLibrary: state.inLibrary.containsKey(game.sourceId),
                          onChanged: () => controller.toggle(game.sourceId),
                        );
                      },
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  key: const Key('onlineImport'),
                  onPressed: state.importable.isEmpty || state.importing ? null : _import,
                  child: Text(state.importing ? l10n.onlineImporting : l10n.onlineImportSelected(state.importable.length)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _header(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
    OnlineImportState state,
    OnlineImportController controller,
    String? status,
    bool invalid,
    List<OnlineGame> visible,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: TextField(
                  key: const Key('onlineUsername'),
                  controller: _controller,
                  enabled: !state.loading,
                  onChanged: (_) => setState(() => _edited = true),
                  onSubmitted: (_) => _fetch(),
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: _source == OnlineSource.lichess ? l10n.onlineUsernameLabelLichess : l10n.onlineUsernameLabelChessCom,
                    errorText: invalid
                        ? (_source == OnlineSource.lichess ? l10n.onlineUsernameInvalidLichess : l10n.onlineUsernameInvalidChessCom)
                        : null,
                    errorMaxLines: 3,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: state.loading
                    ? OutlinedButton(
                        key: const Key('onlineCancel'),
                        style: OutlinedButton.styleFrom(minimumSize: const Size(64, 48)),
                        onPressed: controller.cancel,
                        child: Text(l10n.onlineCancel),
                      )
                    : FilledButton(
                        key: const Key('onlineFetch'),
                        style: FilledButton.styleFrom(minimumSize: const Size(64, 48)),
                        onPressed: _valid ? _fetch : null,
                        child: Text(state.phase == OnlinePhase.done ? l10n.onlineFetchAgain : l10n.onlineFetch),
                      ),
              ),
            ],
          ),
        ),
        if (state.loading)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: LinearProgressIndicator(semanticsLabel: status),
          ),
        if (status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Semantics(
              liveRegion: true,
              container: true,
              child: Text(
                status,
                key: const Key('onlineStatus'),
                style: theme.textTheme.bodyMedium?.copyWith(color: state.error != null ? theme.colorScheme.error : null),
              ),
            ),
          ),
        if (state.games.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final speed in speedFilters(_source))
                  FilterChip(
                    key: Key('speed-${speed.name}'),
                    label: Text(speedName(l10n, speed)),
                    selected: state.filters.contains(speed),
                    onSelected: (_) => controller.toggleFilter(speed),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                Text(
                  l10n.onlineSelectedCount(state.importable.length, visible.length),
                  key: const Key('onlineSelectedCount'),
                  style: theme.textTheme.labelLarge,
                ),
                TextButton(
                  key: const Key('onlineSelectAll'),
                  onPressed: visible.isEmpty ? null : controller.selectAll,
                  child: Text(l10n.onlineSelectAll),
                ),
                TextButton(
                  key: const Key('onlineSelectNone'),
                  onPressed: state.selected.isEmpty ? null : controller.selectNone,
                  child: Text(l10n.onlineSelectNone),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String? _statusText(AppLocalizations l10n, OnlineImportState state) {
    final site = siteName(l10n, _source);
    final backoff = state.backoff;
    if (backoff != null) {
      final seconds = (backoff.inMilliseconds / 1000).ceil();
      return _source == OnlineSource.lichess ? l10n.onlineBackoffLichess(seconds) : l10n.onlineBackoffChessCom(seconds);
    }
    if (state.loading) return l10n.onlineLoading(state.games.length, site);
    final error = state.error;
    final parts = <String>[];
    if (error != null) parts.add(onlineErrorText(l10n, _source, error));
    if (state.cancelled) parts.add(l10n.onlineCancelled);
    if (state.phase == OnlinePhase.done && error == null && !state.cancelled && state.games.isEmpty) parts.add(l10n.onlineEmpty);
    if (state.phase == OnlinePhase.done && state.skipped > 0) parts.add(l10n.onlineSkipped(state.skipped));
    return parts.isEmpty ? null : parts.join(' ');
  }
}

class _GameTile extends StatelessWidget {
  const _GameTile({
    required this.game,
    required this.source,
    required this.selected,
    required this.inLibrary,
    required this.onChanged,
  });

  final OnlineGame game;
  final OnlineSource source;
  final bool selected;
  final bool inLibrary;
  final VoidCallback onChanged;

  String _player(AppLocalizations l10n, String? name, int? rating) {
    final n = name ?? l10n.libraryUnknownPlayer;
    return rating == null ? n : l10n.libraryPlayerWithElo(n, rating);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final title = l10n.libraryGameTitle(_player(l10n, game.white, game.whiteRating), _player(l10n, game.black, game.blackRating));
    final tc = shortTimeControl(game.timeControl);
    final speed = tc == null ? speedName(l10n, game.speed) : '${speedName(l10n, game.speed)} $tc';
    final played = game.playedAtMs == null ? null : DateTime.fromMillisecondsSinceEpoch(game.playedAtMs!, isUtc: true);
    final date = played == null
        ? null
        : '${played.year.toString().padLeft(4, '0')}-${played.month.toString().padLeft(2, '0')}-${played.day.toString().padLeft(2, '0')}';
    final details = date == null
        ? l10n.onlineGameDetailsNoDate(speed, formatResult(game.result))
        : l10n.onlineGameDetails(date, speed, formatResult(game.result));
    final state = inLibrary ? l10n.onlineAlreadyImported : (selected ? l10n.onlineGameSelected : l10n.onlineGameNotSelected);
    return Semantics(
      container: true,
      excludeSemantics: true,
      checked: selected || inLibrary,
      enabled: !inLibrary,
      label: l10n.onlineGameSemantics(title, details, state),
      onTap: inLibrary ? null : onChanged,
      child: CheckboxListTile(
        key: Key('online-game-${game.sourceId}'),
        value: selected || inLibrary,
        onChanged: inLibrary ? null : (_) => onChanged(),
        controlAffinity: ListTileControlAffinity.leading,
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(details),
            if (inLibrary)
              Text(
                l10n.onlineAlreadyImported,
                key: Key('in-library-${game.sourceId}'),
                style: TextStyle(color: Theme.of(context).colorScheme.primary),
              ),
          ],
        ),
        isThreeLine: inLibrary,
      ),
    );
  }
}
