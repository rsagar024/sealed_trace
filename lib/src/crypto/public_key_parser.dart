import 'dart:convert';
import 'dart:typed_data';

import 'der.dart';

/// The modulus and public exponent of an RSA public key.
class RsaPublicKeyData {
  /// Creates key data.
  const RsaPublicKeyData(this.modulus, this.exponent);

  /// The modulus `n`.
  final BigInt modulus;

  /// The public exponent `e`.
  final BigInt exponent;
}

/// Parses the project's RSA public key from PEM.
///
/// Accepts SPKI (`BEGIN PUBLIC KEY`) and PKCS#1 (`BEGIN RSA PUBLIC KEY`).
/// Only 2048-bit keys are accepted, because the envelope algorithm is fixed to
/// RSA-OAEP-2048.
abstract final class PublicKeyParser {
  /// The required modulus size in bits.
  static const int requiredModulusBits = 2048;

  // DER content of the rsaEncryption OID 1.2.840.113549.1.1.1.
  static const List<int> _rsaEncryptionOid = <int>[
    0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, //
  ];

  static final RegExp _pem = RegExp(
    r'^-----BEGIN (PUBLIC KEY|RSA PUBLIC KEY)-----([\s\S]*?)'
    r'-----END (PUBLIC KEY|RSA PUBLIC KEY)-----$',
  );

  /// Parses [pem]. Throws [FormatException] with a reason that never contains
  /// key material.
  static RsaPublicKeyData parse(String pem) {
    final match = _pem.firstMatch(pem.trim());
    if (match == null || match[1] != match[3]) {
      throw const FormatException('Not a PEM RSA public key');
    }
    final Uint8List der;
    try {
      der = base64.decode(match[2]!.replaceAll(RegExp(r'\s'), ''));
    } on FormatException {
      throw const FormatException('Invalid base64 in public key');
    }

    final top = readDerElement(der);
    if (top.tag != 0x30 || top.end != der.length) {
      throw const FormatException('Invalid public key structure');
    }

    final RsaPublicKeyData key;
    if (match[1] == 'PUBLIC KEY') {
      key = _fromSpki(top);
    } else {
      key = _fromPkcs1(top);
    }
    _validate(key);
    return key;
  }

  static RsaPublicKeyData _fromSpki(DerElement sequence) {
    final children = readDerChildren(sequence);
    if (children.length != 2 ||
        children[0].tag != 0x30 ||
        children[1].tag != 0x03) {
      throw const FormatException('Invalid SubjectPublicKeyInfo');
    }
    final algorithm = readDerChildren(children[0]);
    if (algorithm.isEmpty ||
        algorithm.first.tag != 0x06 ||
        !_equals(algorithm.first.content, _rsaEncryptionOid)) {
      throw const FormatException('Not an RSA key');
    }
    final bits = children[1].content;
    if (bits.isEmpty || bits[0] != 0) {
      throw const FormatException('Invalid public key bit string');
    }
    final inner = Uint8List.sublistView(bits, 1);
    final element = readDerElement(inner);
    if (element.tag != 0x30 || element.end != inner.length) {
      throw const FormatException('Invalid RSA public key structure');
    }
    return _fromPkcs1(element);
  }

  static RsaPublicKeyData _fromPkcs1(DerElement sequence) {
    final parts = readDerChildren(sequence);
    if (parts.length != 2) {
      throw const FormatException('Invalid RSAPublicKey');
    }
    return RsaPublicKeyData(readDerInteger(parts[0]), readDerInteger(parts[1]));
  }

  static void _validate(RsaPublicKeyData key) {
    if (key.modulus.bitLength != requiredModulusBits) {
      throw FormatException(
        'RSA key must be $requiredModulusBits bits, '
        'got ${key.modulus.bitLength}',
      );
    }
    if (key.exponent < BigInt.from(3) ||
        key.exponent.isEven ||
        key.exponent.bitLength > 32) {
      throw const FormatException('Unsupported RSA public exponent');
    }
  }

  static bool _equals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
