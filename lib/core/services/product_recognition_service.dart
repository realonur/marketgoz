import 'dart:io';
import 'dart:ui' as ui;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart'; // For temp files

import '../models/product_signature.dart';
import 'product_storage_service.dart';

/// Service for recognizing products using ML Kit object detection
/// and visual signature analysis (aspect ratio + dominant HSV color)
class ProductRecognitionService {
  static ProductRecognitionService? _instance;
  
  // ML Kit Detectors
  ObjectDetector? _objectDetector;
  ImageLabeler? _imageLabeler;
  TextRecognizer? _textRecognizer;
  
  // Storage service
  final ProductStorageService _storageService = ProductStorageService.instance;
  
  // Throttling - configurable FPS (default 2 FPS = 500ms)
  DateTime? _lastProcessTime;
  Duration _throttleDuration = const Duration(milliseconds: 500);
  
  /// Set the processing FPS (1-10 range recommended)
  void setFPS(int fps) {
    final clampedFps = fps.clamp(1, 15);
    _throttleDuration = Duration(milliseconds: (1000 / clampedFps).round());
  }
  
  /// Get current FPS setting
  int get currentFPS => (1000 / _throttleDuration.inMilliseconds).round();  
  
  // Processing lock
  bool _isProcessing = false;
  
  // Tolerance settings (relaxed)
  double ratioTolerance = 0.25;
  double hueTolerance = 30.0;
  double saturationTolerance = 0.3;
  double valueTolerance = 0.3;
  
  // Confidence threshold for detections (lowered to catch more objects)
  double confidenceThreshold = 0.3;
  
  bool _initialized = false;

  ProductRecognitionService._();

  /// Get singleton instance
  static ProductRecognitionService get instance {
    _instance ??= ProductRecognitionService._();
    return _instance!;
  }

  /// Initialize the service
  /// [highAccuracy] - If true, uses single image mode (slower but better bounding boxes)
  Future<void> initialize({bool highAccuracy = false}) async {
    try {
      if (!_initialized) {
        // Initialize storage only once
        await _storageService.initialize();
      }
      
      // Dispose check if re-initializing
      if (_objectDetector != null) {
        await _objectDetector?.close();
        _objectDetector = null;
      }
      if (_imageLabeler != null) {
        await _imageLabeler?.close();
        _imageLabeler = null;
      }
      if (_textRecognizer != null) {
        await _textRecognizer?.close();
        _textRecognizer = null;
      }
      
      // Initialize ML Kit Object Detector
      final options = ObjectDetectorOptions(
        mode: highAccuracy ? DetectionMode.single : DetectionMode.stream,
        classifyObjects: true,
        multipleObjects: true,
      );
      
      _objectDetector = ObjectDetector(options: options);
      
      // Initialize Image Labeler (Semantic Fingerprinting)
      final labelerOptions = ImageLabelerOptions(confidenceThreshold: 0.5);
      _imageLabeler = ImageLabeler(options: labelerOptions);

      // Initialize Text Recognizer (OCR)
      _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      
      _initialized = true;
      
      // Adjust throttling based on mode
      if (highAccuracy) {
        setFPS(1); 
        debugPrint('ProductRecognitionService: Initialized (High Accuracy + Semantics)');
      } else {
        setFPS(2); 
        debugPrint('ProductRecognitionService: Initialized (Stream Mode + Semantics)');
      }
      
    } catch (e) {
      debugPrint('ProductRecognitionService: Initialization error: $e');
      rethrow;
    }
  }

