// Selects, at compile time, how certificate pinning is enforced. Only native
// platforms can: on the web the browser owns TLS, so pins are not applied.
export 'pinned_adapter_stub.dart' if (dart.library.io) 'pinned_adapter_io.dart';
