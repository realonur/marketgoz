import '../constants/date_patterns.dart';
import '../models/expiry_date.dart';

class DateParser {
  DateParser._();

  /// Parse expiry date from OCR text
  static ExpiryDate? parseExpiryDate(List<String> textBlocks) {
    for (final text in textBlocks) {
      // Try each regex pattern
      for (final pattern in DatePatterns.allPatterns) {
        final match = pattern.firstMatch(text);
        if (match != null) {
          final date = _extractDateFromMatch(match, pattern);
          if (date != null) {
            return ExpiryDate.fromDate(date, text);
          }
        }
      }
    }
    
    return null;
  }

  /// Extract DateTime from regex match
  static DateTime? _extractDateFromMatch(RegExpMatch match, RegExp pattern) {
    try {
      // Handle different date formats
      if (pattern == DatePatterns.sktMonthYear) {
        // Format: MM.YYYY
        final month = int.parse(match.group(1)!);
        final year = int.parse(match.group(2)!);
        
        if (month < 1 || month > 12) return null;
        
        // Use last day of the month for month-only dates
        return DateTime(year, month, _getLastDayOfMonth(year, month));
      } else if (pattern == DatePatterns.sktDayMonthYear ||
          pattern == DatePatterns.sonKullanmaTarihi ||
          pattern == DatePatterns.bestBefore ||
          pattern == DatePatterns.genericDate) {
        // Format: DD.MM.YYYY or DD.MM.YY
        final day = int.parse(match.group(1)!);
        final month = int.parse(match.group(2)!);
        var year = int.parse(match.group(3)!);
        
        // Handle 2-digit year
        if (year < 100) {
          year += 2000;
        }
        
        // Validate date components
        if (day < 1 || day > 31 || month < 1 || month > 12) return null;
        
        return DateTime(year, month, day);
      } else if (pattern == DatePatterns.tettFormat) {
        // Format: MM/DD/YY or MM/DD/YYYY (US format)
        final month = int.parse(match.group(1)!);
        final day = int.parse(match.group(2)!);
        var year = match.group(3) != null ? int.parse(match.group(3)!) : DateTime.now().year;
        
        // Handle 2-digit year
        if (year < 100) {
          year += 2000;
        }
        
        // Validate date components
        if (day < 1 || day > 31 || month < 1 || month > 12) return null;
        
        return DateTime(year, month, day);
      }
    } catch (e) {
      print('Error parsing date: $e');
    }
    
    return null;
  }

  /// Get the last day of a specific month
  static int _getLastDayOfMonth(int year, int month) {
    // Create date for first day of next month, then subtract one day
    final nextMonth = month == 12 ? DateTime(year + 1, 1, 1) : DateTime(year, month + 1, 1);
    final lastDay = nextMonth.subtract(const Duration(days: 1));
    return lastDay.day;
  }

  /// Find all potential dates in text (for debugging)
  static List<String> findAllDates(List<String> textBlocks) {
    final foundDates = <String>[];
    
    for (final text in textBlocks) {
      for (final pattern in DatePatterns.allPatterns) {
        final matches = pattern.allMatches(text);
        for (final match in matches) {
          foundDates.add(match.group(0)!);
        }
      }
    }
    
    return foundDates;
  }
}
