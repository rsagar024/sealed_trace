import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/storage/envelope_store.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import 'package:sealed_trace/src/storage/retention_policy.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';
import 'package:sealed_trace/src/storage/storage_sequence_store.dart';

import '../helpers/envelopes.dart';

final DateTime _now = DateTime.utc(2026, 6, 1, 12);

const RetentionPolicy _policy = RetentionPolicy(
  maxEvents: 10000,
  maxAgeDays: 30,
  maxSizeBytes: 50 * 1024 * 1024,
  deadLetterTtl: Duration(days: 7),
);

/// Fails inserts with [StorageFullException] a set number of times.
class _FullAdapter extends MemoryStorageAdapter {
  _FullAdapter(this.failures);
  int failures;
  int insertCalls = 0;

  @override
  Future<void> insertEnvelope(EnvelopeRow row) async {
    insertCalls++;
    if (failures > 0) {
      failures--;
      throw const StorageFullException('quota');
    }
    await super.insertEnvelope(row);
  }
}

EnvelopeStore _store(
  StorageAdapter adapter, {
  RetentionPolicy policy = _policy,
  void Function(int)? onPurged,
  void Function(int)? onDeadLettered,
}) => EnvelopeStore(
  adapter: adapter,
  policy: policy,
  onPurged: onPurged,
  onDeadLettered: onDeadLettered,
);

Future<void> _add(
  EnvelopeStore store,
  String id, {
  required int minutesAgo,
  int bytes = 64,
  int events = 1,
}) => store.append(
  makeEnvelope(
    id: id,
    createdAt: _now.subtract(Duration(minutes: minutesAgo)),
    ciphertextLength: bytes,
    eventCount: events,
  ),
);

