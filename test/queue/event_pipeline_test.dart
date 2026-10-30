import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/diagnostics/diagnostic_counters.dart';
import 'package:sealed_trace/src/event/event_builder.dart';
import 'package:sealed_trace/src/event/event_pipeline.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/event/page_exit_saver.dart';
import 'package:sealed_trace/src/event/sequence_counter.dart';
import 'package:sealed_trace/src/masking/masking_engine.dart';
import 'package:sealed_trace/src/platform/lifecycle_binding.dart';
import 'package:sealed_trace/src/queue/write_behind_queue.dart';
import 'package:sealed_trace/src/storage/envelope_spill.dart';

import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

class _Rig {
  _Rig({
    SealedTraceEnv env = SealedTraceEnv.prod,
    LogRecord Function(LogRecord)? mask,
  }) {
    builder = EventBuilder(
      sequence: SequenceCounter(InMemorySequenceStore(), highWater: 0),
      sessionId: 's',
      device: testDevice,
      env: env,
    );
    queue = WriteBehindQueue(sink: sink.call, onError: (_, _) {});
    pipeline = EventPipeline(
      builder: builder,
      queue: queue,
      lifecycle: lifecycle,
      env: env,
      counters: counters,
      masking: MaskingEngine(const MaskConfig()),
      mask: mask,
    );
  }

  final sink = RecordingSink();
  final lifecycle = FakeLifecycle();
  final counters = DiagnosticCounters();
  late final EventBuilder builder;
  late final WriteBehindQueue queue;
  late final EventPipeline pipeline;

  void log(LogLevel level) =>
      pipeline.enqueue(builder.build(level: level, tag: 't', message: 'm'));
}

void main() {
  test('info waits for the timer; fatal flushes immediately', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.log(LogLevel.info);
      async.flushMicrotasks();
      expect(rig.sink.batches, isEmpty);

      rig.log(LogLevel.fatal);
      async.flushMicrotasks();
      expect(rig.sink.records.map((r) => r.level), [
        LogLevel.info,
        LogLevel.fatal,
      ]);
    });
  });

  test('error flushes immediately outside prod but not in prod', () {
    fakeAsync((async) {
      final prod = _Rig();
      prod.log(LogLevel.error);
      async.flushMicrotasks();
      expect(prod.sink.batches, isEmpty);

      final dev = _Rig(env: SealedTraceEnv.dev);
      dev.log(LogLevel.error);
      async.flushMicrotasks();
      expect(dev.sink.batches, hasLength(1));
    });
  });

  test('paused, inactive, hidden and detached flush the queue', () {
    for (final state in [
      AppLifecycle.paused,
      AppLifecycle.inactive,
      AppLifecycle.hidden,
      AppLifecycle.detached,
    ]) {
      fakeAsync((async) {
        final rig = _Rig();
        rig.log(LogLevel.info);
        rig.lifecycle.emit(state);
        async.flushMicrotasks();
        expect(rig.sink.batches, hasLength(1), reason: state.name);
      });
    }
  });

  test('with a page-exit saver, hidden and detached save synchronously', () {
    for (final state in [AppLifecycle.hidden, AppLifecycle.detached]) {
      final rig = _Rig();
      final spill = MemoryEnvelopeSpill();
      rig.pipeline.pageExitSaver = PageExitSaver(
        queue: rig.queue,
        sealer: EnvelopeSealer(
          publicKey: PublicKeyParser.parse(testPublicKeySpki),
          projectId: 'p',
        ),
        spill: spill,
        store: (_) async {},
        counters: rig.counters,
        onError: (_, _) {},
      );
      rig.log(LogLevel.info);
      rig.lifecycle.emit(state);
      // No microtask has run: the save happened inside the event.
      expect(spill.readAll(), hasLength(1), reason: state.name);
      expect(rig.queue.length, 0, reason: state.name);
      expect(rig.sink.batches, isEmpty, reason: state.name);
    }
  });

  test('with a page-exit saver, paused and inactive still flush', () {
    for (final state in [AppLifecycle.paused, AppLifecycle.inactive]) {
      fakeAsync((async) {
        final rig = _Rig();
        final spill = MemoryEnvelopeSpill();
        rig.pipeline.pageExitSaver = PageExitSaver(
          queue: rig.queue,
          sealer: EnvelopeSealer(
            publicKey: PublicKeyParser.parse(testPublicKeySpki),
            projectId: 'p',
          ),
          spill: spill,
          store: (_) async {},
          counters: rig.counters,
          onError: (_, _) {},
        );
        rig.log(LogLevel.info);
        rig.lifecycle.emit(state);
        async.flushMicrotasks();
        expect(rig.sink.batches, hasLength(1), reason: state.name);
        expect(spill.readAll(), isEmpty, reason: state.name);
      });
    }
  });

  test('resumed does not flush', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.log(LogLevel.info);
      rig.lifecycle.emit(AppLifecycle.resumed);
      async.flushMicrotasks();
      expect(rig.sink.batches, isEmpty);
    });
  });

  test('the mask step runs before the record is queued', () {
    fakeAsync((async) {
      final rig = _Rig(mask: (r) => r.copyWith(message: 'masked'));
      rig.log(LogLevel.fatal);
      async.flushMicrotasks();
      expect(rig.sink.records.single.message, 'masked');
    });
  });

  test('enqueue counts accepted events', () {
    fakeAsync((async) {
      final rig = _Rig();
      rig.log(LogLevel.info);
      rig.log(LogLevel.info);
      expect(rig.counters.eventsAccepted, 2);
    });
  });

  // Real async: StreamSubscription.cancel() completes in the root zone, which
  // fakeAsync cannot flush.
  test('dispose stops listening, drains and disposes the binding', () async {
    final rig = _Rig();
    rig.log(LogLevel.info);
    await rig.pipeline.dispose();
    expect(rig.sink.records, hasLength(1));
    expect(rig.lifecycle.disposed, isTrue);
    expect(rig.queue.hasPendingTimer, isFalse);
  });
}
