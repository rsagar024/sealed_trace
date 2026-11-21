import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart'
    show OpeningDetails, QueryExecutor, QueryExecutorUser;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/crypto_backend.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/key_id.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/model/log_level.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';
import 'package:sealed_trace/src/storage/drift_storage_adapter.dart';
import 'package:sealed_trace/src/storage/envelope_spill.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/envelopes.dart';
import '../helpers/fakes.dart';
import '../helpers/rsa_oaep_decrypt.dart';
import '../helpers/test_keys.dart';

/// I3: envelope v3 carries an authenticated key id, and RSA-3072/4096 keys
/// are accepted.
LogRecord _record(int seq) => LogRecord(
  id: 'id-$seq',
  seq: seq,
  timestamp: DateTime.utc(2026, 1, 1, 10),
  level: LogLevel.info,
  tag: 't',
  message: 'm$seq',
  error: null,
  stackTrace: null,
  metadata: const {},
  sessionId: 's',
  userId: null,
  ctx: const {},
);

EnvelopeSealer _sealer(String pem) => EnvelopeSealer(
  publicKey: PublicKeyParser.parse(pem),
  projectId: 'project-1',
  clock: FakeClock(DateTime.utc(2026, 1, 1, 10, 0, 5)),
  newId: () => 'batch-1',
);

Uint8List _pemDer(String pem) => base64.decode(
  pem
      .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
      .replaceAll(RegExp(r'\s'), ''),
);

