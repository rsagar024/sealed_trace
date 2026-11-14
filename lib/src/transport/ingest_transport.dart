import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../config/upload_config.dart' show AttestationTokenProvider;
import '../model/sealed_envelope.dart';
import '../platform/clock.dart';
import 'ingest_response.dart';
import 'pinned_adapter.dart';
import 'retry_after.dart';
import 'spki_pin.dart';

/// Sends sealed envelopes to the server.
abstract interface class IngestClient {
  /// Posts [envelopes] in one request. Never throws.
  Future<IngestOutcome> send(List<SealedEnvelope> envelopes);

  /// Aborts a request in progress, if any. It then completes as
  /// [IngestCancelled].
  void cancelInFlight();
}

/// The Dio-backed [IngestClient] for `POST {baseUrl}/api/v1/ingest/logs`.
///
/// It owns its own [Dio] with no interceptors, so the SDK's uploads can never
/// be logged by the SDK. Failures are reduced to small outcomes; the exception
/// is never passed on, because it carries the request headers (the API key).
class IngestTransport implements IngestClient {
  /// Creates a transport. [adapter] is for tests.
  IngestTransport({
    required String baseUrl,
    required String apiKey,
    this.timeout = const Duration(seconds: 30),
    HttpClientAdapter? adapter,
    this.clock = const SystemClock(),
    AttestationTokenProvider? attestationTokenProvider,
    List<String> pinnedSpkiSha256 = const [],
  }) : uri = ingestUri(baseUrl),
       _apiKey = apiKey,
       _attestation = attestationTokenProvider,
       _dio = Dio(
         BaseOptions(
           connectTimeout: timeout,
           sendTimeout: timeout,
           receiveTimeout: timeout,
           // Read as a stream so the body can be capped (maxResponseBytes).
           responseType: ResponseType.stream,
           validateStatus: (_) => true,
           // A redirect could carry the API key and envelopes elsewhere, and
           // its target's 202 would be trusted. Never follow one.
           followRedirects: false,
           maxRedirects: 0,
         ),
       ) {
    if (adapter != null) {
      _dio.httpClientAdapter = adapter;
    } else if (pinnedSpkiSha256.isNotEmpty) {
      final pinned = createPinnedAdapter(
        pinnedSpkiSha256.map(SpkiPin.normalize).toSet(),
      );
      if (pinned != null) _dio.httpClientAdapter = pinned;
    }
  }

  /// Longest response body read. Real ingest answers are a few kilobytes;
  /// anything longer is not read further and the request counts as failed.
  static const int maxResponseBytes = 256 * 1024;

  /// The full ingest URL.
  final Uri uri;

  /// Limit for one request, in total.
  final Duration timeout;

  /// Source of "now" for dated `Retry-After` headers.
  final Clock clock;

  final String _apiKey;
  final AttestationTokenProvider? _attestation;
  final Dio _dio;

  /// Header carrying the token from `UploadConfig.attestationTokenProvider`.
  static const String attestationHeader = 'X-SealedTrace-Attestation';

  static final RegExp _lineBreak = RegExp(r'[\r\n]');
  CancelToken? _inFlight;

  /// The client's Dio, exposed so tests can check it has no interceptors.
  Dio get dio => _dio;

  /// `{baseUrl}/api/v1/ingest/logs`, tolerating trailing slashes on [baseUrl].
  static Uri ingestUri(String baseUrl) {
    final trimmed = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$trimmed/api/v1/ingest/logs');
  }

  @override
  void cancelInFlight() => _inFlight?.cancel('cancelled');

  @override
  Future<IngestOutcome> send(List<SealedEnvelope> envelopes) async {
    final token = CancelToken();
    _inFlight = token;
    var timedOut = false;
    try {
      final headers = <String, dynamic>{'X-Api-Key': _apiKey};
      final attestation = _attestation;
      if (attestation != null) {
        final String? value;
        try {
          value = await attestation().timeout(timeout);
        } catch (error) {
          // Never pass the error on: it may carry the token or its source.
          return const IngestAttestationUnavailable();
        }
        if (value == null || value.isEmpty || _lineBreak.hasMatch(value)) {
          return const IngestAttestationUnavailable();
        }
        headers[attestationHeader] = value;
      }
      if (token.isCancelled) return const IngestCancelled();
      final body = jsonEncode(<String, dynamic>{
        'envelopes': <Map<String, dynamic>>[
          for (final envelope in envelopes) envelope.toWireJson(),
        ],
      });
      return await _exchange(body, headers, token).timeout(
        timeout,
        onTimeout: () {
          timedOut = true;
          token.cancel('timeout');
          throw TimeoutException('ingest request timed out');
        },
      );
    } on TimeoutException {
      return const IngestTimeout();
    } on DioException catch (error) {
      switch (error.type) {
        case DioExceptionType.cancel:
          return timedOut ? const IngestTimeout() : const IngestCancelled();
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return const IngestTimeout();
        default:
          if (isPinMismatch(error.error)) {
            return const IngestNetworkError('certificate pin mismatch');
          }
          return IngestNetworkError(error.type.name);
      }
    } catch (error) {
      return IngestNetworkError(error.runtimeType.toString());
    } finally {
      if (identical(_inFlight, token)) _inFlight = null;
    }
  }

  /// Posts [body] and reads the answer, both within the caller's timeout.
  Future<IngestOutcome> _exchange(
    String body,
    Map<String, dynamic> headers,
    CancelToken token,
  ) async {
    final response = await _dio.postUri<ResponseBody>(
      uri,
      data: body,
      cancelToken: token,
      options: Options(contentType: 'application/json', headers: headers),
    );
    final status = response.statusCode ?? 0;
    if ((status >= 300 && status < 400) ||
        response.isRedirect ||
        response.redirects.isNotEmpty) {
      // On the web the browser may already have followed it; either way the
      // answer did not come from the ingest URL and is not trusted.
      await _discard(response.data);
      return IngestServerError(status, 'redirect not followed');
    }
    final text = await _readCapped(response.data);
    if (text == null) {
      return IngestServerError(status, 'response body too large');
    }
    return _interpret(response, text);
  }

  /// The body as text, or null once it passes [maxResponseBytes] (the rest
  /// is not read).
  static Future<String?> _readCapped(ResponseBody? body) async {
    if (body == null) return '';
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in body.stream) {
      if (bytes.length + chunk.length > maxResponseBytes) return null;
      bytes.add(chunk);
    }
    return utf8.decode(bytes.takeBytes(), allowMalformed: true);
  }

  static Future<void> _discard(ResponseBody? body) async {
    if (body == null) return;
    try {
      await body.stream.take(1).drain<void>();
    } catch (_) {
      // Nothing to do: the response is ignored either way.
    }
  }

  IngestOutcome _interpret(Response<ResponseBody> response, String text) {
    final status = response.statusCode ?? 0;
    switch (status) {
      case 202:
        return parseAcceptedBody(text) ??
            const IngestServerError(202, 'unreadable response body');
      case 401:
      case 403:
        return IngestUnauthorized(status);
      case 413:
        return const IngestTooLarge();
      case 429:
        return IngestRateLimited(
          parseRetryAfter(response.headers.value('retry-after'), clock.now()),
        );
      default:
        return IngestServerError(status, 'unexpected status $status');
    }
  }
}
