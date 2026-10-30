import 'package:web/web.dart' as web;

import '../model/sealed_envelope.dart';
import 'envelope_spill.dart';

/// The page-exit spill on the web: `localStorage`, which writes synchronously.
/// Returns null when `localStorage` is unavailable (blocked or a worker).
EnvelopeSpill? openPlatformEnvelopeSpill() {
  try {
    final storage = web.window.localStorage;
    storage.length; // Throws when storage is blocked.
    return LocalStorageEnvelopeSpill(storage);
  } catch (_) {
    return null;
  }
}

/// An [EnvelopeSpill] over `localStorage`, one key per envelope.
class LocalStorageEnvelopeSpill implements EnvelopeSpill {
  /// Creates a spill over [storage] holding at most [maxChars].
  LocalStorageEnvelopeSpill(
    this._storage, {
    this.maxChars = defaultSpillMaxChars,
  });

  final web.Storage _storage;

  /// Capacity in encoded characters.
  final int maxChars;

  /// Prefix of every key this spill owns.
  static const String keyPrefix = 'sealed_trace.spill.';

  Map<String, String> _entries() {
    final out = <String, String>{};
    for (var i = 0; i < _storage.length; i++) {
      final key = _storage.key(i);
      if (key == null || !key.startsWith(keyPrefix)) continue;
      final value = _storage.getItem(key);
      if (value != null) out[key.substring(keyPrefix.length)] = value;
    }
    return out;
  }

  @override
  bool write(SealedEnvelope envelope) {
    try {
      final encoded = encodeSpilledEnvelope(envelope);
      final used = _entries().values.fold<int>(0, (s, e) => s + e.length);
      if (used + encoded.length > maxChars) return false;
      _storage.setItem('$keyPrefix${envelope.batchId}', encoded);
      return true;
    } catch (_) {
      // QuotaExceededError or blocked storage; setItem writes all or nothing.
      return false;
    }
  }

  @override
  List<SealedEnvelope> readAll() {
    try {
      return sortedSpill(_entries(), remove);
    } catch (_) {
      return <SealedEnvelope>[];
    }
  }

  @override
  void remove(String batchId) {
    try {
      _storage.removeItem('$keyPrefix$batchId');
    } catch (_) {
      // Nothing more can be done; the entry is retried on the next start.
    }
  }
}
