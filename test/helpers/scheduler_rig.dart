import 'dart:math';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/diagnostics/diagnostic_counters.dart';
import 'package:sealed_trace/src/storage/envelope_store.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import 'package:sealed_trace/src/storage/retention_policy.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';
import 'package:sealed_trace/src/transport/ingest_response.dart';
import 'package:sealed_trace/src/upload/backoff.dart';
import 'package:sealed_trace/src/upload/upload_scheduler.dart';

import 'envelopes.dart';
import 'fake_connectivity.dart';
import 'fake_ingest.dart';
import 'fakes.dart';

const RetentionPolicy schedulerPolicy = RetentionPolicy(
  maxEvents: 10000,
  maxAgeDays: 30,
  maxSizeBytes: 50 * 1024 * 1024,
  deadLetterTtl: Duration(days: 7),
);

IngestAccepted ack(
  Iterable<String> accepted, {
  Iterable<String> duplicate = const [],
  List<IngestRejection> rejected = const [],
}) => IngestAccepted(
  accepted: accepted.toSet(),
  duplicate: duplicate.toSet(),
  rejected: rejected,
);

class SchedulerRig {
  SchedulerRig({
    UploadConfig config = const UploadConfig(),
    Duration backoffBase = const Duration(seconds: 5),
    FakeConnectivity? connectivity,
  }) : config = config,
       connectivity = connectivity ?? FakeConnectivity() {
    store = EnvelopeStore(
      adapter: adapter,
      policy: schedulerPolicy,
      onPurged: (n) => counters.purgedRows += n,
      onDeadLettered: (n) => counters.envelopesDeadLettered += n,
    );
    scheduler = UploadScheduler(
      store: store,
      client: client,
      config: config,
      counters: counters,
      clock: clock,
      backoff: Backoff(base: backoffBase, random: Random(1)),
      connectivity: this.connectivity,
      onResult: results.add,
      onError: (e, _) => errors.add(e),
      purge: ({Set<String> protected = const <String>{}}) async {
        purgeCalls++;
        purgeProtected.add(Set.of(protected));
        return store.purge(clock.now(), protected: protected);
      },
    );
  }

  final UploadConfig config;
  final FakeConnectivity connectivity;
  final adapter = MemoryStorageAdapter();
  final client = ScriptedIngestClient();
  final counters = DiagnosticCounters();
  // Envelopes are dated 2026-01-01, so keep "now" a day later.
  final clock = FakeClock(DateTime.utc(2026, 1, 2));
  final results = <UploadResult>[];
  final errors = <Object>[];
  final purgeProtected = <Set<String>>[];
  int purgeCalls = 0;
  late final EnvelopeStore store;
  late final UploadScheduler scheduler;

  Future<void> add(
    String id, {
    int events = 1,
    int bytes = 64,
    bool notify = false,
  }) async {
    final envelope = makeEnvelope(
      id: id,
      eventCount: events,
      ciphertextLength: bytes,
    );
    await store.append(envelope);
    if (notify) scheduler.noteStored(envelope);
  }

  Future<void> addAll(Iterable<String> ids) async {
    for (final id in ids) {
      await add(id);
    }
  }

  Future<Map<String, EnvelopeIndexRow>> index() async => {
    for (final row in await adapter.listIndex()) row.batchId: row,
  };

  Future<List<String>> ids() async =>
      (await adapter.listIndex()).map((r) => r.batchId).toList();
}

/// Runs [future] to completion inside fake time.
T awaitFake<T>(FakeAsync async, Future<T> future) {
  T? value;
  var done = false;
  Object? failure;
  future.then(
    (v) {
      value = v;
      done = true;
    },
    onError: (Object e) {
      failure = e;
      done = true;
    },
  );
  async.flushMicrotasks();
  if (failure != null) throw failure!;
  expect(done, isTrue, reason: 'the future did not complete');
  return value as T;
}
