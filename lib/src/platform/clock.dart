/// Source of the current time. Injected so tests are deterministic.
abstract interface class Clock {
  /// The current time.
  DateTime now();
}

/// A [Clock] backed by the system clock. Always returns UTC.
class SystemClock implements Clock {
  /// Creates a system clock.
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
