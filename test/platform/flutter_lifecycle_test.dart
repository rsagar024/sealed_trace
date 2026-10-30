import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/platform/flutter_lifecycle.dart';
import 'package:sealed_trace/src/platform/lifecycle_binding.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forwards Flutter lifecycle states', () async {
    final lifecycle = FlutterLifecycle(pageEvents: const Stream.empty());
    final seen = <AppLifecycle>[];
    final sub = lifecycle.changes.listen(seen.add);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.resumed);
    expect(seen, [AppLifecycle.paused, AppLifecycle.resumed]);
    await sub.cancel();
    lifecycle.dispose();
  });

  test(
    'page events (web visibilitychange, pagehide) reach the listeners',
    () async {
      final page = StreamController<AppLifecycle>.broadcast(sync: true);
      final lifecycle = FlutterLifecycle(pageEvents: page.stream);
      final seen = <AppLifecycle>[];
      final sub = lifecycle.changes.listen(seen.add);
      page.add(AppLifecycle.hidden);
      page.add(AppLifecycle.detached);
      expect(seen, [AppLifecycle.hidden, AppLifecycle.detached]);
      await sub.cancel();
      lifecycle.dispose();
      expect(page.hasListener, isFalse, reason: 'dispose stops listening');
      await page.close();
    },
  );

  test('a failing page source never breaks the binding', () async {
    final page = StreamController<AppLifecycle>.broadcast(sync: true);
    final lifecycle = FlutterLifecycle(pageEvents: page.stream);
    final seen = <AppLifecycle>[];
    final sub = lifecycle.changes.listen(seen.add);
    page.addError(StateError('boom'));
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.hidden);
    expect(seen, [AppLifecycle.hidden]);
    await sub.cancel();
    lifecycle.dispose();
    await page.close();
  });

  test('a page source that cannot be listened to never breaks the binding', () {
    final lifecycle = FlutterLifecycle(pageEvents: _ThrowingStream());
    final seen = <AppLifecycle>[];
    final sub = lifecycle.changes.listen(seen.add);
    lifecycle.didChangeAppLifecycleState(AppLifecycleState.paused);
    expect(seen, [AppLifecycle.paused]);
    sub.cancel();
    lifecycle.dispose();
  });

  test('without a page source (VM) it still works', () {
    final lifecycle = FlutterLifecycle();
    lifecycle.dispose();
  });
}

class _ThrowingStream extends Stream<AppLifecycle> {
  @override
  StreamSubscription<AppLifecycle> listen(
    void Function(AppLifecycle event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => throw StateError('no page');
}
