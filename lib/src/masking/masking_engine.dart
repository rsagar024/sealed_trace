import 'dart:collection';

import '../config/mask_config.dart';
import '../event/event_builder.dart';
import '../event/log_record.dart';
import 'default_keys.dart';
import 'default_patterns.dart';
import 'header_redactor.dart';
import 'url_redactor.dart';

/// Redacts PII before an event is sealed. Also used for network logs.
///
/// Order of work: header denylist, then sensitive keys, then pattern passes.
/// Every method returns new data and never mutates its input. When a custom
/// pattern misbehaves the affected string is replaced entirely, so a failure
/// can only hide data, never expose it.
class MaskingEngine {
  /// Creates an engine from [config].
  ///
  /// Problems are reported through [onError]; they never throw.
  MaskingEngine(
    MaskConfig config, {
    void Function(Object error, StackTrace stack)? onError,
  }) : replacement = config.replacement,
       _onError = onError {
    if (config.useDefaultKeys) {
      _keys.addAll(defaultSensitiveKeys.map(_normalize));
    }
    _keys.addAll(config.extraKeys.map(_normalize));
    _headerDenylist
      ..addAll(defaultHeaderDenylist)
      ..addAll(config.extraHeaderDenylist.map(_normalize));
    if (config.useDefaultPatterns) _rules.addAll(buildDefaultRules());
    for (final pattern in config.extraPatterns) {
      if (!addPattern(pattern)) {
        _report(ArgumentError('Ignored an unusable mask pattern'));
      }
    }
  }

  /// Text that replaces masked values.
  final String replacement;

  final void Function(Object error, StackTrace stack)? _onError;
  final Set<String> _keys = <String>{};
  final Set<String> _headerDenylist = <String>{};
  final List<MaskRule> _rules = <MaskRule>[];

  /// Strings longer than this have their tail dropped instead of masked.
  static const int maxStringChars = 100000;

  /// Appended to a string whose tail was dropped.
  static const String tailMarker = '…[masked tail dropped]';

  static const int _maxDepth = 12;

  static String _normalize(String key) => key.trim().toLowerCase();

  /// Adds sensitive keys, matched exactly and case-insensitively.
  void addKeys(Iterable<String> keys) => _keys.addAll(keys.map(_normalize));

  /// Adds a pattern whose matches are replaced in every string.
  ///
  /// Returns false, and ignores the pattern, if it matches the empty string
  /// (which would corrupt every string) or cannot be tested safely.
  bool addPattern(RegExp pattern) {
    try {
      if (pattern.hasMatch('')) return false;
    } catch (_) {
      return false;
    }
    _rules.add(MaskRule(pattern, (m, replacement) => replacement));
    return true;
  }

  /// The sensitive keys currently in force, lower-cased: the defaults, the
  /// configured extras, and any added at runtime.
  Iterable<String> get sensitiveKeys => _keys;

  /// Whether the value stored under [key] must be masked.
  bool isSensitiveKey(String key) => _keys.contains(_normalize(key));

  /// Masks PII patterns in [input].
  String maskString(String input) {
    if (input.isEmpty) return input;

    var body = input;
    var dropped = false;
    if (body.endsWith(tailMarker)) {
      body = body.substring(0, body.length - tailMarker.length);
      dropped = true;
    }
    if (body.length > maxStringChars) {
      body = body.substring(0, maxStringChars);
      dropped = true;
    }

    var hasAt = false;
    var hasDigit = false;
    for (var i = 0; i < body.length; i++) {
      final unit = body.codeUnitAt(i);
      if (unit == 0x40) hasAt = true;
      if (unit >= 0x30 && unit <= 0x39) hasDigit = true;
    }

    for (final rule in _rules) {
      if (rule.needsAt && !hasAt) continue;
      if (rule.needsDigit && !hasDigit) continue;
      try {
        body = body.replaceAllMapped(
          rule.regex,
          (m) => rule.replace(m, replacement),
        );
      } catch (error, stack) {
        _report(error, stack);
        return replacement;
      }
    }
    return dropped ? '$body$tailMarker' : body;
  }

