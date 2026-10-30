import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';
import 'package:sealed_trace/src/masking/masking_engine.dart';

final _engine = MaskingEngine(const MaskConfig());

const _corpus = <String>[
  '',
  'plain text',
  'asha@example.com',
  'mail asha@example.com phone +91 98765 43210 card 4111111111111111',
  '(555) 123-4567 and 555-123-4567',
  '1234 5678 9012 3456',
  '12.9716, 77.5946',
  '1234567890123456',
  'a@b.com, c@d.org',
  'नमस्ते asha@example.com',
  '***',
  'call ***',
];

void main() {
  group('adversarial 100,000-character inputs finish quickly', () {
    final inputs = <String, String>{
      'a x 100k': 'a' * 100000,
      '@ x 100k': '@' * 100000,
      'a@ x 50k': 'a@' * 50000,
      '1 x 100k': '1' * 100000,
      '"1 " x 50k': '1 ' * 50000,
      '"1-" x 50k': '1-' * 50000,
      '"9876543210 " x 9k': '9876543210 ' * 9000,
      'dots x 100k': '1.' * 50000,
      'a.b@c x 25k': 'a.b@c' * 20000,
      '"(555) " x 16k': '(555) ' * 16000,
    };
    inputs.forEach((name, input) {
      test(name, () {
        final watch = Stopwatch()..start();
        _engine.maskString(input);
        watch.stop();
        expect(watch.elapsedMilliseconds, lessThan(2000), reason: name);
      });
    });
  });

  test('a string over the cap drops its tail and marks it', () {
    final input = '${'x' * MaskingEngine.maxStringChars}TAIL-asha@example.com';
    final out = _engine.maskString(input);
    expect(out, endsWith(MaskingEngine.tailMarker));
    expect(out, isNot(contains('asha@example.com')));
    expect(
      out.length,
      MaskingEngine.maxStringChars + MaskingEngine.tailMarker.length,
    );
  });

  test('PII before the cap is still masked in a long string', () {
    final input = 'asha@example.com${'y' * 150000}';
    final out = _engine.maskString(input);
    expect(out, startsWith('***y'));
    expect(out, endsWith(MaskingEngine.tailMarker));
  });

  group('mask(mask(x)) == mask(x)', () {
    for (final sample in _corpus) {
      test('string: "$sample"', () {
        final once = _engine.maskString(sample);
        expect(_engine.maskString(once), once);
      });
    }

    test('over-cap string', () {
      final once = _engine.maskString('z' * 150000);
      expect(_engine.maskString(once), once);
    });

    test('a long string whose masked form is shorter than the cap', () {
      final once = _engine.maskString('${'a@b.com ' * 20000}tail');
      expect(_engine.maskString(once), once);
    });

    test('urls', () {
      for (final url in [
        'https://user:pw@example.com:8080/a/asha@example.com?token=abc&q=a%40b.com&x=1#frag',
        '/relative?password=p&n=1',
        'not a url %%%',
      ]) {
        final once = _engine.maskUrl(url);
        expect(_engine.maskUrl(once), once, reason: url);
      }
    });

    test('maps', () {
      final once = _engine.maskMap({
        'password': 'p',
        'note': 'mail asha@example.com',
        'n': [
          {'email': 'a@b.com', 'x': '9876543210'},
        ],
      });
      expect(_engine.maskMap(once), once);
    });
  });
}
