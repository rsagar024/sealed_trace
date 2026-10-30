import '../model/sealed_envelope.dart';
import 'retention_policy.dart';
import 'storage_adapter.dart';

/// Totals over everything stored, from index columns only.
class StorageStats {
  /// Creates stats.
  const StorageStats({
    required this.envelopes,
    required this.events,
    required this.bytes,
    required this.deadLetters,
    required this.pendingEvents,
    required this.pendingBytes,
  });

  /// Number of stored envelopes.
  final int envelopes;

  /// Number of events inside them.
  final int events;

  /// Stored bytes of the encrypted fields.
  final int bytes;

  /// How many envelopes are dead-lettered.
  final int deadLetters;

  /// Events in envelopes still waiting to be uploaded.
  final int pendingEvents;

  /// Stored bytes of envelopes still waiting to be uploaded.
  final int pendingBytes;
}

/// Storage behavior shared by every adapter: appending, scheduling queries,
/// failure bookkeeping and retention.
///
/// Every decision here uses index columns; nothing is ever decrypted.
class EnvelopeStore {
  /// Creates a store over [adapter].
  EnvelopeStore({
    required this.adapter,
    required this.policy,
    this.onPurged,
    this.onDeadLettered,
  });

  /// The underlying primitives.
  final StorageAdapter adapter;

  /// Retention limits.
  final RetentionPolicy policy;

  /// Called with the number of rows removed by a purge.
  final void Function(int count)? onPurged;

  /// Called with the number of rows moved to the dead-letter state.
  final void Function(int count)? onDeadLettered;

  /// Share of rows removed by an emergency purge when storage is full.
  static const double emergencyPurgeShare = 0.2;

  /// Stores [envelope] as a pending row.
  ///
  /// If storage is full, the oldest rows are purged once and the write is
  /// retried once; a second failure is thrown to the caller.
  Future<void> append(SealedEnvelope envelope) async {
    final row = EnvelopeRow.pending(envelope);
    try {
      await adapter.insertEnvelope(row);
    } on StorageFullException {
      await _emergencyPurge();
      await adapter.insertEnvelope(row);
    }
  }

  /// Pending envelopes to upload, oldest first.
  ///
  /// Dead letters and acknowledged rows are skipped. At most [limit] rows are
  /// returned and their stored bytes stay within [maxBytes], except that the
  /// first row is always returned so an oversized envelope cannot block the
  /// queue.
  Future<List<EnvelopeRow>> nextPending({
    required int limit,
    required int maxBytes,
    Set<String> exclude = const <String>{},
  }) async {
    final index = await adapter.listIndex();
    final ids = <String>[];
    var bytes = 0;
    for (final row in index) {
      if (ids.length >= limit) break;
      if (row.uploadState != uploadStatePending || row.uploadedAt != null) {
        continue;
      }
      if (exclude.contains(row.batchId)) continue;
      if (ids.isNotEmpty && bytes + row.sizeBytes > maxBytes) break;
      ids.add(row.batchId);
      bytes += row.sizeBytes;
    }
    return ids.isEmpty ? <EnvelopeRow>[] : adapter.fetch(ids);
  }

  /// Dead-lettered rows with their data, oldest first, skipping [exclude].
  Future<List<EnvelopeRow>> nextDeadLetters({
    required int limit,
    Set<String> exclude = const <String>{},
  }) async {
    final ids = <String>[
      for (final row in await adapter.listIndex())
        if (row.uploadState == uploadStateDeadLetter &&
            !exclude.contains(row.batchId))
          row.batchId,
    ].take(limit).toList();
    return ids.isEmpty ? <EnvelopeRow>[] : adapter.fetch(ids);
  }

  /// Moves [batchIds] to the dead-letter state at once, counting the attempt.
  ///
  /// For envelopes that can never be accepted. Returns how many rows changed.
  Future<int> deadLetterNow(Iterable<String> batchIds, DateTime now) async {
    final wanted = batchIds.toSet();
    final existing = <String>[
      for (final row in await adapter.listIndex())
        if (wanted.contains(row.batchId)) row.batchId,
    ];
    if (existing.isEmpty) return 0;
    await adapter.patch(
      existing,
      attemptsDelta: 1,
      lastAttemptAt: now.millisecondsSinceEpoch,
      uploadState: uploadStateDeadLetter,
    );
    onDeadLettered?.call(existing.length);
    return existing.length;
  }

