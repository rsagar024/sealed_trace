import 'dart:async';

import '../crypto/envelope_sealer.dart';
import '../diagnostics/diagnostic_counters.dart';
import '../model/sealed_envelope.dart';
import '../queue/write_behind_queue.dart';
import '../storage/envelope_spill.dart';
import 'log_record.dart';
import 'sealing_batch_handler.dart';

/// Saves the write-behind queue when a browser page is hidden or left.
///
/// An asynchronous IndexedDB write started from `pagehide` does not commit
/// when the page is frozen into the back/forward cache (Chrome, Edge) or torn
/// down (Firefox). So the queue is sealed and written to an [EnvelopeSpill]
/// synchronously, inside the event, and each envelope is then moved to
/// regular storage in the background. Whatever is still in the spill at the
/// next start is moved by [recover]. Moving is idempotent: storage keys rows
/// by batch id, and the server deduplicates on it.
class PageExitSaver {
  /// Creates a saver.
  PageExitSaver({
    required this.queue,
    required this.sealer,
    required this.spill,
    required this.store,
    required this.counters,
    required this.onError,
  });

  /// The queue to drain.
  final WriteBehindQueue queue;

  /// Seals on the calling thread.
  final EnvelopeSealer sealer;

  /// The synchronous store.
  final EnvelopeSpill spill;

  /// Regular storage (normally `StorageService.save`).
  final EnvelopeSink store;

  /// Shared diagnostic counters.
  final DiagnosticCounters counters;

  /// Receives swallowed failures.
  final void Function(Object error, StackTrace stack) onError;

  /// Drains, seals and spills everything queued, synchronously.
  ///
  /// Once the spill refuses an envelope, that envelope and every later batch
  /// go to [store] asynchronously instead (best effort), so a long queue
  /// cannot hold the page exit for longer than filling the spill takes.
  void saveNow() {
    var spillFull = false;
    for (final batch in queue.takeBatches()) {
      if (spillFull) {
        unawaited(Future<void>(() => _sealAndStore(batch)));
        continue;
      }
      final envelope = _sealOrReport(batch);
      if (envelope == null) continue;
      if (spill.write(envelope)) {
        unawaited(_move(envelope));
      } else {
        spillFull = true;
        unawaited(_store(envelope));
      }
    }
  }

  /// Most envelopes taken from the spill at one start. A real page exit
  /// writes at most the queue's worth (5 000 events in batches of 25).
  static const int maxRecovered = 200;

  /// How far in the future a spilled `createdAt` may be (clock skew).
  static const Duration maxFutureSkew = Duration(days: 1);

  /// Moves spilled envelopes to regular storage. Returns how many moved.
  ///
  /// The spill is `localStorage`, which any script on the origin can write,
  /// so an entry is dropped, and counted in `spillEntriesRejected`, if it
  /// belongs to another project, is dated more than [maxFutureSkew] ahead,
  /// or is beyond the newest [maxRecovered]. Entries that do not decode are
  /// dropped by [EnvelopeSpill.readAll] (not counted).
  Future<int> recover() async {
    final now = sealer.clock.now().toUtc();
    final accepted = <SealedEnvelope>[];
    for (final envelope in spill.readAll()) {
      final ours =
          envelope.projectId == sealer.projectId &&
          !envelope.createdAt.isAfter(now.add(maxFutureSkew));
      if (ours) {
        accepted.add(envelope);
      } else {
        _reject(envelope);
      }
    }
    // readAll is oldest first; keep the newest maxRecovered.
    final excess = accepted.length - maxRecovered;
    if (excess > 0) {
      accepted.take(excess).forEach(_reject);
      accepted.removeRange(0, excess);
    }
    var moved = 0;
    for (final envelope in accepted) {
      if (await _move(envelope)) moved++;
    }
    return moved;
  }

  void _reject(SealedEnvelope envelope) {
    counters.spillEntriesRejected++;
    spill.remove(envelope.batchId);
  }

  /// Removes everything from the spill (for `clearLocalLogs`).
  void clear() {
    for (final envelope in spill.readAll()) {
      spill.remove(envelope.batchId);
    }
  }

  SealedEnvelope? _sealOrReport(List<LogRecord> batch) {
    try {
      return sealer.sealSync(batch);
    } catch (error, stack) {
      // Fail closed, as in SealingBatchHandler: never stored in plaintext.
      counters.sealFailures++;
      onError(error, stack);
      return null;
    }
  }

  Future<void> _sealAndStore(List<LogRecord> batch) async {
    final envelope = _sealOrReport(batch);
    if (envelope != null) await _store(envelope);
  }

  Future<bool> _move(SealedEnvelope envelope) async {
    if (!await _store(envelope)) return false;
    spill.remove(envelope.batchId);
    return true;
  }

  Future<bool> _store(SealedEnvelope envelope) async {
    try {
      await store(envelope);
      return true;
    } catch (error, stack) {
      onError(error, stack);
      return false;
    }
  }
}
