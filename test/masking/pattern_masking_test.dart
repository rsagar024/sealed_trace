import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/masking/masking_engine.dart';

final _engine = MaskingEngine(const MaskConfig());

void _masked(String input, {String? expected}) {
  final out = _engine.maskString(input);
  expect(out, expected ?? '***', reason: input);
}

void _untouched(String input) {
  expect(_engine.maskString(input), input, reason: input);
}

void main() {
  group('email', () {
    test('masks common shapes', () {
      _masked('asha@example.com');
      _masked('a.b+tag@sub.example.co.in');
      _masked('contact asha@example.com now', expected: 'contact *** now');
      _masked('a@b.com, c@d.org', expected: '***, ***');
    });
    test('leaves non-emails alone', () {
      _untouched('not an email');
      _untouched('@handle');
      _untouched('user@localhost');
      _untouched('price @ 5');
    });
  });

  group('Indian phone numbers', () {
    test('masks the common formats', () {
      _masked('+91 98765 43210');
      _masked('+91-9876543210');
      _masked('+919876543210');
      _masked('919876543210');
      _masked('9876543210');
      _masked('98765 43210');
      _masked('09876543210');
      _masked('call 9876543210 today', expected: 'call *** today');
      _masked('(9876543210)', expected: '(***)');
    });
    test('does not match numbers outside 6-9 or longer runs', () {
      _untouched('1234567890');
      _untouched('5876543210');
      _untouched('98765432109999'); // longer digit run
      _untouched('ORD-12345');
    });
  });

  group('US phone numbers', () {
    test('masks the common formats', () {
      _masked('(555) 123-4567');
      _masked('555-123-4567');
      _masked('555 123 4567');
      _masked('+1 555 123 4567');
      _masked('+1-555-123-4567');
      _masked('+15551234567');
      _masked('call (555)123-4567.', expected: 'call ***.');
    });
    test('leaves bare runs, dotted forms and dates alone', () {
      _untouched('5551234567');
      _untouched('555.123.4567');
      _untouched('192.168.100.1234');
      _untouched('2026-01-01');
      _untouched('1767225600'); // epoch seconds
      _untouched('1767225600000'); // epoch millis
    });
  });

  group('card-like numbers', () {
    test('masks Luhn-valid numbers', () {
      _masked('4111111111111111'); // Visa test number
      _masked('4111 1111 1111 1111');
      _masked('4111-1111-1111-1111');
      _masked('5500005555555559'); // Mastercard test number
      _masked('378282246310005'); // Amex test number
      _masked('3782 822463 10005'); // Amex grouped
      _masked('4222222222222'); // 13-digit Visa test number
      _masked('card 4111111111111111 ok', expected: 'card *** ok');
    });
    test('masks Luhn-invalid numbers only when grouped like a card', () {
      _masked('1234 5678 9012 3456');
      _masked('1234-5678-9012-3456');
      _untouched('1234567890123456'); // ungrouped and Luhn-invalid
      _untouched('1234567890123');
    });
    test('masks Luhn-invalid numbers grouped 4-6-5 (Amex layout)', () {
      _masked('1234 567890 12345');
      _masked('1234-567890-12345');
      // Three groups in any other layout are not card-like. (Digits that
      // cannot look like a phone number, see the Indian-phone rule.)
      _untouched('12345 12345 12345');
      _untouched('1234 56789 012345');
    });
    test('does not touch short or over-long digit runs', () {
      _untouched('411111111111'); // 12 digits
      _untouched('41111111111111111111'); // 20 digits
    });
  });

  group('coordinates', () {
    test('masks decimal-degree pairs', () {
      _masked('12.9716, 77.5946');
      _masked('12.9716,77.5946');
      _masked('-33.8688, 151.2093');
      _masked('lat/lng 12.9716, 77.5946 end', expected: 'lat/lng *** end');
      _masked('at 12.9716, 77.5946.', expected: 'at ***.');
    });
    test('requires valid ranges and enough precision', () {
      _untouched('91.0000, 10.0000'); // latitude out of range
      _untouched('45.0000, 181.0000'); // longitude out of range
      _untouched('1.5, 2.5');
      _untouched('1.2.3');
      _untouched('192.168.1.1');
    });
  });

  group('combined and edge cases', () {
    test('several kinds in one string', () {
      expect(
        _engine.maskString(
          'mail asha@example.com phone +91 98765 43210 card 4111111111111111',
        ),
        'mail *** phone *** card ***',
      );
    });
    test('empty and plain strings are unchanged', () {
      _untouched('');
      _untouched('hello world');
      _untouched('Android 14');
      _untouched('1.2.3+45');
    });
    test('unicode text is preserved', () {
      _untouched('नमस्ते दुनिया 🌍');
      _masked('नमस्ते asha@example.com 🌍', expected: 'नमस्ते *** 🌍');
    });
  });

  group('configuration', () {
    test('useDefaultPatterns: false leaves PII text alone', () {
      final engine = MaskingEngine(const MaskConfig(useDefaultPatterns: false));
      expect(engine.maskString('asha@example.com'), 'asha@example.com');
    });

    test('custom patterns from config are applied', () {
      final engine = MaskingEngine(
        MaskConfig(extraPatterns: [RegExp(r'EMP-\d{6}')]),
      );
      expect(engine.maskString('id EMP-123456 ok'), 'id *** ok');
    });

    test('addPattern takes effect for later calls', () {
      final engine = MaskingEngine(const MaskConfig());
      expect(engine.maskString('PIN 4821'), 'PIN 4821');
      expect(engine.addPattern(RegExp(r'PIN \d{4}')), isTrue);
      expect(engine.maskString('PIN 4821'), '***');
    });

    test('a pattern matching the empty string is rejected', () {
      final engine = MaskingEngine(const MaskConfig());
      expect(engine.addPattern(RegExp(r'x*')), isFalse);
      expect(engine.maskString('abc'), 'abc');
    });

    test('empty-matching patterns in config are reported and ignored', () {
      final errors = <Object>[];
      final engine = MaskingEngine(
        MaskConfig(extraPatterns: [RegExp(r'a*')]),
        onError: (e, _) => errors.add(e),
      );
      expect(errors, hasLength(1));
      expect(engine.maskString('abc'), 'abc');
    });

    test('a pattern that throws fails closed and is reported', () {
      final errors = <Object>[];
      final engine = MaskingEngine(
        const MaskConfig(),
        onError: (e, _) => errors.add(e),
      );
      expect(engine.addPattern(_ThrowingPattern()), isTrue);
      expect(engine.maskString('secret text'), '***');
      expect(errors, hasLength(1));
    });
  });
}

// A user may pass any RegExp; this double lets us exercise a failing one.
// ignore: deprecated_implement
class _ThrowingPattern implements RegExp {
  @override
  Iterable<RegExpMatch> allMatches(String input, [int start = 0]) =>
      throw StateError('boom');

  @override
  bool hasMatch(String input) => false;

  @override
  RegExpMatch? firstMatch(String input) => throw StateError('boom');

  @override
  String? stringMatch(String input) => throw StateError('boom');

  @override
  Match? matchAsPrefix(String string, [int start = 0]) =>
      throw StateError('boom');

  @override
  String get pattern => 'throwing';

  @override
  bool get isCaseSensitive => true;

  @override
  bool get isDotAll => false;

  @override
  bool get isMultiLine => false;

  @override
  bool get isUnicode => false;
}
