import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _config = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj',
  apiKey: 'key',
  publicKeyPem: testPublicKeySpki,
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

/// Logs one event and returns the record as the sink received it.
Future<LogRecord> _logOne() async {
  final before = sink.records.length;
  SealedTrace.i('t', 'm');
  await SealedTrace.flush();
  expect(sink.records, hasLength(before + 1));
  return sink.records.last;
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

  test('setUser sends the name readably in both keys', () async {
    await _init();
    SealedTrace.setUser('u1', name: 'Demo User');
    final record = await _logOne();
    expect(record.userId, 'u1');
    expect(record.ctx['userName'], 'Demo User');
    expect(record.ctx['userDisplayName'], 'Demo User');
  });

  test('maskUserName: true masks userName but not userDisplayName', () async {
    await _init(
      _config.copyWith(maskConfig: const MaskConfig(maskUserName: true)),
    );
    SealedTrace.setUser('u1', name: 'Demo User');
    final record = await _logOne();
    expect(record.ctx['userName'], '***');
    expect(record.ctx['userDisplayName'], 'Demo User');
  });

  test('the name is trimmed, and a blank or null name is not sent', () async {
    await _init();
    SealedTrace.setUser('u1', name: '  Demo User  ');
    final trimmed = await _logOne();
    expect(trimmed.ctx['userName'], 'Demo User');
    expect(trimmed.ctx['userDisplayName'], 'Demo User');

    for (final name in [null, '', '   ']) {
      SealedTrace.setUser('u1', name: name);
      final record = await _logOne();
      expect(record.ctx.containsKey('userName'), isFalse, reason: name);
      expect(record.ctx.containsKey('userDisplayName'), isFalse, reason: name);
    }
  });

  test('a long name is cut to 256 characters', () async {
    await _init();
    SealedTrace.setUser('u1', name: 'n' * 300);
    final record = await _logOne();
    expect(record.ctx['userName'], 'n' * 256);
    expect(record.ctx['userDisplayName'], 'n' * 256);
  });

  test('clearing the user removes both name keys', () async {
    await _init();
    SealedTrace.setUser('u1', name: 'Demo User');
    await _logOne();

    SealedTrace.setUser(null);
    var record = await _logOne();
    expect(record.userId, isNull);
    expect(record.ctx.containsKey('userName'), isFalse);
    expect(record.ctx.containsKey('userDisplayName'), isFalse);

    SealedTrace.setUser('u1', name: 'Demo User');
    SealedTrace.setUser('u2');
    record = await _logOne();
    expect(record.userId, 'u2');
    expect(record.ctx.containsKey('userName'), isFalse);
    expect(record.ctx.containsKey('userDisplayName'), isFalse);
  });

  test('setContext neither removes nor overrides userDisplayName', () async {
    await _init();
    SealedTrace.setUser('u1', name: 'Demo User');
    SealedTrace.setContext({'userDisplayName': 'Spoof', 'plan': 'pro'});
    var record = await _logOne();
    expect(record.ctx['userDisplayName'], 'Demo User');
    expect(record.ctx['plan'], 'pro');

    SealedTrace.setContext({'other': 1});
    record = await _logOne();
    expect(record.ctx['userDisplayName'], 'Demo User');
  });

  test('a userDisplayName from setContext alone is never sent', () async {
    await _init();
    SealedTrace.setContext({'userDisplayName': 'Spoof'});
    final record = await _logOne();
    expect(record.ctx.containsKey('userDisplayName'), isFalse);
  });

  test('sendUserDisplayName: false never sends the key', () async {
    await _init(_config.copyWith(sendUserDisplayName: false));
    SealedTrace.setUser('u1', name: 'Demo User');
    SealedTrace.setContext({'userDisplayName': 'Demo User'});
    final record = await _logOne();
    expect(record.ctx['userName'], 'Demo User');
    expect(record.ctx.containsKey('userDisplayName'), isFalse);
  });

  test('the raw name never reaches diagnostics or onException', () async {
    final reported = <String>[];
    SealedTrace.onException = (error, stack) => reported.add('$error $stack');
    await _init();
    SealedTrace.setUser('u1', name: 'Demo Marker');
    await _logOne();
    final diagnostics = SealedTrace.diagnostics;
    expect('$diagnostics', isNot(contains('Demo Marker')));
    for (final message in reported) {
      expect(message, isNot(contains('Demo Marker')));
    }
  });
}
