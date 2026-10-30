import '../model/sealed_envelope.dart';

/// Upload state of a stored envelope: waiting to be uploaded.
const int uploadStatePending = 0;

/// Upload state of a stored envelope: gave up after too many attempts.
const int uploadStateDeadLetter = 1;

/// Thrown by an adapter when storage is out of space or quota.
class StorageFullException implements Exception {
  /// Creates the exception, optionally keeping the original [cause].
  const StorageFullException([this.cause]);

  /// The underlying error, if any.
  final Object? cause;

  @override
  String toString() => 'StorageFullException';
}

/// The clear columns of a stored envelope: everything retention and upload
/// scheduling may look at. It never includes the encrypted blobs.
class EnvelopeIndexRow {
  /// Creates an index row.
  const EnvelopeIndexRow({
    required this.batchId,
    required this.createdAt,
    required this.eventCount,
    required this.sizeBytes,
    required this.uploadState,
    required this.attempts,
    required this.lastAttemptAt,
    required this.uploadedAt,
  });

  /// The batch id.
  final String batchId;

  /// Creation time, epoch milliseconds.
  final int createdAt;

  /// Events inside the envelope.
  final int eventCount;

  /// Stored bytes of the encrypted fields.
  final int sizeBytes;

  /// [uploadStatePending] or [uploadStateDeadLetter].
  final int uploadState;

  /// Failed upload attempts so far.
  final int attempts;

  /// Time of the last attempt, epoch milliseconds, or null.
  final int? lastAttemptAt;

  /// Set once the server acknowledged the batch, until the row is deleted.
  final int? uploadedAt;
}

/// A stored envelope together with its upload bookkeeping.
class EnvelopeRow {
  /// Creates a row.
  const EnvelopeRow({
    required this.envelope,
    this.uploadState = uploadStatePending,
    this.attempts = 0,
    this.lastAttemptAt,
    this.uploadedAt,
  });

  /// A new pending row for [envelope].
  factory EnvelopeRow.pending(SealedEnvelope envelope) =>
      EnvelopeRow(envelope: envelope);

  /// The sealed data.
  final SealedEnvelope envelope;

  /// [uploadStatePending] or [uploadStateDeadLetter].
  final int uploadState;

  /// Failed upload attempts so far.
  final int attempts;

  /// Time of the last attempt, epoch milliseconds, or null.
  final int? lastAttemptAt;

  /// Acknowledgement time, epoch milliseconds, or null.
  final int? uploadedAt;

  /// Creation time, epoch milliseconds.
  int get createdAt => envelope.createdAt.millisecondsSinceEpoch;
}

/// Primitive operations on the local envelope store.
///
/// Adapters stay deliberately simple. Retention, dead-lettering and scheduling
/// live once in `EnvelopeStore`. No operation returns decrypted content, and
/// none ever needs it.
abstract interface class StorageAdapter {
  /// Opens the store, creating it if needed. Throws if it cannot be used.
  Future<void> open();

  /// Adds a row. Throws [StorageFullException] when out of space.
  Future<void> insertEnvelope(EnvelopeRow row);

  /// The index columns of every row, oldest first (`createdAt`, then batch id).
  Future<List<EnvelopeIndexRow>> listIndex();

  /// Full rows for [batchIds], oldest first. Unknown ids are skipped.
  Future<List<EnvelopeRow>> fetch(Iterable<String> batchIds);

  /// Removes the given rows.
  Future<void> deleteBatches(Iterable<String> batchIds);

  /// Updates bookkeeping for [batchIds]: adds [attemptsDelta] to `attempts`
  /// and replaces the other columns when given.
  Future<void> patch(
    Iterable<String> batchIds, {
    int attemptsDelta = 0,
    int? lastAttemptAt,
    int? uploadState,
    int? uploadedAt,
  });

  /// Removes every envelope. Metadata is kept.
  Future<void> clearAll();

  /// Reads a small bookkeeping value, or null.
  Future<String?> readMeta(String key);

  /// Writes a small bookkeeping value.
  Future<void> writeMeta(String key, String value);

  /// Releases resources.
  Future<void> close();
}
