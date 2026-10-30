/// Redacts header values whose names are in [denylist] (lower-cased).
///
/// Names are kept. A denied value is replaced by [replacement], keeping the
/// list shape when the value is a list. Other values go through [maskString].
Map<String, dynamic> redactHeaders(
  Map<dynamic, dynamic>? headers, {
  required Set<String> denylist,
  required String replacement,
  required String Function(String value) maskString,
}) {
  if (headers == null || headers.isEmpty) return const <String, dynamic>{};
  final out = <String, dynamic>{};
  for (final entry in headers.entries) {
    final name = entry.key.toString();
    final value = entry.value;
    if (denylist.contains(name.toLowerCase())) {
      out[name] = value is Iterable ? <String>[replacement] : replacement;
    } else if (value is Iterable) {
      out[name] = <String>[for (final item in value) maskString('$item')];
    } else if (value == null) {
      out[name] = null;
    } else {
      out[name] = maskString('$value');
    }
  }
  return out;
}
