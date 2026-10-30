import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'drift_storage_adapter.dart';
import 'memory_storage_adapter.dart';
import 'storage_adapter.dart';

/// File name of the database inside the storage directory.
const String databaseFileName = 'sealed_trace.db';

/// Opens the SQLite database, recovering from a corrupt file.
///
/// Reports each problem through [onProblem]. If the file cannot be opened it
/// is renamed aside and a fresh one is created; if that fails, or there is no
/// usable directory (pure Dart without `databaseDirectory`, unit tests), it
/// falls back to memory so logging keeps working until the process ends.
Future<StorageAdapter> openPlatformStorage({
  String? databaseDirectory,
  required void Function(Object error, StackTrace stack) onProblem,
}) async {
  final File file;
  try {
    final Directory directory;
    if (databaseDirectory != null) {
      directory = Directory(databaseDirectory);
    } else {
      directory = await getApplicationSupportDirectory();
    }
    await directory.create(recursive: true);
    file = File(p.join(directory.path, databaseFileName));
  } catch (error, stack) {
    onProblem(error, stack);
    return MemoryStorageAdapter();
  }

  try {
    return await _open(file);
  } catch (error, stack) {
    onProblem(error, stack);
  }

  try {
    await _moveAside(file);
    return await _open(file);
  } catch (error, stack) {
    onProblem(error, stack);
    return MemoryStorageAdapter();
  }
}

Future<DriftStorageAdapter> _open(File file) async {
  final adapter = DriftStorageAdapter(
    NativeDatabase.createInBackground(file, setup: _configure),
  );
  try {
    await adapter.open();
  } catch (_) {
    try {
      await adapter.close();
    } catch (_) {
      // Already failed; the original error is what matters.
    }
    rethrow;
  }
  return adapter;
}

// Runs in the database isolate when SQLite opens the file.
void _configure(Database database) {
  database.execute('PRAGMA journal_mode = WAL;');
  database.execute('PRAGMA synchronous = NORMAL;');
}

Future<void> _moveAside(File file) async {
  final stamp = DateTime.now().millisecondsSinceEpoch;
  for (final suffix in const ['', '-wal', '-shm']) {
    final candidate = File('${file.path}$suffix');
    if (await candidate.exists()) {
      await candidate.rename('${file.path}.corrupt-$stamp$suffix');
    }
  }
}
