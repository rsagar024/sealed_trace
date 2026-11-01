import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// What the mock ingest server received for one envelope. The device has no
/// private key, so only the clear envelope fields can be shown.
class ReceivedEnvelope {
  /// Creates a record of one received envelope.
  const ReceivedEnvelope({
    required this.batchId,
    required this.eventCount,
    required this.ciphertextBytes,
    required this.receivedAt,
  });

  /// The batch id the server deduplicates on.
  final String batchId;

  /// Events inside, as declared by the envelope.
  final int eventCount;

  /// Size of the encrypted payload.
  final int ciphertextBytes;

  /// When the mock server got it.
  final DateTime receivedAt;
}

/// A stand-in for the SealedTrace ingest endpoint, used through
/// `UploadConfig.httpClientAdapter`. It accepts every envelope, like a
/// healthy server, and keeps what it saw. Works on every platform, including
/// the web, because it never opens a socket.
class MockIngestAdapter implements HttpClientAdapter {
  /// Envelopes received so far, newest last.
  final List<ReceivedEnvelope> received = [];

  /// Called after each request, so the UI can refresh.
  void Function()? onReceived;

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
    if (!options.uri.path.endsWith('/api/v1/ingest/logs')) {
      return ResponseBody.fromString('', 404);
    }
    final body = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    final envelopes = (body['envelopes'] as List).cast<Map<String, dynamic>>();
    final now = DateTime.now();
    for (final e in envelopes) {
      received.add(
        ReceivedEnvelope(
          batchId: e['batchId'] as String,
          eventCount: e['eventCount'] as int,
          ciphertextBytes: base64.decode(e['ciphertext'] as String).length,
          receivedAt: now,
        ),
      );
    }
    onReceived?.call();
    return ResponseBody.fromString(
      jsonEncode({
        'accepted': [for (final e in envelopes) e['batchId']],
        'duplicate': [],
        'rejected': [],
      }),
      202,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
