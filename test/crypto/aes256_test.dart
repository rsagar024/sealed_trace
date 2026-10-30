@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/aes256.dart';

Uint8List _b64(String v) => base64.decode(v);

String _hex(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

Uint8List _encrypt(Uint8List key, Uint8List block) {
  final out = Uint8List(16);
  Aes256(key).encryptBlock(block, 0, out, 0);
  return out;
}

void main() {
  test('FIPS-197 appendix C.3 AES-256 example', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final plain = Uint8List.fromList([
      0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, //
      0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
    ]);
    expect(_hex(_encrypt(key, plain)), '8ea2b7ca516745bfeafc49904b496089');
  });

  test('all-zero key and block give the well-known value', () {
    expect(
      _hex(_encrypt(Uint8List(32), Uint8List(16))),
      'dc95c078a2408989ad48a21492842087',
    );
  });

  group('against Node (aes-256-ecb)', () {
    final doc =
        jsonDecode(
              File('test/vectors/aes_gcm_node_vectors.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final cases = (doc['blockCases'] as List).cast<Map<String, dynamic>>();

    test('there are enough cases to mean something', () {
      expect(cases.length, greaterThanOrEqualTo(40));
    });

    for (final c in cases) {
      test(c['name'] as String, () {
        final out = _encrypt(
          _b64(c['keyBase64'] as String),
          _b64(c['plaintextBase64'] as String),
        );
        expect(base64.encode(out), c['ciphertextBase64']);
      });
    }
  });

  test('input and output may be the same buffer, with offsets', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final plain = Uint8List.fromList([
      0x00, 0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, //
      0x88, 0x99, 0xaa, 0xbb, 0xcc, 0xdd, 0xee, 0xff,
    ]);
    final buffer = Uint8List(40)..setRange(5, 21, plain);
    Aes256(key).encryptBlock(buffer, 5, buffer, 5);
    expect(_hex(buffer.sublist(5, 21)), '8ea2b7ca516745bfeafc49904b496089');
    expect(buffer.sublist(0, 5).every((b) => b == 0), isTrue);
    expect(buffer.sublist(21).every((b) => b == 0), isTrue);
  });

  test('the same key and block always give the same result', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => 255 - i));
    final block = Uint8List.fromList(List<int>.generate(16, (i) => i * 3));
    expect(_encrypt(key, block), _encrypt(key, block));
  });

  test('keys that are not 32 bytes are rejected', () {
    for (final length in [0, 16, 24, 31, 33, 64]) {
      expect(
        () => Aes256(Uint8List(length)),
        throwsArgumentError,
        reason: '$length bytes',
      );
    }
  });
}
