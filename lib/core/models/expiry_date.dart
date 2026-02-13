import 'package:flutter/material.dart';

enum ExpiryStatus {
  safe,
  warning,
  danger,
  expired,
  unknown;

  Color get color {
    switch (this) {
      case ExpiryStatus.safe:
        return const Color(0xFF00C853); // Green
      case ExpiryStatus.warning:
        return const Color(0xFFFF9800); // Orange
      case ExpiryStatus.danger:
        return const Color(0xFFFF5722); // Deep Orange
      case ExpiryStatus.expired:
        return const Color(0xFFD32F2F); // Red
      case ExpiryStatus.unknown:
        return const Color(0xFF757575); // Gray
    }
  }

  String get label {
    switch (this) {
      case ExpiryStatus.safe:
        return 'GÜVENLİ';
      case ExpiryStatus.warning:
        return 'DİKKAT';
      case ExpiryStatus.danger:
        return 'YAKINDA BİTECEK';
      case ExpiryStatus.expired:
        return 'TARİHİ GEÇMİŞ';
      case ExpiryStatus.unknown:
        return 'TARİH BULUNAMADI';
    }
  }
}

class ExpiryDate {
  final DateTime? date;
  final ExpiryStatus status;
  final int? daysRemaining;
  final String originalText;
  final String rawDateString;      // For comparison (e.g., "12.2025")
  final String spokenDateString;   // For TTS (e.g., "Aralık 2025")

  const ExpiryDate({
    this.date,
    required this.status,
    this.daysRemaining,
    required this.originalText,
    required this.rawDateString,
    required this.spokenDateString,
  });

  factory ExpiryDate.fromDate(DateTime date, String originalText) {
    final now = DateTime.now();
    final daysRemaining = date.difference(now).inDays;

    ExpiryStatus status;
    if (daysRemaining < 0) {
      status = ExpiryStatus.expired;
    } else if (daysRemaining < 7) {
      status = ExpiryStatus.danger;
    } else if (daysRemaining < 30) {
      status = ExpiryStatus.warning;
    } else {
      status = ExpiryStatus.safe;
    }
    
    // Create raw date string for comparison
    final rawDateString = '${date.day}.${date.month}.${date.year}';
    
    // Create spoken date string (Turkish month names)
    final spokenDateString = _formatSpokenDate(date);

    return ExpiryDate(
      date: date,
      status: status,
      daysRemaining: daysRemaining,
      originalText: originalText,
      rawDateString: rawDateString,
      spokenDateString: spokenDateString,
    );
  }

  factory ExpiryDate.unknown(String originalText) {
    return ExpiryDate(
      status: ExpiryStatus.unknown,
      originalText: originalText,
      rawDateString: '',
      spokenDateString: 'Tarih bulunamadı',
    );
  }
  
  /// Format date for Turkish TTS (e.g., "15 Aralık 2025")
  static String _formatSpokenDate(DateTime date) {
    const turkishMonths = [
      'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
      'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık'
    ];
    
    final monthName = turkishMonths[date.month - 1];
    return '${date.day} $monthName ${date.year}';
  }

  String get statusMessage {
    if (status == ExpiryStatus.expired) {
      return 'TARİHİ GEÇMİŞ! $spokenDateString tarihinde sona erdi. TÜKETMEYİN!';
    } else if (status == ExpiryStatus.danger) {
      return 'YAKINDA BİTECEK: $daysRemaining gün kaldı. Son kullanma tarihi: $spokenDateString';
    } else if (status == ExpiryStatus.warning) {
      return 'DİKKAT: $daysRemaining gün kaldı. Son kullanma tarihi: $spokenDateString';
    } else if (status == ExpiryStatus.safe) {
      return 'GÜVENLİ: $daysRemaining gün kaldı. Son kullanma tarihi: $spokenDateString';
    } else {
      return 'SON KULLANMA TARİHİ BULUNAMADI';
    }
  }

  String get formattedDate {
    if (date == null) return 'Tarih bulunamadı';
    return '${date!.day}.${date!.month}.${date!.year}';
  }

  @override
  String toString() {
    return 'ExpiryDate(date: $formattedDate, status: ${status.label}, days: $daysRemaining)';
  }
}
