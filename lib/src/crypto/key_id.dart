/// Key identifiers for envelope v3 (I3).
///
/// The `kid` of a project key is the first 16 bytes of the SHA-256 of its
/// canonical DER `SubjectPublicKeyInfo`, base64url without padding (22
/// characters). It is the same whether the app was given the key in SPKI or
/// PKCS#1 PEM, and matches what OpenSSL computes:
///
/// ```sh
/// openssl pkey -pubin -in key.pem -outform der \
///   | openssl dgst -sha256 -binary | head -c 16 \
///   | openssl base64 | tr '+/' '-_' | tr -d '='
/// ```
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'public_key_parser.dart';

/// Length of a `kid` in characters.
const int keyIdLength = 22;

/// The `kid` of [key]; see the library documentation.
String keyId(RsaPublicKeyData key) {
  final digest = sha256.convert(spkiDer(key)).bytes;
  return base64Url.encode(digest.sublist(0, 16)).replaceAll('=', '');
}

/// The canonical DER `SubjectPublicKeyInfo` of [key]: algorithm
/// `rsaEncryption` with NULL parameters, then the PKCS#1 `RSAPublicKey`.
Uint8List spkiDer(RsaPublicKeyData key) {
  final rsaPublicKey = _der(0x30, [
    ..._integer(key.modulus),
    ..._integer(key.exponent),
  ]);
  final algorithm = _der(0x30, [
    ..._der(0x06, _rsaEncryptionOid),
    ..._der(0x05, const []),
  ]);
  return Uint8List.fromList(
    _der(0x30, [
      ...algorithm,
      ..._der(0x03, [0x00, ...rsaPublicKey]),
    ]),
  );
}

/// The unsigned big-endian bytes of [value], `ceil(bitLength / 8)` long
/// (one zero byte for zero).
Uint8List unsignedBytes(BigInt value) {
  final length = value.bitLength == 0 ? 1 : (value.bitLength + 7) >> 3;
  final out = Uint8List(length);
  var n = value;
  final mask = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (n & mask).toInt();
    n >>= 8;
  }
  return out;
}

// DER content of the rsaEncryption OID 1.2.840.113549.1.1.1.
const List<int> _rsaEncryptionOid = <int>[
  0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, //
];

List<int> _integer(BigInt value) {
  final bytes = unsignedBytes(value);
  // A leading 0x00 keeps a value with its top bit set non-negative.
  return _der(0x02, [if (bytes[0] & 0x80 != 0) 0x00, ...bytes]);
}

List<int> _der(int tag, List<int> content) => [
  tag,
  ..._length(content.length),
  ...content,
];

List<int> _length(int length) {
  if (length < 0x80) return [length];
  final bytes = <int>[];
  for (var n = length; n > 0; n >>= 8) {
    bytes.insert(0, n & 0xff);
  }
  return [0x80 | bytes.length, ...bytes];
}
