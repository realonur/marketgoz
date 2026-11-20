/// Robust expiry-date extraction from OCR lines (Turkish + English packaging).
/// Pure Dart. Replaces lib/core/utils/date_parser.dart for the new pipeline.
library;

import 'ocr_frame.dart';

enum DatePrecision { day, monthYear }

enum DateKind { expiry, production, unknown }

class DateCandidate {
  const DateCandidate({
    required this.date,
    required this.precision,
    required this.kind,
    required this.rawText,
    required this.box,
    required this.score,
  });

  /// For [DatePrecision.monthYear] this is the last day of that month.
  final DateTime date;
  final DatePrecision precision;
  final DateKind kind;

  /// The matched date text (not the whole line).
  final String rawText;

  /// Box of the OCR line the date came from.
  final BoxD box;

  /// 0..1 likelihood that this is THE expiry date (production dates score low).
  final double score;

  DateCandidate _with({DateKind? kind, double? score}) => DateCandidate(
        date: date,
        precision: precision,
        kind: kind ?? this.kind,
        rawText: rawText,
        box: box,
        score: (score ?? this.score).clamp(0.0, 1.0),
      );

  @override
  String toString() =>
      'DateCandidate($date, $precision, $kind, "$rawText", ${score.toStringAsFixed(2)})';
}

/// Everything the guidance engine needs to know about one frame.
class FrameAnalysis {
  const FrameAnalysis({
    required this.candidates,
    required this.expiryKeywordBoxes,
    required this.dateLikeBoxes,
    required this.lotSeen,
  });

  /// Parsed dates, best score first.
  final List<DateCandidate> candidates;

  /// Lines holding an expiry keyword that no date was bound to.
  final List<BoxD> expiryKeywordBoxes;

  /// Lines that look like (part of) a date or are digit-heavy, excluding
  /// lot lines and barcodes.
  final List<BoxD> dateLikeBoxes;

  final bool lotSeen;
}

enum _KwType { expiry, production, lot }

class _Kw {
  _Kw(this.type, this.start, this.end);
  final _KwType type;
  final int start;
  final int end;
  bool bound = false;
}

class _Raw {
  _Raw(this.pattern, this.start, this.end, this.g);
  final String pattern; // iso, dmy, named, nameYear, my, run
  final int start;
  final int end;
  final List<String?> g; // groups 1..n
  _Kw? kw;
  bool lotBlocked = false;
}

class _Line {
  _Line(this.line, this.text, this.kws, this.raws);
  final OcrLine line;
  final String text;
  final List<_Kw> kws;
  final List<_Raw> raws;
}

class _Built {
  _Built(this.date, this.precision, this.swapped, this.twoDigitYear);
  final DateTime date;
  final DatePrecision precision;
  final bool swapped;
  final bool twoDigitYear;
}

class ExpiryDateReader {
  ExpiryDateReader({
    DateTime Function()? clock,
    this.pastYears = 5,
    this.futureYears = 10,
  }) : _clock = clock ?? DateTime.now;

  final DateTime Function() _clock;

  /// Accepted year window: now.year - pastYears .. now.year + futureYears.
  final int pastYears;
  final int futureYears;

  List<DateCandidate> read(OcrFrame frame) => analyze(frame).candidates;

