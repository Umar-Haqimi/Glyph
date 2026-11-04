import 'package:glyph_core/glyph_core.dart';

import '../../l10n/app_localizations.dart';

String siteName(AppLocalizations l10n, OnlineSource source) =>
    source == OnlineSource.lichess ? l10n.siteLichess : l10n.siteChessCom;

String speedName(AppLocalizations l10n, OnlineSpeed speed) => switch (speed) {
      OnlineSpeed.bullet => l10n.speedBullet,
      OnlineSpeed.blitz => l10n.speedBlitz,
      OnlineSpeed.rapid => l10n.speedRapid,
      OnlineSpeed.classical => l10n.speedClassical,
      OnlineSpeed.correspondence => l10n.speedCorrespondence,
      OnlineSpeed.daily => l10n.speedDaily,
    };

/// The filter chips of each site (SPEC section 4, screen 2).
List<OnlineSpeed> speedFilters(OnlineSource source) => source == OnlineSource.lichess
    ? const [OnlineSpeed.bullet, OnlineSpeed.blitz, OnlineSpeed.rapid, OnlineSpeed.classical, OnlineSpeed.correspondence]
    : const [OnlineSpeed.bullet, OnlineSpeed.blitz, OnlineSpeed.rapid, OnlineSpeed.daily];

/// `180+2` -> `3+2`, `45` -> `0:45`, `1/86400` (days per move) -> null.
String? shortTimeControl(String? tc) {
  if (tc == null) return null;
  final m = RegExp(r'^(\d+)(?:\+(\d+))?$').firstMatch(tc.trim());
  if (m == null) return null;
  final seconds = int.parse(m.group(1)!);
  final inc = m.group(2);
  final base = seconds % 60 == 0 ? '${seconds ~/ 60}' : '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  return inc == null ? base : '$base+$inc';
}

/// The message for a failed fetch.
String onlineErrorText(AppLocalizations l10n, OnlineSource source, OnlineFetchError error) {
  final site = siteName(l10n, source);
  return switch (error.kind) {
    OnlineErrorKind.invalidUsername =>
      source == OnlineSource.lichess ? l10n.onlineUsernameInvalidLichess : l10n.onlineUsernameInvalidChessCom,
    OnlineErrorKind.userNotFound => l10n.onlineErrorUserNotFound(site),
    OnlineErrorKind.unavailable => l10n.onlineErrorUnavailable(site),
    OnlineErrorKind.rateLimited => l10n.onlineErrorRateLimited(site),
    OnlineErrorKind.offline => l10n.onlineErrorOffline,
    OnlineErrorKind.timeout => l10n.onlineErrorTimeout(site),
    OnlineErrorKind.tls => l10n.onlineErrorTls(site),
    OnlineErrorKind.server =>
      error.status == null ? l10n.onlineErrorServerNoCode(site) : l10n.onlineErrorServer(site, error.status!),
    OnlineErrorKind.badResponse => l10n.onlineErrorBadResponse(site),
    OnlineErrorKind.tooLarge => l10n.onlineErrorTooLarge(site),
  };
}
