import 'dart:async';
import 'dart:math';

import '../config/upload_config.dart';
import '../diagnostics/diagnostic_counters.dart';
import '../model/sealed_envelope.dart';
import '../model/upload_result.dart';
import '../platform/clock.dart';
import '../platform/connectivity_monitor.dart';
import '../storage/envelope_store.dart';
import '../storage/storage_adapter.dart';
import '../transport/ingest_response.dart';
import '../transport/ingest_transport.dart';
import 'backoff.dart';
import 'batch_packer.dart';
import 'dead_letter_policy.dart';
import 'triggers.dart';

/// Decides when stored envelopes are sent and what happens to them afterwards.
///
/// One cycle runs at a time. A trigger that arrives meanwhile queues a single
/// follow-up cycle that all later triggers share. Rows leave storage only when
/// the server acknowledges their batch id. Nothing in here throws.
class UploadScheduler {
  /// Creates a scheduler. Call [start] to begin.
  UploadScheduler({
    required this.store,
    required this.client,
    required this.config,
    required this.counters,
    required this.clock,
    required this.backoff,
    required this.connectivity,
    required this.onResult,
    required this.onError,
    required this.purge,
  });

  /// Where envelopes are read from and removed.
  final EnvelopeStore store;

  /// Sends requests.
  final IngestClient client;

  /// Upload settings (already clamped).
  final UploadConfig config;

  /// Shared diagnostic counters.
  final DiagnosticCounters counters;

  /// Source of "now".
  final Clock clock;

  /// Retry delays.
  final Backoff backoff;

  /// Online/offline hint.
  final ConnectivityMonitor connectivity;

  /// Receives the result of every cycle that attempted something.
  final void Function(UploadResult result) onResult;

  /// Receives swallowed failures.
  final void Function(Object error, StackTrace stack) onError;

  /// Runs retention; rows in `protected` must not be removed.
  final Future<int> Function({Set<String> protected}) purge;

  bool _disposed = false;
  bool _paused = false;
  bool _pauseReported = false;
  bool _running = false;
  bool _deadLettersTried = false;
  int _consecutiveFailures = 0;
  int _pendingEvents = 0;
  int _pendingBytes = 0;

  Future<UploadResult> _current = Future<UploadResult>.value(
    UploadResult.skipped(),
  );
  Future<UploadResult>? _queued;
  Timer? _intervalTimer;
  Timer? _retryTimer;
  StreamSubscription<bool>? _connectivitySubscription;
  final Set<String> _inFlight = <String>{};

  /// Ids of envelopes in a request right now.
  Set<String> get inFlightIds => _inFlight;

  /// Whether uploads are paused because the server rejected the API key.
  bool get isPaused => _paused;

  /// Finishes any delete that a crash interrupted, starts the timers and the
  /// connectivity listener, and kicks off the cold-start cycle.
  Future<void> start() async {
    try {
      await store.deleteAcknowledged();
      await _refreshPending();
    } catch (error, stack) {
      onError(error, stack);
    }
    if (_disposed) return;

    _intervalTimer = Timer.periodic(
      config.interval,
      (_) => unawaited(request(UploadTrigger.interval)),
    );
    if (config.uploadOnConnectivityRestored) {
      _connectivitySubscription = connectivity.onlineChanges.listen((online) {
        if (online) unawaited(request(UploadTrigger.connectivity));
      });
    }
    unawaited(request(UploadTrigger.coldStart));
  }

  /// Asks for an upload cycle. The future completes with that cycle's result
  /// and never fails.
  Future<UploadResult> request(UploadTrigger trigger) {
    if (_disposed) return Future<UploadResult>.value(UploadResult.skipped());
    if (_retryTimer != null && !_bypassesBackoff(trigger)) {
      return Future<UploadResult>.value(UploadResult.skipped());
    }
    final queued = _queued;
    if (queued != null) return queued;
    if (!_running) return _begin(trigger);

    final next = _current.then<UploadResult>((_) {
      _queued = null;
      if (_disposed) return UploadResult.skipped();
      if (_retryTimer != null && !_bypassesBackoff(trigger)) {
        return UploadResult.skipped();
      }
      return _begin(trigger);
    });
    _queued = next;
    return next;
  }

  /// Records that an envelope was stored, and starts a cycle when enough data
  /// is waiting.
  void noteStored(SealedEnvelope envelope) {
    _pendingEvents += envelope.eventCount;
    _pendingBytes += envelope.storedBytes;
    final byEvents =
        config.sizeThresholdEvents > 0 &&
        _pendingEvents >= config.sizeThresholdEvents;
    final byBytes =
        config.sizeThresholdBytes > 0 &&
        _pendingBytes >= config.sizeThresholdBytes;
    if (byEvents || byBytes) unawaited(request(UploadTrigger.threshold));
  }

  /// Stops timers, cancels a request in progress, and waits for the running
  /// cycle to finish.
  Future<void> dispose() async {
    _disposed = true;
    _intervalTimer?.cancel();
    _intervalTimer = null;
    _retryTimer?.cancel();
    _retryTimer = null;
    // Cancel first, before any await, so a request in progress ends at once.
    client.cancelInFlight();
    await _connectivitySubscription?.cancel();
    _connectivitySubscription = null;
    await _current;
  }

