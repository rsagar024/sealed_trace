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

  group('cleartext http baseUrl (H1)', () {
    String problemFor(String env) =>
        'baseUrl must use https outside dev/local envs (got http with env '
        '"$env"); set allowInsecureHttp: true to override';

    test('rejected in prod (default), staging and custom envs', () {
      final http = _valid.copyWith(baseUrl: 'http://logs.example.com');
      expect(ConfigValidator.validate(http), [problemFor('prod')]);
      for (final name in ['staging', 'qa']) {
        expect(
          ConfigValidator.validate(http.copyWith(env: SealedTraceEnv(name))),
          [problemFor(name)],
          reason: name,
        );
      }
    });

    test('rejected regardless of scheme case', () {
      expect(
        ConfigValidator.validate(
          _valid.copyWith(baseUrl: 'HTTP://LOGS.example.com'),
        ),
        [problemFor('prod')],
      );
    });

    test('accepted in dev and local envs', () {
      for (final name in ['dev', 'local']) {
        expect(
          ConfigValidator.validate(
            _valid.copyWith(
              baseUrl: 'http://10.0.2.2:8080',
              env: SealedTraceEnv(name),
            ),
          ),
          isEmpty,
          reason: name,
        );
      }
    });

    test('accepted anywhere with allowInsecureHttp: true', () {
      expect(
        ConfigValidator.validate(
          _valid.copyWith(
            baseUrl: 'http://logs.example.com',
            allowInsecureHttp: true,
          ),
        ),
        isEmpty,
      );
    });

    test('https is accepted in every env', () {
      for (final name in ['dev', 'local', 'staging', 'prod', 'qa']) {
        expect(
          ConfigValidator.validate(_valid.copyWith(env: SealedTraceEnv(name))),
          isEmpty,
          reason: name,
        );
      }
    });

    test('allowInsecureHttp defaults to false and survives copyWith', () {
      expect(_valid.allowInsecureHttp, isFalse);
      final c = _valid.copyWith(allowInsecureHttp: true);
      expect(c.allowInsecureHttp, isTrue);
      expect(c, isNot(_valid));
      expect(c.copyWith(appName: 'x').allowInsecureHttp, isTrue);
    });
  });

  test(
    'rejects a projectId with control characters (M1: it is in the AAD)',
    () {
      for (final id in ['proj\nx', 'proj\rx', 'proj\tx', 'p\u0000']) {
        expect(ConfigValidator.validate(_valid.copyWith(projectId: id)), [
          'projectId must not contain control characters',
        ], reason: id);
      }
    },
  );

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
