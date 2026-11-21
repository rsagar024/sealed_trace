import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/crypto/known_test_keys.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

/// I2: the repository's test key (its private key is public) is refused in
/// release builds.
void main() {
  final testKey = PublicKeyParser.parse(testPublicKeySpki);
  final otherKey = PublicKeyParser.parse(otherPublicKeySpki);

  group('isKnownTestKey', () {
    test('recognizes the test key in both PEM forms', () {
      expect(isKnownTestKey(testKey), isTrue);
      expect(isKnownTestKey(PublicKeyParser.parse(testPublicKeyPkcs1)), isTrue);
    });

    test('does not flag another key', () {
      expect(isKnownTestKey(otherKey), isFalse);
    });

    test('modulusBytes is the 256-byte big-endian modulus', () {
      final bytes = modulusBytes(testKey);
      expect(bytes, hasLength(256));
      expect(bytes.first, isNonZero);
      var n = BigInt.zero;
      for (final b in bytes) {
        n = (n << 8) | BigInt.from(b);
      }
      expect(n, testKey.modulus);
    });
  });

  group('testKeyProblem', () {
    test('refuses the test key only in release mode', () {
      expect(testKeyProblem(testKey, releaseMode: true), contains('test key'));
      expect(testKeyProblem(testKey, releaseMode: false), isNull);
      expect(testKeyProblem(otherKey, releaseMode: true), isNull);
    });
  });

  group('SealedTrace.init', () {
    late List<Object> errors;

    Future<void> init(String pem, {required bool release}) async {
      SealedTrace.debugOverrides = RuntimeOverrides(
        disableUploads: true,
        storage: MemoryStorageAdapter(),
        lifecycle: FakeLifecycle(),
        deviceContext: testDevice,
        releaseMode: release,
      );
      await SealedTrace.init(
        SealedTraceConfig(
          baseUrl: 'https://logs.example.com',
          projectId: 'proj',
          apiKey: 'key',
          publicKeyPem: pem,
          appName: 'app',
        ),
      );
    }

    setUp(() async {
      await SealedTrace.dispose();
      errors = <Object>[];
      SealedTrace.onException = (e, _) => errors.add(e);
    });

    tearDown(() async {
      await SealedTrace.dispose();
      SealedTrace.debugOverrides = null;
      SealedTrace.onException = null;
    });

    test('a release build refuses the test key and stays disabled', () async {
      await init(testPublicKeySpki, release: true);
      expect(SealedTrace.isInitialized, isFalse);
      expect(errors, hasLength(1));
      expect('${errors.single}', contains('sealed_trace test key'));
    });

    test('a release build accepts another key', () async {
      await init(otherPublicKeySpki, release: true);
      expect(SealedTrace.isInitialized, isTrue);
      expect(errors, isEmpty);
    });

    test('a debug build still accepts the test key', () async {
      await init(testPublicKeySpki, release: false);
      expect(SealedTrace.isInitialized, isTrue);
      expect(errors, isEmpty);
    });
  });
}
