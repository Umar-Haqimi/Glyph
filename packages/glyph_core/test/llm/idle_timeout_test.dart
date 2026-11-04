import 'dart:async';

import 'package:glyph_core/src/llm/idle_timeout.dart';
import 'package:test/test.dart';

void main() {
  test('passes data and the end of the stream through', () async {
    final out = await idleTimeout(Stream.fromIterable([1, 2, 3]), const Duration(seconds: 5)).toList();
    expect(out, [1, 2, 3]);
  });

  test('errors pass through and do not end the stream by themselves', () async {
    final c = StreamController<int>();
    final seen = <Object>[];
    final done = Completer<void>();
    idleTimeout(c.stream, const Duration(seconds: 5)).listen(seen.add, onError: seen.add, onDone: done.complete);
    c
      ..add(1)
      ..addError('boom')
      ..add(2);
    await c.close();
    await done.future;
    expect(seen, [1, 'boom', 2]);
  });

  test('a silent source ends with a TimeoutException; events restart the clock', () async {
    final c = StreamController<int>();
    final seen = <Object>[];
    final done = Completer<void>();
    idleTimeout(c.stream, const Duration(milliseconds: 120)).listen(seen.add, onError: seen.add, onDone: done.complete);
    for (var i = 0; i < 4; i++) {
      c.add(i);
      await Future<void>.delayed(const Duration(milliseconds: 60)); // 240 ms in total, never idle for 120
    }
    expect(seen, [0, 1, 2, 3]);
    await done.future.timeout(const Duration(seconds: 2));
    expect(seen.last, isA<TimeoutException>());
    await c.close();
  });

  test('cancelling cancels the source', () async {
    var cancelled = false;
    final c = StreamController<int>(onCancel: () => cancelled = true);
    final sub = idleTimeout(c.stream, const Duration(seconds: 5)).listen((_) {});
    await sub.cancel();
    expect(cancelled, isTrue);
  });
}
