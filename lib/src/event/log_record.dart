import 'dart:convert';

import '../model/log_level.dart';

/// A stamped log event: the exact content that is later encrypted.
///
/// Created only by the SDK. Callers hand in a `LogEvent`; the id, sequence,
/// session, user and context are stamped here and cannot be set from outside.
class LogRecord {
  /// Creates a record.
  LogRecord({
    required this.id,
    required this.seq,
    required DateTime timestamp,
    required this.level,
    required this.tag,
    required this.message,
    required this.error,
    required this.stackTrace,
    required this.metadata,
    required this.sessionId,
    required this.userId,
    required this.ctx,
  }) : timestamp = timestamp.toUtc();

  /// uuid-v4.
  final String id;

  /// Per-install monotonic counter.
  final int seq;

  /// UTC, millisecond precision.
  final DateTime timestamp;

  /// Severity.
  final LogLevel level;

  /// Category label.
  final String tag;

  /// Message text.
  final String message;

  /// Error text, or null.
  final String? error;

  /// Stack trace text, or null.
  final String? stackTrace;

  /// JSON-safe metadata.
  final Map<String, dynamic> metadata;

  /// uuid-v4 of the app run.
  final String sessionId;

  /// User id, or null.
  final String? userId;

  /// Device and app context plus caller context.
  final Map<String, dynamic> ctx;

  /// Approximate serialized size, used by the queue's byte threshold.
  late final int approxBytes = jsonEncode(toJson()).length;

  /// Returns a copy with the given fields replaced. A null argument keeps the
  /// current value.
  LogRecord copyWith({
    String? message,
    String? error,
    String? stackTrace,
    Map<String, dynamic>? metadata,
    Map<String, dynamic>? ctx,
  }) {
    return LogRecord(
      id: id,
      seq: seq,
      timestamp: timestamp,
      level: level,
      tag: tag,
      message: message ?? this.message,
      error: error ?? this.error,
      stackTrace: stackTrace ?? this.stackTrace,
      metadata: metadata ?? this.metadata,
      sessionId: sessionId,
      userId: userId,
      ctx: ctx ?? this.ctx,
    );
  }

  /// The wire form defined by the data model (section 5).
  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'seq': seq,
    'ts': timestamp.toUtc().toIso8601String(),
    'level': level.name,
    'tag': tag,
    'message': message,
    'error': error,
    'stackTrace': stackTrace,
    'metadata': metadata,
    'sessionId': sessionId,
    'userId': userId,
    'ctx': ctx,
  };
}
