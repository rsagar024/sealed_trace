import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/crypto/crypto_backend.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

final RsaPublicKeyData _key = PublicKeyParser.parse(testPublicKeySpki);

LogRecord _record({
  required int seq,
  LogLevel level = LogLevel.info,
  String message = 'hello',
  DateTime? at,
}) {
  return LogRecord(
    id: 'id-$seq',
    seq: seq,
    timestamp: at ?? DateTime.utc(2026, 1, 1, 10),
    level: level,
    tag: 't',
    message: message,
    error: null,
    stackTrace: null,
    metadata: const {},
    sessionId: 's',
    userId: null,
    ctx: const {'platform': 'android'},
  );
}

EnvelopeSealer _sealer({
  CryptoBackend? backend,
  String Function()? newId,
  DateTime? now,
}) {
  return EnvelopeSealer(
    publicKey: _key,
    projectId: 'project-1',
    backend: backend,
    clock: FakeClock(now ?? DateTime.utc(2026, 1, 1, 10, 0, 5)),
    newId: newId ?? () => 'batch-1',
  );
}

String _expectedPlaintext(List<LogRecord> records) =>
    jsonEncode([for (final r in records) r.toJson()]);

void main() {
  test(
    'round trip: the test private key recovers the exact JSON array',
    () async {
      final records = [_record(seq: 1), _record(seq: 2, message: 'two')];
      final envelope = await _sealer().seal(records);
      expect(await openEnvelope(envelope), _expectedPlaintext(records));
    },
  );

  test('field sizes and fixed values', () async {
    final envelope = await _sealer().seal([_record(seq: 1)]);
    expect(envelope.iv, hasLength(12));
    expect(envelope.tag, hasLength(16));
    expect(envelope.wrappedKey, hasLength(256));
    expect(envelope.batchId, 'batch-1');
    expect(envelope.projectId, 'project-1');
    expect(envelope.createdAt, DateTime.utc(2026, 1, 1, 10, 0, 5));
    expect(envelope.eventCount, 1);
  });

  test('ciphertext has the same length as the plaintext', () async {
    final records = [_record(seq: 1, message: 'héllo ✓')];
    final envelope = await _sealer().seal(records);
    expect(envelope.ciphertext.length, envelope.payloadSize);
    expect(
      envelope.payloadSize,
      utf8.encode(_expectedPlaintext(records)).length,
    );
  });

  test('wire JSON has exactly the section 7 keys and values', () async {
    final envelope = await _sealer().seal([_record(seq: 1)]);
    final wire = envelope.toWireJson();
    expect(wire.keys.toList(), [
      'v',
      'batchId',
      'projectId',
      'createdAt',
      'eventCount',
      'alg',
      'wrappedKey',
      'iv',
      'tag',
      'ciphertext',
    ]);
    expect(wire['v'], 1);
    expect(wire['alg'], 'RSA-OAEP-2048-SHA256+AES-256-GCM');
    expect(wire['createdAt'], '2026-01-01T10:00:05.000Z');
    expect(base64.decode(wire['iv'] as String), hasLength(12));
    expect(base64.decode(wire['tag'] as String), hasLength(16));
    expect(base64.decode(wire['wrappedKey'] as String), hasLength(256));
    // Standard alphabet with padding, no URL-safe characters.
    for (final field in ['wrappedKey', 'iv', 'tag', 'ciphertext']) {
      expect(wire[field], matches(RegExp(r'^[A-Za-z0-9+/]+={0,2}$')));
    }
    expect(openWire(wire), completes);
  });

  test('index columns are computed without decrypting', () async {
    final records = [
      _record(
        seq: 12,
        level: LogLevel.error,
        at: DateTime.utc(2026, 1, 1, 10, 0, 3),
      ),
      _record(
        seq: 10,
        level: LogLevel.info,
        at: DateTime.utc(2026, 1, 1, 10, 0, 1),
      ),
      _record(
        seq: 11,
        level: LogLevel.info,
        at: DateTime.utc(2026, 1, 1, 10, 0, 2),
      ),
      _record(
        seq: 13,
        level: LogLevel.verbose,
        at: DateTime.utc(2026, 1, 1, 10, 0, 4),
      ),
    ];
    final envelope = await _sealer().seal(records);
    expect(envelope.eventCount, 4);
    expect(envelope.seqMin, 10);
    expect(envelope.seqMax, 13);
    expect(
      envelope.minTs,
      DateTime.utc(2026, 1, 1, 10, 0, 1).millisecondsSinceEpoch,
    );
    expect(
      envelope.maxTs,
      DateTime.utc(2026, 1, 1, 10, 0, 4).millisecondsSinceEpoch,
    );
    expect(envelope.topLevels, 'verbose,info,error');
  });

  test('a single level gives a single entry', () async {
    final envelope = await _sealer().seal([
      _record(seq: 1, level: LogLevel.fatal),
    ]);
    expect(envelope.topLevels, 'fatal');
  });

  test('an empty batch is rejected', () async {
    await expectLater(_sealer().seal([]), throwsArgumentError);
  });

  group('tampering is detected by GCM', () {
    Future<void> expectFails(
      SealedEnvelope e, {
      Uint8List? iv,
      Uint8List? tag,
      Uint8List? ciphertext,
      Uint8List? wrappedKey,
    }) async {
      await expectLater(
        openFields(
          wrappedKey: wrappedKey ?? e.wrappedKey,
          iv: iv ?? e.iv,
          tag: tag ?? e.tag,
          ciphertext: ciphertext ?? e.ciphertext,
        ),
        throwsA(anything),
      );
    }

    Uint8List flip(Uint8List bytes, int index) {
      final copy = Uint8List.fromList(bytes);
      copy[index] ^= 0x01;
      return copy;
    }

    test('ciphertext, tag and iv', () async {
      final e = await _sealer().seal([_record(seq: 1)]);
      await expectFails(e, ciphertext: flip(e.ciphertext, 0));
      await expectFails(
        e,
        ciphertext: flip(e.ciphertext, e.ciphertext.length - 1),
      );
      await expectFails(e, tag: flip(e.tag, 0));
      await expectFails(e, iv: flip(e.iv, 0));
    });

    test('wrapped key', () async {
      final e = await _sealer().seal([_record(seq: 1)]);
      await expectFails(e, wrappedKey: flip(e.wrappedKey, 10));
    });
  });

  test('10,000 envelopes have unique IVs and keys', () async {
    final backend = DefaultCryptoBackend();
    final ivs = <String>{};
    final keys = <String>{};
    for (var i = 0; i < 10000; i++) {
      ivs.add(base64Encode(backend.randomBytes(12)));
      keys.add(base64Encode(backend.randomBytes(32)));
    }
    expect(ivs, hasLength(10000));
    expect(keys, hasLength(10000));
  });

  test(
    'two seals of the same batch differ (fresh key, iv and OAEP seed)',
    () async {
      final records = [_record(seq: 1)];
      final a = await _sealer().seal(records);
      final b = await _sealer().seal(records);
      expect(a.iv, isNot(b.iv));
      expect(a.wrappedKey, isNot(b.wrappedKey));
      expect(a.ciphertext, isNot(b.ciphertext));
      expect(await openEnvelope(a), await openEnvelope(b));
    },
  );

  test('the AES key is zeroed after sealing (best effort)', () async {
    final backend = _CapturingBackend();
    await _sealer(backend: backend).seal([_record(seq: 1)]);
    expect(backend.lastKey, isNotNull);
    expect(backend.lastKey!.every((b) => b == 0), isTrue);
  });

  test('batch ids come from the injected source', () async {
    var n = 0;
    final sealer = _sealer(newId: () => 'batch-${n++}');
    final first = await sealer.seal([_record(seq: 1)]);
    final second = await sealer.seal([_record(seq: 2)]);
    expect([first.batchId, second.batchId], ['batch-0', 'batch-1']);
  });

  group('offload', () {
    test(
      'large payloads use the offload hook and give a valid envelope',
      () async {
        var offloaded = 0;
        final backend = DefaultCryptoBackend(
          offload: (job) {
            offloaded++;
            return runAesGcm(job);
          },
        );
        final big = [_record(seq: 1, message: 'x' * 20000)];
        final envelope = await _sealer(backend: backend).seal(big);
        expect(offloaded, 1);
        expect(await openEnvelope(envelope), _expectedPlaintext(big));
      },
    );

    test('small payloads stay inline', () async {
      var offloaded = 0;
      final backend = DefaultCryptoBackend(
        offload: (job) {
          offloaded++;
          return runAesGcm(job);
        },
      );
      await _sealer(backend: backend).seal([_record(seq: 1)]);
      expect(offloaded, 0);
    });

    test('a real isolate gives the same result as inline', () async {
      final job = AesGcmJob(
        Uint8List.fromList(List.generate(32, (i) => i)),
        Uint8List.fromList(List.generate(12, (i) => i + 100)),
        Uint8List.fromList(utf8.encode('payload ' * 3000)),
      );
      final inline = await runAesGcm(job);
      final isolated = await compute(runAesGcm, job);
      expect(isolated.ciphertext, inline.ciphertext);
      expect(isolated.tag, inline.tag);
    });
  });

  group('fail closed', () {
    test('a failing backend throws and returns nothing', () async {
      await expectLater(
        _sealer(backend: _BrokenBackend()).seal([_record(seq: 1)]),
        throwsStateError,
      );
    });

    test('wrong sizes from the backend are rejected', () async {
      await expectLater(
        _sealer(backend: _ShortTagBackend()).seal([_record(seq: 1)]),
        throwsStateError,
      );
    });
  });

  test(
    'AES-GCM matches the published NIST test case 14 (via the backend)',
    () async {
      // McGrew-Viega GCM test case 14: zero key, zero IV, one zero block.
      final result = await runAesGcm(
        AesGcmJob(Uint8List(32), Uint8List(12), Uint8List(16)),
      );
      String hex(List<int> b) =>
          b.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
      expect(hex(result.ciphertext), 'cea7403d4d606b6e074ec5d3baf39d18');
      expect(hex(result.tag), 'd0d1c8a799996bf0265b98b5d48ab919');
    },
  );
}

class _CapturingBackend extends DefaultCryptoBackend {
  Uint8List? lastKey;

  @override
  Uint8List randomBytes(int length) {
    final bytes = super.randomBytes(length);
    // The first 32-byte request is the AES key; the RSA step later asks for
    // another 32 bytes to seed its RNG.
    if (length == 32) lastKey ??= bytes;
    return bytes;
  }
}

class _BrokenBackend extends DefaultCryptoBackend {
  @override
  Future<AesGcmResult> aesGcmEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) => Future.error(StateError('crypto unavailable'));
}

class _ShortTagBackend extends DefaultCryptoBackend {
  @override
  Future<AesGcmResult> aesGcmEncrypt({
    required Uint8List key,
    required Uint8List iv,
    required Uint8List plaintext,
  }) async => AesGcmResult(Uint8List(plaintext.length), Uint8List(8));
}
