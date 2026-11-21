import 'package:dio/dio.dart' show HttpClientAdapter;

/// Certificate pinning is not available on this platform (the web: the
/// browser owns TLS). Returns null, so the default client is used.
HttpClientAdapter? createPinnedAdapter(Set<String> pins) => null;

/// Whether [error] is a pin mismatch raised by the pinned adapter.
bool isPinMismatch(Object? error) => false;
