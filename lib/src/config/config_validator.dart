import 'sealed_trace_config.dart';

/// Validates and normalizes a [SealedTraceConfig]. Never throws.
abstract final class ConfigValidator {
  /// Returns human-readable problems; empty when the config is usable.
  static List<String> validate(SealedTraceConfig config) {
    final problems = <String>[];
    if (config.projectId.trim().isEmpty) {
      problems.add('projectId must not be empty');
    }
    if (config.apiKey.trim().isEmpty) {
      problems.add('apiKey must not be empty');
    }
    if (config.appName.trim().isEmpty) {
      problems.add('appName must not be empty');
    }
    if (!_isValidBaseUrl(config.baseUrl)) {
      problems.add('baseUrl must be an absolute http(s) URL');
    }
    if (!_looksLikePem(config.publicKeyPem)) {
      problems.add('publicKeyPem must be a PEM-encoded public key');
    }
    if (!_envName.hasMatch(config.env.name)) {
      problems.add('env must be 1-32 chars of a-z, 0-9, _ or -');
    }
    return problems;
  }

  static final RegExp _envName = RegExp(r'^[a-z0-9][a-z0-9_-]{0,31}$');

  /// Returns [config] with out-of-range values clamped: `batchSize` to 1..50
  /// and `maxAttempts` to at least 1.
  static SealedTraceConfig clamp(SealedTraceConfig config) {
    final upload = config.uploadConfig;
    final batchSize = upload.batchSize.clamp(1, 50);
    final maxAttempts = upload.maxAttempts < 1 ? 1 : upload.maxAttempts;
    if (batchSize == upload.batchSize && maxAttempts == upload.maxAttempts) {
      return config;
    }
    return config.copyWith(
      uploadConfig: upload.copyWith(
        batchSize: batchSize,
        maxAttempts: maxAttempts,
      ),
    );
  }

  static bool _isValidBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    return uri != null &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        (uri.scheme == 'http' || uri.scheme == 'https');
  }

  static bool _looksLikePem(String value) {
    final text = value.trim();
    return text.startsWith('-----BEGIN ') &&
        text.contains('PUBLIC KEY-----') &&
        text.contains('-----END ');
  }
}
