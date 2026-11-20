/// Pure helpers for turning raw camera/ML Kit output into engine inputs.
/// No Flutter, no plugins: unit-testable.
library;

import 'dart:typed_data';

import '../../core/expiry/ocr_frame.dart';

/// Size and box mapping for one processed frame.
///
/// ANDROID: ML Kit rotates the NV21 buffer by [rotationDegrees] before
/// recognising, and reports boxes in that already-rotated (upright) space.
/// So boxes are used as-is and only the frame SIZE swaps for 90/270.
///
/// IOS: google_mlkit_commons ignores `rotation` and the camera plugin already
/// delivers frames rotated to the device orientation, so the buffer is treated
/// as upright: no swap, boxes as-is.
class UprightGeometry {
  const UprightGeometry._(this.width, this.height);

  /// Upright image width/height in pixels.
  final double width;
  final double height;

  factory UprightGeometry.resolve({
    required int rotationDegrees,
    required double bufferWidth,
    required double bufferHeight,
    required bool recognizerAppliesRotation,
  }) {
    final r = ((rotationDegrees % 360) + 360) % 360;
    final swap = recognizerAppliesRotation && (r == 90 || r == 270);
    return swap
        ? UprightGeometry._(bufferHeight, bufferWidth)
        : UprightGeometry._(bufferWidth, bufferHeight);
  }

  /// Normalises a recogniser box (fixes reversed corners, clamps into the
  /// upright frame).
  BoxD convert(double left, double top, double right, double bottom) {
    double cx(double v) => v.clamp(0.0, width).toDouble();
    double cy(double v) => v.clamp(0.0, height).toDouble();
    final l = cx(left < right ? left : right);
    final r = cx(left < right ? right : left);
    final t = cy(top < bottom ? top : bottom);
    final b = cy(top < bottom ? bottom : top);
    return BoxD(l, t, r, b);
  }
}

/// Clockwise degrees the stream buffer must be rotated to appear upright.
///
/// [deviceDegrees] is the UI orientation as 0/90/180/270 (portraitUp = 0,
/// landscapeLeft = 90, portraitDown = 180, landscapeRight = 270). On iOS the
/// plugin already delivers upright frames and ML Kit ignores rotation, so the
/// sensor orientation is passed through untouched.
int streamRotationDegrees({
  required int sensorOrientation,
  required int deviceDegrees,
  required bool frontCamera,
  required bool isIOS,
}) {
  if (isIOS) return sensorOrientation;
  return frontCamera
      ? (sensorOrientation + deviceDegrees) % 360
      : (sensorOrientation - deviceDegrees + 360) % 360;
}

enum LumaFormat { nv21, bgra8888 }

/// Mean luminance 0..1 from the first plane, subsampling every [step] pixels.
/// NV21: the plane starts with the Y plane. BGRA: luma is computed per pixel.
/// Returns null when the buffer is unusable.
double? meanLuma({
  required Uint8List bytes,
  required int width,
  required int height,
  required int bytesPerRow,
  required LumaFormat format,
  int step = 8,
}) {
  if (width <= 0 || height <= 0 || bytesPerRow <= 0 || step <= 0) return null;
  var sum = 0.0;
  var n = 0;
  for (var y = 0; y < height; y += step) {
    final row = y * bytesPerRow;
    for (var x = 0; x < width; x += step) {
      switch (format) {
        case LumaFormat.nv21:
          final i = row + x;
          if (i >= bytes.length) continue;
          sum += bytes[i];
        case LumaFormat.bgra8888:
          final i = row + x * 4;
          if (i + 2 >= bytes.length) continue;
          sum += 0.114 * bytes[i] + 0.587 * bytes[i + 1] + 0.299 * bytes[i + 2];
      }
      n++;
    }
  }
  if (n == 0) return null;
  return (sum / n / 255.0).clamp(0.0, 1.0);
}

/// Geiger-counter pulse spacing for a guidance haptic intensity.
/// null = silent. ~1.2 s at low intensity down to 0.25 s at 1.0.
Duration? pulseInterval(double intensity) {
  if (intensity.isNaN || intensity < 0.05) return null;
  final t = intensity.clamp(0.0, 1.0);
  return Duration(milliseconds: (1200 - (1200 - 250) * t).round());
}

/// Accepts a barcode once it has been seen in two consecutive detections.
/// A short run of misses is tolerated; a longer one forgets the candidate.
class BarcodeConfirmer {
  BarcodeConfirmer({this.maxMisses = 2});

  final int maxMisses;
  String? _last;
  int _misses = 0;

  /// Feed the barcode seen in one scan attempt (null = none). Returns the
  /// confirmed barcode, or null.
  String? add(String? value) {
    if (value == null || value.isEmpty) {
      if (++_misses > maxMisses) _last = null;
      return null;
    }
    _misses = 0;
    if (_last == value) return value;
    _last = value;
    return null;
  }

  void reset() {
    _last = null;
    _misses = 0;
  }
}

/// UPC-A (12 digits) -> EAN-13 by a leading zero; other lengths unchanged.
String normalizeBarcode(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  return digits.length == 12 ? '0$digits' : digits;
}

/// Centre of [box] normalised to 0..1 in the UPRIGHT frame. The camera plugin
/// expects focus/exposure points in the displayed (upright portrait) preview
/// space and applies the sensor rotation itself, so no inverse rotation is
/// needed here: only a division by the upright size from [UprightGeometry].
(double, double)? normalizedCenter(BoxD box, UprightGeometry g) {
  if (g.width <= 0 || g.height <= 0) return null;
  return (
    (box.centerX / g.width).clamp(0.0, 1.0).toDouble(),
    (box.centerY / g.height).clamp(0.0, 1.0).toDouble(),
  );
}

/// Rate limit for focus/exposure requests: at most one per [minGap], and only
/// when the target moved by more than [minMove] (normalised distance).
class FocusThrottle {
  FocusThrottle({
    this.minGap = const Duration(milliseconds: 1500),
    this.minMove = 0.06,
  });

  final Duration minGap;
  final double minMove;
  DateTime? _at;
  (double, double)? _last;

  bool shouldFire(DateTime now, (double, double) p) {
    final at = _at, last = _last;
    if (at != null && now.difference(at) < minGap) return false;
    if (last != null) {
      final dx = p.$1 - last.$1, dy = p.$2 - last.$2;
      if (dx * dx + dy * dy < minMove * minMove) return false;
    }
    _at = now;
    _last = p;
    return true;
  }

  void reset() {
    _at = null;
    _last = null;
  }
}
