/// Limits on how much sealed data is kept on the device.
class RetentionConfig {
  /// Creates a retention configuration.
  const RetentionConfig({
    this.maxEvents = 10000,
    this.maxAgeDays = 30,
    this.maxSizeBytes = 50 * 1024 * 1024,
    this.purgeInterval = const Duration(hours: 1),
    this.deadLetterTtl = const Duration(days: 7),
  });

  /// Maximum number of stored events. Oldest are purged first.
  final int maxEvents;

  /// Maximum age of stored events, in days.
  final int maxAgeDays;

  /// Maximum estimated size of stored data, in bytes.
  final int maxSizeBytes;

  /// Period of the background purge.
  final Duration purgeInterval;

  /// How long dead-lettered envelopes are kept.
  final Duration deadLetterTtl;

  /// Returns a copy with the given fields replaced.
  RetentionConfig copyWith({
    int? maxEvents,
    int? maxAgeDays,
    int? maxSizeBytes,
    Duration? purgeInterval,
    Duration? deadLetterTtl,
  }) {
    return RetentionConfig(
      maxEvents: maxEvents ?? this.maxEvents,
      maxAgeDays: maxAgeDays ?? this.maxAgeDays,
      maxSizeBytes: maxSizeBytes ?? this.maxSizeBytes,
      purgeInterval: purgeInterval ?? this.purgeInterval,
      deadLetterTtl: deadLetterTtl ?? this.deadLetterTtl,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is RetentionConfig &&
      maxEvents == other.maxEvents &&
      maxAgeDays == other.maxAgeDays &&
      maxSizeBytes == other.maxSizeBytes &&
      purgeInterval == other.purgeInterval &&
      deadLetterTtl == other.deadLetterTtl;

  @override
  int get hashCode => Object.hash(
    maxEvents,
    maxAgeDays,
    maxSizeBytes,
    purgeInterval,
    deadLetterTtl,
  );
}
