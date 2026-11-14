import 'package:dio/dio.dart' show HttpClientAdapter;

/// Returns an app-attestation token for one upload request, or null.
typedef AttestationTokenProvider = Future<String?> Function();

/// Configures when and how sealed envelopes are uploaded.
class UploadConfig {
  /// Creates an upload configuration.
  const UploadConfig({
    this.interval = const Duration(minutes: 15),
    this.sizeThresholdEvents = 200,
    this.sizeThresholdBytes = 256 * 1024,
    this.maxAttempts = 5,
    this.batchSize = 50,
    this.requestTimeout = const Duration(seconds: 30),
    this.backoffBase = const Duration(seconds: 5),
    this.uploadOnResume = true,
    this.uploadOnConnectivityRestored = true,
    this.httpClientAdapter,
    this.attestationTokenProvider,
  });

  /// Period of the scheduled upload cycle.
  final Duration interval;

  /// Pending event count that triggers an upload.
  final int sizeThresholdEvents;

  /// Pending payload size, in bytes, that triggers an upload.
  final int sizeThresholdBytes;

  /// Failed attempts per envelope before it is dead-lettered.
  final int maxAttempts;

  /// Envelopes per upload request. Clamped to 1..50 by the SDK.
  final int batchSize;

  /// Timeout for a single ingest request.
  final Duration requestTimeout;

  /// Base delay of the exponential retry backoff.
  final Duration backoffBase;

  /// Whether an upload is attempted when the app returns to the foreground.
  final bool uploadOnResume;

  /// Whether an upload is attempted when connectivity is restored.
  final bool uploadOnConnectivityRestored;

  /// The HTTP client the SDK's own uploads use, or null for Dio's default.
  ///
  /// For a proxy, custom certificates, or a mock server (the example app's
  /// mock mode uses one). It replaces only the connection layer: requests
  /// still go to `{baseUrl}/api/v1/ingest/logs` with the same headers and
  /// timeouts, and no interceptor is ever added to the SDK's own client.
  /// Compared by identity.
  final HttpClientAdapter? httpClientAdapter;

  /// Supplies an app-attestation token, sent with every upload as the
  /// `X-SealedTrace-Attestation` header so the server can check that the
  /// request comes from your genuine app, not just from someone holding the
  /// (extractable) API key. Typical sources are Firebase App Check, Play
  /// Integrity or App Attest.
  ///
  /// Called once per upload request, within `requestTimeout`. If it throws,
  /// times out, or returns null, an empty value or a value with a line break,
  /// the request is **not** sent. The cycle is retried with backoff, and no
  /// upload attempt is counted, so envelopes are never dead-lettered because
  /// of it (retention limits still apply). The token is never logged.
  /// Compared by identity.
  final AttestationTokenProvider? attestationTokenProvider;

  /// Returns a copy with the given fields replaced.
  UploadConfig copyWith({
    Duration? interval,
    int? sizeThresholdEvents,
    int? sizeThresholdBytes,
    int? maxAttempts,
    int? batchSize,
    Duration? requestTimeout,
    Duration? backoffBase,
    bool? uploadOnResume,
    bool? uploadOnConnectivityRestored,
    HttpClientAdapter? httpClientAdapter,
    AttestationTokenProvider? attestationTokenProvider,
  }) {
    return UploadConfig(
      interval: interval ?? this.interval,
      sizeThresholdEvents: sizeThresholdEvents ?? this.sizeThresholdEvents,
      sizeThresholdBytes: sizeThresholdBytes ?? this.sizeThresholdBytes,
      maxAttempts: maxAttempts ?? this.maxAttempts,
      batchSize: batchSize ?? this.batchSize,
      requestTimeout: requestTimeout ?? this.requestTimeout,
      backoffBase: backoffBase ?? this.backoffBase,
      uploadOnResume: uploadOnResume ?? this.uploadOnResume,
      uploadOnConnectivityRestored:
          uploadOnConnectivityRestored ?? this.uploadOnConnectivityRestored,
      httpClientAdapter: httpClientAdapter ?? this.httpClientAdapter,
      attestationTokenProvider:
          attestationTokenProvider ?? this.attestationTokenProvider,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UploadConfig &&
      interval == other.interval &&
      sizeThresholdEvents == other.sizeThresholdEvents &&
      sizeThresholdBytes == other.sizeThresholdBytes &&
      maxAttempts == other.maxAttempts &&
      batchSize == other.batchSize &&
      requestTimeout == other.requestTimeout &&
      backoffBase == other.backoffBase &&
      uploadOnResume == other.uploadOnResume &&
      uploadOnConnectivityRestored == other.uploadOnConnectivityRestored &&
      identical(httpClientAdapter, other.httpClientAdapter) &&
      identical(attestationTokenProvider, other.attestationTokenProvider);

  @override
  int get hashCode => Object.hash(
    interval,
    sizeThresholdEvents,
    sizeThresholdBytes,
    maxAttempts,
    batchSize,
    requestTimeout,
    backoffBase,
    uploadOnResume,
    uploadOnConnectivityRestored,
    httpClientAdapter == null ? 0 : identityHashCode(httpClientAdapter),
    attestationTokenProvider == null
        ? 0
        : identityHashCode(attestationTokenProvider),
  );
}