void main() {
  late MemoryStorageAdapter adapter;
  late EnvelopeStore store;

  setUp(() {
    adapter = MemoryStorageAdapter();
    store = _store(adapter);
  });

  group('append', () {
    test('stores a pending row', () async {
      await _add(store, 'a', minutesAgo: 1);
      final row = (await adapter.fetch(['a'])).single;
      expect(row.uploadState, uploadStatePending);
      expect(row.attempts, 0);
    });

    test('a full store is purged once and the write retried', () async {
      final full = _FullAdapter(1);
      var purged = 0;
      final s = _store(full, onPurged: (n) => purged += n);
      // Five older rows already stored (the failure count starts after them).
      full.failures = 0;
      for (var i = 0; i < 5; i++) {
        await _add(s, 'old$i', minutesAgo: 100 - i);
      }
      full.failures = 1;

      await _add(s, 'new', minutesAgo: 0);

      // 20% of 5 rows is 1: the oldest is removed to make room.
      expect(purged, 1);
      final ids = (await full.listIndex()).map((r) => r.batchId).toList();
      expect(ids, isNot(contains('old0')));
      expect(ids, contains('new'));
      expect(ids, hasLength(5));
    });

    test('a second failure is thrown to the caller', () async {
      final full = _FullAdapter(2);
      final s = _store(full);
      await expectLater(
        _add(s, 'x', minutesAgo: 0),
        throwsA(isA<StorageFullException>()),
      );
      expect(full.insertCalls, 2, reason: 'one retry only');
    });

    test('other errors are not retried', () async {
      final broken = _BrokenAdapter();
      final s = _store(broken);
      await expectLater(_add(s, 'x', minutesAgo: 0), throwsStateError);
      expect(broken.insertCalls, 1);
    });

    test('an emergency purge on an empty store just retries', () async {
      final full = _FullAdapter(1);
      final s = _store(full);
      await _add(s, 'only', minutesAgo: 0);
      expect(await full.listIndex(), hasLength(1));
    });
  });

  group('nextPending', () {
    test('returns the oldest rows first, up to the limit', () async {
      await _add(store, 'c', minutesAgo: 1);
      await _add(store, 'a', minutesAgo: 30);
      await _add(store, 'b', minutesAgo: 20);
      final rows = await store.nextPending(limit: 2, maxBytes: 1 << 30);
      expect(rows.map((r) => r.envelope.batchId), ['a', 'b']);
    });

    test(
      'stays within the byte budget but always returns the first row',
      () async {
        await _add(store, 'a', minutesAgo: 30, bytes: 1000);
        await _add(store, 'b', minutesAgo: 20, bytes: 1000);
        await _add(store, 'c', minutesAgo: 10, bytes: 1000);
        final stored = (await adapter.listIndex()).first.sizeBytes;

        final two = await store.nextPending(limit: 10, maxBytes: stored * 2);
        expect(two.map((r) => r.envelope.batchId), ['a', 'b']);

        final oversized = await store.nextPending(limit: 10, maxBytes: 10);
        expect(oversized.map((r) => r.envelope.batchId), ['a']);
      },
    );

    test('skips dead letters, acknowledged rows and excluded ids', () async {
      await _add(store, 'dead', minutesAgo: 40);
      await _add(store, 'acked', minutesAgo: 30);
      await _add(store, 'busy', minutesAgo: 20);
      await _add(store, 'ok', minutesAgo: 10);
      await adapter.patch(['dead'], uploadState: uploadStateDeadLetter);
      await adapter.patch(['acked'], uploadedAt: 1);

      final rows = await store.nextPending(
        limit: 10,
        maxBytes: 1 << 30,
        exclude: {'busy'},
      );
      expect(rows.map((r) => r.envelope.batchId), ['ok']);
    });

    test('nothing pending gives an empty list', () async {
      expect(await store.nextPending(limit: 5, maxBytes: 100), isEmpty);
    });
  });

  group('recordFailure and dead letters', () {
    test('counts attempts and dead-letters at maxAttempts', () async {
      var buried = 0;
      final s = _store(adapter, onDeadLettered: (n) => buried += n);
      await _add(s, 'a', minutesAgo: 5);

      for (var attempt = 1; attempt <= 4; attempt++) {
        final dead = await s.recordFailure(['a'], _now, maxAttempts: 5);
        expect(dead, 0, reason: 'attempt $attempt');
      }
      var row = (await adapter.listIndex()).single;
      expect(row.attempts, 4);
      expect(row.uploadState, uploadStatePending);
      expect(row.lastAttemptAt, _now.millisecondsSinceEpoch);

      final dead = await s.recordFailure(['a'], _now, maxAttempts: 5);
      expect(dead, 1);
      expect(buried, 1);
      row = (await adapter.listIndex()).single;
      expect(row.attempts, 5);
      expect(row.uploadState, uploadStateDeadLetter);
    });

    test('mixed batches are handled per row', () async {
      await _add(store, 'fresh', minutesAgo: 5);
      await _add(store, 'tired', minutesAgo: 4);
      await adapter.patch(['tired'], attemptsDelta: 4);

      final dead = await store.recordFailure(
        ['fresh', 'tired'],
        _now,
        maxAttempts: 5,
      );
      expect(dead, 1);
      final index = {for (final r in await adapter.listIndex()) r.batchId: r};
      expect(index['fresh']!.uploadState, uploadStatePending);
      expect(index['tired']!.uploadState, uploadStateDeadLetter);
    });

    test('unknown ids and empty input are harmless', () async {
      expect(await store.recordFailure(const [], _now, maxAttempts: 5), 0);
      expect(await store.recordFailure(['ghost'], _now, maxAttempts: 5), 0);
    });

    test('maxAttempts of 1 dead-letters on the first failure', () async {
      await _add(store, 'a', minutesAgo: 1);
      expect(await store.recordFailure(['a'], _now, maxAttempts: 1), 1);
    });

    test('deadLetters lists only dead-lettered rows, oldest first', () async {
      await _add(store, 'x', minutesAgo: 30);
      await _add(store, 'y', minutesAgo: 20);
      await _add(store, 'z', minutesAgo: 10);
      await adapter.patch(['z', 'x'], uploadState: uploadStateDeadLetter);
      expect((await store.deadLetters()).map((r) => r.batchId), ['x', 'z']);
    });
  });

  group('acknowledged rows', () {
    test('markUploadedAndDelete removes the rows', () async {
      await _add(store, 'a', minutesAgo: 3);
      await _add(store, 'b', minutesAgo: 2);
      await store.markUploadedAndDelete(['a'], _now);
      expect((await adapter.listIndex()).map((r) => r.batchId), ['b']);
      await store.markUploadedAndDelete(const [], _now);
    });

    test(
      'a crash between mark and delete is repaired on the next start',
      () async {
        await _add(store, 'a', minutesAgo: 3);
        await _add(store, 'b', minutesAgo: 2);
        // Simulate the crash: marked, never deleted.
        await adapter.patch(['a'], uploadedAt: _now.millisecondsSinceEpoch);

        expect(await store.deleteAcknowledged(), 1);
        expect((await adapter.listIndex()).map((r) => r.batchId), ['b']);
        expect(await store.deleteAcknowledged(), 0);
      },
    );
  });

  group('purge and stats', () {
    test('purge applies the policy and reports the count', () async {
      var purged = 0;
      final s = _store(adapter, onPurged: (n) => purged += n);
      await _add(s, 'old', minutesAgo: 60 * 24 * 40);
      await _add(s, 'new', minutesAgo: 5);
      expect(await s.purge(_now), 1);
      expect(purged, 1);
      expect((await adapter.listIndex()).map((r) => r.batchId), ['new']);
    });

    test('purge keeps protected rows', () async {
      await _add(store, 'old', minutesAgo: 60 * 24 * 40);
      expect(await store.purge(_now, protected: {'old'}), 0);
      expect(await adapter.listIndex(), hasLength(1));
    });

    test('purge with nothing to do does not call the callback', () async {
      var calls = 0;
      final s = _store(adapter, onPurged: (_) => calls++);
      await _add(s, 'fine', minutesAgo: 5);
      expect(await s.purge(_now), 0);
      expect(calls, 0);
    });

    test('purge decides from index columns only', () async {
      final spy = _IndexOnlyAdapter();
      final s = _store(spy);
      await _add(s, 'old', minutesAgo: 60 * 24 * 40);
      await _add(s, 'new', minutesAgo: 5);
      await s.purge(_now);
      expect(spy.fetchCalls, 0, reason: 'purge must not load ciphertext');
    });

    test('stats totals come from the index', () async {
      await _add(store, 'a', minutesAgo: 3, events: 2, bytes: 10);
      await _add(store, 'b', minutesAgo: 2, events: 5, bytes: 20);
      await adapter.patch(['b'], uploadState: uploadStateDeadLetter);
      final stats = await store.stats();
      expect(stats.envelopes, 2);
      expect(stats.events, 7);
      expect(stats.deadLetters, 1);
      expect(stats.bytes, greaterThan(0));
    });

    test('clear removes every envelope', () async {
      await _add(store, 'a', minutesAgo: 3);
      await store.clear();
      expect(await adapter.listIndex(), isEmpty);
    });
  });

  group('StorageSequenceStore', () {
    test('starts at zero and persists the high-water mark', () async {
      final seq = StorageSequenceStore(adapter);
      expect(await seq.readHighWater(), 0);
      await seq.writeHighWater(200);
      expect(await StorageSequenceStore(adapter).readHighWater(), 200);
    });

    test('garbage in the meta table reads as zero', () async {
      await adapter.writeMeta(StorageSequenceStore.key, 'not a number');
      expect(await StorageSequenceStore(adapter).readHighWater(), 0);
    });
  });

  test('SealedEnvelope.storedBytes sums the four binary fields', () {
    final e = makeEnvelope(ciphertextLength: 100);
    expect(e.storedBytes, 256 + 12 + 16 + 100);
  });
}

class _BrokenAdapter extends MemoryStorageAdapter {
  int insertCalls = 0;

  @override
  Future<void> insertEnvelope(EnvelopeRow row) async {
    insertCalls++;
    throw StateError('disk on fire');
  }
}

class _IndexOnlyAdapter extends MemoryStorageAdapter {
  int fetchCalls = 0;

  @override
  Future<List<EnvelopeRow>> fetch(Iterable<String> batchIds) {
    fetchCalls++;
    return super.fetch(batchIds);
  }
}
