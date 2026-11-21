import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/config/config_validator.dart';
import 'package:sealed_trace/src/facade/runtime_overrides.dart';
import 'package:sealed_trace/src/storage/memory_storage_adapter.dart';

import '../helpers/fakes.dart';
import '../helpers/test_keys.dart';

const _valid = SealedTraceConfig(
  baseUrl: 'https://logs.example.com',
  projectId: 'proj',
  apiKey: 'key',
  publicKeyPem: testPublicKeySpki,
  appName: 'app',
);

void main() {
  group('L2: timing and retention floors', () {
    test('the defaults are already safe: same instance, nothing reported', () {
      final out = ConfigValidator.normalize(_valid);
      expect(identical(out.config, _valid), isTrue);
      expect(out.adjusted, isEmpty);
    });

    test('zero and negative upload timings are raised to their floors', () {
      final out = ConfigValidator.normalize(
        _valid.copyWith(
          uploadConfig: const UploadConfig(
            interval: Duration.zero,
            backoffBase: Duration.zero,
            requestTimeout: Duration(milliseconds: -5),
            sizeThresholdEvents: 0,
            sizeThresholdBytes: -1,
          ),
        ),
      );
      final u = out.config.uploadConfig;
      expect(u.interval, const Duration(seconds: 30));
      expect(u.backoffBase, const Duration(seconds: 1));
      expect(u.requestTimeout, const Duration(seconds: 1));
      // 0 or less disables the size triggers, so those are left alone.
      expect(u.sizeThresholdEvents, 0);
      expect(u.sizeThresholdBytes, -1);
      expect(out.adjusted, [
        'uploadConfig.interval 0:00:00.000000 -> 0:00:30.000000',
        'uploadConfig.backoffBase 0:00:00.000000 -> 0:00:01.000000',
        'uploadConfig.requestTimeout -0:00:00.005000 -> 0:00:01.000000',
      ]);
    });

    test('negative or zero retention limits are raised', () {
      final out = ConfigValidator.normalize(
        _valid.copyWith(
          retentionConfig: const RetentionConfig(
            maxEvents: -10,
            maxAgeDays: 0,
            maxSizeBytes: -1,
            purgeInterval: Duration.zero,
            deadLetterTtl: Duration(days: -1),
          ),
        ),
      );
      final r = out.config.retentionConfig;
      expect(r.maxEvents, 1);
      expect(r.maxAgeDays, 1);
      expect(r.maxSizeBytes, 64 * 1024);
      expect(r.purgeInterval, const Duration(minutes: 1));
      expect(r.deadLetterTtl, Duration.zero);
      expect(out.adjusted, hasLength(5));
      expect(out.adjusted.first, 'retentionConfig.maxEvents -10 -> 1');
    });

    test('values at or above a floor are kept exactly', () {
      final config = _valid.copyWith(
        uploadConfig: const UploadConfig(
          interval: Duration(seconds: 30),
          backoffBase: Duration(seconds: 1),
          requestTimeout: Duration(seconds: 1),
        ),
        retentionConfig: const RetentionConfig(
          maxEvents: 1,
          maxAgeDays: 1,
          maxSizeBytes: 64 * 1024,
          purgeInterval: Duration(minutes: 1),
          deadLetterTtl: Duration.zero,
        ),
      );
      final out = ConfigValidator.normalize(config);
      expect(identical(out.config, config), isTrue);
      expect(out.adjusted, isEmpty);
    });

    test('the existing batchSize and maxAttempts clamps are reported too', () {
      final out = ConfigValidator.normalize(
        _valid.copyWith(
          uploadConfig: const UploadConfig(batchSize: 500, maxAttempts: 0),
        ),
      );
      expect(out.adjusted, [
        'uploadConfig.batchSize 500 -> 50',
        'uploadConfig.maxAttempts 0 -> 1',
      ]);
    });

    test('clamp still returns the normalized config', () {
      final c = ConfigValidator.clamp(
        _valid.copyWith(
          uploadConfig: const UploadConfig(interval: Duration.zero),
        ),
      );
      expect(c.uploadConfig.interval, const Duration(seconds: 30));
    });
  });

  group('L2: init reports adjustments without failing', () {
    final printed = <String>[];
    late DebugPrintCallback original;

    setUp(() async {
      await SealedTrace.dispose();
      printed.clear();
      original = debugPrint;
      debugPrint = (message, {wrapWidth}) => printed.add('$message');
      SealedTrace.debugOverrides = RuntimeOverrides(
        disableUploads: true,
        storage: MemoryStorageAdapter(),
        lifecycle: FakeLifecycle(),
        deviceContext: testDevice,
      );
    });

    tearDown(() async {
      debugPrint = original;
      await SealedTrace.dispose();
      SealedTrace.debugOverrides = null;
      SealedTrace.onException = null;
    });

    test('init succeeds, counts each value and prints them', () async {
      final reported = <Object>[];
      SealedTrace.onException = (error, _) => reported.add(error);
      await SealedTrace.init(
        _valid.copyWith(
          uploadConfig: const UploadConfig(
            interval: Duration.zero,
            backoffBase: Duration.zero,
          ),
          retentionConfig: const RetentionConfig(purgeInterval: Duration.zero),
        ),
      );
      expect(SealedTrace.isInitialized, isTrue);
      expect(SealedTrace.diagnostics.configValuesAdjusted, 3);
      expect(SealedTrace.diagnostics.internalExceptions, 0);
      expect(reported, isEmpty, reason: 'a correction is not an error');
      expect(
        printed.where((l) => l.contains('config values adjusted')),
        hasLength(1),
      );
      expect(printed.join('\n'), contains('uploadConfig.interval'));
    });

    test('with verbose internal logs it goes through the logger', () async {
      await SealedTrace.init(
        _valid.copyWith(
          verboseInternalLogs: true,
          uploadConfig: const UploadConfig(interval: Duration.zero),
        ),
      );
      expect(
        printed.where((l) => l.startsWith('[sealed_trace] config values')),
        hasLength(1),
      );
    });

    test('a safe config reports nothing', () async {
      await SealedTrace.init(_valid);
      expect(SealedTrace.diagnostics.configValuesAdjusted, 0);
      expect(printed.where((l) => l.contains('adjusted')), isEmpty);
    });
  });
}
