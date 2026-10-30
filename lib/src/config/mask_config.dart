import 'equality.dart';

/// Configures the masking (PII redaction) applied before events are sealed.
class MaskConfig {
  /// Creates a masking configuration.
  const MaskConfig({
    this.extraKeys = const [],
    this.extraPatterns = const [],
    this.extraHeaderDenylist = const [],
    this.useDefaultKeys = true,
    this.useDefaultPatterns = true,
    this.replacement = '***',
  });

  /// Extra sensitive keys, matched exactly and case-insensitively.
  final List<String> extraKeys;

  /// Extra patterns whose matches are replaced in every string value.
  final List<RegExp> extraPatterns;

  /// Extra header names to redact, in addition to the built-in denylist.
  final List<String> extraHeaderDenylist;

  /// Whether the built-in sensitive key list is applied.
  final bool useDefaultKeys;

  /// Whether the built-in PII patterns are applied.
  final bool useDefaultPatterns;

  /// Text that replaces masked values.
  final String replacement;

  /// Returns a copy with the given fields replaced.
  MaskConfig copyWith({
    List<String>? extraKeys,
    List<RegExp>? extraPatterns,
    List<String>? extraHeaderDenylist,
    bool? useDefaultKeys,
    bool? useDefaultPatterns,
    String? replacement,
  }) {
    return MaskConfig(
      extraKeys: extraKeys ?? this.extraKeys,
      extraPatterns: extraPatterns ?? this.extraPatterns,
      extraHeaderDenylist: extraHeaderDenylist ?? this.extraHeaderDenylist,
      useDefaultKeys: useDefaultKeys ?? this.useDefaultKeys,
      useDefaultPatterns: useDefaultPatterns ?? this.useDefaultPatterns,
      replacement: replacement ?? this.replacement,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is MaskConfig &&
      listsEqual(extraKeys, other.extraKeys) &&
      listsEqual(extraPatterns, other.extraPatterns) &&
      listsEqual(extraHeaderDenylist, other.extraHeaderDenylist) &&
      useDefaultKeys == other.useDefaultKeys &&
      useDefaultPatterns == other.useDefaultPatterns &&
      replacement == other.replacement;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(extraKeys),
    Object.hashAll(extraPatterns),
    Object.hashAll(extraHeaderDenylist),
    useDefaultKeys,
    useDefaultPatterns,
    replacement,
  );
}
