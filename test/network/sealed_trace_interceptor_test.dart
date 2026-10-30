import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import '../helpers/fake_ingest.dart';
import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _config = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj-1',
  apiKey: 'sk_sdk_key',
  publicKeyPem: testPublicKeySpki,
  appName: 'app',
);

const _jsonHeaders = {
  'content-type': ['application/json'],
};

/// Everything that must never reach an event.
const _secrets = <String>[
  'abc.def.ghi',
  'req-secret',
  'resp-secret',
  'asha@example.com',
  'sid=xyz',
  'sk_live_REQKEY',
  'tok_in_url',
  '4111 1111 1111 1111',
];

class _Hostile {
  @override
  String toString() => throw StateError('hostile');
}

class _Env {
  final records = <LogRecord>[];
  final server = FakeHttpClientAdapter();

  Dio newDio({SealedTraceInterceptor? interceptor, bool permissive = false}) {
    final dio = Dio(
      BaseOptions(
        validateStatus: permissive ? (_) => true : null,
        followRedirects: !permissive,
      ),
    );
    dio.httpClientAdapter = server;
    if (interceptor != null) dio.interceptors.add(interceptor);
    return dio;
  }

  Future<void> start({SealedTraceConfig config = _config}) async {
    records.clear();
    SealedTrace.debugOverrides = RuntimeOverrides(
      disableUploads: true,
      storage: MemoryStorageAdapter(),
      lifecycle: FakeLifecycle(),
      deviceContext: testDevice,
      sink: (batch) async => records.addAll(batch),
    );
    await SealedTrace.init(config);
  }

  /// Lets the interceptor's deferred logging run, then drains the queue.
  Future<List<LogRecord>> events() async {
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await SealedTrace.flush();
    return records.where((r) => r.tag == 'network').toList();
  }
}

String _everything(LogRecord record) => jsonEncode(record.toJson());

