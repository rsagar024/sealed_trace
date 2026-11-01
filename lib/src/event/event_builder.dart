import 'package:uuid/uuid.dart';

import '../model/device_context.dart';
import '../model/environment.dart';
import '../model/log_level.dart';
import '../platform/clock.dart';
import '../platform/network_state.dart';
import 'log_record.dart';
import 'metadata_normalizer.dart';
import 'sequence_counter.dart';

/// Context keys the SDK itself fills in. They hold no user data, so masking
/// leaves them alone.
const Set<String> coreContextKeys = <String>{
  'appVersion',
  'buildNumber',
  'platform',
  'os',
  'locale',
  'env',
  'network',
};

/// Context key for the readable user name set by `SealedTrace.setUser`.
///
/// Masking leaves it alone and only `setUser` can set it. The server uses it
/// for the Users tab only and drops it from stored log context.
const String userDisplayNameKey = 'userDisplayName';

/// Longest `ctx.userDisplayName` the server accepts, in UTF-16 code units.
const int maxUserDisplayNameLength = 256;

/// Trims [name] and cuts it to [maxUserDisplayNameLength] without splitting a
/// surrogate pair. Returns null when [name] is null or blank.
String? normalizeUserDisplayName(String? name) {
  if (name == null) return null;
  var value = name.trim();
  if (value.isEmpty) return null;
  if (value.length > maxUserDisplayNameLength) {
    var end = maxUserDisplayNameLength;
    final last = value.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end--;
    value = value.substring(0, end).trimRight();
  }
  return value.isEmpty ? null : value;
}

/// Stamps caller input into a [LogRecord].
class EventBuilder {
  /// Creates a builder for one app run.
  EventBuilder({
    required this.sequence,
    required this.sessionId,
    required DeviceContext device,
    required SealedTraceEnv env,
    this.network = const UnknownNetworkState(),
    this.clock = const SystemClock(),
    String Function()? newId,
  }) : _newId = newId ?? const Uuid().v4,
       _core = <String, dynamic>{
         'appVersion': device.appVersion,
         'buildNumber': device.buildNumber,
         'platform': device.platform,
         'os': device.os,
         'locale': device.locale,
         'env': env.name,
       };

  /// Source of sequence numbers.
  final SequenceCounter sequence;

  /// uuid-v4 shared by every event of this run.
  final String sessionId;

  /// Reports the current network type.
  final NetworkStateProvider network;

  /// Source of timestamps for events that do not carry their own.
  final Clock clock;

  final String Function() _newId;
  final Map<String, dynamic> _core;

  /// Events at or above this size have their long fields shortened.
  ///
  /// Sized so that a network event with two 20,000-character bodies fits.
  static const int maxEventChars = 128 * 1024;

  static const String _suffix = '…[truncated]';

  /// How many records this builder has produced. For tests.
  int builtCount = 0;

  /// Builds a record. [extraContext] must already be JSON-safe.
  LogRecord build({
    required LogLevel level,
    required String tag,
    required String message,
    Object? error,
    StackTrace? stack,
    Map<String, dynamic>? meta,
    DateTime? timestamp,
    String? userId,
    String? userName,
    String? userDisplayName,
    Map<String, dynamic> extraContext = const <String, dynamic>{},
  }) {
    builtCount++;
    final at = timestamp ?? clock.now();
    final ctx = <String, dynamic>{...extraContext};
    // Owned by setUser: a value from setContext is never sent.
    ctx.remove(userDisplayNameKey);
    if (userName != null) ctx['userName'] = userName;
    if (userDisplayName != null) ctx[userDisplayNameKey] = userDisplayName;
    ctx.addAll(_core);
    ctx['network'] = network.current();

    final record = LogRecord(
      id: _newId(),
      seq: sequence.next(),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        at.millisecondsSinceEpoch,
        isUtc: true,
      ),
      level: level,
      tag: tag,
      message: message,
      error: _text(error),
      stackTrace: _text(stack),
      metadata: MetadataNormalizer.normalize(meta),
      sessionId: sessionId,
      userId: userId,
      ctx: ctx,
    );
    return record.approxBytes > maxEventChars ? _shrink(record) : record;
  }

  LogRecord _shrink(LogRecord record) {
    final shrunk = record.copyWith(
      message: _cut(record.message, 16 * 1024),
      error: record.error == null ? null : _cut(record.error!, 8 * 1024),
      stackTrace: record.stackTrace == null
          ? null
          : _cut(record.stackTrace!, 16 * 1024),
    );
    if (shrunk.approxBytes <= maxEventChars) return shrunk;
    return shrunk.copyWith(
      metadata: <String, dynamic>{
        '_truncated': true,
        '_originalChars': record.approxBytes,
      },
    );
  }

  static String _cut(String value, int max) =>
      value.length <= max ? value : '${value.substring(0, max)}$_suffix';

  static String? _text(Object? value) {
    if (value == null) return null;
    try {
      return value.toString();
    } catch (_) {
      return '[unprintable]';
    }
  }
}
