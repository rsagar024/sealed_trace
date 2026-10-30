@TestOn('vm')
library;

import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/platform/lifecycle_binding.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';
import 'package:sealed_trace/src/storage/storage_adapter.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/envelopes.dart';
import '../helpers/fake_connectivity.dart';
import '../helpers/fake_ingest.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _apiKey = 'sk_test_E2E-SECRET-KEY';

const _config = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj-1',
  apiKey: _apiKey,
  publicKeyPem: testPublicKeySpki,
  appName: 'app',
);

class _World {
  _World({
    this.config = _config,
    bool? online = true,
    List<EnvelopeRow> preloaded = const [],
  }) : connectivity = FakeConnectivity(online: online) {
    server.responder = (request) => FakeResponse.accepted(request.batchIds);
    for (final row in preloaded) {
      preload.add(row);
    }
  }

  final SealedTraceConfig config;
  final FakeConnectivity connectivity;
  final adapter = MemoryStorageAdapter();
  final server = FakeHttpClientAdapter();
  final lifecycle = FakeLifecycle();
  final preload = <EnvelopeRow>[];
  final errors = <Object>[];
  final results = <UploadResult>[];

  Future<void> start() async {
    for (final row in preload) {
      await adapter.insertEnvelope(row);
    }
    SealedTrace.onException = (e, _) => errors.add(e);
    SealedTrace.onUploadResult = results.add;
    SealedTrace.debugOverrides = RuntimeOverrides(
      storage: adapter,
      lifecycle: lifecycle,
      deviceContext: testDevice,
      clock: FakeClock(DateTime.utc(2026, 1, 2)),
      httpClientAdapter: server,
      connectivity: connectivity,
      random: Random(1),
    );
    await SealedTrace.init(config);
    await pumpEventQueue();
  }

