// Generates test/vectors/envelope_vectors.json.
//
// Run from the package root:  dart run tool/generate_vectors/generate.dart
//
// The RSA-OAEP step is randomized, so a regenerated file differs from the
// committed one in every `wrappedKey`. Regenerate only when the format changes,
// and tell the backend team when you do.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sealed_trace/src/crypto/crypto_backend.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/crypto/rsa_oaep.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/model/log_level.dart';
import 'package:sealed_trace/src/platform/clock.dart';

import '../../test/helpers/test_keys.dart';

const String _output = 'test/vectors/envelope_vectors.json';
const String _projectId = '3f2b8c1e-7a4d-4e6b-9c2a-5d1e8f0a7b34';

/// Returns fixed bytes for the AES key and IV so plaintext-to-ciphertext
/// results are reproducible; everything else stays random.
class _FixedBackend extends DefaultCryptoBackend {
  _FixedBackend(this._key, this._iv);

  final Uint8List _key;
  final Uint8List _iv;
  bool _keyUsed = false;
  bool _ivUsed = false;

  @override
  Uint8List randomBytes(int length) {
    if (length == 32 && !_keyUsed) {
      _keyUsed = true;
      return Uint8List.fromList(_key); // a copy: the sealer zeroes its key
    }
    if (length == 12 && !_ivUsed) {
      _ivUsed = true;
      return Uint8List.fromList(_iv);
    }
    return super.randomBytes(length);
  }
}

Uint8List _bytes(int length, int seed, int step) => Uint8List.fromList([
  for (var i = 0; i < length; i++) (i * step + seed) & 0xff,
]);

String _b64(List<int> bytes) => base64Encode(bytes);

LogRecord _record({
  required int seq,
  required LogLevel level,
  required String tag,
  required String message,
  required DateTime at,
  String? error,
  String? stackTrace,
  Map<String, dynamic> metadata = const {},
  String? userId,
}) {
  return LogRecord(
    id: '00000000-0000-4000-8000-${seq.toString().padLeft(12, '0')}',
    seq: seq,
    timestamp: at,
    level: level,
    tag: tag,
    message: message,
    error: error,
    stackTrace: stackTrace,
    metadata: metadata,
    sessionId: '9b1deb4d-3b7d-4bad-9bdd-2b0d7b3dcb6d',
    userId: userId,
    ctx: const {
      'appVersion': '1.2.3',
      'buildNumber': '45',
      'platform': 'android',
      'os': 'Android 14',
      'locale': 'en_IN',
      'env': 'prod',
      'network': 'wifi',
    },
  );
}

Future<Map<String, dynamic>> _envelopeCase(
  String name,
  String description,
  List<LogRecord> records,
  int seed,
) async {
  final key = _bytes(32, seed, 7);
  final iv = _bytes(12, seed + 1, 13);
  final sealer = EnvelopeSealer(
    publicKey: PublicKeyParser.parse(testPublicKeySpki),
    projectId: _projectId,
    backend: _FixedBackend(key, iv),
    clock: _FixedClock(DateTime.utc(2026, 1, 1, 10, 0, 5)),
    newId: () => '7c9e6679-7425-40de-944b-e07fc1f90ae${seed % 10}',
  );
  final envelope = await sealer.seal(records);
  return <String, dynamic>{
    'name': name,
    'description': description,
    'aesKeyBase64': _b64(key),
    'plaintextJson': jsonEncode([for (final r in records) r.toJson()]),
    'envelope': envelope.toWireJson(),
    'index': <String, dynamic>{
      'eventCount': envelope.eventCount,
      'seqMin': envelope.seqMin,
      'seqMax': envelope.seqMax,
      'minTs': envelope.minTs,
      'maxTs': envelope.maxTs,
      'topLevels': envelope.topLevels,
      'payloadSize': envelope.payloadSize,
    },
  };
}

