import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';

void main() {
  test('MaskConfig defaults', () {
    const c = MaskConfig();
    expect(c.extraKeys, isEmpty);
    expect(c.extraPatterns, isEmpty);
    expect(c.extraHeaderDenylist, isEmpty);
    expect(c.useDefaultKeys, isTrue);
    expect(c.useDefaultPatterns, isTrue);
    expect(c.replacement, '***');
  });

  test('UploadConfig defaults match the spec', () {
    const c = UploadConfig();
    expect(c.interval, const Duration(minutes: 15));
    expect(c.sizeThresholdEvents, 200);
    expect(c.sizeThresholdBytes, 256 * 1024);
    expect(c.maxAttempts, 5);
    expect(c.batchSize, 50);
    expect(c.requestTimeout, const Duration(seconds: 30));
    expect(c.backoffBase, const Duration(seconds: 5));
    expect(c.uploadOnResume, isTrue);
    expect(c.uploadOnConnectivityRestored, isTrue);
  });

  test('RetentionConfig defaults match the spec', () {
    const c = RetentionConfig();
    expect(c.maxEvents, 10000);
    expect(c.maxAgeDays, 30);
    expect(c.maxSizeBytes, 50 * 1024 * 1024);
    expect(c.purgeInterval, const Duration(hours: 1));
    expect(c.deadLetterTtl, const Duration(days: 7));
  });

  test('NetworkLogConfig defaults match the spec', () {
    const c = NetworkLogConfig();
    expect(c.enabled, isTrue);
    expect(c.maxBodyChars, 20000);
    expect(c.hostAllowlist, isEmpty);
    expect(c.captureRequestBody, isTrue);
    expect(c.captureResponseBody, isTrue);
  });

  const base = SealedTraceConfig(
    baseUrl: 'https://example.com',
    projectId: 'p',
    apiKey: 'k',
    publicKeyPem: 'pem',
    appName: 'app',
  );

  test('SealedTraceConfig defaults', () {
    expect(base.env, SealedTraceEnv.prod);
    expect(base.minLevel, LogLevel.verbose);
    expect(base.enabled, isTrue);
    expect(base.verboseInternalLogs, isFalse);
    expect(base.databaseDirectory, isNull);
    expect(base.sendUserDisplayName, isTrue);
    expect(base.maskConfig.maskUserName, isFalse);
    expect(base.maskConfig, const MaskConfig());
    expect(base.uploadConfig, const UploadConfig());
    expect(base.retentionConfig, const RetentionConfig());
    expect(base.networkLogConfig, const NetworkLogConfig());
  });

  test('copyWith replaces only the given fields', () {
    final c = base.copyWith(minLevel: LogLevel.warning, enabled: false);
    expect(c.minLevel, LogLevel.warning);
    expect(c.enabled, isFalse);
    expect(c.baseUrl, base.baseUrl);
    expect(c.uploadConfig, base.uploadConfig);
    expect(
      base.copyWith(sendUserDisplayName: false).sendUserDisplayName,
      isFalse,
    );
  });

  test('equality and hashCode are value based', () {
    expect(base.copyWith(), base);
    expect(base.copyWith().hashCode, base.hashCode);
    expect(base.copyWith(appName: 'other'), isNot(base));
    expect(base.copyWith(sendUserDisplayName: false), isNot(base));
    expect(const MaskConfig(maskUserName: true), isNot(const MaskConfig()));
    expect(
      const MaskConfig().copyWith(maskUserName: true),
      const MaskConfig(maskUserName: true),
    );
    expect(
      const MaskConfig(extraKeys: ['a']),
      const MaskConfig(extraKeys: ['a']),
    );
    expect(
      const NetworkLogConfig(hostAllowlist: ['a.com']),
      isNot(const NetworkLogConfig(hostAllowlist: ['b.com'])),
    );
  });

  test('toString never contains the API key', () {
    final c = base.copyWith(apiKey: 'super-secret-key');
    expect(c.toString(), isNot(contains('super-secret-key')));
  });
}
