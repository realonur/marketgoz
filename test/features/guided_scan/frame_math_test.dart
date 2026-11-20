import 'dart:typed_data';
import 'package:marketgoz/core/expiry/ocr_frame.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:marketgoz/features/guided_scan/frame_math.dart';

void main() {
  focusTests();
  group('UprightGeometry (Android: recogniser rotates)', () {
    UprightGeometry g(int rot) => UprightGeometry.resolve(
          rotationDegrees: rot,
          bufferWidth: 640,
          bufferHeight: 480,
          recognizerAppliesRotation: true,
        );

    test('0 and 180 keep the buffer size', () {
      for (final r in [0, 180]) {
        expect([g(r).width, g(r).height], [640, 480]);
      }
    });

    test('90 and 270 swap width and height', () {
      for (final r in [90, 270]) {
        expect([g(r).width, g(r).height], [480, 640], reason: 'rot $r');
      }
    });

    test('negative / over-360 rotations are normalised', () {
      expect(g(-90).width, 480);
      expect(g(450).width, 480);
    });

    test('boxes are passed through for every rotation (already upright)', () {
      for (final r in [0, 90, 180, 270]) {
        final b = g(r).convert(10, 20, 110, 70);
        expect([b.left, b.top, b.right, b.bottom], [10, 20, 110, 70]);
      }
    });

    test('boxes are clamped to the upright frame', () {
      final b = g(90).convert(-5, -5, 500, 700); // upright is 480x640
      expect([b.left, b.top, b.right, b.bottom], [0, 0, 480, 640]);
    });

    test('reversed corners are normalised', () {
      final b = g(0).convert(110, 70, 10, 20);
      expect([b.left, b.top, b.right, b.bottom], [10, 20, 110, 70]);
    });
  });

  group('UprightGeometry (iOS: rotation ignored)', () {
    test('never swaps', () {
      for (final r in [0, 90, 180, 270]) {
        final g = UprightGeometry.resolve(
          rotationDegrees: r,
          bufferWidth: 480,
          bufferHeight: 640,
          recognizerAppliesRotation: false,
        );
        expect([g.width, g.height], [480, 640]);
      }
    });
  });

  group('meanLuma', () {
    test('NV21 uniform Y plane', () {
      final bytes = Uint8List(16 * 16 * 3 ~/ 2)..fillRange(0, 16 * 16, 128);
      final l = meanLuma(
          bytes: bytes,
          width: 16,
          height: 16,
          bytesPerRow: 16,
          format: LumaFormat.nv21,
          step: 2);
      expect(l, closeTo(128 / 255, 1e-6));
    });

    test('NV21 black and white', () {
      expect(
          meanLuma(
              bytes: Uint8List(64),
              width: 8,
              height: 8,
              bytesPerRow: 8,
              format: LumaFormat.nv21,
              step: 1),
          0);
      expect(
          meanLuma(
              bytes: Uint8List(64)..fillRange(0, 64, 255),
              width: 8,
              height: 8,
              bytesPerRow: 8,
              format: LumaFormat.nv21,
              step: 1),
          1);
    });

    test('respects bytesPerRow padding', () {
      // 4 px wide, stride 8; padding bytes are 0 and must not be sampled.
      final bytes = Uint8List(8 * 4);
      for (var y = 0; y < 4; y++) {
        for (var x = 0; x < 4; x++) {
          bytes[y * 8 + x] = 255;
        }
      }
      expect(
          meanLuma(
              bytes: bytes,
              width: 4,
              height: 4,
              bytesPerRow: 8,
              format: LumaFormat.nv21,
              step: 1),
          1);
    });

    test('BGRA white is ~1, black is 0', () {
      final white = Uint8List(4 * 4 * 4)..fillRange(0, 64, 255);
      expect(
          meanLuma(
              bytes: white,
              width: 4,
              height: 4,
              bytesPerRow: 16,
              format: LumaFormat.bgra8888,
              step: 1),
          closeTo(1, 1e-6));
      expect(
          meanLuma(
              bytes: Uint8List(64),
              width: 4,
              height: 4,
              bytesPerRow: 16,
              format: LumaFormat.bgra8888,
              step: 1),
          0);
    });

    test('bad input returns null', () {
      expect(
          meanLuma(
              bytes: Uint8List(0),
              width: 0,
              height: 0,
              bytesPerRow: 0,
              format: LumaFormat.nv21),
          isNull);
    });
  });

  group('pulseInterval', () {
    test('silent at 0', () => expect(pulseInterval(0), isNull));
    test('~1.2 s at low, 0.25 s at max', () {
      expect(pulseInterval(0.05)!.inMilliseconds, greaterThan(1100));
      expect(pulseInterval(1)!.inMilliseconds, 250);
    });
    test('monotonic', () {
      var prev = 1 << 30;
      for (var i = 1; i <= 20; i++) {
        final ms = pulseInterval(i / 20)!.inMilliseconds;
        expect(ms, lessThanOrEqualTo(prev));
        prev = ms;
      }
    });
  });

  group('BarcodeConfirmer', () {
    test('needs the same value twice in a row', () {
      final c = BarcodeConfirmer();
      expect(c.add('8690504002020'), isNull);
      expect(c.add('8690504002020'), '8690504002020');
    });
    test('a different value restarts the streak', () {
      final c = BarcodeConfirmer();
      expect(c.add('111'), isNull);
      expect(c.add('222'), isNull);
      expect(c.add('222'), '222');
    });
    test('tolerates short misses but forgets after long ones', () {
      final c = BarcodeConfirmer();
      c.add('111');
      c.add(null);
      expect(c.add('111'), '111');
      final d = BarcodeConfirmer();
      d.add('111');
      d.add(null);
      d.add(null);
      d.add(null);
      expect(d.add('111'), isNull);
    });
  });

  test('normalizeBarcode pads UPC-A to EAN-13', () {
    expect(normalizeBarcode('012345678905'), '0012345678905');
    expect(normalizeBarcode('8690504002020'), '8690504002020');
  });
}

void focusTests() {
  group('focus point', () {
    final g = UprightGeometry.resolve(
      rotationDegrees: 90,
      bufferWidth: 1280,
      bufferHeight: 720,
      recognizerAppliesRotation: true,
    ); // upright 720x1280

    test('normalised in the upright frame', () {
      final p = normalizedCenter(const BoxD(0, 0, 720, 1280), g)!;
      expect(p, (0.5, 0.5));
      final q = normalizedCenter(const BoxD.fromLTWH(540, 320, 100, 40), g)!;
      expect(q.$1, closeTo(590 / 720, 1e-9));
      expect(q.$2, closeTo(340 / 1280, 1e-9));
    });

    test('throttle: gap and movement', () {
      final t = FocusThrottle();
      final t0 = DateTime(2026);
      expect(t.shouldFire(t0, (0.5, 0.5)), isTrue);
      expect(t.shouldFire(t0.add(const Duration(milliseconds: 500)), (0.9, 0.9)),
          isFalse); // too soon
      expect(t.shouldFire(t0.add(const Duration(seconds: 2)), (0.51, 0.5)),
          isFalse); // barely moved
      expect(t.shouldFire(t0.add(const Duration(seconds: 2)), (0.7, 0.5)),
          isTrue);
    });
  });
}
