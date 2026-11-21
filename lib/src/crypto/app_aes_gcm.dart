import 'dart:async';
import 'dart:typed_data';

import '../config/sealed_trace_config.dart' show AesGcmEncryptor;
import 'crypto_backend.dart';
import 'gcm.dart';

/// Checks [encryptor] against the built-in cipher on known-answer cases:
/// empty and multi-block plaintext, with and without additional data.
/// Returns false if any output differs, a call throws, or it takes longer
/// than [timeout] in total. Never throws.
Future<bool> selfTestAesGcm(
  AesGcmEncryptor encryptor, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  Uint8List bytes(int n, int seed) =>
      Uint8List.fromList(List.generate(n, (i) => (i * 29 + seed) & 0xff));
  final cases = [(0, 0), (1, 0), (37, 13), (256, 0), (1000, 200)];
  try {
    return await Future(() async {
      for (final (plainLength, aadLength) in cases) {
        final key = bytes(32, plainLength + 1);
        final iv = bytes(12, aadLength + 7);
        final plain = bytes(plainLength, 3);
        final aad = bytes(aadLength, 5);
        final (ct, tag) = AesGcm256.encrypt(
          key: key,
          iv: iv,
          plaintext: plain,
          aad: aad,
        );
        final got = await encryptor(
          Uint8List.fromList(key),
          Uint8List.fromList(iv),
          Uint8List.fromList(plain),
          Uint8List.fromList(aad),
        );
        if (!_same(got.ciphertext, ct) || !_same(got.tag, tag)) return false;
      }
      return true;
    }).timeout(timeout);
  } catch (_) {
    return false;
  }
}

/// An offload that encrypts with [encryptor], checks the lengths, and falls
/// back to the built-in cipher (reporting through [onError]) if it fails.
AesGcmOffload appAesGcmOffload(
  AesGcmEncryptor encryptor, {
  required void Function(Object error, StackTrace stack) onError,
}) => (job) async {
  try {
    final out = await encryptor(
      job.key,
      job.iv,
      job.plaintext,
      job.aad ?? Uint8List(0),
    );
    if (out.ciphertext.length != job.plaintext.length ||
        out.tag.length != AesGcm256.tagSize) {
      throw StateError('aesGcmEncryptor returned unexpected lengths');
    }
    // Copies, in case the app reuses its buffers.
    return AesGcmResult(
      Uint8List.fromList(out.ciphertext),
      Uint8List.fromList(out.tag),
    );
  } catch (error, stack) {
    onError(error, stack);
    return runAesGcm(job);
  }
};

bool _same(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
