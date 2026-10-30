/// Overall outcome of an upload cycle.
enum UploadOutcome {
  /// Every attempted envelope was acknowledged.
  success,

  /// Some envelopes were acknowledged and some were not.
  partial,

  /// Nothing was acknowledged.
  failed,

  /// No upload was attempted (nothing pending, disabled, or offline).
  skipped,

  /// The server rejected the API key (401 or 403); uploads are paused.
  unauthorized,
}

/// Result of an upload cycle, delivered to `SealedTrace.onUploadResult` and
/// returned by `SealedTrace.flush`.
class UploadResult {
  /// Creates a result.
  const UploadResult({
    required this.outcome,
    required this.at,
    this.accepted = 0,
    this.duplicate = 0,
    this.rejected = 0,
    this.failed = 0,
  });

  /// A result for a cycle in which nothing was attempted.
  factory UploadResult.skipped() =>
      UploadResult(outcome: UploadOutcome.skipped, at: DateTime.now().toUtc());

  /// Overall outcome of the cycle.
  final UploadOutcome outcome;

  /// When the cycle finished (UTC).
  final DateTime at;

  /// Envelopes newly accepted by the server.
  final int accepted;

  /// Envelopes the server had already received.
  final int duplicate;

  /// Envelopes the server rejected.
  final int rejected;

  /// Envelopes that failed to upload and will be retried or dead-lettered.
  final int failed;
}
