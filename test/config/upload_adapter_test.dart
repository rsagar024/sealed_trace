@TestOn('vm')
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/fake_connectivity.dart';
import '../helpers/fake_ingest.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

void main() {
  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.debugOverrides = null;
  });

  group('UploadConfig.httpClientAdapter', () {
    test('defaults to null and survives copyWith and clamping', () {
      expect(const UploadConfig().httpClientAdapter, isNull);
      final adapter = FakeHttpClientAdapter();
      final config = UploadConfig(httpClientAdapter: adapter, batchSize: 999);
      expect(config.copyWith(maxAttempts: 3).httpClientAdapter, same(adapter));
    });

    test('is compared by identity', () {
      final a = FakeHttpClientAdapter();
      expect(
        UploadConfig(httpClientAdapter: a),
        UploadConfig(httpClientAdapter: a),
      );
      expect(
        UploadConfig(httpClientAdapter: a).hashCode,
        UploadConfig(httpClientAdapter: a).hashCode,
      );
      expect(
        UploadConfig(httpClientAdapter: a),
        isNot(UploadConfig(httpClientAdapter: FakeHttpClientAdapter())),
      );
      expect(UploadConfig(httpClientAdapter: a), isNot(const UploadConfig()));
    });

    test(
      'carries the SDK\'s uploads, with the normal URL and headers',
      () async {
        final server = FakeHttpClientAdapter();
        server.responder = (r) => FakeResponse.accepted(r.batchIds);
        // No test override for the adapter: only the public config is used.
        SealedTrace.debugOverrides = RuntimeOverrides(
          storage: MemoryStorageAdapter(),
          lifecycle: FakeLifecycle(),
          deviceContext: testDevice,
          connectivity: FakeConnectivity(online: true),
        );
        await SealedTrace.init(
          SealedTraceConfig(
            baseUrl: 'https://logs.example.com/',
            projectId: 'p',
            apiKey: 'k-123',
            publicKeyPem: testPublicKeySpki,
            appName: 'app',
            uploadConfig: UploadConfig(
              httpClientAdapter: server,
              batchSize: 999,
            ),
          ),
        );
        SealedTrace.i('t', 'through a custom adapter');
        final result = await SealedTrace.flush();
        expect(result.outcome, UploadOutcome.success);
        final r = server.requests.single;
        expect(r.uri.toString(), 'https://logs.example.com/api/v1/ingest/logs');
        expect(r.header('X-Api-Key'), 'k-123');
        final events = jsonDecode(await openWire(r.envelopes.single)) as List;
        expect((events.single as Map)['message'], 'through a custom adapter');
      },
    );
  });
}
