import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import 'storage_adapter_contract.dart';

void main() {
  runStorageAdapterContract('memory', () async => MemoryStorageAdapter());
}
