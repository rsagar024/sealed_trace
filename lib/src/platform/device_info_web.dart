import 'package:web/web.dart' as web;

import 'platform_info.dart';

/// Reads platform facts in the browser.
PlatformInfo readPlatformInfo() {
  var locale = 'unknown';
  var os = 'web';
  try {
    final language = web.window.navigator.language;
    if (language.isNotEmpty) locale = language.replaceAll('-', '_');
    final agent = web.window.navigator.userAgent;
    if (agent.isNotEmpty) {
      os = agent.length > 120 ? agent.substring(0, 120) : agent;
    }
  } catch (_) {
    // Keep the defaults.
  }
  return PlatformInfo(platform: 'web', os: os, locale: locale);
}
