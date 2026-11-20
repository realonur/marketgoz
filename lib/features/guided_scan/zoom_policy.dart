/// Pure zoom decisions for the guided scan. No Flutter, no plugins.
///
/// Why zoom and not a bigger stream: the camera plugin's `setZoomLevel` crops
/// the full sensor (iOS videoZoomFactor, Android CameraX zoom ratio) and
/// scales the crop to the stream size, so a 2x zoom on a 720p stream gives
/// 2x the pixels per character at no extra OCR cost and no stream restart.
library;

import 'dart:math' as math;

import '../../core/expiry/expiry_guidance_engine.dart' show GuidancePhase;
import '../../core/expiry/ocr_frame.dart';

/// Largest zoom the policy will request.
///
/// [pluginMax] is the controller's max zoom. [upscaleThreshold] is iOS's
/// `videoZoomFactorUpscaleThreshold` (null when unknown / Android): beyond it
/// the sensor no longer supplies new detail. Never below 1.5 so a device that
/// reports ~1.0 still gets the (smaller) benefit of larger glyphs for ML Kit.
double zoomCeiling({
  required double pluginMax,
  double? upscaleThreshold,
  double hardCap = 3.0,
}) {
  var c = math.min(pluginMax, hardCap);
  if (upscaleThreshold != null && upscaleThreshold > 0) {
    c = math.min(c, math.max(upscaleThreshold, 1.5));
  }
  return math.max(1.0, c);
}

/// Zoom that makes [box] about [targetPx] tall while keeping it in the frame.
///
/// [box] and [frameW]/[frameH] are in the upright frame captured at zoom
/// [current]. Returns an absolute zoom clamped to [[floor], [ceiling]]; the
/// result is [current] when the box is already in the comfortable band
/// (targetPx .. 2.2*targetPx) so the policy does not chatter.
double desiredZoom({
  required BoxD box,
  required double frameW,
  required double frameH,
  required double current,
  required double floor,
  required double ceiling,
  double targetPx = 28,
  double edgeMargin = 0.06,
}) {
  if (box.height <= 0 || box.width <= 0 || frameW <= 0 || frameH <= 0) {
    return current;
  }
  // Size wish.
  var ratio = 1.0;
  if (box.height < targetPx) {
    ratio = targetPx / box.height;
  } else if (box.height > 2.2 * targetPx) {
    ratio = (2.2 * targetPx) / box.height;
  }
  // Field-of-view limit: after scaling by r about the frame centre the box
  // extent must stay inside the frame minus the margin. May be < 1, which
  // zooms out to un-clip a box.
  final halfW = frameW / 2 * (1 - edgeMargin);
  final halfH = frameH / 2 * (1 - edgeMargin);
  final reachX = (box.centerX - frameW / 2).abs() + box.width / 2;
  final reachY = (box.centerY - frameH / 2).abs() + box.height / 2;
  final fit = math.min(halfW / reachX, halfH / reachY);
  ratio = math.min(ratio, fit);
  return (current * ratio).clamp(floor, math.max(floor, ceiling)).toDouble();
}

/// Maps a focus/exposure point from the (zoomed) upright frame to what the
/// platform expects. iOS focusPointOfInterest is expressed in the full,
/// un-zoomed field of view; Android CameraX metering points are relative to the
/// current crop region, so they need no change.
(double, double) focusPointForZoom((double, double) p, double zoom,
    {required bool fullFieldCoordinates}) {
  if (!fullFieldCoordinates || zoom <= 1.0) return p;
  double f(double v) => (0.5 + (v - 0.5) / zoom).clamp(0.0, 1.0).toDouble();
  return (f(p.$1), f(p.$2));
}

/// Stateful wrapper: rate limiting, settle time and release when searching.
class ZoomPolicy {
  ZoomPolicy({
    required this.ceiling,
    this.floor = 1.0,
    this.targetPx = 28,
    this.settle = const Duration(milliseconds: 700),
    this.releaseAfter = const Duration(milliseconds: 2500),
    this.deadband = 0.12,
    this.step = 0.1,
  });

  final double ceiling;
  final double floor;
  final double targetPx;

  /// Minimum gap between zoom changes; also covers frames already in flight
  /// at the old zoom, whose boxes would be misread as the new zoom's.
  final Duration settle;

  /// How long the target must be gone before zooming back out.
  final Duration releaseAfter;

  /// Relative changes smaller than this are ignored.
  final double deadband;

  /// Requested zoom is rounded to a multiple of this.
  final double step;

  double _current = 1.0;
  DateTime? _lastChange;
  DateTime? _lastTarget;

  double get current => _current;

  /// Returns the new zoom to apply, or null to leave it alone.
  double? decide({
    required DateTime now,
    required GuidancePhase phase,
    required BoxD? targetBox,
    required double frameW,
    required double frameH,
  }) {
    final last = _lastChange;
    if (last != null && now.difference(last) < settle) return null;

    final tracking = targetBox != null &&
        (phase == GuidancePhase.homingIn || phase == GuidancePhase.confirming);

    double wanted;
    if (tracking) {
      _lastTarget = now;
      wanted = desiredZoom(
        box: targetBox,
        frameW: frameW,
        frameH: frameH,
        current: _current,
        floor: floor,
        ceiling: ceiling,
        targetPx: targetPx,
      );
      // While confirming a read, only ever back off (to un-clip), so the
      // picture does not jump under the engine's stability check.
      if (phase == GuidancePhase.confirming) wanted = math.min(wanted, _current);
    } else {
      final seen = _lastTarget;
      if (_current <= floor || seen == null) return null;
      if (now.difference(seen) < releaseAfter) return null;
      wanted = floor;
    }

    wanted = ((wanted / step).round() * step).clamp(floor, ceiling).toDouble();
    if ((wanted / _current - 1).abs() < deadband && wanted != floor) {
      return null;
    }
    if (wanted == _current) return null;
    _current = wanted;
    _lastChange = now;
    return wanted;
  }

  /// Back to [floor] after a restart (the caller applies it to the camera).
  void reset() {
    _current = floor;
    _lastChange = null;
    _lastTarget = null;
  }

  /// The camera refused or reported a different zoom.
  void syncTo(double actual) => _current = actual;
}
