import 'dart:convert';

import '../model/sealed_envelope.dart';
import '../storage/storage_adapter.dart';

/// Rows chosen for one request, and rows that can never be sent.
class PackedBatch {
  /// Creates a result.
  const PackedBatch(this.rows, this.oversized);

  /// Rows for the next request, oldest first.
  final List<EnvelopeRow> rows;

  /// Rows too large to fit in any request.
  final List<EnvelopeRow> oversized;
}

/// Builds requests within the contract limits: at most 50 envelopes and at
/// most [maxRequestBytes] of serialized body.
abstract final class BatchPacker {
  /// Envelopes per request, from the contract.
  static const int maxEnvelopesPerRequest = 50;

  /// Serialized request size limit. The contract says "2 MB"; decimal
  /// megabytes are used so the cap holds whichever way the server counts.
  static const int maxRequestBytes = 2000000;

  // `{"envelopes":[` and `]}`.
  static const int _wrapperBytes = 16;

  /// The exact size of [envelope]'s wire JSON in bytes.
  static int wireBytes(SealedEnvelope envelope) =>
      utf8.encode(jsonEncode(envelope.toWireJson())).length;

  /// The size of a request body holding [envelopes].
  static int bodyBytes(Iterable<SealedEnvelope> envelopes) {
    var total = _wrapperBytes;
    var count = 0;
    for (final envelope in envelopes) {
      total += wireBytes(envelope);
      count++;
    }
    return count > 1 ? total + count - 1 : total;
  }

  /// Takes rows from the front of [rows] (oldest first) until a limit is hit.
  static PackedBatch pack(
    List<EnvelopeRow> rows, {
    int maxEnvelopes = maxEnvelopesPerRequest,
    int maxBytes = maxRequestBytes,
  }) {
    final limit = maxEnvelopes.clamp(1, maxEnvelopesPerRequest);
    final batch = <EnvelopeRow>[];
    final oversized = <EnvelopeRow>[];
    var total = _wrapperBytes;
    for (final row in rows) {
      final size = wireBytes(row.envelope);
      if (_wrapperBytes + size > maxBytes) {
        oversized.add(row);
        continue;
      }
      if (batch.length >= limit) break;
      final separator = batch.isEmpty ? 0 : 1;
      if (total + separator + size > maxBytes) break;
      total += separator + size;
      batch.add(row);
    }
    return PackedBatch(batch, oversized);
  }

  /// Half of [rows], at least one: the response to HTTP 413.
  static List<EnvelopeRow> halve(List<EnvelopeRow> rows) {
    final keep = rows.length ~/ 2;
    return rows.take(keep < 1 ? 1 : keep).toList();
  }
}
