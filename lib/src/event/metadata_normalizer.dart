import 'dart:collection';

/// Converts arbitrary caller data into JSON-safe values with bounded size.
///
/// Maps and lists are copied. Depth is capped at [maxDepth] and the whole
/// walk at [maxEntries] entries. Cycles are replaced with a marker, and values
/// that are not JSON types are converted with `toString()`.
abstract final class MetadataNormalizer {
  /// Deepest nesting kept; deeper containers become `[max depth]`.
  static const int maxDepth = 6;

  /// Total map entries and list items kept across the whole walk.
  static const int maxEntries = 100;

  /// Returns a JSON-safe copy of [meta]. Never throws.
  static Map<String, dynamic> normalize(Map<dynamic, dynamic>? meta) {
    if (meta == null || meta.isEmpty) return const <String, dynamic>{};
    try {
      return _map(meta, 1, _Walk());
    } catch (_) {
      return const <String, dynamic>{'_error': '[unreadable]'};
    }
  }

  static Map<String, dynamic> _map(
    Map<dynamic, dynamic> source,
    int depth,
    _Walk walk,
  ) {
    final out = <String, dynamic>{};
    walk.path.add(source);
    for (final entry in source.entries) {
      if (walk.remaining <= 0) break;
      walk.remaining--;
      out[_text(entry.key)] = _value(entry.value, depth + 1, walk);
    }
    walk.path.remove(source);
    return out;
  }

  static List<dynamic> _list(Iterable<dynamic> source, int depth, _Walk walk) {
    final out = <dynamic>[];
    walk.path.add(source);
    for (final item in source) {
      if (walk.remaining <= 0) break;
      walk.remaining--;
      out.add(_value(item, depth + 1, walk));
    }
    walk.path.remove(source);
    return out;
  }

  static dynamic _value(Object? value, int depth, _Walk walk) {
    if (value == null || value is bool || value is String) return value;
    if (value is num) return value.isFinite ? value : value.toString();
    if (value is DateTime) return value.toUtc().toIso8601String();
    try {
      if (value is Map) {
        if (depth > maxDepth) return '[max depth]';
        if (walk.path.contains(value)) return '[circular]';
        return _map(value, depth, walk);
      }
      if (value is Iterable) {
        if (depth > maxDepth) return '[max depth]';
        if (walk.path.contains(value)) return '[circular]';
        return _list(value, depth, walk);
      }
    } catch (_) {
      return '[unreadable]';
    }
    return _text(value);
  }

  static String _text(Object? value) {
    if (value is String) return value;
    try {
      return value.toString();
    } catch (_) {
      return '[unprintable]';
    }
  }
}

class _Walk {
  int remaining = MetadataNormalizer.maxEntries;
  final Set<Object> path = HashSet<Object>.identity();
}
