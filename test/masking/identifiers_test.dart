import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/masking/pseudonym.dart';
import 'package:sealed_trace/src/platform/user_agent.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _config = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj-1',
  apiKey: 'key',
  publicKeyPem: testPublicKeySpki,
  appName: 'app',
);

void main() {
  group('L12: pseudonyms', () {
    test('match an independent HMAC-SHA256 (computed with Python)', () {
      expect(
        Pseudonym.of('device-123', projectId: 'proj-1'),
        'p_Pgu2R-qcGtowQrM1SZjWWQ',
      );
      expect(
        Pseudonym.of('user-42', projectId: 'proj-1'),
        'p_9o10s1z3-likL5S1lVMjHw',
      );
    });

    test('stable, 24 characters, and scoped to the project', () {
      final a = Pseudonym.of('device-123', projectId: 'proj-1');
      expect(Pseudonym.of('device-123', projectId: 'proj-1'), a);
      expect(a, hasLength(24));
      expect(a, matches(RegExp(r'^p_[A-Za-z0-9_-]{22}$')));
      expect(Pseudonym.of('device-123', projectId: 'proj-2'), isNot(a));
      expect(Pseudonym.of('device-124', projectId: 'proj-1'), isNot(a));
      expect(a, isNot(contains('device')));
    });
  });

  group('L12: coarse web user agent', () {
    final cases = <String, String>{
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, '
              'like Gecko) Chrome/157.0.7300.12 Safari/537.36':
          'Chrome 157 on Windows',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, '
              'like Gecko) Chrome/140.0.0.0 Safari/537.36 Edg/140.0.3485.54':
          'Edge 140 on Windows',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:131.0) '
              'Gecko/20100101 Firefox/131.0':
          'Firefox 131 on macOS',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 '
              '(KHTML, like Gecko) Version/18.1 Safari/605.1.15':
          'Safari 18 on macOS',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 '
              'Mobile/15E148 Safari/604.1':
          'Safari 18 on iOS',
      'Mozilla/5.0 (iPhone; CPU iPhone OS 18_1 like Mac OS X) '
              'AppleWebKit/605.1.15 (KHTML, like Gecko) CriOS/130.0.6723.90 '
              'Mobile/15E148 Safari/604.1':
          'Chrome 130 on iOS',
      'Mozilla/5.0 (Linux; Android 15; Pixel 8 Build/AP3A.241005.015) '
              'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 '
              'Mobile Safari/537.36':
          'Chrome 130 on Android',
      'Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, '
              'like Gecko) SamsungBrowser/26.0 Chrome/122.0.0.0 Mobile '
              'Safari/537.36':
          'Samsung Internet 26 on Android',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, '
              'like Gecko) Chrome/129.0.0.0 Safari/537.36 OPR/114.0.0.0':
          'Opera 114 on Windows',
      'Mozilla/5.0 (X11; CrOS x86_64 14541.0.0) AppleWebKit/537.36 (KHTML, '
              'like Gecko) Chrome/130.0.0.0 Safari/537.36':
          'Chrome 130 on ChromeOS',
      'Mozilla/5.0 (X11; Linux x86_64; rv:131.0) Gecko/20100101 Firefox/131.0':
          'Firefox 131 on Linux',
      '': 'web',
      'SomeBot/1.0': 'web',
    };
    cases.forEach((agent, expected) {
      test(expected, () => expect(coarseUserAgent(agent), expected));
    });

    test('device model and build details are dropped', () {
      final out = coarseUserAgent(
        'Mozilla/5.0 (Linux; Android 15; Pixel 8 Build/AP3A.241005.015) '
        'AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.6723.90 '
        'Mobile Safari/537.36',
      );
      for (final detail in ['Pixel', 'AP3A', '6723', 'Mozilla']) {
        expect(out, isNot(contains(detail)), reason: detail);
      }
    });
  });

  group('L12: through the facade', () {
    late List<LogRecord> sink;

    Future<void> start(SealedTraceConfig config) async {
      await SealedTrace.dispose();
      sink = [];
      SealedTrace.debugOverrides = RuntimeOverrides(
        disableUploads: true,
        storage: MemoryStorageAdapter(),
        lifecycle: FakeLifecycle(),
        deviceContext: testDevice,
        sink: (batch) async => sink.addAll(batch),
      );
      await SealedTrace.init(config);
    }

    tearDown(() async {
      await SealedTrace.dispose();
      SealedTrace.debugOverrides = null;
    });

    test('pseudonym is null before init, then project-scoped', () async {
      await SealedTrace.dispose();
      expect(SealedTrace.pseudonym('device-123'), isNull);
      await start(_config);
      expect(SealedTrace.pseudonym('device-123'), 'p_Pgu2R-qcGtowQrM1SZjWWQ');
    });

    test('userId is sent as given by default', () async {
      await start(_config);
      SealedTrace.setUser('user-42');
      SealedTrace.i('t', 'm');
      await SealedTrace.flush();
      expect(sink.single.userId, 'user-42');
    });

    test('pseudonymizeUserId sends only the pseudonym', () async {
      await start(
        _config.copyWith(
          maskConfig: const MaskConfig(pseudonymizeUserId: true),
        ),
      );
      SealedTrace.setUser('user-42');
      SealedTrace.i('t', 'm');
      SealedTrace.setUser(null);
      SealedTrace.i('t', 'after logout');
      await SealedTrace.flush();
      expect(sink[0].userId, 'p_9o10s1z3-likL5S1lVMjHw');
      expect('${sink[0].toJson()}', isNot(contains('user-42')));
      expect(sink[1].userId, isNull);
    });

    test('the option takes part in copyWith and equality', () {
      const on = MaskConfig(pseudonymizeUserId: true);
      expect(const MaskConfig().pseudonymizeUserId, isFalse);
      expect(const MaskConfig().copyWith(pseudonymizeUserId: true), on);
      expect(on, isNot(const MaskConfig()));
    });
  });
}
