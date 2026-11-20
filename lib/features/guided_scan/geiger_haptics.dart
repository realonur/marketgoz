/// "Geiger counter" haptics: pulse spacing follows the guidance intensity.
library;

import 'dart:async';

import '../../core/utils/haptic_helper.dart';
import 'frame_math.dart';

class GeigerHaptics {
  GeigerHaptics({
    Future<void> Function()? pulse,
    this.staleAfter = const Duration(milliseconds: 2500),
  }) : _pulse = pulse ?? HapticHelper.tick;

  final Future<void> Function() _pulse;

  /// If no new intensity arrives for this long (OCR stalled), go silent.
  final Duration staleAfter;

  Timer? _timer;
  double _intensity = 0;
  DateTime _updated = DateTime.fromMillisecondsSinceEpoch(0);

  bool get running => _timer != null;

  void update(double intensity) {
    _intensity = intensity;
    _updated = DateTime.now();
    if (_timer == null && pulseInterval(intensity) != null) _tick();
  }

  void _tick() {
    _timer = null;
    final interval = pulseInterval(_intensity);
    if (interval == null || DateTime.now().difference(_updated) > staleAfter) {
      return;
    }
    unawaited(_pulse());
    _timer = Timer(interval, _tick);
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _intensity = 0;
  }
}