  // Only a person asking, or the network coming back, may skip a backoff wait.
  static bool _bypassesBackoff(UploadTrigger trigger) =>
      trigger == UploadTrigger.manual || trigger == UploadTrigger.connectivity;

  Future<UploadResult> _begin(UploadTrigger trigger) {
    _running = true;
    final cycle = _runCycle(trigger).whenComplete(() => _running = false);
    _current = cycle;
    return cycle;
  }

  Future<UploadResult> _runCycle(UploadTrigger trigger) async {
    try {
      return await _cycle(trigger);
    } catch (error, stack) {
      onError(error, stack);
      return UploadResult(
        outcome: UploadOutcome.failed,
        at: clock.now().toUtc(),
      );
    }
  }

  Future<UploadResult> _cycle(UploadTrigger trigger) async {
    if (_disposed) return UploadResult.skipped();
    if (_paused) {
      return UploadResult(
        outcome: UploadOutcome.unauthorized,
        at: clock.now().toUtc(),
      );
    }
    if (connectivity.isOnline == false) return UploadResult.skipped();

    // This cycle supersedes any scheduled retry.
    _retryTimer?.cancel();
    _retryTimer = null;

    final totals = _Totals();
    final failedIds = <String>{};
    var limit = min(
      max(config.batchSize, 1),
      BatchPacker.maxEnvelopesPerRequest,
    );
    Duration? retryIn;
    var hadFailure = false;

    if (trigger == UploadTrigger.coldStart && !_deadLettersTried) {
      _deadLettersTried = true;
      retryIn = await _retryDeadLetters(totals, limit);
    }

    while (!_disposed && !_paused && retryIn == null) {
      final rows = await store.nextPending(
        limit: limit,
        maxBytes: 1 << 40,
        exclude: failedIds,
      );
      if (rows.isEmpty) break;

      final packed = BatchPacker.pack(rows, maxEnvelopes: limit);
      if (packed.oversized.isNotEmpty) {
        // Too big for any request: it can never be sent.
        await store.deadLetterNow(
          packed.oversized.map((r) => r.envelope.batchId),
          clock.now(),
        );
        totals.rejected += packed.oversized.length;
        totals.attempted = true;
      }
      if (packed.rows.isEmpty) continue;

      final ids = packed.rows.map((r) => r.envelope.batchId).toList();
      _inFlight.addAll(ids);
      counters.uploadAttempts++;
      totals.attempted = true;
      final IngestOutcome outcome;
      try {
        outcome = await client.send(
          packed.rows.map((r) => r.envelope).toList(),
        );
      } finally {
        _inFlight.removeAll(ids);
      }

      switch (outcome) {
        case IngestAccepted():
          if (await _handleAccepted(outcome, packed.rows, totals, failedIds)) {
            hadFailure = true;
          }
        case IngestUnauthorized():
          counters.uploadFailures++;
          totals.unauthorized = true;
          _pause(outcome.status);
        case IngestTooLarge():
          counters.uploadFailures++;
          if (packed.rows.length > 1) {
            limit = BatchPacker.halve(packed.rows).length;
          } else {
            await store.deadLetterNow(ids, clock.now());
            totals.rejected += ids.length;
          }
        case IngestRateLimited():
          counters.uploadFailures++;
          _consecutiveFailures++;
          hadFailure = true;
          retryIn = outcome.retryAfter ?? backoff.delay(_consecutiveFailures);
        case IngestServerError():
        case IngestNetworkError():
        case IngestTimeout():
          counters.uploadFailures++;
          await store.recordFailure(
            ids,
            clock.now(),
            maxAttempts: config.maxAttempts,
          );
          failedIds.addAll(ids);
          totals.failed += ids.length;
          _consecutiveFailures++;
          hadFailure = true;
          retryIn = backoff.delay(_consecutiveFailures);
        case IngestCancelled():
          failedIds.addAll(ids);
          totals.cancelled = true;
      }
      if (totals.cancelled) break;
    }

    if (!hadFailure && !totals.cancelled) _consecutiveFailures = 0;
    if (hadFailure && retryIn == null) {
      // Rejections the server called transient: retry later, with backoff.
      _consecutiveFailures++;
      retryIn = backoff.delay(_consecutiveFailures);
    }
    if (retryIn != null) _scheduleRetry(retryIn);

    await _refreshPending();
    await purge(protected: Set<String>.of(_inFlight));

    final result = totals.toResult(clock.now().toUtc());
    if (totals.attempted && !_disposed) onResult(result);
    return result;
  }

