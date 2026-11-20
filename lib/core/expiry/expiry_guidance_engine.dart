/// Guidance state machine: turns a stream of OCR frames into spoken prompts,
/// haptic intensity and, finally, the expiry date.
///
/// Pure Dart, no timers: time comes only from [OcrFrame.timestamp] and the
/// injected clock (used only to compute "days remaining").
///
/// DIRECTION CONVENTION: all directions are where the USER should move the
/// ITEM. Assumes rear camera, portrait, image already rotated upright and not
/// mirrored, so image-left == user's left. A date box left of frame centre
/// means "move the item right" ("biraz sağa"); box right of centre -> "sola";
/// box above centre -> "aşağı"; box below centre -> "yukarı".
library;

import 'dart:math' show sqrt;

import 'expiry_date_reader.dart';
import 'ocr_frame.dart';

enum GuidancePhase {
  waitingForItem,
  searching,
  homingIn,
  confirming,
  found,
  tooDark,
}

enum GuidancePrompt {
  tooDark('Ortam karanlık, fener açılıyor'),
  placeItem('Ürünü kameranın yaklaşık 20 santim önüne tutun'),
  rotate('Ürünü yavaşça kendi etrafında çevirin'),
  showBottom('Şimdi ürünün altını gösterin'),
  showTop('Üst kısmını ya da kapağını gösterin'),
  showBack('Arka yüzünü gösterin'),
  showSides('Yan kenarları gösterin'),
  repeatedFace('Bu yüzü zaten gördük, çevirmeye devam edin'),
  productionDate(
      'Bu üretim tarihi, son kullanma tarihini aramaya devam edin'),
  moveLeft('Ürünü biraz sola kaydırın'),
  moveRight('Ürünü biraz sağa kaydırın'),
  moveUp('Ürünü biraz yukarı kaldırın'),
  moveDown('Ürünü biraz aşağı indirin'),
  closer('Ürünü biraz yaklaştırın'),
  farther('Ürünü biraz uzaklaştırın'),
  centeredHold('Tarihi buldum, sabit tutun'),
  glare('Ürünü biraz eğin, parlama olabilir'),
  holdSteady('Sabit tutun'),
  foundResult(''); // text is the ExpiryResult.spokenSummary

  const GuidancePrompt(this.turkish);
  final String turkish;
}

/// A prompt that should be spoken now.
class SpokenPrompt {
  const SpokenPrompt(this.type, this.text);
  final GuidancePrompt type;
  final String text;

  @override
  String toString() => 'SpokenPrompt($type, "$text")';
}

enum ExpiryStatus { expired, expiresToday, soon, ok }

class ExpiryResult {
  const ExpiryResult({
    required this.date,
    required this.precision,
    required this.daysRemaining,
    required this.status,
    required this.spokenSummary,
  });

  /// Last day of the month for [DatePrecision.monthYear].
  final DateTime date;
  final DatePrecision precision;

  /// Negative when already expired.
  final int daysRemaining;
  final ExpiryStatus status;
  final String spokenSummary;
}

class GuidanceOutput {
  const GuidanceOutput({
    required this.phase,
    this.prompt,
    this.hapticIntensity = 0,
    this.torchSuggested = false,
    this.result,
    this.justFound = false,
    this.targetBox,
  });

  final GuidancePhase phase;

  /// Box (upright image coordinates) the user is being steered towards:
  /// set while homing in or confirming, null otherwise.
  final BoxD? targetBox;

  /// Non-null only when it should actually be spoken now.
  final SpokenPrompt? prompt;

  /// 0 = no pulse, rises towards 1 as a readable date gets closer.
  final double hapticIntensity;
  final bool torchSuggested;

  /// Set in every output once [phase] is [GuidancePhase.found].
  final ExpiryResult? result;

  /// True only on the single output that first announces the result.
  final bool justFound;
}

class GuidanceConfig {
  const GuidanceConfig({
    this.darkBrightnessThreshold = 0.12,
    this.darkFramesRequired = 3,
    this.emptyFramesRequired = 2,
    this.minPromptInterval = const Duration(milliseconds: 2500),
    this.repeatPromptInterval = const Duration(seconds: 5),
    this.searchStepDuration = const Duration(seconds: 4),
    this.contentChangeSimilarity = 0.5,
    this.faceMatchSimilarity = 0.6,
    this.faceStableFrames = 3,
    this.minFaceTokens = 3,
    this.maxRememberedFaces = 12,
    this.minCandidateScore = 0.35,
    this.votingWindow = 6,
    this.votesRequired = 3,
    this.voteMaxAge = const Duration(seconds: 4),
    this.tinyBoxHeightFraction = 0.03,
    this.edgeMarginFraction = 0.01,
    this.centerToleranceFraction = 0.12,
    this.glareAfter = const Duration(seconds: 4),
    this.glareMinFrames = 3,
    this.glareStreakGap = const Duration(milliseconds: 1500),
    this.soonDays = 3,
  });

