// Drives the example app on a real device or emulator:
//
//   cd example
//   flutter test integration_test -d <device>
//
// It taps through the demo and checks that events are accepted, that the
// mock ingest server receives sealed envelopes, and that the SDK reported no
// problem. It sends no request to the optional public echo service.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace_example/main.dart';

Future<void> _tap(WidgetTester tester, String label) async {
  final button = find.text(label);
  await tester.scrollUntilVisible(button, 200);
  await tester.tap(button);
  await tester.pump(const Duration(milliseconds: 300));
}

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

  testWidgets('the demo logs, masks, uploads to the mock server and clears', (
    tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await _pumpUntil(tester, () => SealedTrace.isInitialized);
    expect(SealedTrace.isInitialized, isTrue);

    await _tap(tester, 'Log every level');
    await _tap(tester, 'Log with PII');
    await _tap(tester, 'Mock API call');
    await tester.pump(const Duration(seconds: 1));
    await _tap(tester, 'Flush');

    // 6 levels + 1 PII event + 1 network event from the interceptor.
    await _pumpUntil(tester, () => SealedTrace.diagnostics.eventsAccepted >= 8);
    expect(SealedTrace.diagnostics.eventsAccepted, greaterThanOrEqualTo(8));

    final server = find.textContaining('Mock ingest server (');
    await _pumpUntil(tester, () {
      final w = tester.widgetList<Text>(server);
      return w.isNotEmpty && !w.first.data!.contains('(0 envelopes)');
    });
    final title = tester.widget<Text>(server).data!;
    expect(title, isNot(contains('(0 envelopes)')), reason: title);

    expect(find.textContaining('onException'), findsNothing);
    expect(SealedTrace.diagnostics.sealFailures, 0);
    expect(SealedTrace.diagnostics.storageFailures, 0);

    await _tap(tester, 'Clear local logs');
    await _pumpUntil(
      tester,
      () => find.textContaining('clearLocalLogs').evaluate().isNotEmpty,
    );
    expect(find.textContaining('clearLocalLogs'), findsWidgets);
  });
}
