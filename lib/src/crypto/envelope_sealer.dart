import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../event/log_record.dart';
import '../model/log_level.dart';
import '../model/sealed_envelope.dart';
import '../platform/clock.dart';
import 'crypto_backend.dart';
import 'public_key_parser.dart';

/// Seals a batch of events into an encrypted [SealedEnvelope].
///
/// The plaintext is the UTF-8 JSON array of the records (compact, in the field
/// order of `LogRecord.toJson`). A fresh 256-bit key and 96-bit IV encrypt it
/// with AES-256-GCM, and the clear header (`alg`, `projectId`, `batchId`,
/// `createdAt`, `eventCount`) is authenticated as additional data
/// ([envelopeAad]), so it cannot be changed without breaking decryption. The
/// key is then wrapped with the project's RSA public key (RSA-OAEP, SHA-256,
/// MGF1-SHA-256, empty label). The device never holds a key that could
/// decrypt the result.
///
/// [seal] throws if anything goes wrong. It never returns plaintext.
class EnvelopeSealer {
  /// Creates a sealer for one project key.
  EnvelopeSealer({
    required this.publicKey,
    required this.projectId,
    CryptoBackend? backend,
    this.clock = const SystemClock(),
    String Function()? newId,
  }) : backend = backend ?? DefaultCryptoBackend(),
       _newId = newId ?? const Uuid().v4;

  /// The project's RSA public key.
  final RsaPublicKeyData publicKey;

  /// Sent inside every envelope.
  final String projectId;

  /// The crypto primitives.
  final CryptoBackend backend;

  /// Source of `createdAt`.
  final Clock clock;

  final String Function() _newId;

  static const int _keyLength = 32;
  static const int _ivLength = 12;
  static const int _tagLength = 16;
  static const int _wrappedKeyLength = 256;

  /// Encrypts [records] into an envelope.
  Future<SealedEnvelope> seal(List<LogRecord> records) async {
    final plaintext = _plaintext(records);
    final header = _header(records);
    final key = backend.randomBytes(_keyLength);
    final iv = backend.randomBytes(_ivLength);
    try {
      final encrypted = await backend.aesGcmEncrypt(
        key: key,
        iv: iv,
        plaintext: plaintext,
        aad: header.aad,
      );
      return _assemble(records, header, plaintext, key, iv, encrypted);
    } finally {
      // Best effort: neither the key nor the plaintext may outlive the call.
      key.fillRange(0, key.length, 0);
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  /// Like [seal], but entirely on the calling thread with no asynchronous
  /// step, for the page-exit path. Never offloads.
  SealedEnvelope sealSync(List<LogRecord> records) {
    final plaintext = _plaintext(records);
    final header = _header(records);
    final key = backend.randomBytes(_keyLength);
    final iv = backend.randomBytes(_ivLength);
    try {
      final encrypted = backend.aesGcmEncryptSync(
        key: key,
        iv: iv,
        plaintext: plaintext,
        aad: header.aad,
      );
      return _assemble(records, header, plaintext, key, iv, encrypted);
    } finally {
      key.fillRange(0, key.length, 0);
      plaintext.fillRange(0, plaintext.length, 0);
    }
  }

  Uint8List _plaintext(List<LogRecord> records) {
    if (records.isEmpty) {
      throw ArgumentError.value(records, 'records', 'Nothing to seal');
    }
    return Uint8List.fromList(
      utf8.encode(
        jsonEncode(<Map<String, dynamic>>[
          for (final record in records) record.toJson(),
        ]),
      ),
    );
  }

  /// Fixes the clear header before encryption, so it can be authenticated.
  _Header _header(List<LogRecord> records) {
    final created = DateTime.fromMillisecondsSinceEpoch(
      clock.now().millisecondsSinceEpoch,
      isUtc: true,
    );
    final batchId = _newId();
    return _Header(
      batchId,
      created,
      envelopeAad(
        projectId: projectId,
        batchId: batchId,
        createdAt: envelopeCreatedAt(created),
        eventCount: records.length,
      ),
    );
  }

  SealedEnvelope _assemble(
    List<LogRecord> records,
    _Header header,
    Uint8List plaintext,
    Uint8List key,
    Uint8List iv,
    AesGcmResult encrypted,
  ) {
    final wrappedKey = backend.rsaOaepWrap(publicKey, key);

    if (iv.length != _ivLength ||
        encrypted.tag.length != _tagLength ||
        wrappedKey.length != _wrappedKeyLength ||
        encrypted.ciphertext.length != plaintext.length) {
      throw StateError('Crypto backend returned unexpected sizes');
    }

    var seqMin = records.first.seq;
    var seqMax = seqMin;
    var minTs = records.first.timestamp.millisecondsSinceEpoch;
    var maxTs = minTs;
    final levels = <int>{};
    for (final record in records) {
      if (record.seq < seqMin) seqMin = record.seq;
      if (record.seq > seqMax) seqMax = record.seq;
      final ts = record.timestamp.millisecondsSinceEpoch;
      if (ts < minTs) minTs = ts;
      if (ts > maxTs) maxTs = ts;
      levels.add(record.level.index);
    }
    final ordered = levels.toList()..sort();

    return SealedEnvelope(
      batchId: header.batchId,
      projectId: projectId,
      createdAt: header.createdAt,
      eventCount: records.length,
      wrappedKey: wrappedKey,
      iv: iv,
      tag: encrypted.tag,
      ciphertext: encrypted.ciphertext,
      seqMin: seqMin,
      seqMax: seqMax,
      minTs: minTs,
      maxTs: maxTs,
      topLevels: ordered.map((i) => LogLevel.values[i].name).join(','),
      payloadSize: plaintext.length,
    );
  }
}

/// The clear header of an envelope being sealed, and its AAD.
class _Header {
  const _Header(this.batchId, this.createdAt, this.aad);

  final String batchId;
  final DateTime createdAt;
  final Uint8List aad;
}
