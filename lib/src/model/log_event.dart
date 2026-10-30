import 'log_level.dart';

/// A structured log event handed to `SealedTrace.log` for full control.
///
/// The SDK stamps the id, sequence number, session, user and device context
/// itself; they cannot be set by the caller.
class LogEvent {
  /// Creates an event. [timestamp] defaults to the current time.
  LogEvent({
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
    this.metadata,
    DateTime? timestamp,
  }) : timestamp = (timestamp ?? DateTime.now()).toUtc();

  /// Severity of the event.
  final LogLevel level;

  /// Short category label, such as `auth` or `network`.
  final String tag;

  /// Human-readable message. Masked before the event is sealed.
  final String message;

  /// Optional error object. Its string form is masked before sealing.
  final Object? error;

  /// Optional stack trace. Masked before sealing.
  final StackTrace? stackTrace;

  /// Optional structured data. Masked before sealing.
  final Map<String, dynamic>? metadata;

  /// When the event occurred (UTC).
  final DateTime timestamp;
}
