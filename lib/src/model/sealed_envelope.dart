import 'dart:convert';
import 'dart:typed_data';

/// The only envelope version this SDK produces.
const int envelopeVersion = 1;

/// The fixed algorithm identifier carried by every envelope.
const String envelopeAlgorithm = 'RSA-OAEP-2048-SHA256+AES-256-GCM';

/// An encrypted batch of events plus the clear index data stored beside it.
///
/// The index columns (`eventCount`, `seqMin`, `seqMax`, `minTs`, `maxTs`,
/// `topLevels`, `payloadSize`) let retention and upload scheduling work
/// without ever decrypting. They contain no message text.
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

  /// The wire form defined by the envelope format (section 7).
  Map<String, dynamic> toWireJson() => <String, dynamic>{
    'v': envelopeVersion,
    'batchId': batchId,
    'projectId': projectId,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'eventCount': eventCount,
    'alg': envelopeAlgorithm,
    'wrappedKey': base64Encode(wrappedKey),
    'iv': base64Encode(iv),
    'tag': base64Encode(tag),
    'ciphertext': base64Encode(ciphertext),
  };
}
