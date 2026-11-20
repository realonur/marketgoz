import 'package:flutter_test/flutter_test.dart';
import 'package:marketgoz/core/expiry/expiry_date_reader.dart';
import 'package:marketgoz/core/expiry/expiry_guidance_engine.dart';
import 'package:marketgoz/core/expiry/ocr_frame.dart';
import 'package:marketgoz/features/guided_scan/frame_recorder.dart';

import '../../helpers/replay.dart';

void main() {
  final t0 = DateTime(2026, 3, 3, 12);

  OcrFrame frame(int i, List<String> texts, {double? brightness}) => OcrFrame(
        timestamp: t0.add(Duration(milliseconds: 300 * i)),
        imageWidth: 480,
        imageHeight: 640,
        brightness: brightness,
        lines: [
          for (var k = 0; k < texts.length; k++)
            OcrLine(
              text: texts[k],
              box: BoxD.fromLTWH(160, 280 + 40.0 * k, 160, 30),
              confidence: 0.9,
            ),
        ],
      );

  test('OcrFrame JSON round trip', () {
    final f = frame(1, ['SKT 15.03.2026'], brightness: 0.4);
    final g = OcrFrame.fromJson(f.toJson());
    expect(g.timestamp, f.timestamp);
    expect(g.imageWidth, 480);
    expect(g.brightness, 0.4);
    expect(g.lines.single.text, 'SKT 15.03.2026');
    expect(g.lines.single.box.top, 280);
    expect(g.lines.single.confidence, 0.9);
    expect(OcrFrame.fromJson(frame(0, []).toJson()).brightness, isNull);
  });

  test('recorder keeps only the last N frames', () {
    final r = FrameRecorder(capacity: 5);
    for (var i = 0; i < 12; i++) {
      r.add(frame(i, ['x']));
    }
    expect(r.length, 5);
    expect(r.frames.first.timestamp, frame(7, []).timestamp);
  });

  test('a recorded session replays through the engine to a result', () {
    final rec = FrameRecorder();
    rec.add(frame(0, []));
    rec.add(frame(1, ['Net 500 g']));
    for (var i = 2; i < 8; i++) {
      rec.add(frame(i, ['S K T 15.03.2026']));
    }
    final frames = loadFixtureString(rec.toJsonString());
    expect(frames.length, 8);

    final r = replay(frames, clock: () => t0);
    expect(r.foundAt, isNotNull);
    expect(r.result!.date, DateTime(2026, 3, 15));
    expect(r.result!.precision, DatePrecision.day);
    expect(r.result!.status, ExpiryStatus.ok);
    expect(r.result!.daysRemaining, 12);
  });
}
