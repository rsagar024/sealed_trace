@TestOn('vm')
library;

// The ingest contract (IMPLEMENTATION.md section 6, C1-C20), one test per
// item, end to end: the real SealedTrace facade, scheduler and IngestTransport
// (its own Dio) talk to a scripted HTTP adapter. Test names start with the
// C-number so the section 6 table can point at them.

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/model/sealed_envelope.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/envelopes.dart';
import '../helpers/fake_connectivity.dart';
import '../helpers/fake_ingest.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _apiKey = 'sk_test_CONTRACT-KEY';

SealedTraceConfig _config({
  String baseUrl = 'https://logs.example.com',
  UploadConfig upload = const UploadConfig(),
}) => SealedTraceConfig(
  baseUrl: baseUrl,
  projectId: 'proj-c',
  apiKey: _apiKey,
  publicKeyPem: testPublicKeySpki,
  appName: 'app',
  uploadConfig: upload,
);

/// The SDK wired to a scripted server, with optional rows already stored.
class _World {
  _World({
    this.baseUrl = 'https://logs.example.com',
    this.upload = const UploadConfig(),
  }) {
    server.responder = (request) => FakeResponse.accepted(request.batchIds);
  }

  final String baseUrl;
  final UploadConfig upload;
  final adapter = MemoryStorageAdapter();
  final server = FakeHttpClientAdapter();
  final errors = <Object>[];
  final results = <UploadResult>[];

  Future<void> preload(Iterable<SealedEnvelope> envelopes) async {
    for (final e in envelopes) {
      await adapter.insertEnvelope(EnvelopeRow.pending(e));
    }
  }

  /// Starts the SDK. Its cold-start cycle uploads whatever was preloaded.
  Future<void> start() async {
    SealedTrace.onException = (e, _) => errors.add(e);
    SealedTrace.onUploadResult = results.add;
    SealedTrace.debugOverrides = RuntimeOverrides(
      storage: adapter,
      lifecycle: FakeLifecycle(),
      deviceContext: testDevice,
      clock: FakeClock(DateTime.utc(2026, 1, 2)),
      httpClientAdapter: server,
      connectivity: FakeConnectivity(online: true),
      random: Random(1),
    );
    await SealedTrace.init(_config(baseUrl: baseUrl, upload: upload));
    await _settle();
  }

  Future<void> _settle() async {
    for (var i = 0; i < 20; i++) {
      await pumpEventQueue();
    }
  }

  Future<Map<String, EnvelopeIndexRow>> rows() async => {
    for (final r in await adapter.listIndex()) r.batchId: r,
  };
}

Iterable<SealedEnvelope> _envelopes(int n, {int bytes = 64, String p = 'b'}) =>
    [
      for (var i = 0; i < n; i++)
        makeEnvelope(
          id: '$p-${i.toString().padLeft(4, '0')}',
          createdAt: DateTime.utc(2026, 1, 1, 10).add(Duration(seconds: i)),
          ciphertextLength: bytes,
        ),
    ];

