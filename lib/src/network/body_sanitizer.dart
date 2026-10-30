import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../masking/masking_engine.dart';

/// Turns a request or response body into a safe, bounded string for a log
/// event.
///
/// Everything is masked before it is truncated, so a secret can never be cut
/// in half and slip through. The method never throws: anything it cannot
/// handle becomes a placeholder. The body it is given is never modified.
class BodySanitizer {
  /// Creates a sanitizer that masks with [engine] and keeps at most
  /// [maxBodyChars] characters of a body.
  BodySanitizer(this.engine, {required this.maxBodyChars});

  /// The masking engine.
  final MaskingEngine engine;

  /// Characters kept per body, before the truncation marker.
  final int maxBodyChars;

  /// Bodies larger than this are not processed at all.
  static const int maxCaptureChars = 1000000;

  /// Structured bodies with more nodes than this are not processed.
  static const int maxCaptureNodes = 200000;

  /// Content types that are never text.
  static final RegExp _binaryType = RegExp(
    r'^(image|audio|video|font)/|^application/(octet-stream|pdf|zip|gzip|'
    r'x-gzip|x-tar|x-7z-compressed|x-protobuf|protobuf|vnd\.ms-|'
    r'vnd\.openxmlformats|msword|wasm)',
  );

  /// Sanitizes the body of [options].
  String? sanitizeRequest(RequestOptions options) => sanitize(
    options.data,
    contentType:
        options.contentType ??
        _headerValue(options.headers, Headers.contentTypeHeader),
  );

  /// Sanitizes the body of [response].
  String? sanitizeResponse(Response<dynamic> response) => sanitize(
    response.data,
    contentType: response.headers.value(Headers.contentTypeHeader),
    declaredLength: int.tryParse(
      response.headers.value(Headers.contentLengthHeader) ?? '',
    ),
  );

  /// Sanitizes [data], or returns null when there is no body.
  String? sanitize(Object? data, {String? contentType, int? declaredLength}) {
    if (data == null) return null;
    try {
      return _sanitize(data, contentType?.toLowerCase(), declaredLength);
    } catch (_) {
      return '[non-text body]';
    }
  }

  String _sanitize(Object data, String? contentType, int? declaredLength) {
    if (data is FormData) return '[multipart form-data]';
    if (data is ResponseBody || data is Stream) return '[stream]';
    if (data is Uint8List) return '[binary ${data.length} bytes]';
    if (data is List<int>) return '[binary ${data.length} bytes]';

    if (contentType != null) {
      if (contentType.startsWith('multipart/')) return '[multipart form-data]';
      if (_binaryType.hasMatch(contentType)) {
        final size = declaredLength ?? (data is String ? data.length : null);
        return size == null ? '[binary body]' : '[binary $size bytes]';
      }
    }

    if (declaredLength != null && declaredLength > maxCaptureChars) {
      return '[body too large: $declaredLength chars]';
    }

    if (data is String) return _sanitizeText(data, contentType);
    if (data is Map || data is Iterable) return _sanitizeStructure(data);
    if (data is num || data is bool) {
      return _truncate(engine.maskString('$data'));
    }
    return '[non-text body]';
  }

