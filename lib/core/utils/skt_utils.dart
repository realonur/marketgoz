class SktUtils {
  SktUtils._();

  static const Map<String, String> _charFixes = {
    'O': '0',
    'D': '0',
    'I': '1',
    'L': '1',
    'Z': '2',
    'S': '5',
    'B': '8',
    'G': '6',
  };

  static final List<RegExp> _patterns = [
    RegExp(r'\b(\d{2})\.(\d{2})\.(\d{4})\b'),
    RegExp(r'\b(\d{2})\.(\d{2})\.(\d{2})\b'),
    RegExp(r'\b(\d{2})\.(\d{4})\b'),
  ];

  /// Returns the first valid date string found after cleaning, or null.
  static String? findDate(String rawText) {
    if (rawText.trim().isEmpty) return null;

    final cleaned = _clean(rawText);

    for (final pattern in _patterns) {
      for (final match in pattern.allMatches(cleaned)) {
        final candidate = match.group(0);
        if (candidate != null && _isValidDate(match, pattern)) {
          return candidate;
        }
      }
    }

    return null;
  }

  static String _clean(String input) {
    final upper = input.toUpperCase();
    final buffer = StringBuffer();

    for (final char in upper.split('')) {
      buffer.write(_charFixes[char] ?? char);
    }

    return buffer.toString().replaceAll(RegExp(r'[/-]'), '.');
  }

  static bool _isValidDate(RegExpMatch match, RegExp pattern) {
    if (pattern == _patterns[0]) {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      return day >= 1 && day <= 31 && month >= 1 && month <= 12 && year >= 1900;
    }

    if (pattern == _patterns[1]) {
      final day = int.parse(match.group(1)!);
      final month = int.parse(match.group(2)!);
      final year = int.parse(match.group(3)!);
      return day >= 1 && day <= 31 && month >= 1 && month <= 12 && year >= 0;
    }

    if (pattern == _patterns[2]) {
      final month = int.parse(match.group(1)!);
      return month >= 1 && month <= 12;
    }

    return false;
  }
}
