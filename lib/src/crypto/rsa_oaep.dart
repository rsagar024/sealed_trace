import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'public_key_parser.dart';

/// RSA-OAEP encryption (RFC 8017, section 7.1) with SHA-256 as both the label
/// hash and the MGF1 hash, and an empty label.
///
/// Encryption only: the device never holds a private key. Written for this
/// package and not audited; `BigInt.modPow` is not constant-time.
abstract final class RsaOaep {
  /// Bytes in a SHA-256 digest.
  static const int hashLength = 32;

  /// Bytes in the random seed.
  static const int seedLength = hashLength;

  /// The longest message a key with a modulus of [modulusBytes] can carry.
  static int maxMessageLength(int modulusBytes) =>
      modulusBytes - 2 * hashLength - 2;

  /// Encrypts [message] for [key] using the random [seed] (32 bytes).
  ///
  /// The seed must come from a secure random source and must not be reused.
  /// The result is as long as the modulus (256 bytes for RSA-2048).
  static Uint8List encrypt(
    RsaPublicKeyData key,
    Uint8List message,
    Uint8List seed,
  ) {
    final k = (key.modulus.bitLength + 7) >> 3;
    if (seed.length != seedLength) {
      throw ArgumentError.value(seed.length, 'seed.length', 'Needs 32 bytes');
    }
    if (k < 2 * hashLength + 2) {
      throw ArgumentError.value(k, 'modulus bytes', 'RSA key is too small');
    }
    if (message.length > maxMessageLength(k)) {
      throw ArgumentError.value(
        message.length,
        'message.length',
        'Too long for this key (at most ${maxMessageLength(k)} bytes)',
      );
    }

    // DB = lHash || PS (zeros) || 0x01 || M, where lHash is SHA-256("").
    final dbLength = k - hashLength - 1;
    final db = Uint8List(dbLength);
    db.setRange(0, hashLength, sha256.convert(const <int>[]).bytes);
    db[dbLength - message.length - 1] = 0x01;
    db.setRange(dbLength - message.length, dbLength, message);

    final maskedDb = _xor(db, _mgf1(seed, dbLength));
    final maskedSeed = _xor(seed, _mgf1(maskedDb, hashLength));

    // EM = 0x00 || maskedSeed || maskedDB.
    final em = Uint8List(k)
      ..setRange(1, 1 + hashLength, maskedSeed)
      ..setRange(1 + hashLength, k, maskedDb);

    final m = _toBigInt(em);
    if (m >= key.modulus) {
      throw ArgumentError('Encoded message is not smaller than the modulus');
    }
    return _toBytes(m.modPow(key.exponent, key.modulus), k);
  }

  /// MGF1 (RFC 8017, appendix B.2.1) with SHA-256.
  static Uint8List _mgf1(Uint8List seed, int length) {
    final out = Uint8List(length);
    var written = 0;
    for (var counter = 0; written < length; counter++) {
      final input = Uint8List(seed.length + 4)
        ..setRange(0, seed.length, seed)
        ..[seed.length] = (counter >>> 24) & 0xff
        ..[seed.length + 1] = (counter >>> 16) & 0xff
        ..[seed.length + 2] = (counter >>> 8) & 0xff
        ..[seed.length + 3] = counter & 0xff;
      final digest = sha256.convert(input).bytes;
      for (var i = 0; i < digest.length && written < length; i++) {
        out[written++] = digest[i];
      }
    }
    return out;
  }

  static Uint8List _xor(Uint8List a, Uint8List b) {
    final out = Uint8List(a.length);
    for (var i = 0; i < a.length; i++) {
      out[i] = a[i] ^ b[i];
    }
    return out;
  }

  static BigInt _toBigInt(Uint8List bytes) {
    var value = BigInt.zero;
    for (final byte in bytes) {
      value = (value << 8) | BigInt.from(byte);
    }
    return value;
  }

  static Uint8List _toBytes(BigInt value, int length) {
    final out = Uint8List(length);
    var rest = value;
    final mask = BigInt.from(0xff);
    for (var i = length - 1; i >= 0; i--) {
      out[i] = (rest & mask).toInt();
      rest >>= 8;
    }
    return out;
  }
}
