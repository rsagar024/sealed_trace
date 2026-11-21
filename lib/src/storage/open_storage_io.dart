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

/// How long a copy of a corrupt database is kept for diagnosis (L10).
const Duration corruptCopyTtl = Duration(days: 7);

/// Most corrupt-database copies kept; older ones are deleted first.
const int maxCorruptCopies = 3;

// `sealed_trace.db.corrupt-<epoch ms>` plus its `-wal` / `-shm` files.
final RegExp _corruptCopy = RegExp(
  '^${RegExp.escape(databaseFileName)}\\.corrupt-(\\d{1,16})(?:-wal|-shm)?\$',
);

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
  final Directory directory;
  try {
    directory = await _directory(databaseDirectory);
    await directory.create(recursive: true);
    file = File(p.join(directory.path, databaseFileName));
  } catch (error, stack) {
    onProblem(error, stack);
    return MemoryStorageAdapter();
  }

  DriftStorageAdapter? adapter;
  try {
    adapter = await _open(file);
  } catch (error, stack) {
    onProblem(error, stack);
  }

  if (adapter == null) {
    try {
      await _moveAside(file);
      adapter = await _open(file);
    } catch (error, stack) {
      onProblem(error, stack);
      return MemoryStorageAdapter();
    }
  }

  // A good database is open: old corrupt copies are no longer needed (L10).
  try {
    await purgeCorruptCopies(directory, now: DateTime.now());
  } catch (error, stack) {
    onProblem(error, stack);
  }
  return adapter;
}

/// Deletes every corrupt-database copy, for `SealedTrace.clearLocalLogs`.
/// Returns how many copies were deleted. Never throws.
Future<int> deleteCorruptDatabaseCopies({String? databaseDirectory}) async {
  try {
    final directory = await _directory(databaseDirectory);
    if (!await directory.exists()) return 0;
    return await purgeCorruptCopies(directory, now: DateTime.now(), all: true);
  } catch (_) {
    return 0;
  }
}

/// Deletes corrupt-database copies in [directory]: those older than
/// [corruptCopyTtl], those beyond the newest [maxCorruptCopies], or, with
/// [all], every one. A copy's `-wal` and `-shm` files go with it. Only files
/// named exactly like a copy are touched. Returns how many copies (not files)
/// were deleted.
Future<int> purgeCorruptCopies(
  Directory directory, {
  required DateTime now,
  bool all = false,
}) async {
  final byStamp = <int, List<File>>{};
  await for (final entity in directory.list(followLinks: false)) {
    if (entity is! File) continue;
    final match = _corruptCopy.firstMatch(p.basename(entity.path));
    if (match == null) continue;
    final stamp = int.parse(match[1]!);
    (byStamp[stamp] ??= <File>[]).add(entity);
  }
  final newestFirst = byStamp.keys.toList()..sort((a, b) => b.compareTo(a));
  final cutoff = now.subtract(corruptCopyTtl).millisecondsSinceEpoch;
  var deleted = 0;
  for (var i = 0; i < newestFirst.length; i++) {
    final stamp = newestFirst[i];
    if (all || i >= maxCorruptCopies || stamp < cutoff) {
      for (final file in byStamp[stamp]!) {
        await file.delete();
      }
      deleted++;
    }
  }
  return deleted;
}

Future<Directory> _directory(String? databaseDirectory) async =>
    databaseDirectory != null
    ? Directory(databaseDirectory)
    : await getApplicationSupportDirectory();

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
