import 'dart:math';

/// Exponential backoff with jitter.
///
/// `delay(n) = min(base * factor^(n-1), cap) * jitter`, with jitter drawn
/// uniformly from 0.5 to 1.0. The [Random] is injectable so tests are
/// reproducible.
class Backoff {
  /// Creates a backoff policy.
  Backoff({
    required this.base,
    this.factor = 2.0,
    this.cap = const Duration(minutes: 5),
    Random? random,
  }) : _random = random ?? Random();

  /// Delay before the first retry, before jitter.
  final Duration base;

  /// Growth per attempt.
  final double factor;

  /// Longest delay, before jitter.
  final Duration cap;

  final Random _random;

  /// The wait before retry number [attempt] (1 for the first).
  Duration delay(int attempt) {
    final n = attempt < 1 ? 1 : attempt;
    final grown = base.inMilliseconds * pow(factor, n - 1);
    final capped = min(grown, cap.inMilliseconds.toDouble());
    final jitter = 0.5 + _random.nextDouble() * 0.5;
    return Duration(milliseconds: (capped * jitter).round());
  }
}
