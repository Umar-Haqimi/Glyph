import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../../data/models.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/app_log.dart';
import '../../platform/share_intake.dart';
import '../errors/failure_text.dart';
import 'import_preview_screen.dart';
import 'pgn_issue_text.dart';

/// Why shared content cannot be imported.
enum ShareProblem {
  /// Over the 2 MB cap.
  tooLarge,

  /// The intent could not be read.
  unreadable,

  /// A link (a lichess / chess.com game URL, a web page): links are not
  /// fetched, see [decideShare].
  link,

  /// Text with no chess game in it.
  noGame,

  /// The provider stalled past the native deadline.
  timeout,
}

/// What to do with [SharedContent]: show the games to pick from, or tell the
/// user why not.
sealed class ShareDecision {
  const ShareDecision();
}

class ShareReady extends ShareDecision {
  const ShareReady(this.result);

  final PgnParseResult result;
}

class ShareRefused extends ShareDecision {
  const ShareRefused(this.problem);

  final ShareProblem problem;
}

/// A PGN problem (illegal move, unsupported variant...) with its own message.
class ShareInvalid extends ShareDecision {
  const ShareInvalid(this.issue);

  final PgnIssue issue;
}

final _urlPattern = RegExp(r'https?://', caseSensitive: false);

/// Decides what a share / open-with intake leads to (SPEC F2).
///
/// Shared **text** and **files** go through the same parser as paste and
/// Open file (2 MB cap, BOM / CRLF, multi-game, `[%clk]`...). A shared **link**
/// (the lichess app shares game URLs, browsers share page URLs) is **not**
/// fetched: SPEC lists PGN text and files for Share, and fetching from a share
/// intent would send a request nobody asked for. Text that contains no game and
/// a URL says so ([ShareProblem.link]) and points to From lichess / From
/// chess.com.
Future<ShareDecision> decideShare(SharedContent content) async {
  switch (content) {
    case SharedTooLarge():
      return const ShareRefused(ShareProblem.tooLarge);
    case SharedUnreadable():
      return const ShareRefused(ShareProblem.unreadable);
    case SharedTimedOut():
      return const ShareRefused(ShareProblem.timeout);
    case SharedReading():
      // Not a result; the host shows a progress note and waits for the next event.
      return const ShareRefused(ShareProblem.unreadable);
    case SharedFile(:final bytes):
      return _decide(await parsePgnBytesAsync(bytes), null);
    case SharedText(:final text):
      if (utf8.encode(text).length > Limits.maxPgnBytes) return const ShareRefused(ShareProblem.tooLarge);
      return _decide(await parsePgnAsync(text), text);
  }
}

ShareDecision _decide(PgnParseResult result, String? text) {
  if (result is! PgnFailed) return ShareReady(result);
  final issue = result.issue;
  if (issue.kind != PgnIssueKind.noGames) return ShareInvalid(issue);
  if (text != null && _urlPattern.hasMatch(text)) return const ShareRefused(ShareProblem.link);
  return const ShareRefused(ShareProblem.noGame);
}

/// Listens for shared content for the whole life of the app and routes it into
/// the import flow: the same game picker and Save as the file flow (source
/// "share"), then the board. Wrap the app's navigator with it.
class ShareIntakeHost extends ConsumerStatefulWidget {
  const ShareIntakeHost({super.key, required this.navigatorKey, required this.child, this.decide = decideShare});

  final GlobalKey<NavigatorState> navigatorKey;

  /// [decideShare]; a parameter so tests can make one share fail.
  final Future<ShareDecision> Function(SharedContent content) decide;
  final Widget child;

  @override
  ConsumerState<ShareIntakeHost> createState() => _ShareIntakeHostState();
}

class _ShareIntakeHostState extends ConsumerState<ShareIntakeHost> {
  StreamSubscription<SharedContent>? _sub;
  var _queue = Future<void>.value();

  @override
  void initState() {
    super.initState();
    final service = ref.read(shareIntakeServiceProvider);
    _sub = service.shared.listen((content) {
      // One failing share must not stop the later ones: errors are caught per item.
      _queue = _queue.then((_) => _handle(content)).catchError((Object e) {
        AppLog.warning('Handling a shared item failed', e);
      });
    });
    // After the first frame the navigator exists, so the launching intent can
    // be routed the moment it arrives.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) service.start();
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  Future<void> _handle(SharedContent content) async {
    final messenger = widget.navigatorKey.currentContext == null
        ? null
        : ScaffoldMessenger.maybeOf(widget.navigatorKey.currentContext!);
    if (content is SharedReading) {
      final ctx = widget.navigatorKey.currentContext;
      if (ctx != null && ctx.mounted) {
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(SnackBar(
          key: const Key('shareReading'),
          duration: const Duration(seconds: 30),
          content: Text(AppLocalizations.of(ctx).shareReading),
        ));
      }
      return;
    }
    messenger?.hideCurrentSnackBar();
    final decision = await widget.decide(content);
    final navigator = widget.navigatorKey.currentState;
    final context = widget.navigatorKey.currentContext;
    if (!mounted || navigator == null || context == null || !context.mounted) return;
    final l10n = AppLocalizations.of(context);
    switch (decision) {
      case ShareReady(:final result):
        // Not awaited: a second share while this one is open shows its own screen.
        unawaited(navigator.push(MaterialPageRoute<void>(
          builder: (_) => ImportPreviewScreen(result: result, source: GameSource.share),
        )));
      case ShareRefused(:final problem):
        unawaited(_notice(context, shareProblemText(l10n, problem)));
      case ShareInvalid(:final issue):
        unawaited(_notice(context, pgnIssueText(l10n, issue)));
    }
  }

  Future<void> _notice(BuildContext context, String message) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppLocalizations.of(dialogContext).shareTitle),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(MaterialLocalizations.of(dialogContext).okButtonLabel),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
