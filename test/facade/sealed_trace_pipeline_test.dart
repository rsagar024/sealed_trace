import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/platform/lifecycle_binding.dart';

import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _pem = testPublicKeySpki;

const _config = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj',
  apiKey: 'key',
  publicKeyPem: _pem,
  appName: 'app',
);

late RecordingSink sink;
late FakeLifecycle lifecycle;

Future<void> _init([SealedTraceConfig config = _config]) async {
  var n = 0;
  SealedTrace.debugOverrides = RuntimeOverrides(
    disableUploads: true,
    storage: MemoryStorageAdapter(),
    clock: FakeClock(DateTime.utc(2026, 1, 1, 10)),
    lifecycle: lifecycle,
    sink: sink.call,
    deviceContext: testDevice,
    newId: () => 'id-${n++}',
  );
  await SealedTrace.init(config);
}

void main() {
  setUp(() async {
    await SealedTrace.dispose();
    SealedTrace.onException = null;
    sink = RecordingSink();
    lifecycle = FakeLifecycle();
  });

  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.debugOverrides = null;
    SealedTrace.onException = null;
  });

  test('a logged event reaches the sink fully stamped', () async {
    await _init();
    SealedTrace.setUser('u-1', name: 'Asha');
    SealedTrace.setContext({'feature': 'beta'});
    SealedTrace.w('auth', 'slow login', meta: {'ms': 1200});
    await SealedTrace.flush();

    final json = sink.records.single.toJson();
    expect(json['level'], 'warning');
    expect(json['tag'], 'auth');
    expect(json['message'], 'slow login');
    expect(json['metadata'], {'ms': 1200});
    expect(json['userId'], 'u-1');
    expect(json['sessionId'], 'id-0');
    expect(json['seq'], 1);
    expect(json['ts'], '2026-01-01T10:00:00.000Z');
    final ctx = json['ctx'] as Map<String, dynamic>;
    expect(ctx['feature'], 'beta');
    expect(ctx['userName'], 'Asha'); // readable unless maskUserName
    expect(ctx['platform'], 'android');
  });

  test('all six levels and log(LogEvent) arrive in order', () async {
    await _init();
    SealedTrace.v('t', '1');
    SealedTrace.d('t', '2');
    SealedTrace.i('t', '3');
    SealedTrace.w('t', '4');
    SealedTrace.e('t', '5', error: 'boom', stack: StackTrace.current);
    SealedTrace.f('t', '6');
    SealedTrace.log(
      LogEvent(
        level: LogLevel.info,
        tag: 't',
        message: '7',
        timestamp: DateTime.utc(2025, 5, 5),
      ),
    );
    await SealedTrace.flush();

    final records = sink.records;
    expect(records.map((r) => r.message), ['1', '2', '3', '4', '5', '6', '7']);
    expect(records.map((r) => r.seq), [1, 2, 3, 4, 5, 6, 7]);
    expect(records[4].error, 'boom');
    expect(records[4].stackTrace, isNotNull);
    expect(records.last.toJson()['ts'], '2025-05-05T00:00:00.000Z');
    expect(SealedTrace.diagnostics.eventsAccepted, 7);
  });

  test('setUser(null) clears the user for later events', () async {
    await _init();
    SealedTrace.setUser('u-1');
    SealedTrace.i('t', 'a');
    SealedTrace.setUser(null);
    SealedTrace.i('t', 'b');
    await SealedTrace.flush();
    expect(sink.records.map((r) => r.userId), ['u-1', null]);
  });

  test('the disabled path never builds a record', () async {
    await _init(_config.copyWith(enabled: false));
    for (var i = 0; i < 100; i++) {
      SealedTrace.i('t', 'm', meta: {'k': i});
      SealedTrace.f('t', 'm');
    }
    expect(SealedTrace.debugBuiltEvents, 0);
    await SealedTrace.flush();
    expect(sink.batches, isEmpty);
  });

  test('events below minLevel never build a record', () async {
    await _init(_config.copyWith(minLevel: LogLevel.error));
    for (var i = 0; i < 100; i++) {
      SealedTrace.d('t', 'm');
    }
    expect(SealedTrace.debugBuiltEvents, 0);
    SealedTrace.e('t', 'kept');
    expect(SealedTrace.debugBuiltEvents, 1);
  });

  test('fatal flushes without waiting for the timer', () async {
    await _init();
    SealedTrace.f('t', 'crash');
    await Future<void>.delayed(Duration.zero);
    expect(sink.records.single.message, 'crash');
  });

  test('pausing the app flushes the queue', () async {
    await _init();
    SealedTrace.i('t', 'before pause');
    lifecycle.emit(AppLifecycle.paused);
    await Future<void>.delayed(Duration.zero);
    expect(sink.records.single.message, 'before pause');
  });

  test('dispose drains pending events and releases the lifecycle', () async {
    await _init();
    SealedTrace.i('t', 'pending');
    await SealedTrace.dispose();
    expect(sink.records.single.message, 'pending');
    expect(lifecycle.disposed, isTrue);

    SealedTrace.i('t', 'after dispose');
    await Future<void>.delayed(Duration.zero);
    expect(sink.records, hasLength(1));
  });

  test('a throwing sink never reaches the caller', () async {
    final errors = <Object>[];
    SealedTrace.onException = (e, _) => errors.add(e);
    SealedTrace.debugOverrides = RuntimeOverrides(
      disableUploads: true,
      storage: MemoryStorageAdapter(),
      lifecycle: lifecycle,
      deviceContext: testDevice,
      sink: (_) async => throw StateError('sink down'),
    );
    await SealedTrace.init(_config);

    expect(() => SealedTrace.f('t', 'm'), returnsNormally);
    await SealedTrace.flush();

    expect(errors, isNotEmpty);
    expect(SealedTrace.diagnostics.internalExceptions, greaterThan(0));
  });

  test('metadata that cannot be encoded does not break logging', () async {
    await _init();
    final cyclic = <String, dynamic>{};
    cyclic['self'] = cyclic;
    expect(() => SealedTrace.i('t', 'm', meta: cyclic), returnsNormally);
    await SealedTrace.flush();
    expect(sink.records, hasLength(1));
  });

  test('init after dispose starts a new session and sequence', () async {
    await _init();
    SealedTrace.i('t', 'a');
    await SealedTrace.dispose();

    sink = RecordingSink();
    lifecycle = FakeLifecycle();
    await _init();
    SealedTrace.i('t', 'b');
    await SealedTrace.flush();
    expect(sink.records.single.seq, 1);
    expect(sink.records.single.sessionId, 'id-0');
  });

  test('dispose during init leaves the SDK uninitialized', () async {
    SealedTrace.debugOverrides = RuntimeOverrides(
      disableUploads: true,
      storage: MemoryStorageAdapter(),
      lifecycle: lifecycle,
      deviceContext: testDevice,
      sink: sink.call,
    );
    final init = SealedTrace.init(_config);
    await SealedTrace.dispose();
    await init;
    expect(SealedTrace.isInitialized, isFalse);
  });

  test('SealedTrace.i averages under 1 ms per call', () async {
    await _init();
    const calls = 10000;
    final watch = Stopwatch()..start();
    for (var i = 0; i < calls; i++) {
      SealedTrace.i('bench', 'message $i', meta: {'i': i});
    }
    watch.stop();
    final perCallMicros = watch.elapsedMicroseconds / calls;
    // ignore: avoid_print
    print('SealedTrace.i: ${perCallMicros.toStringAsFixed(1)} µs per call');
    expect(perCallMicros, lessThan(1000));
  });
}
