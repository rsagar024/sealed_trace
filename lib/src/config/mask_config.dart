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
    this.maskUserName = false,
    this.maskUrlPathSegments = false,
    this.pseudonymizeUserId = false,
  });

  /// Extra sensitive keys, matched on the whole key, ignoring case and the
  /// separators `_`, `-`, `.` and spaces.
  final List<String> extraKeys;

  /// Extra patterns whose matches are replaced in every string value.
  ///
  /// They run synchronously on every logged string (up to 100,000
  /// characters), so they must not backtrack catastrophically. A pattern
  /// with nested repetition (`(a+)+`, `(\w+\s?)*`, `(a?){30}`), repeated
  /// alternation (`(a|b)*`) or a backreference (`\1`), or one that matches
  /// the empty string, is ignored and reported through
  /// `SealedTrace.onException`. Prefer a literal prefix and bounded
  /// quantifiers, such as `\bORD-\d{6}\b`; avoid leading `.*`.
  final List<RegExp> extraPatterns;

  /// Extra header names to redact, in addition to the built-in denylist.
  final List<String> extraHeaderDenylist;

  /// Whether the built-in sensitive key list is applied.
  final bool useDefaultKeys;

  /// Whether the built-in PII patterns are applied.
  final bool useDefaultPatterns;

  /// Text that replaces masked values.
  final String replacement;

  /// When false (the default), the name passed to `SealedTrace.setUser(name:)`
  /// is sent as given in `ctx.userName`, so the console's log list and log
  /// detail can show it. When true it is sent as [replacement]. Either way it
  /// travels only inside the sealed envelope.
  ///
  /// Only the `setUser` name is exempt: a name anywhere else (message,
  /// metadata, `setContext`) is still masked, and `setContext` cannot set
  /// `ctx.userName`. `ctx.userDisplayName` is controlled separately by
  /// `SealedTraceConfig.sendUserDisplayName`.
  final bool maskUserName;

  /// When true, URL path segments that are not plain words are replaced in
  /// network logs: `/reset/9f8a2c/confirm` becomes `/reset/***/confirm`, and
  /// `/users/asha.rao/orders` becomes `/users/***/orders`. Kept segments are
  /// letters, `-` and `_` (up to 32) and version markers such as `v2`.
  /// Defaults to false, because ids in paths are often useful for debugging.
  final bool maskUrlPathSegments;

  /// When true, the id passed to `SealedTrace.setUser` is sent as its
  /// `SealedTrace.pseudonym` (`p_` plus 22 characters) instead of as given.
  /// Events from one user still group together in the console, but the raw
  /// id never leaves the device. Defaults to false.
  final bool pseudonymizeUserId;

  /// Returns a copy with the given fields replaced.
  MaskConfig copyWith({
    List<String>? extraKeys,
    List<RegExp>? extraPatterns,
    List<String>? extraHeaderDenylist,
    bool? useDefaultKeys,
    bool? useDefaultPatterns,
    String? replacement,
    bool? maskUserName,
    bool? maskUrlPathSegments,
    bool? pseudonymizeUserId,
  }) {
    return MaskConfig(
      extraKeys: extraKeys ?? this.extraKeys,
      extraPatterns: extraPatterns ?? this.extraPatterns,
      extraHeaderDenylist: extraHeaderDenylist ?? this.extraHeaderDenylist,
      useDefaultKeys: useDefaultKeys ?? this.useDefaultKeys,
      useDefaultPatterns: useDefaultPatterns ?? this.useDefaultPatterns,
      replacement: replacement ?? this.replacement,
      maskUserName: maskUserName ?? this.maskUserName,
      maskUrlPathSegments: maskUrlPathSegments ?? this.maskUrlPathSegments,
      pseudonymizeUserId: pseudonymizeUserId ?? this.pseudonymizeUserId,
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
      replacement == other.replacement &&
      maskUserName == other.maskUserName &&
      maskUrlPathSegments == other.maskUrlPathSegments &&
      pseudonymizeUserId == other.pseudonymizeUserId;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(extraKeys),
    Object.hashAll(extraPatterns),
    Object.hashAll(extraHeaderDenylist),
    useDefaultKeys,
    useDefaultPatterns,
    replacement,
    maskUserName,
    maskUrlPathSegments,
    pseudonymizeUserId,
  );
}
