import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import '../crypto/der.dart';

/// Public-key pins in the `UploadConfig.pinnedSpkiSha256` format: the
/// base64 SHA-256 of a certificate's DER `SubjectPublicKeyInfo`, the same
/// value HPKP and OkHttp use. An optional `sha256/` prefix is accepted.
///
/// Compute one with:
/// `openssl x509 -in cert.pem -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary | openssl base64`
abstract final class SpkiPin {
  /// [pin] without its optional `sha256/` prefix and surrounding spaces.
  static String normalize(String pin) {
    final trimmed = pin.trim();
    return trimmed.startsWith('sha256/') ? trimmed.substring(7) : trimmed;
  }

  /// Whether [pin] is base64 for exactly 32 bytes.
  static bool isValid(String pin) {
    try {
      return base64.decode(normalize(pin)).length == 32;
    } on FormatException {
      return false;
    }
  }

  /// The pin of the certificate [certificateDer]. Throws [FormatException]
  /// if it is not an X.509 certificate.
  static String of(Uint8List certificateDer) =>
      base64.encode(sha256.convert(subjectPublicKeyInfo(certificateDer)).bytes);

  /// The DER-encoded `SubjectPublicKeyInfo` inside [certificateDer].
  ///
  /// `Certificate ::= SEQUENCE { tbsCertificate, ... }` and
  /// `TBSCertificate ::= SEQUENCE { [0] version OPTIONAL, serialNumber,
  /// signature, issuer, validity, subject, subjectPublicKeyInfo, ... }`.
  static Uint8List subjectPublicKeyInfo(Uint8List certificateDer) {
    final certificate = readDerElement(certificateDer);
    if (certificate.tag != 0x30 || certificate.end != certificateDer.length) {
      throw const FormatException('Not a DER certificate');
    }
    final tbs = readDerElement(certificate.content);
    if (tbs.tag != 0x30) throw const FormatException('No TBSCertificate');

    final body = tbs.content;
    var offset = 0;
    var index = 0;
    var first = true;
    while (offset < body.length) {
      final element = readDerElement(body, offset);
      final start = offset;
      offset = element.end;
      if (first) {
        first = false;
        if (element.tag == 0xA0) continue; // explicit [0] version
      }
      if (index == 5) {
        if (element.tag != 0x30) {
          throw const FormatException('Malformed SubjectPublicKeyInfo');
        }
        return Uint8List.fromList(body.sublist(start, element.end));
      }
      index++;
    }
    throw const FormatException('No SubjectPublicKeyInfo');
  }
}
