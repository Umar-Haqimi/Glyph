import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/app_info.dart';
import 'package:glyph/data/db.dart';
import 'package:glyph_core/glyph_core.dart';

import 'support/test_app.dart';

/// docs/PRIVACY.md says what is stored and sent. These checks keep it true:
/// the tables, hosts, request parameters, limits, permission and the Settings
/// actions it names are the ones the code has.
void main() {
  final doc = File('../docs/PRIVACY.md').readAsStringSync();

  test('it names every table of the database', () {
    final db = Db.inMemory();
    addTearDown(db.close);
    final tables = db.raw.select("SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'").map((r) => r['name'] as String);
    // Tables that hold no personal data and are structure only are described together.
    const described = {'games', 'analyses', 'position_lines', 'move_labels', 'llm_cache', 'http_cache', 'settings'};
    expect(tables.toSet(), described, reason: 'a new table needs a line in PRIVACY.md section 3');
    for (final t in ['llm_cache', 'http_cache', 'settings', 'glyph.db']) {
      expect(doc, contains(t));
    }
  });

  test('the three hosts, https only, the generic User-Agent, no cookies and no credentials', () {
    for (final host in ['lichess.org', 'api.chess.com']) {
      expect(doc, contains(host));
    }
    expect(doc, contains(onlineUserAgent.replaceFirst(appVersion, '<version>')));
    expect(doc, contains('no cookies, no credentials'));
    expect(doc, contains('HTTPS only'));
    expect(doc, contains('`android.permission.INTERNET`'));
    expect(doc, contains('tool/check_permissions.sh'));
  });

  test('the lichess request parameters in the document are the ones the client sends', () {
    final source = File('../packages/glyph_core/lib/src/online/lichess_client.dart').readAsStringSync();
    for (final param in ['max', 'pgnInJson', 'clocks', 'evals', 'opening', 'sort', 'perfType']) {
      expect(source, contains("'$param'"), reason: 'the client no longer sends $param');
      expect(doc, contains('$param='), reason: 'PRIVACY.md does not list $param');
    }
    // Nothing the client sends is missing from the document: no other query key.
    final keys = RegExp(r"'(\w+)': ").allMatches(source.substring(source.indexOf('queryParameters'), source.indexOf('queryParameters') + 600)).map((m) => m.group(1)).toSet();
    expect(keys.difference({'max', 'pgnInJson', 'clocks', 'evals', 'opening', 'sort', 'perfType'}), isEmpty);
  });

  test('the limits it quotes are the real ones', () {
    expect(Limits.maxOnlineResponseBytes, 16 * 1024 * 1024);
    expect(doc, contains('16 MB'));
    expect(Limits.maxNdjsonLineBytes, 1024 * 1024);
    expect(doc, contains('1 MB'));
    expect(Limits.maxOnlineGames, 50);
    expect(doc, contains('50 games'));
    expect(Limits.maxPgnBytes, 2 * 1024 * 1024);
    expect(doc, contains('2 MB'));
  });

  test('the Settings actions it points to exist with those names', () {
    expect(doc, contains(l10n.settingsClearExplanations));
    expect(doc, contains(l10n.settingsClearOnline));
    expect(doc, contains(l10n.settingsDeleteAll));
    expect(doc, contains('Remove key'));
    expect(l10n.llmApiKeyRemove, 'Remove key');
    expect(doc, contains('Send the key over unencrypted http'));
  });

  test('it lists what is never sent to the LLM, and the prompt tests that enforce it exist', () {
    for (final word in ['player names', 'usernames', 'ratings', 'dates', 'time controls']) {
      expect(doc, contains(word));
    }
    expect(File('../packages/glyph_core/test/llm/prompt_builder_test.dart').existsSync(), isTrue);
    expect(Directory('../packages/glyph_core/test/vectors/prompts').existsSync(), isTrue);
  });

  test('every top-level field of a move prompt is described', () {
    final snapshot = File('../packages/glyph_core/test/vectors/prompts/move_blunder_user.txt').readAsStringSync();
    final json = snapshot.substring(snapshot.indexOf('=== user ===') + 12);
    final keys = RegExp(r'^  "(\w+)":', multiLine: true).allMatches(json).map((m) => m.group(1)!).toSet();
    expect(keys, containsAll(['move', 'classification', 'fenBefore', 'bestMove', 'refutation', 'hangingAfterMove', 'flags', 'opening', 'phase', 'audience', 'tone', 'language']));
    // The document's list: words that cover each field.
    const words = {
      'move': 'the move in SAN',
      'classification': 'the label',
      'fenBefore': 'FEN',
      'winChanceBefore': 'win chances',
      'winChanceAfter': 'win chances',
      'evalBefore': 'evaluations',
      'evalAfter': 'evaluations',
      'bestMove': 'best line',
      'secondBest': 'second-best line',
      'refutation': 'refutes',
      'material': 'material balance',
      'hangingAfterMove': 'hanging',
      'flags': 'flags',
      'opening': 'opening name',
      'phase': 'game phase',
      'audience': 'audience level',
      'tone': 'tone',
      'language': 'language',
    };
    for (final key in keys) {
      expect(words, contains(key), reason: 'the prompt has a field "$key" that PRIVACY.md does not cover');
      expect(doc, contains(words[key]!), reason: key);
    }
  });

  test('every top-level field of the game summary prompt is described, and the "ending" claim is true of the code', () {
    final snapshot = File('../packages/glyph_core/test/vectors/prompts/summary_opera_coach.txt').readAsStringSync();
    final json = snapshot.substring(snapshot.indexOf('=== user ===') + 12);
    final keys = RegExp(r'^  "(\w+)":', multiLine: true).allMatches(json).map((m) => m.group(1)!).toSet();
    expect(keys, containsAll(['result', 'userResult', 'ending', 'plyCount', 'opening', 'userSide', 'accuracy', 'labelCounts', 'keyMoments', 'whiteWinChanceEvery5Plies', 'audience', 'tone', 'language']));
    const words = {
      'result': 'the result as the game records it',
      'userResult': 'whether you won',
      'ending': 'how the game ended',
      'plyCount': 'the number of plies',
      'opening': 'the opening name',
      'userSide': 'your side',
      'accuracy': 'accuracy percentages',
      'labelCounts': 'how many moves of each label',
      'keyMoments': 'key moments',
      'whiteWinChanceEvery5Plies': 'every 5 plies',
      'audience': 'audience level, tone and language',
      'tone': 'audience level, tone and language',
      'language': 'audience level, tone and language',
    };
    for (final key in keys) {
      expect(words, contains(key), reason: 'the summary prompt has a field "$key" that PRIVACY.md does not cover');
      expect(doc, contains(words[key]!), reason: key);
    }
    // The document says the result is the PGN's marker and the ending is derived from the final position, never from a header.
    final builder = File('../packages/glyph_core/lib/src/llm/prompt_builder.dart').readAsStringSync();
    expect(builder, contains("'result': game.result,"));
    expect(builder, contains("'ending': _ending(game, wins.last, positions.last)"));
    expect(builder, isNot(contains('Termination')), reason: 'the Termination header (user names on chess.com) is never read');
    expect(doc, contains('the PGN\'s result marker'));
    expect(doc, contains('never from the `Termination` header'));
    final resultValues = RegExp(r"'result': '([^']*)'").allMatches(json).map((m) => m.group(1)).toList();
    expect(resultValues.every((r) => const {'1-0', '0-1', '1/2-1/2', '*'}.contains(r)), isTrue);
  });

  test('the LLM User-Agent in the document is the one the HTTP client sends, and the code comment agrees', () {
    expect(doc, contains('`User-Agent: ${llmUserAgent.replaceFirst(appVersion, '<version>')}`'));
    final comment = File('lib/platform/llm_http.dart').readAsStringSync();
    expect(comment, isNot(contains('no user agent')));
    expect(comment, contains('llmUserAgent'));
  });

  test('what it says about exported files, key records and logging matches the code', () {
    expect(doc, contains('deleted at every app start, when you delete a game, and by *Delete all data*'));
    expect(File('lib/platform/shared_exports.dart').existsSync(), isTrue);
    expect(File('lib/bootstrap.dart').readAsStringSync(), contains('sharedExports.clear()'));
    expect(File('lib/features/library/library_controller.dart').readAsStringSync(), contains('sharedExportsProvider'));
    expect(File('lib/features/settings/data_management.dart').readAsStringSync(), contains('sharedExportsProvider'));
    // Logging: the hooks the document names exist and are installed.
    expect(doc, contains('FlutterError.onError'));
    expect(doc, contains('PlatformDispatcher.instance.onError'));
    expect(doc, contains('app/lib/platform/error_hooks.dart'));
    expect(File('lib/platform/error_hooks.dart').existsSync(), isTrue);
    expect(File('lib/main.dart').readAsStringSync(), contains('installErrorHooks()'));
    expect(File('lib/platform/app_log.dart').readAsStringSync(), contains('developer.log'));
    expect(doc, contains('in the release APK Glyph\'s Dart code writes nothing to logcat'));
    // Keys: no auto-binding to the current URL, and the reset erases keys.
    expect(doc, contains('never sent to "whatever the URL is now"'));
    expect(doc, contains('start-up database reset'));
  });
}
