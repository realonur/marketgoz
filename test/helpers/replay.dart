import 'dart:io';

import 'package:marketgoz/core/expiry/expiry_guidance_engine.dart';
import 'package:marketgoz/core/expiry/ocr_frame.dart';
import 'package:marketgoz/features/guided_scan/frame_recorder.dart';

/// Loads a fixture written by the debug frame recorder
/// ({"version":1,"frames":[...]}).
List<OcrFrame> loadFixtureString(String json) =>
    FrameRecorder.framesFromJson(json);

List<OcrFrame> loadFixtureFile(String path) =>
    loadFixtureString(File(path).readAsStringSync());

class ReplayResult {
  ReplayResult(this.outputs, this.foundAt);
  final List<GuidanceOutput> outputs;

  /// Index of the frame that produced the result, or null.
  final int? foundAt;

  ExpiryResult? get result => foundAt == null ? null : outputs[foundAt!].result;
  List<SpokenPrompt> get prompts =>
      [for (final o in outputs) if (o.prompt != null) o.prompt!];
}

/// Feeds [frames] through a fresh (or given) engine, in order.
ReplayResult replay(
  List<OcrFrame> frames, {
  ExpiryGuidanceEngine? engine,
  DateTime Function()? clock,
}) {
  final e = engine ?? ExpiryGuidanceEngine(clock: clock);
  final outs = <GuidanceOutput>[];
  int? foundAt;
  for (var i = 0; i < frames.length; i++) {
    final o = e.process(frames[i]);
    outs.add(o);
    if (o.justFound) foundAt ??= i;
  }
  return ReplayResult(outs, foundAt);
}
