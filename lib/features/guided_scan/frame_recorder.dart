/// Debug-only ring buffer of recent OCR frames, exportable as a JSON fixture.
library;

import 'dart:collection';
import 'dart:convert';

import '../../core/expiry/ocr_frame.dart';

class FrameRecorder {
  FrameRecorder({this.capacity = 200});

  final int capacity;
  final Queue<OcrFrame> _frames = Queue();

  int get length => _frames.length;

  void add(OcrFrame f) {
    _frames.addLast(f);
    while (_frames.length > capacity) {
      _frames.removeFirst();
    }
  }

  void clear() => _frames.clear();

  List<OcrFrame> get frames => List.unmodifiable(_frames);

  /// Fixture format: {"version":1,"frames":[...]}.
  String toJsonString() => const JsonEncoder.withIndent(' ').convert({
        'version': 1,
        'frames': [for (final f in _frames) f.toJson()],
      });

  static List<OcrFrame> framesFromJson(String json) {
    final m = jsonDecode(json) as Map<String, dynamic>;
    return [
      for (final f in (m['frames'] as List<dynamic>))
        OcrFrame.fromJson(f as Map<String, dynamic>),
    ];
  }
}
