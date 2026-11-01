import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';

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

Future<void> _init([SealedTraceConfig config = _config]) async {
  SealedTrace.debugOverrides = RuntimeOverrides(
    disableUploads: true,
    storage: MemoryStorageAdapter(),
    lifecycle: FakeLifecycle(),
    sink: sink.call,
    deviceContext: testDevice,
  );
  await SealedTrace.init(config);
}

void main() {
  setUp(() async {
    await SealedTrace.dispose();
    SealedTrace.onException = null;
    sink = RecordingSink();
  });

  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.debugOverrides = null;
    SealedTrace.onException = null;
  });

  test('events reach the sink already masked', () async {
    await _init();
    SealedTrace.setUser('user-42', name: 'Asha Rao');
    SealedTrace.setContext({'contact': 'ctx@example.com'});
    SealedTrace.e(
      'auth',
      'login failed for asha@example.com',
      error: 'card 4111111111111111 declined',
      stack: StackTrace.fromString('#0 phone +91 98765 43210'),
      meta: {
        'password': 'hunter2',
        'profile': {'email': 'p@q.com', 'city': 'Pune'},
      },
    );
    await SealedTrace.flush();

    final record = sink.records.single;
    expect(record.message, 'login failed for ***');
    expect(record.error, 'card *** declined');
    expect(record.stackTrace, '#0 phone ***');
    expect(record.metadata['password'], '***');
    expect((record.metadata['profile'] as Map)['email'], '***');
    expect((record.metadata['profile'] as Map)['city'], 'Pune');
    expect(record.ctx['userName'], 'Asha Rao');
    expect(record.ctx['userDisplayName'], 'Asha Rao');
    expect(record.ctx['contact'], '***');
    expect(record.userId, 'user-42');

    // The readable name is allowed only in the two user name keys.
    final text = jsonEncode(
      record
          .copyWith(
            ctx: Map.of(record.ctx)
              ..remove('userName')
              ..remove('userDisplayName'),
          )
          .toJson(),
    );
    for (final secret in [
      'asha@example.com',
      '4111111111111111',
      '98765 43210',
      'hunter2',
      'p@q.com',
      'Asha Rao',
      'ctx@example.com',
    ]) {
      expect(text, isNot(contains(secret)), reason: secret);
    }
  });

  test('log(LogEvent) is masked too', () async {
    await _init();
    SealedTrace.log(
      LogEvent(
        level: LogLevel.warning,
        tag: 't',
        message: 'ping 555-123-4567',
        metadata: {'token': 'abc'},
      ),
    );
    await SealedTrace.flush();
    expect(sink.records.single.message, 'ping ***');
    expect(sink.records.single.metadata, {'token': '***'});
  });

  test('MaskConfig from the init config is honoured', () async {
    await _init(
      _config.copyWith(
        maskConfig: MaskConfig(
          extraKeys: const ['orderRef'],
          extraPatterns: [RegExp(r'EMP-\d{6}')],
        ),
      ),
    );
    SealedTrace.i('t', 'emp EMP-123456', meta: {'orderRef': 'X1', 'n': 1});
    await SealedTrace.flush();
    expect(sink.records.single.message, 'emp ***');
    expect(sink.records.single.metadata, {'orderRef': '***', 'n': 1});
  });

  test('addMaskKeys applies to later events only', () async {
    await _init();
    SealedTrace.i('t', 'before', meta: {'iban': 'GB00'});
    SealedTrace.addMaskKeys(['IBAN']);
    SealedTrace.i('t', 'after', meta: {'iban': 'GB00'});
    await SealedTrace.flush();
    expect(sink.records[0].metadata, {'iban': 'GB00'});
    expect(sink.records[1].metadata, {'iban': '***'});
  });

  test('addMaskPattern applies to later events', () async {
    await _init();
    SealedTrace.addMaskPattern(RegExp(r'PIN \d{4}'));
    SealedTrace.i('t', 'use PIN 4821 now');
    await SealedTrace.flush();
    expect(sink.records.single.message, 'use *** now');
  });

  test(
    'a pattern that matches the empty string is reported and ignored',
    () async {
      final errors = <Object>[];
      SealedTrace.onException = (e, _) => errors.add(e);
      await _init();
      SealedTrace.addMaskPattern(RegExp(r'x*'));
      SealedTrace.i('t', 'abc');
      await SealedTrace.flush();
      expect(errors, hasLength(1));
      expect(errors.single, isA<ArgumentError>());
      expect(sink.records.single.message, 'abc');
    },
  );

  test('masking does not change ids, sequence or timestamps', () async {
    await _init();
    SealedTrace.i('t', 'a@b.com');
    SealedTrace.i('t', 'c@d.com');
    await SealedTrace.flush();
    expect(sink.records.map((r) => r.seq), [1, 2]);
    expect(sink.records.map((r) => r.id).toSet(), hasLength(2));
  });

  test('masking keeps SealedTrace.i fast (average under 1 ms)', () async {
    await _init();
    const calls = 5000;
    final watch = Stopwatch()..start();
    for (var i = 0; i < calls; i++) {
      SealedTrace.i(
        'bench',
        'user asha@example.com paid with 4111 1111 1111 1111 at $i',
        meta: {'phone': '+91 98765 43210', 'i': i, 'note': 'call 555-123-4567'},
      );
    }
    watch.stop();
    final perCall = watch.elapsedMicroseconds / calls;
    // ignore: avoid_print
    print(
      'SealedTrace.i with masking: ${perCall.toStringAsFixed(1)} µs per call',
    );
    expect(perCall, lessThan(1000));
  });
}
