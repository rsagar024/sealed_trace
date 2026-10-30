/// Shortest wait honored from a `Retry-After` header.
const Duration minRetryAfter = Duration(seconds: 1);

/// Longest wait honored, so a bad header cannot park uploads for days.
const Duration maxRetryAfter = Duration(hours: 1);

const List<String> _months = <String>[
  'jan', 'feb', 'mar', 'apr', 'may', 'jun', //
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

final RegExp _httpDate = RegExp(
  r'^[A-Za-z]{3}, (\d{1,2}) ([A-Za-z]{3}) (\d{4}) '
  r'(\d{2}):(\d{2}):(\d{2}) GMT$',
);

/// Parses a `Retry-After` value: a number of seconds, or an HTTP date.
///
/// The result is clamped to [minRetryAfter]..[maxRetryAfter]. Returns null when
/// the value is missing or cannot be understood.
Duration? parseRetryAfter(String? value, DateTime now) {
  final text = value?.trim();
  if (text == null || text.isEmpty) return null;

  final seconds = int.tryParse(text);
  if (seconds != null) {
    if (seconds < 0) return null;
    return _clamp(Duration(seconds: seconds));
  }

  final match = _httpDate.firstMatch(text);
  if (match == null) return null;
  final month = _months.indexOf(match[2]!.toLowerCase());
  if (month < 0) return null;
  final moment = DateTime.utc(
    int.parse(match[3]!),
    month + 1,
    int.parse(match[1]!),
    int.parse(match[4]!),
    int.parse(match[5]!),
    int.parse(match[6]!),
  );
  return _clamp(moment.difference(now.toUtc()));
}

Duration _clamp(Duration value) {
  if (value < minRetryAfter) return minRetryAfter;
  if (value > maxRetryAfter) return maxRetryAfter;
  return value;
}
