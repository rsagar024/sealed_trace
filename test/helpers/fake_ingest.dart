import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';
import 'package:sealed_trace/src/transport/ingest_response.dart';
import 'package:sealed_trace/src/transport/ingest_transport.dart';

/// One request the fake server saw.
class RecordedRequest {
  RecordedRequest(this.method, this.uri, this.headers, this.body);

  final String method;
  final Uri uri;
  final Map<String, dynamic> headers;
  final String body;

  /// Case-insensitive header lookup.
  String? header(String name) {
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == name.toLowerCase()) {
        return '${entry.value}';
      }
    }
    return null;
  }

  Map<String, dynamic> get json => jsonDecode(body) as Map<String, dynamic>;

  List<Map<String, dynamic>> get envelopes =>
      (json['envelopes'] as List).cast<Map<String, dynamic>>();

  List<String> get batchIds => [
    for (final e in envelopes) e['batchId']! as String,
  ];
}

/// What the fake server answers with.
class FakeResponse {
  const FakeResponse(
    this.status, {
    this.body = '',
    this.headers = const <String, List<String>>{},
    this.delay = Duration.zero,
    this.errorType,
  });

  /// A 202 that accepts every id in [accepted].
  factory FakeResponse.accepted(
    Iterable<String> accepted, {
    Iterable<String> duplicate = const [],
    List<Map<String, String>> rejected = const [],
  }) => FakeResponse(
    202,
    body: jsonEncode({
      'accepted': accepted.toList(),
      'duplicate': duplicate.toList(),
      'rejected': rejected,
    }),
  );

  final int status;
  final String body;
  final Map<String, List<String>> headers;
  final Duration delay;

  /// When set, the adapter throws a [DioException] of this type instead.
  final DioExceptionType? errorType;
}

/// A scripted stand-in for the network, plugged into Dio.
class FakeHttpClientAdapter implements HttpClientAdapter {
  FakeHttpClientAdapter([this.fallback = const FakeResponse(202)]);

  final List<RecordedRequest> requests = [];
  final List<FakeResponse> script = [];

  /// Used when the script is empty.
  FakeResponse fallback;

  /// When set, answers requests once the script is empty (before [fallback]).
  FakeResponse Function(RecordedRequest request)? responder;

  /// Answers the next requests in order.
  void enqueue(FakeResponse response) => script.add(response);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = <int>[];
    if (requestStream != null) {
      await for (final chunk in requestStream) {
        bytes.addAll(chunk);
      }
    }
    final request = RecordedRequest(
      options.method,
      options.uri,
      Map<String, dynamic>.of(options.headers),
      utf8.decode(bytes),
    );
    requests.add(request);

    final response = script.isNotEmpty
        ? script.removeAt(0)
        : (responder?.call(request) ?? fallback);
    if (response.delay > Duration.zero) {
      await Future<void>.delayed(response.delay);
    }
    final type = response.errorType;
    if (type != null) {
      throw DioException(
        requestOptions: options,
        type: type,
        // Deliberately carries the headers, like a real failure would.
        error: 'failed: ${options.headers}',
        message: 'failed: ${options.headers}',
      );
    }
    return ResponseBody.fromString(
      response.body,
      response.status,
      headers: response.headers,
    );
  }

  @override
  void close({bool force = false}) {}
}

/// An [IngestClient] answering from a script, for scheduler tests.
class ScriptedIngestClient implements IngestClient {
  final List<List<String>> calls = [];
  final List<List<SealedEnvelope>> sent = [];
  final List<FutureOr<IngestOutcome> Function(List<SealedEnvelope>)> script =
      [];
  int cancelCalls = 0;
  int running = 0;
  int maxRunning = 0;

  /// Used when the script is empty: accept everything.
  FutureOr<IngestOutcome> Function(List<SealedEnvelope>) fallback = (batch) =>
      IngestAccepted(
        accepted: {for (final e in batch) e.batchId},
        duplicate: const {},
        rejected: const [],
      );

  void enqueue(FutureOr<IngestOutcome> Function(List<SealedEnvelope>) answer) =>
      script.add(answer);

  void enqueueOutcome(IngestOutcome outcome) => script.add((_) => outcome);

  @override
  Future<IngestOutcome> send(List<SealedEnvelope> envelopes) async {
    calls.add([for (final e in envelopes) e.batchId]);
    sent.add(List.of(envelopes));
    running++;
    if (running > maxRunning) maxRunning = running;
    try {
      final answer = script.isNotEmpty ? script.removeAt(0) : fallback;
      return await answer(envelopes);
    } finally {
      running--;
    }
  }

  @override
  void cancelInFlight() => cancelCalls++;
}
