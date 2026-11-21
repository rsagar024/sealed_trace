import 'dart:io';

import 'package:dio/dio.dart' show HttpClientAdapter;
import 'package:dio/io.dart' show IOHttpClientAdapter;

import 'spki_pin.dart';

/// A client that refuses any server whose leaf certificate's public key is
/// not one of [pins] (normalized `SpkiPin` values).
///
/// The check runs inside `HttpClient.connectionFactory`, right after the TLS
/// handshake and **before any HTTP bytes are written**, so a mismatching
/// server never receives the API key or the envelopes. Normal certificate
/// validation (chain and host name) still applies first. Proxies are not
/// used, because the TLS session must be ours to inspect. [context] is for
/// tests.
HttpClientAdapter? createPinnedAdapter(
  Set<String> pins, {
  SecurityContext? context,
}) {
  if (pins.isEmpty) return null;
  return IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient(context: context);
      client.findProxy = (Uri _) => 'DIRECT';
      client.connectionFactory = (Uri uri, String? _, int? _) =>
          _connectPinned(uri, pins, context);
      return client;
    },
  );
}

Future<ConnectionTask<Socket>> _connectPinned(
  Uri uri,
  Set<String> pins,
  SecurityContext? context,
) async {
  if (uri.scheme != 'https') {
    throw const PinMismatchException('pinning requires https');
  }
  final task = await SecureSocket.startConnect(
    uri.host,
    uri.port,
    context: context,
  );
  final checked = task.socket.then<Socket>((socket) {
    final certificate = socket.peerCertificate;
    var ok = false;
    try {
      ok = certificate != null && pins.contains(SpkiPin.of(certificate.der));
    } on FormatException {
      ok = false;
    }
    if (!ok) {
      socket.destroy();
      throw const PinMismatchException('certificate pin mismatch');
    }
    return socket;
  });
  return ConnectionTask.fromSocket(checked, task.cancel);
}

/// Whether [error] is a pin mismatch raised by the pinned adapter.
bool isPinMismatch(Object? error) => error is PinMismatchException;

/// Raised when the server's certificate does not match any pin.
class PinMismatchException implements Exception {
  /// Creates the exception.
  const PinMismatchException(this.message);

  /// What went wrong. Never contains certificate or request data.
  final String message;

  @override
  String toString() => 'PinMismatchException: $message';
}
