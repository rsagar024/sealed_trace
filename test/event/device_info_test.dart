import 'package:flutter_test/flutter_test.dart';
import 'package:sealed_trace/src/platform/device_context_loader.dart';
import 'package:sealed_trace/src/platform/device_info.dart';

void main() {
  test('readPlatformInfo reports a known platform and a locale', () {
    final info = readPlatformInfo();
    expect([
      'android',
      'ios',
      'web',
      'windows',
      'macos',
      'linux',
    ], contains(info.platform));
    expect(info.os, isNotEmpty);
    expect(info.locale, isNotEmpty);
    expect(info.locale, isNot(contains('.')));
  });

  test('loadDeviceContext never throws without the plugin', () async {
    final device = await loadDeviceContext();
    expect(device.platform, isNotEmpty);
    expect(device.appVersion, isNotEmpty);
    expect(device.buildNumber, isNotEmpty);
  });
}
