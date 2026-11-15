import 'dart:convert';
import 'dart:typed_data';

/// The envelope version this SDK produces.
///
/// Version 3 (I3) adds `kid`, the project key's identifier (see
/// `keyId`), to the wire JSON and to the AAD, and allows RSA keys of 2048,
/// 3072 and 4096 bits. Version 2 authenticated the clear header without a
/// `kid`; envelopes stored by a v2 build are still sent as v2
/// ([legacyEnvelopeVersion]). Version 1 had no AAD.
const int envelopeVersion = 3;

/// The version of envelopes sealed before `kid` existed (no `kid`, RSA-2048).
const int legacyEnvelopeVersion = 2;

/// RSA modulus sizes accepted for the project key, in bits.
const Set<int> supportedRsaModulusBits = <int>{2048, 3072, 4096};

/// The algorithm identifier for an RSA key of [modulusBits] bits.
String envelopeAlgorithmFor(int modulusBits) =>
    'RSA-OAEP-$modulusBits-SHA256+AES-256-GCM';

/// The algorithm identifier for RSA-2048, the only one before v3.
const String envelopeAlgorithm = 'RSA-OAEP-2048-SHA256+AES-256-GCM';

/// First line of the v3 additional authenticated data, for domain
/// separation.
const String envelopeAadTag = 'sealed_trace.envelope.v3';

/// First line of the v2 additional authenticated data.
const String legacyEnvelopeAadTag = 'sealed_trace.envelope.v2';

final RegExp _kidPattern = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

/// The AES-GCM additional authenticated data for an envelope's header.
///
/// UTF-8 bytes of lines joined by a single LF (`0x0A`, no trailing LF), each
/// exactly as it appears in the wire JSON (`createdAt` as the ISO-8601
/// string, `eventCount` in decimal):
///
/// - **v3** (with [kid]): [envelopeAadTag], `alg`, `projectId`, `batchId`,
///   `createdAt`, `eventCount`, `kid`.
/// - **v2** ([kid] null): [legacyEnvelopeAadTag], `alg`, `projectId`,
///   `batchId`, `createdAt`, `eventCount`.
///
/// A server rebuilds it from the received fields, so changing any of them
/// makes decryption fail.
///
/// Throws [ArgumentError] if a field contains a line break, which would make
/// the encoding ambiguous, or if [kid] is not 1–64 base64url characters.
Uint8List envelopeAad({
  required String projectId,
  required String batchId,
  required String createdAt,
  required int eventCount,
  String algorithm = envelopeAlgorithm,
  String? kid,
}) {
  for (final (name, value) in [
    ('projectId', projectId),
    ('batchId', batchId),
    ('createdAt', createdAt),
    ('algorithm', algorithm),
  ]) {
    if (value.contains('\n') || value.contains('\r')) {
      throw ArgumentError.value(value, name, 'must not contain a line break');
    }
  }
  if (kid != null && !_kidPattern.hasMatch(kid)) {
    throw ArgumentError.value(kid, 'kid', 'must be 1-64 base64url characters');
  }
  return Uint8List.fromList(
    utf8.encode(
      [
        kid == null ? legacyEnvelopeAadTag : envelopeAadTag,
        algorithm,
        projectId,
        batchId,
        createdAt,
        '$eventCount',
        ?kid,
      ].join('\n'),
    ),
  );
}

/// The wire form of a `createdAt` time: UTC ISO-8601 with milliseconds.
String envelopeCreatedAt(DateTime createdAt) =>
    createdAt.toUtc().toIso8601String();

/// An encrypted batch of events plus the clear index data stored beside it.
///
/// The index columns let retention and upload scheduling work without ever
/// decrypting. They contain no message text. Since L6 the sealer leaves
/// `seqMin`, `seqMax`, `minTs` and `maxTs` at 0 and `topLevels` empty, and
/// `payloadSize` is the padded size, so the clear index reveals only the
/// batch's time, event count and size bucket.
class SealedEnvelope {
  /// Creates an envelope.
  const SealedEnvelope({
    required this.batchId,
    required this.projectId,
    required this.createdAt,
    required this.eventCount,
    required this.wrappedKey,
    required this.iv,
    required this.tag,
    required this.ciphertext,
    required this.seqMin,
    required this.seqMax,
    required this.minTs,
    required this.maxTs,
    required this.topLevels,
    required this.payloadSize,
    this.kid,
  });

  /// uuid-v4 identifying the batch; the server deduplicates on it.
  final String batchId;

  /// The project the batch belongs to.
  final String projectId;

  /// When the envelope was created (UTC).
  final DateTime createdAt;

  /// Number of events inside.
  final int eventCount;

  /// The AES key wrapped with the project's RSA public key: as long as its
  /// modulus (256, 384 or 512 bytes).
  final Uint8List wrappedKey;

  /// The 12-byte AES-GCM nonce.
  final Uint8List iv;

  /// The 16-byte AES-GCM tag.
  final Uint8List tag;

  /// The encrypted JSON array of events.
  final Uint8List ciphertext;

  /// Smallest event `seq` inside.
  final int seqMin;

  /// Largest event `seq` inside.
  final int seqMax;

  /// Earliest event timestamp inside, epoch milliseconds.
  final int minTs;

  /// Latest event timestamp inside, epoch milliseconds.
  final int maxTs;

  /// Distinct levels inside, in severity order, comma separated.
  final String topLevels;

  /// Size of the plaintext JSON in bytes, before encryption.
  final int payloadSize;

  /// Bytes this envelope occupies in storage (all four binary fields).
  int get storedBytes =>
      wrappedKey.length + iv.length + tag.length + ciphertext.length;

  /// The identifier of the project key this envelope was sealed to, or null
  /// for an envelope stored by a v2 build (I3).
  final String? kid;

  /// The wire format version: [envelopeVersion] with a [kid],
  /// [legacyEnvelopeVersion] without.
  int get version => kid == null ? legacyEnvelopeVersion : envelopeVersion;

  /// The algorithm identifier, from the wrapped key's size.
  String get algorithm => envelopeAlgorithmFor(wrappedKey.length * 8);

  /// The additional authenticated data this envelope was sealed with.
  Uint8List get aad => envelopeAad(
    projectId: projectId,
    batchId: batchId,
    createdAt: envelopeCreatedAt(createdAt),
    eventCount: eventCount,
    algorithm: algorithm,
    kid: kid,
  );

  /// The wire form defined by the envelope format (section 7).
  Map<String, dynamic> toWireJson() => <String, dynamic>{
    'v': version,
    'batchId': batchId,
    'projectId': projectId,
    'createdAt': envelopeCreatedAt(createdAt),
    'eventCount': eventCount,
    'alg': algorithm,
    'kid': ?kid,
    'wrappedKey': base64Encode(wrappedKey),
    'iv': base64Encode(iv),
    'tag': base64Encode(tag),
    'ciphertext': base64Encode(ciphertext),
  };
}
