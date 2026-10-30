import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/masking/masking_engine.dart';
import 'package:sealed_trace/src/network/body_sanitizer.dart';

MaskingEngine _engine() => MaskingEngine(const MaskConfig());

BodySanitizer _sanitizer({int max = 20000, MaskingEngine? engine}) =>
    BodySanitizer(engine ?? _engine(), maxBodyChars: max);

String _clean(Object? data, {String? contentType, int? declaredLength}) =>
    _sanitizer().sanitize(
      data,
      contentType: contentType,
      declaredLength: declaredLength,
    )!;

class _Hostile {
  @override
  String toString() => throw StateError('hostile toString');
}

/// Every secret that must never survive, with where it hides.
const _secrets = <String>[
  'hunter2',
  'tok_abc123',
  'asha@example.com',
  'sk_live_SECRET99',
  'eyJhbGciOiJIUzI1NiJ9',
  'dXNlcjpwYXNzd29yZA',
  '4111 1111 1111 1111',
  '98765 43210',
];

void main() {
  group('JSON bodies', () {
    test('nested secrets are masked by key, at any depth', () {
      final out = _clean({
        'user': {
          'email': 'asha@example.com',
          'password': 'hunter2',
          'profile': {'token': 'tok_abc123', 'city': 'Pune'},
        },
        'items': [
          {'cvv': '123', 'sku': 'A1'},
          {
            'deep': {
              'deeper': {'refresh_token': 'sk_live_SECRET99'},
            },
          },
        ],
      });
      expect(out, contains('Pune'));
      expect(out, contains('A1'));
      for (final secret in [
        'hunter2',
        'tok_abc123',
        'asha@example.com',
        'SECRET99',
      ]) {
        expect(out, isNot(contains(secret)), reason: secret);
      }
      final decoded = jsonDecode(out) as Map<String, dynamic>;
      expect((decoded['user'] as Map)['password'], '***');
      expect(((decoded['items'] as List).first as Map)['cvv'], '***');
    });

    test('text that parses as JSON gets the same treatment', () {
      final out = _clean(
        '{"password":"hunter2","note":"mail asha@example.com","ok":1}',
        contentType: 'application/json',
      );
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('asha@example.com')));
      expect(out, contains('"ok":1'));
    });

    test('a JSON array at the top level', () {
      final out = _clean('[{"token":"tok_abc123"},{"a":"b"}]');
      expect(out, isNot(contains('tok_abc123')));
      expect(out, contains('"a":"b"'));
    });

    test('patterns apply to string values too', () {
      final out = _clean({'msg': 'call +91 98765 43210 now'});
      expect(out, isNot(contains('98765')));
    });
  });

  group('form-encoded bodies', () {
    test('sensitive keys are masked and repeated keys survive', () {
      final out = _clean(
        'username=asha&password=hunter2&name=Asha+Rao&q=ok&q=again&token=tok_abc123',
        contentType: 'application/x-www-form-urlencoded',
      );
      expect(out, contains('username=asha'), reason: 'near-miss key kept');
      expect(out, contains('q=ok&q=again'));
      expect(out, contains('password=***'));
      expect(out, contains('name=***'));
      expect(out, contains('token=***'));
      expect(out, isNot(contains('hunter2')));
    });
  });

  group('free text', () {
    test('Bearer and Basic tokens', () {
      final out = _clean(
        'Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.payload.signature\n'
        'Proxy: Basic dXNlcjpwYXNzd29yZA==',
        contentType: 'text/plain',
      );
      expect(out, contains('Bearer ***'));
      expect(out, contains('Basic ***'));
      expect(out, isNot(contains('eyJhbGci')));
      expect(out, isNot(contains('dXNlcjpw')));
    });

    test('XML and HTML tags', () {
      final out = _clean(
        '<login><name>Asha</name><password>hunter2</password>'
        '<passwordHint>blue</passwordHint><city>Pune</city></login>',
        contentType: 'application/xml',
      );
      expect(out, contains('<password>***</password>'));
      expect(out, contains('<name>***</name>'));
      expect(
        out,
        contains('<passwordHint>blue</passwordHint>'),
        reason: 'a different tag is not a sensitive key',
      );
      expect(out, contains('<city>Pune</city>'));
      expect(out, isNot(contains('hunter2')));
    });

    test('invalid or truncated JSON still has its keys masked', () {
      final out = _clean('{"password":"hunter2", "name": "Asha", oops');
      expect(out, contains('"password":"***"'));
      expect(out, contains('"name": "***"'));
      expect(out, isNot(contains('hunter2')));
    });

    test('single-quoted, python-style and key=value forms', () {
      final out = _clean(
        "{'password': 'hunter2'}\napi_key=sk_live_SECRET99\ntoken: tok_abc123",
        contentType: 'text/plain',
      );
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('SECRET99')));
      expect(out, isNot(contains('tok_abc123')));
      expect(out, contains('api_key=***'));
    });

    test('cookie lines are masked to the end of the line', () {
      final out = _clean(
        'Cookie: sid=abc123; sessionid=zzz-secret; theme=dark\nok: yes',
        contentType: 'text/plain',
      );
      expect(out, contains('Cookie: ***'));
      expect(out, isNot(contains('zzz-secret')));
      expect(out, isNot(contains('sid=abc123')));
      expect(out, contains('ok: yes'));
    });

    test('x-api-key and authorization lines', () {
      final out = _clean(
        'x-api-key: sk_live_SECRET99\nauthorization: sometoken-without-scheme',
        contentType: 'text/plain',
      );
      expect(out, isNot(contains('SECRET99')));
      expect(out, isNot(contains('sometoken-without-scheme')));
    });

    test('emails, phones and cards are masked in prose', () {
      final out = _clean(
        'call +91 98765 43210 or mail asha@example.com, card 4111 1111 1111 1111',
        contentType: 'text/plain',
      );
      expect(out, 'call *** or mail ***, card ***');
    });

    test('words that merely contain a sensitive key are left alone', () {
      final out = _clean('username: asha, filename=report.pdf, passport ok');
      expect(out, 'username: asha, filename=report.pdf, passport ok');
    });

    test('keys added at runtime are masked in text too', () {
      final engine = _engine()..addKeys(['iban']);
      final out = _sanitizer(engine: engine).sanitize('iban=GB00BANK1234')!;
      expect(out, 'iban=***');
    });

    test('useDefaultKeys: false leaves only the fixed header-like keys', () {
      final engine = MaskingEngine(const MaskConfig(useDefaultKeys: false));
      final out = _sanitizer(
        engine: engine,
      ).sanitize('password=hunter2 x-api-key: abc123')!;
      expect(out, contains('password=hunter2'));
      expect(out, contains('x-api-key: ***'));
    });

    test('the whole corpus never survives', () {
      final blob = '''
        mail asha@example.com
        {"password":"hunter2","x":{"token":"tok_abc123"}}
        Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.p.s
        Basic dXNlcjpwYXNzd29yZA==
        api_key=sk_live_SECRET99
        card 4111 1111 1111 1111 phone +91 98765 43210
      ''';
      final out = _clean(blob, contentType: 'text/plain');
      for (final secret in _secrets) {
        expect(out, isNot(contains(secret)), reason: secret);
      }
    });
  });

  group('truncation (after masking)', () {
    test(
      'a 25,000-character text body is cut to exactly 20,000 plus a marker',
      () {
        final out = _clean('x' * 25000, contentType: 'text/plain');
        expect(out, '${'x' * 20000}…[truncated 5000 chars]');
      },
    );

    test('a body at the limit is not marked', () {
      expect(_clean('y' * 20000), 'y' * 20000);
      expect(_clean('y' * 19999), 'y' * 19999);
    });

    test('a JSON body longer than the limit is cut after masking', () {
      final out = _clean({
        'pad': 'a' * 19980,
        'password': 'hunter2-secret-value',
      });
      expect(out, contains('…[truncated'));
      expect(out, isNot(contains('hunter2')));
      expect(out.indexOf('…[truncated'), 20000);
    });

    test('a secret that straddles the cut is masked first, never split', () {
      final text = '${'x' * 19990}password=hunter2-secret rest';
      final out = _clean(text, contentType: 'text/plain');
      expect(out, isNot(contains('hunter2')));
      expect(out, isNot(contains('secret rest')));
      expect(out, contains('…[truncated'));
    });

    test('a smaller limit and the extreme limits', () {
      expect(
        _sanitizer(max: 5).sanitize('abcdefghij'),
        'abcde…[truncated 5 chars]',
      );
      expect(_sanitizer(max: 1).sanitize('abc'), 'a…[truncated 2 chars]');
      expect(_sanitizer(max: 0).sanitize('abc'), '…[truncated 3 chars]');
      expect(_sanitizer(max: -5).sanitize('abc'), '…[truncated 3 chars]');
    });

    test('a cut never splits a surrogate pair', () {
      final text = '${'a' * 19999}😀tail';
      final out = _clean(text, contentType: 'text/plain');
      expect(out, startsWith('a' * 19999));
      expect(out, endsWith('…[truncated ${text.length - 19999} chars]'));
      expect(out.contains('\uD83D'), isFalse, reason: 'no lone surrogate');
    });
  });

  group('placeholders', () {
    test('binary data', () {
      expect(_clean(Uint8List(10)), '[binary 10 bytes]');
      expect(_clean(<int>[1, 2, 3]), '[binary 3 bytes]');
      expect(_clean(Uint8List(0)), '[binary 0 bytes]');
    });

    test('binary content types, with or without a declared length', () {
      expect(_clean('whatever', contentType: 'image/png'), '[binary 8 bytes]');
      expect(
        _clean('x', contentType: 'application/pdf', declaredLength: 4096),
        '[binary 4096 bytes]',
      );
      expect(
        _clean('x', contentType: 'Application/Octet-Stream'),
        '[binary 1 bytes]',
      );
      expect(_clean({'a': 1}, contentType: 'video/mp4'), '[binary body]');
    });

    test('multipart bodies', () {
      expect(_clean(FormData()), '[multipart form-data]');
      expect(
        _clean('x', contentType: 'multipart/form-data; boundary=abc'),
        '[multipart form-data]',
      );
    });

    test('streams are never read', () {
      expect(_clean(const Stream<Uint8List>.empty()), '[stream]');
    });

    test('no body is null', () {
      expect(_sanitizer().sanitize(null), isNull);
    });

    test('bodies that are too large are not processed', () {
      expect(
        _clean(
          {'a': 1},
          contentType: 'application/json',
          declaredLength: 2000000,
        ),
        '[body too large: 2000000 chars]',
      );
      expect(_clean('z' * 1000001), '[body too large: 1000001 chars]');
      expect(
        _clean(List<int>.filled(250000, 1).map((e) => e).toList()),
        '[binary 250000 bytes]',
      );
      expect(
        _clean(List<Object>.filled(250000, 1)),
        startsWith('[body too large'),
      );
    });

    test('unknown objects and hostile objects never throw', () {
      expect(_clean(_Hostile()), '[non-text body]');
      expect(_clean(DateTime(2026)), '[non-text body]');
      expect(() => _clean({'k': _Hostile()}), returnsNormally);
      expect(_clean(42), '42');
      expect(_clean(true), 'true');
    });
  });

  group('safety', () {
    test('the input is never modified', () {
      final data = {
        'password': 'hunter2',
        'list': [
          {'token': 'tok_abc123'},
        ],
      };
      _clean(data);
      expect(data['password'], 'hunter2');
      expect(((data['list']! as List).first as Map)['token'], 'tok_abc123');
    });

    test('sanitizing is idempotent', () {
      for (final input in <Object>[
        {
          'password': 'hunter2',
          'a': [1, 2],
        },
        'Bearer eyJhbGciOiJIUzI1NiJ9.p.s and api_key=sk_live_SECRET99',
        'username=asha&password=hunter2',
        '<password>hunter2</password>',
      ]) {
        final once = _clean(
          input,
          contentType: input is String && input.contains('&')
              ? 'application/x-www-form-urlencoded'
              : null,
        );
        expect(_clean(once), once, reason: '$input');
      }
    });

    final adversarial = <String, String>{
      'a x 100k': 'a' * 100000,
      '"password:" x 11k': 'password:' * 11000,
      '"<name>" x 16k': '<name>' * 16000,
      '"\\"password\\":" x 9k': '"password":' * 9000,
      '"bearer " x 14k': 'bearer ' * 14000,
      '"cookie:" x 14k': 'cookie:' * 14000,
      '"token=" x 16k': 'token=' * 16000,
      'quotes x 100k': '"' * 100000,
      'braces x 100k': '{' * 100000,
      '"a=b&" x 33k': 'a=b&' * 33000,
    };
    adversarial.forEach((name, input) {
      test('adversarial input finishes quickly: $name', () {
        final watch = Stopwatch()..start();
        final out = _sanitizer().sanitize(input, contentType: 'text/plain');
        watch.stop();
        expect(out, isNotNull);
        expect(watch.elapsedMilliseconds, lessThan(2000), reason: name);
      });
    });
  });
}