  /// Applies a 202 response. Returns whether any envelope is left to retry.
  Future<bool> _handleAccepted(
    IngestAccepted outcome,
    List<EnvelopeRow> rows,
    _Totals totals,
    Set<String> failedIds,
  ) async {
    final now = clock.now();
    final sent = <String>{for (final r in rows) r.envelope.batchId};
    final accepted = outcome.accepted.where(sent.contains).toSet();
    final duplicate = outcome.duplicate
        .where((id) => sent.contains(id) && !accepted.contains(id))
        .toSet();
    final acknowledged = <String>{...accepted, ...duplicate};
    if (acknowledged.isNotEmpty) {
      await store.markUploadedAndDelete(acknowledged, now);
    }

    final permanent = <String>[];
    final transient = <String>[];
    final rejectedIds = <String>{};
    for (final rejection in outcome.rejected) {
      final id = rejection.batchId;
      if (!sent.contains(id) || acknowledged.contains(id)) continue;
      if (!rejectedIds.add(id)) continue;
      (DeadLetterPolicy.isPermanent(rejection.reason) ? permanent : transient)
          .add(id);
    }
    // Sent but not mentioned anywhere: not acknowledged, so it stays.
    final unlisted = sent.difference(acknowledged).difference(rejectedIds);

    if (permanent.isNotEmpty) await store.deadLetterNow(permanent, now);
    final toFail = <String>[...transient, ...unlisted];
    if (toFail.isNotEmpty) {
      await store.recordFailure(toFail, now, maxAttempts: config.maxAttempts);
    }

    failedIds.addAll(sent.difference(acknowledged));
    totals.accepted += accepted.length;
    totals.duplicate += duplicate.length;
    totals.rejected += permanent.length + transient.length;
    totals.failed += unlisted.length;
    return toFail.isNotEmpty;
  }

  /// Sends dead-lettered envelopes once, at cold start.
  ///
  /// A success deletes the row. A failure leaves it flagged and costs no
  /// attempt. Returns a delay when the server asked us to wait.
  Future<Duration?> _retryDeadLetters(_Totals totals, int limit) async {
    final tried = <String>{};
    while (!_disposed && !_paused) {
      final rows = await store.nextDeadLetters(limit: limit, exclude: tried);
      if (rows.isEmpty) return null;
      final packed = BatchPacker.pack(rows, maxEnvelopes: limit);
      tried.addAll(rows.map((r) => r.envelope.batchId));
      if (packed.rows.isEmpty) continue;

      final ids = packed.rows.map((r) => r.envelope.batchId).toList();
      _inFlight.addAll(ids);
      counters.uploadAttempts++;
      final IngestOutcome outcome;
      try {
        outcome = await client.send(
          packed.rows.map((r) => r.envelope).toList(),
        );
      } finally {
        _inFlight.removeAll(ids);
      }

      switch (outcome) {
        case IngestAccepted():
          final sent = ids.toSet();
          final accepted = outcome.accepted.where(sent.contains).toSet();
          final duplicate = outcome.duplicate
              .where((id) => sent.contains(id) && !accepted.contains(id))
              .toSet();
          final acknowledged = <String>{...accepted, ...duplicate};
          if (acknowledged.isNotEmpty) {
            await store.markUploadedAndDelete(acknowledged, clock.now());
            totals.accepted += accepted.length;
            totals.duplicate += duplicate.length;
            totals.attempted = true;
          }
        case IngestUnauthorized():
          counters.uploadFailures++;
          totals.unauthorized = true;
          _pause(outcome.status);
          return null;
        case IngestRateLimited():
          counters.uploadFailures++;
          return outcome.retryAfter ?? backoff.delay(_consecutiveFailures + 1);
        case IngestTooLarge():
        case IngestServerError():
        case IngestNetworkError():
        case IngestTimeout():
          counters.uploadFailures++;
          return null; // Leave them flagged; do not hammer a failing server.
        case IngestCancelled():
          return null;
      }
    }
    return null;
  }

  void _pause(int status) {
    _paused = true;
    _retryTimer?.cancel();
    _retryTimer = null;
    if (!_pauseReported) {
      _pauseReported = true;
      onError(
        StateError(
          'Uploads paused: the server rejected the API key (HTTP $status)',
        ),
        StackTrace.current,
      );
    }
  }

  void _scheduleRetry(Duration delay) {
    if (_disposed || _paused) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      unawaited(request(UploadTrigger.retry));
    });
  }

  Future<void> _refreshPending() async {
    final stats = await store.stats();
    _pendingEvents = stats.pendingEvents;
    _pendingBytes = stats.pendingBytes;
  }
}

class _Totals {
  int accepted = 0;
  int duplicate = 0;
  int rejected = 0;
  int failed = 0;
  bool attempted = false;
  bool unauthorized = false;
  bool cancelled = false;

  UploadResult toResult(DateTime at) {
    final acknowledged = accepted + duplicate;
    final UploadOutcome outcome;
    if (unauthorized) {
      outcome = UploadOutcome.unauthorized;
    } else if (!attempted) {
      outcome = UploadOutcome.skipped;
    } else if (acknowledged > 0) {
      outcome = rejected + failed > 0
          ? UploadOutcome.partial
          : UploadOutcome.success;
    } else {
      outcome = UploadOutcome.failed;
    }
    return UploadResult(
      outcome: outcome,
      at: at,
      accepted: accepted,
      duplicate: duplicate,
      rejected: rejected,
      failed: failed,
    );
  }
}
