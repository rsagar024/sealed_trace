import 'dart:convert';
import 'dart:typed_data';

/// The only envelope version this SDK produces.
///
/// Version 2 authenticates the clear header fields as AES-GCM additional
/// authenticated data (see [envelopeAad]). Version 1 had no AAD.
const int envelopeVersion = 2;

/// The fixed algorithm identifier carried by every envelope.
const String envelopeAlgorithm = 'RSA-OAEP-2048-SHA256+AES-256-GCM';

/// First line of the additional authenticated data, for domain separation.
const String envelopeAadTag = 'sealed_trace.envelope.v2';

/// The AES-GCM additional authenticated data for an envelope's header.
///
/// UTF-8 bytes of six lines joined by a single LF (`0x0A`, no trailing LF):
/// [envelopeAadTag], `alg`, `projectId`, `batchId`, `createdAt` and
/// `eventCount`, each exactly as it appears in the wire JSON (`createdAt` as
/// the ISO-8601 string, `eventCount` in decimal). A server rebuilds it from
/// the received fields, so changing any of them makes decryption fail.
///
/// Throws [ArgumentError] if a field contains a line break, which would make
/// the encoding ambiguous.
Uint8List envelopeAad({
  required String projectId,
  required String batchId,
  required String createdAt,
  required int eventCount,
  String algorithm = envelopeAlgorithm,
}) {
  for (final (name, value) in [
    ('projectId', projectId),
    ('batchId', batchId),
    ('createdAt', createdAt),
  ]) {
    if (value.contains('\n') || value.contains('\r')) {
      throw ArgumentError.value(value, name, 'must not contain a line break');
    }
  }
  return Uint8List.fromList(
    utf8.encode(
      [
        envelopeAadTag,
        algorithm,
        projectId,
        batchId,
        createdAt,
        '$eventCount',
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
  });

  /// uuid-v4 identifying the batch; the server deduplicates on it.
  final String batchId;

  /// The project the batch belongs to.
  final String projectId;

  /// When the envelope was created (UTC).
  final DateTime createdAt;

  /// Number of events inside.
  final int eventCount;

  /// The AES key wrapped with the project's RSA public key (256 bytes).
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

  /// The additional authenticated data this envelope was sealed with.
  Uint8List get aad => envelopeAad(
    projectId: projectId,
    batchId: batchId,
    createdAt: envelopeCreatedAt(createdAt),
    eventCount: eventCount,
  );

  /// The wire form defined by the envelope format (section 7).
  Map<String, dynamic> toWireJson() => <String, dynamic>{
    'v': envelopeVersion,
    'batchId': batchId,
    'projectId': projectId,
    'createdAt': envelopeCreatedAt(createdAt),
    'eventCount': eventCount,
    'alg': envelopeAlgorithm,
    'wrappedKey': base64Encode(wrappedKey),
    'iv': base64Encode(iv),
    'tag': base64Encode(tag),
    'ciphertext': base64Encode(ciphertext),
  };
}