void main() {
  group('kid', () {
    test('matches the OpenSSL one-liner for the test key', () {
      expect(keyId(PublicKeyParser.parse(testPublicKeySpki)), testKeyId);
      expect(testKeyId, hasLength(keyIdLength));
    });

    test('is the same for the SPKI and PKCS#1 forms of a key', () {
      expect(keyId(PublicKeyParser.parse(testPublicKeyPkcs1)), testKeyId);
    });

    test('spkiDer re-encodes OpenSSL keys byte for byte', () {
      for (final pem in [
        testPublicKeySpki,
        otherPublicKeySpki,
        testPublicKey3072,
        testPublicKey4096,
      ]) {
        expect(spkiDer(PublicKeyParser.parse(pem)), _pemDer(pem));
      }
    });

    test('differs between keys and is base64url', () {
      final ids = {
        for (final pem in [
          testPublicKeySpki,
          otherPublicKeySpki,
          testPublicKey3072,
          testPublicKey4096,
        ])
          keyId(PublicKeyParser.parse(pem)),
      };
      expect(ids, hasLength(4));
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[A-Za-z0-9_-]{22}$')));
      }
    });
  });

  group('RSA key sizes', () {
    test('2048, 3072 and 4096 bits are accepted', () {
      expect(PublicKeyParser.parse(testPublicKeySpki).modulus.bitLength, 2048);
      expect(PublicKeyParser.parse(testPublicKey3072).modulus.bitLength, 3072);
      expect(PublicKeyParser.parse(testPublicKey4096).modulus.bitLength, 4096);
    });

    test('a 3072-bit envelope is v3, 384-byte wrapped, and opens', () async {
      final e = await _sealer(testPublicKey3072).seal([_record(1)]);
      final wire = e.toWireJson();
      expect(wire['v'], 3);
      expect(wire['alg'], 'RSA-OAEP-3072-SHA256+AES-256-GCM');
      expect(wire['kid'], keyId(PublicKeyParser.parse(testPublicKey3072)));
      expect(e.wrappedKey, hasLength(384));

      final key = loadTestPrivateKey(testPrivateKey3072Pkcs8);
      final aesKey = oaepDecrypt(
        modulus: key.modulus,
        privateExponent: key.privateExponent,
        ciphertext: e.wrappedKey,
      );
      final plain = gcmDecrypt(
        key: aesKey,
        iv: e.iv,
        ciphertext: e.ciphertext,
        tag: e.tag,
        aad: wireAad(wire),
      );
      expect(utf8.decode(plain).trimRight(), startsWith('[{'));

      // The header, kid included, is authenticated.
      expect(
        () => gcmDecrypt(
          key: aesKey,
          iv: e.iv,
          ciphertext: e.ciphertext,
          tag: e.tag,
          aad: wireAad({...wire, 'kid': testKeyId}),
        ),
        throwsStateError,
      );
    });

    test('a 4096-bit envelope has a 512-byte wrapped key', () {
      final e = _sealer(testPublicKey4096).sealSync([_record(1)]);
      expect(e.wrappedKey, hasLength(512));
      expect(e.algorithm, 'RSA-OAEP-4096-SHA256+AES-256-GCM');
      expect(e.version, envelopeVersion);
    });
  });

  group('legacy v1 envelopes (left by sealed_trace 1.0.0)', () {
    // Seal exactly as versions/v1.0.0 did: RSA-2048, AES-GCM with no AAD.
    SealedEnvelope sealLikeV100() {
      final backend = DefaultCryptoBackend();
      final aesKey = backend.randomBytes(32);
      final iv = backend.randomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('[{"seq":1}]'));
      final sealed = backend.aesGcmEncryptSync(
        key: aesKey,
        iv: iv,
        plaintext: plaintext,
        aad: Uint8List(0),
      );
      return SealedEnvelope(
        batchId: 'old-1',
        projectId: 'project-1',
        createdAt: DateTime.utc(2026, 1, 1, 10),
        eventCount: 1,
        wrappedKey: backend.rsaOaepWrap(
          PublicKeyParser.parse(testPublicKeySpki),
          aesKey,
        ),
        iv: iv,
        tag: sealed.tag,
        ciphertext: sealed.ciphertext,
        seqMin: 1,
        seqMax: 1,
        minTs: 1767261600000,
        maxTs: 1767261600000,
        topLevels: 'info',
        payloadSize: plaintext.length,
      );
    }

    test('a stored v1.0.0 row is sent exactly as 1.0.0 sent it', () async {
      final wire = sealLikeV100().toWireJson();
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
      // It opens with no AAD, as a v1 server decrypts it.
      expect(await openWire(wire), '[{"seq":1}]');
    });

    test('labelling it v3 would not open (it has no AAD)', () async {
      final e = sealLikeV100();
      final asV3 = {...e.toWireJson(), 'v': 3, 'kid': testKeyId};
      await expectLater(openWire(asV3), throwsA(anything));
    });

    test('a 1.0.0 page-exit spill entry is recovered as v1', () {
      final e = sealLikeV100();
      // The spill format of versions/v1.0.0: wire JSON plus index columns.
      final text = jsonEncode({
        ...e.toWireJson(),
        'seqMin': 1,
        'seqMax': 1,
        'minTs': 1767261600000,
        'maxTs': 1767261600000,
        'topLevels': 'info',
        'payloadSize': e.payloadSize,
      });
      final back = decodeSpilledEnvelope(text);
      expect(back.kid, isNull);
      expect(back.version, 1);
      expect(back.toWireJson(), e.toWireJson());
    });
  });

  group('spill', () {
    test('v3, legacy v1 and 3072-bit envelopes round-trip', () {
      for (final e in [
        makeEnvelope(kid: testKeyId),
        makeEnvelope(kid: null),
        makeEnvelope(wrappedKeyLength: 384),
      ]) {
        final back = decodeSpilledEnvelope(encodeSpilledEnvelope(e));
        expect(back.kid, e.kid);
        expect(back.wrappedKey, e.wrappedKey);
        expect(back.toWireJson(), e.toWireJson());
      }
    });

    Map<String, dynamic> spilled(SealedEnvelope e) =>
        jsonDecode(encodeSpilledEnvelope(e)) as Map<String, dynamic>;

    void rejects(Map<String, dynamic> m, String why) => expect(
      () => decodeSpilledEnvelope(jsonEncode(m)),
      throwsFormatException,
      reason: why,
    );

    test('inconsistent version, kid and algorithm are rejected', () {
      final v3 = spilled(makeEnvelope());
      final v1 = spilled(makeEnvelope(kid: null));
      rejects({...v3}..remove('kid'), 'v3 without kid');
      rejects({...v1, 'kid': testKeyId}, 'v1 with kid');
      rejects({...v1, 'v': 2}, 'v2 (never released)');
      rejects({...v3, 'v': 4}, 'unknown version');
      rejects({...v3, 'kid': 'not base64url!'}, 'bad kid');
      rejects({...v3, 'alg': 'RSA-OAEP-3072-SHA256+AES-256-GCM'}, 'alg/size');
      rejects(
        spilled(makeEnvelope(kid: null, wrappedKeyLength: 384)),
        'v1 with a 3072-bit key',
      );
      rejects(spilled(makeEnvelope(wrappedKeyLength: 300)), 'odd key size');
    });
  });

  group('drift schema 1 -> 2', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('st_migrate'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('a schema-1 row survives the upgrade and reads back as v1', () async {
      final file = File('${dir.path}/sealed_trace.db');
      // Build a schema-1 database as a 1.0.0 build of the SDK left it.
      final v1 = NativeDatabase(
        file,
        setup: (db) {
          db.execute('''
            CREATE TABLE IF NOT EXISTS sealed_envelopes (
              batch_id TEXT NOT NULL, project_id TEXT NOT NULL,
              created_at INTEGER NOT NULL, event_count INTEGER NOT NULL,
              payload_size INTEGER NOT NULL, wrapped_key BLOB NOT NULL,
              iv BLOB NOT NULL, tag BLOB NOT NULL, ciphertext BLOB NOT NULL,
              upload_state INTEGER NOT NULL DEFAULT 0,
              attempts INTEGER NOT NULL DEFAULT 0, last_attempt_at INTEGER,
              seq_min INTEGER NOT NULL, seq_max INTEGER NOT NULL,
              min_ts INTEGER NOT NULL, max_ts INTEGER NOT NULL,
              top_levels TEXT NOT NULL, uploaded_at INTEGER,
              PRIMARY KEY (batch_id));
            CREATE TABLE IF NOT EXISTS sealed_meta (
              "key" TEXT NOT NULL, "value" TEXT NOT NULL,
              PRIMARY KEY ("key"));
            INSERT INTO sealed_envelopes (batch_id, project_id, created_at,
              event_count, payload_size, wrapped_key, iv, tag, ciphertext,
              seq_min, seq_max, min_ts, max_ts, top_levels)
              VALUES ('old-1', 'project-1', 1767261600000, 1, 4,
                zeroblob(256), zeroblob(12), zeroblob(16), zeroblob(4),
                0, 0, 0, 0, '');
            PRAGMA user_version = 1;
          ''');
        },
      );
      await v1.ensureOpen(_NoUser());
      await v1.close();

      final adapter = DriftStorageAdapter(NativeDatabase(file));
      await adapter.open();
      final old = (await adapter.fetch(['old-1'])).single.envelope;
      expect(old.kid, isNull);
      expect(old.version, legacyEnvelopeVersion);
      expect(old.toWireJson().containsKey('kid'), isFalse);

      final fresh = makeEnvelope(id: 'new-1', kid: testKeyId);
      await adapter.insertEnvelope(EnvelopeRow.pending(fresh));
      expect((await adapter.fetch(['new-1'])).single.envelope.kid, testKeyId);
      await adapter.close();
    });
  });
}

/// A query executor user that opens the database without creating tables.
class _NoUser implements QueryExecutorUser {
  @override
  int get schemaVersion => 1;

  @override
  Future<void> beforeOpen(
    QueryExecutor executor,
    OpeningDetails details,
  ) async {}
}
