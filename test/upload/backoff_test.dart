import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/upload/backoff.dart';

void main() {
  const base = Duration(seconds: 5);

  /// Delay range for attempt [n] before the cap: base * 2^(n-1), times 0.5..1.
  (int, int) bounds(int n, {int capMs = 300000}) {
    final raw = (base.inMilliseconds * pow(2, n - 1)).toInt();
    final capped = min(raw, capMs);
    return ((capped * 0.5).floor(), capped);
  }

  test('delays follow base * 2^(n-1) with jitter, capped at 5 minutes', () {
    final backoff = Backoff(base: base, random: Random(1));
    final expectedCaps = [
      5000,
      10000,
      20000,
      40000,
      80000,
      160000,
      300000,
      300000,
    ];
    for (var n = 1; n <= 8; n++) {
      final delay = backoff.delay(n).inMilliseconds;
      final (low, high) = bounds(n);
      expect(high, expectedCaps[n - 1], reason: 'cap for attempt $n');
      expect(delay, inInclusiveRange(low, high), reason: 'attempt $n');
    }
  });

  test('jitter stays within 50%..100% over many draws', () {
    final backoff = Backoff(base: base, random: Random(42));
    var min1 = 1 << 30;
    var max1 = 0;
    for (var i = 0; i < 2000; i++) {
      final ms = backoff.delay(1).inMilliseconds;
      min1 = min(min1, ms);
      max1 = max(max1, ms);
      expect(ms, inInclusiveRange(2500, 5000));
    }
    expect(min1, lessThan(2700), reason: 'the low end of the range is used');
    expect(
      max1,
      greaterThan(4800),
      reason: 'the high end of the range is used',
    );
  });

  test('the same seed reproduces the same sequence', () {
    final a = Backoff(base: base, random: Random(7));
    final b = Backoff(base: base, random: Random(7));
    expect(
      [for (var n = 1; n <= 10; n++) a.delay(n)],
      [for (var n = 1; n <= 10; n++) b.delay(n)],
    );
  });

  test('different seeds give different sequences', () {
    final a = Backoff(base: base, random: Random(1));
    final b = Backoff(base: base, random: Random(2));
    expect([
      for (var n = 1; n <= 6; n++) a.delay(n),
    ], isNot([for (var n = 1; n <= 6; n++) b.delay(n)]));
  });

  test('attempts below 1 behave like 1, and huge attempts do not overflow', () {
    final backoff = Backoff(base: base, random: Random(3));
    expect(backoff.delay(0).inMilliseconds, inInclusiveRange(2500, 5000));
    expect(backoff.delay(-4).inMilliseconds, inInclusiveRange(2500, 5000));
    expect(
      backoff.delay(5000).inMilliseconds,
      inInclusiveRange(150000, 300000),
    );
  });

  test('base, factor and cap are configurable', () {
    final backoff = Backoff(
      base: const Duration(seconds: 1),
      factor: 3,
      cap: const Duration(seconds: 20),
      random: Random(9),
    );
    expect(backoff.delay(1).inMilliseconds, inInclusiveRange(500, 1000));
    expect(backoff.delay(2).inMilliseconds, inInclusiveRange(1500, 3000));
    expect(backoff.delay(3).inMilliseconds, inInclusiveRange(4500, 9000));
    expect(backoff.delay(9).inMilliseconds, inInclusiveRange(10000, 20000));
  });
}
