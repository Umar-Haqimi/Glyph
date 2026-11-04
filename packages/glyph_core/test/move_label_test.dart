import 'package:glyph_core/glyph_core.dart';
import 'package:test/test.dart';

void main() {
  test('there are exactly the 11 labels of the badge set', () {
    expect(MoveLabel.values, hasLength(11));
    expect(
      MoveLabel.values.map((l) => l.name),
      containsAll(<String>[
        'brilliant', 'great', 'best', 'excellent', 'good', 'book', //
        'forced', 'inaccuracy', 'mistake', 'miss', 'blunder',
      ]),
    );
  });
}