  String _sanitizeText(String text, String? contentType) {
    if (text.length > maxCaptureChars) {
      return '[body too large: ${text.length} chars]';
    }
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      try {
        return _sanitizeStructure(jsonDecode(text) as Object);
      } on FormatException {
        // Not valid JSON: fall through to the text rules.
      } on TypeError {
        // A JSON scalar: fall through.
      }
    }
    if (contentType != null && contentType.contains('x-www-form-urlencoded')) {
      return _truncate(engine.maskQueryString(text));
    }
    return _truncate(_credentialPass(engine.maskString(text)));
  }

  String _sanitizeStructure(Object data) {
    if (_exceeds(data, maxCaptureNodes)) {
      return '[body too large: more than $maxCaptureNodes elements]';
    }
    final masked = engine.maskValue(data);
    final encoded = jsonEncode(masked);
    if (encoded.length > maxCaptureChars) {
      return '[body too large: ${encoded.length} chars]';
    }
    return _truncate(encoded);
  }

  /// Whether [data] holds more than [limit] nodes, stopping as soon as it does.
  static bool _exceeds(Object? data, int limit) {
    var count = 0;
    final stack = <Object?>[data];
    while (stack.isNotEmpty) {
      final item = stack.removeLast();
      if (++count > limit) return true;
      if (item is Map) {
        stack.addAll(item.keys);
        stack.addAll(item.values);
      } else if (item is Iterable) {
        stack.addAll(item);
      }
      if (stack.length > limit) return true;
    }
    return false;
  }

  /// Keeps the first [maxBodyChars] characters, never splitting a surrogate
  /// pair, and says how much was cut.
  String _truncate(String text) {
    if (text.length <= maxBodyChars) return text;
    var cut = maxBodyChars < 0 ? 0 : maxBodyChars;
    if (cut > 0 && _isHighSurrogate(text.codeUnitAt(cut - 1))) cut--;
    return '${text.substring(0, cut)}…[truncated ${text.length - cut} chars]';
  }

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static String? _headerValue(Map<String, dynamic> headers, String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name) return '${entry.value}';
    }
    return null;
  }

  // ---- credentials in free text ----

  /// Header names that can show up as `name: value` inside text bodies, in
  /// addition to the engine's sensitive keys.
  static const List<String> _extraTextKeys = <String>[
    'authorization',
    'proxy-authorization',
    'cookie',
    'set-cookie',
    'x-api-key',
  ];

  static const Set<String> _schemeWords = <String>{
    'bearer',
    'basic',
    'digest',
    'negotiate',
    'ntlm',
  };

  static final RegExp _scheme = RegExp(
    r'\b(Bearer|Basic|Digest|Negotiate|NTLM)(\s+)[A-Za-z0-9._~+/=\-]{6,2000}',
    caseSensitive: false,
  );

  // A cookie line holds several pairs, so everything after the colon goes.
  static final RegExp _cookieLine = RegExp(
    r'(\b(?:cookie|set-cookie)\s*:\s*)[^\r\n]{1,2000}',
    caseSensitive: false,
  );

  static String _keysCache = '';
  static RegExp? _jsonPair;
  static RegExp? _xmlPair;
  static RegExp? _plainPair;

  /// Masks credentials that the pattern pass cannot see: scheme tokens such as
  /// `Bearer abc`, and `key=value`, `key: value`, `"key": "value"` and
  /// `<key>value</key>` forms for every sensitive key.
  String _credentialPass(String text) {
    var out = text.replaceAllMapped(_scheme, (m) => '${m[1]}${m[2]}***');
    out = out.replaceAllMapped(_cookieLine, (m) => '${m[1]}***');

    final keys = <String>{...engine.sensitiveKeys, ..._extraTextKeys}.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    if (keys.isEmpty) return out;
    final signature = keys.join('|');
    if (signature != _keysCache) {
      final alternation = keys.map(RegExp.escape).join('|');
      _jsonPair = RegExp(
        '("(?:$alternation)"\\s*:\\s*)'
        r'("(?:[^"\\]|\\.){0,2000}"|[^\s,}\]]{1,500})',
        caseSensitive: false,
      );
      _xmlPair = RegExp(
        '(<(?:$alternation)(?:\\s[^>]{0,200})?>)([^<]{0,2000})'
        '(</(?:$alternation)>)',
        caseSensitive: false,
      );
      _plainPair = RegExp(
        '(\\b(?:$alternation)["\']?\\s{0,5}[=:]\\s{0,5}["\']?)'
        '([^\\s&,;"\'<>{}\\[\\]]{1,500})',
        caseSensitive: false,
      );
      _keysCache = signature;
    }
    out = out.replaceAllMapped(
      _jsonPair!,
      (m) => '${m[1]}"${engine.replacement}"',
    );
    out = out.replaceAllMapped(
      _xmlPair!,
      (m) => '${m[1]}${engine.replacement}${m[3]}',
    );
    out = out.replaceAllMapped(_plainPair!, (m) {
      // "Authorization: Bearer ***": keep the scheme word, the scheme pass
      // already masked the token after it.
      if (_schemeWords.contains(m[2]!.toLowerCase())) return m[0]!;
      return '${m[1]}${engine.replacement}';
    });
    return out;
  }
}
