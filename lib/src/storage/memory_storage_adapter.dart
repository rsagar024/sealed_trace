import 'storage_adapter.dart';

/// A [StorageAdapter] that keeps everything in memory.
///
/// Used in tests, in pure Dart without a database directory, and as the
/// degraded mode when persistent storage cannot be opened. Contents are lost
/// when the process ends.
class MemoryStorageAdapter implements StorageAdapter {
  /// Creates an empty store.
  MemoryStorageAdapter();

  final Map<String, EnvelopeRow> _rows = <String, EnvelopeRow>{};
  final Map<String, String> _meta = <String, String>{};

  @override
  Future<void> open() async {}

  @override
  Future<void> insertEnvelope(EnvelopeRow row) async {
    _rows[row.envelope.batchId] = row;
  }

  @override
  Future<List<EnvelopeIndexRow>> listIndex() async {
    final rows = _rows.values.toList()
      ..sort((a, b) {
        final byTime = a.createdAt.compareTo(b.createdAt);
        return byTime != 0
            ? byTime
            : a.envelope.batchId.compareTo(b.envelope.batchId);
      });
    return <EnvelopeIndexRow>[
      for (final row in rows)
        EnvelopeIndexRow(
          batchId: row.envelope.batchId,
          createdAt: row.createdAt,
          eventCount: row.envelope.eventCount,
          sizeBytes: row.envelope.storedBytes,
          uploadState: row.uploadState,
          attempts: row.attempts,
          lastAttemptAt: row.lastAttemptAt,
          uploadedAt: row.uploadedAt,
        ),
    ];
  }

  @override
  Future<List<EnvelopeRow>> fetch(Iterable<String> batchIds) async {
    final rows =
        <EnvelopeRow>[
          for (final id in batchIds)
            if (_rows[id] != null) _rows[id]!,
        ]..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0
              ? byTime
              : a.envelope.batchId.compareTo(b.envelope.batchId);
        });
    return rows;
  }

  @override
  Future<void> deleteBatches(Iterable<String> batchIds) async {
    batchIds.forEach(_rows.remove);
  }

  @override
  Future<void> patch(
    Iterable<String> batchIds, {
    int attemptsDelta = 0,
    int? lastAttemptAt,
    int? uploadState,
    int? uploadedAt,
  }) async {
    for (final id in batchIds) {
      final row = _rows[id];
      if (row == null) continue;
      _rows[id] = EnvelopeRow(
        envelope: row.envelope,
        attempts: row.attempts + attemptsDelta,
        lastAttemptAt: lastAttemptAt ?? row.lastAttemptAt,
        uploadState: uploadState ?? row.uploadState,
        uploadedAt: uploadedAt ?? row.uploadedAt,
      );
    }
  }

  @override
  Future<void> clearAll() async => _rows.clear();

  @override
  Future<String?> readMeta(String key) async => _meta[key];

  @override
  Future<void> writeMeta(String key, String value) async {
    _meta[key] = value;
  }

  @override
  Future<void> close() async {}
}
