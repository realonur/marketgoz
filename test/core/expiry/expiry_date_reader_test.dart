import 'package:flutter_test/flutter_test.dart';
import 'package:marketgoz/core/expiry/expiry_date_reader.dart';
import 'package:marketgoz/core/expiry/ocr_frame.dart';

final _now = DateTime(2026, 3, 3);
final _reader = ExpiryDateReader(clock: () => _now);

OcrFrame _frame(List<OcrLine> lines) => OcrFrame(
      timestamp: _now,
      imageWidth: 1000,
      imageHeight: 2000,
      lines: lines,
    );

OcrLine _line(String text, [double top = 500, double left = 100, double w = 500]) =>
    OcrLine(text: text, box: BoxD.fromLTWH(left, top, w, 50));

List<DateCandidate> _read(String text) => _reader.read(_frame([_line(text)]));

DateCandidate? _best(String text) {
  final r = _read(text);
  return r.isEmpty ? null : r.first;
}

void main() {
  group('formats', () {
    final cases = <String, (DateTime, DatePrecision)>{
      '15.03.2026': (DateTime(2026, 3, 15), DatePrecision.day),
      '15/03/2026': (DateTime(2026, 3, 15), DatePrecision.day),
      '15-03-2026': (DateTime(2026, 3, 15), DatePrecision.day),
      '15 03 2026': (DateTime(2026, 3, 15), DatePrecision.day),
      '15 . 03 . 2026': (DateTime(2026, 3, 15), DatePrecision.day),
      '15.03.26': (DateTime(2026, 3, 15), DatePrecision.day),
      '2026.03.15': (DateTime(2026, 3, 15), DatePrecision.day),
      '2026-03-15': (DateTime(2026, 3, 15), DatePrecision.day),
      '03.2026': (DateTime(2026, 3, 31), DatePrecision.monthYear),
      '03/26': (DateTime(2026, 3, 31), DatePrecision.monthYear),
      '02/2028': (DateTime(2028, 2, 29), DatePrecision.monthYear),
      '15 MAR 26': (DateTime(2026, 3, 15), DatePrecision.day),
      '15MAR2026': (DateTime(2026, 3, 15), DatePrecision.day),
      'MAR 2026': (DateTime(2026, 3, 31), DatePrecision.monthYear),
      '15 Mart 2026': (DateTime(2026, 3, 15), DatePrecision.day),
      '10 OCA 27': (DateTime(2027, 1, 10), DatePrecision.day),
      '10 ŞUB 27': (DateTime(2027, 2, 10), DatePrecision.day),
      '10 SUB 27': (DateTime(2027, 2, 10), DatePrecision.day),
      '10 NİS 27': (DateTime(2027, 4, 10), DatePrecision.day),
      '10 NIS 27': (DateTime(2027, 4, 10), DatePrecision.day),
      '10 HAZ 27': (DateTime(2027, 6, 10), DatePrecision.day),
      '10 TEM 27': (DateTime(2027, 7, 10), DatePrecision.day),
      '10 AĞU 27': (DateTime(2027, 8, 10), DatePrecision.day),
      '10 AGU 27': (DateTime(2027, 8, 10), DatePrecision.day),
      '10 EYL 27': (DateTime(2027, 9, 10), DatePrecision.day),
      '10 EKİ 27': (DateTime(2027, 10, 10), DatePrecision.day),
      '10 EKI 27': (DateTime(2027, 10, 10), DatePrecision.day),
      '10 KAS 27': (DateTime(2027, 11, 10), DatePrecision.day),
      '10 ARA 27': (DateTime(2027, 12, 10), DatePrecision.day),
      '10 JAN 27': (DateTime(2027, 1, 10), DatePrecision.day),
      '10 FEB 27': (DateTime(2027, 2, 10), DatePrecision.day),
      '10 APR 27': (DateTime(2027, 4, 10), DatePrecision.day),
      '10 jun 27': (DateTime(2027, 6, 10), DatePrecision.day),
      '10 JUL 27': (DateTime(2027, 7, 10), DatePrecision.day),
      '10 AUG 27': (DateTime(2027, 8, 10), DatePrecision.day),
      '10 SEP 27': (DateTime(2027, 9, 10), DatePrecision.day),
      '10 OCT 27': (DateTime(2027, 10, 10), DatePrecision.day),
      '10 NOV 27': (DateTime(2027, 11, 10), DatePrecision.day),
      '10 DEC 27': (DateTime(2027, 12, 10), DatePrecision.day),
      '10 MAY 27': (DateTime(2027, 5, 10), DatePrecision.day),
    };
    cases.forEach((text, expected) {
      test(text, () {
        final c = _best(text);
        expect(c, isNotNull, reason: text);
        expect(c!.date, expected.$1);
        expect(c.precision, expected.$2);
      });
    });

    test('dot-matrix "15 03 26" parses next to an expiry keyword', () {
      final c = _best('SKT 15 03 26');
      expect(c!.date, DateTime(2026, 3, 15));
      expect(c.kind, DateKind.expiry);
    });

    test('bare space-separated two-digit-year groups are ignored', () {
      expect(_read('15 03 26'), isEmpty);
    });

    test('DDMMYY run-together only next to a keyword', () {
      expect(_read('150326'), isEmpty);
      final c = _best('SKT 150326');
      expect(c!.date, DateTime(2026, 3, 15));
      expect(_best('EXP: 15032026')!.date, DateTime(2026, 3, 15));
    });
  });

  group('keywords', () {
    final expiry = [
      'SKT 15.03.2026',
      'S.K.T. 15.03.2026',
      'S.K.T 15.03.2026',
      'skt: 15.03.2026',
      'Son Kullanma Tarihi: 15.03.2026',
      'SON KULLANMA TARİHİ 15.03.2026',
      'Son Kul. Tar. 15.03.2026',
      'Son Tük. Tar. 15.03.2026',
      'TETT 15.03.2026',
      'T.E.T.T. 15.03.2026',
      'TETT: 15.03.2026',
      'Tavsiye Edilen Tüketim Tarihi 15.03.2026',
      'EXP 15.03.2026',
      'EXP. 15.03.2026',
      'Best Before 15.03.2026',
      'BB 15.03.2026',
      'BBE 15.03.2026',
      'Use By 15.03.2026',
      'Tüketim Tarihi 15.03.2026',
      'EXP15.03.2026',
      'S K T 15.03.2026',
      'S . K . T 15.03.2026',
      'T E T T 15.03.2026',
      'E X P 15.03.2026',
    ];
    for (final t in expiry) {
      test('expiry: $t', () {
        final c = _best(t);
        expect(c, isNotNull);
        expect(c!.kind, DateKind.expiry);
        expect(c.date, DateTime(2026, 3, 15));
        expect(c.score, greaterThan(0.85));
      });
    }

    test('letter-spaced dot-matrix keyword with OCR O for zero', () {
      final c = _best('S K T 2O.11.2026');
      expect(c, isNotNull);
      expect(c!.kind, DateKind.expiry);
      expect(c.date, DateTime(2026, 11, 20));
    });

    final production = [
      'ÜT 15.03.2026',
      'Ü.T. 15.03.2026',
      'Ü T 15.03.2026',
      'Üretim Tarihi 15.03.2026',
      'Ür. Tar. 15.03.2026',
      'PROD 15.03.2026',
      'P.D. 15.03.2026',
      'MFG 15.03.2026',
      'MFD: 15.03.2026',
    ];
    for (final t in production) {
      test('production: $t', () {
        final c = _best(t);
        expect(c, isNotNull);
        expect(c!.kind, DateKind.production);
        expect(c.score, lessThan(0.3));
      });
    }

    test('both labels on one line are split by position', () {
      final r = _read('ÜT 01.02.2026 SKT 01.02.2027');
      expect(r.first.kind, DateKind.expiry);
      expect(r.first.date, DateTime(2027, 2, 1));
      expect(r.where((c) => c.kind == DateKind.production).single.date,
          DateTime(2026, 2, 1));
    });

    test('keyword on the line above', () {
      final r = _reader.read(_frame([
        _line('Son Kullanma Tarihi', 400),
        _line('15.03.2026', 460),
      ]));
      expect(r.single.kind, DateKind.expiry);
    });

    test('keyword to the left on the same row', () {
      final r = _reader.read(_frame([
        _line('SKT', 400, 50, 100),
        _line('15.03.2026', 402, 200, 300),
      ]));
      expect(r.single.kind, DateKind.expiry);
    });

    test('production label on the line above', () {
      final r = _reader.read(_frame([
        _line('Üretim Tarihi', 400),
        _line('15.03.2026', 460),
      ]));
      expect(r.single.kind, DateKind.production);
    });

    test('keyword far above is not bound', () {
      final r = _reader.read(_frame([
        _line('SKT', 100),
        _line('15.03.2026', 700),
      ]));
      expect(r.single.kind, DateKind.unknown);
    });

    test('lot line numbers are skipped', () {
      expect(_read('LOT 15.03.2026'), isEmpty);
      expect(_read('Parti No: 150326'), isEmpty);
      expect(_read('Seri No 15032026'), isEmpty);
      final r = _reader.read(_frame([
        _line('LOT', 400),
        _line('15.03.2026', 460),
      ]));
      expect(r, isEmpty);
    });

    test('date after a lot number but with its own keyword still counts', () {
      final c = _best('LOT 123 SKT 15.03.2026');
      expect(c!.kind, DateKind.expiry);
    });
  });

  group('OCR confusion repair', () {
    final cases = {
      'SKT 15.O3.2O26': DateTime(2026, 3, 15),
      'SKT 1S.03.2026': DateTime(2026, 3, 15),
      'SKT l5.03.2026': DateTime(2026, 3, 15),
      'SKT 15.03.2O26': DateTime(2026, 3, 15),
      'SKT I5.0B.2026': DateTime(2026, 8, 15),
      'SKT 15.03.202G': DateTime(2026, 3, 15),
      'SKT 15.03.Z026': DateTime(2026, 3, 15),
      'SKT 15.O3.26': DateTime(2026, 3, 15),
    };
    cases.forEach((t, d) {
      test(t, () => expect(_best(t)?.date, d));
    });

    test('month names are not mangled', () {
      expect(_best('15 SEP 26')!.date, DateTime(2026, 9, 15));
      expect(_best('15 DEC 26')!.date, DateTime(2026, 12, 15));
      expect(_best('15OCT26')!.date, DateTime(2026, 10, 15));
      expect(_best('BB 15 SEP 2026')!.date, DateTime(2026, 9, 15));
    });
  });

  group('validation', () {
    test('rejects 31.02', () => expect(_read('SKT 31.02.2026'), isEmpty));
    test('rejects invalid month', () => expect(_read('SKT 15.13.2026'), isEmpty));
    test('rejects far-past year', () => expect(_read('SKT 15.03.2015'), isEmpty));
    test('rejects far-future year', () => expect(_read('SKT 15.03.2045'), isEmpty));
    test('accepts boundaries', () {
      expect(_read('SKT 01.01.2021'), isNotEmpty);
      expect(_read('SKT 31.12.2036'), isNotEmpty);
    });
    test('MM.YYYY is month end with month precision', () {
      final c = _best('SKT 02.2027')!;
      expect(c.date, DateTime(2027, 2, 28));
      expect(c.precision, DatePrecision.monthYear);
    });
    test('MM/DD fallback only when DD.MM invalid, with lower score', () {
      final us = _best('SKT 03/25/2026')!;
      expect(us.date, DateTime(2026, 3, 25));
      final eu = _best('SKT 03/05/2026')!;
      expect(eu.date, DateTime(2026, 5, 3));
      expect(us.score, lessThan(eu.score));
    });
  });

  group('negatives', () {
    for (final t in [
      '12.50',
      '12.50 TL',
      '₺ 24.90',
      '24,90',
      'Net 500 g',
      'Net 1.5 L',
      '0.33 L',
      '8690123456789',
      '0532 123 45 67',
      '+90 212 555 12 34',
      'www.marka.com.tr',
      'Vitamin C 100 mg',
      'ÜRÜN ADI',
    ]) {
      test('no date in "$t"', () => expect(_read(t), isEmpty));
    }
  });

  group('scoring', () {
    test('keyword beats bare', () {
      expect(_best('SKT 15.03.2026')!.score,
          greaterThan(_best('15.03.2026')!.score));
    });

    test('bare date is medium', () {
      final s = _best('15.03.2026')!.score;
      expect(s, inInclusiveRange(0.4, 0.7));
    });

    test('unlabelled later date beats production-labelled earlier date', () {
      final r = _reader.read(_frame([
        _line('ÜT 01.01.2026', 400),
        _line('01.01.2027', 700),
      ]));
      expect(r.first.date, DateTime(2027, 1, 1));
      expect(r.first.kind, DateKind.unknown);
      expect(r.first.score, greaterThan(0.6));
    });

    test('of two unlabelled dates the later is the expiry', () {
      final r = _reader.read(_frame([
        _line('01.01.2026', 400),
        _line('01.01.2027', 700),
      ]));
      expect(r.first.date, DateTime(2027, 1, 1));
      expect(r.first.score, greaterThan(r.last.score));
    });

    test('analysis reports unbound expiry keyword and date-like lines', () {
      final a = _reader.analyze(_frame([_line('SKT')]));
      expect(a.candidates, isEmpty);
      expect(a.expiryKeywordBoxes, hasLength(1));
      final b = _reader.analyze(_frame([_line('15.03')]));
      expect(b.dateLikeBoxes, hasLength(1));
      final c = _reader.analyze(_frame([_line('8690123456789')]));
      expect(c.dateLikeBoxes, isEmpty);
    });
  });
}