  Future<List<EnvelopeIndexRow>> stored() => adapter.listIndex();
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 200; i++) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

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
    'log, flush, and the server receives masked, encrypted envelopes',
    () async {
      final world = _World();
      await world.start();
      SealedTrace.setUser('user-42');
      SealedTrace.i(
        'auth',
        'login for asha@example.com',
        meta: {'password': 'hunter2', 'city': 'Pune'},
      );
      SealedTrace.e('pay', 'card 4111111111111111 declined');

      final result = await SealedTrace.flush();

      expect(result.outcome, UploadOutcome.success);
      expect(result.accepted, 1);
      expect(world.server.requests, hasLength(1));
      final request = world.server.requests.single;
      expect(request.method, 'POST');
      expect(
        request.uri.toString(),
        'https://logs.example.com/api/v1/ingest/logs',
      );
      expect(request.header('X-Api-Key'), _apiKey);

      // Nothing readable leaves the device.
      for (final secret in [
        'asha@example.com',
        'hunter2',
        '4111111111111111',
        'Pune',
        'login for',
      ]) {
        expect(request.body, isNot(contains(secret)), reason: secret);
      }

      // The server (holding the private key) can read the masked events.
      final plaintext = await openWire(request.envelopes.single);
      final events = jsonDecode(plaintext) as List;
      expect(events, hasLength(2));
      expect((events[0] as Map)['message'], 'login for ***');
      expect(((events[0] as Map)['metadata'] as Map)['password'], '***');
      expect((events[1] as Map)['message'], 'card *** declined');

      expect(await world.stored(), isEmpty, reason: 'deleted after the ack');
      expect(world.results, hasLength(1));
      expect(world.results.single.outcome, UploadOutcome.success);
      final d = SealedTrace.diagnostics;
      expect(d.uploadAttempts, 1);
      expect(d.uploadFailures, 0);
      expect(world.errors, isEmpty);
    },
  );

  test('the SDK does not log its own upload (C18)', () async {
    final world = _World();
    await world.start();
    SealedTrace.i('t', 'one event');
    await SealedTrace.flush();
    expect(SealedTrace.diagnostics.eventsAccepted, 1);
  });

  test('a 401 pauses uploads, reports once, and keeps the data', () async {
    final world = _World();
    world.server.responder = (_) => const FakeResponse(401);
    await world.start();
    SealedTrace.i('t', 'secret-ish event');

    final first = await SealedTrace.flush();
    final second = await SealedTrace.flush();

    expect(first.outcome, UploadOutcome.unauthorized);
    expect(second.outcome, UploadOutcome.unauthorized);
    expect(world.server.requests, hasLength(1), reason: 'no second request');
    expect(world.errors, hasLength(1));
    expect(world.errors.single.toString(), contains('HTTP 401'));
    expect(world.errors.single.toString(), isNot(contains(_apiKey)));
    final rows = await world.stored();
    expect(rows, hasLength(1));
    expect(rows.single.attempts, 0);
  });

  test('offline: nothing is sent until connectivity returns', () async {
    final world = _World(online: false);
    await world.start();
    SealedTrace.i('t', 'while offline');

    final result = await SealedTrace.flush();
    expect(result.outcome, UploadOutcome.skipped);
    expect(world.server.requests, isEmpty);
    expect(await world.stored(), hasLength(1));

    world.connectivity.setOnline(true);
    await _waitFor(() => world.server.requests.isNotEmpty);
    await pumpEventQueue();

    expect(world.server.requests, hasLength(1));
    expect(await world.stored(), isEmpty);
  });

  test('envelopes left over from a previous run are sent at start', () async {
    final leftover = makeEnvelope(
      id: 'left-over',
      createdAt: DateTime.utc(2026, 1, 1, 9),
    );
    final world = _World(preloaded: [EnvelopeRow.pending(leftover)]);
    await world.start();
    await _waitFor(() => world.server.requests.isNotEmpty);
    await pumpEventQueue();

    expect(world.server.requests, hasLength(1));
    expect(world.server.requests.single.batchIds, ['left-over']);
    expect(await world.stored(), isEmpty);
  });

  test('enough pending events start an upload without a flush', () async {
    final world = _World();
    await world.start();
    // 8 batches of 25 events reach the 200-event threshold.
    for (var i = 0; i < 200; i++) {
      SealedTrace.i('bulk', 'event $i');
    }
    await _waitFor(() => world.server.requests.isNotEmpty);
    await _waitFor(() => world.results.isNotEmpty);

    expect(world.server.requests, isNotEmpty);
    final sent = world.server.requests
        .expand((r) => r.envelopes)
        .fold<int>(0, (n, e) => n + (e['eventCount'] as int));
    expect(sent, greaterThan(0));
  });

  test('a transient server error is retried and then succeeds', () async {
    final world = _World(
      config: _config.copyWith(
        uploadConfig: const UploadConfig(
          backoffBase: Duration(milliseconds: 10),
        ),
      ),
    );
    var calls = 0;
    world.server.responder = (request) {
      calls++;
      return calls == 1
          ? const FakeResponse(503)
          : FakeResponse.accepted(request.batchIds);
    };
    await world.start();
    SealedTrace.i('t', 'retry me');

    final first = await SealedTrace.flush();
    expect(first.outcome, UploadOutcome.failed);
    expect(world.server.requests, hasLength(1));
    expect((await world.stored()).single.attempts, 1);

    await _waitFor(() => world.server.requests.length >= 2);
    await _waitFor(() => world.results.length >= 2);

    expect(world.server.requests.length, greaterThanOrEqualTo(2));
    expect(
      world.server.requests[0].batchIds,
      world.server.requests[1].batchIds,
      reason: 'the same batch id on the retry',
    );
    expect(await world.stored(), isEmpty);
    expect(world.errors, isEmpty, reason: 'transient errors are not reported');
  });

  test('network errors never put the API key into a report', () async {
    final world = _World();
    world.server.responder = (_) =>
        const FakeResponse(0, errorType: DioExceptionType.connectionError);
    await world.start();
    SealedTrace.i('t', 'x');
    await SealedTrace.flush();
    expect(world.errors, isEmpty);
    for (final text in world.errors.map((e) => e.toString())) {
      expect(text, isNot(contains(_apiKey)));
    }
    expect((await world.stored()).single.attempts, 1);
  });

  group('app resume', () {
    test('triggers an upload', () async {
      final world = _World(online: false);
      await world.start();
      SealedTrace.i('t', 'stored while offline');
      await SealedTrace.flush();
      expect(world.server.requests, isEmpty);

      world.connectivity.online = true; // no change event, just the state
      world.lifecycle.emit(AppLifecycle.resumed);
      await _waitFor(() => world.server.requests.isNotEmpty);
      await pumpEventQueue();

      expect(world.server.requests, hasLength(1));
      expect(await world.stored(), isEmpty);
    });

    test('uploadOnResume: false ignores it', () async {
      final world = _World(
        online: false,
        config: _config.copyWith(
          uploadConfig: const UploadConfig(uploadOnResume: false),
        ),
      );
      await world.start();
      SealedTrace.i('t', 'stored while offline');
      await SealedTrace.flush();

      world.connectivity.online = true;
      world.lifecycle.emit(AppLifecycle.resumed);
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(world.server.requests, isEmpty);
    });
  });

  test('dispose stops uploading and later flushes do nothing', () async {
    final world = _World();
    await world.start();
    SealedTrace.i('t', 'before dispose');
    await SealedTrace.dispose();

    final afterDispose = await SealedTrace.flush();
    expect(afterDispose.outcome, UploadOutcome.skipped);
    final requestsAtDispose = world.server.requests.length;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(world.server.requests.length, requestsAtDispose);
  });

  test('a disabled SDK never uploads', () async {
    final world = _World(config: _config.copyWith(enabled: false));
    await world.start();
    SealedTrace.i('t', 'ignored');
    final result = await SealedTrace.flush();
    expect(result.outcome, UploadOutcome.skipped);
    expect(world.server.requests, isEmpty);
  });

  test('a throwing onUploadResult callback never escapes', () async {
    final world = _World();
    await world.start();
    SealedTrace.onUploadResult = (_) => throw StateError('boom');
    SealedTrace.i('t', 'x');
    await expectLater(SealedTrace.flush(), completes);
    expect(world.errors.whereType<StateError>(), isNotEmpty);
  });
}
