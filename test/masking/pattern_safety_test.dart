import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart' show MaskConfig;
import 'package:sealed_trace/src/masking/masking_engine.dart';
import 'package:sealed_trace/src/masking/pattern_safety.dart';

/// L13: custom mask patterns that can backtrack exponentially are refused.
void main() {
  group('unsafe patterns are rejected', () {
    const rejected = <String, String>{
      r'(a+)+': 'nested repetition',
      r'(a+)+$': 'nested repetition',
      r'(a*)*b': 'nested repetition',
      r'(?:\w+\s?)*@': 'nested repetition',
      r'(a?){30}a{30}': 'nested repetition',
      r'(a+){10}': 'nested repetition',
      r'(a+?)+': 'nested repetition',
      r'((ab)+c)+': 'nested repetition',
      r'(?:\d{1,3}){2,}': 'nested repetition',
      r'x(?=(a+)+y)': 'nested repetition',
      r'(?<id>\w+)*': 'nested repetition',
      r'(a|a)*': 'repeated alternation',
      r'(\w|\d)+x': 'repeated alternation',
      r'(a|ab){0,40}': 'repeated alternation',
      r'((a|b)c)+': 'repeated alternation',
      r'(x)\1': 'backreference',
      r'(?<n>a)\k<n>': 'backreference',
      r'(a)(b)\2': 'backreference',
    };
    rejected.forEach((source, reason) {
      test(source, () {
        expect(unsafePatternReason(source), contains(reason));
        expect(MaskingEngine.patternProblem(RegExp(source)), contains(reason));
        expect(
          MaskingEngine(const MaskConfig()).addPattern(RegExp(source)),
          isFalse,
        );
      });
    });

    test('an over-long source is rejected', () {
      expect(
        unsafePatternReason('a' * (maxPatternSourceChars + 1)),
        contains('longer than'),
      );
    });

    test('unparseable source is rejected, not trusted', () {
      expect(unsafePatternReason('(abc'), contains('could not be checked'));
      expect(unsafePatternReason('abc)'), contains('could not be checked'));
      expect(unsafePatternReason('[abc'), contains('could not be checked'));
    });
  });

  group('ordinary patterns are accepted', () {
    const accepted = <String>[
      r'\bORD-\d{6}\b',
      r'EMP-\d{6}',
      r'PIN \d{4}',
      r'ORD-\d{6}',
      r'ref-\d+',
      r'PIN-\d{4}',
      r'x',
      r'v\d+(\.\d+)?',
      r'(\d{3}-){2}\d{4}',
      r'[A-Z]{2}\d+',
      r'(?:cat|dog)-\d+',
      r'(?:cat|dog)?-\d+',
      r'(?<=id=)\d{4,12}',
      r'\(a+\)+',
      r'[(a+)+]x',
      r'[\]]+x',
      r'a{,3}',
      r'\u{1F600}+',
      r'\p{L}+@x',
      r'\0x',
      r'acct:\s?\d{8}',
    ];
    for (final source in accepted) {
      test(source, () {
        expect(unsafePatternReason(source), isNull);
        expect(MaskingEngine.patternProblem(RegExp(source)), isNull);
      });
    }

    test('the empty-string check still applies', () {
      expect(
        MaskingEngine.patternProblem(RegExp(r'x*')),
        'it matches the empty string',
      );
    });
  });

  group('engine', () {
    test(
      'an unsafe config pattern is reported with its reason and skipped',
      () {
        final errors = <Object>[];
        final engine = MaskingEngine(
          MaskConfig(extraPatterns: [RegExp(r'(a+)+$'), RegExp(r'EMP-\d{6}')]),
          onError: (e, _) => errors.add(e),
        );
        expect(errors, hasLength(1));
        final error = errors.single as ArgumentError;
        expect(error.invalidValue, r'(a+)+$');
        expect(error.message, contains('nested repetition'));

        // The safe pattern and the defaults still apply.
        expect(engine.maskString('EMP-123456 asha@example.com'), '*** ***');

        final watch = Stopwatch()..start();
        final evil = '${'a' * 40}!';
        expect(engine.maskString(evil), evil);
        expect(watch.elapsedMilliseconds, lessThan(2000));
        expect(engine.snapshot().patterns, hasLength(1));
      },
    );
  });
}