  /// Brightness (0..1) below which a frame counts as dark.
  final double darkBrightnessThreshold;
  final int darkFramesRequired;

  /// Consecutive empty frames (no text, no object) before waitingForItem.
  final int emptyFramesRequired;

  /// Minimum gap between any two spoken prompts.
  final Duration minPromptInterval;

  /// The same prompt is not repeated within this time unless the phase changed.
  final Duration repeatPromptInterval;

  /// Time per rotation-script step while the text content stays unchanged.
  final Duration searchStepDuration;

  /// Jaccard similarity of token sets below which content "changed".
  final double contentChangeSimilarity;
  final double faceMatchSimilarity;

  /// Consecutive unchanged frames before a view counts as a "face".
  final int faceStableFrames;
  final int minFaceTokens;
  final int maxRememberedFaces;

  /// Candidates below this score are ignored by voting.
  final double minCandidateScore;

  /// Last N candidate-carrying frames considered.
  final int votingWindow;

  /// Frames within the window that must agree on the same date.
  final int votesRequired;
  final Duration voteMaxAge;

  /// Box height / image height below which we say "yaklaştırın".
  final double tinyBoxHeightFraction;

  /// Box within this fraction of an image edge counts as clipped.
  final double edgeMarginFraction;

  /// |offset from centre| / image size within which the box counts as centred.
  final double centerToleranceFraction;

  /// Keyword seen without a parseable date for this long -> glare hint.
  final Duration glareAfter;
  final int glareMinFrames;
  final Duration glareStreakGap;

  /// daysRemaining in 1..soonDays gives [ExpiryStatus.soon].
  final int soonDays;
}

class _Vote {
  _Vote(this.time, this.byKey);
  final DateTime time;
  final Map<String, DateCandidate> byKey;
}

class ExpiryGuidanceEngine {
  ExpiryGuidanceEngine({
    DateTime Function()? clock,
    this.config = const GuidanceConfig(),
  })  : _clock = clock ?? DateTime.now,
        _reader = ExpiryDateReader(clock: clock);

  final GuidanceConfig config;
  final DateTime Function() _clock;
  final ExpiryDateReader _reader;

  static const _script = [
    GuidancePrompt.rotate,
    GuidancePrompt.showBottom,
    GuidancePrompt.showTop,
    GuidancePrompt.showBack,
    GuidancePrompt.showSides,
  ];

  // state
  GuidancePhase _phase = GuidancePhase.waitingForItem;
  ExpiryResult? _found;
  int _darkCount = 0;
  int _emptyCount = 0;
  final List<_Vote> _votes = [];

  // prompt gate
  DateTime? _lastPromptAt;
  GuidancePrompt? _lastPrompt;
  bool _phaseChangedSincePrompt = false;

  // search script + face memory
  int _stepIdx = 0;
  DateTime? _stepStart;
  Set<String>? _prevTokens;
  int _stableFrames = 0;
  bool _faceRegistered = false;
  bool _repeatPending = false;
  int _currentFace = -1;
  final List<Set<String>> _faces = [];

  // glare
  DateTime? _kwStreakStart;
  DateTime? _kwLastSeen;
  int _kwFrames = 0;

  void reset() {
    _phase = GuidancePhase.waitingForItem;
    _found = null;
    _darkCount = 0;
    _emptyCount = 0;
    _votes.clear();
    _lastPromptAt = null;
    _lastPrompt = null;
    _phaseChangedSincePrompt = false;
    _stepIdx = 0;
    _stepStart = null;
    _prevTokens = null;
    _stableFrames = 0;
    _faceRegistered = false;
    _repeatPending = false;
    _currentFace = -1;
    _faces.clear();
    _kwStreakStart = null;
    _kwLastSeen = null;
    _kwFrames = 0;
  }

