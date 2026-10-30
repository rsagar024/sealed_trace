import '../transport/ingest_transport.dart';

/// Decides which requests the network interceptor may log.
abstract final class HostFilter {
  /// Whether [uri]'s host is allowed by [allowlist].
  ///
  /// An empty list allows every host. Otherwise an entry is either an exact
  /// host (case-insensitive, port ignored) or `*.example.com`, which matches
  /// any subdomain of `example.com` but not `example.com` itself.
  static bool allows(Uri uri, List<String> allowlist) {
    if (allowlist.isEmpty) return true;
    final host = _normalizeHost(uri.host);
    if (host.isEmpty) return false;
    for (final raw in allowlist) {
      final entry = _normalizeEntry(raw);
      if (entry.isEmpty) continue;
      if (entry.startsWith('*.')) {
        final suffix = entry.substring(1); // ".example.com"
        if (host.length > suffix.length && host.endsWith(suffix)) return true;
      } else if (host == entry) {
        return true;
      }
    }
    return false;
  }

  /// Whether [request] is a call to the SDK's own ingest endpoint, which must
  /// never be logged. Host, effective port and path must all match.
  static bool isIngestRequest(Uri request, String baseUrl) {
    try {
      final ingest = IngestTransport.ingestUri(baseUrl);
      if (_normalizeHost(request.host) != _normalizeHost(ingest.host)) {
        return false;
      }
      if (request.port != ingest.port) return false;
      return _trimSlashes(request.path) == _trimSlashes(ingest.path);
    } catch (_) {
      return false;
    }
  }

  static String _normalizeHost(String host) {
    var value = host.trim().toLowerCase();
    if (value.startsWith('[') && value.endsWith(']')) {
      value = value.substring(1, value.length - 1);
    }
    while (value.endsWith('.')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static String _normalizeEntry(String raw) {
    var value = raw.trim().toLowerCase();
    final scheme = value.indexOf('://');
    if (scheme >= 0) value = value.substring(scheme + 3);
    final slash = value.indexOf('/');
    if (slash >= 0) value = value.substring(0, slash);
    // Drop a port, but leave IPv6 literals alone.
    if (!value.startsWith('[') &&
        value.indexOf(':') == value.lastIndexOf(':')) {
      final colon = value.indexOf(':');
      if (colon >= 0) value = value.substring(0, colon);
    } else if (value.startsWith('[')) {
      final close = value.indexOf(']');
      if (close > 0) value = value.substring(0, close + 1);
    }
    return _normalizeHost(value);
  }

  static String _trimSlashes(String path) =>
      path.replaceAll(RegExp(r'/+$'), '').replaceAll(RegExp(r'^/+'), '');
}
