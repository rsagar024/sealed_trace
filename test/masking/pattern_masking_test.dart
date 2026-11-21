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
      _untouched('1.2.3.4.5');
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
  group('H2: JWT and Bearer patterns apply to every string', () {
    const jwt = 'eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjMifQ.c2lnbmF0dXJlLXZhbHVl';

    test('a JWT in a log message is masked', () {
      expect(
        _engine.maskString('login ok, token was $jwt for user'),
        'login ok, token was *** for user',
      );
    });

    test('a JWT in a URL path is masked', () {
      expect(_engine.maskString('/reset/$jwt/confirm'), '/reset/***/confirm');
    });

    test('an unsigned JWT is masked', () {
      expect(
        _engine.maskString('t=eyJhbGciOiJub25lIn0.eyJzdWIiOiIxIn0.'),
        't=***',
      );
    });

    test('a Bearer token in free text keeps the scheme word', () {
      expect(
        _engine.maskString('sent Authorization Bearer abc.def-ghi_123 ok'),
        'sent Authorization Bearer *** ok',
      );
    });

    test('masking stays idempotent', () {
      final once = _engine.maskString('Bearer abcdef123 and $jwt');
      expect(_engine.maskString(once), once);
    });

    test('ordinary words are left alone', () {
      _untouched('Bearer of bad news');
      _untouched('eyJ alone is not a token');
    });
  });

  group('M4: more default patterns', () {
    test('API keys with a known prefix', () {
      _masked('AKIAIOSFODNN7EXAMPLE');
      _masked(
        'key sk_'
        'live_'
        'FAKEfake0000FAKEfake0000 here',
        expected: 'key *** here',
      );
      _masked(
        'rk_'
        'test_'
        'FAKEfake0000FAKEfake',
      );
      _masked('ghp_${'a' * 36}');
      _masked('github_pat_${'B' * 22}');
      _masked('AIza${'x' * 35}');
      _masked(
        'xox'
        'b-'
        'FAKEfake00-FAKEfake',
      );
      _masked('glpat-${'z' * 20}');
    });

    test('publishable keys and look-alikes are kept', () {
      _untouched(
        'pk_'
        'live_'
        'FAKEfake0000FAKEfake0000',
      );
      _untouched('AKIA is a prefix');
      _untouched('sk_live_short');
    });

    test('IBANs that pass mod-97', () {
      _masked('DE89370400440532013000');
      _masked(
        'pay to DE89 3704 0044 0532 0130 00 today',
        expected: 'pay to *** today',
      );
      _masked('GB82WEST12345698765432');
      _untouched('DE00370400440532013000'); // bad check digits
    });

    test('dashed US SSNs in the valid ranges', () {
      _masked('ssn 123-45-6789', expected: 'ssn ***');
      _untouched('000-12-3456');
      _untouched('666-12-3456');
      _untouched('912-34-5678');
      _untouched('123-00-4567');
      _untouched('2026-01-15'); // a date
    });

    test('Aadhaar numbers that pass Verhoeff', () {
      _masked('234567890124');
      _masked('aadhaar 2345 6789 0124 ok', expected: 'aadhaar *** ok');
      _masked('2345-6789-0124');
      _untouched('234567890129'); // checksum fails
    });

    test('Indian PAN', () {
      _masked('pan ABCPE1234F', expected: 'pan ***');
      _untouched('ABCXE1234F'); // X is not a holder type
      _untouched('abcpe1234f');
    });

    test('IPv4 addresses', () {
      _masked('from 192.168.1.1 now', expected: 'from *** now');
      _masked('host 10.0.0.1.', expected: 'host ***.');
      _untouched('999.1.1.1');
      _untouched('1.2.3');
      _untouched('1.2.3.4.5');
    });

    test('IPv6 addresses', () {
      _masked('2001:db8::1');
      _masked('peer fe80::1ff:fe23:4567:890a up', expected: 'peer *** up');
      _masked('::1');
      _masked('2001:0db8:85a3:0000:0000:8a2e:0370:7334');
      _untouched('at 10:30:45');
      _untouched('std::vector');
      _untouched('a :: b');
    });

    test('masking stays idempotent', () {
      const text =
          'AKIAIOSFODNN7EXAMPLE DE89370400440532013000 123-45-6789 '
          '234567890124 ABCPE1234F 192.168.1.1 2001:db8::1 password=x';
      final once = _engine.maskString(text);
      expect(_engine.maskString(once), once);
    });
  });

  group('M4: credentials in free text (every string)', () {
    test('key=value and key: value in log messages', () {
      expect(
        _engine.maskString('retry with password=hunter2 and otp: 123456'),
        'retry with password=*** and otp: ***',
      );
      expect(
        _engine.maskString('GET /cb?code=1&access_token=abc failed'),
        'GET /cb?code=1&access_token=*** failed',
      );
    });

    test('JSON and XML fragments in log messages', () {
      expect(
        _engine.maskString('body {"clientSecret":"s3cr3t","ok":true}'),
        'body {"clientSecret":"***","ok":true}',
      );
      expect(
        _engine.maskString('<apiKey>k-1</apiKey><city>Pune</city>'),
        '<apiKey>***</apiKey><city>Pune</city>',
      );
    });

    test('Cookie lines in log messages', () {
      expect(_engine.maskString('Cookie: sid=abc; theme=dark'), 'Cookie: ***');
    });

    test('ordinary text with colons and equals signs is kept', () {
      _untouched('status: ok, retries=3, at 10:30');
      _untouched('a == b');
    });

    test('useDefaultKeys: false still masks denylisted header names', () {
      final engine = MaskingEngine(const MaskConfig(useDefaultKeys: false));
      expect(engine.maskString('password=x'), 'password=x');
      expect(engine.maskString('x-api-key: k1'), 'x-api-key: ***');
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
