import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart' show SemanticsAction, SemanticsNode;
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app.dart';
import 'package:glyph/data/models.dart';
import 'package:glyph/features/board/board_screen.dart';
import 'package:glyph/routes.dart';
import 'package:glyph_core/glyph_core.dart';
import 'package:material_ui/material_ui.dart';

import '../support/fake_online.dart';
import '../support/review_fixture.dart';
import '../support/test_app.dart';

/// M8 accessibility pass: every screen on a 360x740 phone with the text scale
/// at 2.0 (the Android maximum), light and dark, must lay out without an
/// overflow; touch targets are at least 48 dp and labelled; the screen reader
/// reaches things in reading order; headings exist.
const _phone = Size(360, 740);

String? _lastDetails;

Future<void> _phone360(WidgetTester tester, {double scale = 2.0, Brightness brightness = Brightness.light}) async {
  // Keep the full diagnostics (which widget overflowed) for the failure message.
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _lastDetails = details.toString();
    previous?.call(details);
  };
  addTearDown(() => FlutterError.onError = previous);
  tester.view.physicalSize = _phone;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  tester.platformDispatcher.platformBrightnessTestValue = brightness;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearTextScaleFactorTestValue();
    tester.platformDispatcher.clearPlatformBrightnessTestValue();
  });
}

Future<void> _pumpApp(WidgetTester tester, TestEnv env) async {
  await tester.pumpWidget(ProviderScope(overrides: env.overrides, child: const GlyphApp()));
  await tester.pumpAndSettle();
}

Future<void> _push(WidgetTester tester, String route, [Object? args]) async {
  tester.state<NavigatorState>(find.byType(Navigator).first).pushNamed(route, arguments: args);
  await tester.pumpAndSettle();
}

void _noProblems(WidgetTester tester, String where) {
  final e = tester.takeException();
  if (e != null) fail('$where: $e\n${_lastDetails ?? ''}');
}

/// Scrolls the first scrollable from top to bottom in steps, checking for
/// layout exceptions after each (an overflow can sit below the fold).
Future<void> _scrollThrough(WidgetTester tester, String where) async {
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) return;
  for (var i = 0; i < 40; i++) {
    final before = tester.state<ScrollableState>(scrollable.first).position.pixels;
    await tester.drag(scrollable.first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 50));
    _noProblems(tester, '$where (scrolled $i)');
    final after = tester.state<ScrollableState>(scrollable.first).position.pixels;
    if (after == before) break;
  }
}

typedef _Setup = Future<void> Function(WidgetTester tester, TestEnv env);

final _screens = <String, _Setup>{
  'library (empty)': (tester, env) async => _pumpApp(tester, env),
  'library (games)': (tester, env) async {
    await env.seed(white: 'A very long player name indeed', black: 'Another remarkably long name', status: AnalysisStatus.completed, completedPlies: 41, whiteAccuracy: 91.2, blackAccuracy: 55.5, eco: 'C50', openingName: 'Italian Game: Giuoco Piano', userSide: Side.white, source: GameSource.lichess);
    await env.seed(white: 'Carol', black: 'Dave', status: AnalysisStatus.paused, completedPlies: 12, importedAt: 2);
    await env.seed(white: 'Erin', black: 'Frank', importedAt: 3);
    await _pumpApp(tester, env);
  },
  'import sheet': (tester, env) async {
    await _pumpApp(tester, env);
    await tester.tap(find.text(l10n.libraryImportFab));
    await tester.pumpAndSettle();
  },
  'paste import (games found)': (tester, env) async {
    await _pumpApp(tester, env);
    await tester.tap(find.text(l10n.libraryImportFab));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.importPastePgn));
    await tester.tap(find.text(l10n.importPastePgn));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pgnField')), vectorPgn('no_blank_lines.pgn'));
    await tester.pumpAndSettle();
  },
  'paste import (error)': (tester, env) async {
    await _pumpApp(tester, env);
    await tester.tap(find.text(l10n.libraryImportFab));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.importPastePgn));
    await tester.tap(find.text(l10n.importPastePgn));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pgnField')), vectorPgn('illegal_move_single.pgn'));
    await tester.pumpAndSettle();
  },
  'online import (lichess, results)': (tester, env) async {
    await _pumpApp(tester, env);
    await tester.tap(find.text(l10n.libraryImportFab));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text(l10n.importFromLichess));
    await tester.tap(find.text(l10n.importFromLichess));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('onlineUsername')), 'someone');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onlineFetch')));
    await tester.pumpAndSettle();
  },
  'settings': (tester, env) async {
    await _pumpApp(tester, env);
    await _push(tester, Routes.settings);
  },
  'llm settings': (tester, env) async {
    await _pumpApp(tester, env);
    await _push(tester, Routes.llmSettings);
  },
  'about': (tester, env) async {
    await _pumpApp(tester, env);
    await _push(tester, Routes.about);
  },
  'board': (tester, env) async {
    final id = await seedReview(env, userSide: Side.white);
    await _pumpApp(tester, env);
    await _push(tester, Routes.board, id);
  },
  'report': (tester, env) async {
    final id = await seedReview(env, userSide: Side.white);
    await _pumpApp(tester, env);
    await _push(tester, Routes.report, id);
  },
};

