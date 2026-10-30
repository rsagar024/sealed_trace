import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/network/host_filter.dart';
import 'package:sealed_trace/src/network/level_mapper.dart';

bool _allows(String url, List<String> list) =>
    HostFilter.allows(Uri.parse(url), list);

bool _ingest(String url, [String base = 'https://logs.example.com']) =>
    HostFilter.isIngestRequest(Uri.parse(url), base);

void main() {
  group('level mapping', () {
    test('2xx is debug', () {
      for (final status in [200, 201, 204, 206, 299]) {
        expect(
          levelForNetwork(status: status),
          LogLevel.debug,
          reason: '$status',
        );
      }
    });

    test('4xx is a warning', () {
      for (final status in [400, 401, 404, 418, 429, 499]) {
        expect(
          levelForNetwork(status: status),
          LogLevel.warning,
          reason: '$status',
        );
      }
    });

    test('5xx is an error', () {
      for (final status in [500, 502, 503, 599]) {
        expect(
          levelForNetwork(status: status),
          LogLevel.error,
          reason: '$status',
        );
      }
    });

    test('1xx, 3xx and unusual codes are debug', () {
      for (final status in [100, 101, 301, 302, 304, 399, 0, 99, 600, 999]) {
        expect(
          levelForNetwork(status: status),
          LogLevel.debug,
          reason: '$status',
        );
      }
    });

    test('a call that threw (no status) is an error', () {
      expect(levelForNetwork(), LogLevel.error);
      expect(levelForNetwork(status: null), LogLevel.error);
    });

    test('a cancelled call is a warning, whatever else is known', () {
      expect(levelForNetwork(cancelled: true), LogLevel.warning);
      expect(levelForNetwork(status: 200, cancelled: true), LogLevel.warning);
      expect(levelForNetwork(status: 500, cancelled: true), LogLevel.warning);
    });
  });

  group('host allowlist', () {
    test('an empty list allows every host', () {
      expect(_allows('https://anything.example/x', const []), isTrue);
      expect(_allows('http://localhost:3000', const []), isTrue);
    });

    test('exact hosts, case-insensitively and ignoring the port', () {
      const list = ['api.example.com'];
      expect(_allows('https://api.example.com/a', list), isTrue);
      expect(_allows('https://API.Example.COM/a', list), isTrue);
      expect(_allows('https://api.example.com:8443/a', list), isTrue);
      expect(_allows('https://other.example.com/a', list), isFalse);
      expect(_allows('https://example.com/a', list), isFalse);
      expect(_allows('https://api.example.com.evil.io/a', list), isFalse);
    });

    test('entries are normalized: whitespace, case, port, scheme, path', () {
      expect(
        _allows('https://api.example.com', ['  API.example.com  ']),
        isTrue,
      );
      expect(
        _allows('https://api.example.com', ['api.example.com:443']),
        isTrue,
      );
      expect(
        _allows('https://api.example.com', ['https://api.example.com/v1']),
        isTrue,
      );
      expect(_allows('https://api.example.com', ['api.example.com.']), isTrue);
    });

    test('a wildcard matches any subdomain but not the apex', () {
      const list = ['*.example.com'];
      expect(_allows('https://a.example.com', list), isTrue);
      expect(_allows('https://a.b.example.com', list), isTrue);
      expect(_allows('https://example.com', list), isFalse);
      expect(_allows('https://evilexample.com', list), isFalse);
      expect(_allows('https://a.example.com.evil.io', list), isFalse);
      expect(_allows('https://notexample.com', list), isFalse);
    });

    test('exact and wildcard entries can be mixed', () {
      const list = ['example.com', '*.example.com'];
      expect(_allows('https://example.com', list), isTrue);
      expect(_allows('https://www.example.com', list), isTrue);
      expect(_allows('https://example.org', list), isFalse);
    });

    test('IPv6 and IPv4 literals', () {
      expect(_allows('http://[::1]:8080/x', ['[::1]']), isTrue);
      expect(_allows('http://127.0.0.1:3000/x', ['127.0.0.1']), isTrue);
      expect(_allows('http://127.0.0.2/x', ['127.0.0.1']), isFalse);
    });

    test('a request without a host is not allowed once a list is set', () {
      expect(HostFilter.allows(Uri.parse('/relative'), ['a.com']), isFalse);
    });

    test('blank entries are ignored', () {
      expect(_allows('https://a.com', ['', '  ', 'a.com']), isTrue);
      expect(_allows('https://b.com', ['', '  ']), isFalse);
    });
  });

  group('ingest exclusion (C18)', () {
    test('the ingest endpoint is recognized', () {
      expect(_ingest('https://logs.example.com/api/v1/ingest/logs'), isTrue);
      expect(_ingest('https://logs.example.com/api/v1/ingest/logs/'), isTrue);
      expect(
        _ingest('https://LOGS.example.com/api/v1/ingest/logs?x=1'),
        isTrue,
      );
    });

    test('other paths on the same host are not the ingest endpoint', () {
      expect(_ingest('https://logs.example.com/api/v1/projects'), isFalse);
      expect(_ingest('https://logs.example.com/'), isFalse);
      expect(_ingest('https://logs.example.com/api/v1/ingest'), isFalse);
      expect(
        _ingest('https://logs.example.com/api/v1/ingest/logs/extra'),
        isFalse,
      );
    });

    test('the same path on another host is not the ingest endpoint', () {
      expect(_ingest('https://other.example.com/api/v1/ingest/logs'), isFalse);
    });

    test('ports must match', () {
      expect(
        _ingest('https://logs.example.com:8443/api/v1/ingest/logs'),
        isFalse,
      );
      expect(
        _ingest(
          'https://logs.example.com:8443/api/v1/ingest/logs',
          'https://logs.example.com:8443',
        ),
        isTrue,
      );
    });

    test('a base URL with a path prefix and trailing slashes', () {
      expect(
        _ingest('https://x.com/base/api/v1/ingest/logs', 'https://x.com/base/'),
        isTrue,
      );
      expect(
        _ingest('https://x.com/api/v1/ingest/logs', 'https://x.com/base/'),
        isFalse,
      );
      expect(
        _ingest('https://x.com/api/v1/ingest/logs', 'https://x.com///'),
        isTrue,
      );
    });

    test('an unusable base URL excludes nothing and never throws', () {
      expect(
        _ingest('https://x.com/api/v1/ingest/logs', ':::not a url'),
        isFalse,
      );
      expect(_ingest('https://x.com/api/v1/ingest/logs', ''), isFalse);
    });
  });
}