void main() {
  setUp(() async {
    await SealedTrace.dispose();
    SealedTrace.onException = null;
    SealedTrace.onUploadResult = null;
  });

  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.debugOverrides = null;
    SealedTrace.onException = null;
    SealedTrace.onUploadResult = null;
  });

  test(
    'C1 base URL is {baseUrl}/api/v1, trailing slashes normalized',
    () async {
      for (final (base, expected) in [
        (
          'https://logs.example.com/',
          'https://logs.example.com/api/v1/ingest/logs',
        ),
        (
          'https://logs.example.com',
          'https://logs.example.com/api/v1/ingest/logs',
        ),
        (
          'https://h.example.com/base//',
          'https://h.example.com/base/api/v1/ingest/logs',
        ),
      ]) {
        await SealedTrace.dispose();
        final w = _World(baseUrl: base);
        await w.preload(_envelopes(1));
        await w.start();
        expect(w.server.requests.single.uri.toString(), expected, reason: base);
      }
    },
  );

  test('C2 uploads are POST /ingest/logs', () async {
    final w = _World();
    await w.preload(_envelopes(1));
    await w.start();
    final r = w.server.requests.single;
    expect(r.method, 'POST');
    expect(r.uri.path, '/api/v1/ingest/logs');
  });

  test('C3 X-Api-Key carries the api key', () async {
    final w = _World();
    await w.preload(_envelopes(1));
    await w.start();
    expect(w.server.requests.single.header('X-Api-Key'), _apiKey);
  });

  test('C4 Content-Type is application/json', () async {
    final w = _World();
    await w.preload(_envelopes(1));
    await w.start();
    expect(
      w.server.requests.single.header('Content-Type'),
      startsWith('application/json'),
    );
  });

  test('C5 body is {"envelopes": [SealedEnvelope, ...]}', () async {
    final w = _World();
    await w.preload(_envelopes(3));
    await w.start();
    final json = w.server.requests.single.json;
    expect(json.keys, ['envelopes']);
    expect(json['envelopes'], isA<List<dynamic>>());
    expect((json['envelopes'] as List).length, 3);
  });

  test('C6 at most 50 envelopes per request, even when the app asks for '
      'more', () async {
    final w = _World(upload: const UploadConfig(batchSize: 500));
    await w.preload(_envelopes(120));
    await w.start();
    final sizes = w.server.requests.map((r) => r.envelopes.length).toList();
    expect(sizes.every((n) => n <= 50), isTrue, reason: '$sizes');
    expect(sizes.fold<int>(0, (a, b) => a + b), 120);
    expect(await w.rows(), isEmpty);
  });

  test('C7 at most 2 MB of serialized body per request', () async {
    final w = _World();
    // About 800 KB of base64 each: two fit in a request, three do not.
    await w.preload(_envelopes(5, bytes: 600 * 1024));
    await w.start();
    expect(w.server.requests, hasLength(greaterThan(1)));
    for (final r in w.server.requests) {
      expect(utf8.encode(r.body).length, lessThanOrEqualTo(2000000));
    }
    expect(await w.rows(), isEmpty);
  });

  test('C8 202 parses accepted, duplicate, rejected; unknown fields '
      'are ignored', () async {
    final w = _World();
    await w.preload(_envelopes(3));
    w.server.enqueue(
      FakeResponse(
        202,
        body: jsonEncode({
          'accepted': ['b-0000'],
          'duplicate': ['b-0001'],
          'rejected': [
            {'batchId': 'b-0002', 'reason': 'try_later', 'extra': 1},
          ],
          'serverTime': '2026-01-02T00:00:00Z',
          'unknown': {'nested': true},
        }),
      ),
    );
    await w.start();
    final result = w.results.first;
    expect(result.accepted, 1);
    expect(result.duplicate, 1);
    expect(result.rejected, 1);
  });

  test('C9 rows are deleted only for accepted and duplicate ids', () async {
    final w = _World();
    await w.preload(_envelopes(4));
    w.server.enqueue(
      FakeResponse.accepted(
        ['b-0000', 'not-ours'],
        duplicate: ['b-0001'],
        rejected: [
          {'batchId': 'b-0002', 'reason': 'try_later'},
        ],
      ),
    );
    await w.start();
    // b-0003 was missing from every list (C11); "not-ours" was never sent.
    expect((await w.rows()).keys, unorderedEquals(['b-0002', 'b-0003']));
  });

  test('C10 rejected rows are kept with a failure, or dead-lettered when '
      'the reason is permanent', () async {
    final w = _World();
    await w.preload(_envelopes(2));
    w.server.enqueue(
      FakeResponse.accepted(
        const [],
        rejected: [
          {'batchId': 'b-0000', 'reason': 'try_later'},
          {'batchId': 'b-0001', 'reason': 'schema_invalid'},
        ],
      ),
    );
    await w.start();
    final rows = await w.rows();
    expect(rows['b-0000']!.attempts, 1);
    expect(rows['b-0000']!.uploadState, uploadStatePending);
    expect(rows['b-0001']!.uploadState, uploadStateDeadLetter);
  });

  test(
    'C11 an id missing from all three lists is kept as unacknowledged',
    () async {
      final w = _World();
      await w.preload(_envelopes(1));
      w.server.enqueue(FakeResponse.accepted(const []));
      await w.start();
      final row = (await w.rows())['b-0000']!;
      expect(row.attempts, 1);
      expect(row.uploadedAt, isNull);
    },
  );

  for (final status in [401, 403]) {
    test('C${status == 401 ? 12 : 13} $status pauses uploads, keeps data, '
        'burns no attempt', () async {
      final w = _World();
      await w.preload(_envelopes(2));
      w.server.enqueue(FakeResponse(status));
      await w.start();
      final rows = await w.rows();
      expect(rows, hasLength(2));
      expect(rows.values.every((r) => r.attempts == 0), isTrue);
      expect(w.errors.whereType<StateError>(), hasLength(1));
      expect('${w.errors.single}', isNot(contains(_apiKey)));

      final sent = w.server.requests.length;
      final again = await SealedTrace.flush();
      expect(again.outcome, UploadOutcome.unauthorized);
      expect(w.server.requests.length, sent, reason: 'paused: nothing sent');
    });
  }

  test('C14 413 halves the request and retries', () async {
    final w = _World();
    await w.preload(_envelopes(4));
    w.server.enqueue(const FakeResponse(413));
    await w.start();
    final sizes = w.server.requests.map((r) => r.envelopes.length).toList();
    expect(sizes.first, 4);
    expect(sizes[1], 2);
    // Every envelope was delivered in the same cycle after halving.
    expect(await w.rows(), isEmpty);
    expect(w.results.first.outcome, UploadOutcome.success);
  });

  test('C15 429 honours Retry-After and burns no attempt', () async {
    final w = _World();
    await w.preload(_envelopes(1));
    w.server.enqueue(
      const FakeResponse(
        429,
        headers: {
          'retry-after': ['120'],
        },
      ),
    );
    await w.start();
    final row = (await w.rows())['b-0000']!;
    expect(row.attempts, 0);
    // A retry is scheduled, so an ordinary trigger must not send now.
    final sent = w.server.requests.length;
    SealedTrace.i('t', 'after 429');
    await pumpEventQueue();
    expect(w.server.requests.length, sent);
  });

  test('C16 batchId is stable across retries', () async {
    final w = _World();
    w.server.enqueue(const FakeResponse(503));
    await w.start();
    // The cold start had nothing; log one event, fail once, then succeed.
    SealedTrace.i('t', 'retry me');
    await SealedTrace.flush();
    final stored = (await w.rows()).keys.single;
    await SealedTrace.flush();
    final ids = [for (final r in w.server.requests) ...r.batchIds];
    expect(ids, [stored, stored]);
    expect(await w.rows(), isEmpty);
  });

  test(
    'C17 the request timeout is 30 s and a timeout keeps the rows',
    () async {
      expect(const UploadConfig().requestTimeout, const Duration(seconds: 30));
      final w = _World();
      await w.preload(_envelopes(1));
      w.server.enqueue(
        const FakeResponse(0, errorType: DioExceptionType.receiveTimeout),
      );
      await w.start();
      expect((await w.rows())['b-0000']!.attempts, 1);
    },
  );

  test('C18 the SDK never logs its own ingest calls', () async {
    final w = _World();
    await w.start();
    // An app Dio with the interceptor, calling the ingest endpoint itself
    // and an ordinary endpoint.
    final appServer = FakeHttpClientAdapter(const FakeResponse(200));
    final dio = Dio()
      ..httpClientAdapter = appServer
      ..interceptors.add(SealedTraceInterceptor());
    await dio.post<void>('https://logs.example.com/api/v1/ingest/logs');
    await dio.get<void>('https://api.example.com/v1/users');
    await pumpEventQueue();
    await SealedTrace.flush();
    final events = [
      for (final r in w.server.requests)
        for (final e in r.envelopes)
          ...(jsonDecode(await openWire(e)) as List)
              .cast<Map<String, dynamic>>(),
    ];
    final urls = [
      for (final e in events)
        if (e['tag'] == 'network') (e['metadata'] as Map)['url'],
    ];
    expect(urls, ['https://api.example.com/v1/users']);
  });

  test('C19 envelope fields are exactly the section 7 format', () async {
    final w = _World();
    await w.start();
    SealedTrace.i('t', 'one');
    SealedTrace.e('t', 'two');
    await SealedTrace.flush();
    final e = w.server.requests.single.envelopes.single;
    expect(e.keys.toSet(), {
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
    });
    expect(e['v'], 1);
    expect(e['alg'], 'RSA-OAEP-2048-SHA256+AES-256-GCM');
    expect(e['projectId'], 'proj-c');
    expect(e['eventCount'], 2);
    expect(base64.decode(e['wrappedKey'] as String), hasLength(256));
    expect(base64.decode(e['iv'] as String), hasLength(12));
    expect(base64.decode(e['tag'] as String), hasLength(16));
    final events = jsonDecode(await openWire(e)) as List;
    expect(events.map((x) => (x as Map)['message']), ['one', 'two']);
  });

  test('C20 only /ingest/logs is ever called', () async {
    final w = _World();
    await w.preload(_envelopes(60));
    w.server.enqueue(const FakeResponse(503));
    w.server.enqueue(const FakeResponse(413));
    await w.start();
    SealedTrace.i('t', 'x');
    await SealedTrace.flush();
    await SealedTrace.flush();
    expect(w.server.requests, isNotEmpty);
    expect(w.server.requests.map((r) => r.uri.path).toSet(), {
      '/api/v1/ingest/logs',
    });
  });
}
