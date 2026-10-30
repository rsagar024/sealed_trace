import 'platform_info.dart';

/// Fallback for platforms with neither `dart:io` nor `dart:js_interop`.
PlatformInfo readPlatformInfo() =>
    const PlatformInfo(platform: 'unknown', os: 'unknown', locale: 'unknown');
