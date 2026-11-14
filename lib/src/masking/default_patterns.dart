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

final RegExp _separator = _spaces;

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

/// Whether [iban] (no spaces) passes the ISO 13616 mod-97 check.
bool ibanValid(String iban) {
  if (iban.length < 15 || iban.length > 34) return false;
  final rearranged = iban.substring(4) + iban.substring(0, 4);
  var remainder = 0;
  for (var i = 0; i < rearranged.length; i++) {
    final unit = rearranged.codeUnitAt(i);
    if (unit >= 0x30 && unit <= 0x39) {
      remainder = (remainder * 10 + unit - 0x30) % 97;
    } else if (unit >= 0x41 && unit <= 0x5A) {
      remainder = (remainder * 100 + unit - 0x41 + 10) % 97;
    } else {
      return false;
    }
  }
  return remainder == 1;
}

const List<List<int>> _verhoeffD = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 2, 3, 4, 0, 6, 7, 8, 9, 5],
  [2, 3, 4, 0, 1, 7, 8, 9, 5, 6],
  [3, 4, 0, 1, 2, 8, 9, 5, 6, 7],
  [4, 0, 1, 2, 3, 9, 5, 6, 7, 8],
  [5, 9, 8, 7, 6, 0, 4, 3, 2, 1],
  [6, 5, 9, 8, 7, 1, 0, 4, 3, 2],
  [7, 6, 5, 9, 8, 2, 1, 0, 4, 3],
  [8, 7, 6, 5, 9, 3, 2, 1, 0, 4],
  [9, 8, 7, 6, 5, 4, 3, 2, 1, 0],
];

const List<List<int>> _verhoeffP = [
  [0, 1, 2, 3, 4, 5, 6, 7, 8, 9],
  [1, 5, 7, 6, 2, 8, 3, 0, 9, 4],
  [5, 8, 0, 3, 7, 9, 6, 1, 4, 2],
  [8, 9, 1, 6, 0, 4, 3, 5, 2, 7],
  [9, 4, 5, 3, 1, 2, 6, 8, 7, 0],
  [4, 2, 8, 6, 5, 7, 3, 9, 0, 1],
  [2, 7, 9, 3, 8, 0, 6, 4, 1, 5],
  [7, 0, 4, 6, 9, 1, 3, 2, 5, 8],
];

/// Whether [digits] passes the Verhoeff checksum (used by Aadhaar numbers).
bool verhoeffValid(String digits) {
  var c = 0;
  for (var i = 0; i < digits.length; i++) {
    final n = digits.codeUnitAt(digits.length - 1 - i) - 0x30;
    if (n < 0 || n > 9) return false;
    c = _verhoeffD[c][_verhoeffP[i % 8][n]];
  }
  return c == 0;
}

/// Whether area-group-serial is a possible US Social Security Number.
bool ssnValid(String area, String group, String serial) {
  final a = int.parse(area);
  return a != 0 &&
      a != 666 &&
      a < 900 &&
      int.parse(group) != 0 &&
      int.parse(serial) != 0;
}

final RegExp _hexDigit = RegExp('[0-9A-Fa-f]');

/// Whether [candidate] is a real IPv6 address with at least one hex digit.
bool ipv6Valid(String candidate) {
  if (!_hexDigit.hasMatch(candidate)) return false;
  try {
    Uri.parseIPv6Address(candidate);
    return true;
  } on FormatException {
    return false;
  }
}

final RegExp _spaces = RegExp(r'[ \-]');

// Group 1 is the character before the match. Lookbehind is avoided because
// older Safari versions do not support it, so each replacer re-emits group 1.
String _keepPrefix(Match m, String replacement) => '${m[1]}$replacement';

