import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Test-only RSA-OAEP decryption (SHA-256, MGF1-SHA-256, empty label).
///
/// Written separately from the production encryptor so the two are not simply
/// mirror images, but it is still the same author and the same package; the
/// independent checks are the Node and OpenSSL runs.
Uint8List oaepDecrypt({
  required BigInt modulus,
  required BigInt privateExponent,
  required Uint8List ciphertext,
}) {
  final k = (modulus.bitLength + 7) >> 3;
  if (ciphertext.length != k) {
    throw StateError('Ciphertext has the wrong length');
  }
  final c = _toBigInt(ciphertext);
  if (c >= modulus) throw StateError('Ciphertext out of range');
  final em = _toBytes(c.modPow(privateExponent, modulus), k);

  const hLen = 32;
  if (em[0] != 0) throw StateError('OAEP decoding error (leading byte)');
  final maskedSeed = em.sublist(1, 1 + hLen);
  final maskedDb = em.sublist(1 + hLen);
  final seed = _xor(maskedSeed, _mgf1(maskedDb, hLen));
  final db = _xor(maskedDb, _mgf1(seed, k - hLen - 1));

  final expected = sha256.convert(const <int>[]).bytes;
  for (var i = 0; i < hLen; i++) {
    if (db[i] != expected[i]) throw StateError('OAEP decoding error (label)');
  }
  var i = hLen;
  while (i < db.length && db[i] == 0) {
    i++;
  }
  if (i == db.length || db[i] != 1) {
    throw StateError('OAEP decoding error (separator)');
  }
  return Uint8List.fromList(db.sublist(i + 1));
}

Uint8List _mgf1(Uint8List seed, int length) {
  final out = BytesBuilder();
  for (var counter = 0; out.length < length; counter++) {
    out.add(
      sha256.convert(<int>[
        ...seed,
        (counter >> 24) & 0xff,
        (counter >> 16) & 0xff,
        (counter >> 8) & 0xff,
        counter & 0xff,
      ]).bytes,
    );
  }
  return Uint8List.fromList(out.toBytes().sublist(0, length));
}

Uint8List _xor(Uint8List a, Uint8List b) =>
    Uint8List.fromList([for (var i = 0; i < a.length; i++) a[i] ^ b[i]]);

BigInt _toBigInt(Uint8List bytes) {
  var v = BigInt.zero;
  for (final b in bytes) {
    v = (v << 8) | BigInt.from(b);
  }
  return v;
}

Uint8List _toBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var rest = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (rest & BigInt.from(0xff)).toInt();
    rest >>= 8;
  }
  return out;
}
