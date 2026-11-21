import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/crypto/aes_gcm_platform.dart';
import 'package:sealed_trace/src/crypto/crypto_backend.dart';
import 'package:sealed_trace/src/masking/masking_engine.dart';
import 'package:sealed_trace/src/network/body_sanitizer.dart';

/// A JSON text body of about [chars] characters with secrets in it.
String _bigJson(int chars) {
  final items = <Map<String, dynamic>>[];
  var i = 0;
  while (jsonEncode(items).length < chars) {
    items.add({
      'id': i,
      'email': 'user$i@example.com',
      'memberNo': 'M-$i',
      'note': 'order ORD-${(100000 + i)} ok',
      'password': 'pw-$i',
    });
    i++;
  }
  return jsonEncode({'items': items});
}

void main() {
  group('M5: capture caps', () {
    test('caps are lowered', () {
      expect(BodySanitizer.maxCaptureChars, 256 * 1024);
      expect(BodySanitizer.maxCaptureNodes, 50000);
    });

    test('a body over the cap is not parsed', () {
      final sanitizer = BodySanitizer(
        MaskingEngine(const MaskConfig()),
        maxBodyChars: 20000,
      );
      final out = sanitizer.sanitize('{"a":"${'x' * 300000}"}');
      expect(out, startsWith('[body too large:'));
    });
  });

  group('M5: large bodies are sanitized in a background isolate', () {
    late MaskingEngine engine;
    late BodySanitizer sanitizer;

    setUp(() {
      engine = MaskingEngine(const MaskConfig());
      sanitizer = BodySanitizer(engine, maxBodyChars: 1 << 20);
    });

    test('small bodies stay synchronous', () {
      final out = sanitizer.sanitizeOffloaded(
        '{"password":"x"}',
        contentType: 'application/json',
      );
      expect(out, isA<String>());
      expect(out, '{"password":"***"}');
    });

    test('a large text body goes to an isolate and matches inline', () async {
      final body = _bigJson(100 * 1024);
      final offloaded = sanitizer.sanitizeOffloaded(
        body,
        contentType: 'application/json',
      );
      expect(offloaded, isA<Future<String?>>());
      final result = await offloaded;
      expect(result, sanitizer.sanitize(body, contentType: 'application/json'));
      expect(result, isNot(contains('@example.com')));
      expect(result, isNot(contains('pw-1')));
    });

    test('a large structured body goes to an isolate too', () async {
      final data = jsonDecode(_bigJson(100 * 1024)) as Map<String, dynamic>;
      final offloaded = sanitizer.sanitizeOffloaded(data);
      expect(offloaded, isA<Future<String?>>());
      expect(await offloaded, sanitizer.sanitize(data));
    });

    test('keys and patterns added at runtime apply in the isolate', () async {
      engine
        ..addKeys(['MEMBER_NO'])
        ..addPattern(RegExp(r'ORD-\d{6}'));
      final result = await sanitizer.sanitizeOffloaded(
        _bigJson(100 * 1024),
        contentType: 'application/json',
      );
      expect(result, isNot(contains('M-1"')));
      expect(result, isNot(contains('ORD-100001')));
    });

    test('a body that cannot be sent is sanitized inline instead', () async {
      final port = ReceivePort();
      addTearDown(port.close);
      final data = <String, dynamic>{
        for (var i = 0; i < 3000; i++) 'k$i': i,
        'port': port.sendPort,
        'raw': RawReceivePort(),
      };
      addTearDown(() => (data['raw'] as RawReceivePort).close());
      final result = await sanitizer.sanitizeOffloaded(data);
      expect(result, isNotNull);
      expect(result, contains('"k1":1'));
    });

    test('bodies over the cap are a cheap placeholder, not offloaded', () {
      final out = sanitizer.sanitizeOffloaded('x' * 300000);
      expect(out, isA<String>());
      expect(out, startsWith('[body too large:'));
    });
  });

  group('M5: engine snapshot', () {
    test('a rebuilt engine masks exactly like the original', () {
      final engine = MaskingEngine(
        MaskConfig(
          extraKeys: const ['memberNo'],
          extraHeaderDenylist: const ['X-Custom'],
          extraPatterns: [RegExp(r'ref-\d+', caseSensitive: false)],
          replacement: '[x]',
          maskUrlPathSegments: true,
        ),
      )..addKeys(['loyaltyId']);
      final copy = MaskingEngine.fromSnapshot(engine.snapshot());
      final samples = <Object>[
        {'memberNo': 1, 'loyaltyId': 2, 'note': 'REF-77 a@b.com', 'ok': 'y'},
        'password=1 and AKIAIOSFODNN7EXAMPLE',
      ];
      for (final s in samples) {
        expect(copy.maskValue(s), engine.maskValue(s));
      }
      expect(
        copy.maskHeaders({'X-Custom': 'v', 'Accept': 'a'}),
        engine.maskHeaders({'X-Custom': 'v', 'Accept': 'a'}),
      );
      expect(
        copy.maskUrl('https://a.com/u/123'),
        engine.maskUrl('https://a.com/u/123'),
      );
    });
  });

  group('M5: AES-GCM offload on native', () {
    test('the platform offload equals the inline cipher, with AAD', () async {
      final job = AesGcmJob(
        Uint8List.fromList(List.generate(32, (i) => i)),
        Uint8List.fromList(List.generate(12, (i) => i * 3)),
        Uint8List.fromList(List.generate(20000, (i) => i & 0xff)),
        Uint8List.fromList(utf8.encode('header')),
      );
      final offloaded = await platformAesGcmOffload()(job);
      final inline = await runAesGcm(job);
      expect(offloaded.ciphertext, inline.ciphertext);
      expect(offloaded.tag, inline.tag);
    });
  });
}
