import 'dart:convert';

import '../model/sealed_envelope.dart';

export 'envelope_spill_stub.dart'
    if (dart.library.js_interop) 'envelope_spill_web.dart';

/// A small synchronous store for sealed envelopes, used only when the page is
/// being left.
///
/// IndexedDB commits asynchronously, and a page that is frozen into the
/// back/forward cache or torn down never finishes the write (seen in Chrome,
/// Edge and Firefox). A synchronous store survives. It holds exactly what
/// IndexedDB would: ciphertext plus index columns, never plaintext.
abstract interface class EnvelopeSpill {
  /// Stores [envelope] synchronously. Returns false if it did not fit or the
  /// store refused it; nothing is half-written.
  bool write(SealedEnvelope envelope);

  /// Every envelope currently held, oldest first. Unreadable entries are
  /// removed and skipped.
  List<SealedEnvelope> readAll();

  /// Removes the envelope with [batchId], if present.
  void remove(String batchId);
}

/// An [EnvelopeSpill] in memory, for tests and platforms without a page.
class MemoryEnvelopeSpill implements EnvelopeSpill {
  /// Creates a spill that holds at most [maxChars] of encoded data.
  MemoryEnvelopeSpill({this.maxChars = defaultSpillMaxChars});

  /// Capacity in encoded characters.
  final int maxChars;

  final Map<String, String> _entries = <String, String>{};

  @override
  bool write(SealedEnvelope envelope) {
    final encoded = encodeSpilledEnvelope(envelope);
    final used = _entries.values.fold<int>(0, (sum, e) => sum + e.length);
    if (used + encoded.length > maxChars) return false;
    _entries[envelope.batchId] = encoded;
    return true;
  }

  @override
  List<SealedEnvelope> readAll() => sortedSpill(_entries, _entries.remove);

  @override
  void remove(String batchId) => _entries.remove(batchId);
}

/// Default capacity: 1 M characters (localStorage allows about 5 M per
/// origin, shared with the host app).
const int defaultSpillMaxChars = 1024 * 1024;

/// Encodes [envelope] with its index columns as one JSON string.
String encodeSpilledEnvelope(SealedEnvelope envelope) => jsonEncode({
  ...envelope.toWireJson(),
  'seqMin': envelope.seqMin,
  'seqMax': envelope.seqMax,
  'minTs': envelope.minTs,
  'maxTs': envelope.maxTs,
  'topLevels': envelope.topLevels,
  'payloadSize': envelope.payloadSize,
});

/// Longest spilled entry accepted, in characters: one request's worth.
const int maxSpilledEntryChars = 3 * 1024 * 1024;

final RegExp _spillBatchId = RegExp(r'^[A-Za-z0-9_\-]{1,64}$');

const Set<String> _levelNames = <String>{
  'verbose',
  'debug',
  'info',
  'warning',
  'error',
  'fatal',
};

/// Decodes what [encodeSpilledEnvelope] produced. Throws on anything else.
///
/// The spill lives in `localStorage`, which any script on the origin can
/// write, so every field is checked: the format version and algorithm, the
/// exact sizes of the key, IV and tag, a ciphertext as long as its declared
/// plaintext, and consistent index columns. This rejects junk and truncated
/// entries; it cannot reject a well-formed envelope built with the public key
/// (see the README).
SealedEnvelope decodeSpilledEnvelope(String text) {
  if (text.length > maxSpilledEntryChars) {
    throw const FormatException('Spilled entry too large');
  }
  final m = jsonDecode(text) as Map<String, dynamic>;
  final version = m['v'];
  final kid = m['kid'];
  if (!((version == envelopeVersion && kid is String) ||
      (version == legacyEnvelopeVersion && kid == null))) {
    throw const FormatException('Unknown spilled envelope format');
  }
  final envelope = _decodeFields(m);
  _checkSpilled(envelope);
  // The algorithm must match the wrapped key's size (and be RSA-2048 for v1).
  if (m['alg'] != envelope.algorithm ||
      (kid == null && envelope.algorithm != envelopeAlgorithm)) {
    throw const FormatException('Unknown spilled envelope format');
  }
  return envelope;
}

void _checkSpilled(SealedEnvelope e) {
  if (!_spillBatchId.hasMatch(e.batchId) ||
      e.projectId.isEmpty ||
      e.projectId.length > 256 ||
      !supportedRsaModulusBits.contains(e.wrappedKey.length * 8) ||
      (e.kid != null && !_spillBatchId.hasMatch(e.kid!)) ||
      e.iv.length != 12 ||
      e.tag.length != 16 ||
      e.eventCount < 1 ||
      e.eventCount > 100000 ||
      e.payloadSize != e.ciphertext.length ||
      e.seqMin > e.seqMax ||
      e.minTs > e.maxTs ||
      (e.topLevels.isNotEmpty &&
          !e.topLevels.split(',').every(_levelNames.contains))) {
    throw const FormatException('Inconsistent spilled envelope');
  }
}

SealedEnvelope _decodeFields(Map<String, dynamic> m) {
  return SealedEnvelope(
    batchId: m['batchId'] as String,
    projectId: m['projectId'] as String,
    createdAt: DateTime.parse(m['createdAt'] as String).toUtc(),
    eventCount: m['eventCount'] as int,
    wrappedKey: base64Decode(m['wrappedKey'] as String),
    iv: base64Decode(m['iv'] as String),
    tag: base64Decode(m['tag'] as String),
    ciphertext: base64Decode(m['ciphertext'] as String),
    seqMin: m['seqMin'] as int,
    seqMax: m['seqMax'] as int,
    minTs: m['minTs'] as int,
    maxTs: m['maxTs'] as int,
    topLevels: m['topLevels'] as String,
    payloadSize: m['payloadSize'] as int,
    kid: m['kid'] as String?,
  );
}

/// Decodes [entries] (batch id to encoded text), oldest first, calling
/// [drop] for every entry that cannot be decoded.
List<SealedEnvelope> sortedSpill(
  Map<String, String> entries,
  void Function(String batchId) drop,
) {
  final out = <SealedEnvelope>[];
  for (final entry in entries.entries.toList()) {
    try {
      final envelope = decodeSpilledEnvelope(entry.value);
      // An entry stored under another batch's key is not ours.
      if (envelope.batchId != entry.key) {
        throw const FormatException('Spill key does not match the batch id');
      }
      out.add(envelope);
    } catch (_) {
      drop(entry.key);
    }
  }
  out.sort((a, b) {
    final byTime = a.createdAt.compareTo(b.createdAt);
    return byTime != 0 ? byTime : a.batchId.compareTo(b.batchId);
  });
  return out;
}
