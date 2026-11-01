import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/event/log_record.dart';
import 'package:sealed_trace/src/masking/masking_engine.dart';

MaskingEngine _engine([MaskConfig config = const MaskConfig()]) =>
    MaskingEngine(config);

void main() {
  group('headers', () {
    test('the default denylist is case-insensitive and keeps names', () {
      final out = _engine().maskHeaders({
        'Authorization': 'Bearer abc',
        'COOKIE': 'sid=1',
        'set-cookie': 'sid=2',
        'X-Api-Key': 'k',
        'Accept': 'application/json',
      });
      expect(out, {
        'Authorization': '***',
        'COOKIE': '***',
        'set-cookie': '***',
        'X-Api-Key': '***',
        'Accept': 'application/json',
      });
    });

    test('list values keep their shape', () {
      final out = _engine().maskHeaders({
        'Set-Cookie': ['a=1', 'b=2'],
        'Accept': ['text/html', 'asha@example.com'],
      });
      expect(out['Set-Cookie'], ['***']);
      expect(out['Accept'], ['text/html', '***']);
    });

    test('extraHeaderDenylist adds names', () {
      final out = _engine(
        const MaskConfig(extraHeaderDenylist: ['X-Session']),
      ).maskHeaders({'x-session': 's', 'Accept': 'a'});
      expect(out, {'x-session': '***', 'Accept': 'a'});
    });

    test('null and empty input', () {
      expect(_engine().maskHeaders(null), isEmpty);
      expect(_engine().maskHeaders({}), isEmpty);
      expect(_engine().maskHeaders({'X': null}), {'X': null});
    });
  });

  group('urls', () {
    test('sensitive query values are masked', () {
      expect(
        _engine().maskUrl('https://api.example.com/v1/login?token=abc&page=2'),
        'https://api.example.com/v1/login?token=***&page=2',
      );
    });

    test('repeated parameters are all handled', () {
      expect(
        _engine().maskUrl('https://x.com/?token=a&n=1&token=b&n=2'),
        'https://x.com/?token=***&n=1&token=***&n=2',
      );
    });

    test('encoded values are decoded before masking', () {
      expect(
        _engine().maskUrl('https://x.com/?q=asha%40example.com&r=a%20b'),
        'https://x.com/?q=***&r=a%20b',
      );
    });

    test('sensitive keys match when percent-encoded', () {
      // Uri normalizes %77 to "w" while parsing, so the output is the
      // normalized key; the point is that the value is masked.
      expect(
        _engine().maskUrl('https://x.com/?pass%77ord=p'),
        'https://x.com/?password=***',
      );
    });

    test('userinfo is replaced', () {
      expect(
        _engine().maskUrl('https://user:pw@example.com:8443/a'),
        'https://***@example.com:8443/a',
      );
    });

    test('path and fragment are pattern-masked', () {
      expect(
        _engine().maskUrl('https://x.com/users/asha@example.com#9876543210'),
        'https://x.com/users/***#***',
      );
    });

    test('relative urls and urls without a query', () {
      expect(_engine().maskUrl('/a/b?apikey=k'), '/a/b?apikey=***');
      expect(_engine().maskUrl('https://x.com/plain'), 'https://x.com/plain');
    });

    test('a key without a value is handled', () {
      expect(
        _engine().maskUrl('https://x.com/?token&a=1'),
        'https://x.com/?token=***&a=1',
      );
    });

    test('ipv6 hosts keep their brackets', () {
      expect(
        _engine().maskUrl('http://[::1]:8080/p?token=t'),
        'http://[::1]:8080/p?token=***',
      );
    });

    test('an unparsable url is masked as text', () {
      expect(
        _engine().maskUrl('http://[bad asha@example.com'),
        'http://[bad ***',
      );
    });

    test('extra keys apply to query strings', () {
      expect(
        _engine(
          const MaskConfig(extraKeys: ['sid']),
        ).maskUrl('https://x.com/?sid=1'),
        'https://x.com/?sid=***',
      );
    });
  });

  group('records', () {
    LogRecord record() => LogRecord(
      id: 'id-1',
      seq: 7,
      timestamp: DateTime.utc(2026, 1, 1),
      level: LogLevel.error,
      tag: 'auth',
      message: 'login for asha@example.com failed',
      error: 'card 4111111111111111 declined',
      stackTrace: '#0 call(+91 98765 43210)',
      metadata: {
        'password': 'hunter2',
        'note': 'mail b@c.com',
        'nested': {'token': 't', 'n': 1},
      },
      sessionId: 'session-1',
      userId: 'user-42',
      ctx: {
        'appVersion': '1.2.3',
        'buildNumber': '45',
        'platform': 'android',
        'os': 'Android 14',
        'locale': 'en_IN',
        'env': 'prod',
        'network': 'wifi',
        'userName': 'Asha Rao',
        'feature': 'beta',
        'contact': 'asha@example.com',
        'email': 'x@y.com',
      },
    );

    test('all free-text parts are masked', () {
      final out = _engine().maskRecord(record());
      expect(out.message, 'login for *** failed');
      expect(out.error, 'card *** declined');
      expect(out.stackTrace, '#0 call(***)');
      expect(out.metadata, {
        'password': '***',
        'note': 'mail ***',
        'nested': {'token': '***', 'n': 1},
      });
      expect(out.ctx['contact'], '***');
      expect(out.ctx['email'], '***');
      expect(out.ctx['feature'], 'beta');
    });

    test('userName is sent as given by default', () {
      expect(_engine().maskRecord(record()).ctx['userName'], 'Asha Rao');
    });

    test('maskUserName replaces userName', () {
      final engine = _engine(const MaskConfig(maskUserName: true));
      expect(engine.maskRecord(record()).ctx['userName'], '***');
    });

    test('ids, tag, level, user id and core context are untouched', () {
      final out = _engine().maskRecord(record());
      expect(out.id, 'id-1');
      expect(out.seq, 7);
      expect(out.timestamp, DateTime.utc(2026, 1, 1));
      expect(out.level, LogLevel.error);
      expect(out.tag, 'auth');
      expect(out.sessionId, 'session-1');
      expect(out.userId, 'user-42');
      for (final key in [
        'appVersion',
        'buildNumber',
        'platform',
        'os',
        'locale',
        'env',
        'network',
      ]) {
        expect(out.ctx[key], record().ctx[key], reason: key);
      }
    });

    test('null error and stack stay null and the input is unchanged', () {
      final original = LogRecord(
        id: 'i',
        seq: 1,
        timestamp: DateTime.utc(2026),
        level: LogLevel.info,
        tag: 't',
        message: 'a@b.com',
        error: null,
        stackTrace: null,
        metadata: const {},
        sessionId: 's',
        userId: null,
        ctx: {'userName': null},
      );
      final out = _engine().maskRecord(original);
      expect(out.error, isNull);
      expect(out.stackTrace, isNull);
      expect(out.ctx['userName'], isNull);
      expect(original.message, 'a@b.com');
    });

    test('masking a record is idempotent and leaves no plaintext', () {
      // maskUserName so that 'Asha Rao' may not appear anywhere either.
      const config = MaskConfig(maskUserName: true);
      final once = _engine(config).maskRecord(record());
      final twice = _engine(config).maskRecord(once);
      expect(jsonEncode(twice.toJson()), jsonEncode(once.toJson()));
      final text = jsonEncode(once.toJson());
      for (final secret in [
        'asha@example.com',
        'hunter2',
        '4111111111111111',
        '98765 43210',
        'Asha Rao',
        'b@c.com',
        'x@y.com',
      ]) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
    });
  });
}
