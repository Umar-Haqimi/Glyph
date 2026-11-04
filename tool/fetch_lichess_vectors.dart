// Fetches the lichess accuracy golden vectors (SPEC 7.1 item 2,
// docs/m0/VECTORS.md section 2) into
// packages/glyph_core/test/vectors/lichess_accuracy/{standard,chess960}.ndjson.
//
// Real, server-analysed games from the lichess games export API, trimmed to
// what the test needs (moves, White-POV evals, both players' accuracy) and
// with every user name, rating and title removed.
//
// Usage (from the repo root; network access needed):
//   dart run tool/fetch_lichess_vectors.dart
//
// One request at a time, 3 s apart; on HTTP 429 it waits 60 s and retries
// once (lichess API rules). Selection is deterministic for a given API
// response but the API returns the users' latest games, so a re-run picks
// other games; the committed files are the reference.
import 'dart:convert';
import 'dart:io';

const _ua = 'Glyph-vectors (https://github.com/Umar-Haqimi/Glyph)';
const _users = ['DrNykterstein', 'penguingim1', 'Fins'];
const _outDir = 'packages/glyph_core/test/vectors/lichess_accuracy';

Future<void> main() async {
  final client = HttpClient()
    ..findProxy = HttpClient.findProxyFromEnvironment
    ..userAgent = _ua;
  final pool = <Map<String, dynamic>>[];
  final chess960 = <Map<String, dynamic>>[];
  try {
    for (final user in _users) {
      pool.addAll(await _fetch(client, user, 'blitz,rapid,classical', 60));
      await Future<void>.delayed(const Duration(seconds: 3));
      chess960.addAll(await _fetch(client, user, 'chess960', 15));
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  } finally {
    client.close();
  }

  final standard = _select(pool.where(_usable).toList(), 34);
  final c960 = _select960(chess960.where(_usable).toList(), 4);
  await Directory(_outDir).create(recursive: true);
  await File('$_outDir/standard.ndjson').writeAsString(standard.map((g) => '${jsonEncode(_trim(g))}\n').join());
  await File('$_outDir/chess960.ndjson').writeAsString(c960.map((g) => '${jsonEncode(_trim(g))}\n').join());
  stdout.writeln('pool ${pool.length} standard + ${chess960.length} chess960; '
      'wrote ${standard.length} standard and ${c960.length} chess960 games to $_outDir');
  _report(standard + c960);
}

Future<List<Map<String, dynamic>>> _fetch(HttpClient client, String user, String perf, int max) async {
  final uri = Uri.https('lichess.org', '/api/games/user/$user', {
    'max': '$max',
    'analysed': 'true',
    'evals': 'true',
    'accuracy': 'true',
    'opening': 'true',
    'perfType': perf,
  });
  for (var attempt = 0; attempt < 2; attempt++) {
    final req = await client.getUrl(uri);
    req.headers.set(HttpHeaders.acceptHeader, 'application/x-ndjson');
    final res = await req.close();
    if (res.statusCode == 429) {
      await res.drain<void>();
      stderr.writeln('429 from lichess, waiting 60 s');
      await Future<void>.delayed(const Duration(seconds: 60));
      continue;
    }
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode} for $uri');
    }
    final body = await res.transform(utf8.decoder).join();
    return [
      for (final l in const LineSplitter().convert(body))
        if (l.trim().isNotEmpty) jsonDecode(l) as Map<String, dynamic>,
    ];
  }
  throw HttpException('rate limited twice for $uri');
}

int _plies(Map<String, dynamic> g) => (g['moves'] as String).split(' ').where((m) => m.isNotEmpty).length;

int? _acc(Map<String, dynamic> g, String colour) =>
    ((g['players'] as Map)[colour] as Map?)?['analysis']?['accuracy'] as int?;

bool _usable(Map<String, dynamic> g) {
  final p = _plies(g);
  return g['analysis'] is List && _acc(g, 'white') != null && _acc(g, 'black') != null && p >= 20 && p <= 150;
}

bool _hasMateEval(Map<String, dynamic> g) => (g['analysis'] as List).any((e) => (e as Map).containsKey('mate'));

/// Greedy cover of the categories of docs/m0/VECTORS.md, then filled up.
List<Map<String, dynamic>> _select(List<Map<String, dynamic>> pool, int target) {
  final chosen = <Map<String, dynamic>>[];
  final ids = <String>{};
  void take(bool Function(Map<String, dynamic>) where, int n) {
    for (final g in pool) {
      if (chosen.where(where).length >= n) return;
      if (!ids.contains(g['id']) && where(g)) {
        chosen.add(g);
        ids.add(g['id'] as String);
      }
    }
  }

  take((g) => _plies(g) <= 40, 4);
  take((g) => _plies(g) >= 120, 4);
  take((g) => g['winner'] == 'white', 4);
  take((g) => g['winner'] == 'black', 4);
  take((g) => g['status'] == 'draw', 4);
  take((g) => g['status'] == 'stalemate', 1);
  take((g) => g['status'] == 'mate', 6);
  take(_hasMateEval, 6);
  take((g) => g['status'] == 'outoftime', 2);
  take((g) => true, target);
  return chosen.take(target).toList();
}

List<Map<String, dynamic>> _select960(List<Map<String, dynamic>> pool, int target) {
  final castles = pool.where((g) => (g['moves'] as String).contains('O-O')).toList();
  final rest = pool.where((g) => !castles.contains(g)).toList();
  return [...castles.take(target ~/ 2 + 1), ...rest].take(target).toList();
}

Map<String, dynamic> _trim(Map<String, dynamic> g) => {
      'id': g['id'],
      'variant': g['variant'],
      'speed': g['speed'],
      'status': g['status'],
      if (g['winner'] != null) 'winner': g['winner'],
      if (g['initialFen'] != null) 'initialFen': g['initialFen'],
      'plies': _plies(g),
      'moves': g['moves'],
      'analysis': [
        for (final e in g['analysis'] as List)
          if ((e as Map).containsKey('mate')) {'mate': e['mate']} else {'eval': e['eval']},
      ],
      'accuracy': {'white': _acc(g, 'white'), 'black': _acc(g, 'black')},
    };

void _report(List<Map<String, dynamic>> games) {
  int count(bool Function(Map<String, dynamic>) f) => games.where(f).length;
  stdout.writeln('  20-40 plies: ${count((g) => _plies(g) <= 40)}, 120-150: ${count((g) => _plies(g) >= 120)}');
  stdout.writeln('  white wins: ${count((g) => g['winner'] == 'white')}, black wins: ${count((g) => g['winner'] == 'black')}, '
      'draws: ${count((g) => g['winner'] == null)}');
  for (final s in ['mate', 'resign', 'outoftime', 'draw', 'stalemate']) {
    stdout.writeln('  status $s: ${count((g) => g['status'] == s)}');
  }
  stdout.writeln('  with mate evals: ${count(_hasMateEval)}, chess960: ${count((g) => g['variant'] == 'chess960')}');
}
