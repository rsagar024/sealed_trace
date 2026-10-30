@TestOn('vm')
library;

// The code samples from README.md, kept here so they must compile against
// the real API (P9.2). The test runs them against an SDK whose uploads are
// disabled. If a README sample changes, change it here too.

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const projectPublicKeyPem = testPublicKeySpki;

Future<void> quickStart() async {
  SealedTrace.onException = (error, stack) {
    // The SDK never throws into your app; problems are reported here.
  };
  await SealedTrace.init(
    const SealedTraceConfig(
      baseUrl: 'https://logs.example.com',
      projectId: 'my-project',
      apiKey: 'sk_live_…',
      publicKeyPem: projectPublicKeyPem,
      appName: 'shop',
      env: SealedTraceEnv.prod,
      minLevel: LogLevel.info,
    ),
  );
}

void levels(Object e, StackTrace s) {
  SealedTrace.v('cache', 'hit', meta: {'key': 'home'});
  SealedTrace.d('cache', 'miss');
  SealedTrace.i('auth', 'signed in');
  SealedTrace.w('sync', 'retrying');
  SealedTrace.e('payment', 'charge failed', error: e, stack: s);
  SealedTrace.f('app', 'unrecoverable', error: e, stack: s);
}

Future<void> signInOut() async {
  SealedTrace.setUser('user-42');
  SealedTrace.setContext({'plan': 'pro', 'abVariant': 'B'});
  await SealedTrace.clearLocalLogs();
  SealedTrace.setUser(null);
}

void ownMasking() {
  SealedTrace.addMaskKeys(['iban', 'authorization']);
  SealedTrace.addMaskPattern(RegExp(r'\bORD-\d{6}\b'));
}

Dio dioWithInterceptor() => Dio()..interceptors.add(SealedTraceInterceptor());

void captureCrashes() {
  FlutterError.onError = (details) {
    SealedTrace.f(
      'flutter',
      details.exceptionAsString(),
      error: details.exception,
      stack: details.stack,
    );
    FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    SealedTrace.f('uncaught', '$error', error: error, stack: stack);
    return true;
  };
}

String diagnostics() {
  final d = SealedTrace.diagnostics;
  return '${d.eventsAccepted} accepted, ${d.uploadFailures} upload failures';
}

/// The "API overview" block of the README.
Future<void> apiOverview(
  SealedTraceConfig config,
  Object error,
  StackTrace stack,
) async {
  // Lifecycle: never throws.
  await SealedTrace.init(config);
  SealedTrace.isInitialized;

  // Logging: six levels, or a full LogEvent.
  SealedTrace.i('tag', 'message', meta: {'key': 'value'});
  SealedTrace.e('tag', 'message', error: error, stack: stack);
  SealedTrace.log(
    LogEvent(level: LogLevel.warning, tag: 'tag', message: 'message'),
  );

  // Context: these do nothing before init has completed.
  SealedTrace.setUser('user-42', name: 'Asha');
  SealedTrace.setContext({'plan': 'pro'});
  SealedTrace.addMaskKeys(['iban']);
  SealedTrace.addMaskPattern(RegExp(r'\bORD-\d{6}\b'));

  // Delivery and local data.
  final UploadResult result = await SealedTrace.flush();
  result.outcome;
  await SealedTrace.clearLocalLogs();

  // Observability: no log content in any of these.
  SealedTrace.onUploadResult = (UploadResult result) {};
  final DiagnosticSnapshot d = SealedTrace.diagnostics;
  d.eventsAccepted;

  // Dio.
  Dio().interceptors.add(SealedTraceInterceptor());
  await SealedTrace.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.debugOverrides = null;
    SealedTrace.onException = null;
  });

  test('the README samples run against the real API', () async {
    final errors = <Object>[];
    SealedTrace.debugOverrides = RuntimeOverrides(
      disableUploads: true,
      storage: MemoryStorageAdapter(),
      lifecycle: FakeLifecycle(),
      deviceContext: testDevice,
    );
    await quickStart();
    SealedTrace.onException = (e, _) => errors.add(e);
    expect(SealedTrace.isInitialized, isTrue);

    levels(StateError('x'), StackTrace.current);
    await signInOut();
    ownMasking();
    expect(dioWithInterceptor().interceptors, isNotEmpty);
    expect(diagnostics(), contains('accepted'));
    expect(errors, isEmpty);
    // minLevel: info drops verbose and debug.
    expect(SealedTrace.diagnostics.eventsDroppedLevel, 2);

    await SealedTrace.dispose();
    await apiOverview(
      const SealedTraceConfig(
        baseUrl: 'https://logs.example.com',
        projectId: 'my-project',
        apiKey: 'sk_live_…',
        publicKeyPem: projectPublicKeyPem,
        appName: 'shop',
      ),
      StateError('x'),
      StackTrace.current,
    );
    expect(errors, isEmpty);
    expect(SealedTrace.isInitialized, isFalse); // disposed at the end
  });

  test('the crash-capture sample installs both handlers', () {
    final previousFlutter = FlutterError.onError;
    final previousPlatform = PlatformDispatcher.instance.onError;
    try {
      captureCrashes();
      expect(FlutterError.onError, isNot(previousFlutter));
      expect(PlatformDispatcher.instance.onError, isNotNull);
    } finally {
      FlutterError.onError = previousFlutter;
      PlatformDispatcher.instance.onError = previousPlatform;
    }
  });
}
