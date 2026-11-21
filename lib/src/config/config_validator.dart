import '../transport/spki_pin.dart';
import 'retention_config.dart';
import 'sealed_trace_config.dart';
import 'upload_config.dart';

/// Validates and normalizes a [SealedTraceConfig]. Never throws.
abstract final class ConfigValidator {
  /// Returns human-readable problems; empty when the config is usable.
  static List<String> validate(SealedTraceConfig config) {
    final problems = <String>[];
    if (config.projectId.trim().isEmpty) {
      problems.add('projectId must not be empty');
    } else if (_controlChars.hasMatch(config.projectId)) {
      // It is part of the envelope's authenticated header (M1).
      problems.add('projectId must not contain control characters');
    }
    if (config.apiKey.trim().isEmpty) {
      problems.add('apiKey must not be empty');
    }
    if (config.appName.trim().isEmpty) {
      problems.add('appName must not be empty');
    }
    if (!_isValidBaseUrl(config.baseUrl)) {
      problems.add('baseUrl must be an absolute http(s) URL');
    } else if (_isCleartext(config.baseUrl) &&
        !config.allowInsecureHttp &&
        !_cleartextEnvs.contains(config.env.name)) {
      problems.add(
        'baseUrl must use https outside dev/local envs (got http with env '
        '"${config.env.name}"); set allowInsecureHttp: true to override',
      );
    }
    if (!_looksLikePem(config.publicKeyPem)) {
      problems.add('publicKeyPem must be a PEM-encoded public key');
    }
    final pins = config.uploadConfig.pinnedSpkiSha256;
    if (pins.isNotEmpty) {
      if (!pins.every(SpkiPin.isValid)) {
        problems.add(
          'pinnedSpkiSha256 entries must be base64 SHA-256 hashes (32 bytes)',
        );
      }
      if (config.uploadConfig.httpClientAdapter != null) {
        problems.add(
          'pinnedSpkiSha256 cannot be combined with httpClientAdapter',
        );
      }
      if (_isCleartext(config.baseUrl)) {
        problems.add('pinnedSpkiSha256 requires an https baseUrl');
      }
    }
    if (!_envName.hasMatch(config.env.name)) {
      problems.add('env must be 1-32 chars of a-z, 0-9, _ or -');
    }
    return problems;
  }

  static final RegExp _controlChars = RegExp(r'[\x00-\x1f\x7f]');

  static final RegExp _envName = RegExp(r'^[a-z0-9][a-z0-9_-]{0,31}$');

  /// Smallest upload [UploadConfig.interval]. A zero or tiny period would
  /// make the periodic timer spin.
  static const Duration minUploadInterval = Duration(seconds: 30);

  /// Smallest [UploadConfig.backoffBase]. Zero would retry server errors
  /// immediately, in a storm.
  static const Duration minBackoffBase = Duration(seconds: 1);

  /// Smallest [UploadConfig.requestTimeout].
  static const Duration minRequestTimeout = Duration(seconds: 1);

  /// Smallest [RetentionConfig.purgeInterval]. Zero would spin the purge
  /// timer.
  static const Duration minPurgeInterval = Duration(minutes: 1);

  /// Smallest [RetentionConfig.maxSizeBytes]: room for at least one batch.
  static const int minRetentionBytes = 64 * 1024;

  /// Returns [config] with out-of-range values clamped. See [normalize].
  static SealedTraceConfig clamp(SealedTraceConfig config) =>
      normalize(config).config;

  /// Returns [config] with out-of-range values clamped, plus one line per
  /// value that was changed, for reporting. The same instance is returned
  /// when nothing changes.
  ///
  /// Upload: `batchSize` 1..50, `maxAttempts` >= 1, `interval` >= 30 s,
  /// `backoffBase` >= 1 s, `requestTimeout` >= 1 s (the size thresholds are
  /// left alone: 0 or less disables those triggers). Retention: `maxEvents` and `maxAgeDays` >= 1,
  /// `maxSizeBytes` >= 64 KiB, `purgeInterval` >= 1 min, `deadLetterTtl`
  /// >= 0.
  static ({SealedTraceConfig config, List<String> adjusted}) normalize(
    SealedTraceConfig config,
  ) {
    final adjusted = <String>[];
    int ints(String name, int value, int fixed) {
      if (value != fixed) adjusted.add('$name $value -> $fixed');
      return fixed;
    }

    int atLeast(String name, int value, int floor) =>
        ints(name, value, value < floor ? floor : value);

    Duration durationAtLeast(String name, Duration value, Duration floor) {
      if (value >= floor) return value;
      adjusted.add('$name $value -> $floor');
      return floor;
    }

    final u = config.uploadConfig;
    final batchSize = ints(
      'uploadConfig.batchSize',
      u.batchSize,
      u.batchSize.clamp(1, 50),
    );
    final maxAttempts = atLeast('uploadConfig.maxAttempts', u.maxAttempts, 1);
    final interval = durationAtLeast(
      'uploadConfig.interval',
      u.interval,
      minUploadInterval,
    );
    final backoffBase = durationAtLeast(
      'uploadConfig.backoffBase',
      u.backoffBase,
      minBackoffBase,
    );
    final requestTimeout = durationAtLeast(
      'uploadConfig.requestTimeout',
      u.requestTimeout,
      minRequestTimeout,
    );

    final r = config.retentionConfig;
    final maxEvents = atLeast('retentionConfig.maxEvents', r.maxEvents, 1);
    final maxAgeDays = atLeast('retentionConfig.maxAgeDays', r.maxAgeDays, 1);
    final maxSizeBytes = atLeast(
      'retentionConfig.maxSizeBytes',
      r.maxSizeBytes,
      minRetentionBytes,
    );
    final purgeInterval = durationAtLeast(
      'retentionConfig.purgeInterval',
      r.purgeInterval,
      minPurgeInterval,
    );
    final deadLetterTtl = durationAtLeast(
      'retentionConfig.deadLetterTtl',
      r.deadLetterTtl,
      Duration.zero,
    );

    if (adjusted.isEmpty) return (config: config, adjusted: adjusted);
    return (
      config: config.copyWith(
        uploadConfig: u.copyWith(
          batchSize: batchSize,
          maxAttempts: maxAttempts,
          interval: interval,
          backoffBase: backoffBase,
          requestTimeout: requestTimeout,
        ),
        retentionConfig: r.copyWith(
          maxEvents: maxEvents,
          maxAgeDays: maxAgeDays,
          maxSizeBytes: maxSizeBytes,
          purgeInterval: purgeInterval,
          deadLetterTtl: deadLetterTtl,
        ),
      ),
      adjusted: adjusted,
    );
  }

  static bool _isValidBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  /// Envs where a cleartext `http://` baseUrl is accepted without opting in.
  static const Set<String> _cleartextEnvs = <String>{'dev', 'local'};

  static bool _isCleartext(String value) =>
      Uri.tryParse(value.trim())?.scheme.toLowerCase() == 'http';

  static bool _looksLikePem(String value) {
    final text = value.trim();
    return text.startsWith('-----BEGIN ') &&
        text.contains('PUBLIC KEY-----') &&
        text.contains('-----END ');
  }
}
