import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/sealed_trace.dart';

void main() {
  test(
    'levels are ordered verbose < debug < info < warning < error < fatal',
    () {
      expect(LogLevel.values, [
        LogLevel.verbose,
        LogLevel.debug,
        LogLevel.info,
        LogLevel.warning,
        LogLevel.error,
        LogLevel.fatal,
      ]);
    },
  );

  test('isAtLeast compares severity', () {
    expect(LogLevel.error.isAtLeast(LogLevel.warning), isTrue);
    expect(LogLevel.info.isAtLeast(LogLevel.info), isTrue);
    expect(LogLevel.debug.isAtLeast(LogLevel.info), isFalse);
  });
}
