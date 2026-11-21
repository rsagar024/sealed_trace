import 'package:web/web.dart' as web;

import 'platform_info.dart';
import 'user_agent.dart';

/// Reads platform facts in the browser.
PlatformInfo readPlatformInfo() {
  var locale = 'unknown';
  var os = 'web';
  try {
    final language = web.window.navigator.language;
    if (language.isNotEmpty) locale = language.replaceAll('-', '_');
    // Only the browser, its major version and the OS, never the full user
    // agent (L12).
    os = coarseUserAgent(web.window.navigator.userAgent);
  } catch (_) {
    // Keep the defaults.
  }
  return PlatformInfo(platform: 'web', os: os, locale: locale);
}
