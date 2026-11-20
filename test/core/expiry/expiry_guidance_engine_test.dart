import 'package:flutter_test/flutter_test.dart';
import 'package:marketgoz/core/expiry/expiry_date_reader.dart';
import 'package:marketgoz/core/expiry/expiry_guidance_engine.dart';
import 'package:marketgoz/core/expiry/ocr_frame.dart';

final _t0 = DateTime(2026, 3, 3, 12);
final _today = DateTime(2026, 3, 3);

const _w = 1000.0, _h = 2000.0;

/// Centred, comfortably sized box (not tiny, not clipped).
const _centre = BoxD(400, 960, 600, 1040);

OcrFrame frame(
  double sec,
  List<OcrLine> lines, {
  double? brightness,
  bool object = true,
}) =>
    OcrFrame(
      timestamp: _t0.add(Duration(milliseconds: (sec * 1000).round())),
      imageWidth: _w,
      imageHeight: _h,
      lines: lines,
      brightness: brightness,
      hasObjectInFrame: object,
    );

OcrLine line(String text, [BoxD box = _centre]) => OcrLine(text: text, box: box);

BoxD boxAt(double cx, double cy, {double w = 200, double h = 80}) =>
    BoxD(cx - w / 2, cy - h / 2, cx + w / 2, cy + h / 2);

ExpiryGuidanceEngine engine() => ExpiryGuidanceEngine(clock: () => _today);

/// Feeds identical-content frames every [step] seconds, returns outputs.
List<GuidanceOutput> feed(
  ExpiryGuidanceEngine e,
  List<OcrLine> lines, {
  double from = 0,
  required double to,
  double step = 1,
}) {
  final out = <GuidanceOutput>[];
  for (var s = from; s <= to + 1e-9; s += step) {
    out.add(e.process(frame(s, lines)));
  }
  return out;
}

List<GuidancePrompt> prompts(Iterable<GuidanceOutput> o) =>
    [for (final x in o) if (x.prompt != null) x.prompt!.type];

