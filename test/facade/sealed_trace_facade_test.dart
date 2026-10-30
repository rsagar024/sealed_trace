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

void _logAtEveryLevel() {
  SealedTrace.v('t', 'm');
  SealedTrace.d('t', 'm');
  SealedTrace.i('t', 'm');
  SealedTrace.w('t', 'm');
  SealedTrace.e('t', 'm', error: 'x', stack: StackTrace.current);
  SealedTrace.f('t', 'm', meta: {'k': 1});
  SealedTrace.log(LogEvent(level: LogLevel.info, tag: 't', message: 'm'));
}

void main() {
  setUp(() async {
    await SealedTrace.dispose();
    SealedTrace.onException = null;
    SealedTrace.onUploadResult = null;
    // Keep tests off the filesystem: the default storage uses path_provider.
    SealedTrace.debugOverrides = RuntimeOverrides(
      disableUploads: true,
      storage: MemoryStorageAdapter(),
      lifecycle: FakeLifecycle(),
      deviceContext: testDevice,
    );
  });

  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.onException = null;
  });

  test('every method is safe before init', () async {
    _logAtEveryLevel();
    SealedTrace.setUser('u', name: 'n');
    SealedTrace.setContext({'a': 1});
    SealedTrace.addMaskKeys(['k']);
    SealedTrace.addMaskPattern(RegExp('x'));
    await SealedTrace.clearLocalLogs();
    expect((await SealedTrace.flush()).outcome, UploadOutcome.skipped);
    expect(SealedTrace.isInitialized, isFalse);
    expect(SealedTrace.diagnostics.eventsAccepted, 0);
  });

  test('init with a valid config initializes', () async {
    await SealedTrace.init(_config);
    expect(SealedTrace.isInitialized, isTrue);
  });

  test('init is idempotent and returns the first future', () async {
    final first = SealedTrace.init(_config);
    final second = SealedTrace.init(_config.copyWith(enabled: false));
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);
    SealedTrace.i('t', 'm');
    // The second config (disabled) was ignored.
    expect(SealedTrace.diagnostics.eventsAccepted, 1);
  });

  test('concurrent init calls initialize once', () async {
    await Future.wait(List.generate(5, (_) => SealedTrace.init(_config)));
    expect(SealedTrace.isInitialized, isTrue);
    expect(SealedTrace.diagnostics.internalExceptions, 0);
  });

  test('dispose then init works again with a new config', () async {
    await SealedTrace.init(_config);
    await SealedTrace.dispose();
    expect(SealedTrace.isInitialized, isFalse);

    await SealedTrace.init(_config.copyWith(enabled: false));
    expect(SealedTrace.isInitialized, isTrue);
    SealedTrace.i('t', 'm');
    expect(SealedTrace.diagnostics.eventsAccepted, 0);
  });

  test('an invalid config reports and leaves the SDK uninitialized', () async {
    final errors = <Object>[];
    SealedTrace.onException = (e, _) => errors.add(e);

    await SealedTrace.init(_config.copyWith(apiKey: ''));

    expect(SealedTrace.isInitialized, isFalse);
    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
    expect(SealedTrace.diagnostics.internalExceptions, 1);
    _logAtEveryLevel();
    expect(SealedTrace.diagnostics.eventsAccepted, 0);
  });

  test('a throwing onException callback never escapes', () async {
    SealedTrace.onException = (_, _) => throw StateError('boom');
    await SealedTrace.init(_config.copyWith(projectId: ''));
    expect(SealedTrace.diagnostics.internalExceptions, 1);
  });

  test('enabled=false is a no-op and counts nothing', () async {
    await SealedTrace.init(_config.copyWith(enabled: false));
    _logAtEveryLevel();
    final d = SealedTrace.diagnostics;
    expect(d.eventsAccepted, 0);
    expect(d.eventsDroppedLevel, 0);
  });

  test('events below minLevel are dropped before any work', () async {
    await SealedTrace.init(_config.copyWith(minLevel: LogLevel.warning));
    SealedTrace.v('t', 'm');
    SealedTrace.d('t', 'm');
    SealedTrace.i('t', 'm');
    var d = SealedTrace.diagnostics;
    expect(d.eventsAccepted, 0);
    expect(d.eventsDroppedLevel, 3);

    SealedTrace.w('t', 'm');
    SealedTrace.e('t', 'm');
    SealedTrace.f('t', 'm');
    d = SealedTrace.diagnostics;
    expect(d.eventsAccepted, 3);
    expect(d.eventsDroppedLevel, 3);
  });

  test('log(LogEvent) honours the level gate', () async {
    await SealedTrace.init(_config.copyWith(minLevel: LogLevel.error));
    SealedTrace.log(LogEvent(level: LogLevel.info, tag: 't', message: 'm'));
    SealedTrace.log(LogEvent(level: LogLevel.fatal, tag: 't', message: 'm'));
    expect(SealedTrace.diagnostics.eventsAccepted, 1);
    expect(SealedTrace.diagnostics.eventsDroppedLevel, 1);
  });

  test('invalid upload values are clamped, not rejected', () async {
    await SealedTrace.init(
      _config.copyWith(
        uploadConfig: const UploadConfig(batchSize: 999, maxAttempts: 0),
      ),
    );
    expect(SealedTrace.isInitialized, isTrue);
    expect(SealedTrace.diagnostics.internalExceptions, 0);
  });

  test('state setters work after init and flush skips for now', () async {
    await SealedTrace.init(_config);
    SealedTrace.setUser('u', name: 'n');
    SealedTrace.setUser(null);
    SealedTrace.setContext({'a': 1});
    SealedTrace.addMaskKeys(['k']);
    SealedTrace.addMaskPattern(RegExp('x'));
    expect((await SealedTrace.flush()).outcome, UploadOutcome.skipped);
    expect(SealedTrace.diagnostics.internalExceptions, 0);
  });
}
