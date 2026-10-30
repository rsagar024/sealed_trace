import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'lifecycle_binding.dart';

/// Page lifecycle events from the browser.
///
/// `AppLifecycleState` is unreliable on the web, so the page itself is
/// watched: `visibilitychange` to hidden reports [AppLifecycle.hidden], and
/// `pagehide` (tab close, navigation away, bfcache) reports
/// [AppLifecycle.detached]. Both make the pipeline persist its queue.
Stream<AppLifecycle> pageLifecycleEvents() {
  late final StreamController<AppLifecycle> controller;
  final JSFunction onVisibility = ((web.Event _) {
    try {
      if (web.document.visibilityState == 'hidden') {
        controller.add(AppLifecycle.hidden);
      }
    } catch (_) {
      // Never let a page event reach the host app.
    }
  }).toJS;
  final JSFunction onPageHide = ((web.Event _) {
    try {
      controller.add(AppLifecycle.detached);
    } catch (_) {
      // Same.
    }
  }).toJS;
  controller = StreamController<AppLifecycle>.broadcast(
    sync: true,
    onListen: () {
      try {
        web.document.addEventListener('visibilitychange', onVisibility);
        web.window.addEventListener('pagehide', onPageHide);
      } catch (_) {
        // No document (worker): stay silent.
      }
    },
    onCancel: () {
      try {
        web.document.removeEventListener('visibilitychange', onVisibility);
        web.window.removeEventListener('pagehide', onPageHide);
      } catch (_) {
        // Already gone.
      }
    },
  );
  return controller.stream;
}
