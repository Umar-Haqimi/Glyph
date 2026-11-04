import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app_info.dart';
import 'package:glyph/features/about/asset_licences.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

Future<void> openAbout(WidgetTester tester) async {
  await tester.tap(find.byTooltip(l10n.settingsTooltip));
  await tester.pumpAndSettle();
  await tester.scrollUntilVisible(find.byKey(const Key('settings-about')), 300, scrollable: find.byType(Scrollable).first);
  await tester.tap(find.byKey(const Key('settings-about')));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('About (F20): version, GPL-3.0-or-later notice, source link, credits, assets and privacy', (tester) async {
    tester.view.physicalSize = const Size(800, 6000);
    await TestEnv().pump(tester);
    tester.view.physicalSize = const Size(800, 6000);
    await openAbout(tester);

    expect(find.text(l10n.aboutVersion(appVersion)), findsOneWidget);
    expect(appVersion, matches(RegExp(r'^\d+\.\d+\.\d+$')));
    final notice = tester.widget<Text>(find.byKey(const Key('about-license-notice'))).data!;
    expect(notice, contains('GNU General Public License'));
    expect(notice, contains('version 3 of the License, or (at your option) any later version'));
    expect(find.text(projectUrl), findsOneWidget);
    expect(projectUrl, 'https://github.com/Umar-Haqimi/Glyph');

    final stockfish = tester.widget<Text>(find.byKey(const Key('about-credit-stockfish'))).data!;
    expect(stockfish, allOf(contains('Stockfish'), contains('GPL-3.0'), contains('multistockfish')));
    final ground = tester.widget<Text>(find.byKey(const Key('about-credit-chessground'))).data!;
    expect(ground, allOf(contains('chessground'), contains('dartchess')));
    expect(tester.widget<Text>(find.byKey(const Key('about-credit-openings'))).data, allOf(contains('chess-openings'), contains('CC0')));

    // Every bundled asset is listed with its licence and author.
    for (final a in assetLicences) {
      final line = tester.widget<Text>(find.byKey(Key('about-asset-${a.id}'))).data!;
      expect(line, allOf(contains(a.name), contains(a.licence), contains(a.author)), reason: a.id);
    }
    // The privacy summary says what is sent where.
    final privacy = tester.widget<Text>(find.byKey(const Key('about-privacy'))).data!;
    expect(privacy, allOf(contains('no analytics'), contains('lichess.org'), contains('chess.com'), contains('API key')));
  });

  testWidgets('the source address is copied with one tap', (tester) async {
    final copied = <String?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String?);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    await TestEnv().pump(tester);
    await openAbout(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('about-source-copy')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('about-source-copy')));
    await tester.pump();
    expect(copied, [projectUrl]);
    expect(find.text(l10n.aboutSourceCopied), findsOneWidget);
  });

  testWidgets('"Open-source licences" opens Flutter\'s licence page with Glyph and its bundled assets listed', (tester) async {
    debugResetAssetLicenceRegistration();
    await TestEnv().pump(tester);
    await openAbout(tester);
    await tester.scrollUntilVisible(find.byKey(const Key('about-licenses')), 200, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('about-licenses')));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Glyph'), findsWidgets);
    expect(find.text(appVersion), findsWidgets);
    // The package list contains Glyph's own entry and an entry per asset.
    expect(find.text('Glyph asset: Merida chess pieces'), findsOneWidget);
    expect(find.text('Glyph asset: Openings'.replaceFirst('Openings', 'Opening names and positions')), findsOneWidget);
    await tester.tap(find.text('Glyph asset: Merida chess pieces'));
    await tester.pumpAndSettle();
    expect(find.textContaining('GPL-2.0-or-later'), findsOneWidget);
    expect(find.textContaining('Armando Hernandez Marroquin'), findsOneWidget);
  });
}
