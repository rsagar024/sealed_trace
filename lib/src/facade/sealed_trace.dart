import 'dart:async';

import 'package:flutter/foundation.dart' show compute;
import 'package:meta/meta.dart';
import 'package:uuid/uuid.dart';

import '../config/config_validator.dart';
import '../config/sealed_trace_config.dart';
import '../crypto/crypto_backend.dart';
import '../crypto/envelope_sealer.dart';
import '../crypto/public_key_parser.dart';
import '../diagnostics/diagnostic_counters.dart';
import '../diagnostics/internal_logger.dart';
import '../event/event_builder.dart';
import '../event/event_pipeline.dart';
import '../event/metadata_normalizer.dart';
import '../event/page_exit_saver.dart';
import '../event/sealing_batch_handler.dart';
import '../event/sequence_counter.dart';
import '../masking/masking_engine.dart';
import '../model/log_event.dart';
import '../model/log_level.dart';
import '../model/upload_result.dart';
import '../platform/clock.dart';
import '../platform/device_context_loader.dart';
import '../platform/flutter_lifecycle.dart';
import '../platform/connectivity_monitor.dart';
import '../queue/write_behind_queue.dart';
import '../storage/envelope_spill.dart';
import '../storage/envelope_store.dart';
import '../storage/open_storage.dart';
import '../storage/retention_policy.dart';
import '../storage/storage_adapter.dart';
import '../storage/storage_sequence_store.dart';
import '../storage/storage_service.dart';
import '../transport/ingest_transport.dart';
import '../upload/backoff.dart';
import '../upload/triggers.dart';
import '../upload/upload_scheduler.dart';
import 'runtime.dart';
import 'runtime_overrides.dart';

/// Entry point of the SealedTrace logging SDK.
///
/// Call [init] once at startup, then log with [v], [d], [i], [w], [e] and [f].
/// No method ever throws: internal failures are swallowed, counted in
/// [diagnostics] and reported through [onException]. Before [init], after
/// [dispose], or when `enabled` is false, every call is a cheap no-op.
abstract final class SealedTrace {
  static Runtime? _runtime;
  static Future<void>? _initFuture;
  static DiagnosticCounters _counters = DiagnosticCounters();
  static InternalLogger _logger = const InternalLogger(false);
  static int _generation = 0;

  /// Replaces internal collaborators. Only for tests; set before [init].
  @visibleForTesting
  static RuntimeOverrides? debugOverrides;

  /// The running SDK state, for the network interceptor. Not public API.
  @internal
  static Runtime? get internalRuntime => _runtime;

  /// Counts and reports a swallowed failure, for the network interceptor.
  @internal
  static void reportInternal(Object error, StackTrace stack) =>
      _report(error, stack);

  /// Records built since [init]. Only for tests.
  @visibleForTesting
  static int get debugBuiltEvents =>
      _runtime?.pipeline?.builder.builtCount ?? 0;

  /// Called when the SDK swallows an internal exception.
  ///
  /// An exception thrown by this callback is itself swallowed.
  static void Function(Object error, StackTrace stack)? onException;

  /// Called after every upload cycle.
  static void Function(UploadResult result)? onUploadResult;

  /// Whether [init] completed successfully and [dispose] has not been called.
  static bool get isInitialized => _runtime != null;

  /// A snapshot of the SDK's internal counters. Never contains log content.
  static DiagnosticSnapshot get diagnostics => _counters.snapshot();

  /// Initializes the SDK.
  ///
  /// Idempotent: later calls return the first call's future and are otherwise
  /// ignored. To change the configuration, call [dispose] first. An invalid
  /// [config] leaves the SDK uninitialized and is reported through
  /// [onException]. Never throws.
  static Future<void> init(SealedTraceConfig config) {
    final existing = _initFuture;
    if (existing != null) return existing;
    return _initFuture = _initialize(config);
  }

  /// Logs at [LogLevel.verbose].
  static void v(String tag, String message, {Map<String, dynamic>? meta}) =>
      _emit(LogLevel.verbose, tag, message, null, null, meta, null);

  /// Logs at [LogLevel.debug].
  static void d(String tag, String message, {Map<String, dynamic>? meta}) =>
      _emit(LogLevel.debug, tag, message, null, null, meta, null);

  /// Logs at [LogLevel.info].
  static void i(String tag, String message, {Map<String, dynamic>? meta}) =>
      _emit(LogLevel.info, tag, message, null, null, meta, null);

  /// Logs at [LogLevel.warning].
  static void w(String tag, String message, {Map<String, dynamic>? meta}) =>
      _emit(LogLevel.warning, tag, message, null, null, meta, null);

