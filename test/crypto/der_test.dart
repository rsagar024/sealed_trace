import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/der.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';

import '../helpers/test_keys.dart';

Uint8List _b(List<int> bytes) => Uint8List.fromList(bytes);

void _rejects(List<int> bytes, String reason) {
  expect(
    () => readDerElement(_b(bytes)),
    throwsFormatException,
    reason: reason,
  );
}

/// A minimal DER PEM for [der] with the given header.
String _pem(String label, List<int> der) =>
    '-----BEGIN $label-----\n${base64.encode(der)}\n-----END $label-----';

void main() {
  group('L9: DER lengths', () {
    test('short and minimal long forms are read', () {
      final short = readDerElement(_b([0x04, 0x02, 0xaa, 0xbb]));
      expect(short.content, [0xaa, 0xbb]);

      final long = readDerElement(
        _b([0x04, 0x81, 0x80, ...List.filled(128, 7)]),
      );
      expect(long.content, hasLength(128));

      final two = readDerElement(
        _b([0x04, 0x82, 0x01, 0x00, ...List.filled(256, 1)]),
      );
      expect(two.content, hasLength(256));
    });

    test('a 4-byte length is refused (it went negative on the web)', () {
      _rejects([0x30, 0x84, 0x80, 0x00, 0x00, 0x00], '2^31');
      _rejects([0x30, 0x84, 0xff, 0xff, 0xff, 0xff], '2^32 - 1');
      _rejects([0x30, 0x84, 0x00, 0x00, 0x00, 0x01], 'four bytes for 1');
    });

    test('non-minimal lengths are refused', () {
      _rejects([0x04, 0x81, 0x05, 1, 2, 3, 4, 5], 'long form for 5');
      _rejects([0x04, 0x82, 0x00, 0x90, ...List.filled(0x90, 0)], 'leading 0');
      _rejects([0x04, 0x81, 0x00], 'long form for 0');
    });

    test('indefinite lengths and high tag numbers are refused', () {
      _rejects([0x30, 0x80, 0x00, 0x00], 'indefinite');
      _rejects([0x1f, 0x22, 0x01, 0x00], 'high tag number');
      _rejects([0xbf, 0x81, 0x01, 0x01, 0x00], 'high tag number, context');
    });

    test('truncated input is a FormatException, never a RangeError', () {
      _rejects([], 'empty');
      _rejects([0x30], 'tag only');
      _rejects([0x30, 0x82, 0x01], 'length cut short');
      _rejects([0x30, 0x83, 0xff, 0xff, 0xff], 'length past the buffer');
      _rejects([0x04, 0x05, 1, 2], 'content cut short');
      expect(
        () => readDerElement(_b([0x04, 0x01, 0x00]), 5),
        throwsFormatException,
        reason: 'offset past the end',
      );
      expect(
        () => readDerElement(_b([0x04, 0x01, 0x00]), -1),
        throwsFormatException,
      );
    });
  });

  group('L9: DER INTEGERs', () {
    BigInt integer(List<int> bytes) =>
        readDerInteger(readDerElement(_b([0x02, bytes.length, ...bytes])));

    test('minimal values are read', () {
      expect(integer([0x00]), BigInt.zero);
      expect(integer([0x7f]), BigInt.from(127));
      expect(integer([0x00, 0x80]), BigInt.from(128));
      expect(integer([0x01, 0x00, 0x01]), BigInt.from(65537));
    });

    test('redundant leading zeros, negatives and empties are refused', () {
      expect(() => integer([0x00, 0x7f]), throwsFormatException);
      expect(() => integer([0x00, 0x00, 0x80]), throwsFormatException);
      expect(() => integer([0x80]), throwsFormatException);
      expect(() => integer([0xff, 0x01]), throwsFormatException);
      expect(
        () => readDerInteger(readDerElement(_b([0x02, 0x00]))),
        throwsFormatException,
      );
    });
  });

  group('L9: public keys', () {
    test('the real test keys still parse', () {
      expect(PublicKeyParser.parse(testPublicKeySpki).modulus.bitLength, 2048);
      expect(PublicKeyParser.parse(testPublicKeyPkcs1).modulus.bitLength, 2048);
    });

    test('a key with a padded exponent is refused', () {
      final key = PublicKeyParser.parse(testPublicKeyPkcs1);
      final n = key.modulus.toRadixString(16).padLeft(512, '0');
      final modulus = [
        0x00,
        for (var i = 0; i < n.length; i += 2)
          int.parse(n.substring(i, i + 2), radix: 16),
      ];
      List<int> pkcs1(List<int> exponent) {
        final body = [
          0x02, 0x82, 0x01, 0x01, ...modulus, //
          0x02, exponent.length, ...exponent,
        ];
        return [0x30, 0x82, body.length >> 8, body.length & 0xff, ...body];
      }

      expect(
        PublicKeyParser.parse(
          _pem('RSA PUBLIC KEY', pkcs1([0x01, 0x00, 0x01])),
        ).exponent,
        BigInt.from(65537),
        reason: 'the hand-built key is valid',
      );
      expect(
        () => PublicKeyParser.parse(
          _pem('RSA PUBLIC KEY', pkcs1([0x00, 0x01, 0x00, 0x01])),
        ),
        throwsFormatException,
      );
    });

    test('a key with a non-minimal outer length is refused', () {
      final der = base64.decode(
        testPublicKeyPkcs1
            .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
            .replaceAll(RegExp(r'\s'), ''),
      );
      // 30 82 01 0a ... becomes 30 83 00 01 0a ...: same length, one
      // redundant leading zero byte.
      expect(der.sublist(0, 2), [0x30, 0x82]);
      final padded = [0x30, 0x83, 0x00, ...der.sublist(2)];
      expect(
        () => PublicKeyParser.parse(_pem('RSA PUBLIC KEY', padded)),
        throwsFormatException,
      );
    });
  });
}
