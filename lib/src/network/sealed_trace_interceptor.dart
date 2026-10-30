import 'dart:async';

import 'package:dio/dio.dart';

import '../config/network_log_config.dart';
import '../facade/sealed_trace.dart';
import '../masking/masking_engine.dart';
import '../model/log_event.dart';
import 'body_sanitizer.dart';
import 'host_filter.dart';
import 'level_mapper.dart';

/// A Dio interceptor that logs every request as a `network` event.
///
/// Add it to one or more `Dio` instances:
///
/// ```dart
/// dio.interceptors.add(SealedTraceInterceptor());
/// ```
///
/// Each event carries the method, URL, status, duration, headers and bodies,
/// all masked before they are sealed (see `MaskConfig`) and bodies truncated
/// to `NetworkLogConfig.maxBodyChars`. The SDK's own uploads are never logged.
///
/// The interceptor never changes, delays or fails a request: it passes every
/// call on first and does its logging afterwards, swallowing any error. It
/// does nothing until `SealedTrace.init` has succeeded, so it is safe to
/// create it before then.
class SealedTraceInterceptor extends Interceptor {
  /// Creates the interceptor.
  ///
  /// With no [config] it follows `SealedTraceConfig.networkLogConfig`. An
  /// explicit [config] replaces that for this interceptor.
  SealedTraceInterceptor({NetworkLogConfig? config}) : _config = config;

  final NetworkLogConfig? _config;

  static const String _startKey = 'sealed_trace.network.start';
  static const int _maxHeaders = 25;

  /// Stamps the start time when the call will be logged, then passes the
  /// request on unchanged.
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    try {
      if (_active() != null) options.extra[_startKey] = Stopwatch()..start();
    } catch (_) {
      // Never let logging interfere with the request.
    }
    handler.next(options);
  }

  /// Passes the response on unchanged, then logs the call (masked) in a
  /// microtask.
  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    final job = _finish(response.requestOptions, response, null);
    handler.next(response);
    _schedule(job);
  }

  /// Passes the error on unchanged, then logs the failed call (masked) in a
  /// microtask.
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final job = _finish(err.requestOptions, err.response, err);
    handler.next(err);
    _schedule(job);
  }

  // ---- internals ----

  /// The settings in force, or null when nothing may be logged: the SDK is not
  /// initialized, is disabled, has no masking engine, or the network log is
  /// off.
  _Active? _active() {
    final runtime = SealedTrace.internalRuntime;
    if (runtime == null || !runtime.enabled) return null;
    final engine = runtime.pipeline?.masking;
    if (engine == null) return null;
    final config = _config ?? runtime.config.networkLogConfig;
    if (!config.enabled) return null;
    return _Active(engine, config);
  }

  /// Captures what must be measured now: the elapsed time, and the pieces of
  /// the call. Removes the start marker from the request options.
  _Job? _finish(
    RequestOptions options,
    Response<dynamic>? response,
    DioException? error,
  ) {
    try {
      final stamp = options.extra.remove(_startKey);
      if (stamp is! Stopwatch) return null;
      stamp.stop();
      return _Job(options, response, error, stamp.elapsedMilliseconds);
    } catch (_) {
      return null;
    }
  }

  void _schedule(_Job? job) {
    if (job == null) return;
    scheduleMicrotask(() {
      try {
        _log(job);
      } catch (error, stack) {
        try {
          SealedTrace.reportInternal(error, stack);
        } catch (_) {
          // Nothing more can be done.
        }
      }
    });
  }

  void _log(_Job job) {
    final active = _active();
    if (active == null) return;
    final runtime = SealedTrace.internalRuntime!;
    final engine = active.engine;
    final config = active.config;

    final options = job.options;
    final uri = options.uri;
    if (!HostFilter.allows(uri, config.hostAllowlist)) return;
    if (HostFilter.isIngestRequest(uri, runtime.config.baseUrl)) return;

    final status = job.response?.statusCode;
    final cancelled = job.error?.type == DioExceptionType.cancel;
    final level = levelForNetwork(status: status, cancelled: cancelled);
    if (level.index < runtime.minLevelIndex) {
      runtime.counters.eventsDroppedLevel++;
      return;
    }

    final sanitizer = BodySanitizer(engine, maxBodyChars: config.maxBodyChars);
    final path = uri.path.isEmpty ? '/' : uri.path;
    final message =
        '${options.method} ${engine.maskString(path)} '
        '-> ${status ?? 'ERR'} in ${job.durationMs}ms';

    final metadata = <String, dynamic>{
      'method': options.method,
      'url': engine.maskUrl(uri.toString()),
      'status': status,
      'durationMs': job.durationMs,
      'requestHeaders': _headers(engine, options.headers),
      'responseHeaders': job.response == null
          ? null
          : _headers(engine, job.response!.headers.map),
      'requestBody': config.captureRequestBody
          ? sanitizer.sanitizeRequest(options)
          : null,
      'responseBody': config.captureResponseBody && job.response != null
          ? sanitizer.sanitizeResponse(job.response!)
          : null,
      'error': job.error == null ? null : _describe(engine, job.error!),
    };

    SealedTrace.log(
      LogEvent(
        level: level,
        tag: 'network',
        message: message,
        metadata: metadata,
      ),
    );
  }

  /// Headers as `name: value` strings with list values joined, through the
  /// denylist redactor. At most [_maxHeaders] are kept so the event metadata
  /// never exceeds the normalizer's entry budget and loses later fields.
  Map<String, dynamic> _headers(
    MaskingEngine engine,
    Map<dynamic, dynamic> raw,
  ) {
    final kept = <String, String>{};
    var skipped = 0;
    for (final entry in raw.entries) {
      if (kept.length >= _maxHeaders) {
        skipped++;
        continue;
      }
      final value = entry.value;
      kept['${entry.key}'] = value is Iterable
          ? value.map((item) => '$item').join(', ')
          : '$value';
    }
    final masked = engine.maskHeaders(kept);
    if (skipped > 0) masked['_truncated'] = '$skipped more headers';
    return masked;
  }

  /// A short description of a failed call: the category, never the exception
  /// message or request, which can carry headers.
  String _describe(MaskingEngine engine, DioException error) {
    final inner = error.error;
    final detail = inner == null ? '' : ': ${inner.runtimeType}';
    return engine.maskString('${error.type.name}$detail');
  }
}

class _Active {
  const _Active(this.engine, this.config);

  final MaskingEngine engine;
  final NetworkLogConfig config;
}

class _Job {
  const _Job(this.options, this.response, this.error, this.durationMs);

  final RequestOptions options;
  final Response<dynamic>? response;
  final DioException? error;
  final int durationMs;
}
