import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/config/config_validator.dart';

const _pem = '-----BEGIN PUBLIC KEY-----\nabc\n-----END PUBLIC KEY-----';

const _valid = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj',
  apiKey: 'key',
  publicKeyPem: _pem,
  appName: 'app',
);

void main() {
  test('a valid config has no problems', () {
    expect(ConfigValidator.validate(_valid), isEmpty);
  });

  test('accepts PKCS#1 public key headers', () {
    final c = _valid.copyWith(
      publicKeyPem:
          '-----BEGIN RSA PUBLIC KEY-----\nabc\n-----END RSA PUBLIC KEY-----',
    );
    expect(ConfigValidator.validate(c), isEmpty);
  });

  test('accepts built-in and custom env names', () {
    for (final name in ['dev', 'staging', 'prod', 'qa', 'stage-2', 'uat_eu']) {
      expect(
        ConfigValidator.validate(_valid.copyWith(env: SealedTraceEnv(name))),
        isEmpty,
        reason: name,
      );
    }
  });

  test('rejects bad env names', () {
    for (final name in ['', 'Stage', '-dev', 'my env', 'a' * 33]) {
      expect(
        ConfigValidator.validate(_valid.copyWith(env: SealedTraceEnv(name))),
        ['env must be 1-32 chars of a-z, 0-9, _ or -'],
        reason: name,
      );
    }
  });

  test('reports empty identifiers', () {
    final c = _valid.copyWith(projectId: ' ', apiKey: '', appName: '');
    expect(ConfigValidator.validate(c), hasLength(3));
  });

  test('rejects bad base URLs', () {
    for (final url in ['', 'logs.example.com', 'ftp://x.com', 'https://']) {
      expect(
        ConfigValidator.validate(_valid.copyWith(baseUrl: url)),
        isNotEmpty,
        reason: url,
      );
    }
  });

  test('rejects non-PEM keys', () {
    for (final pem in ['', 'not a key', '-----BEGIN PRIVATE KEY-----']) {
      expect(
        ConfigValidator.validate(_valid.copyWith(publicKeyPem: pem)),
        isNotEmpty,
        reason: pem,
      );
    }
  });

  test('clamp bounds batchSize to 1..50 and maxAttempts to at least 1', () {
    var c = ConfigValidator.clamp(
      _valid.copyWith(
        uploadConfig: const UploadConfig(batchSize: 500, maxAttempts: 0),
      ),
    );
    expect(c.uploadConfig.batchSize, 50);
    expect(c.uploadConfig.maxAttempts, 1);

    c = ConfigValidator.clamp(
      _valid.copyWith(uploadConfig: const UploadConfig(batchSize: -3)),
    );
    expect(c.uploadConfig.batchSize, 1);
  });

  test('clamp returns the same instance when nothing changes', () {
    expect(identical(ConfigValidator.clamp(_valid), _valid), isTrue);
  });
}
