import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';

import '../helpers/envelopes.dart';

/// Behavior every [StorageAdapter] must share. Web-safe: no `dart:io`.
void runStorageAdapterContract(
  String name,
  Future<StorageAdapter> Function() create, {
  Future<void> Function(StorageAdapter adapter)? cleanup,
}) {
  group('StorageAdapter contract: $name', () {
    late StorageAdapter adapter;

    setUp(() async {
      adapter = await create();
      await adapter.open();
    });

    tearDown(() async {
      await adapter.clearAll();
      await adapter.close();
      await cleanup?.call(adapter);
    });

    void expectSameEnvelope(SealedEnvelope actual, SealedEnvelope expected) {
      expect(actual.batchId, expected.batchId);
      expect(actual.projectId, expected.projectId);
      expect(actual.createdAt, expected.createdAt);
      expect(actual.eventCount, expected.eventCount);
      expect(actual.wrappedKey, expected.wrappedKey);
      expect(actual.iv, expected.iv);
      expect(actual.tag, expected.tag);
      expect(actual.ciphertext, expected.ciphertext);
      expect(actual.seqMin, expected.seqMin);
      expect(actual.seqMax, expected.seqMax);
      expect(actual.minTs, expected.minTs);
      expect(actual.maxTs, expected.maxTs);
      expect(actual.topLevels, expected.topLevels);
      expect(actual.payloadSize, expected.payloadSize);
    }

    test('an empty store lists nothing', () async {
      expect(await adapter.listIndex(), isEmpty);
      expect(await adapter.fetch(['nope']), isEmpty);
      expect(await adapter.fetch(const <String>[]), isEmpty);
    });

    test('insert then fetch returns every field exactly', () async {
      final envelope = makeEnvelope(
        eventCount: 7,
        seqMin: 10,
        seqMax: 16,
        topLevels: 'debug,error',
        projectId: 'proj-xyz',
      );
      await adapter.insertEnvelope(EnvelopeRow.pending(envelope));

      final rows = await adapter.fetch([envelope.batchId]);
      expect(rows, hasLength(1));
      expectSameEnvelope(rows.single.envelope, envelope);
      expect(rows.single.uploadState, uploadStatePending);
      expect(rows.single.attempts, 0);
      expect(rows.single.lastAttemptAt, isNull);
      expect(rows.single.uploadedAt, isNull);
    });

    test('binary data with every byte value survives', () async {
      final base = makeEnvelope();
      final all = Uint8List.fromList(List<int>.generate(256, (i) => i));
      final envelope = SealedEnvelope(
        batchId: base.batchId,
        projectId: base.projectId,
        createdAt: base.createdAt,
        eventCount: 1,
        wrappedKey: all,
        iv: Uint8List.fromList(List<int>.generate(12, (i) => 255 - i)),
        tag: Uint8List(16),
        ciphertext: Uint8List.fromList(<int>[...all, ...all.reversed]),
        seqMin: 1,
        seqMax: 1,
        minTs: 1,
        maxTs: 2,
        topLevels: 'info',
        payloadSize: 512,
      );
      await adapter.insertEnvelope(EnvelopeRow.pending(envelope));
      final back = (await adapter.fetch([envelope.batchId])).single.envelope;
      expectSameEnvelope(back, envelope);
    });

    test('a 1 MB ciphertext round-trips', () async {
      final envelope = makeEnvelope(ciphertextLength: 1024 * 1024);
      await adapter.insertEnvelope(EnvelopeRow.pending(envelope));
      final back = (await adapter.fetch([envelope.batchId])).single.envelope;
      expect(back.ciphertext.length, 1024 * 1024);
      expect(back.ciphertext, envelope.ciphertext);
    });

    test('listIndex carries index columns and sizes, oldest first', () async {
      final newer = makeEnvelope(
        id: 'b-newer',
        createdAt: DateTime.utc(2026, 1, 2),
        eventCount: 3,
        ciphertextLength: 100,
      );
      final older = makeEnvelope(
        id: 'b-older',
        createdAt: DateTime.utc(2026, 1, 1),
        eventCount: 5,
        ciphertextLength: 50,
      );
      await adapter.insertEnvelope(EnvelopeRow.pending(newer));
      await adapter.insertEnvelope(EnvelopeRow.pending(older));

      final index = await adapter.listIndex();
      expect(index.map((r) => r.batchId), ['b-older', 'b-newer']);
      expect(index.first.eventCount, 5);
      expect(
        index.first.createdAt,
        DateTime.utc(2026, 1, 1).millisecondsSinceEpoch,
      );
      expect(index.first.sizeBytes, older.storedBytes);
      expect(index.last.sizeBytes, newer.storedBytes);
      expect(index.first.uploadState, uploadStatePending);
      expect(index.first.uploadedAt, isNull);
    });

    test('equal timestamps are ordered by batch id', () async {
      final at = DateTime.utc(2026, 1, 1);
      for (final id in ['b-3', 'b-1', 'b-2']) {
        await adapter.insertEnvelope(
          EnvelopeRow.pending(makeEnvelope(id: id, createdAt: at)),
        );
      }
      expect((await adapter.listIndex()).map((r) => r.batchId), [
        'b-1',
        'b-2',
        'b-3',
      ]);
    });

    test('fetch returns oldest first and skips unknown ids', () async {
      final a = makeEnvelope(id: 'a', createdAt: DateTime.utc(2026, 1, 3));
      final b = makeEnvelope(id: 'b', createdAt: DateTime.utc(2026, 1, 1));
      await adapter.insertEnvelope(EnvelopeRow.pending(a));
      await adapter.insertEnvelope(EnvelopeRow.pending(b));
      final rows = await adapter.fetch(['a', 'missing', 'b']);
      expect(rows.map((r) => r.envelope.batchId), ['b', 'a']);
    });

    group('patch', () {
      test('adds to attempts and sets the given columns', () async {
        final e = makeEnvelope(id: 'p1');
        await adapter.insertEnvelope(EnvelopeRow.pending(e));

        await adapter.patch(['p1'], attemptsDelta: 1, lastAttemptAt: 1000);
        await adapter.patch(['p1'], attemptsDelta: 2, uploadState: 1);
        await adapter.patch(['p1'], uploadedAt: 2000);

        final row = (await adapter.fetch(['p1'])).single;
        expect(row.attempts, 3);
        expect(row.lastAttemptAt, 1000);
        expect(row.uploadState, uploadStateDeadLetter);
        expect(row.uploadedAt, 2000);
        final index = (await adapter.listIndex()).single;
        expect(index.attempts, 3);
        expect(index.uploadState, uploadStateDeadLetter);
      });

      test('leaves other rows and unknown ids alone', () async {
        await adapter.insertEnvelope(
          EnvelopeRow.pending(makeEnvelope(id: 'x')),
        );
        await adapter.insertEnvelope(
          EnvelopeRow.pending(makeEnvelope(id: 'y')),
        );
        await adapter.patch(['x', 'ghost'], attemptsDelta: 1);
        final index = {for (final r in await adapter.listIndex()) r.batchId: r};
        expect(index['x']!.attempts, 1);
        expect(index['y']!.attempts, 0);
        expect(index.containsKey('ghost'), isFalse);
      });

      test('keeps the encrypted data intact', () async {
        final e = makeEnvelope(id: 'k1');
        await adapter.insertEnvelope(EnvelopeRow.pending(e));
        await adapter.patch(['k1'], attemptsDelta: 1, uploadState: 1);
        expectSameEnvelope((await adapter.fetch(['k1'])).single.envelope, e);
      });
    });

    test('deleteBatches removes only the given rows', () async {
      for (final id in ['d1', 'd2', 'd3']) {
        await adapter.insertEnvelope(EnvelopeRow.pending(makeEnvelope(id: id)));
      }
      await adapter.deleteBatches(['d1', 'd3', 'never-existed']);
      expect((await adapter.listIndex()).map((r) => r.batchId), ['d2']);
      expect(await adapter.fetch(['d1', 'd3']), isEmpty);
      await adapter.deleteBatches(const <String>[]);
    });

    test('clearAll removes envelopes but keeps metadata', () async {
      await adapter.insertEnvelope(EnvelopeRow.pending(makeEnvelope()));
      await adapter.writeMeta('k', 'v');
      await adapter.clearAll();
      expect(await adapter.listIndex(), isEmpty);
      expect(await adapter.readMeta('k'), 'v');
    });

    test('metadata reads, writes and overwrites', () async {
      expect(await adapter.readMeta('seq_high_water'), isNull);
      await adapter.writeMeta('seq_high_water', '100');
      expect(await adapter.readMeta('seq_high_water'), '100');
      await adapter.writeMeta('seq_high_water', '200');
      expect(await adapter.readMeta('seq_high_water'), '200');
      await adapter.writeMeta('other', 'x');
      expect(await adapter.readMeta('other'), 'x');
    });

    test(
      '450 rows list and fetch correctly (crosses statement chunking)',
      () async {
        final ids = <String>[];
        for (var i = 0; i < 450; i++) {
          final id = 'bulk-${i.toString().padLeft(4, '0')}';
          ids.add(id);
          await adapter.insertEnvelope(
            EnvelopeRow.pending(
              makeEnvelope(
                id: id,
                createdAt: DateTime.utc(2026, 1, 1).add(Duration(seconds: i)),
                ciphertextLength: 16,
              ),
            ),
          );
        }
        final index = await adapter.listIndex();
        expect(index, hasLength(450));
        expect(index.map((r) => r.batchId), ids);

        final rows = await adapter.fetch(ids);
        expect(rows, hasLength(450));
        expect(rows.first.envelope.batchId, ids.first);
        expect(rows.last.envelope.batchId, ids.last);

        await adapter.patch(ids, attemptsDelta: 1);
        expect(
          (await adapter.listIndex()).every((r) => r.attempts == 1),
          isTrue,
        );

        await adapter.deleteBatches(ids);
        expect(await adapter.listIndex(), isEmpty);
      },
    );
  });
}
