/// Immutable snapshot of the SDK's internal diagnostic counters.
///
/// Counters never contain log content.
class DiagnosticSnapshot {
  /// Creates a snapshot.
  const DiagnosticSnapshot({
    this.eventsAccepted = 0,
    this.eventsDroppedLevel = 0,
    this.eventsDroppedQueueFull = 0,
    this.sealFailures = 0,
    this.storageFailures = 0,
    this.uploadAttempts = 0,
    this.uploadFailures = 0,
    this.envelopesDeadLettered = 0,
    this.purgedRows = 0,
    this.internalExceptions = 0,
  });

  /// Events that passed the gate and entered the pipeline.
  final int eventsAccepted;

  /// Events dropped because they were below `minLevel`.
  final int eventsDroppedLevel;

  /// Events dropped because the in-memory queue was full.
  final int eventsDroppedQueueFull;

  /// Batches dropped because sealing failed.
  final int sealFailures;

  /// Storage operations that failed.
  final int storageFailures;

  /// Upload requests attempted.
  final int uploadAttempts;

  /// Upload requests that failed.
  final int uploadFailures;

  /// Envelopes moved to the dead-letter state.
  final int envelopesDeadLettered;

  /// Stored rows removed by retention.
  final int purgedRows;

  /// Exceptions swallowed internally and reported through `onException`.
  final int internalExceptions;
}

/// Mutable counters owned by the facade. Internal.
class DiagnosticCounters {
  /// See [DiagnosticSnapshot.eventsAccepted].
  int eventsAccepted = 0;

  /// See [DiagnosticSnapshot.eventsDroppedLevel].
  int eventsDroppedLevel = 0;

  /// See [DiagnosticSnapshot.eventsDroppedQueueFull].
  int eventsDroppedQueueFull = 0;

  /// See [DiagnosticSnapshot.sealFailures].
  int sealFailures = 0;

  /// See [DiagnosticSnapshot.storageFailures].
  int storageFailures = 0;

  /// See [DiagnosticSnapshot.uploadAttempts].
  int uploadAttempts = 0;

  /// See [DiagnosticSnapshot.uploadFailures].
  int uploadFailures = 0;

  /// See [DiagnosticSnapshot.envelopesDeadLettered].
  int envelopesDeadLettered = 0;

  /// See [DiagnosticSnapshot.purgedRows].
  int purgedRows = 0;

  /// See [DiagnosticSnapshot.internalExceptions].
  int internalExceptions = 0;

  /// Returns an immutable copy of the current values.
  DiagnosticSnapshot snapshot() => DiagnosticSnapshot(
    eventsAccepted: eventsAccepted,
    eventsDroppedLevel: eventsDroppedLevel,
    eventsDroppedQueueFull: eventsDroppedQueueFull,
    sealFailures: sealFailures,
    storageFailures: storageFailures,
    uploadAttempts: uploadAttempts,
    uploadFailures: uploadFailures,
    envelopesDeadLettered: envelopesDeadLettered,
    purgedRows: purgedRows,
    internalExceptions: internalExceptions,
  );
}