class _FixedClock implements Clock {
  _FixedClock(this._now);
  final DateTime _now;
  @override
  DateTime now() => _now;
}

Future<Map<String, dynamic>> _aesCase(
  String name,
  String plaintext,
  int seed,
) async {
  final key = _bytes(32, seed, 11);
  final iv = _bytes(12, seed + 3, 17);
  final plaintextBytes = Uint8List.fromList(utf8.encode(plaintext));
  final result = await runAesGcm(AesGcmJob(key, iv, plaintextBytes));
  return <String, dynamic>{
    'name': name,
    'keyBase64': _b64(key),
    'ivBase64': _b64(iv),
    'plaintextBase64': _b64(plaintextBytes),
    'ciphertextBase64': _b64(result.ciphertext),
    'tagBase64': _b64(result.tag),
  };
}

Future<void> main() async {
  final base = DateTime.utc(2026, 1, 1, 10);

  final aesCases = <Map<String, dynamic>>[
    await _aesCase('ascii', 'hello world', 1),
    await _aesCase('unicode', 'héllo ✓ 你好 नमस्ते 🌍', 2),
    await _aesCase('empty', '', 3),
    await _aesCase('large_20000_bytes', '0123456789' * 2000, 4),
    await _aesCase(
      'json_array_single_event',
      jsonEncode([
        _record(
          seq: 1,
          level: LogLevel.info,
          tag: 'auth',
          message: 'login ok',
          at: base,
        ).toJson(),
      ]),
      5,
    ),
  ];

  final envelopes = <Map<String, dynamic>>[
    await _envelopeCase(
      'single_event_ascii',
      'One info event, empty metadata, no error.',
      [
        _record(
          seq: 1,
          level: LogLevel.info,
          tag: 'auth',
          message: 'login ok',
          at: base,
          userId: 'user-42',
        ),
      ],
      1,
    ),
    await _envelopeCase(
      'multi_event_mixed_levels',
      'Three events at different levels, one with an error and a stack trace.',
      [
        _record(
          seq: 41,
          level: LogLevel.debug,
          tag: 'network',
          message: 'GET /items -> 200 in 83ms',
          at: base,
          metadata: {'status': 200, 'durationMs': 83},
        ),
        _record(
          seq: 42,
          level: LogLevel.warning,
          tag: 'sync',
          message: 'slow sync',
          at: base.add(const Duration(milliseconds: 250)),
          metadata: {
            'items': [1, 2, 3],
            'nested': {'ok': true},
          },
        ),
        _record(
          seq: 43,
          level: LogLevel.error,
          tag: 'payment',
          message: 'charge failed',
          at: base.add(const Duration(milliseconds: 900)),
          error: 'Bad state: card declined',
          stackTrace: '#0 charge (payment.dart:10:3)\n#1 main (main.dart:5:1)',
        ),
      ],
      2,
    ),
    await _envelopeCase(
      'unicode_event',
      'Non-ASCII text is written as raw UTF-8, never as \\u escapes.',
      [
        _record(
          seq: 7,
          level: LogLevel.info,
          tag: 'i18n',
          message: 'héllo ✓ 你好 नमस्ते 🌍',
          at: base,
          metadata: {'greeting': 'नमस्ते'},
        ),
      ],
      3,
    ),
    await _envelopeCase(
      'full_batch_25_events',
      'A full 25-event batch, as produced by the write-behind queue.',
      [
        for (var i = 0; i < 25; i++)
          _record(
            seq: 100 + i,
            level: LogLevel.values[i % LogLevel.values.length],
            tag: 'bulk',
            message: 'event number $i',
            at: base.add(Duration(milliseconds: i * 10)),
            metadata: {'index': i},
          ),
      ],
      4,
    ),
  ];

  // Keys wrapped by the SDK's own RSA-OAEP, for an independent implementation
  // (Node, OpenSSL) to unwrap.
  final wrapKey = PublicKeyParser.parse(testPublicKeySpki);
  final wrapBackend = DefaultCryptoBackend();
  final wrapCases = <Map<String, dynamic>>[
    for (var i = 0; i < 25; i++)
      () {
        final message = wrapBackend.randomBytes(32);
        return <String, dynamic>{
          'name': 'sdk-wrapped-key-$i',
          'messageBase64': _b64(message),
          'ciphertextBase64': _b64(wrapBackend.rsaOaepWrap(wrapKey, message)),
        };
      }(),
    for (final length in [0, 1, 190])
      () {
        final message = wrapBackend.randomBytes(length);
        return <String, dynamic>{
          'name': 'sdk-wrapped-$length-bytes',
          'messageBase64': _b64(message),
          'ciphertextBase64': _b64(
            RsaOaep.encrypt(
              wrapKey,
              message,
              wrapBackend.randomBytes(RsaOaep.seedLength),
            ),
          ),
        };
      }(),
  ];

  final document = <String, dynamic>{
    'description': <String>[
      'Golden test vectors for the sealed_trace envelope format (v1).',
      'TEST ONLY: the private key below is published on purpose and protects nothing.',
      'RSA-OAEP is randomized, so wrappedKey differs on every encryption. '
          'Verify envelopes by DECRYPTING them, not by comparing wrappedKey bytes.',
      'aesGcmCases are fully deterministic: the same key, iv and plaintext '
          'must give exactly the listed ciphertext and tag.',
      'envelopes hold complete wire envelopes (the shape POSTed to '
          '/api/v1/ingest/logs), the AES key they must unwrap to, and the '
          'plaintext they must decrypt to.',
    ],
    'specification': <String, String>{
      'plaintext':
          'UTF-8 bytes of the compact JSON array of LogEvent objects (no spaces, '
          'keys in the order id, seq, ts, level, tag, message, error, stackTrace, '
          'metadata, sessionId, userId, ctx; non-ASCII characters are not escaped).',
      'aes':
          'AES-256-GCM, 32-byte random key, 12-byte random IV, no additional '
          'authenticated data, 16-byte tag stored separately from the ciphertext.',
      'rsa':
          'RSA-OAEP over the 32-byte AES key: 2048-bit key, SHA-256 label hash, '
          'MGF1 with SHA-256, empty label. wrappedKey is 256 bytes.',
      'base64': 'Standard alphabet with padding (RFC 4648 section 4).',
      'createdAt':
          'UTC ISO-8601 with milliseconds, e.g. 2026-01-01T10:00:05.000Z.',
      'alg': 'RSA-OAEP-2048-SHA256+AES-256-GCM',
    },
    'verification': <String, dynamic>{
      'openssl': <String>[
        'Save the private key as test_private.pem and one wrappedKey as wrapped.b64, then:',
        'base64 -d wrapped.b64 > wrapped.bin',
        'openssl pkeyutl -decrypt -inkey test_private.pem -in wrapped.bin '
            '-pkeyopt rsa_padding_mode:oaep -pkeyopt rsa_oaep_md:sha256 '
            '-pkeyopt rsa_mgf1_md:sha256 | base64',
        'The output must equal the case\'s aesKeyBase64.',
      ],
      'node': 'node tool/generate_vectors/verify_vectors.js',
    },
    'testOnlyKeys': <String, String>{
      'publicKeySpki': testPublicKeySpki,
      'publicKeyPkcs1': testPublicKeyPkcs1,
      'privateKeyPkcs8': testPrivateKeyPkcs8,
    },
    'projectId': _projectId,
    'aesGcmCases': aesCases,
    'envelopes': envelopes,
    'rsaOaepWrapCases': wrapCases,
  };

  final file = File(_output);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(document)}\n',
  );
  stdout.writeln(
    'Wrote $_output '
    '(${aesCases.length} AES cases, ${envelopes.length} envelopes, '
    '${wrapCases.length} wrapped-key cases)',
  );
}
