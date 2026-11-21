import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/aes256.dart';
import 'package:sealed_trace/src/crypto/aes_gcm_platform.dart';
import 'package:sealed_trace/src/crypto/crypto_backend.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/gcm.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/crypto/rsa_oaep.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/model/log_level.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/test_keys.dart';

bool _allZero(Uint8List b) => b.every((x) => x == 0);

Uint8List _bytes(int n, int seed) =>
    Uint8List.fromList(List.generate(n, (i) => (i * 7 + seed) & 0xff));

LogRecord _record(String message) => LogRecord(
  id: 'id-1',
  seq: 1,
  timestamp: DateTime.utc(2026, 1, 1),
  level: LogLevel.info,
  tag: 't',
  message: message,
  error: null,
  stackTrace: null,
  metadata: const {},
  sessionId: 's',
  userId: null,
  ctx: const {},
);

/// Captures the buffers the sealer hands to the backend.
class _Capturing extends DefaultCryptoBackend {
  _Capturing({super.offload});

  Uint8List? key;
  Uint8List? plaintext;
  final seeds = <Uint8List>[];

  @override
  Uint8List randomBytes(int length) {
    final bytes = super.randomBytes(length);
    if (length == 32) {
      if (key == null) {
        key = bytes;
      } else {
        seeds.add(bytes);
      }
    }
    return bytes;
  }

  @override
  Future<AesGcmResult> aesGcmEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
    required Uint8List aad,
  }) {
    this.plaintext = plaintext;
    return super.aesGcmEncrypt(
      key: key,
      iv: iv,
      plaintext: plaintext,
      aad: aad,
    );
  }
}

void main() {
  tearDown(() {
    AesGcm256.debugOnWipe = null;
    RsaOaep.debugOnWipe = null;
  });

  test('Aes256.destroy zeroes the expanded key', () {
    final aes = Aes256(_bytes(32, 1));
    expect(aes.debugRoundKeys.any((w) => w != 0), isTrue);
    aes.destroy();
    expect(aes.debugRoundKeys.every((w) => w == 0), isTrue);
  });

  test('AES-GCM wipes H, the tag mask, the keystream, the counter, the '
      'expanded key and the GHASH state', () {
    List<Uint8List>? wiped;
    AesGcm256.debugOnWipe = (buffers) => wiped = buffers;
    final (ct, tag) = AesGcm256.encrypt(
      key: _bytes(32, 3),
      iv: _bytes(12, 5),
      plaintext: _bytes(100, 9),
      aad: _bytes(13, 2),
    );
    expect(ct, hasLength(100));
    expect(tag, hasLength(16));
    expect(wiped, hasLength(6));
    for (final b in wiped!) {
      expect(b, isNotEmpty);
      expect(_allZero(b), isTrue);
    }
  });

  test('AES-GCM output is unchanged by the wiping', () {
    final key = _bytes(32, 3);
    final iv = _bytes(12, 5);
    final plain = _bytes(1000, 9);
    final a = AesGcm256.encrypt(key: key, iv: iv, plaintext: plain);
    final b = AesGcm256.encrypt(key: key, iv: iv, plaintext: plain);
    expect(a.$1, b.$1);
    expect(a.$2, b.$2);
    expect(key, _bytes(32, 3), reason: 'the caller key is left alone');
  });

  test('RSA-OAEP wipes DB, the masks, the masked seed and EM', () {
    List<Uint8List>? wiped;
    RsaOaep.debugOnWipe = (buffers) => wiped = buffers;
    final message = _bytes(32, 11);
    final wrapped = RsaOaep.encrypt(
      PublicKeyParser.parse(testPublicKeySpki),
      message,
      _bytes(32, 4),
    );
    expect(wiped, hasLength(6));
    for (final b in wiped!) {
      expect(_allZero(b), isTrue);
    }
    expect(unwrapKey(wrapped), message, reason: 'still a valid wrap');
  });

  test('the backend wipes the OAEP seed after wrapping', () {
    final backend = _Capturing();
    backend.key = Uint8List(0); // so the next 32-byte request is the seed
    final message = _bytes(32, 1);
    final wrapped = backend.rsaOaepWrap(
      PublicKeyParser.parse(testPublicKeySpki),
      message,
    );
    expect(backend.seeds, hasLength(1));
    expect(_allZero(backend.seeds.single), isTrue);
    expect(unwrapKey(wrapped), message);
  });

  test('runAesGcmAndWipe wipes its job, runAesGcm does not', () async {
    final key = _bytes(32, 2);
    final plain = _bytes(64, 8);
    final inline = await runAesGcm(AesGcmJob(key, _bytes(12, 1), plain));
    expect(key, _bytes(32, 2), reason: 'the sealer still needs it');
    expect(plain, _bytes(64, 8));

    final job = AesGcmJob(_bytes(32, 2), _bytes(12, 1), _bytes(64, 8));
    final wiped = await runAesGcmAndWipe(job);
    expect(wiped.ciphertext, inline.ciphertext);
    expect(wiped.tag, inline.tag);
    expect(_allZero(job.key), isTrue);
    expect(_allZero(job.plaintext), isTrue);
  });

  for (final offloaded in [false, true]) {
    test('the sealer wipes its key and plaintext '
        '(${offloaded ? 'background isolate' : 'inline'})', () async {
      final backend = _Capturing(
        offload: offloaded ? platformAesGcmOffload() : null,
      );
      final sealer = EnvelopeSealer(
        publicKey: PublicKeyParser.parse(testPublicKeySpki),
        projectId: 'p',
        backend: backend,
      );
      final message = offloaded ? 'x' * 20000 : 'small';
      final envelope = await sealer.seal([_record(message)]);
      expect(_allZero(backend.key!), isTrue);
      expect(_allZero(backend.plaintext!), isTrue);
      expect(backend.seeds.every(_allZero), isTrue);
      // Wiping happened after use: the envelope still opens.
      final opened = jsonDecode(await openEnvelope(envelope)) as List;
      expect((opened.single as Map)['message'], message);
    });
  }

  test('sealSync wipes its key and plaintext too', () async {
    Uint8List? plaintext;
    final backend = _SyncCapturing((p) => plaintext = p);
    final sealer = EnvelopeSealer(
      publicKey: PublicKeyParser.parse(testPublicKeySpki),
      projectId: 'p',
      backend: backend,
    );
    final envelope = sealer.sealSync([_record('page exit')]);
    expect(_allZero(plaintext!), isTrue);
    expect(_allZero(backend.key!), isTrue);
    expect(await openEnvelope(envelope), contains('page exit'));
  });
}

class _SyncCapturing extends DefaultCryptoBackend {
  _SyncCapturing(this.onPlaintext);

  final void Function(Uint8List) onPlaintext;
  Uint8List? key;

  @override
  Uint8List randomBytes(int length) {
    final bytes = super.randomBytes(length);
    if (length == 32) key ??= bytes;
    return bytes;
  }

  @override
  AesGcmResult aesGcmEncryptSync({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
    required Uint8List aad,
  }) {
    onPlaintext(plaintext);
    return super.aesGcmEncryptSync(
      key: key,
      iv: iv,
      plaintext: plaintext,
      aad: aad,
    );
  }
}