void main() {
  group('tooDark / waitingForItem', () {
    test('dark for several frames suggests torch and speaks once', () {
      final e = engine();
      final o = [
        for (var i = 0; i < 4; i++)
          e.process(frame(i * 1.0, const [], brightness: 0.02)),
      ];
      expect(o[0].phase, isNot(GuidancePhase.tooDark));
      expect(o[0].prompt, isNull);
      expect(o[2].phase, GuidancePhase.tooDark);
      expect(o[2].torchSuggested, isTrue);
      expect(o[2].prompt!.type, GuidancePrompt.tooDark);
      expect(o[2].prompt!.text, 'Ortam karanlık, fener açılıyor');
      expect(o[3].phase, GuidancePhase.tooDark);
      expect(o[3].prompt, isNull); // dedup within 5 s
    });

    test('torch no longer suggested once bright again', () {
      final e = engine();
      for (var i = 0; i < 3; i++) {
        e.process(frame(i * 1.0, const [], brightness: 0.02));
      }
      final o = e.process(frame(3, [line('SÜT TAM YAĞLI 1 LT')], brightness: 0.5));
      expect(o.torchSuggested, isFalse);
      expect(o.phase, GuidancePhase.searching);
    });

    test('no text and no object prompts to hold the item up', () {
      final e = engine();
      final o1 = e.process(frame(0, const [], object: false));
      final o2 = e.process(frame(1, const [], object: false));
      expect(o1.prompt, isNull);
      expect(o2.phase, GuidancePhase.waitingForItem);
      expect(o2.prompt!.text, 'Ürünü kameranın yaklaşık 20 santim önüne tutun');
      expect(o2.hapticIntensity, 0);
    });
  });

  group('searching script', () {
    final text = [line('SÜT TAM YAĞLI PASTÖRİZE 1 LİTRE')];

    test('advances every 4 s while the content is unchanged, then loops', () {
      final e = engine();
      final o = feed(e, text, to: 21);
      expect(o.every((x) => x.phase == GuidancePhase.searching), isTrue);
      expect(prompts(o), [
        GuidancePrompt.rotate,
        GuidancePrompt.showBottom,
        GuidancePrompt.showTop,
        GuidancePrompt.showBack,
        GuidancePrompt.showSides,
        GuidancePrompt.rotate,
      ]);
      expect(o[0].prompt!.text, 'Ürünü yavaşça kendi etrafında çevirin');
      expect(o[4].prompt!.text, 'Şimdi ürünün altını gösterin');
      expect(o[8].prompt!.text, 'Üst kısmını ya da kapağını gösterin');
      expect(o[12].prompt!.text, 'Arka yüzünü gösterin');
      expect(o[16].prompt!.text, 'Yan kenarları gösterin');
    });

    test('timer resets while the visible text keeps changing', () {
      final e = engine();
      final o = <GuidanceOutput>[];
      for (var i = 0; i <= 12; i++) {
        o.add(e.process(frame(i * 1.0, [line('KELIME$i BASKA$i DIGER$i')])));
      }
      final p = prompts(o);
      expect(p, isNot(contains(GuidancePrompt.showBottom)));
      expect(p.first, GuidancePrompt.rotate);
    });

    test('object but no text yet still coaches', () {
      final e = engine();
      final o = e.process(frame(0, const []));
      expect(o.phase, GuidancePhase.searching);
      expect(o.prompt!.type, GuidancePrompt.rotate);
    });

    test('revisiting a seen face says so', () {
      final e = engine();
      final a = [line('SÜT TAM YAĞLI PASTÖRİZE LİTRE')];
      final b = [line('BESİN DEĞERLERİ ENERJİ PROTEİN KARBONHİDRAT')];
      final o = <GuidanceOutput>[
        ...feed(e, a, from: 0, to: 4),
        ...feed(e, b, from: 5, to: 9),
        ...feed(e, a, from: 10, to: 14),
      ];
      final idx = prompts(o).indexOf(GuidancePrompt.repeatedFace);
      expect(idx, isNonNegative);
      final spoken = o.firstWhere((x) => x.prompt?.type == GuidancePrompt.repeatedFace);
      expect(spoken.prompt!.text, 'Bu yüzü zaten gördük, çevirmeye devam edin');
    });

    test('holding the same face still does not say it was seen', () {
      final e = engine();
      final o = feed(e, text, to: 20);
      expect(prompts(o), isNot(contains(GuidancePrompt.repeatedFace)));
    });
  });

  group('targetBox', () {
    test('homingIn exposes the box being steered to', () {
      final b = boxAt(200, 1000);
      final o = engine().process(frame(0, [line('SKT', b)]));
      expect(o.phase, GuidancePhase.homingIn);
      expect(o.targetBox!.centerX, b.centerX);
      expect(o.targetBox!.centerY, b.centerY);
    });

    test('confirming exposes the date line box', () {
      final b = boxAt(300, 900);
      final o = engine().process(frame(0, [line('SKT 15.03.2026', b)]));
      expect(o.phase, GuidancePhase.confirming);
      expect(o.targetBox!.centerX, b.centerX);
    });

    test('absent while searching and when found', () {
      final e = engine();
      expect(e.process(frame(0, [line('Net 500 g')])).targetBox, isNull);
      final good = [line('SKT 15.03.2026')];
      e.process(frame(1, good));
      e.process(frame(1.3, good));
      expect(e.process(frame(1.6, good)).targetBox, isNull);
    });
  });

  group('homingIn directions (item movement)', () {
    void expectPrompt(BoxD box, GuidancePrompt expected, {String text = 'SKT'}) {
      final e = engine();
      final o = e.process(frame(0, [line(text, box)]));
      expect(o.phase, GuidancePhase.homingIn);
      expect(o.prompt!.type, expected);
      expect(o.hapticIntensity, greaterThan(0));
    }

    test('box left of centre -> move item right', () {
      expectPrompt(boxAt(200, 1000), GuidancePrompt.moveRight);
    });
    test('box right of centre -> move item left', () {
      expectPrompt(boxAt(800, 1000), GuidancePrompt.moveLeft);
    });
    test('box above centre -> move item down', () {
      expectPrompt(boxAt(500, 400), GuidancePrompt.moveDown);
    });
    test('box below centre -> move item up', () {
      expectPrompt(boxAt(500, 1600), GuidancePrompt.moveUp);
    });
    test('tiny box -> closer', () {
      expectPrompt(boxAt(500, 1000, h: 30), GuidancePrompt.closer);
    });
    test('clipped at edge -> farther', () {
      expectPrompt(const BoxD(0, 960, 300, 1040), GuidancePrompt.farther);
    });
    test('centred -> hold steady message', () {
      final e = engine();
      final o = e.process(frame(0, [line('SKT')]));
      expect(o.prompt!.text, 'Tarihi buldum, sabit tutun');
    });
    test('digit-heavy partial date without keyword also homes in', () {
      expectPrompt(boxAt(200, 1000), GuidancePrompt.moveRight, text: '15.03');
    });
    test('barcode digits do not trigger homing', () {
      final e = engine();
      final o = e.process(frame(0, [line('8690123456789')]));
      expect(o.phase, GuidancePhase.searching);
    });

    test('haptics rise as the box approaches the centre', () {
      double h(BoxD b) =>
          (engine()..reset()).process(frame(0, [line('SKT', b)])).hapticIntensity;
      expect(h(boxAt(500, 1000)), greaterThan(h(boxAt(700, 1000))));
      expect(h(boxAt(700, 1000)), greaterThan(h(boxAt(900, 1000))));
    });

    test('glare hint after a keyword stays unparsed for a few seconds', () {
      final e = engine();
      final o = feed(e, [line('SKT')], to: 6);
      final p = prompts(o);
      expect(p.first, GuidancePrompt.centeredHold);
      expect(p, contains(GuidancePrompt.glare));
      final g = o.firstWhere((x) => x.prompt?.type == GuidancePrompt.glare);
      expect(g.prompt!.text, 'Ürünü biraz eğin, parlama olabilir');
      expect(o.indexOf(g), greaterThanOrEqualTo(4));
    });
  });

  group('confirming / found', () {
    final good = [line('SKT 15.03.2026')];

    test('needs 3 agreeing frames', () {
      final e = engine();
      final o1 = e.process(frame(0, good));
      final o2 = e.process(frame(0.3, good));
      expect(o1.phase, GuidancePhase.confirming);
      expect(o1.prompt!.text, 'Sabit tutun');
      expect(o2.phase, GuidancePhase.confirming);
      expect(o2.result, isNull);
      final o3 = e.process(frame(0.6, good));
      expect(o3.phase, GuidancePhase.found);
      expect(o3.justFound, isTrue);
      expect(o3.prompt!.text, o3.result!.spokenSummary);
      expect(o3.result!.date, DateTime(2026, 3, 15));
    });

    test('a single noisy read does not trigger found', () {
      final e = engine();
      final o = [
        e.process(frame(0, good)),
        e.process(frame(0.3, [line('SÜT TAM YAĞLI')])),
        e.process(frame(0.6, [line('SÜT TAM YAĞLI')])),
        e.process(frame(0.9, [line('SÜT TAM YAĞLI')])),
        e.process(frame(1.2, [line('SÜT TAM YAĞLI')])),
      ];
      expect(o.any((x) => x.phase == GuidancePhase.found), isFalse);
    });

    test('conflicting dates keep asking to hold steady', () {
      final e = engine();
      final dates = ['10', '11', '12', '13', '14', '15', '16', '17'];
      final o = [
        for (var i = 0; i < dates.length; i++)
          e.process(frame(i * 3.0, [line('SKT ${dates[i]}.03.2026')])),
      ];
      expect(o.every((x) => x.phase == GuidancePhase.confirming), isTrue);
      expect(prompts(o).every((p) => p == GuidancePrompt.holdSteady), isTrue);
    });

    test('noise reading mixed in does not stop the real date winning', () {
      final e = engine();
      e.process(frame(0, good));
      e.process(frame(0.2, [line('SKT 18.03.2026')]));
      e.process(frame(0.4, good));
      final o = e.process(frame(0.6, good));
      expect(o.phase, GuidancePhase.found);
      expect(o.result!.date, DateTime(2026, 3, 15));
    });

    test('production-only date never triggers found', () {
      final e = engine();
      final o = feed(e, [line('ÜT 01.02.2026')], to: 8, step: 0.5);
      expect(o.any((x) => x.phase == GuidancePhase.found), isFalse);
      expect(o.every((x) => x.phase == GuidancePhase.searching), isTrue);
      expect(o.first.prompt!.text,
          'Bu üretim tarihi, son kullanma tarihini aramaya devam edin');
    });

    test('expiry date wins over a production date on the same package', () {
      final e = engine();
      final both = [
        line('ÜT 01.02.2026', const BoxD(100, 300, 500, 350)),
        line('SKT 01.02.2027', const BoxD(100, 400, 500, 450)),
      ];
      final o = feed(e, both, to: 0.6, step: 0.3);
      expect(o.last.phase, GuidancePhase.found);
      expect(o.last.result!.date, DateTime(2027, 2, 1));
    });

    test('stays found until reset', () {
      final e = engine();
      feed(e, good, to: 0.6, step: 0.3);
      final again = e.process(frame(5, [line('baska yazi')]));
      expect(again.phase, GuidancePhase.found);
      expect(again.justFound, isFalse);
      expect(again.prompt, isNull);
      expect(again.result, isNotNull);
      e.reset();
      expect(e.process(frame(10, [line('baska yazi')])).phase,
          GuidancePhase.searching);
    });

    final summaries = <String, (String, ExpiryStatus, int)>{
      'SKT 15.03.2026': (
        'Son kullanma tarihi 15 Mart 2026. 12 gün kaldı.',
        ExpiryStatus.ok,
        12,
      ),
      'SKT 03.03.2026': (
        'Son kullanma tarihi 3 Mart 2026. Bugün son gün.',
        ExpiryStatus.expiresToday,
        0,
      ),
      'SKT 04.03.2026': (
        'Dikkat, son kullanma tarihi 4 Mart 2026. Yarın son gün.',
        ExpiryStatus.soon,
        1,
      ),
      'SKT 06.03.2026': (
        'Dikkat, son kullanma tarihi 6 Mart 2026. 3 gün kaldı.',
        ExpiryStatus.soon,
        3,
      ),
      'SKT 07.03.2026': (
        'Son kullanma tarihi 7 Mart 2026. 4 gün kaldı.',
        ExpiryStatus.ok,
        4,
      ),
      'SKT 28.02.2026': (
        'Dikkat, son kullanma tarihi 28 Şubat 2026, 3 gün önce geçmiş.',
        ExpiryStatus.expired,
        -3,
      ),
      'SKT 03/2026': (
        'Son kullanma tarihi Mart 2026 sonu.',
        ExpiryStatus.ok,
        28,
      ),
      'SKT 12/2026': (
        'Son kullanma tarihi Aralık 2026 sonu.',
        ExpiryStatus.ok,
        303,
      ),
      'SKT 02/2026': (
        'Dikkat, son kullanma tarihi Şubat 2026 sonu, süresi geçmiş.',
        ExpiryStatus.expired,
        -3,
      ),
    };
    summaries.forEach((text, exp) {
      test('summary: $text', () {
        final e = engine();
        final o = feed(e, [line(text)], to: 0.6, step: 0.3).last;
        expect(o.phase, GuidancePhase.found);
        expect(o.result!.spokenSummary, exp.$1);
        expect(o.result!.status, exp.$2);
        expect(o.result!.daysRemaining, exp.$3);
      });
    });

    test('month-only result has month precision', () {
      final e = engine();
      final o = feed(e, [line('SKT 03/2026')], to: 0.6, step: 0.3).last;
      expect(o.result!.precision, DatePrecision.monthYear);
    });
  });

  group('prompt gating', () {
    test('same prompt is not repeated within 5 s, then is', () {
      final e = engine();
      final left = [line('15.03', boxAt(200, 1000))];
      final o = feed(e, left, to: 5.5, step: 0.5);
      final times = [
        for (var i = 0; i < o.length; i++)
          if (o[i].prompt != null) i * 0.5,
      ];
      expect(times, [0.0, 5.0]);
    });

    test('a different prompt waits for the 2.5 s minimum interval', () {
      final e = engine();
      final o = <GuidanceOutput>[
        e.process(frame(0, [line('SKT', boxAt(200, 1000))])),
        e.process(frame(1, [line('SKT', boxAt(800, 1000))])),
        e.process(frame(2, [line('SKT', boxAt(800, 1000))])),
        e.process(frame(2.5, [line('SKT', boxAt(800, 1000))])),
      ];
      expect(o[0].prompt!.type, GuidancePrompt.moveRight);
      expect(o[1].prompt, isNull);
      expect(o[2].prompt, isNull);
      expect(o[3].prompt!.type, GuidancePrompt.moveLeft);
    });

    test('phase change allows a repeat of the same prompt', () {
      final e = engine();
      final a = e.process(frame(0, [line('SKT')])); // centeredHold in homing
      expect(a.prompt!.type, GuidancePrompt.centeredHold);
      // Leave homing, come back inside 5 s but past 2.5 s.
      e.process(frame(1, [line('SÜT TAM YAĞLI')]));
      final b = e.process(frame(3, [line('SKT')]));
      expect(b.prompt?.type, GuidancePrompt.centeredHold);
    });
  });
}
