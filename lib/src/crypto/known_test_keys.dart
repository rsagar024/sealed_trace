/// Guards against shipping the SDK's own test key (I2).
///
/// The repository's tests and vectors use an RSA key pair whose **private
/// key is public** (`test/helpers/test_keys.dart`, `test/vectors/`). Logs
/// sealed to it can be read by anyone, so release builds refuse it.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'public_key_parser.dart';

/// SHA-256 of the big-endian modulus of the sealed_trace test key.
const String _testKeyModulusSha256 =
    '95e8ffd9d27fdb2f3f041af76e2ccd359ec2869f1bfe1b6e813a4b1089aa56d7';

/// Whether [key] is the sealed_trace test key, whose private key is public.
bool isKnownTestKey(RsaPublicKeyData key) =>
    sha256.convert(modulusBytes(key)).toString() == _testKeyModulusSha256;

/// The modulus of [key] as unsigned big-endian bytes, `ceil(bits / 8)` long.
Uint8List modulusBytes(RsaPublicKeyData key) {
  final length = (key.modulus.bitLength + 7) >> 3;
  final out = Uint8List(length);
  var n = key.modulus;
  final mask = BigInt.from(0xff);
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (n & mask).toInt();
    n >>= 8;
  }
  return out;
}

/// The problem with using [key] for sealing, or null when there is none.
///
/// The test key is refused only when [releaseMode] is true (by default,
/// in Flutter release builds), so debug runs and tests keep working.
String? testKeyProblem(RsaPublicKeyData key, {required bool releaseMode}) {
  if (!releaseMode || !isKnownTestKey(key)) return null;
  return 'publicKeyPem is the sealed_trace test key, whose private key is '
      'public; use your project key from the SealedTrace console';
}
