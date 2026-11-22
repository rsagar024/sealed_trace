// The platform interface instead of package_info_plus.dart: that library
// exports its Linux implementation unconditionally, which pulls dart:io into
// the web graph and makes the package incompatible with WASM. Registration of
// the platform implementations still comes from the package_info_plus
// dependency.
import 'package:package_info_plus_platform_interface/package_info_platform_interface.dart';

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
    final package = await PackageInfoPlatform.instance.getAll();
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
