/// Severity of a log event, ordered from least to most severe.
enum LogLevel {
  /// Very detailed tracing output.
  verbose,

  /// Diagnostic information useful while debugging.
  debug,

  /// Normal, noteworthy application events.
  info,

  /// Something unexpected that the app can recover from.
  warning,

  /// A failure that affected an operation.
  error,

  /// A failure that is likely to terminate the app or a major feature.
  fatal;

  /// Whether this level is at least as severe as [other].
  bool isAtLeast(LogLevel other) => index >= other.index;
}
