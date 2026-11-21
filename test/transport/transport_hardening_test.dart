import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/config/config_validator.dart';
import 'package:sealed_trace/src/transport/ingest_response.dart';
import 'package:sealed_trace/src/transport/ingest_transport.dart';
import 'package:sealed_trace/src/transport/pinned_adapter_io.dart';
import 'package:sealed_trace/src/transport/spki_pin.dart';

import '../helpers/envelopes.dart';
import '../helpers/fake_ingest.dart';
import '../helpers/test_keys.dart';
import '../helpers/tls_test_cert.dart';

Uint8List _der(String pem) => base64.decode(
  pem
      .replaceAll(RegExp(r'-----[A-Z ]+-----'), '')
      .replaceAll(RegExp(r'\s'), ''),
);

IngestTransport _transport(FakeHttpClientAdapter adapter) => IngestTransport(
  baseUrl: 'https://logs.example.com',
  apiKey: 'key',
  adapter: adapter,
);

void main() {
  group('L1: redirects are never followed', () {
    test('the client is configured not to follow', () {
      final dio = _transport(FakeHttpClientAdapter()).dio;
      expect(dio.options.followRedirects, isFalse);
      expect(dio.options.maxRedirects, 0);
    });

    for (final status in [301, 302, 303, 307, 308]) {
      test(
        '$status is a failure, sent once, and its body is ignored',
        () async {
          final adapter = FakeHttpClientAdapter()
            ..enqueue(
              FakeResponse(
                status,
                body: jsonEncode({
                  'accepted': ['b-1'],
                }),
                headers: {
                  'location': ['https://evil.example/collect'],
                },
              ),
            );
          final outcome = await _transport(adapter).send([makeEnvelope()]);
          expect(outcome, isA<IngestServerError>());
          expect((outcome as IngestServerError).status, status);
          expect(outcome.description, 'redirect not followed');
          expect(adapter.requests, hasLength(1));
        },
      );
    }

    test(
      'a 202 the browser reached through a redirect is not trusted',
      () async {
        final adapter = FakeHttpClientAdapter()
          ..enqueue(
            FakeResponse(
              202,
              body: jsonEncode({
                'accepted': ['b-1'],
              }),
              isRedirect: true,
            ),
          );
        final outcome = await _transport(adapter).send([makeEnvelope()]);
        expect(outcome, isA<IngestServerError>());
        expect(
          (outcome as IngestServerError).description,
          'redirect not followed',
        );
      },
    );
  });

  group('L1: the response body is capped', () {
    test('a body over 256 KB is not read and the request fails', () async {
      final adapter = FakeHttpClientAdapter()
        ..enqueue(
          FakeResponse(
            202,
            body: '{"accepted":[], "pad":"${'x' * (300 * 1024)}"}',
          ),
        );
      final outcome = await _transport(adapter).send([makeEnvelope()]);
      expect(outcome, isA<IngestServerError>());
      expect(
        (outcome as IngestServerError).description,
        'response body too large',
      );
    });

    test('a normal 202 body is still read', () async {
      final envelope = makeEnvelope();
      final adapter = FakeHttpClientAdapter()
        ..enqueue(FakeResponse.accepted([envelope.batchId]));
      final outcome = await _transport(adapter).send([envelope]);
      expect(outcome, isA<IngestAccepted>());
      expect((outcome as IngestAccepted).accepted, [envelope.batchId]);
    });
  });

  group('L1: SPKI pins', () {
    test('the pin of a certificate matches OpenSSL', () {
      expect(SpkiPin.of(_der(tlsTestCertPem)), tlsTestCertPin);
      expect(SpkiPin.of(_der(tlsOtherCertPem)), tlsOtherCertPin);
    });

    test('pins are normalized and validated', () {
      expect(SpkiPin.normalize(' sha256/$tlsTestCertPin '), tlsTestCertPin);
      expect(SpkiPin.isValid(tlsTestCertPin), isTrue);
      expect(SpkiPin.isValid('sha256/$tlsTestCertPin'), isTrue);
      expect(SpkiPin.isValid('not base64!'), isFalse);
      expect(SpkiPin.isValid(base64.encode(List.filled(20, 1))), isFalse);
    });

    test('a non-certificate is a FormatException', () {
      expect(
        () => SpkiPin.of(Uint8List.fromList([0x30, 0x03, 0x02, 0x01, 0x01])),
        throwsFormatException,
      );
      expect(() => SpkiPin.of(Uint8List(0)), throwsFormatException);
    });
  });

  group('L1: pinning against a real TLS server', () {
    late HttpServer server;
    late SecurityContext clientContext;
    var received = 0;

    setUp(() async {
      received = 0;
      final serverContext = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(tlsTestCertPem))
        ..usePrivateKeyBytes(utf8.encode(tlsTestKeyPem));
      server = await HttpServer.bindSecure(
        InternetAddress.loopbackIPv4,
        0,
        serverContext,
      );
      server.listen((request) async {
        received++;
        await request.drain<void>();
        request.response
          ..statusCode = 202
          ..write(jsonEncode({'accepted': <String>[]}));
        await request.response.close();
      });
      clientContext = SecurityContext(withTrustedRoots: false)
        ..setTrustedCertificatesBytes(utf8.encode(tlsTestCertPem));
    });

    tearDown(() => server.close(force: true));

    IngestTransport pinned(Set<String> pins) => IngestTransport(
      baseUrl: 'https://localhost:${server.port}',
      apiKey: 'key-must-not-leak',
      timeout: const Duration(seconds: 10),
      adapter: createPinnedAdapter(pins, context: clientContext),
    );

    test('the matching pin connects and the request arrives', () async {
      final outcome = await pinned({tlsTestCertPin}).send([makeEnvelope()]);
      expect(outcome, isA<IngestAccepted>());
      expect(received, 1);
    });

    test('a backup pin alongside it is fine', () async {
      final outcome = await pinned({
        tlsOtherCertPin,
        tlsTestCertPin,
      }).send([makeEnvelope()]);
      expect(outcome, isA<IngestAccepted>());
    });

    test('a wrong pin fails before any request bytes are sent', () async {
      final outcome = await pinned({tlsOtherCertPin}).send([makeEnvelope()]);
      expect(outcome, isA<IngestNetworkError>());
      expect(
        (outcome as IngestNetworkError).description,
        'certificate pin mismatch',
      );
      expect(received, 0, reason: 'the server never saw the request');
    });

    test('no pins means no pinned adapter', () {
      expect(createPinnedAdapter(<String>{}), isNull);
    });
  });

  group('L1: config validation', () {
    const base = SealedTraceConfig(
      baseUrl: 'https://logs.example.com',
      projectId: 'p',
      apiKey: 'k',
      publicKeyPem: testPublicKeySpki,
      appName: 'a',
    );

    SealedTraceConfig withPins(List<String> pins, {String? baseUrl}) =>
        base.copyWith(
          baseUrl: baseUrl,
          env: SealedTraceEnv.dev,
          uploadConfig: UploadConfig(pinnedSpkiSha256: pins),
        );

    test('valid pins pass', () {
      expect(ConfigValidator.validate(withPins([tlsTestCertPin])), isEmpty);
    });

    test('malformed pins, http and an adapter are reported', () {
      expect(ConfigValidator.validate(withPins(['nope'])), [
        'pinnedSpkiSha256 entries must be base64 SHA-256 hashes (32 bytes)',
      ]);
      expect(
        ConfigValidator.validate(
          withPins([tlsTestCertPin], baseUrl: 'http://localhost:8080'),
        ),
        ['pinnedSpkiSha256 requires an https baseUrl'],
      );
      expect(
        ConfigValidator.validate(
          base.copyWith(
            uploadConfig: UploadConfig(
              pinnedSpkiSha256: const [tlsTestCertPin],
              httpClientAdapter: FakeHttpClientAdapter(),
            ),
          ),
        ),
        ['pinnedSpkiSha256 cannot be combined with httpClientAdapter'],
      );
    });

    test('the field takes part in copyWith and equality', () {
      const a = UploadConfig(pinnedSpkiSha256: [tlsTestCertPin]);
      expect(const UploadConfig().pinnedSpkiSha256, isEmpty);
      expect(
        const UploadConfig().copyWith(pinnedSpkiSha256: [tlsTestCertPin]),
        a,
      );
      expect(a, isNot(const UploadConfig()));
    });
  });
}
