import 'equality.dart';

/// Configures the Dio network-logging interceptor.
class NetworkLogConfig {
  /// Creates a network logging configuration.
  const NetworkLogConfig({
    this.enabled = true,
    this.maxBodyChars = 20000,
    this.hostAllowlist = const [],
    this.captureRequestBody = true,
    this.captureResponseBody = true,
  });

  /// Whether network calls are logged.
  final bool enabled;

  /// Maximum characters kept per request or response body.
  final int maxBodyChars;

  /// Hosts to log. Empty means every host except the ingest endpoint.
  final List<String> hostAllowlist;

  /// Whether request bodies are captured.
  final bool captureRequestBody;

  /// Whether response bodies are captured.
  final bool captureResponseBody;

  /// Returns a copy with the given fields replaced.
  NetworkLogConfig copyWith({
    bool? enabled,
    int? maxBodyChars,
    List<String>? hostAllowlist,
    bool? captureRequestBody,
    bool? captureResponseBody,
  }) {
    return NetworkLogConfig(
      enabled: enabled ?? this.enabled,
      maxBodyChars: maxBodyChars ?? this.maxBodyChars,
      hostAllowlist: hostAllowlist ?? this.hostAllowlist,
      captureRequestBody: captureRequestBody ?? this.captureRequestBody,
      captureResponseBody: captureResponseBody ?? this.captureResponseBody,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkLogConfig &&
      enabled == other.enabled &&
      maxBodyChars == other.maxBodyChars &&
      listsEqual(hostAllowlist, other.hostAllowlist) &&
      captureRequestBody == other.captureRequestBody &&
      captureResponseBody == other.captureResponseBody;

  @override
  int get hashCode => Object.hash(
    enabled,
    maxBodyChars,
    Object.hashAll(hostAllowlist),
    captureRequestBody,
    captureResponseBody,
  );
}
