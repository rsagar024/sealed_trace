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
      'dob', 'ssn', 'cvv', 'username', 'otp', 'pin', 'mpin', 'cvc', 'session',
      'sessionId', 'sid', 'cardNumber', 'ccNumber', 'client_secret',
      'authCode', 'iban', 'passport', 'passportNumber', 'passportNo', 'aadhaar',
      'aadhar', 'aadhaarNumber', 'panNumber', 'panCard', 'nationalId', 'taxId',
      'ip', 'ipAddress', 'clientIp', //
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
      'filename': 'f.txt',
      'compass': 'N',
      'names': 'n',
      'author': 'a',
      'authority': 'b',
      'authorName': 'c',
      'pinned': true,
      'sidebar': 'left',
    });
    expect(out, {
      'filename': 'f.txt',
      'compass': 'N',
      'names': 'n',
      'author': 'a',
      'authority': 'b',
      'authorName': 'c',
      'pinned': true,
      'sidebar': 'left',
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
    expect(engine.maskMap({'memberNo': 'X'}), {'memberNo': 'X'});
    engine.addKeys(['MEMBER_NO']);
    expect(engine.maskMap({'memberNo': 'X'}), {'memberNo': '***'});
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

  group('H2: normalized and fragment key matching', () {
    test('separator and case variants of a default key match', () {
      for (final key in [
        'accessToken',
        'access-token',
        'ACCESS_TOKEN',
        'Access.Token',
        'api-key',
        'refreshToken',
        'sessionId',
        'session_id',
        'client-secret',
        'firstName',
        'FIRST-NAME',
      ]) {
        expect(_engine().maskMap({key: 'v'}), {key: '***'}, reason: key);
      }
    });

    test('keys holding a credential fragment match', () {
      for (final key in [
        'id_token',
        'idToken',
        'x-auth-token',
        'csrfToken',
        'clientSecretValue',
        'oldPassword',
        'passwordHint',
        'db_passwd',
        'passphrase',
        'awsCredentials',
        'googleApiKey',
        'private_key',
        'authorization',
        'cookie',
        'jwt',
      ]) {
        expect(_engine().maskMap({key: 'v'}), {key: '***'}, reason: key);
      }
    });

    test('keys ending with auth match; author and authority do not', () {
      for (final key in ['oauth', 'basicAuth', 'x-auth', 'auth']) {
        expect(_engine().isSensitiveKey(key), isTrue, reason: key);
      }
      for (final key in ['author', 'authority', 'authors', 'authorId']) {
        expect(_engine().isSensitiveKey(key), isFalse, reason: key);
      }
    });

    test('new exact keys match', () {
      for (final key in [
        'username',
        'otp',
        'pin',
        'mpin',
        'cvc',
        'session',
        'sid',
        'card_number',
        'ccNumber',
        'authCode',
      ]) {
        expect(_engine().isSensitiveKey(key), isTrue, reason: key);
      }
    });

    test('useDefaultKeys: false turns fragments off too', () {
      final engine = _engine(const MaskConfig(useDefaultKeys: false));
      expect(engine.isSensitiveKey('accessToken'), isFalse);
      expect(engine.isSensitiveKey('oauth'), isFalse);
    });

    test('extraKeys are normalized the same way', () {
      final engine = _engine(const MaskConfig(extraKeys: ['national_id']));
      expect(engine.isSensitiveKey('nationalId'), isTrue);
      expect(engine.isSensitiveKey('NATIONAL-ID'), isTrue);
    });

    test('an OAuth token response is fully masked', () {
      final out = _engine().maskMap({
        'access_token': 'at-1',
        'id_token': 'it-1',
        'refresh_token': 'rt-1',
        'token_type': 'Bearer',
        'expires_in': 3600,
        'scope': 'openid',
      });
      expect(out, {
        'access_token': '***',
        'id_token': '***',
        'refresh_token': '***',
        'token_type': '***',
        'expires_in': 3600,
        'scope': 'openid',
      });
    });
  });

  group('M4: PII in map keys', () {
    test('a key holding PII is masked, its value is kept', () {
      final out = _engine().maskMap({
        'asha@example.com': {'orders': 3},
        'city': 'Pune',
      });
      expect(out, {
        '***': {'orders': 3},
        'city': 'Pune',
      });
    });

    test('keys that mask to the same text stay distinct', () {
      final out = _engine().maskMap({
        'a@example.com': 1,
        'b@example.com': 2,
        'c@example.com': 3,
      });
      expect(out, {'***': 1, '***#2': 2, '***#3': 3});
    });

    test('nested maps and context keys too', () {
      final out = _engine().maskMap({
        'byIp': {'192.168.1.1': 'blocked'},
      });
      expect(out, {
        'byIp': {'***': 'blocked'},
      });
    });

    test('new identity keys are masked', () {
      for (final key in [
        'iban',
        'passport',
        'passport_number',
        'aadhaar',
        'pan_number',
        'national_id',
        'tax-id',
        'ipAddress',
        'client_ip',
      ]) {
        expect(_engine().isSensitiveKey(key), isTrue, reason: key);
      }
    });
  });
}
