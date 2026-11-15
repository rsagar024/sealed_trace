import 'dart:collection';

import '../config/mask_config.dart';
import '../event/event_builder.dart';
import '../event/log_record.dart';
import 'default_keys.dart';
import 'default_patterns.dart';
import 'credential_pass.dart';
import 'header_redactor.dart';
import 'pattern_safety.dart';
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
       _maskUserName = config.maskUserName,
       _useDefaultKeys = config.useDefaultKeys,
       _maskUrlPathSegments = config.maskUrlPathSegments,
       _usesDefaultPatterns = config.useDefaultPatterns,
       _onError = onError {
    _credentials = CredentialPass(
      isSensitive: isSensitiveHeader,
      replacement: replacement,
    );
    if (config.useDefaultKeys) {
      _keys.addAll(defaultSensitiveKeys.map(_normalize));
      _fragments.addAll(defaultSensitiveKeyFragments.map(_normalize));
    }
    _keys.addAll(config.extraKeys.map(_normalize));
    _headerDenylist
      ..addAll(defaultHeaderDenylist)
      ..addAll(config.extraHeaderDenylist.map(_headerName));
    if (config.useDefaultPatterns) _rules.addAll(buildDefaultRules());
    for (final pattern in config.extraPatterns) {
      final problem = patternProblem(pattern);
      if (problem != null) {
        _report(
          ArgumentError.value(
            pattern.pattern,
            'pattern',
            'Mask pattern ignored: $problem',
          ),
        );
      } else {
        _addRule(pattern);
      }
    }
  }

  /// Text that replaces masked values.
  final String replacement;

  final bool _maskUserName;
  final void Function(Object error, StackTrace stack)? _onError;
  final bool _useDefaultKeys;
  final bool _maskUrlPathSegments;
  final bool _usesDefaultPatterns;
  late final CredentialPass _credentials;
  final Set<String> _keys = <String>{};
  final List<String> _fragments = <String>[];
  final Set<String> _headerDenylist = <String>{};
  final List<MaskRule> _rules = <MaskRule>[];
  final List<RegExp> _extraPatterns = <RegExp>[];

  /// Everything this engine masks with, including keys and patterns added at
  /// runtime, as plain data that can be sent to another isolate.
  MaskingSnapshot snapshot() => MaskingSnapshot(
    replacement: replacement,
    maskUserName: _maskUserName,
    useDefaultKeys: _useDefaultKeys,
    useDefaultPatterns: _usesDefaultPatterns,
    maskUrlPathSegments: _maskUrlPathSegments,
    keys: _keys.toList(),
    headerDenylist: _headerDenylist.toList(),
    patterns: [
      for (final p in _extraPatterns)
        (p.pattern, p.isCaseSensitive, p.isMultiLine, p.isUnicode, p.isDotAll),
    ],
  );

  /// Rebuilds an engine from [snapshot], for example inside an isolate.
  factory MaskingEngine.fromSnapshot(MaskingSnapshot snapshot) => MaskingEngine(
    MaskConfig(
      replacement: snapshot.replacement,
      maskUserName: snapshot.maskUserName,
      useDefaultKeys: snapshot.useDefaultKeys,
      useDefaultPatterns: snapshot.useDefaultPatterns,
      maskUrlPathSegments: snapshot.maskUrlPathSegments,
      extraKeys: snapshot.keys,
      extraHeaderDenylist: snapshot.headerDenylist,
      extraPatterns: [
        for (final (source, caseSensitive, multiLine, unicode, dotAll)
            in snapshot.patterns)
          RegExp(
            source,
            caseSensitive: caseSensitive,
            multiLine: multiLine,
            unicode: unicode,
            dotAll: dotAll,
          ),
      ],
    ),
  );

  /// Strings longer than this have their tail dropped instead of masked.
  static const int maxStringChars = 100000;

  /// Appended to a string whose tail was dropped.
  static const String tailMarker = '…[masked tail dropped]';

  static const int _maxDepth = 12;

  static final RegExp _keySeparators = RegExp(r'[\s_.\-]');

  /// Lower-cases [key] and drops `_`, `-`, `.` and whitespace, so
  /// `access_token`, `accessToken` and `Access-Token` compare equal.
  static String _normalize(String key) =>
      key.toLowerCase().replaceAll(_keySeparators, '');

  static String _headerName(String name) => name.trim().toLowerCase();

  /// Adds sensitive keys, matched case-insensitively and ignoring `_`, `-`,
  /// `.` and whitespace.
  void addKeys(Iterable<String> keys) => _keys.addAll(keys.map(_normalize));

  /// Why [pattern] cannot be used as a mask pattern, or null when it can.
  ///
  /// A pattern is refused when it matches the empty string (which would
  /// corrupt every string), cannot be tested safely, or can backtrack
  /// exponentially: nested repetition such as `(a+)+`, repeated alternation
  /// such as `(a|b)*`, or a backreference. Custom patterns run synchronously
  /// on every logged string, so such a pattern could freeze the app (L13).
  static String? patternProblem(RegExp pattern) {
    final unsafe = unsafePatternReason(pattern.pattern);
    if (unsafe != null) return unsafe;
    try {
      if (pattern.hasMatch('')) return 'it matches the empty string';
    } catch (_) {
      return 'it could not be tested';
    }
    return null;
  }

  /// Adds a pattern whose matches are replaced in every string.
  ///
  /// Returns false, and ignores the pattern, when [patternProblem] finds a
  /// problem with it.
  bool addPattern(RegExp pattern) {
    if (patternProblem(pattern) != null) return false;
    _addRule(pattern);
    return true;
  }

  void _addRule(RegExp pattern) {
    _rules.add(MaskRule(pattern, (m, replacement) => replacement));
    _extraPatterns.add(pattern);
  }

  /// The exact sensitive keys currently in force, normalized: the defaults,
  /// the configured extras, and any added at runtime.
  Iterable<String> get sensitiveKeys => _keys;

  /// Whether the value stored under [key] must be masked.
  ///
  /// True when the normalized key is one of [sensitiveKeys] or, with the
  /// default keys on, contains a default fragment such as `token` or
  /// `secret`, or ends with `auth`.
  bool isSensitiveKey(String key) {
    final normalized = _normalize(key);
    if (normalized.isEmpty) return false;
    if (_keys.contains(normalized)) return true;
    if (!_useDefaultKeys) return false;
    if (normalized.endsWith('auth')) return true;
    for (final fragment in _fragments) {
      if (normalized.contains(fragment)) return true;
    }
    return false;
  }

  /// Whether a header, or a `name: value` line in a text body, called [name]
  /// must be masked: it is denylisted or a sensitive key.
  bool isSensitiveHeader(String name) =>
      _headerDenylist.contains(_headerName(name)) || isSensitiveKey(name);

  /// Masks PII patterns in [input], then credentials written as key-value
  /// text (`token=...`, `password: ...`, `"secret": ...`).
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
    try {
      body = _credentials.apply(body);
    } catch (error, stack) {
      _report(error, stack);
      return replacement;
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

  /// Redacts headers: denylisted names, and names that are sensitive keys
  /// (such as `X-Custom-Token`), have their values replaced.
  Map<String, dynamic> maskHeaders(Map<dynamic, dynamic>? headers) =>
      redactHeaders(
        headers,
        denylist: _headerDenylist,
        replacement: replacement,
        maskString: maskString,
        isSensitiveName: isSensitiveKey,
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
    maskPathSegments: _maskUrlPathSegments,
  );

  /// Masks every free-text part of [record].
  ///
  /// `id`, `seq`, `ts`, `level`, `tag`, `sessionId`, `userId` and the SDK's own
  /// context keys are left alone. `ctx.userName` is replaced when
  /// `MaskConfig.maskUserName` is true (the default) and sent as given
  /// otherwise. `ctx.userDisplayName`, set only by `SealedTrace.setUser` and
  /// only when `SealedTraceConfig.sendUserDisplayName` is true, is sent as
  /// given.
  LogRecord maskRecord(LogRecord record) {
    final seen = HashSet<Object>.identity();
    final ctx = <String, dynamic>{};
    for (final entry in record.ctx.entries) {
      final key = entry.key;
      if (key == 'userName') {
        ctx[key] = _maskUserName && entry.value != null
            ? replacement
            : entry.value;
      } else if (key == userDisplayNameKey || coreContextKeys.contains(key)) {
        ctx[key] = entry.value;
      } else if (isSensitiveKey(key) && entry.value != null) {
        _put(ctx, key, replacement);
      } else {
        _put(ctx, key, _value(entry.value, 1, seen));
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
        _put(out, key, replacement);
      } else {
        _put(out, key, _value(value, depth + 1, path));
      }
    }
    path.remove(map);
    return out;
  }

  /// Stores [value] under [key] with PII in the key itself masked, such as a
  /// map keyed by email. Keys that mask to the same text stay distinct.
  void _put(Map<String, dynamic> out, String key, Object? value) {
    final masked = maskString(key);
    if (masked == key) {
      out[key] = value;
      return;
    }
    var unique = masked;
    for (var n = 2; out.containsKey(unique); n++) {
      unique = '$masked#$n';
    }
    out[unique] = value;
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

/// A [MaskingEngine]'s rules as plain, sendable data. Patterns are kept as
/// their source and flags, and rebuilt on the other side.
class MaskingSnapshot {
  /// Creates a snapshot.
  const MaskingSnapshot({
    required this.replacement,
    required this.maskUserName,
    required this.useDefaultKeys,
    required this.useDefaultPatterns,
    required this.maskUrlPathSegments,
    required this.keys,
    required this.headerDenylist,
    required this.patterns,
  });

  /// Text that replaces masked values.
  final String replacement;

  /// Whether `ctx.userName` is masked.
  final bool maskUserName;

  /// Whether the default keys and fragments apply.
  final bool useDefaultKeys;

  /// Whether the default patterns apply.
  final bool useDefaultPatterns;

  /// Whether URL path segments are masked.
  final bool maskUrlPathSegments;

  /// Every exact sensitive key, normalized.
  final List<String> keys;

  /// Every denylisted header name, lower-cased.
  final List<String> headerDenylist;

  /// Extra patterns: source, caseSensitive, multiLine, unicode, dotAll.
  final List<(String, bool, bool, bool, bool)> patterns;
}
