@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/storage/indexeddb_storage_adapter.dart';
import 'package:sealed_trace/src/storage/open_storage.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';

import '../helpers/envelopes.dart';
import 'storage_adapter_contract.dart';

int _databases = 0;

String _uniqueName() =>
    'sealed_trace_test_${DateTime.now().microsecondsSinceEpoch}_${_databases++}';

void main() {
  runStorageAdapterContract(
    'indexeddb',
    () async => IndexedDbStorageAdapter(databaseName: _uniqueName()),
    cleanup: (adapter) => (adapter as IndexedDbStorageAdapter).deleteDatabase(),
  );

  group('IndexedDB specifics', () {
    test('data survives closing and reopening the database', () async {
      final name = _uniqueName();
      final first = IndexedDbStorageAdapter(databaseName: name);
      await first.open();
      final envelope = makeEnvelope(id: 'persist', eventCount: 3);
      await first.insertEnvelope(EnvelopeRow.pending(envelope));
      await first.writeMeta('seq_high_water', '500');
      await first.close();

      final second = IndexedDbStorageAdapter(databaseName: name);
      await second.open();
      final row = (await second.fetch(['persist'])).single;
      expect(row.envelope.ciphertext, envelope.ciphertext);
      expect(row.envelope.eventCount, 3);
      expect(await second.readMeta('seq_high_water'), '500');
      await second.deleteDatabase();
    });

    test('using the adapter before open fails clearly', () async {
      final adapter = IndexedDbStorageAdapter(databaseName: _uniqueName());
      await expectLater(adapter.listIndex(), throwsStateError);
    });

    test('openPlatformStorage uses IndexedDB in a browser', () async {
      final problems = <Object>[];
      final adapter = await openPlatformStorage(
        onProblem: (e, _) => problems.add(e),
      );
      expect(problems, isEmpty);
      expect(adapter, isA<IndexedDbStorageAdapter>());
      await adapter.clearAll();
      await adapter.close();
    });

    test(
      'rows written in one transaction are all-or-nothing visible',
      () async {
        final adapter = IndexedDbStorageAdapter(databaseName: _uniqueName());
        await adapter.open();
        for (var i = 0; i < 20; i++) {
          await adapter.insertEnvelope(
            EnvelopeRow.pending(
              makeEnvelope(id: 'tx-$i', ciphertextLength: 32),
            ),
          );
        }
        // Index and blob stores must agree.
        final index = await adapter.listIndex();
        final rows = await adapter.fetch(index.map((r) => r.batchId));
        expect(rows, hasLength(index.length));
        await adapter.deleteDatabase();
      },
    );
  });
}
