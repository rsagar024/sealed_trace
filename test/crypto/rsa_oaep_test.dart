@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/crypto/rsa_oaep.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/rsa_oaep_decrypt.dart';
import '../helpers/test_keys.dart';

final RsaPublicKeyData _publicKey = PublicKeyParser.parse(testPublicKeySpki);
final ({BigInt modulus, BigInt privateExponent}) _privateKey =
    loadTestPrivateKey();

Uint8List _seed(int fill) => Uint8List.fromList(List<int>.filled(32, fill));

Uint8List _message(int length) =>
    Uint8List.fromList(List<int>.generate(length, (i) => (i * 7 + 3) & 0xff));

Uint8List _decrypt(Uint8List ciphertext) => oaepDecrypt(
  modulus: _privateKey.modulus,
  privateExponent: _privateKey.privateExponent,
  ciphertext: ciphertext,
);

void main() {
  test('the test private key matches the public key', () {
    expect(_privateKey.modulus, _publicKey.modulus);
  });

  group('decoding what Node encrypted (SHA-256 OAEP, empty label)', () {
    final doc =
        jsonDecode(
              File(
                'test/vectors/rsa_oaep_node_vectors.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    final cases = (doc['oaepCases'] as List).cast<Map<String, dynamic>>();

    test('the fixture covers empty, key-sized and maximum-length messages', () {
      final names = cases.map((c) => c['name']).toSet();
      expect(names, contains('node-encrypted-0-bytes'));
      expect(names, contains('node-encrypted-32-bytes'));
      expect(names, contains('node-encrypted-190-bytes'));
    });

    for (final c in cases) {
      test(c['name'] as String, () {
        final plain = _decrypt(base64.decode(c['ciphertextBase64'] as String));
        expect(base64.encode(plain), c['messageBase64']);
      });
    }
  });

  group('our encryption', () {
    test('round-trips messages of many lengths', () {
      for (final length in [0, 1, 2, 31, 32, 33, 100, 189, 190]) {
        final message = _message(length);
        final ciphertext = RsaOaep.encrypt(_publicKey, message, _seed(length));
        expect(ciphertext.length, 256, reason: 'length $length');
        expect(_decrypt(ciphertext), message, reason: 'length $length');
      }
    });

    test('the same message and seed always give the same ciphertext', () {
      final a = RsaOaep.encrypt(_publicKey, _message(32), _seed(5));
      final b = RsaOaep.encrypt(_publicKey, _message(32), _seed(5));
      expect(a, b);
    });

    test(
      'a different seed gives a different ciphertext for the same message',
      () {
        final a = RsaOaep.encrypt(_publicKey, _message(32), _seed(5));
        final b = RsaOaep.encrypt(_publicKey, _message(32), _seed(6));
        expect(a, isNot(b));
        expect(_decrypt(a), _decrypt(b));
      },
    );

    test('the maximum message length is 190 bytes for RSA-2048', () {
      expect(RsaOaep.maxMessageLength(256), 190);
      expect(
        () => RsaOaep.encrypt(_publicKey, _message(191), _seed(1)),
        throwsArgumentError,
      );
    });

    test('a seed that is not 32 bytes is rejected', () {
      for (final length in [0, 20, 31, 33]) {
        expect(
          () => RsaOaep.encrypt(_publicKey, _message(32), Uint8List(length)),
          throwsArgumentError,
          reason: '$length bytes',
        );
      }
    });

    test('a key that is too small for OAEP-SHA-256 is rejected', () {
      final tiny = RsaPublicKeyData(
        (BigInt.one << 400) + BigInt.one, // 50-byte modulus
        BigInt.from(65537),
      );
      expect(
        () => RsaOaep.encrypt(tiny, Uint8List(1), _seed(1)),
        throwsArgumentError,
      );
    });

    test('the input buffers are not modified', () {
      final message = _message(32);
      final seed = _seed(9);
      RsaOaep.encrypt(_publicKey, message, seed);
      expect(message, _message(32));
      expect(seed, _seed(9));
    });

    test('the encoded block is not predictable from the message alone', () {
      // With public exponent 1 the "ciphertext" is the encoded block, so we
      // can look at the structure: leading zero byte and a masked seed that
      // depends on the seed.
      final identity = RsaPublicKeyData(_publicKey.modulus, BigInt.one);
      final a = RsaOaep.encrypt(identity, _message(32), _seed(1));
      final b = RsaOaep.encrypt(identity, _message(32), _seed(2));
      expect(a[0], 0);
      expect(b[0], 0);
      expect(a.sublist(1, 33), isNot(b.sublist(1, 33)));
      expect(
        a.sublist(33),
        isNot(b.sublist(33)),
        reason: 'the whole block depends on the seed',
      );
    });
  });
}
