import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../models/product_signature.dart';
import 'product_recognition_service.dart';

/// Hybrid Detector - combines ML Kit object detection with visual signature analysis
/// This class provides a simple interface for camera frame processing
class HybridDetector {
  static HybridDetector? _instance;
  
  final ProductRecognitionService _recognitionService = ProductRecognitionService.instance;
  
  // Latest detection results
  List<HybridDetectionResult>? _lastResults;
  
  HybridDetector._();

  /// Get singleton instance
  static HybridDetector get instance {
    _instance ??= HybridDetector._();
    return _instance!;
  }

  /// Factory constructor for backward compatibility
  factory HybridDetector() => instance;

  /// Initialize the detector
  Future<void> initialize() async {
    await _recognitionService.initialize();
  }

  /// Analyze a camera frame and return the primary detection result
  /// Returns null if no objects detected or frame is throttled
  HybridDetectionResult? analyzeFrame(CameraImage image) {
    // This method is synchronous for compatibility, but actual processing is async
    // The last result is cached for immediate return
    
    // Trigger async processing
    _processFrameAsync(image);
    
    // Return the most recent primary result
    return _lastResults?.isNotEmpty == true ? _lastResults!.first : null;
  }

  /// Async frame processing
  Future<void> _processFrameAsync(CameraImage image) async {
    try {
      final results = await _recognitionService.processFrame(image);
      if (results != null) {
        _lastResults = results;
      }
    } catch (e) {
      debugPrint('HybridDetector: Error analyzing frame: $e');
    }
  }

  /// Analyze a frame and get all detection results
  Future<List<HybridDetectionResult>?> analyzeFrameAsync(
    CameraImage image, {
    InputImageRotation rotation = InputImageRotation.rotation0deg,
  }) async {
    final results = await _recognitionService.processFrame(
      image,
      rotation: rotation,
    );
    
    if (results != null) {
      _lastResults = results;
    }
    
    return results;
  }

  /// Get the last detection results
  List<HybridDetectionResult>? get lastResults => _lastResults;

  /// Clear cached results
  void clearResults() {
    _lastResults = null;
  }

  /// Reset throttling
  void resetThrottling() {
    _recognitionService.resetThrottling();
  }

  /// Check if initialized
  bool get isInitialized => _recognitionService.isInitialized;

  /// Dispose resources
  Future<void> dispose() async {
    await _recognitionService.dispose();
    _lastResults = null;
  }
}
