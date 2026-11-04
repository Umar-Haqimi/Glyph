/// Wall-clock abstraction so timestamps are deterministic in tests.
abstract interface class Clock {
  /// Milliseconds since the Unix epoch.
  int nowMs();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  int nowMs() => DateTime.now().millisecondsSinceEpoch;
}

/// A clock that only moves when told to.
class FakeClock implements Clock {
  FakeClock([this._now = 0]);

  int _now;

  @override
  int nowMs() => _now;

  void advance(Duration d) => _now += d.inMilliseconds;
}
