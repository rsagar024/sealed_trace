import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/crypto/app_aes_gcm.dart';
import 'package:sealed_trace/src/crypto/aes_gcm_platform.dart';
import 'package:sealed_trace/src/crypto/crypto_backend.dart';
import 'package:sealed_trace/src/crypto/gcm.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

/// A correct "platform" cipher: the built-in one behind the public type.
int correctCalls = 0;
Future<({Uint8List ciphertext, Uint8List tag})> correct(
  Uint8List key,
  Uint8List iv,
  Uint8List plaintext,
  Uint8List aad,
) async {
  correctCalls++;
  final (ciphertext, tag) = AesGcm256.encrypt(
    key: key,
    iv: iv,
    plaintext: plaintext,
    aad: aad,
  );
  return (ciphertext: ciphertext, tag: tag);
}

/// Gets the tag wrong, e.g. a cipher that ignores the additional data.
Future<({Uint8List ciphertext, Uint8List tag})> ignoresAad(
  Uint8List key,
  Uint8List iv,
  Uint8List plaintext,
  Uint8List aad,
) => correct(key, iv, plaintext, Uint8List(0));

Future<({Uint8List ciphertext, Uint8List tag})> throws(
  Uint8List key,
  Uint8List iv,
  Uint8List plaintext,
  Uint8List aad,
) async => throw StateError('no platform crypto');

Future<({Uint8List ciphertext, Uint8List tag})> shortTag(
  Uint8List key,
  Uint8List iv,
  Uint8List plaintext,
  Uint8List aad,
) async {
  final r = await correct(key, iv, plaintext, aad);
  return (ciphertext: r.ciphertext, tag: Uint8List.sublistView(r.tag, 0, 8));
}

Future<({Uint8List ciphertext, Uint8List tag})> hangs(
  Uint8List key,
  Uint8List iv,
  Uint8List plaintext,
  Uint8List aad,
) => Completer<({Uint8List ciphertext, Uint8List tag})>().future;

const _config = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj-1',
  apiKey: 'key',
  publicKeyPem: testPublicKeySpki,
  appName: 'app',
);

void main() {
  setUp(() => correctCalls = 0);

  group('L5: self-test of an app-supplied AES-GCM', () {
    test('a correct cipher passes', () async {
      expect(await selfTestAesGcm(correct), isTrue);
      expect(correctCalls, 5, reason: 'five known-answer cases');
    });

    test('wrong output, a throw, a short tag or a hang fail', () async {
      expect(await selfTestAesGcm(ignoresAad), isFalse);
      expect(await selfTestAesGcm(throws), isFalse);
      expect(await selfTestAesGcm(shortTag), isFalse);
      expect(
        await selfTestAesGcm(hangs, timeout: const Duration(milliseconds: 50)),
        isFalse,
      );
    });
  });

  group('L5: the app cipher offload', () {
    final job = AesGcmJob(
      Uint8List.fromList(List.generate(32, (i) => i)),
      Uint8List.fromList(List.generate(12, (i) => i + 1)),
      Uint8List.fromList(utf8.encode('hello platform crypto')),
      Uint8List.fromList(utf8.encode('header')),
    );

    test('uses the app cipher and matches the built-in one', () async {
      final errors = <Object>[];
      final out = await appAesGcmOffload(
        correct,
        onError: (e, _) => errors.add(e),
      )(job);
      final builtIn = await runAesGcm(job);
      expect(correctCalls, 1);
      expect(out.ciphertext, builtIn.ciphertext);
      expect(out.tag, builtIn.tag);
      expect(errors, isEmpty);
    });

    test('a failing or malformed call falls back and is reported', () async {
      for (final broken in [throws, shortTag]) {
        final errors = <Object>[];
        final out = await appAesGcmOffload(
          broken,
          onError: (e, _) => errors.add(e),
        )(job);
        final builtIn = await runAesGcm(job);
        expect(out.ciphertext, builtIn.ciphertext);
        expect(out.tag, builtIn.tag);
        expect(errors, hasLength(1));
      }
    });
  });

  group('L5: through init', () {
    late List<SealedEnvelope> envelopes;
    late List<Object> reported;

    setUp(() async {
      await SealedTrace.dispose();
      envelopes = [];
      reported = [];
      SealedTrace.onException = (e, _) => reported.add(e);
      SealedTrace.debugOverrides = RuntimeOverrides(
        disableUploads: true,
        storage: MemoryStorageAdapter(),
        lifecycle: FakeLifecycle(),
        deviceContext: testDevice,
        envelopeSink: (e) async => envelopes.add(e),
      );
    });

    tearDown(() async {
      await SealedTrace.dispose();
      SealedTrace.debugOverrides = null;
      SealedTrace.onException = null;
    });

    test('an accepted cipher seals every batch, even small ones', () async {
      await SealedTrace.init(_config.copyWith(aesGcmEncryptor: correct));
      final afterSelfTest = correctCalls;
      SealedTrace.i('t', 'small batch');
      await SealedTrace.flush();
      expect(correctCalls, afterSelfTest + 1);
      expect(reported, isEmpty);
      expect(await openEnvelope(envelopes.single), contains('small batch'));
    });

    test(
      'a cipher that fails its self-test is reported and not used',
      () async {
        await SealedTrace.init(_config.copyWith(aesGcmEncryptor: ignoresAad));
        expect(SealedTrace.isInitialized, isTrue);
        expect(reported.single.toString(), contains('failed its self-test'));
        final afterSelfTest = correctCalls;
        SealedTrace.i('t', 'built-in cipher');
        await SealedTrace.flush();
        expect(correctCalls, afterSelfTest, reason: 'not called again');
        expect(await openEnvelope(envelopes.single), contains('built-in'));
      },
    );

    test('the field takes part in copyWith and equality', () {
      final a = _config.copyWith(aesGcmEncryptor: correct);
      expect(_config.aesGcmEncryptor, isNull);
      expect(a, _config.copyWith(aesGcmEncryptor: correct));
      expect(a, isNot(_config));
      expect(a.copyWith(appName: 'x').aesGcmEncryptor, isNotNull);
    });
  });

  test('native keeps the 8 KB isolate threshold', () {
    expect(platformOffloadThresholdBytes, 8 * 1024);
  });
}
