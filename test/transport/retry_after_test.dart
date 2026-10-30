import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/transport/retry_after.dart';

final DateTime _now = DateTime.utc(2026, 6, 1, 12);

void main() {
  test('seconds', () {
    expect(parseRetryAfter('7', _now), const Duration(seconds: 7));
    expect(parseRetryAfter(' 30 ', _now), const Duration(seconds: 30));
  });

  test('seconds are clamped to 1 second .. 1 hour', () {
    expect(parseRetryAfter('0', _now), minRetryAfter);
    expect(parseRetryAfter('99999', _now), maxRetryAfter);
    expect(parseRetryAfter('3600', _now), const Duration(hours: 1));
  });

  test('negative numbers are not understood', () {
    expect(parseRetryAfter('-5', _now), isNull);
  });

  test('an HTTP date in the future', () {
    expect(
      parseRetryAfter('Mon, 01 Jun 2026 12:00:45 GMT', _now),
      const Duration(seconds: 45),
    );
  });

  test('an HTTP date in the past gives the minimum', () {
    expect(
      parseRetryAfter('Mon, 01 Jun 2026 11:00:00 GMT', _now),
      minRetryAfter,
    );
  });

  test('an HTTP date far away is clamped', () {
    expect(
      parseRetryAfter('Mon, 01 Jun 2027 12:00:00 GMT', _now),
      maxRetryAfter,
    );
  });

  test('month names are case-insensitive and every month works', () {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    for (final month in months) {
      expect(
        parseRetryAfter(
          'Mon, 01 ${month.toUpperCase()} 2026 12:00:00 GMT',
          _now,
        ),
        isNotNull,
        reason: month,
      );
    }
  });

  test('garbage and missing values', () {
    for (final value in [
      null,
      '',
      '   ',
      'soon',
      '1.5',
      'Mon, 01 Foo 2026 12:00:00 GMT',
      'Mon, 01 Jun 2026 12:00:00 PST',
      '2026-06-01T12:00:45Z',
    ]) {
      expect(parseRetryAfter(value, _now), isNull, reason: '$value');
    }
  });
}
