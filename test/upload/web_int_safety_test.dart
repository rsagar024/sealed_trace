import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/storage/envelope_store.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import 'package:sealed_trace/src/storage/retention_policy.dart';
import 'package:sealed_trace/src/upload/batch_packer.dart';
import 'package:sealed_trace/src/upload/upload_scheduler.dart';

import '../helpers/envelopes.dart';

void main() {
  test('L11: the candidate bound is a plain constant, the request limit', () {
    expect(UploadScheduler.candidateBytes, BatchPacker.maxRequestBytes);
    expect(UploadScheduler.candidateBytes, greaterThan(0));
    // Fits a 32-bit signed int, so it is the same number under dart2js.
    expect(UploadScheduler.candidateBytes, lessThan(0x7fffffff));
  });

  test('L11: the bound lets a whole batch of envelopes through', () async {
    final adapter = MemoryStorageAdapter();
    await adapter.open();
    final store = EnvelopeStore(
      adapter: adapter,
      policy: const RetentionPolicy(
        maxEvents: 1 << 20,
        maxAgeDays: 3650,
        maxSizeBytes: 1 << 30,
        deadLetterTtl: Duration(days: 7),
      ),
    );
    for (var i = 0; i < 10; i++) {
      await store.append(makeEnvelope(id: 'e$i', createdAt: DateTime.now()));
    }
    final rows = await store.nextPending(
      limit: 50,
      maxBytes: UploadScheduler.candidateBytes,
    );
    expect(rows, hasLength(10));
  });

  test('L11: no shift of 32 or more in lib/ (wrong under dart2js)', () {
    // dart2js does `<<` on 32-bit values: `1 << 40` is 0 there. Such
    // constants must be written as plain numbers. A shift by 31 is fine when
    // the result is masked to 32 bits (as GHASH does, checked in a browser).
    final shift = RegExp(r'<<\s*(\d+)');
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('.g.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        for (final m in shift.allMatches(code)) {
          if (int.parse(m[1]!) >= 32) offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
