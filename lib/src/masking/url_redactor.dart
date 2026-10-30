/// Redacts a URL: userinfo, sensitive query values, and PII in the path,
/// other query values and the fragment.
///
/// Repeated query parameters are preserved, and values that need no change
/// keep their original percent-encoding. An unparsable URL is masked as a
/// plain string.
String redactUrl(
  String url, {
  required bool Function(String key) isSensitiveKey,
  required String Function(String value) maskString,
  required String replacement,
}) {
  final uri = Uri.tryParse(url);
  if (uri == null) return maskString(url);

  final out = StringBuffer();
  if (uri.hasScheme) out.write('${uri.scheme}:');
  if (uri.hasAuthority) {
    out.write('//');
    if (uri.userInfo.isNotEmpty) out.write('$replacement@');
    out.write(uri.host.contains(':') ? '[${uri.host}]' : uri.host);
    if (uri.hasPort) out.write(':${uri.port}');
  }
  out.write(maskString(uri.path));
  if (uri.hasQuery) {
    out
      ..write('?')
      ..write(_redactQuery(uri.query, isSensitiveKey, maskString, replacement));
  }
  if (uri.hasFragment) out.write('#${maskString(uri.fragment)}');
  return out.toString();
}

/// Redacts a query string (or a form-encoded body) such as `a=1&token=x`.
///
/// Values of sensitive keys are replaced, other values are decoded, masked and
/// re-encoded only when they changed, and repeated keys are preserved.
String redactQueryString(
  String query, {
  required bool Function(String key) isSensitiveKey,
  required String Function(String value) maskString,
  required String replacement,
}) => _redactQuery(query, isSensitiveKey, maskString, replacement);

String _redactQuery(
  String query,
  bool Function(String key) isSensitiveKey,
  String Function(String value) maskString,
  String replacement,
) {
  final encodedReplacement = Uri.encodeQueryComponent(replacement);
  final parts = <String>[];
  for (final part in query.split('&')) {
    if (part.isEmpty) {
      parts.add(part);
      continue;
    }
    final eq = part.indexOf('=');
    final rawKey = eq < 0 ? part : part.substring(0, eq);
    if (eq < 0) {
      parts.add(
        isSensitiveKey(_decode(rawKey)) ? '$rawKey=$replacement' : part,
      );
      continue;
    }
    if (isSensitiveKey(_decode(rawKey))) {
      parts.add('$rawKey=$replacement');
      continue;
    }
    final rawValue = part.substring(eq + 1);
    final decoded = _decode(rawValue);
    final masked = maskString(decoded);
    if (masked == decoded) {
      parts.add(part);
    } else {
      final encoded = Uri.encodeQueryComponent(
        masked,
      ).replaceAll(encodedReplacement, replacement);
      parts.add('$rawKey=$encoded');
    }
  }
  return parts.join('&');
}

String _decode(String value) {
  try {
    return Uri.decodeQueryComponent(value);
  } catch (_) {
    return value;
  }
}
