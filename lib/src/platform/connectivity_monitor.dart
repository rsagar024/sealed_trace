import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import 'network_state.dart';

/// Reports whether the device is online and what kind of network it is on.
///
/// This is only a hint: when it is unknown the uploader still tries, and a
/// failed request stays the authority on reachability.
abstract interface class ConnectivityMonitor {
  /// Whether the device is online, or null when that is not known.
  bool? get isOnline;

  /// `wifi`, `mobile`, `none` or `unknown`.
  String get networkKind;

  /// Emits `true` when the device goes online and `false` when it goes offline.
  Stream<bool> get onlineChanges;

  /// Reads the current state and starts listening. Never throws.
  Future<void> start();

  /// Stops listening.
  void dispose();
}

/// `wifi`, `mobile`, `none` or `unknown` for a connectivity result list.
String networkKindOf(List<ConnectivityResult> results) {
  if (results.isEmpty) return 'unknown';
  if (results.contains(ConnectivityResult.wifi) ||
      results.contains(ConnectivityResult.ethernet)) {
    return 'wifi';
  }
  if (results.contains(ConnectivityResult.mobile)) return 'mobile';
  if (results.every((r) => r == ConnectivityResult.none)) return 'none';
  return 'unknown';
}

/// Whether [results] mean online, or null when they say nothing.
bool? isOnlineOf(List<ConnectivityResult> results) {
  if (results.isEmpty) return null;
  return !results.every((r) => r == ConnectivityResult.none);
}

/// A [ConnectivityMonitor] over the `connectivity_plus` plugin.
///
/// Every plugin call is guarded: where the plugin is unavailable (pure Dart,
/// unit tests) the monitor simply stays "unknown".
class PluginConnectivityMonitor implements ConnectivityMonitor {
  /// Creates the monitor. [check] and [changes] replace the plugin (tests).
  PluginConnectivityMonitor({
    Future<List<ConnectivityResult>> Function()? check,
    Stream<List<ConnectivityResult>> Function()? changes,
  }) : _checkSource = check,
       _changeSource = changes;

  final Future<List<ConnectivityResult>> Function()? _checkSource;
  final Stream<List<ConnectivityResult>> Function()? _changeSource;
  final StreamController<bool> _changes = StreamController<bool>.broadcast();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool? _online;
  String _kind = 'unknown';

  @override
  bool? get isOnline => _online;

  @override
  String get networkKind => _kind;

  @override
  Stream<bool> get onlineChanges => _changes.stream;

  @override
  Future<void> start() async {
    try {
      final plugin = (_checkSource == null || _changeSource == null)
          ? Connectivity()
          : null;
      final check = _checkSource ?? plugin!.checkConnectivity;
      final changes = _changeSource ?? (() => plugin!.onConnectivityChanged);
      _apply(
        await check().timeout(const Duration(seconds: 2)),
        announce: false,
      );
      _subscription = changes().listen(
        (results) => _apply(results, announce: true),
        onError: (Object _) {},
      );
    } catch (_) {
      // Plugin unavailable: stay unknown.
    }
  }

  void _apply(List<ConnectivityResult> results, {required bool announce}) {
    _kind = networkKindOf(results);
    final online = isOnlineOf(results);
    final changed = online != _online;
    _online = online;
    if (announce && changed && online != null && !_changes.isClosed) {
      _changes.add(online);
    }
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    _subscription = null;
    unawaited(_changes.close());
  }
}

/// A monitor that knows nothing and never emits.
class NoopConnectivityMonitor implements ConnectivityMonitor {
  /// Creates the monitor.
  const NoopConnectivityMonitor();

  @override
  bool? get isOnline => null;

  @override
  String get networkKind => 'unknown';

  @override
  Stream<bool> get onlineChanges => const Stream<bool>.empty();

  @override
  Future<void> start() async {}

  @override
  void dispose() {}
}

/// Feeds `ctx.network` from a [ConnectivityMonitor].
class ConnectivityNetworkState implements NetworkStateProvider {
  /// Creates the provider.
  const ConnectivityNetworkState(this.monitor);

  /// Where the value comes from.
  final ConnectivityMonitor monitor;

  @override
  String current() => monitor.networkKind;
}
