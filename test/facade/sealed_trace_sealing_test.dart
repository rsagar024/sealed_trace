import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/crypto/crypto_backend.dart';
import 'package:sealed_trace/src/event/sealing_batch_handler.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';

import '../helpers/envelope_opener.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _config = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj-1',
  apiKey: 'key',
  publicKeyPem: testPublicKeySpki,
  appName: 'app',
);

late List<SealedEnvelope> envelopes;

Future<void> _init({
  SealedTraceConfig config = _config,
  CryptoBackend? backend,
  EnvelopeSink? envelopeSink,
}) async {
  SealTestHooks.install(
    envelopes: envelopes,
    backend: backend,
    envelopeSink: envelopeSink,
  );
  await SealedTrace.init(config);
}

/// Builds the test overrides in one place.
class SealTestHooks {
  static void install({
    required List<SealedEnvelope> envelopes,
    CryptoBackend? backend,
    EnvelopeSink? envelopeSink,
  }) {
    SealedTrace.debugOverrides = RuntimeOverrides(
      disableUploads: true,
      storage: MemoryStorageAdapter(),
      lifecycle: FakeLifecycle(),
      deviceContext: testDevice,
      cryptoBackend: backend,
      envelopeSink:
          envelopeSink ??
          (envelope) async {
            envelopes.add(envelope);
          },
    );
  }
}

class _FailingBackend extends DefaultCryptoBackend {
  @override
  Future<AesGcmResult> aesGcmEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) => Future.error(StateError('crypto unavailable'));
}

