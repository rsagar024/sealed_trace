import '../event/sequence_counter.dart';
import 'storage_adapter.dart';

/// Keeps the sequence high-water mark in the storage meta table, so `seq`
/// keeps increasing across app restarts.
class StorageSequenceStore implements SequenceStore {
  /// Creates a store over [adapter].
  StorageSequenceStore(this.adapter);

  /// Where the value lives.
  final StorageAdapter adapter;

  /// The meta key holding the high-water mark.
  static const String key = 'seq_high_water';

  @override
  Future<int> readHighWater() async {
    final stored = await adapter.readMeta(key);
    return int.tryParse(stored ?? '') ?? 0;
  }

  @override
  Future<void> writeHighWater(int value) =>
      adapter.writeMeta(key, value.toString());
}
