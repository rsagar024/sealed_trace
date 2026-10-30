import 'package:flutter/foundation.dart';

/// Prints the SDK's own diagnostics when `verboseInternalLogs` is on.
///
/// It never receives log content and never goes through `SealedTrace.log`, so
/// it cannot feed back into the pipeline.
class InternalLogger {
  /// Creates a logger that prints only when [enabled].
  const InternalLogger(this.enabled);

  /// Whether messages are printed.
  final bool enabled;

  /// Prints [message] with the SDK prefix when enabled.
  void log(String message) {
    if (enabled) debugPrint('[sealed_trace] $message');
  }
}
