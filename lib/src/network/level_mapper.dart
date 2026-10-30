import '../model/log_level.dart';

/// The log level for a network call.
///
/// A cancelled request is a warning. A call that threw, so has no [status],
/// is an error. Otherwise 2xx is debug, 4xx a warning, 5xx an error, and
/// anything else (1xx, 3xx, unusual codes) debug.
LogLevel levelForNetwork({int? status, bool cancelled = false}) {
  if (cancelled) return LogLevel.warning;
  if (status == null) return LogLevel.error;
  if (status >= 400 && status < 500) return LogLevel.warning;
  if (status >= 500 && status < 600) return LogLevel.error;
  return LogLevel.debug;
}
