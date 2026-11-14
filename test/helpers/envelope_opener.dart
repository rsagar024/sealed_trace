import 'dart:convert';
import 'dart:typed_data';

import 'package:sealed_trace/src/crypto/der.dart';
import 'package:sealed_trace/src/crypto/gcm.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';

import 'rsa_oaep_decrypt.dart';
import 'test_keys.dart';

/// Modulus and private exponent of a PKCS#8 private key.
({BigInt modulus, BigInt privateExponent}) loadTestPrivateKey([
  String pem = testPrivateKeyPkcs8,
]) {
  final body = pem
      .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
      .replaceAll(RegExp(r'\s'), '');
  final der = base64.decode(body);
  final pkcs8 = readDerChildren(readDerElement(der));
  // PrivateKeyInfo: version, algorithm, OCTET STRING holding the PKCS#1 key.
  final pkcs1 = readDerChildren(readDerElement(pkcs8[2].content));
  // RSAPrivateKey: version, n, e, d, p, q, ...
  return (
    modulus: readDerInteger(pkcs1[1]),
    privateExponent: readDerInteger(pkcs1[3]),
  );
}

/// Unwraps an RSA-OAEP (SHA-256) wrapped key with the test private key.
Uint8List unwrapKey(Uint8List wrapped) {
  final key = loadTestPrivateKey();
  return oaepDecrypt(
    modulus: key.modulus,
    privateExponent: key.privateExponent,
    ciphertext: wrapped,
  );
}

/// AES-256-GCM decryption that verifies the tag. Throws if it does not match.
///
/// GCM decryption is counter mode plus a tag check, so this reuses the
/// encryptor: CTR is its own inverse, and re-encrypting the recovered plaintext
/// must reproduce the tag. It therefore shares code with the code under test;
/// the Node and OpenSSL runs are the independent check.
Uint8List gcmDecrypt({
  required Uint8List key,
  required Uint8List iv,
  required Uint8List ciphertext,
  required Uint8List tag,
  Uint8List? aad,
}) {
  final (plain, _) = AesGcm256.encrypt(key: key, iv: iv, plaintext: ciphertext);
  final (_, expected) = AesGcm256.encrypt(
    key: key,
    iv: iv,
    plaintext: plain,
    aad: aad,
  );
  var diff = tag.length ^ expected.length;
  for (var i = 0; i < tag.length && i < expected.length; i++) {
    diff |= tag[i] ^ expected[i];
  }
  if (diff != 0) throw StateError('GCM authentication failed');
  return plain;
}

/// Decrypts an envelope's fields. Throws if the tag does not verify.
Future<Uint8List> openFields({
  required Uint8List wrappedKey,
  required Uint8List iv,
  required Uint8List tag,
  required Uint8List ciphertext,
  required Uint8List aad,
}) async {
  final key = unwrapKey(wrappedKey);
  return gcmDecrypt(
    key: key,
    iv: iv,
    ciphertext: ciphertext,
    tag: tag,
    aad: aad,
  );
}

/// The AAD a server rebuilds from a wire envelope's clear header fields.
Uint8List wireAad(Map<String, dynamic> wire) => envelopeAad(
  projectId: wire['projectId'] as String,
  batchId: wire['batchId'] as String,
  createdAt: wire['createdAt'] as String,
  eventCount: wire['eventCount'] as int,
  algorithm: wire['alg'] as String,
);

/// Decrypts a [SealedEnvelope] to its plaintext JSON array text, without the
/// trailing padding spaces (L6). See [openEnvelopeRaw] for the padded text.
Future<String> openEnvelope(SealedEnvelope envelope) async =>
    _unpad(await openEnvelopeRaw(envelope));

/// The decrypted plaintext exactly as sealed, padding included.
Future<String> openEnvelopeRaw(SealedEnvelope envelope) async => utf8.decode(
  await openFields(
    wrappedKey: envelope.wrappedKey,
    iv: envelope.iv,
    tag: envelope.tag,
    ciphertext: envelope.ciphertext,
    aad: envelope.aad,
  ),
);

/// Decrypts a wire-format envelope map to its plaintext JSON array text,
/// without the trailing padding spaces.
Future<String> openWire(Map<String, dynamic> wire) async =>
    _unpad(await _openWireRaw(wire));

/// The `seq` of every event inside [envelope], read by decrypting it (the
/// clear index no longer records them, L6).
Future<List<int>> sealedSeqs(SealedEnvelope envelope) async => [
  for (final event in jsonDecode(await openEnvelope(envelope)) as List)
    (event as Map)['seq'] as int,
];

String _unpad(String text) {
  var end = text.length;
  while (end > 0 && text.codeUnitAt(end - 1) == 0x20) {
    end--;
  }
  return text.substring(0, end);
}

Future<String> _openWireRaw(Map<String, dynamic> wire) async => utf8.decode(
  await openFields(
    wrappedKey: base64.decode(wire['wrappedKey'] as String),
    iv: base64.decode(wire['iv'] as String),
    tag: base64.decode(wire['tag'] as String),
    ciphertext: base64.decode(wire['ciphertext'] as String),
    aad: wireAad(wire),
  ),
);
