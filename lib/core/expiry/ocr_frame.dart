/// ML-Kit-independent input model for the expiry guidance pipeline.
/// Pure Dart: no dart:ui, no Flutter, no plugins.
library;

/// Axis-aligned box in image pixel coordinates (origin top-left, y down).
class BoxD {
  const BoxD(this.left, this.top, this.right, this.bottom);

  /// Convenience constructor from left/top/width/height.
  const BoxD.fromLTWH(double left, double top, double width, double height)
      : this(left, top, left + width, top + height);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  double get centerX => (left + right) / 2;
  double get centerY => (top + bottom) / 2;

  @override
  String toString() => 'BoxD($left, $top, $right, $bottom)';

  List<double> toJson() => [left, top, right, bottom];

  factory BoxD.fromJson(List<dynamic> j) => BoxD(
        (j[0] as num).toDouble(),
        (j[1] as num).toDouble(),
        (j[2] as num).toDouble(),
        (j[3] as num).toDouble(),
      );
}

/// One recognised text line.
class OcrLine {
  const OcrLine({required this.text, required this.box, this.confidence});

  final String text;
  final BoxD box;

  /// 0..1 when the recogniser provides it.
  final double? confidence;

  Map<String, dynamic> toJson() => {
        'text': text,
        'box': box.toJson(),
        if (confidence != null) 'confidence': confidence,
      };

  factory OcrLine.fromJson(Map<String, dynamic> j) => OcrLine(
        text: j['text'] as String,
        box: BoxD.fromJson(j['box'] as List<dynamic>),
        confidence: (j['confidence'] as num?)?.toDouble(),
      );
}

/// One OCR'd camera frame. The image is assumed to be already rotated upright
/// (portrait, as the user sees it) and not mirrored (rear camera).
class OcrFrame {
  const OcrFrame({
    required this.timestamp,
    required this.imageWidth,
    required this.imageHeight,
    this.lines = const [],
    this.brightness,
    this.hasObjectInFrame = true,
  });

  final DateTime timestamp;
  final double imageWidth;
  final double imageHeight;
  final List<OcrLine> lines;

  /// Mean luminance 0..1, if known.
  final double? brightness;

  /// Hint from an object detector; defaults to true when unknown.
  final bool hasObjectInFrame;

  Map<String, dynamic> toJson() => {
        't': timestamp.toIso8601String(),
        'w': imageWidth,
        'h': imageHeight,
        'lines': [for (final l in lines) l.toJson()],
        if (brightness != null) 'brightness': brightness,
        'object': hasObjectInFrame,
      };

  factory OcrFrame.fromJson(Map<String, dynamic> j) => OcrFrame(
        timestamp: DateTime.parse(j['t'] as String),
        imageWidth: (j['w'] as num).toDouble(),
        imageHeight: (j['h'] as num).toDouble(),
        lines: [
          for (final l in (j['lines'] as List<dynamic>? ?? const []))
            OcrLine.fromJson(l as Map<String, dynamic>),
        ],
        brightness: (j['brightness'] as num?)?.toDouble(),
        hasObjectInFrame: j['object'] as bool? ?? true,
      );
}
