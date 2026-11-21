import 'dart:convert';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/crypto/envelope_sealer.dart';
import 'package:sealed_trace/src/crypto/public_key_parser.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/model/log_level.dart';

import '../helpers/envelope_opener.dart';
import '../helpers/test_keys.dart';

/// Padmé computed independently, with floating-point logarithms.
int _reference(int length) {
  if (length <= 256) return 256;
  final e = (log(length) / ln2).floor();
  final s = (log(e) / ln2).floor() + 1;
  final step = pow(2, e - s).toInt();
  return (length / step).ceil() * step;
}

LogRecord _record(String message, {LogLevel level = LogLevel.info}) =>
    LogRecord(
      id: 'id-1',
      seq: 1,
      timestamp: DateTime.utc(2026, 1, 1),
      level: level,
      tag: 't',
      message: message,
      error: null,
      stackTrace: null,
      metadata: const {},
      sessionId: 's',
      userId: null,
      ctx: const {},
    );

void main() {
  group('L6: Padmé lengths', () {
    test('small plaintexts all become 256 bytes', () {
      for (final l in [0, 1, 100, 255, 256]) {
        expect(padmeLength(l), 256, reason: '$l');
      }
    });

    test('matches the floating-point reference for every length to 70 000', () {
      for (var l = 1; l <= 70000; l++) {
        final p = padmeLength(l);
        if (p != _reference(l)) fail('length $l: $p != ${_reference(l)}');
      }
    });

    test('never shrinks, never decreases, overhead at most 12 %', () {
      var previous = 0;
      for (var l = 257; l <= 4 * 1024 * 1024; l = l * 21 ~/ 20 + 1) {
        final p = padmeLength(l);
        expect(p, greaterThanOrEqualTo(l));
        expect(p, greaterThanOrEqualTo(previous));
        expect((p - l) / l, lessThanOrEqualTo(0.12), reason: '$l -> $p');
        previous = p;
      }
    });

    test('hides the exact size: few distinct lengths per power of two', () {
      final buckets = {for (var l = 4097; l <= 8192; l++) padmeLength(l)};
      expect(buckets.length, lessThanOrEqualTo(16));
    });

    test('known values', () {
      expect(padmeLength(257), 272);
      expect(padmeLength(1313), 1344);
      expect(padmeLength(9970), 10240);
      expect(padmeLength(100000), 100352);
    });
  });

  group('L6: sealed plaintext is padded with spaces', () {
    final sealer = EnvelopeSealer(
      publicKey: PublicKeyParser.parse(testPublicKeySpki),
      projectId: 'p',
    );

    test('the decrypted text is the JSON plus spaces, and parses', () async {
      final envelope = await sealer.seal([_record('hello')]);
      final raw = await openEnvelopeRaw(envelope);
      final json = jsonEncode([_record('hello').toJson()]);
      expect(utf8.encode(raw).length, padmeLength(utf8.encode(json).length));
      expect(raw.startsWith(json), isTrue);
      expect(raw.substring(json.length), matches(RegExp(r'^ *$')));
      expect(jsonDecode(raw), isA<List<dynamic>>(), reason: 'valid JSON');
    });

    test('messages of different lengths share a size bucket', () async {
      final short = await sealer.seal([_record('a')]);
      final longer = await sealer.seal([_record('a' * 60)]);
      expect(short.ciphertext.length, longer.ciphertext.length);
    });

    test('sealSync pads the same way', () {
      final a = sealer.sealSync([_record('x' * 3000)]);
      final b = sealer.sealSync([_record('y' * 3000)]);
      expect(a.payloadSize, padmeLength(a.payloadSize));
      expect(a.payloadSize, b.payloadSize);
    });
  });
}
