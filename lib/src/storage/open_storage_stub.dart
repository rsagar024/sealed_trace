import 'memory_storage_adapter.dart';
import 'storage_adapter.dart';

/// Fallback for platforms with neither `dart:io` nor `dart:js_interop`.
///
/// Uses memory only and reports that logs will not survive a restart.
Future<StorageAdapter> openPlatformStorage({
  String? databaseDirectory,
  required void Function(Object error, StackTrace stack) onProblem,
}) async {
  onProblem(
    UnsupportedError('No persistent storage on this platform'),
    StackTrace.current,
  );
  return MemoryStorageAdapter();
}

/// There are no database files here, so nothing to delete.
Future<int> deleteCorruptDatabaseCopies({String? databaseDirectory}) async => 0;
