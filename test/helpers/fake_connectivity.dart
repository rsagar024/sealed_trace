import 'dart:async';

import 'package:sealed_trace/src/platform/connectivity_monitor.dart';

/// A [ConnectivityMonitor] the test controls.
class FakeConnectivity implements ConnectivityMonitor {
  FakeConnectivity({this.online, this.kind = 'wifi'});

  bool? online;
  String kind;
  bool started = false;
  bool disposed = false;
  final StreamController<bool> _controller = StreamController<bool>.broadcast(
    sync: true,
  );

  @override
  bool? get isOnline => online;

  @override
  String get networkKind => kind;

  @override
  Stream<bool> get onlineChanges => _controller.stream;

  /// Changes the state and announces it, like the plugin would.
  void setOnline(bool value) {
    online = value;
    kind = value ? 'wifi' : 'none';
    _controller.add(value);
  }

  @override
  Future<void> start() async {
    started = true;
  }

  @override
  void dispose() {
    disposed = true;
    unawaited(_controller.close());
  }
}
