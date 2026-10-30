import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/masking/default_keys.dart';
import 'package:sealed_trace/src/masking/masking_engine.dart';

MaskingEngine _engine([MaskConfig config = const MaskConfig()]) =>
    MaskingEngine(config);

void main() {
  test('the default key list is exactly the spec list', () {
    expect(defaultSensitiveKeys, [
      'password', 'pass', 'pwd', 'token', 'secret', 'auth', 'apikey',
      'api_key', 'access_token', 'refresh_token', 'firstName', 'lastName',
      'name', 'first_name', 'last_name', 'fName', 'lName', 'email', 'phone',
      'dob', 'ssn', 'cvv', //
    ]);
  });

  group('every default key is masked in three casings', () {
    for (final key in defaultSensitiveKeys) {
      for (final variant in {key, key.toLowerCase(), key.toUpperCase()}) {
        test(variant, () {
          final out = _engine().maskMap({variant: 'value-123', 'keep': 'ok'});
          expect(out[variant], '***');
          expect(out['keep'], 'ok');
        });
      }
    }
  });

  test('keys are masked at any depth, including lists of maps', () {
    final out = _engine().maskMap({
      'a': {
        'b': [
          {'password': 'p1', 'x': 1},
          {
            'c': {'token': 't1'},
          },
        ],
      },
    });
    expect(out, {
      'a': {
        'b': [
          {'password': '***', 'x': 1},
          {
            'c': {'token': '***'},
          },
        ],
      },
    });
  });

  test('a sensitive key replaces the whole nested value', () {
    final out = _engine().maskMap({
      'auth': {
        'user': 'a',
        'deep': [1, 2, 3],
      },
    });
    expect(out['auth'], '***');
  });

  test('near-miss keys are not masked', () {
    final out = _engine().maskMap({
      'username': 'u',
      'filename': 'f.txt',
      'passport': 'P1',
      'names': 'n',
      'passwordHint': 'h',
    });
    expect(out, {
      'username': 'u',
      'filename': 'f.txt',
      'passport': 'P1',
      'names': 'n',
      'passwordHint': 'h',
    });
  });

  test('null values stay null', () {
    expect(_engine().maskMap({'password': null}), {'password': null});
  });

  test('non-string values under sensitive keys are masked too', () {
    final out = _engine().maskMap({'phone': 9876543210, 'cvv': 123});
    expect(out, {'phone': '***', 'cvv': '***'});
  });

  test('useDefaultKeys: false drops the built-in list', () {
    final engine = _engine(const MaskConfig(useDefaultKeys: false));
    expect(engine.maskMap({'password': 'p'}), {'password': 'p'});
  });

  test('extraKeys are matched exactly and case-insensitively', () {
    final engine = _engine(const MaskConfig(extraKeys: ['Session_ID']));
    final out = engine.maskMap({
      'session_id': 'a',
      'SESSION_ID': 'b',
      'session_ids': 'c',
    });
    expect(out, {'session_id': '***', 'SESSION_ID': '***', 'session_ids': 'c'});
  });

  test('addKeys takes effect for later calls only', () {
    final engine = _engine();
    expect(engine.maskMap({'iban': 'X'}), {'iban': 'X'});
    engine.addKeys(['IBAN']);
    expect(engine.maskMap({'iban': 'X'}), {'iban': '***'});
  });

  test('the replacement text is configurable', () {
    final engine = _engine(const MaskConfig(replacement: '[hidden]'));
    expect(engine.maskMap({'password': 'p'}), {'password': '[hidden]'});
  });

  test('cyclic input terminates', () {
    final map = <String, dynamic>{'a': 1};
    map['self'] = map;
    final list = <dynamic>[];
    list.add(list);
    final out = _engine().maskMap({'m': map, 'l': list});
    expect(out, isNotEmpty);
  });

  test('over-deep input terminates and fails closed', () {
    Object nested = 'leaf-secret@example.com';
    for (var i = 0; i < 40; i++) {
      nested = {'n': nested};
    }
    final out = _engine().maskMap({'root': nested});
    expect(out.toString(), isNot(contains('leaf-secret')));
  });

  test('input maps are never mutated', () {
    final input = {
      'password': 'p',
      'list': [
        {'token': 't'},
      ],
    };
    _engine().maskMap(input);
    expect(input['password'], 'p');
    expect(((input['list']! as List).first as Map)['token'], 't');
  });
}
