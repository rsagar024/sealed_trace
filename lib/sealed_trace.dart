/// Production-grade logging SDK for Flutter and Dart.
///
/// Logs are masked, sealed with hybrid encryption that only the SealedTrace
/// server can open, stored offline and uploaded reliably.
///
/// ```dart
/// await SealedTrace.init(const SealedTraceConfig(
///   baseUrl: 'https://logs.example.com',
///   projectId: 'my-project',
///   apiKey: 'sk_live_…',
///   publicKeyPem: projectPublicKeyPem,
///   appName: 'shop',
/// ));
/// SealedTrace.i('checkout', 'order placed', meta: {'orderId': 'o-123'});
/// ```
///
/// Start with [SealedTrace] and [SealedTraceConfig]; use
/// [SealedTraceInterceptor] to log Dio calls. The device holds only the
/// project's public key, so nothing here can read a stored log back.
library;

export 'src/config/mask_config.dart';
export 'src/config/network_log_config.dart';
export 'src/config/retention_config.dart';
export 'src/config/sealed_trace_config.dart';
export 'src/config/upload_config.dart';
export 'src/diagnostics/diagnostic_counters.dart' show DiagnosticSnapshot;
export 'src/facade/sealed_trace.dart';
export 'src/model/environment.dart';
export 'src/model/log_event.dart';
export 'src/model/log_level.dart';
export 'src/model/upload_result.dart';
export 'src/network/sealed_trace_interceptor.dart';
