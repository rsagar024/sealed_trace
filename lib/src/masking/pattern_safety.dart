/// Static ReDoS check for custom mask patterns (L13).
///
/// Custom patterns run synchronously on every logged string (up to
/// `MaskingEngine.maxStringChars`), and Dart cannot interrupt a running
/// `RegExp`, so a pattern that backtracks exponentially would freeze the
/// caller's thread. This check rejects, before a pattern is ever used, the
/// constructs behind exponential backtracking:
///
/// - **Nested repetition:** a group that contains a variable quantifier
///   (`?`, `*`, `+`, `{n,}`, `{n,m}` with n < m) repeated by a quantifier
///   that allows more than one pass: `(a+)+`, `(\w+\s?)*`, `(a?){30}`.
/// - **Repeated alternation:** a group containing `|` repeated more than
///   once: `(a|a)*`, `(\w|\d)+`, `(a|ab){0,40}`.
/// - **Backreferences:** `\1`, `\k<name>`.
///
/// It is deliberately conservative: some safe patterns such as
/// `(?:\.\d{1,3}){3}` are rejected and must be unrolled
/// (`\.\d{1,3}\.\d{1,3}\.\d{1,3}`). It does not catch polynomial cost, such
/// as `.*x` or `[A-Z]+-` on a long run of matching characters.
library;

/// Longest pattern source accepted.
const int maxPatternSourceChars = 1000;

/// Why [source] is unsafe as a mask pattern, or null when it passes.
String? unsafePatternReason(String source) {
  if (source.length > maxPatternSourceChars) {
    return 'the pattern is longer than $maxPatternSourceChars characters';
  }
  try {
    final parser = _Parser(source);
    parser.alternation();
    if (parser.i < source.length) {
      throw const FormatException('unbalanced ")"');
    }
    return null;
  } on _Unsafe catch (e) {
    return e.reason;
  } on FormatException catch (e) {
    return 'the pattern could not be checked (${e.message})';
  }
}

class _Unsafe implements Exception {
  const _Unsafe(this.reason);
  final String reason;
}

/// What a parsed piece of pattern contains, anywhere inside it.
class _Info {
  bool variable = false;
  bool alternation = false;

  void add(_Info other) {
    variable |= other.variable;
    alternation |= other.alternation;
  }
}

class _Parser {
  _Parser(this.s);

  final String s;
  int i = 0;

  bool get _done => i >= s.length;
  String get _c => s[i];

  /// sequence ('|' sequence)*, up to an unmatched ')' or the end.
  _Info alternation() {
    final info = sequence();
    while (!_done && _c == '|') {
      i++;
      info
        ..alternation = true
        ..add(sequence());
    }
    return info;
  }

  _Info sequence() {
    final info = _Info();
    while (!_done && _c != '|' && _c != ')') {
      final start = i;
      final atomInfo = atom();
      final q = quantifier();
      if (q != null) {
        final (min, max) = q;
        final repeats = max == null || max > 1;
        if (repeats && atomInfo.variable) {
          throw _Unsafe(
            'nested repetition at "${_excerpt(start)}": a repeated group '
            'contains a variable quantifier, which can backtrack '
            'exponentially; use one bounded quantifier instead',
          );
        }
        if (repeats && atomInfo.alternation) {
          throw _Unsafe(
            'repeated alternation at "${_excerpt(start)}": a repeated group '
            'contains "|", which can backtrack exponentially; use a '
            'character class or unroll the repetition',
          );
        }
        if (min != max) atomInfo.variable = true;
      }
      info.add(atomInfo);
    }
    return info;
  }

  String _excerpt(int start) {
    final end = i - start > 40 ? start + 40 : i;
    return s.substring(start, end);
  }

  _Info atom() {
    final c = _c;
    switch (c) {
      case '(':
        i++;
        _groupPrefix();
        final inner = alternation();
        if (_done || _c != ')') throw const FormatException('unclosed "("');
        i++;
        return inner;
      case '[':
        _characterClass();
        return _Info();
      case r'\':
        _escape();
        return _Info();
      case '*':
      case '+':
      case '?':
        throw FormatException('nothing to repeat before "$c"');
      case '{':
        if (_quantifierBraceAt(i) != null) {
          throw const FormatException('nothing to repeat before "{"');
        }
        i++;
        return _Info();
      default:
        i++;
        return _Info();
    }
  }

  void _groupPrefix() {
    if (_done || _c != '?') return;
    i++;
    if (_done) throw const FormatException('bad group');
    final c = _c;
    if (c == ':' || c == '=' || c == '!') {
      i++;
    } else if (c == '<') {
      i++;
      if (!_done && (_c == '=' || _c == '!')) {
        i++;
      } else {
        final close = s.indexOf('>', i);
        if (close < 0) throw const FormatException('bad group name');
        i = close + 1;
      }
    } else {
      throw const FormatException('bad group');
    }
  }

  void _characterClass() {
    i++; // '['
    if (!_done && _c == '^') i++;
    while (!_done && _c != ']') {
      if (_c == r'\') {
        i += 2;
      } else {
        i++;
      }
    }
    if (_done) throw const FormatException('unclosed "["');
    i++; // ']'
  }

  void _escape() {
    i++; // '\'
    if (_done) throw const FormatException(r'trailing "\"');
    final c = _c;
    final unit = c.codeUnitAt(0);
    if (unit >= 0x31 && unit <= 0x39) {
      throw const _Unsafe('backreferences are not allowed in mask patterns');
    }
    if (c == 'k' && i + 1 < s.length && s[i + 1] == '<') {
      throw const _Unsafe('backreferences are not allowed in mask patterns');
    }
    i++;
    if ((c == 'u' || c == 'p' || c == 'P') && !_done && _c == '{') {
      final close = s.indexOf('}', i);
      if (close < 0) throw const FormatException('unclosed "{"');
      i = close + 1;
    }
  }

  /// Parses an optional quantifier and lazy `?`; returns (min, max), with a
  /// null max meaning unbounded.
  (int, int?)? quantifier() {
    if (_done) return null;
    (int, int?) q;
    switch (_c) {
      case '*':
        q = (0, null);
        i++;
      case '+':
        q = (1, null);
        i++;
      case '?':
        q = (0, 1);
        i++;
      case '{':
        final brace = _quantifierBraceAt(i);
        if (brace == null) return null;
        final (min, max, end) = brace;
        q = (min, max);
        i = end;
      default:
        return null;
    }
    if (!_done && _c == '?') i++;
    return q;
  }

  /// A `{n}`, `{n,}` or `{n,m}` starting at [at]: (min, max, index after).
  (int, int?, int)? _quantifierBraceAt(int at) {
    final m = _brace.matchAsPrefix(s, at);
    if (m == null) return null;
    final min = int.parse(m[1]!);
    final int? max;
    if (m[2] == null) {
      max = min;
    } else if (m[3] == null || m[3]!.isEmpty) {
      max = null;
    } else {
      max = int.parse(m[3]!);
    }
    return (min, max, m.end);
  }

  static final RegExp _brace = RegExp(r'\{(\d+)(,(\d*))?\}');
}
