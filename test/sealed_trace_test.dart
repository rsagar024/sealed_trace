import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';

void main() {
  test('barrel exports the public API', () {
    expect(SealedTrace.isInitialized, isFalse);
    expect(LogLevel.values, hasLength(6));
    expect(SealedTraceEnv.prod.isProd, isTrue);
    expect(const SealedTraceEnv('qa').isProd, isFalse);
    expect(const SealedTraceEnv('dev'), SealedTraceEnv.dev);
    expect(
      const SealedTraceConfig(
        baseUrl: 'https://example.com',
        projectId: 'p',
        apiKey: 'k',
        publicKeyPem: 'pem',
        appName: 'app',
      ).env,
      SealedTraceEnv.prod,
    );
  });
}
