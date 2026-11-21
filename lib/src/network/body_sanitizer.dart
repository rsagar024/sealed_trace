import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show compute, kIsWeb;

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

  /// Bodies larger than this are not processed at all. Bounds the parsing
  /// and masking work one hostile or huge response can cause.
  static const int maxCaptureChars = 256 * 1024;

  /// Structured bodies with more nodes than this are not processed.
  static const int maxCaptureNodes = 50000;

  /// Content types that are never text.
  static final RegExp _binaryType = RegExp(
    r'^(image|audio|video|font)/|^application/(octet-stream|pdf|zip|gzip|'
    r'x-gzip|x-tar|x-7z-compressed|x-protobuf|protobuf|vnd\.ms-|'
    r'vnd\.openxmlformats|msword|wasm)',
  );

  /// Text bodies at least this long are sanitized off the UI isolate.
  static const int offloadChars = 32 * 1024;

  /// Structured bodies with more nodes than this are sanitized off the UI
  /// isolate.
  static const int offloadNodes = 2000;

  /// Sanitizes the body of [options].
  String? sanitizeRequest(RequestOptions options) =>
      sanitize(options.data, contentType: _requestType(options));

  /// Sanitizes the body of [response].
  String? sanitizeResponse(Response<dynamic> response) => sanitize(
    response.data,
    contentType: response.headers.value(Headers.contentTypeHeader),
    declaredLength: _declaredLength(response),
  );

  /// Like [sanitizeRequest], but see [sanitizeOffloaded].
  FutureOr<String?> sanitizeRequestOffloaded(RequestOptions options) =>
      sanitizeOffloaded(options.data, contentType: _requestType(options));

  /// Like [sanitizeResponse], but see [sanitizeOffloaded].
  FutureOr<String?> sanitizeResponseOffloaded(Response<dynamic> response) =>
      sanitizeOffloaded(
        response.data,
        contentType: response.headers.value(Headers.contentTypeHeader),
        declaredLength: _declaredLength(response),
      );

  /// Like [sanitize], but a large body (at least [offloadChars] of text, or
  /// more than [offloadNodes] structured nodes) is parsed and masked in a
  /// background isolate on native platforms, so a hostile or huge response
  /// cannot stall the UI. Small bodies, and every body on the web, are
  /// sanitized synchronously and returned as a plain value.
  ///
  /// The isolate uses a snapshot of the engine, so keys and patterns added at
  /// runtime apply. If the body cannot be sent to an isolate, it is
  /// sanitized here instead. Never throws.
  FutureOr<String?> sanitizeOffloaded(
    Object? data, {
    String? contentType,
    int? declaredLength,
  }) {
    if (kIsWeb || !_worthOffloading(data, declaredLength)) {
      return sanitize(
        data,
        contentType: contentType,
        declaredLength: declaredLength,
      );
    }
    final job = SanitizeJob(
      engine.snapshot(),
      maxBodyChars,
      data,
      contentType,
      declaredLength,
    );
    return compute(sanitizeInIsolate, job).then<String?>(
      (value) => value,
      onError: (Object _) => sanitize(
        data,
        contentType: contentType,
        declaredLength: declaredLength,
      ),
    );
  }

  bool _worthOffloading(Object? data, int? declaredLength) {
    try {
      if (data == null) return false;
      if (declaredLength != null && declaredLength > maxCaptureChars) {
        return false; // Becomes a placeholder at no cost.
      }
      if (data is String) {
        return data.length >= offloadChars && data.length <= maxCaptureChars;
      }
      if (data is Uint8List || data is List<int>) return false;
      if (data is Map || data is Iterable) return _exceeds(data, offloadNodes);
      return false;
    } catch (_) {
      return false;
    }
  }

  static String? _requestType(RequestOptions options) =>
      options.contentType ??
      _headerValue(options.headers, Headers.contentTypeHeader);

  static int? _declaredLength(Response<dynamic> response) =>
      int.tryParse(response.headers.value(Headers.contentLengthHeader) ?? '');

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
    return _truncate(_schemePass(engine.maskString(text)));
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

  static final RegExp _scheme = RegExp(
    r'\b(Bearer|Basic|Digest|Negotiate|NTLM)(\s+)[A-Za-z0-9._~+/=\-]{6,2000}',
    caseSensitive: false,
  );

  /// Masks scheme tokens such as `Basic abc` in text bodies. Key-value pairs
  /// (`token=...`, `"password": ...`, `<idToken>...`) are already masked by
  /// `MaskingEngine.maskString`, which applies them to every string. `Basic`
  /// and the other schemes are matched here only, not in log messages, where
  /// "Basic setup" is ordinary text.
  String _schemePass(String text) => text.replaceAllMapped(
    _scheme,
    (m) => '${m[1]}${m[2]}${engine.replacement}',
  );
}

/// One body to sanitize in a background isolate. Plain, sendable data.
class SanitizeJob {
  /// Creates a job.
  const SanitizeJob(
    this.snapshot,
    this.maxBodyChars,
    this.data,
    this.contentType,
    this.declaredLength,
  );

  /// The masking rules to apply.
  final MaskingSnapshot snapshot;

  /// Characters kept per body.
  final int maxBodyChars;

  /// The body: a string, or a JSON-like map or list.
  final Object? data;

  /// The body's content type, lower-cased or null.
  final String? contentType;

  /// The declared `Content-Length`, if any.
  final int? declaredLength;
}

/// Sanitizes [job] with an engine rebuilt from its snapshot. A top-level
/// function so it can run in a background isolate.
String? sanitizeInIsolate(SanitizeJob job) =>
    BodySanitizer(
      MaskingEngine.fromSnapshot(job.snapshot),
      maxBodyChars: job.maxBodyChars,
    ).sanitize(
      job.data,
      contentType: job.contentType,
      declaredLength: job.declaredLength,
    );
