import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart' show RetentionConfig;
import 'package:sealed_trace/src/storage/retention_policy.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';

final DateTime _now = DateTime.utc(2026, 6, 1, 12);

EnvelopeIndexRow _row(
  String id, {
  required Duration age,
  int events = 1,
  int bytes = 100,
  int state = uploadStatePending,
  Duration? lastAttemptAge,
}) {
  return EnvelopeIndexRow(
    batchId: id,
    createdAt: _now.subtract(age).millisecondsSinceEpoch,
    eventCount: events,
    sizeBytes: bytes,
    uploadState: state,
    attempts: 0,
    lastAttemptAt: lastAttemptAge == null
        ? null
        : _now.subtract(lastAttemptAge).millisecondsSinceEpoch,
    uploadedAt: null,
  );
}

const RetentionPolicy _policy = RetentionPolicy(
  maxEvents: 1000,
  maxAgeDays: 30,
  maxSizeBytes: 10000,
  deadLetterTtl: Duration(days: 7),
);

List<String> _plan(
  List<EnvelopeIndexRow> rows, {
  RetentionPolicy policy = _policy,
  Set<String> protected = const {},
  DateTime? now,
}) => RetentionPlanner.plan(rows, policy, now ?? _now, protected: protected);

void main() {
  test('nothing is removed when every limit holds', () {
    expect(_plan([_row('a', age: const Duration(days: 1))]), isEmpty);
    expect(_plan(const []), isEmpty);
  });

  group('age', () {
    test('rows past maxAgeDays are removed, newer ones kept', () {
      final rows = [
        _row('old', age: const Duration(days: 31)),
        _row('edge-in', age: const Duration(days: 29, hours: 23)),
        _row('new', age: const Duration(days: 1)),
      ];
      expect(_plan(rows), ['old']);
    });

    test('exactly maxAgeDays old is kept (strictly older is removed)', () {
      expect(_plan([_row('x', age: const Duration(days: 30))]), isEmpty);
      expect(
        _plan([_row('y', age: const Duration(days: 30, milliseconds: 1))]),
        ['y'],
      );
    });
  });

  group('event count', () {
    test('the oldest rows go first until the total fits', () {
      const policy = RetentionPolicy(
        maxEvents: 10,
        maxAgeDays: 30,
        maxSizeBytes: 1 << 30,
        deadLetterTtl: Duration(days: 7),
      );
      final rows = [
        _row('oldest', age: const Duration(hours: 5), events: 4),
        _row('middle', age: const Duration(hours: 4), events: 4),
        _row('newest', age: const Duration(hours: 3), events: 4),
      ];
      // 12 events, limit 10: removing the oldest (4) leaves 8.
      expect(_plan(rows, policy: policy), ['oldest']);
    });

    test('exactly at the limit keeps everything', () {
      const policy = RetentionPolicy(
        maxEvents: 8,
        maxAgeDays: 30,
        maxSizeBytes: 1 << 30,
        deadLetterTtl: Duration(days: 7),
      );
      final rows = [
        _row('a', age: const Duration(hours: 2), events: 4),
        _row('b', age: const Duration(hours: 1), events: 4),
      ];
      expect(_plan(rows, policy: policy), isEmpty);
    });
  });

  group('size', () {
    const policy = RetentionPolicy(
      maxEvents: 1 << 30,
      maxAgeDays: 30,
      maxSizeBytes: 250,
      deadLetterTtl: Duration(days: 7),
    );

    test('the oldest rows go first until the bytes fit', () {
      final rows = [
        _row('a', age: const Duration(hours: 3), bytes: 100),
        _row('b', age: const Duration(hours: 2), bytes: 100),
        _row('c', age: const Duration(hours: 1), bytes: 100),
      ];
      expect(_plan(rows, policy: policy), ['a']);
    });

    test('a single oversized row is removed even if it is the newest', () {
      final rows = [_row('huge', age: const Duration(hours: 1), bytes: 999)];
      expect(_plan(rows, policy: policy), ['huge']);
    });

    test('equal timestamps are removed in batch id order', () {
      final rows = [
        _row('z', age: const Duration(hours: 1), bytes: 100),
        _row('a', age: const Duration(hours: 1), bytes: 100),
        _row('m', age: const Duration(hours: 1), bytes: 100),
      ];
      expect(_plan(rows, policy: policy), ['a']);
    });
  });

  group('dead letters', () {
    test('expire after the TTL, measured from the last attempt', () {
      final rows = [
        _row(
          'dl-old',
          age: const Duration(days: 20),
          state: uploadStateDeadLetter,
          lastAttemptAge: const Duration(days: 8),
        ),
        _row(
          'dl-recent',
          age: const Duration(days: 20),
          state: uploadStateDeadLetter,
          lastAttemptAge: const Duration(days: 6),
        ),
        _row('pending-same-age', age: const Duration(days: 20)),
      ];
      expect(_plan(rows), ['dl-old']);
    });

    test('without a last attempt the creation time is used', () {
      final rows = [
        _row('dl', age: const Duration(days: 8), state: uploadStateDeadLetter),
      ];
      expect(_plan(rows), ['dl']);
    });
  });

  group('combined limits and protection', () {
    test('age first, then count and size on what remains', () {
      const policy = RetentionPolicy(
        maxEvents: 5,
        maxAgeDays: 30,
        maxSizeBytes: 1 << 30,
        deadLetterTtl: Duration(days: 7),
      );
      final rows = [
        _row('expired', age: const Duration(days: 40), events: 3),
        _row('a', age: const Duration(hours: 5), events: 3),
        _row('b', age: const Duration(hours: 4), events: 3),
      ];
      // expired goes by age; a+b is 6 events > 5 so a goes too.
      expect(_plan(rows, policy: policy), ['expired', 'a']);
    });

    test('protected rows are never chosen but still count', () {
      const policy = RetentionPolicy(
        maxEvents: 5,
        maxAgeDays: 30,
        maxSizeBytes: 1 << 30,
        deadLetterTtl: Duration(days: 7),
      );
      final rows = [
        _row('inflight', age: const Duration(hours: 5), events: 4),
        _row('b', age: const Duration(hours: 4), events: 4),
        _row('c', age: const Duration(hours: 3), events: 4),
      ];
      // inflight is oldest but protected, so b is removed instead; still over
      // the limit (8 > 5) so c goes too, and inflight survives.
      final plan = _plan(rows, policy: policy, protected: {'inflight'});
      expect(plan, ['b', 'c']);
    });

    test('a protected expired row is kept', () {
      final rows = [_row('p', age: const Duration(days: 90))];
      expect(_plan(rows, protected: {'p'}), isEmpty);
    });

    test('the result never repeats an id', () {
      final rows = [
        _row(
          'x',
          age: const Duration(days: 90),
          state: uploadStateDeadLetter,
          lastAttemptAge: const Duration(days: 30),
        ),
      ];
      expect(_plan(rows), ['x']);
    });
  });

  group('clock problems', () {
    test('a clock that moved backwards removes nothing by age', () {
      final rows = [_row('a', age: const Duration(days: 5))];
      expect(
        _plan(rows, now: _now.subtract(const Duration(days: 400))),
        isEmpty,
      );
    });

    test('rows dated in the future survive the age check', () {
      final rows = [
        EnvelopeIndexRow(
          batchId: 'future',
          createdAt: _now.add(const Duration(days: 365)).millisecondsSinceEpoch,
          eventCount: 1,
          sizeBytes: 100,
          uploadState: uploadStatePending,
          attempts: 0,
          lastAttemptAt: null,
          uploadedAt: null,
        ),
      ];
      expect(_plan(rows), isEmpty);
    });

    test('count and size limits still apply to future-dated rows', () {
      const policy = RetentionPolicy(
        maxEvents: 3,
        maxAgeDays: 30,
        maxSizeBytes: 1 << 30,
        deadLetterTtl: Duration(days: 7),
      );
      final rows = [
        for (var i = 0; i < 5; i++)
          EnvelopeIndexRow(
            batchId: 'f$i',
            createdAt: _now.add(Duration(days: 300 + i)).millisecondsSinceEpoch,
            eventCount: 1,
            sizeBytes: 10,
            uploadState: uploadStatePending,
            attempts: 0,
            lastAttemptAt: null,
            uploadedAt: null,
          ),
      ];
      expect(_plan(rows, policy: policy), ['f0', 'f1']);
    });
  });

  test('RetentionPolicy.fromConfig mirrors the spec defaults', () {
    final policy = RetentionPolicy.fromConfig(const RetentionConfig());
    expect(policy.maxEvents, 10000);
    expect(policy.maxAgeDays, 30);
    expect(policy.maxSizeBytes, 50 * 1024 * 1024);
    expect(policy.deadLetterTtl, const Duration(days: 7));
  });
}