  GuidanceOutput process(OcrFrame frame) {
    final found = _found;
    if (found != null) {
      return GuidanceOutput(
        phase: GuidancePhase.found,
        hapticIntensity: 1,
        result: found,
      );
    }
    final now = frame.timestamp;
    final analysis = _reader.analyze(frame);
    final tokens = _fingerprint(frame);
    final changed = _trackContent(tokens);

    // Dark tracking.
    final dark = frame.brightness != null &&
        frame.brightness! < config.darkBrightnessThreshold;
    _darkCount = dark ? _darkCount + 1 : 0;

    final eligible = analysis.candidates
        .where((c) =>
            c.kind != DateKind.production && c.score >= config.minCandidateScore)
        .toList();
    final hasText = frame.lines.any((l) => l.text.trim().isNotEmpty);

    // --- candidates present: confirming / found
    if (eligible.isNotEmpty) {
      _resetGlare();
      _emptyCount = 0;
      return _vote(now, eligible);
    }
    _expireVotes(now);

    // --- dark
    if (dark) {
      if (_darkCount >= config.darkFramesRequired) {
        _setPhase(GuidancePhase.tooDark);
        return GuidanceOutput(
          phase: GuidancePhase.tooDark,
          prompt: _gate(GuidancePrompt.tooDark, GuidancePrompt.tooDark.turkish, now),
          torchSuggested: true,
        );
      }
      if (!hasText) {
        // Still counting dark frames: hold position silently.
        return GuidanceOutput(phase: _phase);
      }
    }

    // --- nothing in view
    if (!hasText && !frame.hasObjectInFrame) {
      _emptyCount++;
      if (_emptyCount >= config.emptyFramesRequired) {
        _setPhase(GuidancePhase.waitingForItem);
        return GuidanceOutput(
          phase: GuidancePhase.waitingForItem,
          prompt: _gate(
              GuidancePrompt.placeItem, GuidancePrompt.placeItem.turkish, now),
        );
      }
      return GuidanceOutput(phase: _phase);
    }
    _emptyCount = 0;

    // --- production date only
    final productionOnly = analysis.candidates.isNotEmpty;
    if (productionOnly) {
      _resetGlare();
      _enterSearching(now);
      _stepOrReset(now, changed);
      return GuidanceOutput(
        phase: GuidancePhase.searching,
        hapticIntensity: 0.3,
        prompt: _gate(GuidancePrompt.productionDate,
            GuidancePrompt.productionDate.turkish, now),
      );
    }

    // --- partial date / keyword: homing in
    final kwBoxes = analysis.expiryKeywordBoxes;
    final targets = kwBoxes.isNotEmpty ? kwBoxes : analysis.dateLikeBoxes;
    if (targets.isNotEmpty) {
      return _homing(frame, now, targets, kwBoxes.isNotEmpty);
    }

    // --- searching
    _resetGlare();
    return _searching(now, changed, analysis.dateLikeBoxes.isNotEmpty);
  }

  // ------------------------------------------------------------------ voting

  GuidanceOutput _vote(DateTime now, List<DateCandidate> eligible) {
    _expireVotes(now);
    final byKey = <String, DateCandidate>{};
    for (final c in eligible) {
      final k = _key(c);
      final cur = byKey[k];
      if (cur == null || c.score > cur.score) byKey[k] = c;
    }
    _votes.add(_Vote(now, byKey));
    while (_votes.length > config.votingWindow) {
      _votes.removeAt(0);
    }

    final counts = <String, int>{};
    final best = <String, DateCandidate>{};
    for (final v in _votes) {
      v.byKey.forEach((k, c) {
        counts[k] = (counts[k] ?? 0) + 1;
        final cur = best[k];
        if (cur == null || _rank(c) > _rank(cur)) best[k] = c;
      });
    }
    String? winner;
    for (final e in counts.entries) {
      if (e.value < config.votesRequired) continue;
      if (winner == null || _rank(best[e.key]!) > _rank(best[winner]!)) {
        winner = e.key;
      }
    }

    if (winner != null) {
      final result = _buildResult(best[winner]!);
      _found = result;
      _phase = GuidancePhase.found;
      _lastPromptAt = now;
      _lastPrompt = GuidancePrompt.foundResult;
      return GuidanceOutput(
        phase: GuidancePhase.found,
        prompt: SpokenPrompt(GuidancePrompt.foundResult, result.spokenSummary),
        hapticIntensity: 1,
        result: result,
        justFound: true,
      );
    }

    _setPhase(GuidancePhase.confirming);
    return GuidanceOutput(
      phase: GuidancePhase.confirming,
      hapticIntensity: 0.9,
      targetBox: byKey.values
          .reduce((a, b) => _rank(a) >= _rank(b) ? a : b)
          .box,
      prompt: _gate(
          GuidancePrompt.holdSteady, GuidancePrompt.holdSteady.turkish, now),
    );
  }

