@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/crypto_backend.dart';
import 'package:sealed_trace/src/crypto/key_id.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/test_keys.dart';

Uint8List _b64(String value) => base64.decode(value);

void main() {
  final doc =
      jsonDecode(File('test/vectors/envelope_vectors.json').readAsStringSync())
          as Map<String, dynamic>;
  final aesCases = (doc['aesGcmCases'] as List).cast<Map<String, dynamic>>();
  final envelopes = (doc['envelopes'] as List).cast<Map<String, dynamic>>();

  test('the vectors file embeds the same test keys as the helpers', () {
    final keys = doc['testOnlyKeys'] as Map<String, dynamic>;
    expect(keys['publicKeySpki'], testPublicKeySpki);
    expect(keys['publicKeyPkcs1'], testPublicKeyPkcs1);
    expect(keys['privateKeyPkcs8'], testPrivateKeyPkcs8);
    expect(keys['publicKey3072Spki'], testPublicKey3072);
    expect(keys['privateKey3072Pkcs8'], testPrivateKey3072Pkcs8);
  });

  test('the file covers the documented cases', () {
    expect(
      aesCases.map((c) => c['name']),
      containsAll(['ascii', 'unicode', 'empty', 'large_20000_bytes']),
    );
    expect(
      envelopes.map((c) => c['name']),
      containsAll([
        'single_event_ascii',
        'multi_event_mixed_levels',
        'unicode_event',
        'full_batch_25_events',
        'rsa_3072_key',
        'legacy_v1_no_aad',
      ]),
    );
  });

  group('deterministic AES-GCM vectors', () {
    for (final c in aesCases) {
      test(c['name'] as String, () async {
        final result = await runAesGcm(
          AesGcmJob(
            _b64(c['keyBase64'] as String),
            _b64(c['ivBase64'] as String),
            _b64(c['plaintextBase64'] as String),
          ),
        );
        expect(base64.encode(result.ciphertext), c['ciphertextBase64']);
        expect(base64.encode(result.tag), c['tagBase64']);
      });
    }
  });

  group('committed envelopes decrypt to the committed plaintext', () {
    for (final c in envelopes) {
      test(c['name'] as String, () async {
        final wire = (c['envelope'] as Map).cast<String, dynamic>();

        final legacy = c['name'] == 'legacy_v1_no_aad';
        final rsa3072 = c['name'] == 'rsa_3072_key';
        expect(wire['v'], legacy ? 1 : 3);
        expect(
          wire['alg'],
          rsa3072
              ? 'RSA-OAEP-3072-SHA256+AES-256-GCM'
              : 'RSA-OAEP-2048-SHA256+AES-256-GCM',
        );
        // I3: the kid is the key's own identifier (absent for v2).
        expect(
          wire['kid'],
          legacy
              ? isNull
              : keyId(
                  PublicKeyParser.parse(
                    rsa3072 ? testPublicKey3072 : testPublicKeySpki,
                  ),
                ),
        );
        expect(utf8.decode(wireAad(wire)), c['aadUtf8']);
        expect(_b64(wire['iv'] as String), hasLength(12));
        expect(_b64(wire['tag'] as String), hasLength(16));
        expect(
          _b64(wire['wrappedKey'] as String),
          hasLength(rsa3072 ? 384 : 256),
        );

        final key = unwrapKey(_b64(wire['wrappedKey'] as String));
        expect(base64.encode(key), c['aesKeyBase64']);
        expect(await openWire(wire), c['plaintextJson']);
        // L6: the ciphertext is the padded plaintext's length.
        expect(
          base64.decode(wire['ciphertext'] as String).length,
          c['paddedLength'],
        );
        expect(
          legacy
              // 1.0.0 did not pad (L6 came later).
              ? utf8.encode(c['plaintextJson'] as String).length
              : padmeLength(utf8.encode(c['plaintextJson'] as String).length),
          c['paddedLength'],
        );

        final events = jsonDecode(c['plaintextJson'] as String) as List;
        expect(events, hasLength(wire['eventCount'] as int));
      });
    }
  });

  test('plaintext is compact JSON with raw UTF-8, never \\u escapes', () {
    final unicode = envelopes.firstWhere((c) => c['name'] == 'unicode_event');
    final plaintext = unicode['plaintextJson'] as String;
    expect(plaintext, contains('नमस्ते'));
    expect(plaintext, isNot(contains(r'\u')));
    expect(plaintext, isNot(contains('": ')));
    expect(plaintext, isNot(contains(', "')));
  });

  test('each event keeps the section 5 key order', () {
    final first = envelopes.first['plaintextJson'] as String;
    final event = (jsonDecode(first) as List).first as Map<String, dynamic>;
    expect(event.keys.toList(), [
      'id',
      'seq',
      'ts',
      'level',
      'tag',
      'message',
      'error',
      'stackTrace',
      'metadata',
      'sessionId',
      'userId',
      'ctx',
    ]);
  });

  group('keys wrapped by the SDK decode to the original message', () {
    final wrapCases = (doc['rsaOaepWrapCases'] as List)
        .cast<Map<String, dynamic>>();

    test('the file has the expected number of cases', () {
      expect(wrapCases.length, 28);
    });

    for (final c in wrapCases) {
      test(c['name'] as String, () {
        expect(
          base64.encode(unwrapKey(_b64(c['ciphertextBase64'] as String))),
          c['messageBase64'],
        );
      });
    }
  });
}
