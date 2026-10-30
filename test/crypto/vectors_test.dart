@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/crypto_backend.dart';

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

        expect(wire['v'], 1);
        expect(wire['alg'], 'RSA-OAEP-2048-SHA256+AES-256-GCM');
        expect(_b64(wire['iv'] as String), hasLength(12));
        expect(_b64(wire['tag'] as String), hasLength(16));
        expect(_b64(wire['wrappedKey'] as String), hasLength(256));

        final key = unwrapKey(_b64(wire['wrappedKey'] as String));
        expect(base64.encode(key), c['aesKeyBase64']);
        expect(await openWire(wire), c['plaintextJson']);

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
