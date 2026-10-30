import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';
import 'package:sealed_trace/src/transport/ingest_response.dart';
import 'package:sealed_trace/src/upload/triggers.dart';

import '../helpers/envelopes.dart';
import '../helpers/fake_connectivity.dart';
import '../helpers/scheduler_rig.dart';

void main() {
  group('triggers', () {
    test(
      'a manual flush sends everything and deletes the acknowledged rows',
      () async {
        final rig = SchedulerRig();
        await rig.addAll(['a', 'b', 'c']);

        final result = await rig.scheduler.request(UploadTrigger.manual);

        expect(rig.client.calls, [
          ['a', 'b', 'c'],
        ]);
        expect(result.outcome, UploadOutcome.success);
        expect(result.accepted, 3);
        expect(await rig.ids(), isEmpty);
        expect(rig.results, hasLength(1));
        expect(rig.counters.uploadAttempts, 1);
        expect(rig.counters.uploadFailures, 0);
      },
    );

    test(
      'nothing pending is a quiet skip: no request, no result callback',
      () async {
        final rig = SchedulerRig();
        final result = await rig.scheduler.request(UploadTrigger.manual);
        expect(result.outcome, UploadOutcome.skipped);
        expect(rig.client.calls, isEmpty);
        expect(rig.results, isEmpty);
      },
    );

    test('start() runs a cold-start cycle by itself', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a']);
      await rig.scheduler.start();
      await pumpEventQueue();
      expect(rig.client.calls, [
        ['a'],
      ]);
      await rig.scheduler.dispose();
    });

    test('the interval timer starts a cycle every interval', () {
      fakeAsync((async) {
        final rig = SchedulerRig(
          config: const UploadConfig(interval: Duration(minutes: 10)),
        );
        awaitFake(async, rig.scheduler.start());
        expect(rig.client.calls, isEmpty);

        awaitFake(async, rig.add('a'));
        async.elapse(const Duration(minutes: 9, seconds: 59));
        expect(rig.client.calls, isEmpty, reason: 'not yet');

        async.elapse(const Duration(seconds: 2));
        expect(rig.client.calls, [
          ['a'],
        ]);

        awaitFake(async, rig.add('b'));
        async.elapse(const Duration(minutes: 10));
        expect(rig.client.calls, hasLength(2));
      });
    });

    group('size threshold', () {
      test('200 pending events start a cycle; fewer do not', () async {
        final rig = SchedulerRig();
        await rig.add('a', events: 50, notify: true);
        await rig.add('b', events: 50, notify: true);
        await rig.add('c', events: 50, notify: true);
        await pumpEventQueue();
        expect(rig.client.calls, isEmpty, reason: '150 events');

        await rig.add('d', events: 50, notify: true);
        await pumpEventQueue();
        expect(rig.client.calls, hasLength(1), reason: '200 events');
        expect(rig.client.calls.single, ['a', 'b', 'c', 'd']);
      });

      test('pending bytes start a cycle too', () async {
        final rig = SchedulerRig(
          config: const UploadConfig(sizeThresholdBytes: 2000),
        );
        await rig.add('a', bytes: 500, notify: true);
        await rig.add('b', bytes: 500, notify: true);
        await pumpEventQueue();
        expect(rig.client.calls, isEmpty);

        await rig.add('c', bytes: 900, notify: true);
        await pumpEventQueue();
        expect(rig.client.calls, hasLength(1));
      });

      test('a threshold of zero disables that trigger', () async {
        final rig = SchedulerRig(
          config: const UploadConfig(
            sizeThresholdEvents: 0,
            sizeThresholdBytes: 0,
          ),
        );
        await rig.add('a', events: 5000, bytes: 900000, notify: true);
        await pumpEventQueue();
        expect(rig.client.calls, isEmpty);
      });

      test('counters are seeded from storage at start', () async {
        final rig = SchedulerRig();
        await rig.add('old', events: 190);
        await rig.scheduler.start();
        await pumpEventQueue();
        // The cold start already sent it; refill and cross the threshold.
        rig.client.calls.clear();
        await rig.add('x', events: 150, notify: true);
        await pumpEventQueue();
        expect(rig.client.calls, isEmpty);
        await rig.add('y', events: 60, notify: true);
        await pumpEventQueue();
        expect(rig.client.calls, hasLength(1));
        await rig.scheduler.dispose();
      });
    });

    group('connectivity', () {
      test('coming back online starts a cycle', () async {
        final connectivity = FakeConnectivity(online: false);
        final rig = SchedulerRig(connectivity: connectivity);
        await rig.addAll(['a']);
        await rig.scheduler.start();
        await pumpEventQueue();
        expect(rig.client.calls, isEmpty, reason: 'offline');

        connectivity.setOnline(true);
        await pumpEventQueue();
        expect(rig.client.calls, [
          ['a'],
        ]);
        await rig.scheduler.dispose();
      });

      test('going offline starts nothing', () async {
        final connectivity = FakeConnectivity(online: true);
        final rig = SchedulerRig(connectivity: connectivity);
        await rig.scheduler.start();
        await pumpEventQueue();
        await rig.addAll(['a']);
        connectivity.setOnline(false);
        await pumpEventQueue();
        expect(rig.client.calls, isEmpty);
        await rig.scheduler.dispose();
      });

      test('uploadOnConnectivityRestored: false ignores the event', () async {
        final connectivity = FakeConnectivity(online: false);
        final rig = SchedulerRig(
          config: const UploadConfig(uploadOnConnectivityRestored: false),
          connectivity: connectivity,
        );
        await rig.addAll(['a']);
        await rig.scheduler.start();
        connectivity.setOnline(true);
        await pumpEventQueue();
        expect(rig.client.calls, isEmpty);
        await rig.scheduler.dispose();
      });

      test(
        'a cycle is skipped while offline, even for a manual flush',
        () async {
          final rig = SchedulerRig(
            connectivity: FakeConnectivity(online: false),
          );
          await rig.addAll(['a']);
          final result = await rig.scheduler.request(UploadTrigger.manual);
          expect(result.outcome, UploadOutcome.skipped);
          expect(rig.client.calls, isEmpty);
          expect(
            (await rig.index())['a']!.attempts,
            0,
            reason: 'offline must not burn attempts',
          );
        },
      );

      test('unknown connectivity does not block uploads', () async {
        final rig = SchedulerRig(connectivity: FakeConnectivity(online: null));
        await rig.addAll(['a']);
        await rig.scheduler.request(UploadTrigger.manual);
        expect(rig.client.calls, hasLength(1));
      });
    });

    test('a resume request runs a cycle', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a']);
      await rig.scheduler.request(UploadTrigger.resume);
      expect(rig.client.calls, hasLength(1));
    });
  });

  group('one cycle at a time', () {
    test(
      'overlapping triggers coalesce into a single follow-up cycle',
      () async {
        final rig = SchedulerRig();
        await rig.addAll(['a']);
        final gate = Completer<IngestOutcome>();
        rig.client.enqueue((batch) => gate.future);

        final first = rig.scheduler.request(UploadTrigger.manual);
        await pumpEventQueue();
        expect(rig.client.calls, hasLength(1));

        await rig.add('b');
        final second = rig.scheduler.request(UploadTrigger.manual);
        final third = rig.scheduler.request(UploadTrigger.manual);
        final fourth = rig.scheduler.request(UploadTrigger.connectivity);
        expect(identical(second, third), isTrue);
        expect(identical(third, fourth), isTrue);

        gate.complete(ack(['a']));
        await Future.wait([first, second]);

        expect(rig.client.calls, [
          ['a'],
          ['b'],
        ], reason: 'exactly one follow-up cycle');
        expect(rig.client.maxRunning, 1, reason: 'never two at once');
        expect(await rig.ids(), isEmpty);
      },
    );

    test(
      'a manual flush waits for the running cycle, then runs its own',
      () async {
        final rig = SchedulerRig();
        await rig.addAll(['a']);
        final gate = Completer<IngestOutcome>();
        rig.client.enqueue((batch) => gate.future);

        final running = rig.scheduler.request(UploadTrigger.interval);
        await pumpEventQueue();
        await rig.add('b');
        final flush = rig.scheduler.request(UploadTrigger.manual);

        var flushDone = false;
        unawaited(flush.then((_) => flushDone = true));
        await pumpEventQueue();
        expect(flushDone, isFalse, reason: 'must wait for the running cycle');

        gate.complete(ack(['a']));
        await flush;
        await running;
        // The running cycle's loop already picked up the row stored meanwhile,
        // so the follow-up cycle found nothing left to send.
        expect(rig.client.calls, [
          ['a'],
          ['b'],
        ]);
        expect(await rig.ids(), isEmpty);
        expect(flushDone, isTrue);
      },
    );

    test('a request after dispose does nothing', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a']);
      await rig.scheduler.dispose();
      final result = await rig.scheduler.request(UploadTrigger.manual);
      expect(result.outcome, UploadOutcome.skipped);
      expect(rig.client.calls, isEmpty);
    });
  });

  group('responses (C9-C11)', () {
    test('rows are deleted only for accepted or duplicate ids', () async {
      final rig = SchedulerRig();
      await rig.addAll(['r1', 'r2', 'r3', 'r4', 'r5']);
      rig.client.enqueueOutcome(
        ack(
          ['r1', 'not-ours'],
          duplicate: ['r2'],
          rejected: const [
            IngestRejection('r3', 'schema_invalid'),
            IngestRejection('r4', 'temporarily_unavailable'),
          ],
        ),
      );

      final result = await rig.scheduler.request(UploadTrigger.manual);
      final index = await rig.index();

      expect(index.keys, unorderedEquals(['r3', 'r4', 'r5']));
      expect(
        index['r3']!.uploadState,
        uploadStateDeadLetter,
        reason: 'permanent rejection',
      );
      expect(index['r3']!.attempts, 1);
      expect(
        index['r4']!.uploadState,
        uploadStatePending,
        reason: 'transient rejection',
      );
      expect(index['r4']!.attempts, 1);
      expect(
        index['r5']!.uploadState,
        uploadStatePending,
        reason: 'an id missing from every list is not acknowledged',
      );
      expect(index['r5']!.attempts, 1);

      expect(result.outcome, UploadOutcome.partial);
      expect(result.accepted, 1);
      expect(result.duplicate, 1);
      expect(result.rejected, 2);
      expect(result.failed, 1);
      expect(rig.counters.envelopesDeadLettered, 1);
    });

    test('an id the server returns that we never sent is ignored', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a']);
      rig.client.enqueueOutcome(ack(['ghost'], duplicate: ['phantom']));
      final result = await rig.scheduler.request(UploadTrigger.manual);
      expect((await rig.index()).keys, ['a']);
      expect(result.accepted, 0);
      expect(result.duplicate, 0);
    });

    test('an empty 202 acknowledges nothing', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a', 'b']);
      rig.client.enqueueOutcome(ack([]));
      final result = await rig.scheduler.request(UploadTrigger.manual);
      expect((await rig.ids()), ['a', 'b']);
      expect(result.outcome, UploadOutcome.failed);
      expect(result.failed, 2);
    });

    test('an id that is both accepted and duplicate counts once', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a']);
      rig.client.enqueueOutcome(ack(['a'], duplicate: ['a']));
      final result = await rig.scheduler.request(UploadTrigger.manual);
      expect(result.accepted, 1);
      expect(result.duplicate, 0);
      expect(await rig.ids(), isEmpty);
    });

    test(
      'a server that answers "duplicate" lets the row go (idempotent)',
      () async {
        final rig = SchedulerRig();
        await rig.addAll(['a']);
        rig.client.enqueueOutcome(ack([], duplicate: ['a']));
        final result = await rig.scheduler.request(UploadTrigger.manual);
        expect(result.outcome, UploadOutcome.success);
        expect(await rig.ids(), isEmpty);
      },
    );

    test('more than 50 rows go out in several requests', () async {
      final rig = SchedulerRig();
      await rig.addAll([
        for (var i = 0; i < 120; i++) 'id-${i.toString().padLeft(3, '0')}',
      ]);
      final result = await rig.scheduler.request(UploadTrigger.manual);
      expect(rig.client.calls.map((c) => c.length), [50, 50, 20]);
      expect(result.accepted, 120);
      expect(await rig.ids(), isEmpty);
    });

    test('batchSize limits the request size', () async {
      final rig = SchedulerRig(config: const UploadConfig(batchSize: 10));
      await rig.addAll([
        for (var i = 0; i < 25; i++) 'id-${i.toString().padLeft(3, '0')}',
      ]);
      await rig.scheduler.request(UploadTrigger.manual);
      expect(rig.client.calls.map((c) => c.length), [10, 10, 5]);
    });

    test('rows go oldest first', () async {
      final rig = SchedulerRig();
      await rig.store.append(
        makeEnvelope(id: 'newer', createdAt: DateTime.utc(2026, 1, 1, 12)),
      );
      await rig.store.append(
        makeEnvelope(id: 'older', createdAt: DateTime.utc(2026, 1, 1, 8)),
      );
      await rig.scheduler.request(UploadTrigger.manual);
      expect(rig.client.calls.single, ['older', 'newer']);
    });
  });

  group('crash safety and purge', () {
    test('rows marked uploaded but not deleted are removed at start', () async {
      final rig = SchedulerRig();
      await rig.addAll(['half-done', 'pending']);
      // Simulate the crash between the mark and the delete.
      await rig.adapter.patch(['half-done'], uploadedAt: 1);

      await rig.scheduler.start();
      await pumpEventQueue();

      expect(rig.client.calls, [
        ['pending'],
      ], reason: 'the marked row must not be sent again');
      expect(await rig.ids(), isEmpty);
      await rig.scheduler.dispose();
    });

    test('retention runs after a cycle that sent something', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a']);
      await rig.scheduler.request(UploadTrigger.manual);
      expect(rig.purgeCalls, 1);
      expect(
        rig.purgeProtected.single,
        isEmpty,
        reason: 'nothing is in flight once the cycle is over',
      );
    });

    test(
      'rows being uploaded are exposed so retention can protect them',
      () async {
        final rig = SchedulerRig();
        await rig.addAll(['a', 'b']);
        final gate = Completer<IngestOutcome>();
        Set<String>? seen;
        rig.client.enqueue((batch) {
          seen = Set.of(rig.scheduler.inFlightIds);
          return gate.future;
        });
        final cycle = rig.scheduler.request(UploadTrigger.manual);
        await pumpEventQueue();
        expect(seen, {'a', 'b'});
        expect(rig.scheduler.inFlightIds, {'a', 'b'});
        gate.complete(ack(['a', 'b']));
        await cycle;
        expect(rig.scheduler.inFlightIds, isEmpty);
      },
    );
  });

  group('results and counters', () {
    test('onResult fires only for cycles that attempted something', () async {
      final rig = SchedulerRig();
      await rig.scheduler.request(UploadTrigger.manual);
      expect(rig.results, isEmpty);

      await rig.addAll(['a']);
      await rig.scheduler.request(UploadTrigger.manual);
      expect(rig.results, hasLength(1));
      expect(rig.results.single.outcome, UploadOutcome.success);
    });

    test('a failing cycle reports a failed result', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a']);
      rig.client.enqueueOutcome(const IngestServerError(500, 'down'));
      final result = await rig.scheduler.request(UploadTrigger.manual);
      expect(result.outcome, UploadOutcome.failed);
      expect(result.failed, 1);
      expect(rig.results.single.outcome, UploadOutcome.failed);
      expect(rig.counters.uploadAttempts, 1);
      expect(rig.counters.uploadFailures, 1);
    });

    test('the result timestamp comes from the clock', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a']);
      final result = await rig.scheduler.request(UploadTrigger.manual);
      expect(result.at, DateTime.utc(2026, 1, 2));
    });
  });
}
