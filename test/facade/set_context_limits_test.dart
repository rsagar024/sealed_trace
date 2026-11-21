import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/event/context_limits.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _config = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj',
  apiKey: 'key',
  publicKeyPem: testPublicKeySpki,
  appName: 'app',
  // Readable names, so a spoofed userName would be visible if it got through.
  maskConfig: MaskConfig(maskUserName: false),
);

void main() {
  group('L8: ContextLimits.merge', () {
    test('at most 100 keys; the rest are dropped and counted', () {
      final context = <String, dynamic>{};
      final dropped = ContextLimits.merge(context, {
        for (var i = 0; i < 150; i++) 'k$i': i,
      });
      expect(context, hasLength(100));
      expect(dropped, 50);
      expect(context.containsKey('k99'), isTrue);
      expect(context.containsKey('k100'), isFalse);
    });

    test('limits hold across calls, and existing keys can still change', () {
      final context = <String, dynamic>{};
      for (var call = 0; call < 10; call++) {
        ContextLimits.merge(context, {
          for (var i = 0; i < 20; i++) 'c${call}_$i': i,
        });
      }
      expect(context, hasLength(100));
      expect(ContextLimits.merge(context, {'c0_0': 'updated'}), 0);
      expect(context['c0_0'], 'updated');
      expect(ContextLimits.merge(context, {'brand-new': 1}), 1);
    });

    test('a value past 16 KB is dropped and the old one kept', () {
      final context = <String, dynamic>{'note': 'small'};
      final dropped = ContextLimits.merge(context, {'note': 'x' * 20000});
      expect(dropped, 1);
      expect(context['note'], 'small');
    });

    test('the total size is bounded across many medium values', () {
      final context = <String, dynamic>{};
      var dropped = 0;
      for (var i = 0; i < 40; i++) {
        dropped += ContextLimits.merge(context, {'big$i': 'y' * 1000});
      }
      final chars = context.entries.fold<int>(
        0,
        (n, e) => n + e.key.length + (e.value as String).length,
      );
      expect(chars, lessThanOrEqualTo(ContextLimits.maxChars));
      expect(dropped, greaterThan(0));
    });

    test('reserved keys are ignored and not counted', () {
      final context = <String, dynamic>{};
      final dropped = ContextLimits.merge(context, {
        'userName': 'Spoof',
        'userDisplayName': 'Spoof',
        'platform': 'evil-os',
        'plan': 'pro',
      });
      expect(context, {'plan': 'pro'});
      expect(dropped, 0);
    });
  });

  group('L8: through the facade', () {
    late List<LogRecord> sink;
    late List<Object> reported;

    setUp(() async {
      await SealedTrace.dispose();
      sink = [];
      reported = [];
      SealedTrace.onException = (e, _) => reported.add(e);
      SealedTrace.debugOverrides = RuntimeOverrides(
        disableUploads: true,
        storage: MemoryStorageAdapter(),
        lifecycle: FakeLifecycle(),
        deviceContext: testDevice,
        sink: (batch) async => sink.addAll(batch),
      );
      await SealedTrace.init(_config);
    });

    tearDown(() async {
      await SealedTrace.dispose();
      SealedTrace.debugOverrides = null;
      SealedTrace.onException = null;
    });

    Future<LogRecord> logOne() async {
      SealedTrace.i('t', 'm');
      await SealedTrace.flush();
      return sink.last;
    }

    test('setContext cannot set userName, even without setUser', () async {
      SealedTrace.setContext({'userName': 'Spoofed Name', 'plan': 'pro'});
      final record = await logOne();
      expect(record.ctx.containsKey('userName'), isFalse);
      expect(record.ctx['plan'], 'pro');
    });

    test('setUser\'s name wins over a userName from setContext', () async {
      SealedTrace.setUser('u1', name: 'Real Name');
      SealedTrace.setContext({'userName': 'Spoofed Name'});
      final record = await logOne();
      expect(record.ctx['userName'], 'Real Name');
    });

    test('overflow is counted, and reported once per session', () async {
      for (var call = 0; call < 3; call++) {
        SealedTrace.setContext({for (var i = 0; i < 60; i++) 'k${call}_$i': i});
      }
      final record = await logOne();
      final extra = record.ctx.keys.where((k) => k.startsWith('k'));
      expect(extra, hasLength(100));
      expect(SealedTrace.diagnostics.contextEntriesDropped, 80);
      expect(reported, hasLength(1));
      expect(reported.single.toString(), contains('setContext dropped'));
    });
  });
}
