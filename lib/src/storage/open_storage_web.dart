import 'indexeddb_storage_adapter.dart';
import 'memory_storage_adapter.dart';
import 'storage_adapter.dart';

/// Opens IndexedDB storage in a browser.
///
/// If IndexedDB is unavailable or blocked (private browsing, disabled site
/// data), reports the problem and falls back to memory so logging keeps working
/// until the page closes.
Future<StorageAdapter> openPlatformStorage({
  String? databaseDirectory,
  required void Function(Object error, StackTrace stack) onProblem,
}) async {
  try {
    final adapter = IndexedDbStorageAdapter();
    await adapter.open();
    return adapter;
  } catch (error, stack) {
    onProblem(error, stack);
    return MemoryStorageAdapter();
  }
}
