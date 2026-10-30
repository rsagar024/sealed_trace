@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/gcm.dart';

Uint8List _b64(String v) => base64.decode(v);

String _hex(List<int> b) =>
    b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();

Uint8List _fromHex(String hex) => Uint8List.fromList([
  for (var i = 0; i < hex.length; i += 2)
    int.parse(hex.substring(i, i + 2), radix: 16),
]);

void main() {
  group('published McGrew-Viega test cases, with constants written out', () {
    test('case 13: empty plaintext', () {
      final (ct, tag) = AesGcm256.encrypt(
        key: Uint8List(32),
        iv: Uint8List(12),
        plaintext: Uint8List(0),
      );
      expect(ct, isEmpty);
      expect(_hex(tag), '530f8afbc74536b9a963b4f1c4cb738b');
    });

    test('case 14: one zero block', () {
      final (ct, tag) = AesGcm256.encrypt(
        key: Uint8List(32),
        iv: Uint8List(12),
        plaintext: Uint8List(16),
      );
      expect(_hex(ct), 'cea7403d4d606b6e074ec5d3baf39d18');
      expect(_hex(tag), 'd0d1c8a799996bf0265b98b5d48ab919');
    });

    test('case 15: four blocks', () {
      final (ct, tag) = AesGcm256.encrypt(
        key: _fromHex(
          'feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308',
        ),
        iv: _fromHex('cafebabefacedbaddecaf888'),
        plaintext: _fromHex(
          'd9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a72'
          '1c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b391aafd255',
        ),
      );
      expect(
        _hex(ct),
        '522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa'
        '8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f662898015ad',
      );
      expect(_hex(tag), 'b094dac5d93471bdec1a502270e3cc6c');
    });
  });

  group('against Node (aes-256-gcm)', () {
    final doc =
        jsonDecode(
              File('test/vectors/aes_gcm_node_vectors.json').readAsStringSync(),
            )
            as Map<String, dynamic>;
    final cases = (doc['gcmCases'] as List).cast<Map<String, dynamic>>();

    test('the fixture covers the boundary lengths and large payloads', () {
      final names = cases.map((c) => c['name'] as String).toSet();
      for (final n in [1, 15, 16, 17, 31, 32, 33, 4096, 10000, 100000]) {
        expect(names, contains('random-len-$n'));
      }
      expect(names.where((n) => n.startsWith('nist-')).length, 4);
      expect(names.where((n) => n.contains('aad')).length, greaterThan(3));
    });

    for (final c in cases) {
      test(c['name'] as String, () {
        final aad = _b64(c['aadBase64'] as String);
        final (ct, tag) = AesGcm256.encrypt(
          key: _b64(c['keyBase64'] as String),
          iv: _b64(c['ivBase64'] as String),
          plaintext: _b64(c['plaintextBase64'] as String),
          aad: aad.isEmpty ? null : aad,
        );
        expect(base64.encode(ct), c['ciphertextBase64']);
        expect(base64.encode(tag), c['tagBase64']);
      });
    }
  });

  group('behavior', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final iv = Uint8List.fromList(List<int>.generate(12, (i) => i + 50));

    test('output lengths', () {
      for (final n in [0, 1, 15, 16, 17, 1000]) {
        final (ct, tag) = AesGcm256.encrypt(
          key: key,
          iv: iv,
          plaintext: Uint8List(n),
        );
        expect(ct.length, n);
        expect(tag.length, 16);
      }
    });

    test('changing any input changes the tag', () {
      final plain = Uint8List.fromList([1, 2, 3]);
      final base = AesGcm256.encrypt(key: key, iv: iv, plaintext: plain).$2;
      final otherKey = Uint8List.fromList(key)..[0] ^= 1;
      final otherIv = Uint8List.fromList(iv)..[0] ^= 1;
      expect(
        AesGcm256.encrypt(key: otherKey, iv: iv, plaintext: plain).$2,
        isNot(base),
      );
      expect(
        AesGcm256.encrypt(key: key, iv: otherIv, plaintext: plain).$2,
        isNot(base),
      );
      expect(
        AesGcm256.encrypt(
          key: key,
          iv: iv,
          plaintext: Uint8List.fromList([1, 2, 4]),
        ).$2,
        isNot(base),
      );
      expect(
        AesGcm256.encrypt(
          key: key,
          iv: iv,
          plaintext: plain,
          aad: Uint8List.fromList([9]),
        ).$2,
        isNot(base),
      );
    });

    test('the input buffers are not modified', () {
      final k = Uint8List.fromList(key);
      final v = Uint8List.fromList(iv);
      final p = Uint8List.fromList(List<int>.generate(50, (i) => i));
      AesGcm256.encrypt(key: k, iv: v, plaintext: p);
      expect(k, key);
      expect(v, iv);
      expect(p, List<int>.generate(50, (i) => i));
    });

    test('IVs that are not 12 bytes are rejected', () {
      for (final length in [0, 8, 11, 13, 16]) {
        expect(
          () => AesGcm256.encrypt(
            key: key,
            iv: Uint8List(length),
            plaintext: Uint8List(1),
          ),
          throwsArgumentError,
          reason: '$length bytes',
        );
      }
    });

    test('keys that are not 32 bytes are rejected', () {
      expect(
        () => AesGcm256.encrypt(
          key: Uint8List(16),
          iv: iv,
          plaintext: Uint8List(1),
        ),
        throwsArgumentError,
      );
    });
  });

  test('throughput is reported', () {
    final key = Uint8List.fromList(List<int>.generate(32, (i) => i));
    final data = Uint8List(1024 * 1024);
    final watch = Stopwatch()..start();
    AesGcm256.encrypt(key: key, iv: Uint8List(12), plaintext: data);
    watch.stop();
    final mibPerSecond = 1.0 / (watch.elapsedMicroseconds / 1e6);
    // ignore: avoid_print
    print(
      'AES-256-GCM, 1 MiB: ${watch.elapsedMilliseconds} ms '
      '(${mibPerSecond.toStringAsFixed(1)} MiB/s)',
    );
    expect(watch.elapsedMilliseconds, lessThan(30000));
  });
}