  /// Process a camera frame and return detected products
  /// Returns null if throttled or no detections
  Future<List<HybridDetectionResult>?> processFrame(
    CameraImage cameraImage, {
    InputImageRotation rotation = InputImageRotation.rotation0deg,
  }) async {
    // Throttle check
    final now = DateTime.now();
    if (_lastProcessTime != null &&
        now.difference(_lastProcessTime!) < _throttleDuration) {
      return null;
    }
    
    // Lock check
    if (_isProcessing) return null;
    _isProcessing = true;
    _lastProcessTime = now;

    try {
      // Convert camera image to InputImage
      final inputImage = _convertCameraImage(cameraImage, rotation);
      if (inputImage == null) {
        return null;
      }

      // Run ML Kit object detection
      final objects = await _objectDetector?.processImage(inputImage);
      
      debugPrint('ProductRecognitionService: ML Kit returned ${objects?.length ?? 0} objects');
      
      if (objects == null || objects.isEmpty) {
        return null;
      }
      
      // Log all detected objects even if we filter them
      for (final obj in objects) {
        final labels = obj.labels.map((l) => '${l.text}(${(l.confidence * 100).toStringAsFixed(0)}%)').join(', ');
        debugPrint('  Object: labels=[$labels], box=${obj.boundingBox}');
      }

      // Get raw image bytes for color extraction
      final imageBytes = _getRawImageBytes(cameraImage);
      final imageWidth = cameraImage.width;
      final imageHeight = cameraImage.height;

      // Process each detected object
      final results = <HybridDetectionResult>[];
      
      // Minimum size thresholds (as percentage of image)
      const minWidthPercent = 0.08;  // At least 8% of image width
      const minHeightPercent = 0.08; // At least 8% of image height
      const maxWidthPercent = 0.95;  // Not more than 95% (likely full frame)
      const maxHeightPercent = 0.95;
      
      for (final object in objects) {
        final boundingBox = object.boundingBox;
        
        // Calculate relative size
        final relativeWidth = boundingBox.width / imageWidth;
        final relativeHeight = boundingBox.height / imageHeight;
        
        // Filter out boxes that are too small (noise) or too large (background)
        if (relativeWidth < minWidthPercent || relativeHeight < minHeightPercent) {
          debugPrint('  Skipped: too small (${(relativeWidth * 100).toStringAsFixed(1)}% x ${(relativeHeight * 100).toStringAsFixed(1)}%)');
          continue;
        }
        if (relativeWidth > maxWidthPercent || relativeHeight > maxHeightPercent) {
          debugPrint('  Skipped: too large (likely background)');
          continue;
        }
        
        // Filter out boxes at the very edge (often partial objects)
        if (boundingBox.left < 5 || boundingBox.top < 5 ||
            boundingBox.right > imageWidth - 5 || boundingBox.bottom > imageHeight - 5) {
          // Only skip if it's touching multiple edges (likely noise)
          int edgeCount = 0;
          if (boundingBox.left < 5) edgeCount++;
          if (boundingBox.top < 5) edgeCount++;
          if (boundingBox.right > imageWidth - 5) edgeCount++;
          if (boundingBox.bottom > imageHeight - 5) edgeCount++;
          if (edgeCount >= 2) {
            debugPrint('  Skipped: touching multiple edges');
            continue;
          }
        }
        
        // Get label (use 'Nesne' if no labels - we don't rely on labels for matching anymore)
        String labelText = 'Nesne';
        double labelConfidence = 1.0;
        
        if (object.labels.isNotEmpty) {
          final topLabel = object.labels.first;
          if (topLabel.confidence < confidenceThreshold) continue;
          labelText = topLabel.text;
          labelConfidence = topLabel.confidence;
        }

        // Calculate aspect ratio
        final aspectRatioValue = boundingBox.height / boundingBox.width;
        final aspectRatio = ColorUtils.getCategoricalAspectRatio(aspectRatioValue);

        // Extract dominant color from center of bounding box
        final colorResult = _extractDominantColor(
          imageBytes,
          imageWidth,
          imageHeight,
          boundingBox,
          cameraImage.format.group,
        );

        final dominantColor = colorResult['color'] as ui.Color;
        final colorHSV = colorResult['hsv'] as List<double>;
        final colorName = ColorUtils.getColorName(colorHSV);

        // ML Kit returns bounding boxes in RAW buffer space (imageWidth x imageHeight)
        // The rotation metadata helps detection accuracy but doesn't rotate output coordinates
        // We normalize to 0..1 using raw buffer dimensions
        final normalizedBox = ui.Rect.fromLTRB(
          boundingBox.left / imageWidth,
          boundingBox.top / imageHeight,
          boundingBox.right / imageWidth,
          boundingBox.bottom / imageHeight,
        );
        
        // SEMANTIC FINGERPRINTING
        Map<String, double> semanticTags = {};
        if (_imageLabeler != null) {
           semanticTags = await _extractSemanticTags(cameraImage, boundingBox, rotation);
           if (semanticTags.isNotEmpty) {
             debugPrint('  Extracted Tags for ${object.trackingId}: ${semanticTags.keys.take(3).join(", ")}');
           }
        }

        // TEXT RECOGNITION (OCR)
        String detectedText = '';
        if (_textRecognizer != null) {
           detectedText = await _extractText(cameraImage, boundingBox, rotation);
           if (detectedText.isNotEmpty) {
             debugPrint('  Extracted Text for ${object.trackingId}: "${detectedText.replaceAll('\n', ' ')}"');
           }
        }
        
        debugPrint('Box Normalized (${imageWidth}x$imageHeight): left=${normalizedBox.left.toStringAsFixed(2)}, top=${normalizedBox.top.toStringAsFixed(2)}, w=${normalizedBox.width.toStringAsFixed(2)}, h=${normalizedBox.height.toStringAsFixed(2)}');

        // Create detection result
        var result = HybridDetectionResult(
          label: labelText,
          aspectRatio: aspectRatio,
          aspectRatioValue: aspectRatioValue,
          dominantColor: dominantColor,
          colorName: colorName,
          colorHSV: colorHSV,
          confidence: labelConfidence,
          boundingBox: boundingBox,
          normalizedBox: normalizedBox,
          trackingId: object.trackingId ?? results.length,
          visualTags: semanticTags,
          detectedText: detectedText,
        );

        // Try to find a matching saved signature
        final matchedSignature = _storageService.findBestMatch(
          result,
          ratioTolerance: ratioTolerance,
          hueTolerance: hueTolerance,
        );

        if (matchedSignature != null) {
          // Update with matched product info
          result = HybridDetectionResult(
            detectedProductName: matchedSignature.displayName,
            label: result.label,
            aspectRatio: result.aspectRatio,
            aspectRatioValue: result.aspectRatioValue,
            dominantColor: result.dominantColor,
            colorName: result.colorName,
            colorHSV: result.colorHSV,
            confidence: matchedSignature.matchScore(result.toSignature(
              id: 'temp',
              userGivenName: '',
            )),
            matchedSignature: matchedSignature,
            boundingBox: result.boundingBox,
            normalizedBox: result.normalizedBox,
            trackingId: result.trackingId,
          );
          
          // Record detection hit
          _storageService.recordDetectionHit(matchedSignature.id);
        }

        results.add(result);
      }

      // Apply Non-Maximum Suppression to remove overlapping boxes
      final nmsResults = _applyNMS(results, iouThreshold: 0.4);
      
      debugPrint('ProductRecognitionService: After NMS: ${nmsResults.length} objects (was ${results.length})');

      return nmsResults.isEmpty ? null : nmsResults;
    } catch (e) {
      debugPrint('ProductRecognitionService: Error processing frame: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }
  
  /// Apply Non-Maximum Suppression to remove overlapping detections
  List<HybridDetectionResult> _applyNMS(
    List<HybridDetectionResult> detections, {
    double iouThreshold = 0.4,
  }) {
    if (detections.isEmpty) return detections;
    
    // Sort by confidence (higher first)
    final sorted = List<HybridDetectionResult>.from(detections)
      ..sort((a, b) => b.confidence.compareTo(a.confidence));
    
    final kept = <HybridDetectionResult>[];
    final suppressed = <int>{};
    
    for (int i = 0; i < sorted.length; i++) {
      if (suppressed.contains(i)) continue;
      
      kept.add(sorted[i]);
      final boxA = sorted[i].normalizedBox!;
      
      for (int j = i + 1; j < sorted.length; j++) {
        if (suppressed.contains(j)) continue;
        
        final boxB = sorted[j].normalizedBox!;
        final iou = _calculateIoU(boxA, boxB);
        
        if (iou > iouThreshold) {
          suppressed.add(j);
        }
      }
    }
    
    return kept;
  }
  
  /// Calculate Intersection over Union between two rectangles
  double _calculateIoU(ui.Rect a, ui.Rect b) {
    final intersectionLeft = a.left > b.left ? a.left : b.left;
    final intersectionTop = a.top > b.top ? a.top : b.top;
    final intersectionRight = a.right < b.right ? a.right : b.right;
    final intersectionBottom = a.bottom < b.bottom ? a.bottom : b.bottom;
    
    if (intersectionRight <= intersectionLeft || intersectionBottom <= intersectionTop) {
      return 0.0;
    }
    
    final intersectionArea = (intersectionRight - intersectionLeft) * (intersectionBottom - intersectionTop);
    final areaA = a.width * a.height;
    final areaB = b.width * b.height;
    final unionArea = areaA + areaB - intersectionArea;
    
    return unionArea > 0 ? intersectionArea / unionArea : 0.0;
  }

  /// Process an InputImage directly (for already converted images)
  Future<List<HybridDetectionResult>?> processInputImage(
    InputImage inputImage,
    Uint8List? rawImageBytes,
    int imageWidth,
    int imageHeight,
  ) async {
    // Throttle check
    final now = DateTime.now();
    if (_lastProcessTime != null &&
        now.difference(_lastProcessTime!) < _throttleDuration) {
      return null;
    }
    
    if (_isProcessing) return null;
    _isProcessing = true;
    _lastProcessTime = now;

    try {
      final objects = await _objectDetector?.processImage(inputImage);
      if (objects == null || objects.isEmpty) {
        return null;
      }

      final results = <HybridDetectionResult>[];
      
      for (final object in objects) {
        if (object.labels.isEmpty) continue;
        
        final topLabel = object.labels.first;
        if (topLabel.confidence < confidenceThreshold) continue;

        final boundingBox = object.boundingBox;
        final aspectRatioValue = boundingBox.height / boundingBox.width;
        final aspectRatio = ColorUtils.getCategoricalAspectRatio(aspectRatioValue);

        // Extract color if we have raw bytes
        ui.Color dominantColor = const ui.Color(0xFF808080); // Default gray
        List<double> colorHSV = [0, 0, 0.5];
        String colorName = 'gray';

        if (rawImageBytes != null) {
          final colorResult = _extractDominantColorFromRGBA(
            rawImageBytes,
            imageWidth,
            imageHeight,
            boundingBox,
          );
          dominantColor = colorResult['color'] as ui.Color;
          colorHSV = colorResult['hsv'] as List<double>;
          colorName = ColorUtils.getColorName(colorHSV);
        }

        final normalizedBox = ui.Rect.fromLTRB(
          boundingBox.left / imageWidth,
          boundingBox.top / imageHeight,
          boundingBox.right / imageWidth,
          boundingBox.bottom / imageHeight,
        );

        var result = HybridDetectionResult(
          label: topLabel.text,
          aspectRatio: aspectRatio,
          aspectRatioValue: aspectRatioValue,
          dominantColor: dominantColor,
          colorName: colorName,
          colorHSV: colorHSV,
          confidence: topLabel.confidence,
          boundingBox: boundingBox,
          normalizedBox: normalizedBox,
          trackingId: object.trackingId ?? results.length,
        );

        // Try to find a matching signature
        final matchedSignature = _storageService.findBestMatch(
          result,
          ratioTolerance: ratioTolerance,
          hueTolerance: hueTolerance,
        );

        if (matchedSignature != null) {
          result = HybridDetectionResult(
            detectedProductName: matchedSignature.displayName,
            label: result.label,
            aspectRatio: result.aspectRatio,
            aspectRatioValue: result.aspectRatioValue,
            dominantColor: result.dominantColor,
            colorName: result.colorName,
            colorHSV: result.colorHSV,
            confidence: matchedSignature.matchScore(result.toSignature(
              id: 'temp',
              userGivenName: '',
            )),
            matchedSignature: matchedSignature,
            boundingBox: result.boundingBox,
            normalizedBox: result.normalizedBox,
            trackingId: result.trackingId,
          );
          
          _storageService.recordDetectionHit(matchedSignature.id);
        }

        results.add(result);
      }

      return results.isEmpty ? null : results;
    } catch (e) {
      debugPrint('ProductRecognitionService: Error processing input image: $e');
      return null;
    } finally {
      _isProcessing = false;
    }
  }

  /// Teach the service a new product by saving its signature
  Future<ProductSignature> teachProduct(
    HybridDetectionResult detection,
    String userGivenName, {
    String? barcode,
  }) async {
    final id = _storageService.generateId();
    
    final signature = detection.toSignature(
      id: id,
      userGivenName: userGivenName,
      barcode: barcode,
    );
    
    // Auto-populate text keywords from detected text if available
    if (detection.detectedText.isNotEmpty) {
      // Split by spaces, remove short words
      final words = detection.detectedText
          .split(RegExp(r'\s+'))
          .where((w) => w.length > 3)
          .map((w) => w.toLowerCase())
          .toSet() // Removes duplicates
          .toList();
          
      if (words.isNotEmpty) {
        final updatedSignature = signature.copyWith(
          textKeywords: words,
        );
        debugPrint('ProductRecognitionService: Added text keywords: $words');
        await _storageService.saveSignature(updatedSignature);
        debugPrint('ProductRecognitionService: Taught new product "$userGivenName"');
        return updatedSignature;
      }
    }

    await _storageService.saveSignature(signature);
    
    debugPrint('ProductRecognitionService: Taught new product "$userGivenName"');
    return signature;
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

  /// Convert CameraImage to InputImage
  InputImage? _convertCameraImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final format = _getInputImageFormat(image.format.group);
      if (format == null) return null;

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: ui.Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: format,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('ProductRecognitionService: Error converting camera image: $e');
      return null;
    }
  }

  /// Get raw image bytes from CameraImage
  Uint8List _getRawImageBytes(CameraImage image) {
    final WriteBuffer allBytes = WriteBuffer();
    for (final plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    return allBytes.done().buffer.asUint8List();
  }

  /// Extract dominant color from a region of the image
  Map<String, dynamic> _extractDominantColor(
    Uint8List imageBytes,
    int imageWidth,
    int imageHeight,
    ui.Rect boundingBox,
    ImageFormatGroup formatGroup,
  ) {
    try {
      // Sample from center 50% of bounding box for more accurate color
      final centerX = boundingBox.center.dx.toInt();
      final centerY = boundingBox.center.dy.toInt();
      final sampleWidth = (boundingBox.width * 0.5).toInt();
      final sampleHeight = (boundingBox.height * 0.5).toInt();

      final startX = (centerX - sampleWidth ~/ 2).clamp(0, imageWidth - 1);
      final startY = (centerY - sampleHeight ~/ 2).clamp(0, imageHeight - 1);
      final endX = (centerX + sampleWidth ~/ 2).clamp(0, imageWidth - 1);
      final endY = (centerY + sampleHeight ~/ 2).clamp(0, imageHeight - 1);

      int totalR = 0, totalG = 0, totalB = 0;
      int sampleCount = 0;

      // Handle different image formats
      if (formatGroup == ImageFormatGroup.bgra8888) {
        // BGRA format (iOS)
        for (int y = startY; y < endY; y += 2) {
          for (int x = startX; x < endX; x += 2) {
            final index = (y * imageWidth + x) * 4;
            if (index + 3 < imageBytes.length) {
              totalB += imageBytes[index];
              totalG += imageBytes[index + 1];
              totalR += imageBytes[index + 2];
              sampleCount++;
            }
          }
        }
      } else if (formatGroup == ImageFormatGroup.yuv420) {
        // YUV420 format (Android) - approximate using Y channel only
        // For a more accurate result, we'd need to convert YUV to RGB
        for (int y = startY; y < endY; y += 2) {
          for (int x = startX; x < endX; x += 2) {
            final index = y * imageWidth + x;
            if (index < imageBytes.length) {
              final yValue = imageBytes[index];
              totalR += yValue;
              totalG += yValue;
              totalB += yValue;
              sampleCount++;
            }
          }
        }
      } else {
        // Fallback: assume RGBA
        for (int y = startY; y < endY; y += 2) {
          for (int x = startX; x < endX; x += 2) {
            final index = (y * imageWidth + x) * 4;
            if (index + 3 < imageBytes.length) {
              totalR += imageBytes[index];
              totalG += imageBytes[index + 1];
              totalB += imageBytes[index + 2];
              sampleCount++;
            }
          }
        }
      }

      if (sampleCount == 0) {
        return {
          'color': const ui.Color(0xFF808080),
          'hsv': [0.0, 0.0, 0.5],
        };
      }

      final avgR = totalR ~/ sampleCount;
      final avgG = totalG ~/ sampleCount;
      final avgB = totalB ~/ sampleCount;

      final color = ui.Color.fromARGB(255, avgR, avgG, avgB);
      final hsv = ColorUtils.rgbToHsv(color);

      return {
        'color': color,
        'hsv': hsv,
      };
    } catch (e) {
      debugPrint('ProductRecognitionService: Error extracting color: $e');
      return {
        'color': const ui.Color(0xFF808080),
        'hsv': [0.0, 0.0, 0.5],
      };
    }
  }

  /// Extract dominant color from RGBA image bytes
  Map<String, dynamic> _extractDominantColorFromRGBA(
    Uint8List imageBytes,
    int imageWidth,
    int imageHeight,
    ui.Rect boundingBox,
  ) {
    try {
      final centerX = boundingBox.center.dx.toInt();
      final centerY = boundingBox.center.dy.toInt();
      final sampleWidth = (boundingBox.width * 0.5).toInt();
      final sampleHeight = (boundingBox.height * 0.5).toInt();

      final startX = (centerX - sampleWidth ~/ 2).clamp(0, imageWidth - 1);
      final startY = (centerY - sampleHeight ~/ 2).clamp(0, imageHeight - 1);
      final endX = (centerX + sampleWidth ~/ 2).clamp(0, imageWidth - 1);
      final endY = (centerY + sampleHeight ~/ 2).clamp(0, imageHeight - 1);

      int totalR = 0, totalG = 0, totalB = 0;
      int sampleCount = 0;

      for (int y = startY; y < endY; y += 2) {
        for (int x = startX; x < endX; x += 2) {
          final index = (y * imageWidth + x) * 4;
          if (index + 3 < imageBytes.length) {
            totalR += imageBytes[index];
            totalG += imageBytes[index + 1];
            totalB += imageBytes[index + 2];
            sampleCount++;
          }
        }
      }

      if (sampleCount == 0) {
        return {
          'color': const ui.Color(0xFF808080),
          'hsv': [0.0, 0.0, 0.5],
        };
      }

      final avgR = totalR ~/ sampleCount;
      final avgG = totalG ~/ sampleCount;
      final avgB = totalB ~/ sampleCount;

      final color = ui.Color.fromARGB(255, avgR, avgG, avgB);
      final hsv = ColorUtils.rgbToHsv(color);

      return {
        'color': color,
        'hsv': hsv,
      };
    } catch (e) {
      return {
        'color': const ui.Color(0xFF808080),
        'hsv': [0.0, 0.0, 0.5],
      };
    }
  }

  /// Get InputImageFormat from ImageFormatGroup
  InputImageFormat? _getInputImageFormat(ImageFormatGroup group) {
    switch (group) {
      case ImageFormatGroup.nv21:
        return InputImageFormat.nv21;
      case ImageFormatGroup.yuv420:
        return InputImageFormat.yuv420;
      case ImageFormatGroup.bgra8888:
        return InputImageFormat.bgra8888;
      default:
        return null;
    }
  }

  /// Reset throttling (useful when resuming from pause)
  void resetThrottling() {
    _lastProcessTime = null;
  }

  /// Check if service is initialized
  bool get isInitialized => _initialized;

  /// Dispose resources
  Future<void> dispose() async {
    _objectDetector?.close();
    _objectDetector = null;
    _textRecognizer?.close();
    _textRecognizer = null;
    _initialized = false;
  }
  /// Extract semantic tags from a detected object region
  Future<Map<String, double>> _extractSemanticTags(
      CameraImage cameraImage, ui.Rect box, InputImageRotation rotation) async {
    if (_imageLabeler == null) return {};

    try {
      // ... (rest of logic same until saving tags) ...
      
      // Convert full frame to RGB Image
      final fullImage = _convertCameraImageToImage(cameraImage);
      if (fullImage == null) return {};

      // Handle rotation if needed (CameraImage is usually landscape)
      img.Image processedImage = fullImage;
      if (rotation == InputImageRotation.rotation90deg) {
        processedImage = img.copyRotate(fullImage, angle: 90);
      } else if (rotation == InputImageRotation.rotation270deg) {
        processedImage = img.copyRotate(fullImage, angle: 270);
      }
      
      // Safety: Clamp box to image bounds
      final cropX = box.left.toInt().clamp(0, processedImage.width - 1);
      final cropY = box.top.toInt().clamp(0, processedImage.height - 1);
      final cropW = box.width.toInt().clamp(1, processedImage.width - cropX);
      final cropH = box.height.toInt().clamp(1, processedImage.height - cropY);
      
      final cropped = img.copyCrop(processedImage, x: cropX, y: cropY, width: cropW, height: cropH);
      
      // Save to temp file
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/temp_crop_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final file = File(path);
      await file.writeAsBytes(img.encodeJpg(cropped, quality: 80));
      
      // Process with Image Labeler
      final inputImage = InputImage.fromFilePath(path);
      final labels = await _imageLabeler!.processImage(inputImage);
      
      if (labels.isEmpty) {
        debugPrint('[Debug] ImageLabeler returned 0 labels');
      } else {
        debugPrint('[Debug] ImageLabeler found: ${labels.take(3).map((l) => "${l.label}:${l.confidence.toStringAsFixed(2)}").join(", ")}');
      }

      // Cleanup
      await file.delete();
      
      // Convert to Map
      final Map<String, double> tags = {};
      for (final l in labels) {
         tags[l.label] = l.confidence; // Use .label instead of .text
      }
      return tags;
    } catch (e) {
      debugPrint('ProductRecognitionService: Error extracting semantics: $e');
      return {};
    }
  }

  // Extract text from object region
  Future<String> _extractText(
      CameraImage cameraImage, ui.Rect box, InputImageRotation rotation) async {
    if (_textRecognizer == null) return '';

    try {
      // Use existing crop logic
      final fullImage = _convertCameraImageToImage(cameraImage);
      if (fullImage == null) return '';

      img.Image processedImage = fullImage;
      if (rotation == InputImageRotation.rotation90deg) {
        processedImage = img.copyRotate(fullImage, angle: 90);
      } else if (rotation == InputImageRotation.rotation270deg) {
        processedImage = img.copyRotate(fullImage, angle: 270);
      }
      
      final cropX = box.left.toInt().clamp(0, processedImage.width - 1);
      final cropY = box.top.toInt().clamp(0, processedImage.height - 1);
      final cropW = box.width.toInt().clamp(1, processedImage.width - cropX);
      final cropH = box.height.toInt().clamp(1, processedImage.height - cropY);
      
      final cropped = img.copyCrop(processedImage, x: cropX, y: cropY, width: cropW, height: cropH);
      
      final tempDir = await getTemporaryDirectory();
      final path = '${tempDir.path}/temp_ocr_${DateTime.now().microsecondsSinceEpoch}.jpg';
      final file = File(path);
      await file.writeAsBytes(img.encodeJpg(cropped, quality: 80));
      
      final inputImage = InputImage.fromFilePath(path);
      final recognizedText = await _textRecognizer!.processImage(inputImage);
      
      await file.delete();
      
      if (recognizedText.text.isEmpty) return '';
      
      // Filter out garbage / very short text
      final cleanText = recognizedText.text.trim();
      if (cleanText.length < 2) return '';
      
      return cleanText;
    } catch (e) {
      debugPrint('ProductRecognitionService: Error extracting text: $e');
      return '';
    }
  }

  /// Convert CameraImage (YUV420/BGRA) to img.Image (RGB)
  img.Image? _convertCameraImageToImage(CameraImage image) {
    try {
      final width = image.width;
      final height = image.height;
      
      // Check format
      if (image.format.group == ImageFormatGroup.yuv420) {
        final uvRowStride = image.planes[1].bytesPerRow;
        final uvPixelStride = image.planes[1].bytesPerPixel ?? 1;
        
        final imgBuffer = img.Image(width: width, height: height);
        
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                final uvIndex = uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
                final index = y * width + x;
                
                final yp = image.planes[0].bytes[index];
                final up = image.planes[1].bytes[uvIndex];
                final vp = image.planes[2].bytes[uvIndex];
                
                int r = (yp + vp * 1436 / 1024 - 179).round().clamp(0, 255);
                int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91).round().clamp(0, 255);
                int b = (yp + up * 1814 / 1024 - 227).round().clamp(0, 255);
                
                imgBuffer.setPixelRgb(x, y, r, g, b);
            }
        }
        return imgBuffer;
      } else if (image.format.group == ImageFormatGroup.bgra8888) {
        // iOS
        final imgBuffer = img.Image(width: width, height: height);
        final planes = image.planes;
        final bytes = planes[0].bytes;
        
        for (int i = 0; i < width * height; i++) {
            // BGRA -> RGBA? or just RGB
            // bytes usually: B, G, R, A
            int b = bytes[i * 4];
            int g = bytes[i * 4 + 1];
            int r = bytes[i * 4 + 2];
            int a = bytes[i * 4 + 3];
            
            imgBuffer.setPixelRgb(i % width, i ~/ width, r, g, b);
        }
        return imgBuffer;
      }
      return null;
    } catch (e) {
      debugPrint('Error converting camera image: $e');
      return null;
    }
  }
}
