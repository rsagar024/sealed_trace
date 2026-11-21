/// Reduces a browser user agent to `<browser> <major version> on <OS>` (L12).
///
/// The full user agent, which the web `ctx.os` used to carry (up to 120
/// characters), adds fingerprinting detail the console does not need: minor
/// versions, device models, engine builds. Returns `'web'` when nothing is
/// recognised. Pure Dart, so it is tested on the VM.
String coarseUserAgent(String agent) {
  final browser = _browser(agent);
  final os = _os(agent);
  if (browser == null && os == null) return 'web';
  if (browser == null) return os!;
  if (os == null) return browser;
  return '$browser on $os';
}

String? _browser(String a) {
  // Order matters: Edge and Opera also say "Chrome", Chrome also "Safari".
  for (final (pattern, name) in _browsers) {
    final match = pattern.firstMatch(a);
    if (match != null) return '$name ${match[1]}';
  }
  return null;
}

final List<(RegExp, String)> _browsers = [
  (RegExp(r'Edg(?:e|A|iOS)?/(\d{1,4})'), 'Edge'),
  (RegExp(r'(?:OPR|Opera)/(\d{1,4})'), 'Opera'),
  (RegExp(r'SamsungBrowser/(\d{1,4})'), 'Samsung Internet'),
  (RegExp(r'(?:Firefox|FxiOS)/(\d{1,4})'), 'Firefox'),
  (RegExp(r'(?:Chrome|CriOS)/(\d{1,4})'), 'Chrome'),
  (RegExp(r'Version/(\d{1,4})[\d.]* (?:Mobile/\S+ )?Safari/'), 'Safari'),
];

String? _os(String a) {
  if (a.contains('Windows')) return 'Windows';
  if (a.contains('Android')) return 'Android';
  if (a.contains('iPhone') || a.contains('iPad') || a.contains('iPod')) {
    return 'iOS';
  }
  if (a.contains('CrOS')) return 'ChromeOS';
  if (a.contains('Mac OS X') || a.contains('Macintosh')) return 'macOS';
  if (a.contains('Linux')) return 'Linux';
  return null;
}
