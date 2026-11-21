import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/storage/drift_storage_adapter.dart';
import 'package:sealed_trace/src/storage/open_storage_io.dart';

import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

late Directory _root;

final _now = DateTime.utc(2026, 11, 15, 12);

/// Writes a copy (main file plus -wal and -shm) stamped [age] before [_now].
void _copy(Directory dir, Duration age, {bool sidecars = true}) {
  final stamp = _now.subtract(age).millisecondsSinceEpoch;
  for (final suffix in sidecars ? const ['', '-wal', '-shm'] : const ['']) {
    File(
      p.join(dir.path, '$databaseFileName.corrupt-$stamp$suffix'),
    ).writeAsBytesSync(const [1, 2, 3]);
  }
}

List<String> _names(Directory dir) =>
    [for (final e in dir.listSync()) p.basename(e.path)]..sort();

void main() {
  setUpAll(() async {
    _root = await Directory.systemTemp.createTemp('sealed_trace_l10');
  });

  tearDownAll(() async {
    try {
      await _root.delete(recursive: true);
    } catch (_) {
      // Windows may still hold a file briefly.
    }
  });

  group('L10: purgeCorruptCopies', () {
    test('copies older than 7 days go, with their -wal and -shm', () async {
      final dir = await _root.createTemp('age');
      _copy(dir, const Duration(days: 1));
      _copy(dir, const Duration(days: 8));
      final deleted = await purgeCorruptCopies(dir, now: _now);
      expect(deleted, 1);
      expect(_names(dir), hasLength(3), reason: 'the recent copy, 3 files');
      final recent = _now
          .subtract(const Duration(days: 1))
          .millisecondsSinceEpoch;
      expect(_names(dir).every((n) => n.contains('$recent')), isTrue);
    });

    test('at most the newest 3 copies are kept', () async {
      final dir = await _root.createTemp('count');
      for (var h = 1; h <= 5; h++) {
        _copy(dir, Duration(hours: h), sidecars: false);
      }
      expect(await purgeCorruptCopies(dir, now: _now), 2);
      final kept = _names(dir);
      expect(kept, hasLength(3));
      final oldest = _now
          .subtract(const Duration(hours: 5))
          .millisecondsSinceEpoch;
      expect(kept.any((n) => n.contains('$oldest')), isFalse);
    });

    test('all: every copy goes; nothing else is touched', () async {
      final dir = await _root.createTemp('all');
      _copy(dir, const Duration(minutes: 1));
      final unrelated = [
        databaseFileName,
        '$databaseFileName-wal',
        '$databaseFileName.corrupt-notanumber',
        '$databaseFileName.corrupt-123.bak',
        'other.db.corrupt-123',
        'notes.txt',
      ];
      for (final name in unrelated) {
        File(p.join(dir.path, name)).writeAsStringSync('x');
      }
      expect(await purgeCorruptCopies(dir, now: _now, all: true), 1);
      expect(_names(dir), unorderedEquals(unrelated));
    });
  });

  group('L10: at open and in clearLocalLogs', () {
    test('a successful open deletes stale copies', () async {
      final dir = await _root.createTemp('open');
      final stale = DateTime.now()
          .subtract(const Duration(days: 30))
          .millisecondsSinceEpoch;
      File(
        p.join(dir.path, '$databaseFileName.corrupt-$stale'),
      ).writeAsBytesSync(const [0]);
      final adapter = await openPlatformStorage(
        databaseDirectory: dir.path,
        onProblem: (e, _) => fail('unexpected problem: $e'),
      );
      expect(adapter, isA<DriftStorageAdapter>());
      await adapter.close();
      expect(_names(dir).where((n) => n.contains('.corrupt-')), isEmpty);
    });

    test('deleteCorruptDatabaseCopies removes all and never throws', () async {
      final dir = await _root.createTemp('delete');
      _copy(dir, Duration.zero);
      expect(await deleteCorruptDatabaseCopies(databaseDirectory: dir.path), 1);
      expect(_names(dir), isEmpty);
      expect(
        await deleteCorruptDatabaseCopies(
          databaseDirectory: p.join(dir.path, 'missing'),
        ),
        0,
      );
      // No databaseDirectory: path_provider has no plugin in unit tests.
      expect(await deleteCorruptDatabaseCopies(), 0);
    });

    test('clearLocalLogs deletes the previous user\'s corrupt copies', () async {
      final dir = await _root.createTemp('logout');
      // A recent copy, which a normal open keeps for diagnosis.
      File(
        p.join(
          dir.path,
          '$databaseFileName.corrupt-${DateTime.now().millisecondsSinceEpoch}',
        ),
      ).writeAsBytesSync(const [9, 9, 9]);
      SealedTrace.debugOverrides = RuntimeOverrides(
        disableUploads: true,
        lifecycle: FakeLifecycle(),
        deviceContext: testDevice,
      );
      addTearDown(() async {
        await SealedTrace.dispose();
        SealedTrace.debugOverrides = null;
      });
      await SealedTrace.init(
        SealedTraceConfig(
          baseUrl: 'https://logs.example.com',
          projectId: 'proj',
          apiKey: 'key',
          publicKeyPem: testPublicKeySpki,
          appName: 'app',
          databaseDirectory: dir.path,
        ),
      );
      expect(
        _names(dir).where((n) => n.contains('.corrupt-')),
        hasLength(1),
        reason: 'kept at open',
      );
      await SealedTrace.clearLocalLogs();
      expect(_names(dir).where((n) => n.contains('.corrupt-')), isEmpty);
      expect(_names(dir), contains(databaseFileName), reason: 'live db kept');
    });
  });
}