  String _key(DateCandidate c) =>
      '${c.date.year}-${c.date.month}-${c.date.day}/${c.precision.name}';

  /// Expiry-labelled beats unlabelled; then score; then later date.
  double _rank(DateCandidate c) =>
      (c.kind == DateKind.expiry ? 10 : 0) + c.score;

  void _expireVotes(DateTime now) {
    _votes.removeWhere((v) => now.difference(v.time) > config.voteMaxAge);
  }

  // ------------------------------------------------------------------ homing

  GuidanceOutput _homing(
    OcrFrame f,
    DateTime now,
    List<BoxD> targets,
    bool keywordSeen,
  ) {
    _setPhase(GuidancePhase.homingIn);
    final w = f.imageWidth, h = f.imageHeight;
    // Pick the target nearest the frame centre.
    BoxD pick = targets.first;
    double bestD = double.infinity;
    for (final b in targets) {
      final d = _norm(b, w, h);
      if (d < bestD) {
        bestD = d;
        pick = b;
      }
    }
    final dx = (pick.centerX - w / 2) / w;
    final dy = (pick.centerY - h / 2) / h;
    final mx = config.edgeMarginFraction * w, my = config.edgeMarginFraction * h;
    final clipped = pick.left <= mx ||
        pick.top <= my ||
        pick.right >= w - mx ||
        pick.bottom >= h - my;
    final tiny = pick.height / h < config.tinyBoxHeightFraction;
    final tol = config.centerToleranceFraction;
    final centered = dx.abs() <= tol && dy.abs() <= tol;

    GuidancePrompt p;
    if (clipped) {
      p = GuidancePrompt.farther;
    } else if (tiny) {
      p = GuidancePrompt.closer;
    } else if (centered) {
      p = GuidancePrompt.centeredHold;
    } else if (dx.abs() >= dy.abs()) {
      p = dx < 0 ? GuidancePrompt.moveRight : GuidancePrompt.moveLeft;
    } else {
      p = dy < 0 ? GuidancePrompt.moveDown : GuidancePrompt.moveUp;
    }

    // Glare: keyword keeps showing but digits never parse.
    var glare = false;
    if (keywordSeen) {
      if (_kwLastSeen == null ||
          now.difference(_kwLastSeen!) > config.glareStreakGap) {
        _kwStreakStart = now;
        _kwFrames = 0;
      }
      _kwLastSeen = now;
      _kwFrames++;
      glare = _kwFrames >= config.glareMinFrames &&
          now.difference(_kwStreakStart!) >= config.glareAfter;
    } else {
      _resetGlare();
    }
    if (glare) p = GuidancePrompt.glare;

    final prompt = _gate(p, p.turkish, now);
    if (prompt != null && glare) _kwStreakStart = now;

    final closeness = (1 - _norm(pick, w, h) / 0.5).clamp(0.0, 1.0);
    final haptic = 0.25 +
        (keywordSeen ? 0.15 : 0) +
        0.35 * closeness +
        ((!clipped && !tiny) ? 0.1 : 0);
    return GuidanceOutput(
      phase: GuidancePhase.homingIn,
      prompt: prompt,
      targetBox: pick,
      hapticIntensity: haptic.clamp(0.0, 0.85),
    );
  }

  double _norm(BoxD b, double w, double h) {
    final dx = (b.centerX - w / 2) / w, dy = (b.centerY - h / 2) / h;
    return sqrt(dx * dx + dy * dy);
  }

  void _resetGlare() {
    _kwStreakStart = null;
    _kwLastSeen = null;
    _kwFrames = 0;
  }

  // --------------------------------------------------------------- searching

  GuidanceOutput _searching(DateTime now, bool changed, bool digitsSeen) {
    _enterSearching(now);
    _stepOrReset(now, changed);
    GuidancePrompt p = _script[_stepIdx];
    if (_repeatPending) p = GuidancePrompt.repeatedFace;
    final prompt = _gate(p, p.turkish, now);
    if (prompt != null && p == GuidancePrompt.repeatedFace) {
      _repeatPending = false;
    }
    return GuidanceOutput(
      phase: GuidancePhase.searching,
      prompt: prompt,
      hapticIntensity: digitsSeen ? 0.1 : 0,
    );
  }

  void _enterSearching(DateTime now) {
    if (_phase != GuidancePhase.searching) {
      _setPhase(GuidancePhase.searching);
      _stepIdx = 0;
      _stepStart = now;
    }
  }

