import 'dart:math';
import 'dart:typed_data';

import 'gcm.dart';
import 'public_key_parser.dart';
import 'rsa_oaep.dart';

/// The output of AES-256-GCM encryption, with the tag split off.
class AesGcmResult {
  /// Creates a result.
  const AesGcmResult(this.ciphertext, this.tag);

  /// Ciphertext, the same length as the plaintext.
  final Uint8List ciphertext;

  /// The 16-byte authentication tag.
  final Uint8List tag;
}

/// Input for one AES-256-GCM encryption. Sendable across isolates.
class AesGcmJob {
  /// Creates a job.
  const AesGcmJob(this.key, this.iv, this.plaintext);

  /// 32-byte key.
  final Uint8List key;

  /// 12-byte nonce.
  final Uint8List iv;

  /// Data to encrypt.
  final Uint8List plaintext;
}

/// Encrypts [job] with AES-256-GCM and no additional authenticated data.
///
/// A top-level function so it can run in a background isolate.
Future<AesGcmResult> runAesGcm(AesGcmJob job) async {
  final (ciphertext, tag) = AesGcm256.encrypt(
    key: job.key,
    iv: job.iv,
    plaintext: job.plaintext,
  );
  return AesGcmResult(ciphertext, tag);
}

/// The primitives the envelope sealer needs. Replaceable in tests.
abstract interface class CryptoBackend {
  /// [length] cryptographically secure random bytes.
  Uint8List randomBytes(int length);

  /// AES-256-GCM encryption with no additional authenticated data.
  Future<AesGcmResult> aesGcmEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  });

  /// AES-256-GCM on the calling thread, for the page-exit path where nothing
  /// asynchronous is guaranteed to finish.
  AesGcmResult aesGcmEncryptSync({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  });

  /// RSA-OAEP (SHA-256, MGF1-SHA-256, empty label) encryption of [data].
  Uint8List rsaOaepWrap(RsaPublicKeyData key, Uint8List data);
}

/// Runs an [AesGcmJob] somewhere other than the calling isolate.
typedef AesGcmOffload = Future<AesGcmResult> Function(AesGcmJob job);

/// The production backend, built on this package's own AES-256-GCM and
/// RSA-OAEP (hashing comes from the `crypto` package).
///
/// Payloads larger than [offloadThresholdBytes] are encrypted through
/// [offload] when one is supplied.
class DefaultCryptoBackend implements CryptoBackend {
  /// Creates the backend.
  DefaultCryptoBackend({
    this.offload,
    this.offloadThresholdBytes = 8 * 1024,
    Random? random,
  }) : _random = random ?? Random.secure();

  /// Optional hook that runs large AES jobs off the calling isolate.
  final AesGcmOffload? offload;

  /// Payload size above which [offload] is used.
  final int offloadThresholdBytes;

  final Random _random;

  @override
  Uint8List randomBytes(int length) {
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _random.nextInt(256);
    }
    return bytes;
  }

  @override
  Future<AesGcmResult> aesGcmEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) {
    final job = AesGcmJob(key, iv, plaintext);
    final offload = this.offload;
    if (offload != null && plaintext.length > offloadThresholdBytes) {
      return offload(job);
    }
    return runAesGcm(job);
  }

  @override
  AesGcmResult aesGcmEncryptSync({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) {
    final (ciphertext, tag) = AesGcm256.encrypt(
      key: key,
      iv: iv,
      plaintext: plaintext,
    );
    return AesGcmResult(ciphertext, tag);
  }

  @override
  Uint8List rsaOaepWrap(RsaPublicKeyData key, Uint8List data) =>
      RsaOaep.encrypt(key, data, randomBytes(RsaOaep.seedLength));
}
