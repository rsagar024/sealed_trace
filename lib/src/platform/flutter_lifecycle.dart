import 'dart:async';

import 'package:flutter/widgets.dart';

import 'lifecycle_binding.dart';
import 'page_events.dart';

/// A [LifecycleBinding] backed by Flutter's `WidgetsBindingObserver`.
///
/// If the Flutter binding is not available it quietly never emits.
class FlutterLifecycle with WidgetsBindingObserver implements LifecycleBinding {
  /// Registers with the widgets binding when one exists.
  ///
  /// [pageEvents] defaults to the browser's `visibilitychange` and `pagehide`
  /// events on the web (and to nothing elsewhere); tests inject their own.
  FlutterLifecycle({Stream<AppLifecycle>? pageEvents}) {
    try {
      WidgetsBinding.instance.addObserver(this);
      _attached = true;
    } catch (_) {
      // No binding (pure Dart or before runApp): behave as a no-op.
    }
    try {
      _pageSubscription = (pageEvents ?? pageLifecycleEvents()).listen(
        _controller.add,
        onError: (Object _) {},
      );
    } catch (_) {
      // Page events are an extra; the binding above still works.
    }
  }

  final StreamController<AppLifecycle> _controller =
      StreamController<AppLifecycle>.broadcast(sync: true);
  StreamSubscription<AppLifecycle>? _pageSubscription;
  bool _attached = false;

  @override
  Stream<AppLifecycle> get changes => _controller.stream;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _controller.add(switch (state) {
      AppLifecycleState.resumed => AppLifecycle.resumed,
      AppLifecycleState.inactive => AppLifecycle.inactive,
      AppLifecycleState.hidden => AppLifecycle.hidden,
      AppLifecycleState.paused => AppLifecycle.paused,
      AppLifecycleState.detached => AppLifecycle.detached,
    });
  }

  @override
  void dispose() {
    unawaited(_pageSubscription?.cancel());
    _pageSubscription = null;
    if (_attached) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {
        // Binding already gone.
      }
      _attached = false;
    }
    unawaited(_controller.close());
  }
}
