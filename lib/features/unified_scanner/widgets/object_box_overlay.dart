import 'package:flutter/material.dart';
import 'dart:ui' as ui;

import '../../../core/constants/app_theme.dart';
import '../../../core/models/product_signature.dart';

/// Overlay widget for rendering object bounding boxes
/// Uses proper camera-to-screen coordinate transformation
class ObjectBoxOverlay extends StatelessWidget {
  final List<HybridDetectionResult> detections;
  final Size previewSize;
  final Size screenSize;
  final Color unknownBoxColor;
  final Color knownBoxColor;
  final Color linkedBoxColor;
  final void Function(HybridDetectionResult)? onBoxTap;
  final bool showLabels;
  final bool dataCollectionMode;

  const ObjectBoxOverlay({
    super.key,
    required this.detections,
    required this.previewSize,
    required this.screenSize,
    this.unknownBoxColor = AppTheme.defaultBoxColorUnknown,
    this.knownBoxColor = AppTheme.defaultBoxColorKnown,
    this.linkedBoxColor = AppTheme.defaultBoxColorLinked,
    this.onBoxTap,
    this.showLabels = true,
    this.dataCollectionMode = false,
  });

  @override
  Widget build(BuildContext context) {
    if (detections.isEmpty) return const SizedBox.shrink();

    return Stack(
      children: detections.map((detection) {
        final box = _transformBox(detection.normalizedBox);
        if (box == null) return const SizedBox.shrink();

        final color = _getBoxColor(detection);
        final isKnown = detection.isKnown;
        final hasBarcode = detection.matchedSignature?.barcode != null;

        return Positioned(
          left: box.left,
          top: box.top,
          width: box.width,
          height: box.height,
          child: GestureDetector(
            onTap: onBoxTap != null ? () => onBoxTap!(detection) : null,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: color,
                  width: 3.0,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Stack(
                children: [
                  // Label at top
                  if (showLabels)
                    Positioned(
                      top: 0,
                      left: 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: color,
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(6),
                                bottomRight: Radius.circular(6),
                              ),
                            ),
                            child: Text(
                              detection.displayName, // Always use displayName (handles fallback)
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (detection.detectedText.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 2),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                detection.detectedText,
                                style: const TextStyle(
                                  color: Colors.yellow,
                                  fontSize: 10,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ),

                  // Status indicator at bottom
                  Positioned(
                    bottom: 4,
                    left: 4,
                    right: 4,
                    child: Center(
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 100),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              dataCollectionMode
                                  ? Icons.add_circle
                                  : (hasBarcode
                                      ? Icons.qr_code
                                      : Icons.touch_app),
                              color: Colors.white,
                              size: 12,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                dataCollectionMode
                                    ? 'Ekle'
                                    : (hasBarcode ? 'Barkod' : 'Dokun'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 9,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  /// Transform normalized box (0..1) to screen coordinates
  /// Since CameraPreview fills the full screen, we map directly
  Rect? _transformBox(ui.Rect? normalizedBox) {
    if (normalizedBox == null) return null;

    // CameraPreview fills the entire screen by scaling to fit
    // So normalized coordinates (0..1) map directly to screen pixels
    final left = normalizedBox.left * screenSize.width;
    final top = normalizedBox.top * screenSize.height;
    final width = normalizedBox.width * screenSize.width;
    final height = normalizedBox.height * screenSize.height;

    // Clamp to screen bounds with safe min/max
    final clampedLeft = left.clamp(0.0, screenSize.width - 20);
    final clampedTop = top.clamp(0.0, screenSize.height - 20);
    final maxWidth = (screenSize.width - clampedLeft).clamp(20.0, screenSize.width);
    final maxHeight = (screenSize.height - clampedTop).clamp(20.0, screenSize.height);
    
    return Rect.fromLTWH(
      clampedLeft,
      clampedTop,
      width.clamp(20.0, maxWidth),
      height.clamp(20.0, maxHeight),
    );
  }

  Color _getBoxColor(HybridDetectionResult detection) {
    if (detection.matchedSignature?.barcode != null) {
      return linkedBoxColor;
    } else if (detection.isKnown) {
      return knownBoxColor;
    } else {
      return unknownBoxColor;
    }
  }
}
