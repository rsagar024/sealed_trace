import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../model/sealed_envelope.dart';
import '../platform/clock.dart';
import 'ingest_response.dart';
import 'retry_after.dart';

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
  }) : uri = ingestUri(baseUrl),
       _apiKey = apiKey,
       _dio = Dio(
         BaseOptions(
           connectTimeout: timeout,
           sendTimeout: timeout,
           receiveTimeout: timeout,
           responseType: ResponseType.plain,
           validateStatus: (_) => true,
         ),
       ) {
    if (adapter != null) _dio.httpClientAdapter = adapter;
  }

  /// The full ingest URL.
  final Uri uri;

  /// Limit for one request, in total.
  final Duration timeout;

  /// Source of "now" for dated `Retry-After` headers.
  final Clock clock;

  final String _apiKey;
  final Dio _dio;
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
      final body = jsonEncode(<String, dynamic>{
        'envelopes': <Map<String, dynamic>>[
          for (final envelope in envelopes) envelope.toWireJson(),
        ],
      });
      final response = await _dio
          .postUri<String>(
            uri,
            data: body,
            cancelToken: token,
            options: Options(
              contentType: 'application/json',
              headers: <String, dynamic>{'X-Api-Key': _apiKey},
            ),
          )
          .timeout(
            timeout,
            onTimeout: () {
              timedOut = true;
              token.cancel('timeout');
              throw TimeoutException('ingest request timed out');
            },
          );
      return _interpret(response);
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
          return IngestNetworkError(error.type.name);
      }
    } catch (error) {
      return IngestNetworkError(error.runtimeType.toString());
    } finally {
      if (identical(_inFlight, token)) _inFlight = null;
    }
  }

  IngestOutcome _interpret(Response<String> response) {
    final status = response.statusCode ?? 0;
    switch (status) {
      case 202:
        return parseAcceptedBody(response.data) ??
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
