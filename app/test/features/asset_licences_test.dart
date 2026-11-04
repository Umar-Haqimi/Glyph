import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glyph/features/about/asset_licences.dart';
import 'package:glyph/features/board/board_assets.dart';
import 'package:yaml/yaml.dart';

/// SPEC trap 15: the asset audit stays true. The Dart list, `docs/ASSETS.md`,
/// the files on disk and the vendoring allow-list must agree, and no licence
/// outside the free list may appear.
const _free = {
  'GPL-2.0-or-later',
  'GPL-3.0-or-later',
  'AGPL-3.0-or-later',
  'CC0-1.0',
  'Apache-2.0',
  'ODbL-1.0', // attribution for the data the Stockfish network was trained on (nothing of it ships)
  'blessing', // SQLite's public-domain dedication
};

String _doc() => File('../docs/ASSETS.md').readAsStringSync();

Set<String> _entries(Directory dir) => {
      for (final e in dir.listSync()) e.path.split('/').last,
    };

void main() {
  test('every asset has a free licence, an author and a source', () {
    expect(assetLicences, isNotEmpty);
    final ids = <String>{};
    for (final a in assetLicences) {
      expect(ids.add(a.id), isTrue, reason: 'duplicate id ${a.id}');
      expect(_free, contains(a.spdx), reason: '${a.id}: ${a.spdx} is not on the free list');
      expect(a.author.trim(), isNotEmpty, reason: a.id);
      expect(a.source.trim(), isNotEmpty, reason: a.id);
      expect(a.licence.trim(), isNotEmpty, reason: a.id);
      expect(a.name.trim(), isNotEmpty, reason: a.id);
    }
  });

  test('no licence on the list is non-commercial, no-derivatives or "freeware"', () {
    for (final a in assetLicences) {
      final text = '${a.licence} ${a.spdx} ${a.note}'.toLowerCase();
      expect(text, isNot(contains('non-commercial')), reason: a.id);
      expect(text, isNot(contains('noncommercial')), reason: a.id);
      expect(text, isNot(contains('-nc')), reason: a.id);
      expect(text, isNot(contains('no-derivatives')), reason: a.id);
      expect(text, isNot(contains('freeware')), reason: a.id);
    }
  });

  test('every path an entry names exists', () {
    for (final a in assetLicences) {
      for (final path in a.paths) {
        final repoPath = '../$path';
        if (path.endsWith('/')) {
          expect(Directory(repoPath).existsSync(), isTrue, reason: '${a.id}: $path');
          expect(Directory(repoPath).listSync(), isNotEmpty, reason: '${a.id}: $path');
        } else {
          expect(File(repoPath).existsSync(), isTrue, reason: '${a.id}: $path');
        }
      }
    }
  });

  test('every piece set directory on disk is licensed, and the allow-lists, the script and the pubspec say the same', () {
    final onDisk = _entries(Directory('../third_party/chessground/assets/piece_sets'));
    final licensed = {
      for (final a in assetLicences)
        if (a.kind == AssetKind.pieceSet) a.id.replaceFirst('piece-', ''),
    };
    expect(onDisk, licensed, reason: 'a piece set without a licence entry (or an entry without files)');
    expect(selectablePieceSets.keys.toSet(), licensed);
    final script = File('../tool/vendor_chessground.sh').readAsStringSync();
    final listed = RegExp(r'KEEP_PIECE_SETS=\(([^)]*)\)').firstMatch(script)!.group(1)!.split(RegExp(r'\s+')).where((e) => e.isNotEmpty).toSet();
    expect(listed, licensed);
    final pubspec = loadYaml(File('../third_party/chessground/pubspec.yaml').readAsStringSync()) as YamlMap;
    final assets = (pubspec['flutter'] as YamlMap)['assets'] as YamlList;
    expect(assets.toSet(), {for (final s in licensed) 'assets/piece_sets/$s/', 'assets/boards/'});
  });

  test('every file under app/assets is licensed; nothing but the openings data ships there', () {
    final files = Directory('assets').listSync(recursive: true).whereType<File>().map((f) => f.path.replaceFirst('assets/', '')).toSet();
    expect(files, {'openings.tsv', 'openings.tsv.sha256'});
    final covered = {for (final a in assetLicences) ...a.paths};
    expect(covered, containsAll(['app/assets/openings.tsv', 'app/assets/openings.tsv.sha256']));
    // And the Flutter assets of the app are exactly that file.
    final pubspec = loadYaml(File('pubspec.yaml').readAsStringSync()) as YamlMap;
    expect(((pubspec['flutter'] as YamlMap)['assets'] as YamlList).toList(), ['assets/openings.tsv']);
    expect((pubspec['flutter'] as YamlMap).containsKey('fonts'), isFalse, reason: 'a bundled font needs a licence entry');
  });

  test('board images on disk are the board-images entry, and none is the non-free one', () {
    final boards = _entries(Directory('../third_party/chessground/assets/boards'));
    expect(boards, hasLength(19));
    expect(boards.any((b) => b.startsWith('horsey')), isFalse);
    // Left out in M8: unreferenced (ncf-board) / licence not confirmed (newspaper).
    expect(boards, isNot(contains('ncf-board.webp')));
    expect(boards, isNot(contains('newspaper.webp')));
  });

  test('the launcher icon is Glyph\'s own vector drawing: no template PNGs remain', () {
    final res = Directory('android/app/src/main/res');
    final pngs = res.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.png') || f.path.endsWith('.webp') || f.path.endsWith('.jpg'));
    expect(pngs, isEmpty, reason: 'the Flutter template icons were replaced by an adaptive vector icon');
    expect(File('android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml').readAsStringSync(), contains('<adaptive-icon'));
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(), contains('android:icon="@mipmap/ic_launcher"'));
  });

  group('docs/ASSETS.md', () {
    test('has a section for every asset with the same licence, author and files', () {
      final doc = _doc();
      for (final a in assetLicences) {
        final start = doc.indexOf('### `${a.id}`');
        expect(start, isNonNegative, reason: 'no section for ${a.id}');
        final next = doc.indexOf('\n### ', start + 4);
        final end = next == -1 ? doc.indexOf('\n## ', start + 4) : next;
        final section = doc.substring(start, end == -1 ? doc.length : end);
        expect(section, contains(a.name), reason: a.id);
        expect(section, contains('`${a.spdx}`'), reason: '${a.id}: SPDX');
        expect(section, contains(a.author), reason: '${a.id}: author');
        for (final p in a.paths) {
          expect(section, contains('`$p`'), reason: '${a.id}: $p');
        }
      }
    });

    test('lists the removed sets and says how they stay out', () {
      final doc = _doc();
      for (final removed in ['horsey', 'alpha', 'shahi-ivory-brown', 'leipzig', 'california']) {
        expect(doc, contains(removed));
      }
      expect(doc, contains('tool/vendor_chessground.sh'));
      expect(doc, contains('board_assets.dart'));
    });
  });

  test('the licence page gets the asset licences and Glyph\'s own notice', () async {
    debugResetAssetLicenceRegistration();
    registerAssetLicences();
    registerAssetLicences(); // idempotent
    final entries = <LicenseEntry>[];
    await for (final e in LicenseRegistry.licenses) {
      entries.add(e);
    }
    final glyph = entries.where((e) => e.packages.contains('Glyph')).toList();
    expect(glyph, hasLength(1));
    final text = glyph.single.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('GNU General Public License'));
    expect(text, contains('either version 3 of the License, or (at your option) any later version'));
    expect(text, contains('https://github.com/Umar-Haqimi/Glyph'));
    final assets = entries.where((e) => e.packages.any((p) => p.startsWith('Glyph asset: '))).toList();
    expect(assets, hasLength(assetLicences.length));
    for (final a in assetLicences) {
      final entry = assets.singleWhere((e) => e.packages.contains('Glyph asset: ${a.name}'));
      final body = entry.paragraphs.map((p) => p.text).join('\n');
      expect(body, contains(a.spdx));
      expect(body, contains(a.author));
    }
  });
}