  FrameAnalysis analyze(OcrFrame frame) {
    final now = _clock();
    final minYear = now.year - pastYears;
    final maxYear = now.year + futureYears;

    final lines = <_Line>[];
    for (final l in frame.lines) {
      final folded = _fold(l.text);
      if (folded.trim().isEmpty) continue;
      final kws = _findKeywords(folded);
      final repaired = _repair(folded, kws);
      lines.add(_Line(l, repaired, kws, _findRaws(repaired)));
    }

    _bindKeywords(lines);

    final out = <DateCandidate>[];
    for (final ln in lines) {
      for (final r in ln.raws) {
        if (r.lotBlocked) continue;
        final kw = r.kw;
        if (kw != null && kw.type == _KwType.lot) continue;
        final hasKw = kw != null;
        if (r.pattern == 'run' && !hasKw) continue;
        if (_priceGuard(ln.text, r)) continue;
        final b = _build(r, hasKw, minYear, maxYear);
        if (b == null) continue;
        final spaceOnly = _spaceOnly(r);
        if (spaceOnly && !hasKw && b.twoDigitYear) continue;
        final kind = kw == null
            ? DateKind.unknown
            : (kw.type == _KwType.expiry ? DateKind.expiry : DateKind.production);
        out.add(DateCandidate(
          date: b.date,
          precision: b.precision,
          kind: kind,
          rawText: ln.text.substring(r.start, r.end).trim(),
          box: ln.line.box,
          score: _baseScore(kind, r, b, spaceOnly),
        ));
      }
    }

    final adjusted = _crossAdjust(_dedupe(out))
      ..sort((a, b) => b.score.compareTo(a.score));

    final kwBoxes = <BoxD>[];
    final dateLike = <BoxD>[];
    var lot = false;
    for (final ln in lines) {
      final hasLot = ln.kws.any((k) => k.type == _KwType.lot);
      if (hasLot) lot = true;
      if (ln.kws.any((k) => k.type == _KwType.expiry && !k.bound)) {
        kwBoxes.add(ln.line.box);
      }
      if (!hasLot && _isDateLike(ln.text)) dateLike.add(ln.line.box);
    }
    return FrameAnalysis(
      candidates: adjusted,
      expiryKeywordBoxes: kwBoxes,
      dateLikeBoxes: dateLike,
      lotSeen: lot,
    );
  }

  // ---------------------------------------------------------------- folding

