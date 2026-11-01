// Drives the example app on a real device or emulator:
//
//   cd example
//   flutter test integration_test -d <device>
//
// It runs offline: the SDK is initialized here with a demo-only public key
// and a mock ingest server, because pumpWidget does not run main(). It checks
// that the screen's events are accepted, that the mock server receives sealed
// envelopes, and that the SDK reported no problem.

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace_example/main.dart';

import 'demo_key.dart';
import 'mock_ingest.dart';

/// Pumps until [condition] holds or [timeout] passes.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final end = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the example logs, masks and uploads sealed envelopes', (
    tester,
  ) async {
    final ingest = MockIngestAdapter();
    final exceptions = <Object>[];
    SealedTrace.onException = (error, _) => exceptions.add(error);

    await SealedTrace.init(
      SealedTraceConfig(
        baseUrl: 'https://ingest.mock.invalid', // never contacted
        projectId: 'demo-project',
        apiKey: 'demo-api-key', // placeholder, not a real key
        publicKeyPem: demoPublicKeyPem,
        appName: 'sealed_trace_example',
        env: SealedTraceEnv('dev'),
        minLevel: LogLevel.info,
        uploadConfig: UploadConfig(httpClientAdapter: ingest),
      ),
    );
    expect(SealedTrace.isInitialized, isTrue);
    SealedTrace.setUser('demo-user', name: 'Demo User');

    // The screen logs and flushes once on start.
    await tester.pumpWidget(const ExampleApp());

    // info, warning, error, fatal + 1 PII event; verbose and debug dropped.
    await _pumpUntil(tester, () => SealedTrace.diagnostics.eventsAccepted >= 5);
    expect(SealedTrace.diagnostics.eventsAccepted, greaterThanOrEqualTo(5));

    await tester.tap(find.text('Flush'));
    await _pumpUntil(tester, () => ingest.received.isNotEmpty);
    expect(ingest.received, isNotEmpty);

    expect(exceptions, isEmpty);
    expect(SealedTrace.diagnostics.sealFailures, 0);
    expect(SealedTrace.diagnostics.storageFailures, 0);

    await SealedTrace.dispose();
  });
}