void main() {
  setUp(() async {
    await SealedTrace.dispose();
    SealedTrace.onException = null;
    envelopes = [];
  });

  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.debugOverrides = null;
    SealedTrace.onException = null;
  });

  group('the public key is validated at init', () {
    final bad = <String, String>{
      '1024-bit key': testPublicKey1024,
      '3072-bit key': testPublicKey3072,
      'EC key': testPublicKeyEc,
      'private key': testPrivateKeyPkcs8,
      'garbage between PEM markers':
          '-----BEGIN PUBLIC KEY-----\nAAAA\n-----END PUBLIC KEY-----',
    };
    bad.forEach((name, pem) {
      test(name, () async {
        final errors = <Object>[];
        SealedTrace.onException = (e, _) => errors.add(e);
        await _init(config: _config.copyWith(publicKeyPem: pem));

        expect(SealedTrace.isInitialized, isFalse);
        expect(errors, hasLength(1));
        expect(errors.single, isA<StateError>());
        expect(errors.single.toString(), contains('publicKeyPem'));
        // The report must not echo key material.
        expect(errors.single.toString(), isNot(contains('MII')));
        SealedTrace.i('t', 'm');
        expect(SealedTrace.diagnostics.eventsAccepted, 0);
      });
    });

    test('a disabled config never parses the key', () async {
      await _init(
        config: _config.copyWith(
          enabled: false,
          publicKeyPem: testPublicKey1024,
        ),
      );
      expect(SealedTrace.isInitialized, isTrue);
    });

    test('PKCS#1 keys are accepted', () async {
      await _init(config: _config.copyWith(publicKeyPem: testPublicKeyPkcs1));
      expect(SealedTrace.isInitialized, isTrue);
    });
  });

  test(
    'a logged batch is sealed, and only ciphertext leaves the sealer',
    () async {
      await _init();
      SealedTrace.setUser('user-42');
      SealedTrace.i(
        'auth',
        'login for asha@example.com',
        meta: {'password': 'hunter2', 'city': 'Pune'},
      );
      SealedTrace.e('auth', 'card 4111111111111111 declined');
      await SealedTrace.flush();

      expect(envelopes, hasLength(1));
      final envelope = envelopes.single;
      expect(envelope.projectId, 'proj-1');
      expect(envelope.eventCount, 2);
      expect(envelope.seqMin, 1);
      expect(envelope.seqMax, 2);
      expect(envelope.topLevels, 'info,error');

      final plaintext = await openEnvelope(envelope);
      final events = jsonDecode(plaintext) as List;
      expect(events, hasLength(2));
      expect((events[0] as Map)['message'], 'login for ***');
      expect(((events[0] as Map)['metadata'] as Map)['password'], '***');
      expect((events[1] as Map)['message'], 'card *** declined');

      // Nothing the device holds in the clear mentions the secrets.
      final everything = jsonEncode(envelope.toWireJson());
      for (final secret in [
        'asha@example.com',
        'hunter2',
        '4111111111111111',
      ]) {
        expect(everything, isNot(contains(secret)));
        expect(plaintext, isNot(contains(secret)));
      }
      expect(envelope.topLevels, isNot(contains('@')));
    },
  );

  test('a large event goes through the real isolate offload', () async {
    await _init();
    SealedTrace.i('big', 'x' * 20000);
    await SealedTrace.flush();
    expect(envelopes, hasLength(1));
    final events = jsonDecode(await openEnvelope(envelopes.single)) as List;
    expect(((events.single as Map)['message'] as String).length, 20000);
  });

  test('successive batches get distinct batch ids and ivs', () async {
    await _init();
    SealedTrace.i('t', 'a');
    await SealedTrace.flush();
    SealedTrace.i('t', 'b');
    await SealedTrace.flush();
    expect(envelopes, hasLength(2));
    expect(envelopes[0].batchId, isNot(envelopes[1].batchId));
    expect(envelopes[0].iv, isNot(envelopes[1].iv));
  });

  group('fail closed', () {
    test('a failing backend drops the batch and reports it', () async {
      final errors = <Object>[];
      SealedTrace.onException = (e, _) => errors.add(e);
      await _init(backend: _FailingBackend());

      SealedTrace.f('t', 'secret asha@example.com');
      await SealedTrace.flush();

      expect(envelopes, isEmpty);
      expect(errors, isNotEmpty);
      final d = SealedTrace.diagnostics;
      expect(d.sealFailures, 1);
      expect(d.internalExceptions, greaterThan(0));
      expect(errors.join(), isNot(contains('asha@example.com')));
    });

    test('later batches still seal after a failure', () async {
      var fail = true;
      final backend = _FlakyBackend(() => fail);
      await _init(backend: backend);

      SealedTrace.f('t', 'first');
      await SealedTrace.flush();
      fail = false;
      SealedTrace.f('t', 'second');
      await SealedTrace.flush();

      expect(envelopes, hasLength(1));
      expect(SealedTrace.diagnostics.sealFailures, 1);
    });

    test('a throwing envelope sink never reaches the caller', () async {
      final errors = <Object>[];
      SealedTrace.onException = (e, _) => errors.add(e);
      await _init(envelopeSink: (_) async => throw StateError('disk full'));

      expect(() => SealedTrace.f('t', 'm'), returnsNormally);
      await SealedTrace.flush();
      expect(errors, isNotEmpty);
    });
  });

  test(
    'logging stays fast with sealing wired in (average under 1 ms)',
    () async {
      await _init();
      const calls = 5000;
      final watch = Stopwatch()..start();
      for (var i = 0; i < calls; i++) {
        SealedTrace.i(
          'bench',
          'event $i for asha@example.com',
          meta: {'phone': '+91 98765 43210', 'i': i},
        );
      }
      watch.stop();
      final perCall = watch.elapsedMicroseconds / calls;
      // ignore: avoid_print
      print(
        'SealedTrace.i with sealing wired: '
        '${perCall.toStringAsFixed(1)} µs per call',
      );
      expect(perCall, lessThan(1000));
      await SealedTrace.flush();
      expect(envelopes, isNotEmpty);
    },
  );

  test(
    'sealing a full 25-event batch takes a measurable, small time',
    () async {
      await _init();
      for (var i = 0; i < 25; i++) {
        SealedTrace.i('t', 'event $i', meta: {'i': i});
      }
      final watch = Stopwatch()..start();
      await SealedTrace.flush();
      watch.stop();
      // ignore: avoid_print
      print(
        'Sealing and delivering 25 events: ${watch.elapsedMilliseconds} ms',
      );
      expect(envelopes.fold<int>(0, (n, e) => n + e.eventCount), 25);
      expect(watch.elapsedMilliseconds, lessThan(2000));
    },
  );
}

class _FlakyBackend extends DefaultCryptoBackend {
  _FlakyBackend(this._shouldFail);
  final bool Function() _shouldFail;

  @override
  Future<AesGcmResult> aesGcmEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) {
    if (_shouldFail()) return Future.error(StateError('flaky'));
    return super.aesGcmEncrypt(key: key, iv: iv, plaintext: plaintext);
  }
}