  /// Upper-cases and strips Turkish diacritics, 1:1 per character, so that
  /// offsets in the result are valid for every later stage.
  static String _fold(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      final c = String.fromCharCode(r);
      switch (c) {
        case 'ı':
        case 'İ':
        case 'i':
          b.write('I');
        case 'ş':
        case 'Ş':
          b.write('S');
        case 'ğ':
        case 'Ğ':
          b.write('G');
        case 'ü':
        case 'Ü':
          b.write('U');
        case 'ö':
        case 'Ö':
          b.write('O');
        case 'ç':
        case 'Ç':
          b.write('C');
        case '\n':
        case '\r':
        case '\t':
          b.write(' ');
        case '̇': // combining dot above
          break;
        default:
          final u = c.toUpperCase();
          b.write(u.length == c.length ? u : c);
      }
    }
    return b.toString();
  }

  // --------------------------------------------------------------- keywords

  static final _kwPatterns = <MapEntry<_KwType, RegExp>>[
    // Expiry
    MapEntry(_KwType.expiry, RegExp(r'(?<![A-Z])S[\s.]{0,3}K[\s.]{0,3}T(?![A-Z])\.?')),
    MapEntry(
        _KwType.expiry,
        RegExp(r'SON\s*(?:KULLANMA|KUL|TUKETIM|TUK)[A-Z]*\.?(?:\s*TAR[A-Z]*\.?)?')),
    MapEntry(_KwType.expiry, RegExp(r'(?<![A-Z])T[\s.]{0,3}E[\s.]{0,3}T[\s.]{0,3}T(?![A-Z])\.?')),
    MapEntry(_KwType.expiry,
        RegExp(r'TAVSIYE\s*EDILEN(?:\s*TUKETIM)?(?:\s*TAR[A-Z]*\.?)?')),
    MapEntry(_KwType.expiry,
        RegExp(r'(?<![A-Z])E[\s.]?X[\s.]?P(?:IRY|IRES|IRATION)?(?![A-Z])\.?')),
    MapEntry(_KwType.expiry, RegExp(r'BEST\s*BEFORE')),
    MapEntry(_KwType.expiry, RegExp(r'(?<![A-Z])BBE?(?![A-Z])')),
    MapEntry(_KwType.expiry, RegExp(r'(?<![A-Z])USE\s*BY(?![A-Z])')),
    MapEntry(_KwType.expiry, RegExp(r'TUKETIM\s*TAR[A-Z]*\.?')),
    // Production
    MapEntry(_KwType.production, RegExp(r'(?<![A-Z])U[\s.]{0,3}T(?![A-Z])\.?')),
    MapEntry(_KwType.production, RegExp(r'URETIM(?:\s*TAR[A-Z]*\.?)?')),
    MapEntry(_KwType.production, RegExp(r'(?<![A-Z])UR\.\s*TAR[A-Z]*\.?')),
    MapEntry(_KwType.production, RegExp(r'(?<![A-Z])PROD(?:UCTION)?(?![A-Z])')),
    MapEntry(_KwType.production, RegExp(r'(?<![A-Z])P\.\s?D\.?')),
    MapEntry(_KwType.production, RegExp(r'(?<![A-Z])MF[GD](?![A-Z])')),
    MapEntry(_KwType.production, RegExp(r'MANUFACTURED')),
    // Lot / batch
    MapEntry(
        _KwType.lot,
        RegExp(r'(?<![A-Z])(?:LOT|PARTI|SERI|BATCH)(?![A-Z])(?:\s*(?:NO|NUM)(?![A-Z])\.?)?:?')),
  ];

  static List<_Kw> _findKeywords(String t) {
    final all = <_Kw>[];
    for (final e in _kwPatterns) {
      for (final m in e.value.allMatches(t)) {
        all.add(_Kw(e.key, m.start, m.end));
      }
    }
    all.sort((a, b) =>
        a.start != b.start ? a.start - b.start : (b.end - b.start) - (a.end - a.start));
    final out = <_Kw>[];
    for (final k in all) {
      if (out.isNotEmpty && k.start < out.last.end) continue;
      out.add(k);
    }
    return out;
  }

  // ---------------------------------------------------------------- months

  static const _monAlt =
      r'(OCAK|OCA|SUBAT|SUB|MART|MARCH|MAR|NISAN|NIS|MAYIS|MAY|HAZIRAN|HAZ|TEMMUZ|TEM|AGUSTOS|AGU|EYLUL|EYL|EKIM|EKI|KASIM|KAS|ARALIK|ARA|JANUARY|JAN|FEBRUARY|FEB|APRIL|APR|JUNE|JUN|JULY|JUL|AUGUST|AUG|SEPTEMBER|SEPT|SEP|OCTOBER|OCT|NOVEMBER|NOV|DECEMBER|DEC)(?![A-Z])';

  static const _monthNum = {
    'OCA': 1, 'SUB': 2, 'MAR': 3, 'NIS': 4, 'MAY': 5, 'HAZ': 6,
    'TEM': 7, 'AGU': 8, 'EYL': 9, 'EKI': 10, 'KAS': 11, 'ARA': 12,
    'JAN': 1, 'FEB': 2, 'APR': 4, 'JUN': 6, 'JUL': 7, 'AUG': 8,
    'SEP': 9, 'OCT': 10, 'NOV': 11, 'DEC': 12,
  };

  static final _monthTokenRe = RegExp('(?<![A-Z])$_monAlt');

  // ---------------------------------------------------------------- repair

  static const _confusable = 'OQDILZSBG|!';

  static String _confMap(String c) {
    switch (c) {
      case 'O':
      case 'Q':
      case 'D':
        return '0';
      case 'I':
      case 'L':
      case '|':
      case '!':
        return '1';
      case 'Z':
        return '2';
      case 'S':
        return '5';
      case 'B':
        return '8';
      case 'G':
        return '6';
    }
    return c;
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;

  /// Fixes OCR letter/digit confusions inside digit groups only. Month names
  /// and keywords are protected so "SEP", "OCT", "BB" are never mangled.
  static String _repair(String t, List<_Kw> kws) {
    final prot = List<bool>.filled(t.length, false);
    for (final k in kws) {
      for (var i = k.start; i < k.end; i++) {
        prot[i] = true;
      }
    }
    for (final m in _monthTokenRe.allMatches(t)) {
      for (var i = m.start; i < m.end; i++) {
        prot[i] = true;
      }
    }
    final out = t.split('');
    bool runChar(int i) =>
        !prot[i] && (_isDigit(t[i]) || _confusable.contains(t[i]));
    var i = 0;
    while (i < t.length) {
      if (!runChar(i)) {
        i++;
        continue;
      }
      var j = i;
      while (j < t.length && runChar(j)) {
        j++;
      }
      var digits = 0;
      for (var x = i; x < j; x++) {
        if (_isDigit(t[x])) digits++;
      }
      final letters = (j - i) - digits;
      if (digits >= 1 && letters > 0 && letters <= 2 * digits) {
        for (var x = i; x < j; x++) {
          out[x] = _confMap(t[x]);
        }
      }
      i = j;
    }
    return out.join();
  }

  // --------------------------------------------------------------- matching

  static const _sep = r'(\s*[.\-/]\s*|\s+)';
  static const _pre = r'(?<!\d)(?<!\d[.\-/])';
  static const _post = r'(?!\d)(?![.\-/]\d)';

  static final _isoRe =
      RegExp('$_pre(\\d{4})$_sep(\\d{1,2})$_sep(\\d{1,2})$_post');
  static final _dmyRe =
      RegExp('$_pre(\\d{1,2})$_sep(\\d{1,2})$_sep(\\d{4}|\\d{2})$_post');
  static final _namedRe = RegExp(
      "(?<!\\d)(\\d{1,2})\\s*[.\\-/]?\\s*$_monAlt\\s*[.\\-/,']?\\s*(\\d{4}|\\d{2})$_post");
  static final _nameYearRe = RegExp(
      "(?<![A-Z])$_monAlt\\s*[.\\-/,']?\\s*(\\d{4}|\\d{2})$_post");
  static final _myRe = RegExp('$_pre(\\d{1,2})$_sep(\\d{4}|\\d{2})$_post');
  static final _runRe = RegExp(r'(?<!\d)(\d{2})(\d{2})(\d{4}|\d{2})(?!\d)');

  static List<_Raw> _findRaws(String t) {
    final accepted = <_Raw>[];
    bool overlaps(int s, int e) => accepted.any((r) => s < r.end && e > r.start);
    void run(String name, RegExp re) {
      for (final m in re.allMatches(t)) {
        if (overlaps(m.start, m.end)) continue;
        accepted.add(_Raw(name, m.start, m.end,
            [for (var i = 1; i <= m.groupCount; i++) m.group(i)]));
      }
    }

    run('iso', _isoRe);
    run('dmy', _dmyRe);
    run('named', _namedRe);
    run('nameYear', _nameYearRe);
    run('my', _myRe);
    run('run', _runRe);
    accepted.sort((a, b) => a.start - b.start);
    return accepted;
  }

  static bool _spaceOnly(_Raw r) {
    switch (r.pattern) {
      case 'iso':
      case 'dmy':
        return !_hasPunct(r.g[1]) && !_hasPunct(r.g[3]);
      case 'my':
        return !_hasPunct(r.g[1]);
    }
    return false;
  }

  static bool _hasPunct(String? s) => s != null && RegExp(r'[.\-/]').hasMatch(s);

  static bool _priceGuard(String t, _Raw r) {
    final after = t.substring(r.end);
    if (RegExp(r'^\s*(?:TL|₺|\$|€|EUR|USD)').hasMatch(after)) return true;
    final before = t.substring(0, r.start);
    if (RegExp(r'[₺$€]\s*$').hasMatch(before)) return true;
    return false;
  }

  // --------------------------------------------------------------- building

  _Built? _build(_Raw r, bool hasKw, int minYear, int maxYear) {
    int? year(String s) {
      final y = int.parse(s);
      return s.length == 2 ? 2000 + y : y;
    }

    DateTime? ymd(int y, int m, int d) {
      if (y < minYear || y > maxYear || m < 1 || m > 12 || d < 1 || d > 31) {
        return null;
      }
      final dt = DateTime(y, m, d);
      return (dt.month == m && dt.day == d) ? dt : null;
    }

    DateTime? monthEnd(int y, int m) {
      if (y < minYear || y > maxYear || m < 1 || m > 12) return null;
      return DateTime(y, m + 1, 0);
    }

    switch (r.pattern) {
      case 'iso':
        final d = ymd(int.parse(r.g[0]!), int.parse(r.g[2]!), int.parse(r.g[4]!));
        return d == null ? null : _Built(d, DatePrecision.day, false, false);
      case 'dmy':
        return _dayFirst(r.g[0]!, r.g[2]!, r.g[4]!, ymd, year);
      case 'run':
        return _dayFirst(r.g[0]!, r.g[1]!, r.g[2]!, ymd, year);
      case 'named':
        final y = year(r.g[2]!)!;
        final d = ymd(y, _monthNum[r.g[1]!.substring(0, 3)]!, int.parse(r.g[0]!));
        return d == null
            ? null
            : _Built(d, DatePrecision.day, false, r.g[2]!.length == 2);
      case 'nameYear':
        final d = monthEnd(year(r.g[1]!)!, _monthNum[r.g[0]!.substring(0, 3)]!);
        return d == null
            ? null
            : _Built(d, DatePrecision.monthYear, false, r.g[1]!.length == 2);
      case 'my':
        final two = r.g[2]!.length == 2;
        // MM.YY is too close to prices/versions; need "/" or "-" or a keyword.
        if (two && !hasKw && !RegExp(r'[/\-]').hasMatch(r.g[1]!)) return null;
        final d = monthEnd(year(r.g[2]!)!, int.parse(r.g[0]!));
        return d == null ? null : _Built(d, DatePrecision.monthYear, false, two);
    }
    return null;
  }

  _Built? _dayFirst(
    String a,
    String b,
    String yStr,
    DateTime? Function(int, int, int) ymd,
    int? Function(String) year,
  ) {
    final y = year(yStr)!;
    final two = yStr.length == 2;
    final x = int.parse(a), z = int.parse(b);
    final eu = ymd(y, z, x); // DD.MM
    if (eu != null) return _Built(eu, DatePrecision.day, false, two);
    final us = ymd(y, x, z); // MM/DD only when DD.MM impossible
    if (us != null) return _Built(us, DatePrecision.day, true, two);
    return null;
  }

  // ---------------------------------------------------------------- binding

  /// Assigns a keyword (or lot marker) to every raw date, using the same line
  /// first, then neighbouring lines by geometry.
  void _bindKeywords(List<_Line> lines) {
    // 1. Preceding keyword on the same line.
    for (final ln in lines) {
      for (final r in ln.raws) {
        _Kw? best;
        for (final k in ln.kws) {
          if (k.end <= r.start && r.start - k.end <= 14) best = k;
        }
        if (best != null &&
            ln.raws.any((o) => o != r && o.start >= best!.end && o.start < r.start)) {
          best = null;
        }
        if (best != null) {
          r.kw = best;
          best.bound = true;
        }
      }
    }
    // 2. Trailing keyword on the same line ("15.03.26 EXP").
    for (final ln in lines) {
      for (final r in ln.raws) {
        if (r.kw != null) continue;
        for (final k in ln.kws) {
          if (k.bound || k.start < r.end || k.start - r.end > 6) continue;
          if (ln.raws.any((o) => o != r && o.start >= r.end && o.start < k.start)) {
            continue;
          }
          r.kw = k;
          k.bound = true;
          break;
        }
      }
    }
    // 3. Neighbouring lines: keyword above or to the left.
    for (final ln in lines) {
      for (final r in ln.raws) {
        if (r.kw != null) continue;
        final box = ln.line.box;
        final h = box.height <= 0 ? 1.0 : box.height;
        _Kw? bestKw;
        double bestDist = double.infinity;
        for (final nb in lines) {
          if (identical(nb, ln)) continue;
          final unbound = nb.kws.where((k) => !k.bound).toList();
          if (unbound.isEmpty) continue;
          final nbBox = nb.line.box;
          double? dist;
          // Same row, to the left.
          if ((nbBox.centerY - box.centerY).abs() <= 0.6 * h &&
              nbBox.right <= box.left + 0.5 * h &&
              box.left - nbBox.right <= 6 * h) {
            dist = (box.left - nbBox.right).clamp(0.0, double.infinity) / h;
          }
          // Above.
          final dy = box.top - nbBox.bottom;
          final xGap = nbBox.left > box.right
              ? nbBox.left - box.right
              : (box.left > nbBox.right ? box.left - nbBox.right : 0.0);
          if (dy >= -0.5 * h && dy <= 1.5 * h && xGap <= 2 * h) {
            final d = dy.clamp(0.0, double.infinity) / h + 0.01;
            if (dist == null || d < dist) dist = d;
          }
          if (dist != null && dist < bestDist) {
            bestDist = dist;
            bestKw = unbound.last;
          }
        }
        if (bestKw != null) {
          r.kw = bestKw;
          bestKw.bound = true;
        }
      }
    }
  }

  // ---------------------------------------------------------------- scoring

  double _baseScore(DateKind kind, _Raw r, _Built b, bool spaceOnly) {
    double s;
    switch (kind) {
      case DateKind.expiry:
        s = 0.9;
        if (b.precision == DatePrecision.day && !b.twoDigitYear) s += 0.05;
      case DateKind.production:
        s = 0.1;
      case DateKind.unknown:
        if (b.precision == DatePrecision.day) {
          s = b.twoDigitYear ? 0.45 : 0.55;
        } else {
          s = (r.pattern == 'nameYear') ? 0.5 : 0.45;
        }
    }
    if (spaceOnly && kind != DateKind.production) s *= 0.85;
    if (b.swapped) s *= 0.6;
    return s;
  }

  List<DateCandidate> _dedupe(List<DateCandidate> c) {
    final best = <String, DateCandidate>{};
    for (final x in c) {
      final key = '${x.date.year}-${x.date.month}-${x.date.day}/${x.precision.name}/${x.kind.name}';
      final cur = best[key];
      if (cur == null || x.score > cur.score) best[key] = x;
    }
    return best.values.toList();
  }

  /// If a package shows several dates: labelled production dates are never the
  /// expiry; an unlabelled date later than the production date (or the latest
  /// unlabelled one) is the likely expiry, earlier ones lose score.
  List<DateCandidate> _crossAdjust(List<DateCandidate> c) {
    final prod = c.where((x) => x.kind == DateKind.production).toList();
    final unk = c.where((x) => x.kind == DateKind.unknown).toList();
    if (unk.isEmpty || c.length < 2) return c;
    final latestProd = prod.isEmpty
        ? null
        : prod.map((p) => p.date).reduce((a, b) => a.isAfter(b) ? a : b);
    final unkDates = unk.map((u) => u.date).toSet();
    final latestUnk = unk.map((u) => u.date).reduce((a, b) => a.isAfter(b) ? a : b);
    return [
      for (final x in c)
        if (x.kind != DateKind.unknown)
          x
        else
          () {
            var s = x.score;
            if (latestProd != null) {
              if (x.date.isAfter(latestProd)) {
                s += 0.2;
              } else if (x.date.isBefore(latestProd)) {
                s -= 0.15;
              }
            }
            if (unkDates.length > 1) {
              s += x.date == latestUnk ? 0.1 : -0.1;
            }
            return x._with(score: s);
          }(),
    ];
  }

  // -------------------------------------------------------------- heuristics

  static bool _isDateLike(String t) {
    if (RegExp(r'\d{9,}').hasMatch(t)) return false; // barcode
    if (RegExp(r'\d+[.,]\d{2}\s*(?:TL|₺)').hasMatch(t)) return false; // price
    final digits = RegExp(r'\d').allMatches(t).length;
    if (digits == 0) return false;
    if (_monthTokenRe.hasMatch(t) && digits >= 2) return true;
    if (RegExp(r'\d{1,2}\s*[.\-/]\s*\d{1,4}').hasMatch(t) && digits >= 3) return true;
    final nonSpace = t.replaceAll(RegExp(r'\s'), '').length;
    return digits >= 4 && digits / nonSpace >= 0.5;
  }
}