  /// Dead-lettered rows, oldest first.
  Future<List<EnvelopeIndexRow>> deadLetters() async => <EnvelopeIndexRow>[
    for (final row in await adapter.listIndex())
      if (row.uploadState == uploadStateDeadLetter) row,
  ];

  /// Records that the server acknowledged [batchIds], then deletes them.
  ///
  /// The mark is written first so that a crash between the two steps is
  /// repaired by [deleteAcknowledged] on the next start.
  Future<void> markUploadedAndDelete(
    Iterable<String> batchIds,
    DateTime now,
  ) async {
    final ids = batchIds.toList();
    if (ids.isEmpty) return;
    await adapter.patch(ids, uploadedAt: now.millisecondsSinceEpoch);
    await adapter.deleteBatches(ids);
  }

  /// Deletes rows that were acknowledged but not yet removed (a crash
  /// between the mark and the delete). Returns how many were removed.
  Future<int> deleteAcknowledged() async {
    final ids = <String>[
      for (final row in await adapter.listIndex())
        if (row.uploadedAt != null) row.batchId,
    ];
    if (ids.isNotEmpty) await adapter.deleteBatches(ids);
    return ids.length;
  }

  /// Records a failed upload attempt for [batchIds].
  ///
  /// Each row's attempt count goes up by one; rows reaching [maxAttempts] are
  /// moved to the dead-letter state, and their count is returned.
  Future<int> recordFailure(
    Iterable<String> batchIds,
    DateTime now, {
    required int maxAttempts,
  }) async {
    final wanted = batchIds.toSet();
    if (wanted.isEmpty) return 0;
    final nowMs = now.millisecondsSinceEpoch;
    final keep = <String>[];
    final bury = <String>[];
    for (final row in await adapter.listIndex()) {
      if (!wanted.contains(row.batchId)) continue;
      (row.attempts + 1 >= maxAttempts ? bury : keep).add(row.batchId);
    }
    if (keep.isNotEmpty) {
      await adapter.patch(keep, attemptsDelta: 1, lastAttemptAt: nowMs);
    }
    if (bury.isNotEmpty) {
      await adapter.patch(
        bury,
        attemptsDelta: 1,
        lastAttemptAt: nowMs,
        uploadState: uploadStateDeadLetter,
      );
      onDeadLettered?.call(bury.length);
    }
    return bury.length;
  }

  /// Applies retention. Rows in [protected] are never removed.
  ///
  /// Returns the number of rows removed.
  Future<int> purge(
    DateTime now, {
    Set<String> protected = const <String>{},
  }) async {
    final doomed = RetentionPlanner.plan(
      await adapter.listIndex(),
      policy,
      now,
      protected: protected,
    );
    if (doomed.isEmpty) return 0;
    await adapter.deleteBatches(doomed);
    onPurged?.call(doomed.length);
    return doomed.length;
  }

  /// Totals over everything stored.
  Future<StorageStats> stats() async {
    var envelopes = 0;
    var events = 0;
    var bytes = 0;
    var deadLetters = 0;
    var pendingEvents = 0;
    var pendingBytes = 0;
    for (final row in await adapter.listIndex()) {
      envelopes++;
      events += row.eventCount;
      bytes += row.sizeBytes;
      if (row.uploadState == uploadStateDeadLetter) {
        deadLetters++;
      } else if (row.uploadedAt == null) {
        pendingEvents += row.eventCount;
        pendingBytes += row.sizeBytes;
      }
    }
    return StorageStats(
      envelopes: envelopes,
      events: events,
      bytes: bytes,
      deadLetters: deadLetters,
      pendingEvents: pendingEvents,
      pendingBytes: pendingBytes,
    );
  }

  /// Removes every envelope.
  Future<void> clear() => adapter.clearAll();

  Future<void> _emergencyPurge() async {
    final index = await adapter.listIndex();
    if (index.isEmpty) return;
    final count = (index.length * emergencyPurgeShare).ceil();
    final doomed = <String>[for (final row in index.take(count)) row.batchId];
    await adapter.deleteBatches(doomed);
    onPurged?.call(doomed.length);
  }
}
