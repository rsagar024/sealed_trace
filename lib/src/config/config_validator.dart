import 'sealed_trace_config.dart';

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
    if (!_envName.hasMatch(config.env.name)) {
      problems.add('env must be 1-32 chars of a-z, 0-9, _ or -');
    }
    return problems;
  }

  static final RegExp _controlChars = RegExp(r'[\x00-\x1f\x7f]');

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
