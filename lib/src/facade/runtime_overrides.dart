import 'dart:math';

import 'package:dio/dio.dart' show HttpClientAdapter;

import '../crypto/crypto_backend.dart';
import '../event/sealing_batch_handler.dart';
import '../event/sequence_counter.dart';
import '../model/device_context.dart';
import '../platform/clock.dart';
import '../platform/connectivity_monitor.dart';
import '../platform/lifecycle_binding.dart';
import '../platform/network_state.dart';
import '../queue/write_behind_queue.dart';
import '../transport/ingest_transport.dart';
import '../storage/envelope_spill.dart';
import '../storage/storage_adapter.dart';

/// Replacements for the SDK's collaborators, used only by tests.
class RuntimeOverrides {
  /// Creates overrides; any field left null uses the real implementation.
  const RuntimeOverrides({
    this.clock,
    this.lifecycle,
    this.sink,
    this.envelopeSink,
    this.cryptoBackend,
    this.storage,
    this.sequenceStore,
    this.deviceContext,
    this.network,
    this.newId,
    this.flushInterval,
    this.ingestClient,
    this.httpClientAdapter,
    this.connectivity,
    this.disableUploads = false,
    this.random,
    this.envelopeSpill,
  });

  /// Time source.
  final Clock? clock;

  /// Lifecycle source.
  final LifecycleBinding? lifecycle;

  /// Replaces the whole batch handler, so records skip sealing.
  final BatchSink? sink;

  /// Receives sealed envelopes instead of the discarding default.
  final EnvelopeSink? envelopeSink;

  /// Crypto primitives.
  final CryptoBackend? cryptoBackend;

  /// Replaces the platform storage (for example with memory storage).
  final StorageAdapter? storage;

  /// Sequence persistence. Defaults to the storage meta table.
  final SequenceStore? sequenceStore;

  /// Device context, skipping plugin lookups.
  final DeviceContext? deviceContext;

  /// Network type source.
  final NetworkStateProvider? network;

  /// Id generator.
  final String Function()? newId;

  /// Queue flush interval.
  final Duration? flushInterval;

  /// Replaces the whole ingest client.
  final IngestClient? ingestClient;

  /// Replaces the HTTP adapter under the real ingest client (a fake server).
  final HttpClientAdapter? httpClientAdapter;

  /// Replaces the connectivity monitor.
  final ConnectivityMonitor? connectivity;

  /// When true no uploader is created, so nothing touches the network.
  final bool disableUploads;

  /// Random source for retry jitter.
  final Random? random;

  /// The page-exit spill. Defaults to `localStorage` on the web and to none
  /// elsewhere.
  final EnvelopeSpill? envelopeSpill;
}
