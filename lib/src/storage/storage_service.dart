import 'dart:async';

import '../diagnostics/diagnostic_counters.dart';
import '../model/sealed_envelope.dart';
import '../platform/clock.dart';
import 'envelope_store.dart';

/// Owns the open store: saves envelopes, runs retention at start and on a
/// timer, and closes the database. Failures are counted and reported, never
/// thrown to the caller of a logging method.
class StorageService {
  /// Creates the service.
  StorageService({
    required this.store,
    required this.purgeInterval,
    required this.clock,
    required this.counters,
    required this.onError,
  });

  /// The envelope store.
  final EnvelopeStore store;

  /// How often retention runs in the background.
  final Duration purgeInterval;

  /// Source of "now" for retention.
  final Clock clock;

  /// Shared diagnostic counters.
  final DiagnosticCounters counters;

  /// Receives swallowed failures.
  final void Function(Object error, StackTrace stack) onError;

  /// Called after an envelope has been stored. Set by the uploader.
  void Function(SealedEnvelope envelope)? onStored;

  /// Ids of envelopes being uploaded right now; retention never removes them.
  Set<String> Function()? inFlight;

  Timer? _timer;

  /// Runs retention once, then schedules it every [purgeInterval].
  Future<void> start() async {
    await purge();
    _timer = Timer.periodic(purgeInterval, (_) => unawaited(purge()));
  }

  /// Saves a sealed envelope. Counts and rethrows a failure so the queue
  /// reports it.
  Future<void> save(SealedEnvelope envelope) async {
    try {
      await store.append(envelope);
    } catch (_) {
      counters.storageFailures++;
      rethrow;
    }
    try {
      onStored?.call(envelope);
    } catch (error, stack) {
      onError(error, stack);
    }
  }

  /// Applies retention now. Returns the number of rows removed; a failure is
  /// counted and reported, and returns 0.
  Future<int> purge({Set<String> protected = const <String>{}}) async {
    try {
      return await store.purge(
        clock.now(),
        protected: <String>{...protected, ...?inFlight?.call()},
      );
    } catch (error, stack) {
      counters.storageFailures++;
      onError(error, stack);
      return 0;
    }
  }

  /// Removes every stored envelope.
  Future<void> clear() => store.clear();

  /// Stops the timer and closes the database.
  Future<void> dispose() async {
    _timer?.cancel();
    _timer = null;
    try {
      await store.adapter.close();
    } catch (error, stack) {
      onError(error, stack);
    }
  }
}
