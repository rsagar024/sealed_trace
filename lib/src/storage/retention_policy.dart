import '../config/retention_config.dart';
import 'storage_adapter.dart';

/// The limits retention enforces.
class RetentionPolicy {
  /// Creates a policy.
  const RetentionPolicy({
    required this.maxEvents,
    required this.maxAgeDays,
    required this.maxSizeBytes,
    required this.deadLetterTtl,
  });

  /// The policy described by [config].
  factory RetentionPolicy.fromConfig(RetentionConfig config) => RetentionPolicy(
    maxEvents: config.maxEvents,
    maxAgeDays: config.maxAgeDays,
    maxSizeBytes: config.maxSizeBytes,
    deadLetterTtl: config.deadLetterTtl,
  );

  /// Most events kept.
  final int maxEvents;

  /// Oldest age kept, in days.
  final int maxAgeDays;

  /// Most stored bytes kept.
  final int maxSizeBytes;

  /// How long dead-lettered rows are kept.
  final Duration deadLetterTtl;
}

/// Decides which rows retention removes. Pure: it reads index columns only.
abstract final class RetentionPlanner {
  /// Returns the batch ids to delete, in the order they were chosen.
  ///
  /// Dead letters past their TTL go first, then rows older than the maximum
  /// age, then the oldest rows until both the event-count and size limits
  /// hold. Rows in [protected] (for example in flight to the server) are never
  /// chosen, though they still count toward the totals.
  static List<String> plan(
    List<EnvelopeIndexRow> rows,
    RetentionPolicy policy,
    DateTime now, {
    Set<String> protected = const <String>{},
  }) {
    final nowMs = now.millisecondsSinceEpoch;
    final ageCutoff = nowMs - Duration(days: policy.maxAgeDays).inMilliseconds;
    final deadLetterCutoff = nowMs - policy.deadLetterTtl.inMilliseconds;

    final remove = <String>[];
    final removed = <String>{};
    void take(EnvelopeIndexRow row) {
      if (removed.add(row.batchId)) remove.add(row.batchId);
    }

    for (final row in rows) {
      if (protected.contains(row.batchId)) continue;
      if (row.uploadState == uploadStateDeadLetter &&
          (row.lastAttemptAt ?? row.createdAt) < deadLetterCutoff) {
        take(row);
      }
    }
    for (final row in rows) {
      if (protected.contains(row.batchId)) continue;
      if (row.createdAt < ageCutoff) take(row);
    }

    var events = 0;
    var bytes = 0;
    for (final row in rows) {
      if (removed.contains(row.batchId)) continue;
      events += row.eventCount;
      bytes += row.sizeBytes;
    }

    if (events > policy.maxEvents || bytes > policy.maxSizeBytes) {
      final oldestFirst = rows.toList()
        ..sort((a, b) {
          final byTime = a.createdAt.compareTo(b.createdAt);
          return byTime != 0 ? byTime : a.batchId.compareTo(b.batchId);
        });
      for (final row in oldestFirst) {
        if (events <= policy.maxEvents && bytes <= policy.maxSizeBytes) break;
        if (removed.contains(row.batchId) || protected.contains(row.batchId)) {
          continue;
        }
        take(row);
        events -= row.eventCount;
        bytes -= row.sizeBytes;
      }
    }
    return remove;
  }
}