  /// Logs at [LogLevel.error], optionally with an [error] and [stack].
  static void e(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? meta,
  }) => _emit(LogLevel.error, tag, message, error, stack, meta, null);

  /// Logs at [LogLevel.fatal], optionally with an [error] and [stack].
  static void f(
    String tag,
    String message, {
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? meta,
  }) => _emit(LogLevel.fatal, tag, message, error, stack, meta, null);

  /// Logs a fully specified [event].
  static void log(LogEvent event) => _emit(
    event.level,
    event.tag,
    event.message,
    event.error,
    event.stackTrace,
    event.metadata,
    event.timestamp,
  );

  /// Sets the current user. Pass a null [id] on logout.
  ///
  /// [name] is masked like any other value. No-op before [init].
  static void setUser(String? id, {String? name}) {
    final runtime = _runtime;
    if (runtime == null) return;
    try {
      runtime.userId = id;
      runtime.userName = name;
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Merges [ctx] into the context attached to every later event.
  ///
  /// No-op before [init].
  static void setContext(Map<String, dynamic> ctx) {
    final runtime = _runtime;
    if (runtime == null) return;
    try {
      runtime.context.addAll(MetadataNormalizer.normalize(ctx));
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Adds sensitive [keys] to mask, matched case-insensitively.
  ///
  /// No-op before [init].
  static void addMaskKeys(List<String> keys) {
    final runtime = _runtime;
    if (runtime == null) return;
    try {
      runtime.pipeline?.masking.addKeys(keys);
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Adds a [pattern] whose matches are masked in every string value.
  ///
  /// No-op before [init].
  static void addMaskPattern(RegExp pattern) {
    final runtime = _runtime;
    if (runtime == null) return;
    try {
      final masking = runtime.pipeline?.masking;
      if (masking != null && !masking.addPattern(pattern)) {
        _report(
          ArgumentError.value(
            pattern.pattern,
            'pattern',
            'Mask pattern ignored: it matches the empty string',
          ),
          StackTrace.current,
        );
      }
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Uploads pending logs now and returns the outcome.
  ///
  /// Completes with [UploadOutcome.skipped] when nothing was attempted.
  /// Never completes with an error.
  static Future<UploadResult> flush() async {
    final pipeline = _runtime?.pipeline;
    if (pipeline == null) return UploadResult.skipped();
    try {
      await pipeline.queue.flush();
    } catch (error, stack) {
      _report(error, stack);
    }
    final uploader = _runtime?.uploader;
    if (uploader == null) return UploadResult.skipped();
    return uploader.request(UploadTrigger.manual);
  }

  /// Deletes all locally stored logs, for example on logout.
  ///
  /// Never completes with an error.
  static Future<void> clearLocalLogs() async {
    final runtime = _runtime;
    if (runtime == null) return;
    try {
      await runtime.clearLocal();
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Flushes pending work and releases resources.
  ///
  /// Afterwards [init] may be called again. Never completes with an error.
  static Future<void> dispose() async {
    final runtime = _runtime;
    _generation++;
    _runtime = null;
    _initFuture = null;
    try {
      await runtime?.dispose();
    } catch (error, stack) {
      _report(error, stack);
    }
    _counters = DiagnosticCounters();
    _logger = const InternalLogger(false);
  }

  static Future<void> _initialize(SealedTraceConfig config) async {
    final generation = _generation;
    StorageAdapter? opened;
    ConnectivityMonitor? startedMonitor;
    try {
      final problems = ConfigValidator.validate(config);
      if (problems.isNotEmpty) {
        _report(
          StateError('Invalid SealedTraceConfig: ${problems.join('; ')}'),
          StackTrace.current,
        );
        return;
      }
      final clamped = ConfigValidator.clamp(config);
      _logger = InternalLogger(clamped.verboseInternalLogs);

      EventPipeline? pipeline;
      PageExitSaver? exitSaver;
      StorageService? storage;
      UploadScheduler? uploader;
      if (clamped.enabled) {
        final RsaPublicKeyData publicKey;
        try {
          publicKey = PublicKeyParser.parse(clamped.publicKeyPem);
        } on FormatException catch (error, stack) {
          // Fail closed: without a usable key nothing can be sealed.
          _report(StateError('Invalid publicKeyPem: ${error.message}'), stack);
          return;
        }
        final overrides = debugOverrides;
        final counters = _counters;
        final adapter =
            overrides?.storage ??
            await openPlatformStorage(
              databaseDirectory: clamped.databaseDirectory,
              onProblem: (error, stack) {
                counters.storageFailures++;
                _report(error, stack);
              },
            );
        opened = adapter;
        final seqStore =
            overrides?.sequenceStore ?? StorageSequenceStore(adapter);
        final highWater = await seqStore.readHighWater();
        final device = overrides?.deviceContext ?? await loadDeviceContext();
        final monitor = overrides?.connectivity ?? PluginConnectivityMonitor();
        await monitor.start();
        startedMonitor = monitor;
        if (generation != _generation) return;

        final service = StorageService(
          store: EnvelopeStore(
            adapter: adapter,
            policy: RetentionPolicy.fromConfig(clamped.retentionConfig),
            onPurged: (n) => counters.purgedRows += n,
            onDeadLettered: (n) => counters.envelopesDeadLettered += n,
          ),
          purgeInterval: clamped.retentionConfig.purgeInterval,
          clock: overrides?.clock ?? const SystemClock(),
          counters: counters,
          onError: _report,
        );
        storage = service;

        final newId = overrides?.newId ?? const Uuid().v4;
        final builder = EventBuilder(
          sequence: SequenceCounter(
            seqStore,
            highWater: highWater,
            onError: _report,
          ),
          sessionId: newId(),
          device: device,
          env: clamped.env,
          network: overrides?.network ?? ConnectivityNetworkState(monitor),
          clock: overrides?.clock ?? const SystemClock(),
          newId: newId,
        );
        final sealer = EnvelopeSealer(
          publicKey: publicKey,
          projectId: clamped.projectId,
          backend:
              overrides?.cryptoBackend ??
              DefaultCryptoBackend(offload: (job) => compute(runAesGcm, job)),
          clock: overrides?.clock ?? const SystemClock(),
          newId: newId,
        );
        final queue = WriteBehindQueue(
          sink:
              overrides?.sink ??
              SealingBatchHandler(
                sealer: sealer,
                counters: counters,
                onError: _report,
                envelopeSink: overrides?.envelopeSink ?? service.save,
              ).call,
          onError: _report,
          onDropped: () => counters.eventsDroppedQueueFull++,
          flushInterval: overrides?.flushInterval ?? const Duration(seconds: 2),
        );
        pipeline = EventPipeline(
          builder: builder,
          queue: queue,
          lifecycle: overrides?.lifecycle ?? FlutterLifecycle(),
          env: clamped.env,
          counters: counters,
          masking: MaskingEngine(clamped.maskConfig, onError: _report),
        );
        final spill =
            overrides?.envelopeSpill ??
            (overrides == null ? openPlatformEnvelopeSpill() : null);
        if (spill != null && overrides?.sink == null) {
          exitSaver = PageExitSaver(
            queue: queue,
            sealer: sealer,
            spill: spill,
            store: overrides?.envelopeSink ?? service.save,
            counters: counters,
            onError: _report,
          );
          pipeline.pageExitSaver = exitSaver;
        }

        if (overrides?.disableUploads != true) {
          final scheduler = UploadScheduler(
            store: service.store,
            client:
                overrides?.ingestClient ??
                IngestTransport(
                  baseUrl: clamped.baseUrl,
                  apiKey: clamped.apiKey,
                  timeout: clamped.uploadConfig.requestTimeout,
                  adapter:
                      overrides?.httpClientAdapter ??
                      clamped.uploadConfig.httpClientAdapter,
                  clock: overrides?.clock ?? const SystemClock(),
                ),
            config: clamped.uploadConfig,
            counters: counters,
            clock: overrides?.clock ?? const SystemClock(),
            backoff: Backoff(
              base: clamped.uploadConfig.backoffBase,
              random: overrides?.random,
            ),
            connectivity: monitor,
            onResult: _deliverUploadResult,
            onError: _report,
            purge: ({Set<String> protected = const <String>{}}) =>
                service.purge(protected: protected),
          );
          service.onStored = scheduler.noteStored;
          service.inFlight = () => scheduler.inFlightIds;
          if (clamped.uploadConfig.uploadOnResume) {
            pipeline.onResumed = () =>
                unawaited(scheduler.request(UploadTrigger.resume));
          }
          uploader = scheduler;
        }
      }

      await storage?.start();
      // Envelopes spilled when the page was last left go to storage before
      // the cold-start upload cycle.
      await exitSaver?.recover();
      await uploader?.start();
      if (generation != _generation) {
        // Disposed while starting: release what was built.
        await uploader?.dispose();
        await pipeline?.dispose();
        await storage?.dispose();
        opened = null;
        return;
      }

      _runtime = Runtime(
        clamped,
        _counters,
        pipeline: pipeline,
        storage: storage,
        uploader: uploader,
        connectivity: startedMonitor,
      );
      opened = null; // The runtime owns the adapter now.
      startedMonitor = null; // ...and the connectivity monitor.
      _logger.log('initialized (enabled: ${clamped.enabled})');
    } catch (error, stack) {
      _report(error, stack);
    } finally {
      startedMonitor?.dispose();
      final leftover = opened;
      if (leftover != null) {
        try {
          await leftover.close();
        } catch (_) {
          // Init already failed or was cancelled; nothing more to report.
        }
      }
    }
  }

  static void _deliverUploadResult(UploadResult result) {
    try {
      onUploadResult?.call(result);
    } catch (error, stack) {
      _report(error, stack);
    }
  }

  /// Gate shared by every logging call. Nothing is allocated before a call
  /// passes it, so a disabled or filtered call is a null check and an int
  /// comparison.
  static void _emit(
    LogLevel level,
    String tag,
    String message,
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? meta,
    DateTime? timestamp,
  ) {
    final runtime = _runtime;
    if (runtime == null || !runtime.enabled) return;
    if (level.index < runtime.minLevelIndex) {
      runtime.counters.eventsDroppedLevel++;
      return;
    }
    try {
      runtime.record(level, tag, message, error, stack, meta, timestamp);
    } catch (e, s) {
      _report(e, s);
    }
  }

  static void _report(Object error, StackTrace stack) {
    _counters.internalExceptions++;
    _logger.log('internal exception: ${error.runtimeType}');
    try {
      onException?.call(error, stack);
    } catch (_) {
      // A faulty callback must never break the host app.
    }
  }
}
