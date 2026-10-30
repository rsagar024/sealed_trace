import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/diagnostics/diagnostic_counters.dart';
import 'package:sealed_trace/src/storage/envelope_store.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import 'package:sealed_trace/src/storage/retention_policy.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';
import 'package:sealed_trace/src/storage/storage_service.dart';

import '../helpers/envelopes.dart';
import '../helpers/fakes.dart';

const RetentionPolicy _policy = RetentionPolicy(
  maxEvents: 10000,
  maxAgeDays: 30,
  maxSizeBytes: 50 * 1024 * 1024,
  deadLetterTtl: Duration(days: 7),
);

class _SpyAdapter extends MemoryStorageAdapter {
  int closeCalls = 0;
  bool failList = false;
  bool failInsert = false;

  @override
  Future<void> close() async {
    closeCalls++;
  }

  @override
  Future<List<EnvelopeIndexRow>> listIndex() {
    if (failList) return Future.error(StateError('list failed'));
    return super.listIndex();
  }

  @override
  Future<void> insertEnvelope(EnvelopeRow row) {
    if (failInsert) return Future.error(StateError('insert failed'));
    return super.insertEnvelope(row);
  }
}

class _Rig {
  _Rig({Duration interval = const Duration(hours: 1)}) {
    final clock = FakeClock(DateTime.utc(2026, 6, 1, 12));
    this.clock = clock;
    store = EnvelopeStore(
      adapter: adapter,
      policy: _policy,
      onPurged: (n) => counters.purgedRows += n,
    );
    service = StorageService(
      store: store,
      purgeInterval: interval,
      clock: clock,
      counters: counters,
      onError: (e, _) => errors.add(e),
    );
  }

  final adapter = _SpyAdapter();
  final counters = DiagnosticCounters();
  final errors = <Object>[];
  late final FakeClock clock;
  late final EnvelopeStore store;
  late final StorageService service;

  Future<void> addOld(String id) => store.append(
    makeEnvelope(
      id: id,
      createdAt: clock.value.subtract(const Duration(days: 40)),
    ),
  );
}

void main() {
  test('start purges once immediately', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.addOld('old');
      async.flushMicrotasks();

      rig.service.start();
      async.flushMicrotasks();

      expect(rig.counters.purgedRows, 1);
      rig.adapter.listIndex().then((rows) => expect(rows, isEmpty));
      async.flushMicrotasks();
    });
  });

  test('the timer purges again every interval', () {
    fakeAsync((async) {
      final rig = _Rig(interval: const Duration(minutes: 10));
      rig.service.start();
      async.flushMicrotasks();
      expect(rig.counters.purgedRows, 0);

      rig.addOld('late-old');
      async.flushMicrotasks();
      async.elapse(const Duration(minutes: 9));
      expect(rig.counters.purgedRows, 0, reason: 'interval not reached');

      async.elapse(const Duration(minutes: 2));
      expect(rig.counters.purgedRows, 1);
    });
  });

  test('dispose stops the timer and closes the adapter', () {
    fakeAsync((async) {
      final rig = _Rig(interval: const Duration(minutes: 10));
      rig.service.start();
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 1);

      rig.service.dispose();
      async.flushMicrotasks();
      expect(async.periodicTimerCount, 0);
      expect(rig.adapter.closeCalls, 1);

      rig.addOld('after');
      async.flushMicrotasks();
      async.elapse(const Duration(hours: 5));
      expect(rig.counters.purgedRows, 0, reason: 'no purge after dispose');
    });
  });

  test('a failing purge is counted and reported, never thrown', () async {
    final rig = _Rig();
    rig.adapter.failList = true;
    expect(await rig.service.purge(), 0);
    expect(rig.counters.storageFailures, 1);
    expect(rig.errors, hasLength(1));
  });

  test('start survives a failing first purge and still schedules', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.adapter.failList = true;
      rig.service.start();
      async.flushMicrotasks();
      expect(rig.errors, hasLength(1));
      expect(async.periodicTimerCount, 1);
    });
  });

  test('save stores the envelope', () async {
    final rig = _Rig();
    await rig.service.save(makeEnvelope(id: 'saved'));
    expect((await rig.adapter.listIndex()).single.batchId, 'saved');
  });

  test('a failing save counts the failure and rethrows', () async {
    final rig = _Rig();
    rig.adapter.failInsert = true;
    await expectLater(rig.service.save(makeEnvelope()), throwsStateError);
    expect(rig.counters.storageFailures, 1);
  });

  test('clear empties the store', () async {
    final rig = _Rig();
    await rig.service.save(makeEnvelope(id: 'x'));
    await rig.service.clear();
    expect(await rig.adapter.listIndex(), isEmpty);
  });

  test('rows being uploaded are protected from retention', () async {
    final rig = _Rig();
    await rig.addOld('uploading');
    await rig.addOld('idle');
    rig.service.inFlight = () => {'uploading'};

    expect(await rig.service.purge(), 1);

    final left = (await rig.adapter.listIndex()).map((r) => r.batchId);
    expect(left, ['uploading']);
  });

  test('the stored hook is called after a successful save only', () async {
    final rig = _Rig();
    final seen = <String>[];
    rig.service.onStored = (e) => seen.add(e.batchId);
    await rig.service.save(makeEnvelope(id: 'one'));
    rig.adapter.failInsert = true;
    await expectLater(
      rig.service.save(makeEnvelope(id: 'two')),
      throwsStateError,
    );
    expect(seen, ['one']);
  });

  test('a throwing stored hook is reported, never thrown', () async {
    final rig = _Rig();
    rig.service.onStored = (_) => throw StateError('hook broke');
    await expectLater(rig.service.save(makeEnvelope(id: 'x')), completes);
    expect(rig.errors, hasLength(1));
    expect((await rig.adapter.listIndex()), hasLength(1));
  });
}
