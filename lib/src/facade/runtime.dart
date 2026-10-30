import '../config/sealed_trace_config.dart';
import '../diagnostics/diagnostic_counters.dart';
import '../event/event_pipeline.dart';
import '../model/log_level.dart';
import '../platform/connectivity_monitor.dart';
import '../storage/storage_service.dart';
import '../upload/upload_scheduler.dart';

/// State of an initialized SDK. Internal.
///
/// Created by `SealedTrace.init` after the config validates, and dropped by
/// `SealedTrace.dispose`.
class Runtime {
  /// Creates the runtime for a validated [config].
  ///
  /// [pipeline] is null when the config is disabled, so a disabled SDK holds
  /// no queue, timers or listeners.
  Runtime(
    this.config,
    this.counters, {
    this.pipeline,
    this.storage,
    this.uploader,
    this.connectivity,
  }) : enabled = config.enabled,
       minLevelIndex = config.minLevel.index;

  /// Local storage and retention, or null when disabled.
  final StorageService? storage;

  /// The upload scheduler, or null when disabled.
  final UploadScheduler? uploader;

  /// The connectivity monitor, or null when disabled.
  final ConnectivityMonitor? connectivity;

  /// The validated, clamped configuration.
  final SealedTraceConfig config;

  /// Diagnostic counters shared with the facade.
  final DiagnosticCounters counters;

  /// The event pipeline, or null when disabled.
  final EventPipeline? pipeline;

  /// Cached `config.enabled`, read on every logging call.
  final bool enabled;

  /// Cached `config.minLevel.index`, read on every logging call.
  final int minLevelIndex;

  /// Current user id, or null when signed out.
  String? userId;

  /// Current user display name, or null.
  String? userName;

  /// Extra context merged into every event. Values are already JSON-safe.
  final Map<String, dynamic> context = {};

  /// Builds a record from a call that passed the gate and queues it.
  void record(
    LogLevel level,
    String tag,
    String message,
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? meta,
    DateTime? timestamp,
  ) {
    final pipeline = this.pipeline;
    if (pipeline == null) return;
    pipeline.enqueue(
      pipeline.builder.build(
        level: level,
        tag: tag,
        message: message,
        error: error,
        stack: stack,
        meta: meta,
        timestamp: timestamp,
        userId: userId,
        userName: userName,
        extraContext: context,
      ),
    );
  }

  /// Throws away queued events and stored envelopes, keeping `seq` moving
  /// forward so numbers are never reused.
  Future<void> clearLocal() async {
    final pipeline = this.pipeline;
    if (pipeline == null) return;
    pipeline.queue.discardPending();
    pipeline.pageExitSaver?.clear();
    await pipeline.queue.settle();
    await storage?.clear();
  }

  /// Stops uploads, drains the queue to storage, then stops retention and
  /// closes storage.
  Future<void> dispose() async {
    await uploader?.dispose();
    await pipeline?.dispose();
    await pipeline?.builder.sequence.settle();
    await storage?.dispose();
    connectivity?.dispose();
  }
}
