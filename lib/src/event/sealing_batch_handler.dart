import '../crypto/envelope_sealer.dart';
import '../diagnostics/diagnostic_counters.dart';
import '../model/sealed_envelope.dart';
import 'log_record.dart';

/// Receives an envelope that has been sealed and is ready to be stored.
typedef EnvelopeSink = Future<void> Function(SealedEnvelope envelope);

/// Turns each queued batch into a sealed envelope and passes it on.
///
/// Fails closed: a batch that cannot be sealed is dropped, counted in
/// `sealFailures` and reported, and is never forwarded in plaintext.
class SealingBatchHandler {
  /// Creates a handler.
  SealingBatchHandler({
    required this.sealer,
    required this.counters,
    required this.onError,
    required this.envelopeSink,
  });

  /// Produces the envelopes.
  final EnvelopeSealer sealer;

  /// Shared diagnostic counters.
  final DiagnosticCounters counters;

  /// Receives swallowed failures.
  final void Function(Object error, StackTrace stack) onError;

  /// Where sealed envelopes go. Storage replaces the discarding default.
  final EnvelopeSink envelopeSink;

  /// The queue's batch sink.
  Future<void> call(List<LogRecord> batch) async {
    final SealedEnvelope envelope;
    try {
      envelope = await sealer.seal(batch);
    } catch (error, stack) {
      counters.sealFailures++;
      onError(error, stack);
      return;
    }
    await envelopeSink(envelope);
  }
}
