import 'lifecycle_binding.dart';

/// No browser page here, so nothing to report.
Stream<AppLifecycle> pageLifecycleEvents() =>
    const Stream<AppLifecycle>.empty();
