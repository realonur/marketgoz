import 'package:flutter_test/flutter_test.dart';
import 'package:marketgoz/core/expiry/expiry_guidance_engine.dart';
import 'package:marketgoz/core/expiry/ocr_frame.dart';
import 'package:marketgoz/features/guided_scan/frame_math.dart';
import 'package:marketgoz/features/guided_scan/zoom_policy.dart';

const _w = 720.0, _h = 1280.0;

BoxD _box(double cx, double cy, double w, double h) =>
    BoxD.fromLTWH(cx - w / 2, cy - h / 2, w, h);

void main() {
  group('zoomCeiling', () {
    test('plugin max and hard cap win', () {
      expect(zoomCeiling(pluginMax: 2.0), 2.0);
      expect(zoomCeiling(pluginMax: 20), 3.0);
    });
    test('iOS upscale threshold limits, but not below 1.5', () {
      expect(zoomCeiling(pluginMax: 20, upscaleThreshold: 2.2), 2.2);
      expect(zoomCeiling(pluginMax: 20, upscaleThreshold: 1.0), 1.5);
    });
    test('never below 1', () {
      expect(zoomCeiling(pluginMax: 0.5), 1.0);
    });
  });

  group('desiredZoom', () {
    double z(BoxD b, {double cur = 1, double ceil = 3}) => desiredZoom(
          box: b,
          frameW: _w,
          frameH: _h,
          current: cur,
          floor: 1,
          ceiling: ceil,
        );

    test('tiny centred box is magnified to about 28 px', () {
      expect(z(_box(360, 640, 100, 14)), closeTo(2.0, 1e-9));
    });
    test('clamped to the ceiling', () {
      expect(z(_box(360, 640, 60, 7), ceil: 2.5), 2.5);
    });
    test('box already in the comfortable band is left alone', () {
      expect(z(_box(360, 640, 200, 40), cur: 1.5), 1.5);
    });
    test('very large box zooms back out, not below the floor', () {
      expect(z(_box(360, 640, 300, 150), cur: 2), 1.0);
      expect(z(_box(360, 640, 300, 124), cur: 3), closeTo(3 * 61.6 / 124, 1e-9));
    });
    test('limited so the box stays in frame', () {
      // 200 px wide box centred 200 px right of centre: reach 300 of 338.4.
      final r = z(_box(560, 640, 200, 10));
      expect(r, closeTo(338.4 / 300, 1e-9));
    });
    test('clipped box zooms out', () {
      final r = z(_box(700, 640, 100, 40), cur: 2);
      expect(r, lessThan(2));
      expect(r, greaterThanOrEqualTo(1));
    });
    test('degenerate box is ignored', () {
      expect(z(const BoxD(5, 5, 5, 5), cur: 1.7), 1.7);
    });
  });

  group('ZoomPolicy', () {
    final t0 = DateTime(2025, 1, 1, 12);
    ZoomPolicy policy() => ZoomPolicy(ceiling: 3);
    double? step(ZoomPolicy p, DateTime now, GuidancePhase ph, BoxD? b) =>
        p.decide(now: now, phase: ph, targetBox: b, frameW: _w, frameH: _h);
    final tiny = _box(360, 640, 100, 14);

    test('zooms in while homing in on a tiny box', () {
      final p = policy();
      expect(step(p, t0, GuidancePhase.homingIn, tiny), 2.0);
      expect(p.current, 2.0);
    });
    test('searching and waiting never zoom in', () {
      final p = policy();
      for (final ph in [GuidancePhase.searching, GuidancePhase.waitingForItem]) {
        expect(step(p, t0, ph, tiny), isNull);
      }
    });
    test('settle time blocks rapid changes', () {
      final p = policy();
      step(p, t0, GuidancePhase.homingIn, tiny);
      final tinier = _box(360, 640, 100, 9);
      expect(
          step(p, t0.add(const Duration(milliseconds: 300)),
              GuidancePhase.homingIn, tinier),
          isNull);
      expect(
          step(p, t0.add(const Duration(milliseconds: 800)),
              GuidancePhase.homingIn, tinier),
          isNotNull);
    });
    test('confirming never zooms in', () {
      final p = policy();
      expect(step(p, t0, GuidancePhase.confirming, tiny), isNull);
    });
    test('confirming still backs off a clipped box', () {
      final p = policy();
      step(p, t0, GuidancePhase.homingIn, tiny);
      final clipped = _box(700, 640, 100, 40);
      final r = step(p, t0.add(const Duration(seconds: 1)),
          GuidancePhase.confirming, clipped);
      expect(r, isNotNull);
      expect(r!, lessThan(2.0));
    });
    test('releases to the floor only after the target has been gone', () {
      final p = policy();
      step(p, t0, GuidancePhase.homingIn, tiny);
      expect(
          step(p, t0.add(const Duration(seconds: 1)), GuidancePhase.searching,
              null),
          isNull);
      expect(
          step(p, t0.add(const Duration(seconds: 4)), GuidancePhase.searching,
              null),
          1.0);
      expect(p.current, 1.0);
    });
    test('small wobble inside the deadband is ignored', () {
      final p = policy();
      step(p, t0, GuidancePhase.homingIn, tiny); // 2.0
      final slightly = _box(360, 640, 200, 27); // measured at 2x: wants 2.07
      expect(
          step(p, t0.add(const Duration(seconds: 2)), GuidancePhase.homingIn,
              slightly),
          isNull);
    });
    test('reset returns to the floor', () {
      final p = policy();
      step(p, t0, GuidancePhase.homingIn, tiny);
      p.reset();
      expect(p.current, 1.0);
      expect(step(p, t0, GuidancePhase.homingIn, tiny), 2.0);
    });
  });

  group('focusPointForZoom', () {
    test('Android: unchanged', () {
      expect(focusPointForZoom((0.7, 0.4), 2, fullFieldCoordinates: false),
          (0.7, 0.4));
    });
    test('iOS: maps into the un-zoomed field', () {
      final p = focusPointForZoom((0.7, 0.3), 2, fullFieldCoordinates: true);
      expect(p.$1, closeTo(0.6, 1e-9));
      expect(p.$2, closeTo(0.4, 1e-9));
    });
    test('iOS at 1x: unchanged', () {
      expect(focusPointForZoom((0.7, 0.4), 1, fullFieldCoordinates: true),
          (0.7, 0.4));
    });
  });

  group('streamRotationDegrees', () {
    int r(int sensor, int dev, {bool front = false, bool ios = false}) =>
        streamRotationDegrees(
            sensorOrientation: sensor,
            deviceDegrees: dev,
            frontCamera: front,
            isIOS: ios);
    test('Android back camera portrait', () => expect(r(90, 0), 90));
    test('Android back camera landscapeLeft', () => expect(r(90, 90), 0));
    test('Android back camera portraitDown', () => expect(r(90, 180), 270));
    test('Android front adds', () => expect(r(270, 90, front: true), 0));
    test('iOS passes sensor orientation through',
        () => expect(r(90, 180, ios: true), 90));
  });
}
