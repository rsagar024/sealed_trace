import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/transport/ingest_response.dart';
import 'package:sealed_trace/src/transport/ingest_transport.dart';

import '../helpers/envelopes.dart';
import '../helpers/fake_ingest.dart';
import '../helpers/fakes.dart';

const _apiKey = 'sk_live_SUPER-SECRET-KEY-123';

IngestTransport _transport(
  FakeHttpClientAdapter adapter, {
  String baseUrl = 'https://logs.example.com',
  Duration timeout = const Duration(seconds: 30),
  DateTime? now,
}) => IngestTransport(
  baseUrl: baseUrl,
  apiKey: _apiKey,
  timeout: timeout,
  adapter: adapter,
  clock: FakeClock(now ?? DateTime.utc(2026, 6, 1, 12)),
);

void main() {
  group('request shape (C1-C5, C20)', () {
    test('URL: {baseUrl}/api/v1/ingest/logs, trailing slashes tolerated', () {
      expect(
        IngestTransport.ingestUri('https://x.com').toString(),
        'https://x.com/api/v1/ingest/logs',
      );
      expect(
        IngestTransport.ingestUri('https://x.com///').toString(),
        'https://x.com/api/v1/ingest/logs',
      );
      expect(
        IngestTransport.ingestUri('  https://x.com/base/ ').toString(),
        'https://x.com/base/api/v1/ingest/logs',
      );
      expect(
        IngestTransport.ingestUri('http://localhost:8080').toString(),
        'http://localhost:8080/api/v1/ingest/logs',
      );
    });

    test('POST with the key and JSON content type', () async {
      final adapter = FakeHttpClientAdapter();
      await _transport(adapter).send([makeEnvelope()]);

      expect(adapter.requests, hasLength(1));
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.toString(),
        'https://logs.example.com/api/v1/ingest/logs',
      );
      expect(request.header('X-Api-Key'), _apiKey);
      expect(request.header('Content-Type'), startsWith('application/json'));
    });

    test('only /ingest/logs is ever used', () async {
      final adapter = FakeHttpClientAdapter();
      final transport = _transport(adapter);
      await transport.send([makeEnvelope()]);
      await transport.send([makeEnvelope()]);
      expect(adapter.requests.map((r) => r.uri.path).toSet(), {
        '/api/v1/ingest/logs',
      });
    });

    test('the body is {"envelopes": [SealedEnvelope, ...]} exactly', () async {
      final a = makeEnvelope(id: 'a');
      final b = makeEnvelope(id: 'b', eventCount: 4);
      final adapter = FakeHttpClientAdapter();
      await _transport(adapter).send([a, b]);

      final json = adapter.requests.single.json;
      expect(json.keys.toList(), ['envelopes']);
      expect(adapter.requests.single.envelopes, [
        a.toWireJson(),
        b.toWireJson(),
      ]);
      expect(adapter.requests.single.envelopes.first.keys.toList(), [
        'v',
        'batchId',
        'projectId',
        'createdAt',
        'eventCount',
        'alg',
        'wrappedKey',
        'iv',
        'tag',
        'ciphertext',
      ]);
    });

    test('has no interceptors of its own (C18)', () {
      final transport = _transport(FakeHttpClientAdapter());
      final names = transport.dio.interceptors.map(
        (i) => i.runtimeType.toString(),
      );
      // Dio installs a built-in content-type helper; nothing of ours.
      expect(
        names.toSet().difference({'ImplyContentTypeInterceptor'}),
        isEmpty,
      );
    });

    test(
      'request timeout is configurable and defaults to 30 seconds (C17)',
      () {
        final transport = _transport(FakeHttpClientAdapter());
        expect(transport.timeout, const Duration(seconds: 30));
        expect(
          transport.dio.options.connectTimeout,
          const Duration(seconds: 30),
        );
        expect(transport.dio.options.sendTimeout, const Duration(seconds: 30));
        expect(
          transport.dio.options.receiveTimeout,
          const Duration(seconds: 30),
        );
      },
    );
  });

  group('responses (C8)', () {
    test('202 with all three lists', () async {
      final adapter = FakeHttpClientAdapter()
        ..enqueue(
          FakeResponse.accepted(
            ['a'],
            duplicate: ['b'],
            rejected: [
              {'batchId': 'c', 'reason': 'schema_invalid'},
            ],
          ),
        );
      final outcome = await _transport(adapter).send([makeEnvelope()]);
      outcome as IngestAccepted;
      expect(outcome.accepted, {'a'});
      expect(outcome.duplicate, {'b'});
      expect(outcome.rejected.single.batchId, 'c');
      expect(outcome.rejected.single.reason, 'schema_invalid');
    });

    test('unknown fields are ignored and missing lists are empty', () async {
      final adapter = FakeHttpClientAdapter()
        ..enqueue(
          const FakeResponse(
            202,
            body: '{"accepted":["a"],"serverTime":"2026","extra":{"x":1}}',
          ),
        );
      final outcome = await _transport(adapter).send([makeEnvelope()]);
      outcome as IngestAccepted;
      expect(outcome.accepted, {'a'});
      expect(outcome.duplicate, isEmpty);
      expect(outcome.rejected, isEmpty);
    });

    test('a rejection without a reason is "unknown"', () async {
      final adapter = FakeHttpClientAdapter()
        ..enqueue(
          const FakeResponse(202, body: '{"rejected":[{"batchId":"x"}]}'),
        );
      final outcome = await _transport(adapter).send([makeEnvelope()]);
      expect((outcome as IngestAccepted).rejected.single.reason, 'unknown');
    });

    for (final body in [
      '',
      'not json',
      '[]',
      '"text"',
      '{"accepted":"a"}',
      '{"accepted":[1,2]}',
      '{"duplicate":{"a":1}}',
      '{"rejected":"x"}',
      '{"rejected":[1]}',
      '{"rejected":[{"reason":"r"}]}',
    ]) {
      test('a 202 with a malformed body is a failure: "$body"', () async {
        final adapter = FakeHttpClientAdapter()
          ..enqueue(FakeResponse(202, body: body));
        final outcome = await _transport(adapter).send([makeEnvelope()]);
        expect(outcome, isA<IngestServerError>());
      });
    }

    test('statuses map to outcomes', () async {
      Future<IngestOutcome> run(int status) async {
        final adapter = FakeHttpClientAdapter()..enqueue(FakeResponse(status));
        return _transport(adapter).send([makeEnvelope()]);
      }

      expect(await run(401), isA<IngestUnauthorized>());
      expect((await run(401) as IngestUnauthorized).status, 401);
      expect((await run(403) as IngestUnauthorized).status, 403);
      expect(await run(413), isA<IngestTooLarge>());
      expect(await run(429), isA<IngestRateLimited>());
      for (final status in [200, 201, 204, 400, 404, 409, 422, 500, 502, 503]) {
        final outcome = await run(status);
        expect(outcome, isA<IngestServerError>(), reason: '$status');
        expect((outcome as IngestServerError).status, status);
      }
    });

    test('Retry-After is read in seconds, as a date, or ignored', () async {
      Future<Duration?> run(String? header) async {
        final adapter = FakeHttpClientAdapter()
          ..enqueue(
            FakeResponse(
              429,
              headers: header == null
                  ? const {}
                  : {
                      'retry-after': [header],
                    },
            ),
          );
        final outcome = await _transport(
          adapter,
          now: DateTime.utc(2026, 6, 1, 12),
        ).send([makeEnvelope()]);
        return (outcome as IngestRateLimited).retryAfter;
      }

      expect(await run('7'), const Duration(seconds: 7));
      expect(
        await run('Mon, 01 Jun 2026 12:01:30 GMT'),
        const Duration(seconds: 90),
      );
      expect(await run('garbage'), isNull);
      expect(await run(null), isNull);
    });
  });

  group('failures', () {
    test('connection errors are network errors', () async {
      for (final type in [
        DioExceptionType.connectionError,
        DioExceptionType.badCertificate,
        DioExceptionType.badResponse,
        DioExceptionType.unknown,
      ]) {
        final adapter = FakeHttpClientAdapter()
          ..enqueue(FakeResponse(0, errorType: type));
        final outcome = await _transport(adapter).send([makeEnvelope()]);
        expect(outcome, isA<IngestNetworkError>(), reason: type.name);
      }
    });

    test('Dio timeouts are timeouts', () async {
      for (final type in [
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ]) {
        final adapter = FakeHttpClientAdapter()
          ..enqueue(FakeResponse(0, errorType: type));
        final outcome = await _transport(adapter).send([makeEnvelope()]);
        expect(outcome, isA<IngestTimeout>(), reason: type.name);
      }
    });

    test('a request slower than the limit times out', () async {
      final adapter = FakeHttpClientAdapter()
        ..enqueue(const FakeResponse(202, delay: Duration(milliseconds: 600)));
      final watch = Stopwatch()..start();
      final outcome = await _transport(
        adapter,
        timeout: const Duration(milliseconds: 100),
      ).send([makeEnvelope()]);
      expect(outcome, isA<IngestTimeout>());
      expect(watch.elapsedMilliseconds, lessThan(550));
    });

    test('cancelInFlight ends a running request as cancelled', () async {
      final adapter = FakeHttpClientAdapter()
        ..enqueue(const FakeResponse(202, delay: Duration(seconds: 5)));
      final transport = _transport(adapter);
      final pending = transport.send([makeEnvelope()]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      transport.cancelInFlight();
      expect(await pending, isA<IngestCancelled>());
    });

    test('cancelInFlight with nothing running is harmless', () {
      expect(
        () => _transport(FakeHttpClientAdapter()).cancelInFlight(),
        returnsNormally,
      );
    });

    test('the transport can be used again after a failure', () async {
      final adapter = FakeHttpClientAdapter()
        ..enqueue(
          const FakeResponse(0, errorType: DioExceptionType.connectionError),
        )
        ..enqueue(FakeResponse.accepted(['x']));
      final transport = _transport(adapter);
      expect(await transport.send([makeEnvelope()]), isA<IngestNetworkError>());
      expect(await transport.send([makeEnvelope()]), isA<IngestAccepted>());
    });
  });

  group('the API key never leaks', () {
    test('failure outcomes contain no part of the key or its header', () async {
      final outcomes = <IngestOutcome>[];
      for (final type in DioExceptionType.values) {
        if (type == DioExceptionType.cancel) continue;
        final adapter = FakeHttpClientAdapter()
          ..enqueue(FakeResponse(0, errorType: type));
        outcomes.add(await _transport(adapter).send([makeEnvelope()]));
      }
      for (final status in [400, 401, 413, 429, 500]) {
        final adapter = FakeHttpClientAdapter()..enqueue(FakeResponse(status));
        outcomes.add(await _transport(adapter).send([makeEnvelope()]));
      }
      for (final outcome in outcomes) {
        final text = switch (outcome) {
          IngestServerError(:final description) => description,
          IngestNetworkError(:final description) => description,
          _ => outcome.runtimeType.toString(),
        };
        expect(text, isNot(contains(_apiKey)));
        expect(text.toLowerCase(), isNot(contains('x-api-key')));
        expect(text, isNot(contains('SECRET')));
      }
    });

    test(
      'a transport error that carried headers is reduced to its type',
      () async {
        final adapter = FakeHttpClientAdapter()
          ..enqueue(
            const FakeResponse(0, errorType: DioExceptionType.connectionError),
          );
        final outcome = await _transport(adapter).send([makeEnvelope()]);
        expect((outcome as IngestNetworkError).description, 'connectionError');
      },
    );
  });

  test('timing: a full 50-envelope request against the fake server', () async {
    final envelopes = [
      for (var i = 0; i < 50; i++)
        makeEnvelope(id: 'perf-$i', ciphertextLength: 15000),
    ];
    final adapter = FakeHttpClientAdapter()
      ..responder = (request) => FakeResponse.accepted(request.batchIds);
    final transport = _transport(adapter);
    final watch = Stopwatch()..start();
    final outcome = await transport.send(envelopes);
    watch.stop();
    expect(outcome, isA<IngestAccepted>());
    final kb = adapter.requests.single.body.length ~/ 1024;
    // ignore: avoid_print
    print(
      'Sending 50 envelopes ($kb KB body) to the fake server: '
      '${watch.elapsedMilliseconds} ms',
    );
    expect(watch.elapsedMilliseconds, lessThan(5000));
  });
}
