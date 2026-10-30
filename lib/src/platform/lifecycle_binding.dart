/// App lifecycle states the SDK reacts to.
enum AppLifecycle {
  /// Visible and responding.
  resumed,

  /// Visible but not focused.
  inactive,

  /// Hidden from the user.
  hidden,

  /// In the background.
  paused,

  /// About to be destroyed.
  detached,
}

/// Source of app lifecycle changes.
abstract interface class LifecycleBinding {
  /// Emits each lifecycle change. Broadcast.
  Stream<AppLifecycle> get changes;

  /// Stops listening and releases resources.
  void dispose();
}

/// A binding that never emits, for pure Dart and tests.
class NoopLifecycleBinding implements LifecycleBinding {
  /// Creates the binding.
  const NoopLifecycleBinding();

  @override
  Stream<AppLifecycle> get changes => const Stream<AppLifecycle>.empty();

  @override
  void dispose() {}
}
