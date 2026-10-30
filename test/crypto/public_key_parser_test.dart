import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';

import '../helpers/test_keys.dart';

void _rejects(String pem, {String? reason}) {
  expect(
    () => PublicKeyParser.parse(pem),
    throwsA(isA<FormatException>()),
    reason: reason ?? pem,
  );
}

void main() {
  group('accepts valid keys', () {
    test('SPKI', () {
      final key = PublicKeyParser.parse(testPublicKeySpki);
      expect(key.modulus.bitLength, 2048);
      expect(key.exponent, BigInt.from(65537));
    });

    test('PKCS#1 gives the same key as SPKI', () {
      final spki = PublicKeyParser.parse(testPublicKeySpki);
      final pkcs1 = PublicKeyParser.parse(testPublicKeyPkcs1);
      expect(pkcs1.modulus, spki.modulus);
      expect(pkcs1.exponent, spki.exponent);
    });

    test('CRLF line endings', () {
      final crlf = testPublicKeySpki.replaceAll('\n', '\r\n');
      expect(PublicKeyParser.parse(crlf).modulus.bitLength, 2048);
    });

    test('no line breaks inside the body', () {
      final lines = testPublicKeySpki.trim().split('\n');
      final flat =
          '${lines.first}\n${lines.sublist(1, lines.length - 1).join()}'
          '\n${lines.last}';
      expect(PublicKeyParser.parse(flat).modulus.bitLength, 2048);
    });

    test('surrounding and inner whitespace', () {
      final padded = '\n\n  ${testPublicKeySpki.replaceAll('\n', '\n  ')}  \n';
      expect(PublicKeyParser.parse(padded).modulus.bitLength, 2048);
    });
  });

  group('rejects bad keys', () {
    test('empty and non-PEM text', () {
      _rejects('');
      _rejects('not a key');
      _rejects('-----BEGIN PUBLIC KEY-----');
    });

    test('a private key', () {
      _rejects(testPrivateKeyPkcs8, reason: 'private key');
    });

    test('mismatched header and footer', () {
      _rejects(
        testPublicKeySpki.replaceFirst(
          '-----END PUBLIC KEY-----',
          '-----END RSA PUBLIC KEY-----',
        ),
      );
    });

    test('1024-bit and 3072-bit RSA keys', () {
      _rejects(testPublicKey1024, reason: '1024');
      _rejects(testPublicKey3072, reason: '3072');
    });

    test('an elliptic-curve key', () {
      _rejects(testPublicKeyEc);
    });

    test('invalid base64', () {
      _rejects('-----BEGIN PUBLIC KEY-----\n@@@@\n-----END PUBLIC KEY-----');
    });

    test('truncated DER', () {
      final lines = testPublicKeySpki.trim().split('\n');
      final cut = [lines.first, lines[1], lines[2], lines.last].join('\n');
      _rejects(cut);
    });

    test('valid DER with trailing bytes', () {
      final body = testPublicKeySpki
          .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
          .replaceAll(RegExp(r'\s'), '');
      final longer = base64.encode([...base64.decode(body), 0, 0]);
      _rejects('-----BEGIN PUBLIC KEY-----\n$longer\n-----END PUBLIC KEY-----');
    });

    test(
      'flipping any single character never throws anything but FormatException',
      () {
        final lines = testPublicKeySpki.trim().split('\n');
        final body = lines.sublist(1, lines.length - 1).join();
        for (var i = 0; i < body.length; i += 7) {
          final flipped =
              body.substring(0, i) +
              (body[i] == 'A' ? 'B' : 'A') +
              body.substring(i + 1);
          final pem =
              '-----BEGIN PUBLIC KEY-----\n$flipped\n-----END PUBLIC KEY-----';
          try {
            PublicKeyParser.parse(pem);
          } on FormatException {
            // Rejected: fine.
          }
        }
      },
    );
  });
}
