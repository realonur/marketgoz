import 'package:vibration/vibration.dart';

class HapticHelper {
  HapticHelper._();

  /// Light vibration for button taps
  static Future<void> light() async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 50);
    }
  }

  /// Medium vibration for scan success
  static Future<void> medium() async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 200);
    }
  }

  /// Heavy vibration for errors
  static Future<void> heavy() async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: 400);
    }
  }

  /// Pattern vibration for scan success (short-pause-short)
  static Future<void> scanSuccess() async {
    if (await Vibration.hasCustomVibrationsSupport()) {
      await Vibration.vibrate(
        pattern: [0, 100, 50, 100],
        intensities: [0, 128, 0, 255],
      );
    } else {
      await medium();
    }
  }

  /// Pattern vibration for error (three short bursts)
  static Future<void> error() async {
    if (await Vibration.hasCustomVibrationsSupport()) {
      await Vibration.vibrate(
        pattern: [0, 100, 100, 100, 100, 100],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    } else {
      await heavy();
    }
  }

  /// One short tick for the Geiger-counter guidance pulses.
  static Future<void> tick([int ms = 40]) async {
    if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(duration: ms);
    }
  }

  /// Distinct "found it" pattern: long - short - long.
  static Future<void> foundPattern() async {
    if (await Vibration.hasCustomVibrationsSupport()) {
      await Vibration.vibrate(
        pattern: [0, 450, 150, 120, 150, 450],
        intensities: [0, 255, 0, 255, 0, 255],
      );
    } else if (await Vibration.hasVibrator()) {
      await Vibration.vibrate(pattern: [0, 450, 150, 120, 150, 450]);
    }
  }
}