TestEnv _env() => TestEnv(
      lichess: FakeOnlineClient.games([
        lichessOnline('aaaa1111', white: 'a_very_long_lichess_user_name', black: 'another_long_name'),
        lichessOnline('bbbb2222', speed: OnlineSpeed.rapid, result: '0-1'),
      ]),
    );

void main() {
  group('text scale 2.0 on 360x740: no overflow anywhere, top to bottom', () {
    for (final brightness in Brightness.values) {
      for (final entry in _screens.entries) {
        testWidgets('${entry.key}, ${brightness.name}', (tester) async {
          await _phone360(tester, brightness: brightness);
          final env = _env();
          await entry.value(tester, env);
          final where = '${entry.key} ${brightness.name}';
          _noProblems(tester, where);
          await _scrollThrough(tester, where);
        });
      }
    }
  });

  group('sheets and dialogs at text scale 2.0', () {
    testWidgets('key moments sheet, explain sheet and the report from the board', (tester) async {
      await _phone360(tester);
      final env = _env();
      final id = await seedReview(env, userSide: Side.white);
      await _pumpApp(tester, env);
      await _push(tester, Routes.board, id);
      await tester.tap(find.byKey(const Key('nav-next'))); // the start position has no Explain button
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open-key-moments')));
      await tester.pumpAndSettle();
      _noProblems(tester, 'key moments');
      await _scrollThrough(tester, 'key moments');
      tester.state<NavigatorState>(find.byType(Navigator).first).pop(); // close the sheet
      await tester.pumpAndSettle();
      expect(find.byType(BoardScreen), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      final vertical = find.descendant(
        of: find.byType(BoardScreen),
        matching: find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical),
      );
      await tester.scrollUntilVisible(find.byKey(const Key('explain-button')), 150, scrollable: vertical.first);
      await tester.tap(find.byKey(const Key('explain-button')));
      await tester.pumpAndSettle();
      _noProblems(tester, 'explain sheet (not configured)');
      await _scrollThrough(tester, 'explain sheet');
    });

    testWidgets('settings dialogs: engine, threads, hash, board colours (24 entries), piece set, delete all', (tester) async {
      await _phone360(tester);
      final env = _env();
      await _pumpApp(tester, env);
      await _push(tester, Routes.settings);
      for (final key in ['settings-engine-preset', 'settings-engine-threads', 'settings-engine-hash', 'settings-board-theme', 'settings-piece-set', 'settings-delete-all']) {
        await tester.scrollUntilVisible(find.byKey(Key(key)), 200, scrollable: find.byType(Scrollable).first);
        await tester.ensureVisible(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(key)));
        await tester.pumpAndSettle();
        _noProblems(tester, key);
        final dialog = find.byType(Dialog);
        expect(dialog, findsOneWidget, reason: key);
        await _scrollThroughDialog(tester, key);
        await tester.tapAt(const Offset(4, 4)); // barrier
        await tester.pumpAndSettle();
        expect(find.byType(Dialog), findsNothing, reason: key);
      }
    });
  });

  group('touch targets and labels', () {
    final screens = {
      'library': _screens['library (games)']!,
      'import sheet': _screens['import sheet']!,
      'settings': _screens['settings']!,
      'about': _screens['about']!,
      'board': _screens['board']!,
      'report': _screens['report']!,
      'online import': _screens['online import (lichess, results)']!,
    };
    for (final entry in screens.entries) {
      testWidgets('${entry.key}: every tappable is at least 48 dp and has a label (text scale 1.0 and 2.0)', (tester) async {
        final handle = tester.ensureSemantics();
        for (final scale in [1.0, 2.0]) {
          await _phone360(tester, scale: scale);
          final env = _env();
          await entry.value(tester, env);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: '${entry.key} @ $scale');
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: '${entry.key} @ $scale');
          await tester.pumpWidget(const SizedBox());
        }
        handle.dispose();
      });
    }
  });

  group('screen reader structure', () {
    testWidgets('settings: each section has a heading and the headings come in screen order', (tester) async {
      final handle = tester.ensureSemantics();
      await _phone360(tester, scale: 1.0);
      tester.view.physicalSize = const Size(360, 3600); // everything built at once
      final env = _env();
      await _screens['settings']!(tester, env);
      final headings = <String>[];
      for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
        if (node.getSemanticsData().flagsCollection.isHeader) headings.add(node.getSemanticsData().label);
      }
      expect(headings, [
        l10n.settingsTitle, // the app bar title
        l10n.settingsEngine,
        l10n.settingsExplanations,
        l10n.settingsAccounts,
        l10n.settingsAppearance,
        l10n.settingsData,
      ]);
      handle.dispose();
    });

    testWidgets('about: headings for the title and every section', (tester) async {
      final handle = tester.ensureSemantics();
      await _phone360(tester, scale: 1.0);
      tester.view.physicalSize = const Size(360, 3600);
      await _screens['about']!(tester, _env());
      final headings = [
        for (final node in tester.semantics.simulatedAccessibilityTraversal())
          if (node.getSemanticsData().flagsCollection.isHeader) node.getSemanticsData().label,
      ];
      expect(headings, [
        l10n.aboutTitle, // the app bar title
        l10n.appTitle,
        l10n.aboutLicenseTitle,
        l10n.aboutSourceTitle,
        l10n.aboutCreditsTitle,
        l10n.aboutAssetsTitle,
        l10n.aboutPrivacyTitle,
      ]);
      handle.dispose();
    });

    testWidgets('board: the traversal goes status -> gauge -> players and board -> coach -> move list -> bottom bar', (tester) async {
      final handle = tester.ensureSemantics();
      await _phone360(tester, scale: 1.0);
      final env = _env();
      final id = await seedReview(env, userSide: Side.white);
      await pumpReview(tester, env, id, initialPly: 6);
      tester.view.physicalSize = const Size(360, 3000);
      await tester.pumpAndSettle();
      String name(SemanticsNode n) {
        final d = n.getSemanticsData();
        return [d.label, d.tooltip, d.value].where((t) => t.isNotEmpty).join(' | ');
      }
      final order = [for (final n in tester.semantics.simulatedAccessibilityTraversal()) name(n)];
      int at(Pattern p) {
        final i = order.indexWhere((l) => p is String ? l.contains(p) : (p as RegExp).hasMatch(l));
        expect(i, isNonNegative, reason: 'no node labelled $p in $order');
        return i;
      }

      final sequence = [
        at(l10n.boardFlip),
        at(RegExp(r'Black, Bob')),
        at(RegExp(r'Bishop c5')), // the board / badge label
        at(RegExp(r'White, Alice')),
        at(RegExp(r'Move 4, White|Best was|Bishop c4')), // the coach card
        at(l10n.boardFirstMove),
        at(l10n.boardPreviousMove),
        at(l10n.boardNextMove),
        at(l10n.boardLastMove),
      ];
      final sorted = [...sequence]..sort();
      expect(sequence, sorted, reason: 'reading order: $order');
      handle.dispose();
    });

    testWidgets('keyboard focus order on the Paste screen follows the screen: text field, paste, clear, then the games', (tester) async {
      await _phone360(tester, scale: 1.0);
      final env = _env();
      await _screens['paste import (games found)']!(tester, env);
      String where() {
        final focus = FocusManager.instance.primaryFocus;
        if (focus == null) return 'none';
        final element = focus.context;
        if (element == null) return 'none';
        if (element.findAncestorWidgetOfExactType<EditableText>() != null || element.widget is EditableText) return 'field';
        final text = <String>[];
        void visit(Element e) {
          if (e.widget is Text) text.add((e.widget as Text).data ?? '');
          e.visitChildren(visit);
        }
        (element as Element).visitChildren(visit);
        return text.isEmpty ? element.widget.runtimeType.toString() : text.first;
      }

      // Start from the text field, then Tab through the controls.
      await tester.tap(find.byKey(const Key('pgnField')));
      await tester.pump();
      final order = <String>[where()];
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        order.add(where());
      }
      // Field, Paste from clipboard, Clear, then the games to choose from; Save is
      // disabled until one is chosen, so Tab skips it.
      expect(order.take(3).toList(), ['field', l10n.importPasteFromClipboard, l10n.importClear], reason: '$order');
      expect(order[3], contains(' – '), reason: 'the first game of the list: $order');
      await tester.tap(find.byKey(const Key('pgnField')));
      await tester.pump();
    });

    testWidgets('library: a game card is one node that reads players, result, date, moves, source, analysis, accuracy and side, and opens the game; the menu is its own node', (tester) async {
      final handle = tester.ensureSemantics();
      await _phone360(tester, scale: 1.0);
      final env = _env();
      await env.seed(white: 'Alice', black: 'Bob', status: AnalysisStatus.completed, completedPlies: 41, whiteAccuracy: 91.2, blackAccuracy: 55.5, eco: 'C50', openingName: 'Italian Game', userSide: Side.white, source: GameSource.lichess);
      await _pumpApp(tester, env);
      final nodes = [for (final n in tester.semantics.simulatedAccessibilityTraversal()) n.getSemanticsData()];
      final card = nodes.singleWhere((d) => d.label.startsWith('Alice (1500) – Bob'));
      for (final part in ['1-0', '2026-10-23', '20 moves', 'lichess', 'Analysed', 'White 91%', 'Black 56%', 'You: White', 'C50', 'Italian Game']) {
        expect(card.label, contains(part));
      }
      expect(card.flagsCollection.isButton, isTrue);
      expect(card.hasAction(SemanticsAction.tap), isTrue);
      // Nothing of the card's text is left as a separate stop.
      expect(nodes.where((d) => d.label == '1-0' || d.label == 'Analysed'), isEmpty);
      expect(nodes.where((d) => d.tooltip == l10n.boardMenuTooltip), hasLength(1));
      // Activating it through the semantics tree opens the board.
      await tester.tap(find.bySemanticsLabel(RegExp(r'^Alice \(1500\) – Bob')));
      await tester.pumpAndSettle();
      expect(find.byType(BoardScreen), findsOneWidget);
      handle.dispose();
    });

    testWidgets('every switch, button and slider in settings reports a label and a state', (tester) async {
      final handle = tester.ensureSemantics();
      await _phone360(tester, scale: 1.0);
      tester.view.physicalSize = const Size(360, 3600);
      await _screens['settings']!(tester, _env());
      var checked = 0;
      for (final node in tester.semantics.simulatedAccessibilityTraversal()) {
        final data = node.getSemanticsData();
        if (data.flagsCollection.isEnabled != Tristate.none || data.flagsCollection.isButton || data.flagsCollection.isToggled != Tristate.none) {
          expect(
            data.label.trim().isNotEmpty || data.value.trim().isNotEmpty || data.tooltip.trim().isNotEmpty,
            isTrue,
            reason: 'unlabelled control ${node.rect} $data',
          );
          checked++;
        }
      }
      expect(checked, greaterThan(10));
      handle.dispose();
    });
  });
}

Future<void> _scrollThroughDialog(WidgetTester tester, String where) async {
  final scrollable = find.descendant(of: find.byType(Dialog), matching: find.byType(Scrollable));
  if (scrollable.evaluate().isEmpty) return;
  for (var i = 0; i < 20; i++) {
    await tester.drag(scrollable.first, const Offset(0, -300));
    await tester.pump(const Duration(milliseconds: 30));
    _noProblems(tester, '$where (dialog scrolled $i)');
  }
}
