import 'dart:async';

/// [source] with an idle limit: if no event (data, error or done) arrives for
/// [limit], a [TimeoutException] is added and the stream ends. Every event
/// restarts the clock, so a long answer is fine while a stalled one is cut.
///
/// Used instead of `Stream.timeout`, whose end-of-stream event is not delivered
/// reliably under a fake-async test zone.
Stream<T> idleTimeout<T>(Stream<T> source, Duration limit) {
  late final StreamController<T> out;
  StreamSubscription<T>? sub;
  Timer? timer;

  void arm() {
    timer?.cancel();
    timer = Timer(limit, () {
      if (out.isClosed) return;
      out.addError(TimeoutException('No data for ${limit.inSeconds} s', limit));
      unawaited(sub?.cancel());
      unawaited(out.close());
    });
  }

  out = StreamController<T>(
    onListen: () {
      arm();
      sub = source.listen(
        (event) {
          arm();
          out.add(event);
        },
        onError: (Object error, StackTrace stack) {
          arm();
          out.addError(error, stack);
        },
        onDone: () {
          timer?.cancel();
          unawaited(out.close());
        },
      );
    },
    onPause: () => sub?.pause(),
    onResume: () => sub?.resume(),
    onCancel: () {
      timer?.cancel();
      unawaited(sub?.cancel());
    },
  );
  return out.stream;
}
