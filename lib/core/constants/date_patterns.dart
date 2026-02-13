/// Regular expression patterns for detecting Turkish expiry date formats
class DatePatterns {
  DatePatterns._();
  
  // SKT: DD.MM.YYYY or SKT: DD.MM.YY
  static final RegExp sktDayMonthYear = RegExp(
    r'SKT[:\.\s]*(\d{2})[./](\d{2})[./](\d{2,4})',
    caseSensitive: false,
  );
  
  // SKT: MM.YYYY or SKT: MM.YY (only month and year)
  static final RegExp sktMonthYear = RegExp(
    r'SKT[:\.\s]*(\d{2})[./](\d{4})',
    caseSensitive: false,
  );
  
  // TETT: MM/DD/YY (US format sometimes used)
  static final RegExp tettFormat = RegExp(
    r'TETT[:\.\s]*(\d{2})[./](\d{2})[./]?(\d{2,4})?',
    caseSensitive: false,
  );
  
  // Son Kullanma Tarihi: DD.MM.YYYY
  static final RegExp sonKullanmaTarihi = RegExp(
    r'Son\s+Kullanma\s+Tarihi[:\.\s]*(\d{2})[./](\d{2})[./](\d{2,4})',
    caseSensitive: false,
  );
  
  // BB: DD.MM.YYYY (Best Before)
  static final RegExp bestBefore = RegExp(
    r'BB[:\.\s]*(\d{2})[./](\d{2})[./](\d{2,4})',
    caseSensitive: false,
  );
  
  // Generic date pattern DD.MM.YYYY (fallback)
  static final RegExp genericDate = RegExp(
    r'\b(\d{2})[./](\d{2})[./](\d{2,4})\b',
  );
  
  /// All patterns to try in order of priority
  static final List<RegExp> allPatterns = [
    sktDayMonthYear,
    sonKullanmaTarihi,
    sktMonthYear,
    tettFormat,
    bestBefore,
    genericDate,
  ];
}