  void _stepOrReset(DateTime now, bool changed) {
    _stepStart ??= now;
    if (changed) {
      _stepStart = now;
    } else if (now.difference(_stepStart!) >= config.searchStepDuration) {
      _stepIdx = (_stepIdx + 1) % _script.length;
      _stepStart = now;
    }
  }

  // ------------------------------------------------------------- face memory

  static final _tokenRe = RegExp(r'[A-Za-z0-9ÇĞİÖŞÜçğıöşü]{2,}');

  Set<String> _fingerprint(OcrFrame f) {
    final s = <String>{};
    for (final l in f.lines) {
      for (final m in _tokenRe.allMatches(l.text)) {
        s.add(m.group(0)!.toUpperCase());
      }
    }
    return s;
  }

  double _jaccard(Set<String> a, Set<String> b) {
    if (a.isEmpty && b.isEmpty) return 1;
    final inter = a.intersection(b).length;
    final union = a.length + b.length - inter;
    return union == 0 ? 1 : inter / union;
  }

  /// Returns true when the visible text changed significantly (user turning).
  bool _trackContent(Set<String> tokens) {
    final prev = _prevTokens;
    _prevTokens = tokens;
    final changed =
        prev == null || _jaccard(prev, tokens) < config.contentChangeSimilarity;
    if (changed) {
      _stableFrames = 0;
      _faceRegistered = false;
      _repeatPending = false;
      return true;
    }
    _stableFrames++;
    if (!_faceRegistered &&
        _stableFrames >= config.faceStableFrames &&
        tokens.length >= config.minFaceTokens) {
      _faceRegistered = true;
      var match = -1;
      for (var i = 0; i < _faces.length; i++) {
        if (_jaccard(_faces[i], tokens) >= config.faceMatchSimilarity) {
          match = i;
          break;
        }
      }
      if (match == -1) {
        _faces.add(tokens);
        if (_faces.length > config.maxRememberedFaces) {
          _faces.removeAt(0);
        }
        _currentFace = _faces.length - 1;
      } else {
        if (match != _currentFace) _repeatPending = true;
        _currentFace = match;
      }
    }
    return false;
  }

  // ------------------------------------------------------------- prompt gate

  void _setPhase(GuidancePhase p) {
    if (p != _phase) _phaseChangedSincePrompt = true;
    _phase = p;
  }

  SpokenPrompt? _gate(GuidancePrompt p, String text, DateTime now) {
    final at = _lastPromptAt;
    if (at != null) {
      final since = now.difference(at);
      if (since < config.minPromptInterval) return null;
      if (p == _lastPrompt &&
          !_phaseChangedSincePrompt &&
          since < config.repeatPromptInterval) {
        return null;
      }
    }
    _lastPromptAt = now;
    _lastPrompt = p;
    _phaseChangedSincePrompt = false;
    return SpokenPrompt(p, text);
  }

  // ------------------------------------------------------------------ result

  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz',
    'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];

  ExpiryResult _buildResult(DateCandidate c) {
    final n = _clock();
    final today = DateTime.utc(n.year, n.month, n.day);
    final target = DateTime.utc(c.date.year, c.date.month, c.date.day);
    final days = target.difference(today).inDays;
    final status = days < 0
        ? ExpiryStatus.expired
        : days == 0
            ? ExpiryStatus.expiresToday
            : days <= config.soonDays
                ? ExpiryStatus.soon
                : ExpiryStatus.ok;
    final month = _months[c.date.month - 1];
    final monthOnly = c.precision == DatePrecision.monthYear;
    final what = monthOnly
        ? '$month ${c.date.year} sonu'
        : '${c.date.day} $month ${c.date.year}';

    final String text;
    switch (status) {
      case ExpiryStatus.expired:
        text = monthOnly
            ? 'Dikkat, son kullanma tarihi $what, süresi geçmiş.'
            : 'Dikkat, son kullanma tarihi $what, ${-days} gün önce geçmiş.';
      case ExpiryStatus.expiresToday:
        text = 'Son kullanma tarihi $what. Bugün son gün.';
      case ExpiryStatus.soon:
        text = 'Dikkat, son kullanma tarihi $what. '
            '${days == 1 ? 'Yarın son gün.' : '$days gün kaldı.'}';
      case ExpiryStatus.ok:
        text = monthOnly
            ? 'Son kullanma tarihi $what.'
            : 'Son kullanma tarihi $what. $days gün kaldı.';
    }
    return ExpiryResult(
      date: c.date,
      precision: c.precision,
      daysRemaining: days,
      status: status,
      spokenSummary: text,
    );
  }
}
