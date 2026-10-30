import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/queue/write_behind_queue.dart';

import '../helpers/fakes.dart';

WriteBehindQueue _queue(
  RecordingSink sink, {
  List<Object>? errors,
  void Function()? onDropped,
  int maxQueued = 5000,
}) {
  return WriteBehindQueue(
    sink: sink.call,
    onError: (e, _) => errors?.add(e),
    onDropped: onDropped,
    maxQueued: maxQueued,
  );
}

void main() {
  test('flushes after 2 seconds', () {
    fakeAsync((async) {
      final sink = RecordingSink();
      final q = _queue(sink);
      q.add(makeRecord());

      async.elapse(const Duration(milliseconds: 1999));
      expect(sink.batches, isEmpty);

      async.elapse(const Duration(milliseconds: 2));
      expect(sink.batches, hasLength(1));
      expect(q.length, 0);
    });
  });

  test('flushes when 25 events are buffered', () {
    fakeAsync((async) {
      final sink = RecordingSink();
      final q = _queue(sink);
      for (var i = 0; i < 24; i++) {
        q.add(makeRecord());
      }
      async.flushMicrotasks();
      expect(sink.batches, isEmpty);

      q.add(makeRecord());
      async.flushMicrotasks();
      expect(sink.batches, hasLength(1));
      expect(sink.batches.single, hasLength(25));
    });
  });

  test('flushes when 64 KB is buffered', () {
    fakeAsync((async) {
      final sink = RecordingSink();
      final q = _queue(sink);
      q.add(makeRecord(message: 'x' * 40000));
      async.flushMicrotasks();
      expect(sink.batches, isEmpty);

      q.add(makeRecord(message: 'x' * 40000));
      async.flushMicrotasks();
      expect(sink.records, hasLength(2));
      // The two records do not fit one 64 KB batch, so they are split.
      expect(sink.batches, hasLength(2));
    });
  });

  test('a single record larger than 64 KB goes out alone', () {
    fakeAsync((async) {
      final sink = RecordingSink();
      final q = _queue(sink);
      q.add(makeRecord(message: 'x' * 100000));
      async.flushMicrotasks();
      expect(sink.batches.single, hasLength(1));
    });
  });

  test('immediate flushes at once', () {
    fakeAsync((async) {
      final sink = RecordingSink();
      final q = _queue(sink);
      q.add(makeRecord(), immediate: true);
      async.flushMicrotasks();
      expect(sink.batches, hasLength(1));
    });
  });

  test('order is preserved across batches', () {
    fakeAsync((async) {
      final sink = RecordingSink();
      final q = _queue(sink);
      for (var i = 1; i <= 60; i++) {
        q.add(makeRecord(seq: i));
      }
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(sink.records.map((r) => r.seq), List.generate(60, (i) => i + 1));
      expect(sink.batches.every((b) => b.length <= 25), isTrue);
    });
  });

  test('an empty queue arms no timer', () {
    fakeAsync((async) {
      final sink = RecordingSink();
      final q = _queue(sink);
      expect(q.hasPendingTimer, isFalse);
      q.add(makeRecord());
      expect(q.hasPendingTimer, isTrue);
      unawaited(q.flush());
      async.flushMicrotasks();
      expect(q.hasPendingTimer, isFalse);
      expect(async.nonPeriodicTimerCount, 0);
    });
  });

  test('records added during a flush go to the next batch in order', () {
    fakeAsync((async) {
      final gate = Completer<void>();
      final batches = <List<int>>[];
      final q = WriteBehindQueue(
        sink: (batch) async {
          batches.add(batch.map((r) => r.seq).toList());
          if (batches.length == 1) await gate.future;
        },
        onError: (_, _) {},
      );

      q.add(makeRecord(seq: 1), immediate: true);
      async.flushMicrotasks();
      expect(batches, [
        [1],
      ]);

      q.add(makeRecord(seq: 2));
      q.add(makeRecord(seq: 3));
      gate.complete();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));

      expect(batches, [
        [1],
        [2, 3],
      ]);
    });
  });

  test('overflow drops the oldest and reports each drop', () {
    fakeAsync((async) {
      final sink = RecordingSink();
      var dropped = 0;
      final q = WriteBehindQueue(
        sink: sink.call,
        onError: (_, _) {},
        onDropped: () => dropped++,
        maxBatchEvents: 1000,
        maxQueued: 5,
      );
      for (var i = 1; i <= 8; i++) {
        q.add(makeRecord(seq: i));
      }
      expect(dropped, 3);
      expect(q.length, 5);

      async.elapse(const Duration(seconds: 3));
      expect(sink.records.map((r) => r.seq), [4, 5, 6, 7, 8]);
    });
  });

  test('a throwing sink is reported and later batches still go out', () {
    fakeAsync((async) {
      final errors = <Object>[];
      final seen = <int>[];
      var calls = 0;
      final q = WriteBehindQueue(
        sink: (batch) async {
          calls++;
          if (calls == 1) throw StateError('disk full');
          seen.addAll(batch.map((r) => r.seq));
        },
        onError: (e, _) => errors.add(e),
      );

      q.add(makeRecord(seq: 1), immediate: true);
      async.flushMicrotasks();
      q.add(makeRecord(seq: 2), immediate: true);
      async.flushMicrotasks();

      expect(errors, hasLength(1));
      expect(seen, [2]);
    });
  });

  test('flush completes without error even when the sink throws', () async {
    final q = WriteBehindQueue(
      sink: (_) async => throw StateError('x'),
      onError: (_, _) {},
    );
    q.add(makeRecord());
    await expectLater(q.flush(), completes);
  });

  test('dispose drains and then ignores new records', () {
    fakeAsync((async) {
      final sink = RecordingSink();
      final q = _queue(sink);
      q.add(makeRecord(seq: 1));
      q.add(makeRecord(seq: 2));
      unawaited(q.dispose());
      async.flushMicrotasks();
      expect(sink.records.map((r) => r.seq), [1, 2]);

      q.add(makeRecord(seq: 3));
      async.elapse(const Duration(seconds: 5));
      expect(sink.records, hasLength(2));
      expect(q.hasPendingTimer, isFalse);
    });
  });
}
