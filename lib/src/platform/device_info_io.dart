import 'dart:io';

import 'platform_info.dart';

/// Reads platform facts on `dart:io` platforms.
PlatformInfo readPlatformInfo() {
  final String platform;
  if (Platform.isAndroid) {
    platform = 'android';
  } else if (Platform.isIOS) {
    platform = 'ios';
  } else if (Platform.isWindows) {
    platform = 'windows';
  } else if (Platform.isMacOS) {
    platform = 'macos';
  } else if (Platform.isLinux) {
    platform = 'linux';
  } else {
    platform = 'unknown';
  }

  var locale = 'unknown';
  try {
    // Linux reports values such as `en_US.UTF-8`; keep the language part.
    locale = Platform.localeName.split('.').first;
  } catch (_) {
    // Keep the default.
  }

  return PlatformInfo(
    platform: platform,
    os: '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    locale: locale.isEmpty ? 'unknown' : locale,
  );
}
