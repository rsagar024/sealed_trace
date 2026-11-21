import 'dart:convert';

import 'event_builder.dart' show coreContextKeys, userDisplayNameKey;

/// Bounds on the context `SealedTrace.setContext` builds up across calls.
///
/// Every event carries a copy of the whole context, so without a limit a
/// long-running app that keeps adding keys makes every event, and every
/// envelope, grow without end.
abstract final class ContextLimits {
  /// Most keys kept in the merged context.
  static const int maxEntries = 100;

  /// Largest merged context, as compact JSON characters.
  static const int maxChars = 16 * 1024;

  /// Keys only the SDK sets: the device context, and the user name keys that
  /// only `setUser` may set. A value for them from `setContext` is ignored.
  static const Set<String> reservedKeys = <String>{
    ...coreContextKeys,
    'userName',
    userDisplayNameKey,
  };

  /// Merges [incoming] (already normalized) into [context] in place.
  ///
  /// Reserved keys are skipped. A new key, or a new value for an existing
  /// key, that would take the context past [maxEntries] or [maxChars] is
  /// dropped and the existing value kept. Returns how many entries were
  /// dropped for the limits (reserved keys are not counted).
  static int merge(
    Map<String, dynamic> context,
    Map<String, dynamic> incoming,
  ) {
    final sizes = <String, int>{
      for (final entry in context.entries)
        entry.key: _size(entry.key, entry.value),
    };
    var total = sizes.values.fold<int>(0, (sum, n) => sum + n);
    var dropped = 0;
    for (final entry in incoming.entries) {
      final key = entry.key;
      if (reservedKeys.contains(key)) continue;
      final size = _size(key, entry.value);
      final isNew = !context.containsKey(key);
      final nextTotal = total - (sizes[key] ?? 0) + size;
      if ((isNew && context.length >= maxEntries) || nextTotal > maxChars) {
        dropped++;
        continue;
      }
      context[key] = entry.value;
      sizes[key] = size;
      total = nextTotal;
    }
    return dropped;
  }

  /// The JSON characters one entry adds, separator included.
  static int _size(String key, Object? value) {
    try {
      return jsonEncode(<String, Object?>{key: value}).length - 1;
    } catch (_) {
      return maxChars + 1; // Unencodable: never fits.
    }
  }
}