  /// Masks a JSON-like value: strings by pattern, maps by key then pattern,
  /// lists element by element. Other values are returned as they are.
  Object? maskValue(Object? value) => _value(value, 0, HashSet.identity());

  /// Masks a map: values under sensitive keys are replaced whole.
  Map<String, dynamic> maskMap(Map<dynamic, dynamic>? map) {
    if (map == null || map.isEmpty) return const <String, dynamic>{};
    return _map(map, 0, HashSet.identity());
  }

  /// Redacts headers: denylisted names have their values replaced.
  Map<String, dynamic> maskHeaders(Map<dynamic, dynamic>? headers) =>
      redactHeaders(
        headers,
        denylist: _headerDenylist,
        replacement: replacement,
        maskString: maskString,
      );

  /// Redacts a query string or a form-encoded body such as `a=1&token=x`.
  String maskQueryString(String query) => redactQueryString(
    query,
    isSensitiveKey: isSensitiveKey,
    maskString: maskString,
    replacement: replacement,
  );

  /// Redacts a URL: userinfo, sensitive query values, and PII elsewhere.
  String maskUrl(String url) => redactUrl(
    url,
    isSensitiveKey: isSensitiveKey,
    maskString: maskString,
    replacement: replacement,
  );

  /// Masks every free-text part of [record].
  ///
  /// `id`, `seq`, `ts`, `level`, `tag`, `sessionId`, `userId` and the SDK's own
  /// context keys are left alone. `ctx.userName` is always replaced.
  LogRecord maskRecord(LogRecord record) {
    final seen = HashSet<Object>.identity();
    final ctx = <String, dynamic>{};
    for (final entry in record.ctx.entries) {
      final key = entry.key;
      if (key == 'userName') {
        ctx[key] = entry.value == null ? null : replacement;
      } else if (coreContextKeys.contains(key)) {
        ctx[key] = entry.value;
      } else if (isSensitiveKey(key) && entry.value != null) {
        ctx[key] = replacement;
      } else {
        ctx[key] = _value(entry.value, 1, seen);
      }
    }
    final error = record.error;
    final stack = record.stackTrace;
    return record.copyWith(
      message: maskString(record.message),
      error: error == null ? null : maskString(error),
      stackTrace: stack == null ? null : maskString(stack),
      metadata: _map(record.metadata, 0, seen),
      ctx: ctx,
    );
  }

  Object? _value(Object? value, int depth, Set<Object> path) {
    if (value == null || value is bool || value is num) return value;
    if (value is String) return maskString(value);
    if (depth > _maxDepth) return replacement;
    if (value is Map) return _map(value, depth, path);
    if (value is Iterable) return _list(value, depth, path);
    try {
      return maskString(value.toString());
    } catch (_) {
      return replacement;
    }
  }

  Map<String, dynamic> _map(
    Map<dynamic, dynamic> map,
    int depth,
    Set<Object> path,
  ) {
    if (!path.add(map)) return const <String, dynamic>{'_': '[circular]'};
    final out = <String, dynamic>{};
    for (final entry in map.entries) {
      final key = entry.key.toString();
      final value = entry.value;
      if (value != null && isSensitiveKey(key)) {
        out[key] = replacement;
      } else {
        out[key] = _value(value, depth + 1, path);
      }
    }
    path.remove(map);
    return out;
  }

  List<dynamic> _list(Iterable<dynamic> items, int depth, Set<Object> path) {
    if (!path.add(items)) return const <dynamic>['[circular]'];
    final out = <dynamic>[
      for (final item in items) _value(item, depth + 1, path),
    ];
    path.remove(items);
    return out;
  }

  void _report(Object error, [StackTrace? stack]) {
    _onError?.call(error, stack ?? StackTrace.current);
  }
}
