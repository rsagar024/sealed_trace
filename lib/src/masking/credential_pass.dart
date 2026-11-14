/// Masks credentials written as key-value text, wherever they appear: log
/// messages, errors, stack traces, metadata strings and network bodies.
///
/// Handles `key=value`, `key: value`, `"key": value`, `<key>value</key>` and
/// `Cookie:` / `Set-Cookie:` lines. Whether a key is sensitive is decided by
/// [isSensitive], so text follows exactly the same key rules as maps. Every
/// quantifier is bounded, so matching time is linear in the input.
class CredentialPass {
  /// Creates a pass that masks values under keys for which [isSensitive] is
  /// true, replacing them with [replacement].
  CredentialPass({required this.isSensitive, required this.replacement});

  /// Whether a key (or header name) holds a credential or personal data.
  final bool Function(String key) isSensitive;

  /// Text that replaces a masked value.
  final String replacement;

  /// Words kept after `Authorization:` so `Bearer ***` stays readable.
  static const Set<String> schemeWords = <String>{
    'bearer',
    'basic',
    'digest',
    'negotiate',
    'ntlm',
  };

  // A cookie line holds several pairs, so everything after the colon goes.
  static final RegExp _cookieLine = RegExp(
    r'(\b(?:cookie|set-cookie)\s*:\s*)[^\r\n]{1,2000}',
    caseSensitive: false,
  );

  // "key": value
  static final RegExp _jsonPair = RegExp(
    r'("([^"\\\r\n]{1,64})"\s*:\s*)("(?:[^"\\]|\\.){0,2000}"|[^\s,}\]]{1,500})',
  );

  // <key attr>value</key>
  static final RegExp _xmlPair = RegExp(
    r'(<([A-Za-z_][A-Za-z0-9_.:\-]{0,63})(?:\s[^>]{0,200})?>)([^<]{0,2000})'
    r'(</\2>)',
    caseSensitive: false,
  );

  // key=value, key: value, key = "value"
  static final RegExp _plainPair = RegExp(
    r'''(\b([A-Za-z_][A-Za-z0-9_.\-]{0,63})["']?\s{0,5}[=:]\s{0,5}["']?)'''
    r'''([^\s&,;"'<>{}\[\]]{1,500})''',
  );

  /// Returns [text] with every sensitive key-value pair masked.
  String apply(String text) {
    if (!_mayHavePair(text)) return text;
    var out = text.replaceAllMapped(_cookieLine, (m) => '${m[1]}$replacement');
    out = out.replaceAllMapped(_jsonPair, (m) {
      if (!isSensitive(m[2]!)) return m[0]!;
      return '${m[1]}"$replacement"';
    });
    out = out.replaceAllMapped(_xmlPair, (m) {
      if (!isSensitive(m[2]!)) return m[0]!;
      return '${m[1]}$replacement${m[4]}';
    });
    return _plain(out);
  }

  String _plain(String text) => text.replaceAllMapped(_plainPair, (m) {
    final value = m[3]!;
    // A harmless key must not hide a pair in its value: `note:password=x`.
    if (!isSensitive(m[2]!)) return '${m[1]}${_plain(value)}';
    // "Authorization: Bearer ***": keep the scheme word; the token after it
    // is masked by the Bearer pattern or the network scheme pass.
    if (schemeWords.contains(value.toLowerCase())) return m[0]!;
    return '${m[1]}$replacement';
  });

  /// A pair needs `=`, `:` or `<`; most strings have none and skip the work.
  static bool _mayHavePair(String text) {
    for (var i = 0; i < text.length; i++) {
      final unit = text.codeUnitAt(i);
      if (unit == 0x3D || unit == 0x3A || unit == 0x3C) return true;
    }
    return false;
  }
}
