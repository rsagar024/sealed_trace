@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/platform/lifecycle_binding.dart';
import 'package:sealed_trace/src/storage/envelope_spill.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import 'package:sealed_trace/src/storage/open_storage_io.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/envelopes.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _config = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj-1',
  apiKey: 'key',
  publicKeyPem: testPublicKeySpki,
  appName: 'app',
);

class _SpyAdapter extends MemoryStorageAdapter {
  int closeCalls = 0;
  bool failInsert = false;

  @override
  Future<void> close() async {
    closeCalls++;
  }

  @override
  Future<void> insertEnvelope(EnvelopeRow row) {
    if (failInsert) return Future.error(StateError('insert failed'));
    return super.insertEnvelope(row);
  }
}

late Directory _tempRoot;
final DateTime _fixedNow = DateTime.utc(2026, 6, 1, 12);

void _install({StorageAdapter? storage, RuntimeOverrides? custom}) {
  SealedTrace.debugOverrides =
      custom ??
      RuntimeOverrides(
        disableUploads: true,
        storage: storage,
        lifecycle: FakeLifecycle(),
        deviceContext: testDevice,
        clock: FakeClock(_fixedNow),
      );
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    _tempRoot = await Directory.systemTemp.createTemp('sealed_trace_facade_');
  });

  tearDownAll(() async {
    try {
      await _tempRoot.delete(recursive: true);
    } catch (_) {
      // A database isolate may still hold a file on Windows.
    }
  });

  setUp(() async {
    await SealedTrace.dispose();
    SealedTrace.onException = null;
  });

  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.debugOverrides = null;
    SealedTrace.onException = null;
  });

  group('flushed events are stored as ciphertext rows', () {
    test(
      'with correct index columns, decryptable with the private key',
      () async {
        final adapter = MemoryStorageAdapter();
        _install(storage: adapter);
        await SealedTrace.init(_config);

        SealedTrace.i('auth', 'login for asha@example.com');
        SealedTrace.e('auth', 'boom');
        await SealedTrace.flush();

        final index = await adapter.listIndex();
        expect(index, hasLength(1));
        expect(index.single.eventCount, 2);
        expect(index.single.uploadState, uploadStatePending);

        final row = (await adapter.fetch([index.single.batchId])).single;
        expect(row.envelope.projectId, 'proj-1');
        expect(row.envelope.seqMin, 1);
        expect(row.envelope.seqMax, 2);
        expect(row.envelope.topLevels, 'info,error');
        final events = jsonDecode(await openEnvelope(row.envelope)) as List;
        expect((events.first as Map)['message'], 'login for ***');
      },
    );

    test('several batches become several rows', () async {
      final adapter = MemoryStorageAdapter();
      _install(storage: adapter);
      await SealedTrace.init(_config);
      SealedTrace.i('t', 'one');
      await SealedTrace.flush();
      SealedTrace.i('t', 'two');
      await SealedTrace.flush();
      expect(await adapter.listIndex(), hasLength(2));
    });
  });

  group('page-exit spill (web path, with an injected spill)', () {
    RuntimeOverrides overrides(
      StorageAdapter storage,
      EnvelopeSpill spill,
      FakeLifecycle lifecycle,
    ) => RuntimeOverrides(
      disableUploads: true,
      storage: storage,
      lifecycle: lifecycle,
      deviceContext: testDevice,
      clock: FakeClock(_fixedNow),
      envelopeSpill: spill,
    );

    test('init moves envelopes left in the spill into storage', () async {
      final adapter = MemoryStorageAdapter();
      final spill = MemoryEnvelopeSpill()
        ..write(makeEnvelope(id: 'left-behind', eventCount: 2));
      _install(custom: overrides(adapter, spill, FakeLifecycle()));
      await SealedTrace.init(_config);

      final index = await adapter.listIndex();
      expect(index.map((r) => r.batchId), ['left-behind']);
      expect(spill.readAll(), isEmpty);
    });

    test(
      'leaving the page spills the queue, which then reaches storage',
      () async {
        final adapter = MemoryStorageAdapter();
        final spill = MemoryEnvelopeSpill();
        final lifecycle = FakeLifecycle();
        _install(custom: overrides(adapter, spill, lifecycle));
        await SealedTrace.init(_config);

        SealedTrace.i('t', 'about to leave');
        lifecycle.emit(AppLifecycle.detached);
        expect(spill.readAll(), hasLength(1));

        await _waitFor(() => spill.readAll().isEmpty);
        final index = await adapter.listIndex();
        expect(index.single.eventCount, 1);
        final row = (await adapter.fetch([index.single.batchId])).single;
        final events = jsonDecode(await openEnvelope(row.envelope)) as List;
        expect((events.single as Map)['message'], 'about to leave');
      },
    );

    test('clearLocalLogs also empties the spill', () async {
      final adapter = MemoryStorageAdapter();
      final spill = MemoryEnvelopeSpill();
      _install(custom: overrides(adapter, spill, FakeLifecycle()));
      await SealedTrace.init(_config);
      spill.write(makeEnvelope(id: 'stale'));

      await SealedTrace.clearLocalLogs();
      expect(spill.readAll(), isEmpty);
      expect(await adapter.listIndex(), isEmpty);
    });
  });

  group('sequence numbers survive restarts', () {
    test('a second run continues after the first run\'s reservation', () async {
      final adapter = MemoryStorageAdapter();

      _install(storage: adapter);
      await SealedTrace.init(_config);
      for (var i = 0; i < 3; i++) {
        SealedTrace.i('t', 'run one $i');
      }
      await SealedTrace.flush();
      await SealedTrace.dispose();

      _install(storage: adapter);
      await SealedTrace.init(_config);
      SealedTrace.i('t', 'run two');
      await SealedTrace.flush();

      final rows = await adapter.listIndex();
      final seqs = [
        for (final r in await adapter.fetch(rows.map((r) => r.batchId)))
          r.envelope.seqMin,
      ];
      // Both rows share the fake clock's timestamp, so their order is not
      // meaningful; compare as a sorted list. Run one reserved 1..100 and run
      // two starts after that reservation.
      expect(seqs..sort(), [1, 101]);
    });
  });

  group('clearLocalLogs', () {
    test(
      'discards queued events and stored rows but keeps seq moving',
      () async {
        final adapter = MemoryStorageAdapter();
        _install(storage: adapter);
        await SealedTrace.init(_config);

        SealedTrace.i('t', 'stored 1');
        SealedTrace.i('t', 'stored 2');
        await SealedTrace.flush();
        SealedTrace.i('t', 'still queued');
        expect(await adapter.listIndex(), hasLength(1));

        await SealedTrace.clearLocalLogs();
        expect(await adapter.listIndex(), isEmpty);

        await SealedTrace.flush();
        expect(
          await adapter.listIndex(),
          isEmpty,
          reason: 'the queued event must be gone too',
        );

        SealedTrace.i('t', 'after logout');
        await SealedTrace.flush();
        final row = (await adapter.fetch(
          (await adapter.listIndex()).map((r) => r.batchId),
        )).single;
        expect(row.envelope.seqMin, 4, reason: 'seq is never reused');
      },
    );

    test('is safe before init and when disabled', () async {
      await SealedTrace.clearLocalLogs();
      _install(storage: MemoryStorageAdapter());
      await SealedTrace.init(_config.copyWith(enabled: false));
      await SealedTrace.clearLocalLogs();
    });
  });

  group('retention', () {
    test('init removes rows older than maxAgeDays', () async {
      final adapter = MemoryStorageAdapter();
      await adapter.insertEnvelope(
        EnvelopeRow.pending(
          makeEnvelope(
            id: 'ancient',
            createdAt: _fixedNow.subtract(const Duration(days: 40)),
          ),
        ),
      );
      await adapter.insertEnvelope(
        EnvelopeRow.pending(
          makeEnvelope(
            id: 'recent',
            createdAt: _fixedNow.subtract(const Duration(days: 2)),
          ),
        ),
      );
      _install(storage: adapter);

      await SealedTrace.init(_config);

      expect((await adapter.listIndex()).map((r) => r.batchId), ['recent']);
      expect(SealedTrace.diagnostics.purgedRows, 1);
    });

    test('init enforces the event-count limit', () async {
      final adapter = MemoryStorageAdapter();
      for (var i = 0; i < 4; i++) {
        await adapter.insertEnvelope(
          EnvelopeRow.pending(
            makeEnvelope(
              id: 'r$i',
              eventCount: 10,
              createdAt: _fixedNow.subtract(Duration(hours: 10 - i)),
            ),
          ),
        );
      }
      _install(storage: adapter);
      await SealedTrace.init(
        _config.copyWith(retentionConfig: const RetentionConfig(maxEvents: 25)),
      );
      expect((await adapter.listIndex()).map((r) => r.batchId), ['r2', 'r3']);
    });

    test('the periodic timer purges rows that expire later', () async {
      final adapter = MemoryStorageAdapter();
      _install(storage: adapter);
      await SealedTrace.init(
        _config.copyWith(
          retentionConfig: const RetentionConfig(
            purgeInterval: Duration(milliseconds: 40),
          ),
        ),
      );
      expect(SealedTrace.diagnostics.purgedRows, 0);

      await adapter.insertEnvelope(
        EnvelopeRow.pending(
          makeEnvelope(
            id: 'expired-later',
            createdAt: _fixedNow.subtract(const Duration(days: 60)),
          ),
        ),
      );
      await _waitFor(() => SealedTrace.diagnostics.purgedRows >= 1);

      expect(SealedTrace.diagnostics.purgedRows, 1);
      expect(await adapter.listIndex(), isEmpty);
    });

    test('dispose stops the timer and closes the database', () async {
      final adapter = _SpyAdapter();
      _install(storage: adapter);
      await SealedTrace.init(
        _config.copyWith(
          retentionConfig: const RetentionConfig(
            purgeInterval: Duration(milliseconds: 30),
          ),
        ),
      );
      await SealedTrace.dispose();
      expect(adapter.closeCalls, 1);

      await adapter.insertEnvelope(
        EnvelopeRow.pending(
          makeEnvelope(
            id: 'left-alone',
            createdAt: _fixedNow.subtract(const Duration(days: 90)),
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(
        await adapter.listIndex(),
        hasLength(1),
        reason: 'no purge may run after dispose',
      );
    });
  });

  group('failures never reach the caller', () {
    test('a failing insert is counted and reported', () async {
      final errors = <Object>[];
      SealedTrace.onException = (e, _) => errors.add(e);
      final adapter = _SpyAdapter()..failInsert = true;
      _install(storage: adapter);
      await SealedTrace.init(_config);

      expect(() => SealedTrace.f('t', 'm'), returnsNormally);
      await SealedTrace.flush();

      expect(errors, isNotEmpty);
      expect(SealedTrace.diagnostics.storageFailures, 1);
    });
  });

  group('degraded modes', () {
    test(
      'no database directory falls back to memory and reports once',
      () async {
        final errors = <Object>[];
        SealedTrace.onException = (e, _) => errors.add(e);
        _install(
          custom: RuntimeOverrides(
            disableUploads: true,
            lifecycle: FakeLifecycle(),
            deviceContext: testDevice,
          ),
        );

        await SealedTrace.init(_config); // no databaseDirectory, no plugin

        expect(SealedTrace.isInitialized, isTrue);
        expect(errors, hasLength(1));
        expect(SealedTrace.diagnostics.storageFailures, 1);
        expect(() => SealedTrace.i('t', 'still works'), returnsNormally);
        await SealedTrace.flush();
      },
    );

    test('an unusable directory falls back to memory', () async {
      final blocker = File(p.join(_tempRoot.path, 'blocker'));
      await blocker.writeAsString('x');
      final errors = <Object>[];
      SealedTrace.onException = (e, _) => errors.add(e);
      _install(
        custom: RuntimeOverrides(
          disableUploads: true,
          lifecycle: FakeLifecycle(),
          deviceContext: testDevice,
        ),
      );

      await SealedTrace.init(
        _config.copyWith(databaseDirectory: p.join(blocker.path, 'sub')),
      );

      expect(SealedTrace.isInitialized, isTrue);
      expect(errors, hasLength(1));
    });
  });

  group('real SQLite file end to end', () {
    test('events survive a restart and seq continues', () async {
      final dir = await _tempRoot.createTemp('e2e');
      final config = _config.copyWith(databaseDirectory: dir.path);

      for (var run = 1; run <= 2; run++) {
        _install(
          custom: RuntimeOverrides(
            disableUploads: true,
            lifecycle: FakeLifecycle(),
            deviceContext: testDevice,
          ),
        );
        final errors = <Object>[];
        SealedTrace.onException = (e, _) => errors.add(e);
        await SealedTrace.init(config);
        SealedTrace.i('t', 'run $run secret asha@example.com');
        SealedTrace.i('t', 'run $run second');
        await SealedTrace.flush();
        await SealedTrace.dispose();
        expect(errors, isEmpty, reason: 'run $run');
      }

      final adapter = await openPlatformStorage(
        databaseDirectory: dir.path,
        onProblem: (e, _) => fail('unexpected problem: $e'),
      );
      final rows = await adapter.fetch(
        (await adapter.listIndex()).map((r) => r.batchId),
      );
      expect(rows, hasLength(2));
      expect(rows[0].envelope.seqMin, 1);
      expect(rows[1].envelope.seqMin, greaterThan(rows[0].envelope.seqMax));
      expect(rows[1].envelope.seqMin, 101);

      for (final row in rows) {
        final text = await openEnvelope(row.envelope);
        expect(text, isNot(contains('asha@example.com')));
        expect(jsonDecode(text) as List, hasLength(2));
      }
      await adapter.close();
    });
  });

  test(
    'logging stays fast with storage wired in (average under 1 ms)',
    () async {
      final adapter = MemoryStorageAdapter();
      _install(storage: adapter);
      await SealedTrace.init(_config);
      const calls = 5000;
      final watch = Stopwatch()..start();
      for (var i = 0; i < calls; i++) {
        SealedTrace.i(
          'bench',
          'event $i for asha@example.com',
          meta: {'phone': '+91 98765 43210', 'i': i},
        );
      }
      watch.stop();
      final perCall = watch.elapsedMicroseconds / calls;
      // ignore: avoid_print
      print(
        'SealedTrace.i with storage wired: '
        '${perCall.toStringAsFixed(1)} µs per call',
      );
      expect(perCall, lessThan(1000));
      final flushWatch = Stopwatch()..start();
      await SealedTrace.flush();
      flushWatch.stop();
      // ignore: avoid_print
      print(
        'Flushing ${5000} queued events to storage: '
        '${flushWatch.elapsedMilliseconds} ms',
      );
      expect(await adapter.listIndex(), isNotEmpty);
    },
  );
}
