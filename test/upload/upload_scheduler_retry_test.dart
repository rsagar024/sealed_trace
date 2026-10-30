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

const IngestOutcome _serverDown = IngestServerError(503, 'down');

void main() {
  group('failures add attempts and retry with backoff (A15, A16)', () {
    test(
      'a server error adds an attempt and retries after a backoff delay',
      () {
        fakeAsync((async) {
          final rig = SchedulerRig();
          awaitFake(async, rig.add('a'));
          rig.client.enqueueOutcome(_serverDown);

          final first = awaitFake(
            async,
            rig.scheduler.request(UploadTrigger.manual),
          );
          expect(first.outcome, UploadOutcome.failed);
          expect(awaitFake(async, rig.index())['a']!.attempts, 1);
          expect(rig.client.calls, hasLength(1));

          async.elapse(
            const Duration(seconds: 6),
          ); // first delay is at most 5 s
          expect(rig.client.calls, hasLength(2), reason: 'retried');
          expect(awaitFake(async, rig.ids()), isEmpty, reason: 'then accepted');
        });
      },
    );

    for (final entry in <String, IngestOutcome>{
      'network error': const IngestNetworkError('connectionError'),
      'timeout': const IngestTimeout(),
      'other status': const IngestServerError(400, 'bad'),
    }.entries) {
      test('${entry.key} counts as a failed attempt', () {
        fakeAsync((async) {
          final rig = SchedulerRig();
          awaitFake(async, rig.add('a'));
          rig.client.enqueueOutcome(entry.value);
          awaitFake(async, rig.scheduler.request(UploadTrigger.manual));
          expect(awaitFake(async, rig.index())['a']!.attempts, 1);
          expect(rig.counters.uploadFailures, 1);
        });
      });
    }

    test('delays between retries grow: 5, 10, 20, 40 seconds with jitter', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('a'));
        final times = <Duration>[];
        for (var i = 0; i < 4; i++) {
          rig.client.enqueue((_) {
            times.add(async.elapsed);
            return _serverDown;
          });
        }
        unawaited(rig.scheduler.request(UploadTrigger.manual));
        async.elapse(const Duration(minutes: 5));

        expect(rig.client.calls, hasLength(5), reason: '4 failures + success');
        final gaps = <int>[];
        for (var i = 1; i < times.length; i++) {
          gaps.add((times[i] - times[i - 1]).inMilliseconds);
        }
        final caps = [5000, 10000, 20000];
        for (var i = 0; i < gaps.length; i++) {
          expect(
            gaps[i],
            inInclusiveRange(caps[i] ~/ 2, caps[i]),
            reason: 'gap ${i + 1}',
          );
        }
        expect(awaitFake(async, rig.ids()), isEmpty);
      });
    });

    test('the batchId is the same on every retry (C16)', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('stable-id'));
        rig.client.enqueueOutcome(_serverDown);
        rig.client.enqueueOutcome(_serverDown);
        unawaited(rig.scheduler.request(UploadTrigger.manual));
        async.elapse(const Duration(minutes: 2));
        expect(rig.client.calls, [
          ['stable-id'],
          ['stable-id'],
          ['stable-id'],
        ]);
        expect(awaitFake(async, rig.ids()), isEmpty);
      });
    });

    test('a row never exceeds 5 attempts, then it is dead-lettered', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('doomed'));
        rig.client.fallback = (_) => _serverDown;

        unawaited(rig.scheduler.request(UploadTrigger.manual));
        async.elapse(const Duration(hours: 2));

        expect(
          rig.client.calls,
          hasLength(5),
          reason: 'five requests, no more',
        );
        final row = awaitFake(async, rig.index())['doomed']!;
        expect(row.attempts, 5);
        expect(row.uploadState, uploadStateDeadLetter);
        expect(rig.counters.envelopesDeadLettered, 1);

        async.elapse(const Duration(hours: 5));
        expect(
          rig.client.calls,
          hasLength(5),
          reason: 'a dead letter is not retried in normal cycles',
        );
      });
    });

    test('a cancelled request counts no attempt and schedules no retry', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('a'));
        rig.client.enqueueOutcome(const IngestCancelled());
        awaitFake(async, rig.scheduler.request(UploadTrigger.manual));
        expect(awaitFake(async, rig.index())['a']!.attempts, 0);
        async.elapse(const Duration(minutes: 30));
        expect(rig.client.calls, hasLength(1));
      });
    });

    test('while a retry is pending, interval, threshold and resume wait', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('a', events: 500));
        rig.client.enqueueOutcome(_serverDown);
        awaitFake(async, rig.scheduler.request(UploadTrigger.manual));
        expect(rig.client.calls, hasLength(1));

        for (final trigger in [
          UploadTrigger.interval,
          UploadTrigger.threshold,
          UploadTrigger.resume,
        ]) {
          final result = awaitFake(async, rig.scheduler.request(trigger));
          expect(result.outcome, UploadOutcome.skipped, reason: '$trigger');
        }
        rig.scheduler.noteStored(makeEnvelope(id: 'x', eventCount: 500));
        async.flushMicrotasks();
        expect(rig.client.calls, hasLength(1), reason: 'backoff is respected');
      });
    });

    test('a manual flush and a connectivity change may skip the wait', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('a'));
        rig.client.enqueueOutcome(_serverDown);
        awaitFake(async, rig.scheduler.request(UploadTrigger.manual));
        expect(rig.client.calls, hasLength(1));

        awaitFake(async, rig.scheduler.request(UploadTrigger.manual));
        expect(rig.client.calls, hasLength(2));
        expect(awaitFake(async, rig.ids()), isEmpty);
        async.elapse(const Duration(minutes: 10));
        expect(
          rig.client.calls,
          hasLength(2),
          reason: 'the cancelled retry must not fire',
        );
      });
    });

    test('a rejection the server calls transient is retried later', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('a'));
        rig.client.enqueueOutcome(
          ack(const [], rejected: const [IngestRejection('a', 'busy')]),
        );
        awaitFake(async, rig.scheduler.request(UploadTrigger.manual));
        expect(rig.client.calls, hasLength(1));
        async.elapse(const Duration(seconds: 6));
        expect(rig.client.calls, hasLength(2));
        expect(awaitFake(async, rig.ids()), isEmpty);
      });
    });
  });

  group('401 and 403 (C12, C13, A13)', () {
    for (final status in [401, 403]) {
      test('$status pauses uploads without burning attempts', () async {
        final rig = SchedulerRig();
        await rig.addAll(['a']);
        rig.client.enqueueOutcome(IngestUnauthorized(status));

        final result = await rig.scheduler.request(UploadTrigger.manual);

        expect(result.outcome, UploadOutcome.unauthorized);
        expect((await rig.index())['a']!.attempts, 0);
        expect(rig.scheduler.isPaused, isTrue);
        expect(rig.errors, hasLength(1));
        expect(rig.errors.single, isA<StateError>());
        expect(rig.errors.single.toString(), contains('HTTP $status'));
      });
    }

    test('later triggers send nothing and do not report again', () async {
      final rig = SchedulerRig();
      await rig.addAll(['a']);
      rig.client.enqueueOutcome(const IngestUnauthorized(401));
      await rig.scheduler.request(UploadTrigger.manual);

      await rig.addAll(['b']);
      final again = await rig.scheduler.request(UploadTrigger.manual);
      await rig.scheduler.request(UploadTrigger.interval);
      await rig.scheduler.request(UploadTrigger.coldStart);

      expect(again.outcome, UploadOutcome.unauthorized);
      expect(rig.client.calls, hasLength(1), reason: 'no further requests');
      expect(rig.errors, hasLength(1), reason: 'reported once per session');
      expect(
        (await rig.index()).keys,
        unorderedEquals(['a', 'b']),
        reason: 'the data stays on disk',
      );
    });

    test('a retry is not scheduled once paused', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('a'));
        rig.client.enqueueOutcome(const IngestUnauthorized(403));
        awaitFake(async, rig.scheduler.request(UploadTrigger.manual));
        async.elapse(const Duration(hours: 1));
        expect(rig.client.calls, hasLength(1));
      });
    });
  });

  group('413 (C14, A12)', () {
    test(
      'the request is halved until it fits, with no attempts burned',
      () async {
        final rig = SchedulerRig();
        await rig.addAll([for (var i = 1; i <= 8; i++) 'id-$i']);
        rig.client
          ..enqueueOutcome(const IngestTooLarge())
          ..enqueueOutcome(const IngestTooLarge());

        final result = await rig.scheduler.request(UploadTrigger.manual);

        expect(rig.client.calls.map((c) => c.length), [8, 4, 2, 2, 2, 2]);
        expect(result.outcome, UploadOutcome.success);
        expect(result.accepted, 8);
        expect(await rig.ids(), isEmpty);
      },
    );

    test(
      'a single envelope that is still too large is dead-lettered',
      () async {
        final rig = SchedulerRig();
        await rig.addAll(['lonely']);
        rig.client.enqueueOutcome(const IngestTooLarge());

        final result = await rig.scheduler.request(UploadTrigger.manual);
        final row = (await rig.index())['lonely']!;

        expect(row.uploadState, uploadStateDeadLetter);
        expect(row.attempts, 1);
        expect(result.rejected, 1);
        expect(rig.counters.envelopesDeadLettered, 1);
      },
    );

    test(
      'an envelope too big for any request is dead-lettered unsent',
      () async {
        final rig = SchedulerRig();
        await rig.add('ok-1');
        await rig.add('huge', bytes: 1600000);
        await rig.add('ok-2');

        final result = await rig.scheduler.request(UploadTrigger.manual);

        expect(rig.client.calls, [
          ['ok-1', 'ok-2'],
        ], reason: 'the huge one is never sent');
        final index = await rig.index();
        expect(index.keys, ['huge']);
        expect(index['huge']!.uploadState, uploadStateDeadLetter);
        expect(result.outcome, UploadOutcome.partial);
        expect(result.accepted, 2);
        expect(result.rejected, 1);
      },
    );
  });

  group('429 (C15, A14)', () {
    test('waits for Retry-After and burns no attempt', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('a'));
        rig.client.enqueueOutcome(
          const IngestRateLimited(Duration(seconds: 30)),
        );

        final result = awaitFake(
          async,
          rig.scheduler.request(UploadTrigger.manual),
        );
        expect(result.outcome, UploadOutcome.failed);
        expect(awaitFake(async, rig.index())['a']!.attempts, 0);

        async.elapse(const Duration(seconds: 29));
        expect(rig.client.calls, hasLength(1), reason: 'still waiting');
        async.elapse(const Duration(seconds: 2));
        expect(rig.client.calls, hasLength(2));
        expect(awaitFake(async, rig.ids()), isEmpty);
      });
    });

    test('without Retry-After it uses the backoff delay', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('a'));
        rig.client.enqueueOutcome(const IngestRateLimited(null));
        awaitFake(async, rig.scheduler.request(UploadTrigger.manual));
        expect(awaitFake(async, rig.index())['a']!.attempts, 0);

        async.elapse(const Duration(seconds: 6));
        expect(rig.client.calls, hasLength(2));
      });
    });

    test('repeated 429s back off further each time', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, rig.add('a'));
        final times = <Duration>[];
        for (var i = 0; i < 3; i++) {
          rig.client.enqueue((_) {
            times.add(async.elapsed);
            return const IngestRateLimited(null);
          });
        }
        unawaited(rig.scheduler.request(UploadTrigger.manual));
        async.elapse(const Duration(minutes: 3));
        expect(times, hasLength(3));
        final first = (times[1] - times[0]).inMilliseconds;
        final second = (times[2] - times[1]).inMilliseconds;
        expect(first, inInclusiveRange(2500, 5000));
        expect(second, inInclusiveRange(5000, 10000));
      });
    });
  });

  group('dead letters (A15, P6.4)', () {
    Future<void> deadLetter(SchedulerRig rig, String id) async {
      await rig.add(id);
      await rig.adapter.patch(
        [id],
        attemptsDelta: 5,
        uploadState: uploadStateDeadLetter,
      );
    }

    test('are retried once at cold start; success deletes them', () async {
      final rig = SchedulerRig();
      await deadLetter(rig, 'd1');
      await deadLetter(rig, 'd2');
      await rig.add('p1');

      await rig.scheduler.request(UploadTrigger.coldStart);

      expect(rig.client.calls, [
        ['d1', 'd2'],
        ['p1'],
      ], reason: 'dead letters first, then normal rows');
      expect(await rig.ids(), isEmpty);
    });

    test('are not retried again in the same run', () async {
      final rig = SchedulerRig();
      await rig.scheduler.request(UploadTrigger.coldStart);
      await deadLetter(rig, 'late-dead');
      await rig.scheduler.request(UploadTrigger.coldStart);
      await rig.scheduler.request(UploadTrigger.manual);
      expect(rig.client.calls, isEmpty);
      expect((await rig.index()).keys, ['late-dead']);
    });

    test('are not sent by ordinary cycles', () async {
      final rig = SchedulerRig();
      await deadLetter(rig, 'dead');
      await rig.add('live');
      await rig.scheduler.request(UploadTrigger.manual);
      expect(rig.client.calls, [
        ['live'],
      ]);
    });

    test('a failed retry leaves them flagged and costs no attempt', () async {
      final rig = SchedulerRig();
      await deadLetter(rig, 'd1');
      await rig.add('p1');
      rig.client.enqueueOutcome(_serverDown); // for the dead-letter request

      await rig.scheduler.request(UploadTrigger.coldStart);

      final index = await rig.index();
      expect(index['d1']!.uploadState, uploadStateDeadLetter);
      expect(index['d1']!.attempts, 5, reason: 'no further attempt counted');
      expect(rig.client.calls, [
        ['d1'],
        ['p1'],
      ]);
    });

    test('a permanent rejection of a dead letter changes nothing', () async {
      final rig = SchedulerRig();
      await deadLetter(rig, 'd1');
      rig.client.enqueueOutcome(
        ack(
          const [],
          rejected: const [IngestRejection('d1', 'schema_invalid')],
        ),
      );
      await rig.scheduler.request(UploadTrigger.coldStart);
      final row = (await rig.index())['d1']!;
      expect(row.attempts, 5);
      expect(row.uploadState, uploadStateDeadLetter);
    });

    test('401 while retrying dead letters pauses and sends no more', () async {
      final rig = SchedulerRig();
      await deadLetter(rig, 'd1');
      await rig.add('p1');
      rig.client.enqueueOutcome(const IngestUnauthorized(401));
      final result = await rig.scheduler.request(UploadTrigger.coldStart);
      expect(result.outcome, UploadOutcome.unauthorized);
      expect(rig.client.calls, hasLength(1));
      expect(rig.scheduler.isPaused, isTrue);
    });

    test('a 429 while retrying dead letters waits instead of sending more', () {
      fakeAsync((async) {
        final rig = SchedulerRig();
        awaitFake(async, deadLetter(rig, 'd1'));
        awaitFake(async, rig.add('p1'));
        rig.client.enqueueOutcome(
          const IngestRateLimited(Duration(seconds: 20)),
        );
        awaitFake(async, rig.scheduler.request(UploadTrigger.coldStart));
        expect(rig.client.calls, hasLength(1));
        async.elapse(const Duration(seconds: 21));
        expect(rig.client.calls.last, ['p1']);
      });
    });

    test('expire through retention after 7 days', () async {
      final rig = SchedulerRig();
      await deadLetter(rig, 'old-dead');
      await rig.adapter.patch(
        ['old-dead'],
        lastAttemptAt: rig.clock
            .now()
            .subtract(const Duration(days: 8))
            .millisecondsSinceEpoch,
      );
      await rig.store.purge(rig.clock.now());
      expect(await rig.ids(), isEmpty);
    });
  });

  group('dispose', () {
    test('cancels a pending retry', () async {
      final rig = SchedulerRig(backoffBase: const Duration(milliseconds: 20));
      await rig.add('a');
      rig.client.enqueueOutcome(_serverDown);
      await rig.scheduler.request(UploadTrigger.manual);
      await rig.scheduler.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(rig.client.calls, hasLength(1));
    });

    test('cancels a request in progress and then completes', () async {
      final rig = SchedulerRig();
      await rig.add('a');
      final gate = Completer<IngestOutcome>();
      rig.client.enqueue((_) => gate.future);
      final cycle = rig.scheduler.request(UploadTrigger.manual);
      await pumpEventQueue();

      final disposed = rig.scheduler.dispose();
      expect(rig.client.cancelCalls, 1);
      gate.complete(const IngestCancelled());
      await disposed;
      await cycle;

      expect(
        (await rig.index())['a']!.attempts,
        0,
        reason: 'a cancelled request is not an attempt',
      );
      expect(rig.results, isEmpty, reason: 'no callback after dispose');
    });

    test('stops the interval timer', () async {
      final rig = SchedulerRig(
        config: const UploadConfig(interval: Duration(milliseconds: 30)),
      );
      await rig.scheduler.start();
      await rig.scheduler.dispose();
      await rig.add('a');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(rig.client.calls, isEmpty);
    });

    test('stops listening to connectivity', () async {
      final connectivity = FakeConnectivity(online: false);
      final rig = SchedulerRig(connectivity: connectivity);
      await rig.add('a');
      await rig.scheduler.start();
      await rig.scheduler.dispose();
      connectivity.setOnline(true);
      await pumpEventQueue();
      expect(rig.client.calls, isEmpty);
    });
  });
}
