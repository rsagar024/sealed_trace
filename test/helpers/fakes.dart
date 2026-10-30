import 'dart:async';

import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/model/device_context.dart';
import 'package:sealed_trace/src/model/log_level.dart';
import 'package:sealed_trace/src/platform/clock.dart';
import 'package:sealed_trace/src/platform/lifecycle_binding.dart';

const testDevice = DeviceContext(
  appVersion: '1.2.3',
  buildNumber: '45',
  platform: 'android',
  os: 'Android 14',
  locale: 'en_IN',
);

class FakeClock implements Clock {
  FakeClock(this.value);
  DateTime value;

  @override
  DateTime now() => value;
}

class FakeLifecycle implements LifecycleBinding {
  final StreamController<AppLifecycle> _controller =
      StreamController<AppLifecycle>.broadcast(sync: true);
  bool disposed = false;

  void emit(AppLifecycle state) => _controller.add(state);

  @override
  Stream<AppLifecycle> get changes => _controller.stream;

  @override
  void dispose() {
    disposed = true;
    unawaited(_controller.close());
  }
}

/// Records every batch handed to it.
class RecordingSink {
  final List<List<LogRecord>> batches = [];

  List<LogRecord> get records => [for (final b in batches) ...b];

  Future<void> call(List<LogRecord> batch) async {
    batches.add(batch);
  }
}

int _counter = 0;

LogRecord makeRecord({
  LogLevel level = LogLevel.info,
  String message = 'm',
  int? seq,
}) {
  _counter++;
  return LogRecord(
    id: 'id-$_counter',
    seq: seq ?? _counter,
    timestamp: DateTime.utc(2026, 1, 1, 10),
    level: level,
    tag: 't',
    message: message,
    error: null,
    stackTrace: null,
    metadata: const {},
    sessionId: 's',
    userId: null,
    ctx: const {},
  );
}
