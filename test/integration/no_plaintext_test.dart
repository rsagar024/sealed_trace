@TestOn('vm')
library;

// Security regression (P9.1): marker secrets logged through the public API
// must not appear anywhere the device keeps or emits data in the clear: the
// SQLite files, the page-exit spill, onException messages, the diagnostics,
// the SDK's own log lines, or the request headers and body. The API key must
// not leak into errors either.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:dio/dio.dart' show DioExceptionType;
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/platform/lifecycle_binding.dart';
import 'package:sealed_trace/src/storage/envelope_spill.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/fake_connectivity.dart';
import '../helpers/fake_ingest.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _apiKey = 'sk_live_NEVER-IN-LOGS-7731';

/// Not PII, so masking keeps it: only encryption can hide it.
const _sentinel = 'sentinel-7f3a-plain';

/// Markers that masking must remove before anything is stored.
const _markers = <String>[
  'marker.person@example.com',
  '98765 43210',
  '4111 1111 1111 1111',
  'hunter2-marker-pass',
];

/// A credential in manually logged metadata under a key the default list
/// does not contain (`Authorization`, A53). Masking keeps it by design, so
/// only encryption protects it; the README tells apps to add the key.
const _bearer = 'Bearer marker-token-abc';

void main() {
  late Directory dir;
  final printed = <String>[];
  final originalDebugPrint = debugPrint;

  setUp(() async {
    await SealedTrace.dispose();
    dir = await Directory.systemTemp.createTemp('sealed_trace_noplain_');
    printed.clear();
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) printed.add(message);
    };
  });

  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.debugOverrides = null;
    SealedTrace.onException = null;
    debugPrint = originalDebugPrint;
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // The database isolate may still hold the file on Windows.
    }
  });

  test('no marker reaches the database files, spill, errors, diagnostics, '
      'internal logs or the wire in clear text', () async {
    final errors = <String>[];
    final server = FakeHttpClientAdapter(
      const FakeResponse(0, errorType: DioExceptionType.connectionError),
    );
    final spill = MemoryEnvelopeSpill();
    final lifecycle = FakeLifecycle();
    SealedTrace.onException = (e, s) => errors.add('$e\n$s');
    SealedTrace.debugOverrides = RuntimeOverrides(
      lifecycle: lifecycle,
      deviceContext: testDevice,
      clock: FakeClock(DateTime.utc(2026, 1, 2)),
      httpClientAdapter: server,
      connectivity: FakeConnectivity(online: true),
      random: Random(3),
      envelopeSpill: spill,
    );
    await SealedTrace.init(
      SealedTraceConfig(
        baseUrl: 'https://logs.example.com',
        projectId: 'proj-sec',
        apiKey: _apiKey,
        publicKeyPem: testPublicKeySpki,
        appName: 'app',
        databaseDirectory: dir.path,
        verboseInternalLogs: true,
      ),
    );
    expect(SealedTrace.isInitialized, isTrue);

    SealedTrace.setUser('user-1', name: 'Asha Marker');
    for (var i = 0; i < 10; i++) {
      SealedTrace.e(
        'auth',
        'login for marker.person@example.com, phone +91 98765 43210 '
            '$_sentinel',
        error: StateError('card 4111 1111 1111 1111 declined'),
        meta: {
          'password': 'hunter2-marker-pass',
          'headers': {'Authorization': 'Bearer marker-token-abc'},
        },
      );
    }
    await SealedTrace.flush(); // fails: rows stay on disk
    // Leave some events in the queue for the page-exit spill.
    SealedTrace.i('auth', 'spilled marker.person@example.com');
    lifecycle.emit(AppLifecycle.detached);
    await pumpEventQueue();
    await SealedTrace.flush();
    final diagnostics = SealedTrace.diagnostics;
    await SealedTrace.dispose();

    // Sanity: data really is on disk, the network was really tried.
    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('sealed_trace.db'))
        .toList();
    expect(files, isNotEmpty);
    expect(server.requests, isNotEmpty);

    final haystacks = <String, String>{
      for (final f in files)
        p.basename(f.path): latin1.decode(f.readAsBytesSync()),
      'onException': errors.join('\n'),
      'internal logs': printed.join('\n'),
      'diagnostics': '$diagnostics ${diagnostics.uploadAttempts}',
      for (final (i, r) in server.requests.indexed) ...{
        'request $i headers': jsonEncode(
          r.headers.map((k, v) => MapEntry(k, '$v')),
        ),
        'request $i body': r.body,
      },
      for (final e in spill.readAll())
        'spill ${e.batchId}': encodeSpilledEnvelope(e),
    };
    for (final entry in haystacks.entries) {
      for (final marker in [..._markers, 'Asha Marker', _sentinel, _bearer]) {
        expect(
          entry.value.contains(marker),
          isFalse,
          reason: '"$marker" found in ${entry.key}',
        );
      }
    }
    // The api key goes only into the X-Api-Key header.
    for (final entry in haystacks.entries) {
      if (entry.key.endsWith('headers')) continue;
      expect(
        entry.value.contains(_apiKey),
        isFalse,
        reason: 'api key found in ${entry.key}',
      );
    }

    // And the data is still there, encrypted: the server-side key opens it.
    final opened = [
      for (final r in server.requests)
        for (final e in r.envelopes) await openWire(e),
    ].join('\n');
    expect(opened, contains('***'));
    expect(opened, contains(_sentinel)); // it was logged, just never in clear
    expect(_markers.where(opened.contains).toList(), isEmpty);
    // Documented gap: not masked under the default key list, still encrypted.
    expect(opened, contains(_bearer));
  });

  test(
    'adding "authorization" to extraKeys masks a logged bearer token',
    () async {
      final server = FakeHttpClientAdapter();
      server.responder = (r) => FakeResponse.accepted(r.batchIds);
      SealedTrace.debugOverrides = RuntimeOverrides(
        lifecycle: FakeLifecycle(),
        deviceContext: testDevice,
        clock: FakeClock(DateTime.utc(2026, 1, 2)),
        httpClientAdapter: server,
        connectivity: FakeConnectivity(online: true),
      );
      await SealedTrace.init(
        SealedTraceConfig(
          baseUrl: 'https://logs.example.com',
          projectId: 'proj-sec',
          apiKey: _apiKey,
          publicKeyPem: testPublicKeySpki,
          appName: 'app',
          databaseDirectory: dir.path,
          maskConfig: const MaskConfig(extraKeys: ['authorization']),
        ),
      );
      SealedTrace.i(
        'http',
        'manual',
        meta: {
          'headers': {'Authorization': _bearer},
        },
      );
      await SealedTrace.flush();
      final opened = await openWire(server.requests.last.envelopes.single);
      expect(opened, isNot(contains(_bearer)));
      expect(opened, contains('"Authorization":"***"'));
    },
  );
}
