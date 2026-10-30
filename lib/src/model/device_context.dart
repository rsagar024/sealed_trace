/// Device and app facts attached to every event as `ctx`.
class DeviceContext {
  /// Creates a device context.
  const DeviceContext({
    required this.appVersion,
    required this.buildNumber,
    required this.platform,
    required this.os,
    required this.locale,
  });

  /// App version such as `1.2.3`, or `unknown`.
  final String appVersion;

  /// App build number such as `45`, or `unknown`.
  final String buildNumber;

  /// `android`, `ios`, `web`, `windows`, `macos`, `linux` or `unknown`.
  final String platform;

  /// OS description such as `Android 14`.
  final String os;

  /// Locale such as `en_IN`.
  final String locale;
}
