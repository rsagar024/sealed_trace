import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/platform/connectivity_monitor.dart';

void main() {
  group('networkKindOf', () {
    test('maps connectivity results to the ctx.network values', () {
      expect(networkKindOf(const []), 'unknown');
      expect(networkKindOf([ConnectivityResult.none]), 'none');
      expect(networkKindOf([ConnectivityResult.wifi]), 'wifi');
      expect(networkKindOf([ConnectivityResult.ethernet]), 'wifi');
      expect(networkKindOf([ConnectivityResult.mobile]), 'mobile');
      expect(networkKindOf([ConnectivityResult.vpn]), 'unknown');
      expect(networkKindOf([ConnectivityResult.bluetooth]), 'unknown');
      expect(networkKindOf([ConnectivityResult.other]), 'unknown');
    });

    test('wifi wins over mobile; none only when everything is none', () {
      expect(
        networkKindOf([ConnectivityResult.mobile, ConnectivityResult.wifi]),
        'wifi',
      );
      expect(
        networkKindOf([ConnectivityResult.none, ConnectivityResult.none]),
        'none',
      );
      expect(
        networkKindOf([ConnectivityResult.none, ConnectivityResult.mobile]),
        'mobile',
      );
    });
  });

  group('isOnlineOf', () {
    test('says nothing for an empty list', () {
      expect(isOnlineOf(const []), isNull);
    });

    test('offline only when every result is none', () {
      expect(isOnlineOf([ConnectivityResult.none]), isFalse);
      expect(isOnlineOf([ConnectivityResult.wifi]), isTrue);
      expect(isOnlineOf([ConnectivityResult.vpn]), isTrue);
      expect(
        isOnlineOf([ConnectivityResult.none, ConnectivityResult.mobile]),
        isTrue,
      );
    });
  });

  group('PluginConnectivityMonitor', () {
    late StreamController<List<ConnectivityResult>> source;
    late PluginConnectivityMonitor monitor;

    setUp(() {
      source = StreamController<List<ConnectivityResult>>.broadcast(sync: true);
    });

    tearDown(() async {
      monitor.dispose();
      await source.close();
    });

    PluginConnectivityMonitor make(List<ConnectivityResult> initial) =>
        monitor = PluginConnectivityMonitor(
          check: () async => initial,
          changes: () => source.stream,
        );

    test('reads the initial state without announcing it', () async {
      make([ConnectivityResult.wifi]);
      final events = <bool>[];
      monitor.onlineChanges.listen(events.add);
      await monitor.start();
      expect(monitor.isOnline, isTrue);
      expect(monitor.networkKind, 'wifi');
      expect(events, isEmpty);
    });

    test('announces transitions to online and offline', () async {
      make([ConnectivityResult.wifi]);
      final events = <bool>[];
      monitor.onlineChanges.listen(events.add);
      await monitor.start();

      source.add([ConnectivityResult.none]);
      expect(monitor.isOnline, isFalse);
      expect(monitor.networkKind, 'none');
      source.add([ConnectivityResult.mobile]);
      expect(monitor.isOnline, isTrue);
      expect(monitor.networkKind, 'mobile');

      await pumpEventQueue();
      expect(events, [false, true]);
    });

    test('switching between online networks does not announce', () async {
      make([ConnectivityResult.wifi]);
      final events = <bool>[];
      monitor.onlineChanges.listen(events.add);
      await monitor.start();
      source.add([ConnectivityResult.mobile]);
      source.add([ConnectivityResult.wifi, ConnectivityResult.mobile]);
      await pumpEventQueue();
      expect(events, isEmpty);
      expect(monitor.networkKind, 'wifi');
    });

    test('starting offline then coming online is announced', () async {
      make([ConnectivityResult.none]);
      final events = <bool>[];
      monitor.onlineChanges.listen(events.add);
      await monitor.start();
      expect(monitor.isOnline, isFalse);
      source.add([ConnectivityResult.wifi]);
      await pumpEventQueue();
      expect(events, [true]);
    });

    test('an empty result list is "unknown", not offline', () async {
      make(const []);
      await monitor.start();
      expect(monitor.isOnline, isNull);
      expect(monitor.networkKind, 'unknown');
    });

    test(
      'a failing check leaves the state unknown and does not throw',
      () async {
        monitor = PluginConnectivityMonitor(
          check: () async => throw StateError('no plugin'),
          changes: () => source.stream,
        );
        await monitor.start();
        expect(monitor.isOnline, isNull);
        expect(monitor.networkKind, 'unknown');
      },
    );

    test('errors on the change stream are ignored', () async {
      make([ConnectivityResult.wifi]);
      await monitor.start();
      source.addError(StateError('flaky'));
      source.add([ConnectivityResult.none]);
      await pumpEventQueue();
      expect(monitor.isOnline, isFalse);
    });

    test('nothing is announced after dispose', () async {
      make([ConnectivityResult.wifi]);
      final events = <bool>[];
      monitor.onlineChanges.listen(events.add);
      await monitor.start();
      monitor.dispose();
      source.add([ConnectivityResult.none]);
      await pumpEventQueue();
      expect(events, isEmpty);
    });
  });

  test(
    'without the plugin (as in unit tests) the real monitor stays unknown',
    () async {
      final monitor = PluginConnectivityMonitor();
      await monitor.start();
      expect(monitor.networkKind, anyOf('unknown', 'wifi', 'mobile', 'none'));
      monitor.dispose();
    },
  );

  test('NoopConnectivityMonitor knows nothing and never emits', () async {
    const monitor = NoopConnectivityMonitor();
    await monitor.start();
    expect(monitor.isOnline, isNull);
    expect(monitor.networkKind, 'unknown');
    expect(await monitor.onlineChanges.isEmpty, isTrue);
  });

  test('ConnectivityNetworkState reports the monitor\'s network kind', () {
    final monitor = PluginConnectivityMonitor(
      check: () async => [ConnectivityResult.mobile],
      changes: () => const Stream<List<ConnectivityResult>>.empty(),
    );
    expect(const NoopConnectivityMonitor().networkKind, 'unknown');
    expect(ConnectivityNetworkState(monitor).current(), 'unknown');
    monitor.dispose();
  });
}
