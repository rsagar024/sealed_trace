import 'dart:convert';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../event/log_record.dart';
import '../model/sealed_envelope.dart';
import '../platform/clock.dart';
import 'crypto_backend.dart';
import 'public_key_parser.dart';

/// Seals a batch of events into an encrypted [SealedEnvelope].
///
/// The plaintext is the UTF-8 JSON array of the records (compact, in the field
/// order of `LogRecord.toJson`), followed by ASCII spaces up to its
/// [padmeLength], so its size is hidden within a bucket. A fresh 256-bit key and 96-bit IV encrypt it
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
    final json = utf8.encode(
      jsonEncode(<Map<String, dynamic>>[
        for (final record in records) record.toJson(),
      ]),
    );
    // Padded with ASCII spaces to a Padmé length (L6), so the ciphertext
    // length reveals only a size bucket. Trailing whitespace is valid JSON.
    final length = padmeLength(json.length);
    final padded = Uint8List(length)
      ..fillRange(0, length, 0x20)
      ..setRange(0, json.length, json);
    json.fillRange(0, json.length, 0);
    return padded;
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

    return SealedEnvelope(
      batchId: header.batchId,
      projectId: projectId,
      createdAt: header.createdAt,
      eventCount: records.length,
      wrappedKey: wrappedKey,
      iv: iv,
      tag: encrypted.tag,
      ciphertext: encrypted.ciphertext,
      // L6: the clear index no longer records sequence numbers, event times
      // or levels (whether a fatal occurred); nothing reads them, and they
      // are all inside the ciphertext. Retention uses createdAt, eventCount
      // and the stored size.
      seqMin: 0,
      seqMax: 0,
      minTs: 0,
      maxTs: 0,
      topLevels: '',
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

/// Smallest padded plaintext, in bytes.
const int minPaddedLength = 256;

/// The Padmé length for a plaintext of [length] bytes (Nikitin et al.,
/// "Reducing Metadata Leakage from Encrypted Files and Communication with
/// PURBs", PETS 2019): [length] rounded up so that only O(log log L) bits of
/// it are revealed, with at most about 12 % overhead. At least
/// [minPaddedLength].
int padmeLength(int length) {
  if (length <= minPaddedLength) return minPaddedLength;
  final e = length.bitLength - 1; // floor(log2 L)
  final s = e.bitLength; // floor(log2 E) + 1
  final lastBits = e - s;
  final mask = (1 << lastBits) - 1;
  return (length + mask) & ~mask;
}