/// The built-in PII rules, in the order they are applied.
///
/// Every quantifier is bounded, so matching time is linear in the input.
List<MaskRule> buildDefaultRules() => <MaskRule>[
  // JWTs (header.payload.signature, base64url), anywhere in a string: JSON
  // values, log messages, URL paths. The signature may be empty (alg none).
  MaskRule(
    RegExp(
      r'(^|[^A-Za-z0-9_\-])(eyJ[A-Za-z0-9_\-]{2,8000}\.[A-Za-z0-9_\-]{2,8000}'
      r'\.[A-Za-z0-9_\-]{0,8000})',
    ),
    _keepPrefix,
  ),
  // Bearer tokens: the scheme word is kept, the token is replaced.
  MaskRule(
    RegExp(r'\b(Bearer)(\s+)[A-Za-z0-9._~+/=\-]{6,2000}', caseSensitive: false),
    (m, replacement) => '${m[1]}${m[2]}$replacement',
  ),
  // API keys with a recognisable prefix: AWS access key ids, Stripe secret
  // and restricted keys, GitHub tokens, Google API keys, Slack and GitLab
  // tokens. Publishable keys (`pk_...`) are not secrets and are kept.
  MaskRule(
    RegExp(
      r'(^|[^A-Za-z0-9_])((?:AKIA|ASIA|AGPA|AIDA|AROA|ANPA)[0-9A-Z]{16}'
      r'|(?:sk|rk)_(?:live|test)_[0-9A-Za-z]{10,247}'
      r'|gh[pousr]_[A-Za-z0-9]{36,251}'
      r'|github_pat_[A-Za-z0-9_]{22,255}'
      r'|AIza[0-9A-Za-z_\-]{35}'
      r'|xox[abposr]-[A-Za-z0-9\-]{10,250}'
      r'|glpat-[A-Za-z0-9_\-]{20,64})',
    ),
    _keepPrefix,
  ),
  // IBAN: country code, check digits, 11 to 30 more characters, optionally
  // grouped by four; only matches that pass the mod-97 check.
  MaskRule(
    RegExp(
      r'(^|[^A-Za-z0-9])([A-Z]{2}\d{2}(?: ?[A-Z0-9]{4}){2,7}(?: ?[A-Z0-9]{1,4})?)'
      r'(?![A-Za-z0-9])',
    ),
    (m, replacement) => ibanValid(m[2]!.replaceAll(' ', ''))
        ? _keepPrefix(m, replacement)
        : m[0]!,
    needsDigit: true,
  ),
  // US Social Security Numbers, dashed (bare nine-digit runs are too common).
  MaskRule(
    RegExp(r'(^|[^\d\-])(\d{3})-(\d{2})-(\d{4})(?![\d\-])'),
    (m, replacement) =>
        ssnValid(m[2]!, m[3]!, m[4]!) ? _keepPrefix(m, replacement) : m[0]!,
    needsDigit: true,
  ),
  // Aadhaar: 12 digits starting 2-9, optionally grouped 4-4-4, that pass the
  // Verhoeff checksum.
  MaskRule(
    RegExp(r'(^|[^\d])([2-9]\d{3}[ \-]?\d{4}[ \-]?\d{4})(?!\d)'),
    (m, replacement) => verhoeffValid(m[2]!.replaceAll(_spaces, ''))
        ? _keepPrefix(m, replacement)
        : m[0]!,
    needsDigit: true,
  ),
  // Indian PAN: five letters (the fourth is the holder type), four digits,
  // one letter.
  MaskRule(
    RegExp(
      r'(^|[^A-Za-z0-9])([A-Z]{3}[ABCFGHJLPT][A-Z]\d{4}[A-Z])(?![A-Za-z0-9])',
    ),
    _keepPrefix,
    needsDigit: true,
  ),
  // IPv6 addresses (validated, so times like 10:30:45 are kept). Runs before
  // the IPv4 rule so an embedded IPv4 tail goes with it.
  MaskRule(
    RegExp(
      r'(^|[^0-9A-Za-z:.])((?:[0-9A-Fa-f]{0,4}:){2,7}'
      r'(?:[0-9A-Fa-f]{0,4}|\d{1,3}(?:\.\d{1,3}){3}))(?![0-9A-Za-z:])',
    ),
    (m, replacement) => ipv6Valid(m[2]!) ? _keepPrefix(m, replacement) : m[0]!,
    needsDigit: true,
  ),
  // IPv4 addresses (each part 0-255). A sentence-ending dot is allowed.
  MaskRule(
    RegExp(
      r'(^|[^\d.])((?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)'
      r'(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3})(?!\d|\.\d)',
    ),
    _keepPrefix,
    needsDigit: true,
  ),
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
