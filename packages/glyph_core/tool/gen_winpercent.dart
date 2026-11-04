// Writes test/vectors/winpercent.json (SPEC 7.1 item 1): White Win% for
// cp in -2000..2000 step 50 and for a few mate scores, from the scalachess
// formula (core/src/main/scala/eval.scala L57-110; docs/m0/algorithms.md 1.1).
// The formula is written out here on purpose, independently of
// lib/src/classify/win_percent.dart, so the test cross-checks the two.
//
// Usage: cd packages/glyph_core && dart run tool/gen_winpercent.dart
import 'dart:convert';
import 'dart:io';
import 'dart:math';

double _win(int cp) {
  final c = cp < -1000 ? -1000 : (cp > 1000 ? 1000 : cp);
  return 50 + 50 * (2 / (1 + exp(-0.00368208 * c)) - 1);
}

void main() {
  final cps = [
    for (var cp = -2000; cp <= 2000; cp += 50) {'cp': cp, 'win': _win(cp)},
  ];
  final mates = [
    for (final m in [1, 5, 30, -1, -5, -30]) {'mate': m, 'win': _win(m > 0 ? 1000 : -1000)},
  ];
  final out = {
    'source': 'scalachess core/src/main/scala/eval.scala (b73baa5): clamp cp to +-1000, '
        'win = 50 + 50 * (2 / (1 + exp(-0.00368208 * cp)) - 1), every mate = +-1000 cp',
    'tolerance': 1e-9,
    'cp': cps,
    'mate': mates,
  };
  File('test/vectors/winpercent.json').writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(out)}\n');
  stdout.writeln('wrote test/vectors/winpercent.json (${cps.length} cp + ${mates.length} mate entries)');
}
