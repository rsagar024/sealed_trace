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

/// Decodes what [encodeSpilledEnvelope] produced. Throws on anything else.
SealedEnvelope decodeSpilledEnvelope(String text) {
  final m = jsonDecode(text) as Map<String, dynamic>;
  if (m['v'] != envelopeVersion || m['alg'] != envelopeAlgorithm) {
    throw const FormatException('Unknown spilled envelope format');
  }
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
      out.add(decodeSpilledEnvelope(entry.value));
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
