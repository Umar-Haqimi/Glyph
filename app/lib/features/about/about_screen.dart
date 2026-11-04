import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app_info.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/section_header.dart';
import 'asset_licences.dart';

/// About and licences (SPEC F20): version, the GPL-3.0-or-later notice, the
/// source repository, credits (Stockfish, chessground, dartchess, the opening
/// data), every bundled asset with its licence, a privacy summary, and
/// Flutter's licence page with the asset licences added.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  void _showLicences(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    registerAssetLicences();
    showLicensePage(
      context: context,
      applicationName: l10n.appTitle,
      applicationVersion: appVersion,
      applicationLegalese: l10n.aboutLicenseNotice,
    );
  }

  Future<void> _copyLink(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(const ClipboardData(text: projectUrl));
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(l10n.aboutSourceCopied)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.aboutTitle)),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Semantics(header: true, container: true, child: Text(l10n.appTitle, style: theme.textTheme.headlineMedium)),
            const SizedBox(height: 4),
            Text(l10n.aboutVersion(appVersion), key: const Key('about-version'), style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(l10n.aboutTagline),
            SectionHeader(l10n.aboutLicenseTitle, padding: const EdgeInsets.only(top: 24, bottom: 8)),
            Text(l10n.aboutLicenseNotice, key: const Key('about-license-notice')),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                key: const Key('about-licenses'),
                onPressed: () => _showLicences(context),
                child: Text(l10n.aboutLicenses),
              ),
            ),
            SectionHeader(l10n.aboutSourceTitle, padding: const EdgeInsets.only(top: 24, bottom: 8)),
            // One 48 dp tile: the address, and a tap copies it (Glyph has no
            // browser dependency, so there is no "open" action).
            ListTile(
              key: const Key('about-source-copy'),
              contentPadding: EdgeInsets.zero,
              title: Text(projectUrl, key: const Key('about-source-url')),
              subtitle: Text(l10n.aboutSourceCopy),
              trailing: const Icon(Icons.copy_outlined),
              onTap: () => _copyLink(context),
            ),
            SectionHeader(l10n.aboutCreditsTitle, padding: const EdgeInsets.only(top: 24, bottom: 8)),
            Text(l10n.aboutCreditStockfish, key: const Key('about-credit-stockfish')),
            const SizedBox(height: 8),
            Text(l10n.aboutCreditChessground, key: const Key('about-credit-chessground')),
            const SizedBox(height: 8),
            Text(l10n.aboutCreditOpenings, key: const Key('about-credit-openings')),
            SectionHeader(l10n.aboutAssetsTitle, padding: const EdgeInsets.only(top: 24, bottom: 8)),
            Text(l10n.aboutAssetsIntro),
            const SizedBox(height: 8),
            for (final asset in assetLicences)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  l10n.aboutAssetBy(asset.name, asset.licence, asset.author),
                  key: Key('about-asset-${asset.id}'),
                ),
              ),
            SectionHeader(l10n.aboutPrivacyTitle, padding: const EdgeInsets.only(top: 24, bottom: 8)),
            Text(l10n.aboutPrivacyBody, key: const Key('about-privacy')),
          ],
        ),
      ),
    );
  }
}
