@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/model/log_level.dart';
import 'package:sealed_trace/src/storage/drift_storage_adapter.dart';
import 'package:sealed_trace/src/storage/envelope_store.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import 'package:sealed_trace/src/storage/open_storage_io.dart';
import 'package:sealed_trace/src/storage/retention_policy.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/envelopes.dart';
import '../helpers/test_keys.dart';
import 'storage_adapter_contract.dart';

late Directory _tempRoot;

Future<Directory> _freshDir() => _tempRoot.createTemp('db');

Future<Uint8List> _allDatabaseBytes(Directory dir) async {
  final bytes = BytesBuilder();
  await for (final entity in dir.list()) {
    if (entity is File) bytes.add(await entity.readAsBytes());
  }
  return bytes.toBytes();
}

bool _contains(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return true;
  }
  return false;
}

void main() {
  setUpAll(() async {
    _tempRoot = await Directory.systemTemp.createTemp('sealed_trace_drift_');
  });

  tearDownAll(() async {
    if (await _tempRoot.exists()) {
      try {
        await _tempRoot.delete(recursive: true);
      } catch (_) {
        // A lingering database isolate may still hold a file on Windows.
      }
    }
  });

  runStorageAdapterContract(
    'drift (in memory)',
    () async => DriftStorageAdapter(NativeDatabase.memory()),
  );

  runStorageAdapterContract('drift (file, background isolate)', () async {
    final problems = <Object>[];
    final adapter = await openPlatformStorage(
      databaseDirectory: (await _freshDir()).path,
      onProblem: (e, _) => problems.add(e),
    );
    expect(problems, isEmpty);
    expect(adapter, isA<DriftStorageAdapter>());
    return adapter;
  });

  group('file database', () {
    test('rows and metadata survive close and reopen', () async {
      final dir = await _freshDir();
      final first = await openPlatformStorage(
        databaseDirectory: dir.path,
        onProblem: (e, _) => fail('unexpected problem: $e'),
      );
      final envelope = makeEnvelope(id: 'persist-1', eventCount: 4);
      await first.insertEnvelope(EnvelopeRow.pending(envelope));
      await first.patch(['persist-1'], attemptsDelta: 2, uploadState: 1);
      await first.writeMeta('seq_high_water', '300');
      await first.close();

      final second = await openPlatformStorage(
        databaseDirectory: dir.path,
        onProblem: (e, _) => fail('unexpected problem: $e'),
      );
      final row = (await second.fetch(['persist-1'])).single;
      expect(row.envelope.ciphertext, envelope.ciphertext);
      expect(row.envelope.eventCount, 4);
      expect(row.attempts, 2);
      expect(row.uploadState, uploadStateDeadLetter);
      expect(await second.readMeta('seq_high_water'), '300');
      await second.close();
    });

    test('write-ahead logging is enabled', () async {
      final adapter =
          await openPlatformStorage(
                databaseDirectory: (await _freshDir()).path,
                onProblem: (e, _) => fail('unexpected problem: $e'),
              )
              as DriftStorageAdapter;
      final rows = await adapter.rawSelect('PRAGMA journal_mode');
      expect(rows.single.data.values.single.toString().toLowerCase(), 'wal');
      await adapter.close();
    });

    test(
      'a corrupt file is moved aside and a fresh database is created',
      () async {
        final dir = await _freshDir();
        final file = File(p.join(dir.path, databaseFileName));
        await file.writeAsBytes(
          List<int>.generate(4096, (i) => (i * 7) & 0xff),
        );

        final problems = <Object>[];
        final adapter = await openPlatformStorage(
          databaseDirectory: dir.path,
          onProblem: (e, _) => problems.add(e),
        );

        expect(problems, hasLength(1));
        expect(adapter, isA<DriftStorageAdapter>());
        final aside = [
          for (final e in dir.listSync())
            if (p.basename(e.path).contains('.corrupt-')) e,
        ];
        expect(aside, isNotEmpty);

        await adapter.insertEnvelope(EnvelopeRow.pending(makeEnvelope()));
        expect(await adapter.listIndex(), hasLength(1));
        await adapter.close();
      },
    );

    test('no directory available falls back to memory and reports', () async {
      final problems = <Object>[];
      // path_provider has no plugin in unit tests, like pure Dart.
      final adapter = await openPlatformStorage(
        onProblem: (e, _) => problems.add(e),
      );
      expect(adapter, isA<MemoryStorageAdapter>());
      expect(problems, hasLength(1));
    });

    test('a path that cannot be a directory falls back to memory', () async {
      final blocker = File(p.join((await _freshDir()).path, 'blocker'));
      await blocker.writeAsString('x');
      final problems = <Object>[];
      final adapter = await openPlatformStorage(
        databaseDirectory: p.join(blocker.path, 'sub'),
        onProblem: (e, _) => problems.add(e),
      );
      expect(adapter, isA<MemoryStorageAdapter>());
      expect(problems, hasLength(1));
    });

    test(
      'the database file never contains plaintext, only ciphertext',
      () async {
        const marker = 'PLAINTEXT-MARKER-4f9a1c7e-do-not-store';
        final dir = await _freshDir();
        final adapter = await openPlatformStorage(
          databaseDirectory: dir.path,
          onProblem: (e, _) => fail('unexpected problem: $e'),
        );

        final sealer = EnvelopeSealer(
          publicKey: PublicKeyParser.parse(testPublicKeySpki),
          projectId: 'p',
        );
        final record = LogRecord(
          id: 'id-1',
          seq: 1,
          timestamp: DateTime.utc(2026, 1, 1),
          level: LogLevel.error,
          tag: 'auth',
          message: 'the secret is $marker',
          error: marker,
          stackTrace: null,
          metadata: {'note': marker},
          sessionId: 's',
          userId: null,
          ctx: const {},
        );
        final envelope = await sealer.seal([record]);
        await adapter.insertEnvelope(EnvelopeRow.pending(envelope));
        await adapter.close();

        final bytes = await _allDatabaseBytes(dir);
        expect(bytes, isNotEmpty);
        expect(
          _contains(bytes, marker.codeUnits),
          isFalse,
          reason: 'plaintext found in the database files',
        );
        expect(
          _contains(bytes, envelope.ciphertext.sublist(0, 24)),
          isTrue,
          reason: 'ciphertext should be in the database files',
        );

        // And the stored row still decrypts to the original text.
        final reopened = await openPlatformStorage(
          databaseDirectory: dir.path,
          onProblem: (e, _) => fail('unexpected problem: $e'),
        );
        final stored = (await reopened.fetch([envelope.batchId])).single;
        expect(await openEnvelope(stored.envelope), contains(marker));
        await reopened.close();
      },
    );
  });

  group('a real full database (SQLITE_FULL)', () {
    // max_page_count caps the database, so SQLite itself reports
    // "database or disk is full", as it would on a full disk.
    DriftStorageAdapter capped() => DriftStorageAdapter(
      NativeDatabase.memory(
        setup: (db) => db.execute('PRAGMA max_page_count = 80'),
      ),
    );

    test('a write that does not fit throws StorageFullException', () async {
      final adapter = capped();
      await adapter.open();
      Object? failure;
      var stored = 0;
      for (var i = 0; i < 100 && failure == null; i++) {
        try {
          await adapter.insertEnvelope(
            EnvelopeRow.pending(
              makeEnvelope(id: 'f-${1000 + i}', ciphertextLength: 20000),
            ),
          );
          stored++;
        } catch (error) {
          failure = error;
        }
      }
      expect(failure, isA<StorageFullException>());
      expect(stored, greaterThan(0));
      // The failed write left nothing half-written.
      expect(await adapter.listIndex(), hasLength(stored));
      await adapter.close();
    });

    test('EnvelopeStore.append purges the oldest rows and retries', () async {
      final adapter = capped();
      await adapter.open();
      final store = EnvelopeStore(
        adapter: adapter,
        policy: const RetentionPolicy(
          maxEvents: 1 << 30,
          maxAgeDays: 3650,
          maxSizeBytes: 1 << 40,
          deadLetterTtl: Duration(days: 7),
        ),
      );
      var stored = 0;
      for (var i = 0; i < 100; i++) {
        try {
          await adapter.insertEnvelope(
            EnvelopeRow.pending(
              makeEnvelope(id: 'f-${1000 + i}', ciphertextLength: 20000),
            ),
          );
          stored++;
        } on StorageFullException {
          break;
        }
      }
      await store.append(makeEnvelope(id: 'f-new', ciphertextLength: 20000));
      final ids = (await adapter.listIndex()).map((r) => r.batchId).toList();
      expect(ids, contains('f-new'));
      expect(ids, isNot(contains('f-1000')));
      expect(ids.length, lessThanOrEqualTo(stored));
      await adapter.close();
    });
  });
}
