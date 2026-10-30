import 'dart:async';

import '../diagnostics/diagnostic_counters.dart';
import '../masking/masking_engine.dart';
import '../model/environment.dart';
import '../model/log_level.dart';
import '../platform/lifecycle_binding.dart';
import '../queue/write_behind_queue.dart';
import 'event_builder.dart';
import 'log_record.dart';
import 'page_exit_saver.dart';

/// Builder, masking step, queue and lifecycle flushing as one unit.
class EventPipeline {
  /// Wires the pieces together and starts listening to [lifecycle].
  EventPipeline({
    required this.builder,
    required this.queue,
    required this.lifecycle,
    required this.env,
    required this.counters,
    required this.masking,
    LogRecord Function(LogRecord record)? mask,
  }) : mask = mask ?? masking.maskRecord {
    _subscription = lifecycle.changes.listen(_onLifecycle);
  }

  /// Stamps caller input into records.
  final EventBuilder builder;

  /// Buffers records and delivers batches.
  final WriteBehindQueue queue;

  /// Source of lifecycle changes.
  final LifecycleBinding lifecycle;

  /// Environment, used for the immediate-flush rule.
  final SealedTraceEnv env;

  /// Shared diagnostic counters.
  final DiagnosticCounters counters;

  /// Redacts PII; also reached by `addMaskKeys` and `addMaskPattern`.
  final MaskingEngine masking;

  /// Masking step applied before a record enters the queue. Defaults to
  /// [MaskingEngine.maskRecord]; tests may replace it.
  final LogRecord Function(LogRecord record) mask;

  /// Called when the app returns to the foreground. Set by the uploader.
  void Function()? onResumed;

  /// Web only: saves the queue synchronously on `hidden` and `detached`.
  /// Without it those states flush asynchronously like the others.
  PageExitSaver? pageExitSaver;

  late final StreamSubscription<AppLifecycle> _subscription;

  /// Masks [record] and queues it.
  ///
  /// `fatal` events, and `error` events outside production, flush at once so
  /// the most important events do not wait out the write-behind window.
  void enqueue(LogRecord record) {
    final masked = mask(record);
    final immediate =
        record.level == LogLevel.fatal ||
        (record.level == LogLevel.error && env != SealedTraceEnv.prod);
    queue.add(masked, immediate: immediate);
    counters.eventsAccepted++;
  }

  void _onLifecycle(AppLifecycle state) {
    switch (state) {
      case AppLifecycle.hidden:
      case AppLifecycle.detached:
        final saver = pageExitSaver;
        if (saver != null) {
          // Synchronously, inside the event: an async write may never land.
          saver.saveNow();
        } else {
          unawaited(queue.flush());
        }
      case AppLifecycle.inactive:
      case AppLifecycle.paused:
        unawaited(queue.flush());
      case AppLifecycle.resumed:
        onResumed?.call();
    }
  }

  /// Stops listening, then drains the queue.
  Future<void> dispose() async {
    await _subscription.cancel();
    lifecycle.dispose();
    await queue.dispose();
  }
}
