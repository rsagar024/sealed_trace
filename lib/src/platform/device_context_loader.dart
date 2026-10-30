import 'package:package_info_plus/package_info_plus.dart';

import '../model/device_context.dart';
import 'device_info.dart';

/// Resolves the [DeviceContext]. Never throws.
///
/// App version and build number need the `package_info_plus` plugin; when it
/// is unavailable (pure Dart, unit tests) they fall back to `unknown`.
Future<DeviceContext> loadDeviceContext() async {
  final info = readPlatformInfo();
  var version = 'unknown';
  var build = 'unknown';
  try {
    final package = await PackageInfo.fromPlatform();
    if (package.version.isNotEmpty) version = package.version;
    if (package.buildNumber.isNotEmpty) build = package.buildNumber;
  } catch (_) {
    // Plugin unavailable; keep the fallbacks.
  }
  return DeviceContext(
    appVersion: version,
    buildNumber: build,
    platform: info.platform,
    os: info.os,
    locale: info.locale,
  );
}