void main() {
  late _Env env;

  setUp(() async {
    await SealedTrace.dispose();
    SealedTrace.onException = null;
    env = _Env();
  });

  tearDown(() async {
    await SealedTrace.dispose();
    SealedTrace.debugOverrides = null;
    SealedTrace.onException = null;
  });

  group('event shape (spec section 8)', () {
    test('a successful call', () async {
      await env.start();
      env.server.enqueue(
        FakeResponse(
          200,
          body: jsonEncode({
            'ok': true,
            'password': 'resp-secret',
            'email': 'asha@example.com',
          }),
          headers: {
            ..._jsonHeaders,
            'set-cookie': ['sid=xyz; HttpOnly'],
            'x-request-id': ['r-1'],
          },
        ),
      );
      final dio = env.newDio(interceptor: SealedTraceInterceptor());

      final response = await dio.post<dynamic>(
        'https://api.example.com/users?token=tok_in_url&page=2',
        data: {
          'user': 'asha',
          'password': 'req-secret',
          'cc': '4111 1111 1111 1111',
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer abc.def.ghi',
            'X-Api-Key': 'sk_live_REQKEY',
            'Accept': 'application/json',
          },
        ),
      );
      expect(response.statusCode, 200);

      final events = await env.events();
      expect(events, hasLength(1));
      final event = events.single;

      expect(event.level, LogLevel.debug);
      expect(event.tag, 'network');
      expect(event.message, matches(RegExp(r'^POST /users -> 200 in \d+ms$')));
      expect(event.metadata.keys.toList(), [
        'method',
        'url',
        'status',
        'durationMs',
        'requestHeaders',
        'responseHeaders',
        'requestBody',
        'responseBody',
        'error',
      ]);
      expect(event.metadata['method'], 'POST');
      expect(
        event.metadata['url'],
        'https://api.example.com/users?token=***&page=2',
      );
      expect(event.metadata['status'], 200);
      expect(event.metadata['durationMs'], isA<int>());
      expect(event.metadata['error'], isNull);

      final reqHeaders = event.metadata['requestHeaders'] as Map;
      expect(reqHeaders['Authorization'], '***');
      expect(reqHeaders['X-Api-Key'], '***');
      expect(reqHeaders['Accept'], 'application/json');
      final resHeaders = event.metadata['responseHeaders'] as Map;
      expect(resHeaders['set-cookie'], '***');
      expect(resHeaders['x-request-id'], 'r-1');

      final reqBody =
          jsonDecode(event.metadata['requestBody'] as String) as Map;
      expect(reqBody['user'], 'asha');
      expect(reqBody['password'], '***');
      final resBody =
          jsonDecode(event.metadata['responseBody'] as String) as Map;
      expect(resBody['ok'], true);
      expect(resBody['password'], '***');

      final everything = _everything(event);
      for (final secret in _secrets) {
        expect(everything, isNot(contains(secret)), reason: secret);
      }
    });

    test('durationMs reflects how long the call took', () async {
      await env.start();
      env.server.enqueue(
        FakeResponse(
          200,
          body: '{}',
          headers: _jsonHeaders,
          delay: const Duration(milliseconds: 120),
        ),
      );
      await env
          .newDio(interceptor: SealedTraceInterceptor())
          .get<dynamic>('https://a.com/slow');
      final event = (await env.events()).single;
      expect(event.metadata['durationMs'] as int, greaterThanOrEqualTo(100));
      expect(event.metadata['durationMs'] as int, lessThan(2000));
      expect(event.message, contains('in ${event.metadata['durationMs']}ms'));
    });

    test('the message uses the masked path only', () async {
      await env.start();
      await env
          .newDio(interceptor: SealedTraceInterceptor())
          .get<dynamic>(
            'https://a.com/users/asha@example.com/profile?token=tok_in_url',
          );
      final event = (await env.events()).single;
      expect(
        event.message,
        'GET /users/***/profile -> 202 in ${event.metadata['durationMs']}ms',
      );
      expect(event.message, isNot(contains('token')));
    });

    test('no body or headers of a kind give null, not a missing key', () async {
      await env.start();
      env.server.enqueue(const FakeResponse(204));
      await env
          .newDio(interceptor: SealedTraceInterceptor())
          .get<dynamic>('https://a.com/none');
      final event = (await env.events()).single;
      expect(event.metadata.containsKey('requestBody'), isTrue);
      expect(event.metadata['requestBody'], isNull);
      expect(event.metadata.containsKey('responseBody'), isTrue);
    });
  });

  group('level mapping through Dio (A: default validateStatus)', () {
    for (final entry in <int, LogLevel>{
      404: LogLevel.warning,
      401: LogLevel.warning,
      429: LogLevel.warning,
      500: LogLevel.error,
      503: LogLevel.error,
    }.entries) {
      test('${entry.key} is ${entry.value.name}', () async {
        await env.start();
        env.server.enqueue(
          FakeResponse(
            entry.key,
            body: '{"detail":"nope"}',
            headers: _jsonHeaders,
          ),
        );
        await expectLater(
          env
              .newDio(interceptor: SealedTraceInterceptor())
              .get<dynamic>('https://a.com/x'),
          throwsA(isA<DioException>()),
        );
        final event = (await env.events()).single;
        expect(event.level, entry.value);
        expect(event.metadata['status'], entry.key);
        expect(event.message, contains('-> ${entry.key} in'));
        expect(event.metadata['error'], startsWith('badResponse'));
        expect(
          event.metadata['responseBody'],
          contains('nope'),
          reason: 'the error body is still captured',
        );
      });
    }
  });

  group('level mapping with a permissive validateStatus', () {
    for (final entry in <int, LogLevel>{
      200: LogLevel.debug,
      204: LogLevel.debug,
      301: LogLevel.debug,
      304: LogLevel.debug,
      404: LogLevel.warning,
      500: LogLevel.error,
    }.entries) {
      test('${entry.key} is ${entry.value.name}', () async {
        await env.start();
        env.server.enqueue(FakeResponse(entry.key));
        final response = await env
            .newDio(interceptor: SealedTraceInterceptor(), permissive: true)
            .get<dynamic>('https://a.com/x');
        expect(response.statusCode, entry.key);
        final event = (await env.events()).single;
        expect(event.level, entry.value);
        expect(event.metadata['status'], entry.key);
        expect(event.metadata['error'], isNull);
      });
    }
  });

  group('calls that threw', () {
    test('a connection error is an error with status ERR', () async {
      await env.start();
      env.server.enqueue(
        const FakeResponse(0, errorType: DioExceptionType.connectionError),
      );
      await expectLater(
        env
            .newDio(interceptor: SealedTraceInterceptor())
            .get<dynamic>(
              'https://a.com/down',
              options: Options(
                headers: {'Authorization': 'Bearer abc.def.ghi'},
              ),
            ),
        throwsA(isA<DioException>()),
      );
      final event = (await env.events()).single;
      expect(event.level, LogLevel.error);
      expect(event.message, matches(RegExp(r'^GET /down -> ERR in \d+ms$')));
      expect(event.metadata['status'], isNull);
      expect(event.metadata['responseHeaders'], isNull);
      expect(event.metadata['responseBody'], isNull);
      expect(event.metadata['error'], startsWith('connectionError'));
      for (final secret in _secrets) {
        expect(_everything(event), isNot(contains(secret)), reason: secret);
      }
      expect(
        _everything(event),
        isNot(contains('failed:')),
        reason: 'the exception message carries headers and must not be logged',
      );
    });

    test('a timeout is an error', () async {
      await env.start();
      env.server.enqueue(
        const FakeResponse(0, errorType: DioExceptionType.receiveTimeout),
      );
      await expectLater(
        env
            .newDio(interceptor: SealedTraceInterceptor())
            .get<dynamic>('https://a.com/t'),
        throwsA(isA<DioException>()),
      );
      final event = (await env.events()).single;
      expect(event.level, LogLevel.error);
      expect(event.metadata['error'], startsWith('receiveTimeout'));
    });

    test('a cancelled call is a warning', () async {
      await env.start();
      env.server.enqueue(
        const FakeResponse(200, delay: Duration(milliseconds: 400)),
      );
      final token = CancelToken();
      final dio = env.newDio(interceptor: SealedTraceInterceptor());
      final pending = dio.get<dynamic>('https://a.com/c', cancelToken: token);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      token.cancel('user left');
      await expectLater(pending, throwsA(isA<DioException>()));

      final event = (await env.events()).single;
      expect(event.level, LogLevel.warning);
      expect(event.message, contains('-> ERR in'));
      expect(event.metadata['error'], startsWith('cancel'));
    });
  });

  group('the request is never altered', () {
    test(
      'status, headers and data are identical with and without it',
      () async {
        await env.start();
        FakeResponse answer() => FakeResponse(
          200,
          body: '{"a":[1,2,{"b":"c"}],"password":"resp-secret"}',
          headers: {
            ..._jsonHeaders,
            'x-extra': ['1'],
          },
        );
        env.server.enqueue(answer());
        env.server.enqueue(answer());

        final plain = await env.newDio().get<dynamic>('https://a.com/same');
        final logged = await env
            .newDio(interceptor: SealedTraceInterceptor())
            .get<dynamic>('https://a.com/same');

        expect(logged.statusCode, plain.statusCode);
        expect(logged.data, plain.data);
        expect(
          logged.data['password'],
          'resp-secret',
          reason: 'the app still sees the real value',
        );
        expect(logged.headers.map, plain.headers.map);
      },
    );

    test(
      'request data and headers are not modified, and nothing is left in extra',
      () async {
        await env.start();
        final data = {
          'password': 'req-secret',
          'list': [1, 2],
        };
        final options = Options(
          headers: {'Authorization': 'Bearer abc.def.ghi'},
        );
        final response = await env
            .newDio(interceptor: SealedTraceInterceptor())
            .post<dynamic>('https://a.com/p', data: data, options: options);

        expect(data, {
          'password': 'req-secret',
          'list': [1, 2],
        });
        expect(options.headers!['Authorization'], 'Bearer abc.def.ghi');
        expect(
          response.requestOptions.extra.keys.where(
            (k) => k.contains('sealed_trace'),
          ),
          isEmpty,
        );
        // The server received the real, unmasked request.
        expect(env.server.requests.single.body, contains('req-secret'));
        expect(
          env.server.requests.single.header('Authorization'),
          'Bearer abc.def.ghi',
        );
      },
    );

    test('hostile data cannot break the call or the interceptor', () async {
      await env.start();
      final interceptor = SealedTraceInterceptor();
      final options = RequestOptions(path: 'https://a.com/h');
      interceptor.onRequest(options, RequestInterceptorHandler());

      final handler = ResponseInterceptorHandler();
      final response = Response<dynamic>(
        requestOptions: options,
        statusCode: 200,
        data: _Hostile(),
      );
      interceptor.onResponse(response, handler);

      // ignore: invalid_use_of_protected_member
      final state = await handler.future;
      expect(
        state.data,
        same(response),
        reason: 'the response is passed on untouched',
      );
      final event = (await env.events()).single;
      expect(event.metadata['responseBody'], '[non-text body]');
    });

    test('an error with no response is passed on untouched', () async {
      await env.start();
      final interceptor = SealedTraceInterceptor();
      final options = RequestOptions(path: 'https://a.com/e');
      interceptor.onRequest(options, RequestInterceptorHandler());
      final error = DioException(
        requestOptions: options,
        type: DioExceptionType.unknown,
      );
      final handler = ErrorInterceptorHandler();
      interceptor.onError(error, handler);
      // Dio completes the error handler's future with the state as an error.
      Object? thrown;
      try {
        // ignore: invalid_use_of_protected_member
        await handler.future;
      } on Object catch (e) {
        thrown = e;
      }
      expect(thrown, isNotNull);
      // ignore: avoid_dynamic_calls
      expect((thrown as dynamic).data, same(error));
      expect(
        (await env.events()).single.metadata['error'],
        startsWith('unknown'),
      );
    });
  });

  group('when nothing may be logged', () {
    test('before init the interceptor is a pure pass-through', () async {
      final dio = env.newDio(interceptor: SealedTraceInterceptor());
      final response = await dio.get<dynamic>('https://a.com/early');
      expect(response.statusCode, 202);
      expect(response.requestOptions.extra, isEmpty);
      expect(env.records, isEmpty);
    });

    test('a disabled SDK logs nothing', () async {
      await env.start(config: _config.copyWith(enabled: false));
      await env
          .newDio(interceptor: SealedTraceInterceptor())
          .get<dynamic>('https://a.com/x');
      expect(await env.events(), isEmpty);
    });

    test(
      'NetworkLogConfig(enabled: false) logs nothing and stamps nothing',
      () async {
        await env.start(
          config: _config.copyWith(
            networkLogConfig: const NetworkLogConfig(enabled: false),
          ),
        );
        final response = await env
            .newDio(interceptor: SealedTraceInterceptor())
            .get<dynamic>('https://a.com/x');
        expect(response.requestOptions.extra, isEmpty);
        expect(await env.events(), isEmpty);
      },
    );

    test('an explicit interceptor config overrides the SDK\'s', () async {
      await env.start(
        config: _config.copyWith(
          networkLogConfig: const NetworkLogConfig(enabled: false),
        ),
      );
      await env
          .newDio(
            interceptor: SealedTraceInterceptor(
              config: const NetworkLogConfig(),
            ),
          )
          .get<dynamic>('https://a.com/x');
      expect(await env.events(), hasLength(1));

      env.records.clear();
      await env
          .newDio(
            interceptor: SealedTraceInterceptor(
              config: const NetworkLogConfig(enabled: false),
            ),
          )
          .get<dynamic>('https://a.com/y');
      expect(await env.events(), isEmpty);
    });

    test(
      'disposing the SDK mid-request logs nothing and breaks nothing',
      () async {
        await env.start();
        env.server.enqueue(
          const FakeResponse(200, delay: Duration(milliseconds: 100)),
        );
        final pending = env
            .newDio(interceptor: SealedTraceInterceptor())
            .get<dynamic>('https://a.com/mid');
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await SealedTrace.dispose();
        final response = await pending;
        expect(response.statusCode, 200);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(env.records.where((r) => r.tag == 'network'), isEmpty);
      },
    );

    test('the SDK minLevel drops the event before any body work', () async {
      await env.start(config: _config.copyWith(minLevel: LogLevel.warning));
      await env
          .newDio(interceptor: SealedTraceInterceptor())
          .get<dynamic>('https://a.com/ok');
      expect(await env.events(), isEmpty);
      expect(
        SealedTrace.debugBuiltEvents,
        0,
        reason: 'no record was even built',
      );
      expect(SealedTrace.diagnostics.eventsDroppedLevel, 1);

      env.server.enqueue(const FakeResponse(404));
      await expectLater(
        env
            .newDio(interceptor: SealedTraceInterceptor())
            .get<dynamic>('https://a.com/missing'),
        throwsA(isA<DioException>()),
      );
      expect(await env.events(), hasLength(1));
    });
  });

  group('capture settings', () {
    test(
      'request and response bodies can be switched off separately',
      () async {
        await env.start(
          config: _config.copyWith(
            networkLogConfig: const NetworkLogConfig(captureRequestBody: false),
          ),
        );
        env.server.enqueue(
          FakeResponse(200, body: '{"k":1}', headers: _jsonHeaders),
        );
        await env
            .newDio(interceptor: SealedTraceInterceptor())
            .post<dynamic>('https://a.com/x', data: {'a': 1});
        var event = (await env.events()).single;
        expect(event.metadata['requestBody'], isNull);
        expect(event.metadata['responseBody'], '{"k":1}');

        await SealedTrace.dispose();
        await env.start(
          config: _config.copyWith(
            networkLogConfig: const NetworkLogConfig(
              captureResponseBody: false,
            ),
          ),
        );
        env.server.enqueue(
          FakeResponse(200, body: '{"k":1}', headers: _jsonHeaders),
        );
        await env
            .newDio(interceptor: SealedTraceInterceptor())
            .post<dynamic>('https://a.com/x', data: {'a': 1});
        event = (await env.events()).single;
        expect(event.metadata['requestBody'], '{"a":1}');
        expect(event.metadata['responseBody'], isNull);
      },
    );

    test('maxBodyChars truncates both sides', () async {
      await env.start(
        config: _config.copyWith(
          networkLogConfig: const NetworkLogConfig(maxBodyChars: 10),
        ),
      );
      env.server.enqueue(
        FakeResponse(
          200,
          body: 'x' * 50,
          headers: const {
            'content-type': ['text/plain'],
          },
        ),
      );
      await env
          .newDio(interceptor: SealedTraceInterceptor())
          .post<dynamic>(
            'https://a.com/x',
            data: 'y' * 40,
            options: Options(contentType: 'text/plain'),
          );
      final event = (await env.events()).single;
      expect(event.metadata['requestBody'], '${'y' * 10}…[truncated 30 chars]');
      expect(
        event.metadata['responseBody'],
        '${'x' * 10}…[truncated 40 chars]',
      );
    });

    test('many headers never push the other fields out of the event', () async {
      await env.start();
      env.server.enqueue(
        FakeResponse(
          200,
          body: '{"fine":true}',
          headers: {
            ..._jsonHeaders,
            for (var i = 0; i < 60; i++) 'x-res-$i': ['v$i'],
          },
        ),
      );
      await env
          .newDio(interceptor: SealedTraceInterceptor())
          .get<dynamic>(
            'https://a.com/many',
            options: Options(
              headers: {for (var i = 0; i < 60; i++) 'x-req-$i': 'v$i'},
            ),
          );
      final event = (await env.events()).single;
      final req = event.metadata['requestHeaders'] as Map;
      final res = event.metadata['responseHeaders'] as Map;
      expect(req.length, lessThanOrEqualTo(26));
      expect(res.length, lessThanOrEqualTo(26));
      expect(req['_truncated'], contains('more headers'));
      expect(res['_truncated'], contains('more headers'));
      expect(
        event.metadata['responseBody'],
        '{"fine":true}',
        reason: 'later fields survive the metadata entry budget',
      );
      expect(event.metadata['error'], isNull);
      expect(event.metadata.keys, hasLength(9));
    });
  });

  group('host allowlist and ingest exclusion', () {
    test('only allowed hosts are logged', () async {
      await env.start(
        config: _config.copyWith(
          networkLogConfig: const NetworkLogConfig(
            hostAllowlist: ['api.example.com', '*.cdn.example.com'],
          ),
        ),
      );
      final dio = env.newDio(interceptor: SealedTraceInterceptor());
      await dio.get<dynamic>('https://api.example.com/a');
      await dio.get<dynamic>('https://other.example.org/b');
      await dio.get<dynamic>('https://img.cdn.example.com/c');
      await dio.get<dynamic>(
        'https://cdn.example.com/d',
      ); // the apex is not matched
      final events = await env.events();
      expect(events.map((e) => (e.metadata['url'] as String)), [
        'https://api.example.com/a',
        'https://img.cdn.example.com/c',
      ]);
    });

    test('the SDK\'s own ingest endpoint is never logged', () async {
      await env.start();
      final dio = env.newDio(interceptor: SealedTraceInterceptor());
      await dio.post<dynamic>(
        'https://logs.example.com/api/v1/ingest/logs',
        data: {'envelopes': <Object>[]},
      );
      expect(await env.events(), isEmpty);

      await dio.get<dynamic>('https://logs.example.com/api/v1/projects');
      await dio.post<dynamic>('https://other.example.com/api/v1/ingest/logs');
      final events = await env.events();
      expect(events, hasLength(2));
    });

    test(
      'an empty allowlist logs every host but the ingest endpoint',
      () async {
        await env.start();
        final dio = env.newDio(interceptor: SealedTraceInterceptor());
        for (final host in ['a.com', 'b.org', 'localhost:3000']) {
          await dio.get<dynamic>('http://$host/x');
        }
        expect(await env.events(), hasLength(3));
      },
    );
  });

  group('several Dio instances and concurrent calls', () {
    test('one interceptor on two Dios keeps each call separate', () async {
      await env.start();
      final shared = SealedTraceInterceptor();
      final first = env.newDio(interceptor: shared);
      final second = env.newDio(interceptor: shared);
      env.server
        ..enqueue(const FakeResponse(200, delay: Duration(milliseconds: 160)))
        ..enqueue(const FakeResponse(200, delay: Duration(milliseconds: 10)));

      await Future.wait([
        first.get<dynamic>('https://a.com/slow'),
        second.get<dynamic>('https://a.com/fast'),
      ]);

      final events = await env.events();
      expect(events, hasLength(2));
      final byPath = {for (final e in events) (e.metadata['url'] as String): e};
      expect(
        byPath['https://a.com/slow']!.metadata['durationMs'] as int,
        greaterThanOrEqualTo(140),
      );
      expect(
        byPath['https://a.com/fast']!.metadata['durationMs'] as int,
        lessThan(120),
      );
    });

    test(
      'the same interceptor on one Dio handles many parallel calls',
      () async {
        await env.start();
        final dio = env.newDio(interceptor: SealedTraceInterceptor());
        await Future.wait([
          for (var i = 0; i < 20; i++) dio.get<dynamic>('https://a.com/p/$i'),
        ]);
        final events = await env.events();
        expect(events, hasLength(20));
        expect(events.map((e) => e.message.split(' ')[1]).toSet(), {
          for (var i = 0; i < 20; i++) '/p/$i',
        });
      },
    );
  });

  test('the events pass through sealing and storage like any other', () async {
    await env.start();
    await env
        .newDio(interceptor: SealedTraceInterceptor())
        .get<dynamic>('https://a.com/x');
    await env.events();
    expect(SealedTrace.diagnostics.eventsAccepted, 1);
    expect(SealedTrace.diagnostics.internalExceptions, 0);
  });

  test('timing: the interceptor adds little to a request', () async {
    await env.start();
    env.server.fallback = FakeResponse(
      200,
      body: '{"k":"v"}',
      headers: _jsonHeaders,
    );
    const calls = 200;

    Future<int> run(Dio dio) async {
      final watch = Stopwatch()..start();
      for (var i = 0; i < calls; i++) {
        await dio.get<dynamic>('https://a.com/x?i=$i');
      }
      return watch.elapsedMicroseconds;
    }

    final plain = await run(env.newDio());
    final logged = await run(env.newDio(interceptor: SealedTraceInterceptor()));
    // ignore: avoid_print
    print(
      'Dio request: ${(plain / calls).toStringAsFixed(0)} µs plain, '
      '${(logged / calls).toStringAsFixed(0)} µs with the interceptor',
    );
    expect(logged / calls, lessThan(20000));
  });
}
