/// Builds the text that replaces a match, given the configured replacement.
typedef MaskReplacer = String Function(Match match, String replacement);

/// One pattern pass over a string.
class MaskRule {
  /// Creates a rule.
  ///
  /// [needsAt] and [needsDigit] let the engine skip the rule for strings that
  /// cannot match, which keeps the common case cheap.
  MaskRule(
    this.regex,
    this.replace, {
    this.needsAt = false,
    this.needsDigit = false,
  });

  /// The pattern.
  final RegExp regex;

  /// Produces the replacement for a match.
  final MaskReplacer replace;

  /// The rule can only match strings containing `@`.
  final bool needsAt;

  /// The rule can only match strings containing a digit.
  final bool needsDigit;
}

/// Whether [digits] passes the Luhn checksum.
bool luhnValid(String digits) {
  var sum = 0;
  var doubleIt = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var n = digits.codeUnitAt(i) - 48;
    if (doubleIt) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    doubleIt = !doubleIt;
  }
  return sum % 10 == 0;
}

final RegExp _separator = RegExp(r'[ \-]');

/// Whether [candidate] is grouped like a printed card number: 4-4-4-x or
/// 4-6-5 (Amex).
bool groupedLikeCard(String candidate) {
  final groups = candidate.split(_separator);
  if (groups.length == 4) {
    return groups[0].length == 4 &&
        groups[1].length == 4 &&
        groups[2].length == 4 &&
        groups[3].isNotEmpty &&
        groups[3].length <= 7;
  }
  if (groups.length == 3) {
    return groups[0].length == 4 &&
        groups[1].length == 6 &&
        groups[2].length == 5;
  }
  return false;
}

// Group 1 is the character before the match. Lookbehind is avoided because
// older Safari versions do not support it, so each replacer re-emits group 1.
String _keepPrefix(Match m, String replacement) => '${m[1]}$replacement';

/// The built-in PII rules, in the order they are applied.
///
/// Every quantifier is bounded, so matching time is linear in the input.
List<MaskRule> buildDefaultRules() => <MaskRule>[
  // Email.
  MaskRule(
    RegExp(
      r'[A-Za-z0-9._%+\-]{1,64}@[A-Za-z0-9\-]{1,63}'
      r'(?:\.[A-Za-z0-9\-]{1,63}){1,8}',
    ),
    (m, replacement) => replacement,
    needsAt: true,
  ),
  // Card-like numbers: 13 to 19 digits, single space or dash separators.
  MaskRule(RegExp(r'(^|[^\d])(\d(?:[ \-]?\d){12,18})(?!\d)'), (m, replacement) {
    final candidate = m[2]!;
    final digits = candidate.replaceAll(_separator, '');
    if (digits.length < 13 || digits.length > 19) return m[0]!;
    if (luhnValid(digits) || groupedLikeCard(candidate)) {
      return _keepPrefix(m, replacement);
    }
    return m[0]!;
  }, needsDigit: true),
  // Latitude/longitude pairs in decimal degrees.
  MaskRule(
    RegExp(
      r'(^|[^\d.\-])(-?\d{1,3}\.\d{3,12})\s{0,3}[,;]\s{0,3}'
      r'(-?\d{1,3}\.\d{3,12})(?!\d)',
    ),
    (m, replacement) {
      final lat = double.tryParse(m[2]!);
      final lon = double.tryParse(m[3]!);
      if (lat == null || lon == null) return m[0]!;
      if (lat.abs() > 90 || lon.abs() > 180) return m[0]!;
      return _keepPrefix(m, replacement);
    },
    needsDigit: true,
  ),
  // Indian mobile numbers: optional +91 / 91 / 0, then 10 digits from 6-9.
  MaskRule(
    RegExp(r'(^|[^\d])((?:\+91[ \-]?|91[ \-]?|0)?[6-9]\d{4}[ \-]?\d{5})(?!\d)'),
    _keepPrefix,
    needsDigit: true,
  ),
  // US numbers: (555) 123-4567, 555-123-4567, +1 555 123 4567.
  // Bare 10-digit runs and dotted forms are left alone on purpose.
  MaskRule(
    RegExp(
      r'(^|[^\d])((?:\+1[ \-]?)?\(\d{3}\)[ \-]?\d{3}[ \-]?\d{4}'
      r'|(?:\+1[ \-]?)?\d{3}[ \-]\d{3}[ \-]?\d{4}'
      r'|\+1[ \-]?\d{10})(?!\d)',
    ),
    _keepPrefix,
    needsDigit: true,
  ),
];
