// Builds app/assets/openings.tsv (epd<TAB>eco<TAB>name) from a chess-openings
// checkout by replaying every line with dartchess, and records its SHA-256 in
// app/assets/openings.tsv.sha256 (sha256sum format).
//
// Usage (from the repo root):
//   dart run tool/build_openings.dart [path/to/chess-openings]
// Default checkout: ~/development/upstream/chess-openings (lichess-org/chess-openings, CC0).
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:glyph_core/glyph_core.dart';

Future<void> main(List<String> args) async {
  final home = Platform.environment['HOME'] ?? '';
  final src = Directory(args.isNotEmpty ? args.first : '$home/development/upstream/chess-openings');
  final files = <String>[];
  for (final volume in ['a', 'b', 'c', 'd', 'e']) {
    final f = File('${src.path}/$volume.tsv');
    if (!f.existsSync()) {
      stderr.writeln('Missing ${f.path}');
      exitCode = 2;
      return;
    }
    files.add(await f.readAsString());
  }
  final tsv = buildOpeningsTsv(files);
  final out = File('app/assets/openings.tsv');
  await out.create(recursive: true);
  await out.writeAsString(tsv);
  final digest = sha256.convert(utf8.encode(tsv)).toString();
  await File('app/assets/openings.tsv.sha256').writeAsString('$digest  openings.tsv\n');
  stdout.writeln('Wrote ${out.path}: ${tsv.split('\n').where((l) => l.isNotEmpty).length} rows, sha256 $digest');
}
