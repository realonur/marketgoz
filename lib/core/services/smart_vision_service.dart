import 'dart:ui';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';

import '../models/product_signature.dart';
import 'product_recognition_service.dart';
import 'product_storage_service.dart';

/// Smart Vision service - facade for product recognition
/// Provides compatibility with existing UI components
class SmartVisionService {
  static SmartVisionService? _instance;
  
  final ProductRecognitionService _recognitionService = ProductRecognitionService.instance;
  final ProductStorageService _storageService = ProductStorageService.instance;
  
  bool _initialized = false;

  SmartVisionService._();

  /// Get singleton instance
  static SmartVisionService get instance {
    _instance ??= SmartVisionService._();
    return _instance!;
  }

  /// Factory constructor for backward compatibility
  factory SmartVisionService() => instance;

  /// Initialize the service
  Future<void> initialize({bool highAccuracy = false}) async {
    // Allows re-initialization if needed
    try {
      await _recognitionService.initialize(highAccuracy: highAccuracy);
      _initialized = true;
      debugPrint('SmartVisionService: Initialized (HighAccuracy: $highAccuracy)');
    } catch (e) {
      debugPrint('SmartVisionService: Initialization error: $e');
      rethrow;
    }
  }

  /// Change detection accuracy mode
  Future<void> setAccuracyMode(bool highAccuracy) async {
    await initialize(highAccuracy: highAccuracy);
  }

  /// Find a matching signature for given visual features
  /// This is the main method called by the scanner
  ProductSignature? findMatchingSignature({
    required String yoloLabel,
    required String aspectRatio,
    required Color dominantColor,
    double aspectRatioValue = 1.0,
    List<double>? colorHSV,
  }) {
    // Convert to HSV if not provided
    final hsv = colorHSV ?? ColorUtils.rgbToHsv(dominantColor);
    final colorName = ColorUtils.getColorName(hsv);

    // Create a temporary detection result for matching
    final tempDetection = HybridDetectionResult(
      label: yoloLabel,
      aspectRatio: aspectRatio,
      aspectRatioValue: aspectRatioValue,
      dominantColor: dominantColor,
      colorName: colorName,
      colorHSV: hsv,
    );

    return _storageService.findBestMatch(tempDetection);
  }

  /// Add a new product signature to the database
  Future<ProductSignature> addSignature({
    required String productName,
    required String yoloLabel,
    required String aspectRatio,
    required Color dominantColor,
    required String colorName,
    double aspectRatioValue = 1.0,
    List<double>? colorHSV,
    String? barcode,
    Map<String, double> visualTags = const {},
  }) async {
    final hsv = colorHSV ?? ColorUtils.rgbToHsv(dominantColor);
    final id = _storageService.generateId();

    final signature = ProductSignature(
      id: id,
      barcode: barcode,
      productName: productName,
      userGivenName: productName,
      label: yoloLabel,
      aspectRatio: aspectRatio,
      aspectRatioValue: aspectRatioValue,
      dominantColor: dominantColor,
      colorName: colorName,
      colorHSV: hsv,
      visualTags: visualTags, // Save fingerprint
    );

    await _storageService.saveSignature(signature);
    return signature;
  }

  /// Record a detection hit for a signature
  Future<void> recordDetectionHit(String signatureId) async {
    await _storageService.recordDetectionHit(signatureId);
  }

  /// Get all saved signatures
  List<ProductSignature> getAllSignatures() {
    return _storageService.getAllSignatures();
  }

  /// Delete a signature
  Future<void> deleteSignature(String id) async {
    await _storageService.deleteSignature(id);
  }

  /// Get statistics
  Map<String, dynamic> getStatistics() {
    return _storageService.getStatistics();
  }

  /// Check if initialized
  bool get isInitialized => _initialized;

  /// Dispose resources
  Future<void> dispose() async {
    await _recognitionService.dispose();
    _initialized = false;
  }
}
