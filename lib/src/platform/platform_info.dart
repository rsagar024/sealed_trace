/// Static facts about the host platform, read once at init.
class PlatformInfo {
  /// Creates platform info.
  const PlatformInfo({
    required this.platform,
    required this.os,
    required this.locale,
  });

  /// One of `android`, `ios`, `web`, `windows`, `macos`, `linux`, `unknown`.
  final String platform;

  /// Human-readable OS description.
  final String os;

  /// Locale such as `en_IN`, or `unknown`.
  final String locale;
}
