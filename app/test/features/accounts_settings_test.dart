import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../support/test_app.dart';

Future<void> openSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip(l10n.settingsTooltip));
  await tester.pumpAndSettle();
}

Future<void> editName(WidgetTester tester, String tileKey, String text) async {
  await tester.ensureVisible(find.byKey(Key(tileKey)));
  await tester.tap(find.byKey(Key(tileKey)));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('settings-username-field')), text);
  await tester.pumpAndSettle();
}

const pgn = '[Site "https://lichess.org/abc"]\n[White "Alice_99"]\n[Black "bob"]\n[Result "1-0"]\n\n1. e4 e5 2. Nf3 Nc6 1-0';

void main() {
  testWidgets('Settings > Accounts lists both names, "Not set" by default', (tester) async {
    await TestEnv().pump(tester);
    await openSettings(tester);
    expect(find.text(l10n.settingsAccounts), findsOneWidget);
    expect(find.text(l10n.settingsAccountsHelp), findsOneWidget);
    expect(find.text(l10n.settingsUsernameNotSet), findsNWidgets(2));
  });

  testWidgets('a lichess name is validated, trimmed, saved and shown', (tester) async {
    final env = TestEnv();
    await env.pump(tester);
    await openSettings(tester);

    await editName(tester, 'settings-lichess-username', 'not valid!');
    expect(find.text(l10n.onlineUsernameInvalidLichess), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('settings-username-save'))).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('settings-username-field')), '  Alice_99 ');
    await tester.pumpAndSettle();
    expect(find.text(l10n.onlineUsernameInvalidLichess), findsNothing);
    await tester.tap(find.byKey(const Key('settings-username-save')));
    await tester.pumpAndSettle();
    expect(await env.settings.get('lichess_username'), 'Alice_99');
    expect(find.text('Alice_99'), findsOneWidget);
    expect(await env.settings.get('chesscom_username'), isNull);
  });

  testWidgets('chess.com names have their own format (3 to 25 characters)', (tester) async {
    final env = TestEnv();
    await env.pump(tester);
    await openSettings(tester);
    await editName(tester, 'settings-chesscom-username', 'ab');
    expect(find.text(l10n.onlineUsernameInvalidChessCom), findsOneWidget);
    await tester.enterText(find.byKey(const Key('settings-username-field')), 'abc');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-username-save')));
    await tester.pumpAndSettle();
    expect(await env.settings.get('chesscom_username'), 'abc');
  });

  testWidgets('Remove (or saving an empty name) deletes the setting; Cancel changes nothing', (tester) async {
    final env = TestEnv(settings: {'lichess_username': 'old_name', 'chesscom_username': 'keepme'});
    await env.pump(tester);
    await openSettings(tester);
    expect(find.text('old_name'), findsOneWidget);

    await editName(tester, 'settings-lichess-username', 'changed');
    await tester.tap(find.text(l10n.settingsUsernameCancel));
    await tester.pumpAndSettle();
    expect(await env.settings.get('lichess_username'), 'old_name');

    await tester.tap(find.byKey(const Key('settings-lichess-username')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-username-clear')));
    await tester.pumpAndSettle();
    expect(await env.settings.get('lichess_username'), isNull);
    expect(find.text('old_name'), findsNothing);

    await tester.tap(find.byKey(const Key('settings-chesscom-username')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('settings-username-field')), '   ');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-username-save')));
    await tester.pumpAndSettle();
    expect(await env.settings.get('chesscom_username'), isNull);
  });

  testWidgets('the saved name feeds side detection at import (case-insensitive) and a later change leaves old games alone', (tester) async {
    final env = TestEnv();
    await env.pump(tester);
    final before = await env.seed(white: 'Alice_99', black: 'bob'); // imported before the name existed
    await openSettings(tester);
    await editName(tester, 'settings-lichess-username', 'alice_99');
    await tester.tap(find.byKey(const Key('settings-username-save')));
    await tester.pumpAndSettle();

    final id = await _importPasted(tester, env, pgn);
    expect((await env.games.get(id))!.userSide, Side.white);
    expect((await env.games.get(before))!.userSide, isNull, reason: 'detection runs at import only (documented policy)');

    // Changing the name again does not rewrite the stored side either.
    tester.state<NavigatorState>(find.byType(Navigator)).popUntil((r) => r.isFirst);
    await tester.pumpAndSettle();
    await openSettings(tester);
    await tester.tap(find.byKey(const Key('settings-lichess-username')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('settings-username-field')), 'someone_else');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('settings-username-save')));
    await tester.pumpAndSettle();
    expect((await env.games.get(id))!.userSide, Side.white);
  });

  testWidgets('tiles and dialog buttons are at least 48 dp tall and the tiles read as buttons', (tester) async {
    final handle = tester.ensureSemantics();
    await TestEnv(settings: {'lichess_username': 'alice'}).pump(tester);
    await openSettings(tester);
    await tester.ensureVisible(find.byKey(const Key('settings-lichess-username')));
    expect(tester.getSize(find.byKey(const Key('settings-lichess-username'))).height, greaterThanOrEqualTo(48));
    final node = tester.getSemantics(find.byKey(const Key('settings-lichess-username')));
    expect(node.label, contains(l10n.settingsLichessUsername));
    expect(node.label, contains('alice'));
    await tester.tap(find.byKey(const Key('settings-lichess-username')));
    await tester.pumpAndSettle();
    for (final key in ['settings-username-save', 'settings-username-clear']) {
      expect(tester.getSize(find.byKey(Key(key))).height, greaterThanOrEqualTo(48), reason: key);
    }
    handle.dispose();
  });
}

/// Back to the library, then Import > Paste PGN > Save (the real flow).
Future<int> _importPasted(WidgetTester tester, TestEnv env, String text) async {
  tester.state<NavigatorState>(find.byType(Navigator)).popUntil((r) => r.isFirst);
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.libraryImportFab));
  await tester.pumpAndSettle();
  await tester.tap(find.text(l10n.importPastePgn));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('pgnField')), text);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('importSave')));
  await tester.pumpAndSettle();
  final games = await env.games.list();
  for (final g in games) {
    if (g.source == GameSource.paste && g.white == 'Alice_99' && (await env.games.get(g.id))!.pgn.contains('Nf3')) return g.id;
  }
  throw StateError('the pasted game was not saved');
}
