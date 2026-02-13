import 'dart:ui';
import 'dart:ui' show Rect;
import 'dart:math' as math;

/// Represents a product's unique visual signature for Smart Vision detection
/// Combines: Object Type (ML Kit) + Aspect Ratio + Dominant HSV Color
/// Can be linked to barcode and expiry date for full product recognition
class ProductSignature {
  final String id; // Unique ID (e.g., "sig_001")
  final String? barcode; // Linked barcode (optional)
  final String? firebaseProductId; // Link to Firebase product record
  final String productName; // e.g., "Ketchup"
  final String? userGivenName; // User's custom name (e.g., "Erikli Su")
  final String label; // ML Kit output, e.g., "Bottle" (formerly yoloLabel)
  final String aspectRatio; // "tall", "wide", "square" (categorical)
  final double aspectRatioValue; // Numeric Height/Width ratio (e.g., 2.5)
  final Color dominantColor; // RGB color
  final String colorName; // Human readable, e.g., "red", "blue"
  final List<double> colorHSV; // [Hue (0-360), Saturation (0-1), Value (0-1)]
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final int detectionCount; // How many times this signature was used
  final DateTime? expiryDate; // Linked expiry date (optional)
  final int sampleCount; // Number of training samples used
  final Map<String, double> visualTags; // Semantic labels from Image Labeling (e.g. {"Bottle": 0.9})
  final List<String> requiredTags; // Tags that MUST be present (AND condition)
  final List<String> excludedTags; // Tags that must NOT be present (NOT condition)
  final List<String> textKeywords; // Specific words to look for via OCR (e.g. "Coca-Cola")
  final String detectedText; // Text detected during this specific observation (transient)

  ProductSignature({
    required this.id,
    this.barcode,
    this.firebaseProductId,
    required this.productName,
    this.userGivenName,
    required this.label,
    required this.aspectRatio,
    this.aspectRatioValue = 1.0,
    required this.dominantColor,
    required this.colorName,
    this.colorHSV = const [0.0, 0.0, 0.0],
    DateTime? createdAt,
    this.lastUsedAt,
    this.detectionCount = 0,
    this.expiryDate,
    this.sampleCount = 1,
    this.visualTags = const {},
    this.requiredTags = const [],

    this.excludedTags = const [],
    this.textKeywords = const [],
    this.detectedText = '',
  }) : createdAt = createdAt ?? DateTime.now();

  /// Legacy getter for backward compatibility
  String get yoloLabel => label;

  /// Get the display name (userGivenName if available, otherwise productName)
  String get displayName => userGivenName ?? productName;

  /// Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'barcode': barcode,
      'firebaseProductId': firebaseProductId,
      'productName': productName,
      'userGivenName': userGivenName,
      'label': label,
      'yoloLabel': label, // Backward compatibility
      'aspectRatio': aspectRatio,
      'aspectRatioValue': aspectRatioValue,
      'dominantColor': dominantColor.value, // Store as int
      'colorName': colorName,
      'colorHSV': colorHSV,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
      'detectionCount': detectionCount,
      'expiryDate': expiryDate?.toIso8601String(),
      'sampleCount': sampleCount,
      'visualTags': visualTags,
      'requiredTags': requiredTags,

      'excludedTags': excludedTags,
      'textKeywords': textKeywords,
      'detectedText': detectedText,
    };
  }

  /// Create from JSON
  factory ProductSignature.fromJson(Map<String, dynamic> json) {
    // Handle colorHSV which might be stored as List<dynamic>
    List<double> hsv = const [0.0, 0.0, 0.0];
    if (json['colorHSV'] != null) {
      final rawHsv = json['colorHSV'] as List;
      hsv = rawHsv.map((e) => (e as num).toDouble()).toList();
    }
    
    // Handle visual tags
    Map<String, double> tags = {};
    if (json['visualTags'] != null) {
      final rawTags = json['visualTags'] as Map<String, dynamic>;
      rawTags.forEach((key, value) {
        tags[key] = (value as num).toDouble();
      });
    }

    return ProductSignature(
      id: json['id'] as String,
      barcode: json['barcode'] as String?,
      firebaseProductId: json['firebaseProductId'] as String?,
      productName: json['productName'] as String,
      userGivenName: json['userGivenName'] as String?,
      label: json['label'] as String? ?? json['yoloLabel'] as String,
      aspectRatio: json['aspectRatio'] as String,
      aspectRatioValue: (json['aspectRatioValue'] as num?)?.toDouble() ?? 1.0,
      dominantColor: Color(json['dominantColor'] as int),
      colorName: json['colorName'] as String,
      colorHSV: hsv,
      createdAt: DateTime.parse(json['createdAt'] as String),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.parse(json['lastUsedAt'] as String)
          : null,
      detectionCount: json['detectionCount'] as int? ?? 0,
      expiryDate: json['expiryDate'] != null
          ? DateTime.parse(json['expiryDate'] as String)
          : null,
      sampleCount: json['sampleCount'] as int? ?? 1,
      visualTags: tags,
      requiredTags: (json['requiredTags'] as List<dynamic>?)?.cast<String>() ?? [],

      excludedTags: (json['excludedTags'] as List<dynamic>?)?.cast<String>() ?? [],
      textKeywords: (json['textKeywords'] as List<dynamic>?)?.cast<String>() ?? [],
      detectedText: json['detectedText'] as String? ?? '',
    );
  }

  /// Create a copy with updated fields
  ProductSignature copyWith({
    String? id,
    String? barcode,
    String? firebaseProductId,
    String? productName,
    String? userGivenName,
    String? label,
    String? aspectRatio,
    double? aspectRatioValue,
    Color? dominantColor,
    String? colorName,
    List<double>? colorHSV,
    DateTime? createdAt,
    DateTime? lastUsedAt,
    int? detectionCount,
    DateTime? expiryDate,
    int? sampleCount,
    Map<String, double>? visualTags,
    List<String>? requiredTags,

    List<String>? excludedTags,
    List<String>? textKeywords,
    String? detectedText,
  }) {
    return ProductSignature(
      id: id ?? this.id,
      barcode: barcode ?? this.barcode,
      firebaseProductId: firebaseProductId ?? this.firebaseProductId,
      productName: productName ?? this.productName,
      userGivenName: userGivenName ?? this.userGivenName,
      label: label ?? this.label,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      aspectRatioValue: aspectRatioValue ?? this.aspectRatioValue,
      dominantColor: dominantColor ?? this.dominantColor,
      colorName: colorName ?? this.colorName,
      colorHSV: colorHSV ?? this.colorHSV,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
      detectionCount: detectionCount ?? this.detectionCount,
      expiryDate: expiryDate ?? this.expiryDate,
      sampleCount: sampleCount ?? this.sampleCount,
      visualTags: visualTags ?? this.visualTags,
      requiredTags: requiredTags ?? this.requiredTags,

      excludedTags: excludedTags ?? this.excludedTags,
      textKeywords: textKeywords ?? this.textKeywords,
      detectedText: detectedText ?? this.detectedText,
    );
  }

  /// Check if this signature matches another within given tolerances
  /// Uses HSV color space for more perceptually uniform matching
  bool matchesWithTolerance(
    ProductSignature other, {
    double ratioTolerance = 0.15, // Stricter tolerance (was 0.2)
    double hueTolerance = 20.0,
    double saturationTolerance = 0.3,
    double valueTolerance = 0.3,
  }) {
    // --- CLASS TAG FILTER (AND/NOT conditions) ---
    // Check if the detected object (other) meets our required/excluded tag criteria
    
    // Required Tags (AND): ALL must be present in the detected object's visualTags
    if (requiredTags.isNotEmpty && other.visualTags.isNotEmpty) {
      for (final reqTag in requiredTags) {
        // Check if any visualTag key contains this required tag (case-insensitive)
        bool found = other.visualTags.keys.any(
          (key) => key.toLowerCase().contains(reqTag.toLowerCase()),
        );
        if (!found) {
          // Required tag not found - no match
          return false;
        }
      }
    }
    
    // Excluded Tags (NOT): NONE should be present in the detected object's visualTags
    if (excludedTags.isNotEmpty && other.visualTags.isNotEmpty) {
      for (final exclTag in excludedTags) {
        // Check if any visualTag key contains this excluded tag (case-insensitive)
        bool found = other.visualTags.keys.any(
          (key) => key.toLowerCase().contains(exclTag.toLowerCase()),
        );
        if (found) {
          // Excluded tag found - no match
          return false;
        }
      }
    }

    // --- TEXT KEYWORD MATCH ---
    // If text keywords are defined, we check if they appear in the detected text
    if (textKeywords.isNotEmpty && other.detectedText.isNotEmpty) {
      bool foundAny = textKeywords.any((k) => 
        other.detectedText.toLowerCase().contains(k.toLowerCase())
      );
      // If we have keywords but none are found in the text, fail.
      if (!foundAny) return false;
    }
    
    // NOTE: Label matching removed - we use color + aspect ratio + text for identification
    // Labels (like "Food", "Home good") are too generic to be useful

    // Check aspect ratio within tolerance
    if ((aspectRatioValue - other.aspectRatioValue).abs() > ratioTolerance) {
      return false;
    }

    // ACHROMATIC LOGIC (White/Black/Gray handling)
    // If ANY signature is low saturation (achromatic), use special logic
    bool thisIsAchromatic = colorHSV[1] < 0.15;
    bool otherIsAchromatic = other.colorHSV[1] < 0.15;

    if (thisIsAchromatic || otherIsAchromatic) {
      // If one is colored and other is grayscale, they DON'T match
      if (thisIsAchromatic != otherIsAchromatic) return false;
      
      // Both are achromatic (white/gray/black)
      // IGNORE HUE completely (hue is unstable at low saturation)
      
      // Strict Saturation check (ensure both stick to grayscale)
      if ((colorHSV[1] - other.colorHSV[1]).abs() > 0.15) return false;

      // Value (brightness) check - distinguishes White vs Gray vs Black
      if ((colorHSV[2] - other.colorHSV[2]).abs() > valueTolerance) return false;
      
      return true;
    }

    // CHROMATIC LOGIC (Normal colored objects)
    
    // Check HSV color within tolerance
    // Hue is circular (0-360), so we need special handling
    double hueDiff = (colorHSV[0] - other.colorHSV[0]).abs();
    if (hueDiff > 180) hueDiff = 360 - hueDiff; // Handle wrap-around
    if (hueDiff > hueTolerance) {
      return false;
    }

    // Saturation check
    if ((colorHSV[1] - other.colorHSV[1]).abs() > saturationTolerance) {
      return false;
    }

    // Value (brightness) check
    if ((colorHSV[2] - other.colorHSV[2]).abs() > valueTolerance) {
      return false;
    }
    
    // Semantic Tag Check (If available)
    if (visualTags.isNotEmpty && other.visualTags.isNotEmpty) {
       double overlap = _calculateTagOverlap(visualTags, other.visualTags);
       // If overlap is extremely low (< 0.1), considering them 'different objects'
       if (overlap < 0.1) return false;
    }

    return true;
  }

  /// Calculate a match score (0.0 to 1.0) against another signature
  /// Higher score = better match
  double matchScore(ProductSignature other) {
    // --- PRE-CHECKS (AND/NOT conditions) ---
    // If tag conditions are not met, return 0 score
    if (requiredTags.isNotEmpty && other.visualTags.isNotEmpty) {
      for (final reqTag in requiredTags) {
        bool found = other.visualTags.keys.any(
          (key) => key.toLowerCase().contains(reqTag.toLowerCase()),
        );
        if (!found) return 0.0; // Required tag missing
      }
    }
    if (excludedTags.isNotEmpty && other.visualTags.isNotEmpty) {
      for (final exclTag in excludedTags) {
        bool found = other.visualTags.keys.any(
          (key) => key.toLowerCase().contains(exclTag.toLowerCase()),
        );
        if (found) return 0.0; // Excluded tag present
      }
    }
    
    // NOTE: Label matching removed - we rely on color + aspect ratio + text for identification
    // Labels from ML Kit are too generic (Food, Home Good, etc.)

    // --- 1. TEXT MATCH SCORE (The "Gold Standard") ---
    double textScore = 0.0;
    if (textKeywords.isNotEmpty && other.detectedText.isNotEmpty) {
       int hitCount = 0;
       final otherTextLower = other.detectedText.toLowerCase();
       // Check each keyword
       for (final keyword in textKeywords) {
         if (keyword.length < 3) continue; // Skip tiny keywords
         if (otherTextLower.contains(keyword.toLowerCase())) {
           hitCount++;
         }
       }
       // If we match significant keywords, this provides a massive signal
       if (hitCount > 0) {
         // Calculate percentage of keywords matched
         // e.g. "Coca Cola Zero" -> match "Coca", "Cola" = 2/3 = 0.66
         textScore = hitCount / textKeywords.where((k) => k.length >= 3).length;
         if (textScore > 1.0) textScore = 1.0;
       }
    } else if (textKeywords.isNotEmpty && other.detectedText.isEmpty) {
      // Expected text but saw none? Neutral, don't punish too hard yet (lighting/blur)
      textScore = 0.0;
    }

    // --- 2. SEMANTIC SCORE (Visual Tags) ---
    double semanticScore = 0.0;
    if (visualTags.isNotEmpty && other.visualTags.isNotEmpty) {
      semanticScore = _calculateTagOverlap(visualTags, other.visualTags);
    }
    
    // --- 3. PHYSICAL SCORE (Color + Ratio) ---
    // Aspect Ratio Score
    double ratioDiff = (aspectRatioValue - other.aspectRatioValue).abs();
    double ratioScore = math.max(0, 1.0 - (ratioDiff / 0.5));

    // Color Score
    bool isAchromatic = colorHSV[1] < 0.15 && other.colorHSV[1] < 0.15;
    double colorScore;
    if (isAchromatic) {
       // Black/White/Gray - rely on Value (Brightness)
       double valDiff = (colorHSV[2] - other.colorHSV[2]).abs();
       colorScore = math.max(0, 1.0 - (valDiff / 0.5));
    } else {
       // Chromatic - rely on Hue and Saturation
       double hueDiff = (colorHSV[0] - other.colorHSV[0]).abs();
       if (hueDiff > 180) hueDiff = 360 - hueDiff;
       double hueScore = math.max(0, 1.0 - (hueDiff / 60)); // 60 deg tolerance slope
       
       double satDiff = (colorHSV[1] - other.colorHSV[1]).abs();
       double satScore = math.max(0, 1.0 - (satDiff / 0.5));
       
       colorScore = (hueScore * 0.7) + (satScore * 0.3);
    }
    
    double physicalScore = (ratioScore * 0.4) + (colorScore * 0.6);

    // --- FINAL WEIGHTED FUSION ---
    double finalScore;
    
    // CASE A: Strong Text Match (Highly Reliable)
    // If we matched >50% of keywords, we trust this almost implicitly
    if (textScore >= 0.5) {
      // Formula: Text (70%) + Physical (30%)
      // We allow physical mismatch (lighting/angle) if text is verified
      finalScore = (textScore * 0.7) + (physicalScore * 0.3);
      
      // Boost confidence slightly as text is definitive
      finalScore = math.min(1.0, finalScore * 1.2);
    } 
    // CASE B: Strong Semantic Match (Good for "Types" of objects)
    else if (semanticScore > 0.6) {
       // Formula: Semantic (50%) + Physical (40%) + Text (10%)
       finalScore = (semanticScore * 0.5) + (physicalScore * 0.4) + (textScore * 0.1);
    }
    // CASE C: Purely Visual Match (No clear text/tags)
    else {
       // Formula: Physical (70%) + Semantic (30%)
       finalScore = (physicalScore * 0.7) + (semanticScore * 0.3);
       
       // Penalty if expected text but found NONE (mismatch candidates)
       if (textKeywords.isNotEmpty && textScore == 0.0) {
         finalScore *= 0.8; // Reduce confidence
       }
    }
    
    return finalScore;
  }
  
  /// Calculate Jaccard Similarity of two tag maps
  double _calculateTagOverlap(Map<String, double> tagsA, Map<String, double> tagsB) {
    Set<String> allKeys = {...tagsA.keys, ...tagsB.keys};
    if (allKeys.isEmpty) return 0.0;
    
    double intersection = 0.0;
    double union = 0.0;
    
    for (String key in allKeys) {
      double confA = tagsA[key] ?? 0.0;
      double confB = tagsB[key] ?? 0.0;
      
      intersection += math.min(confA, confB);
      union += math.max(confA, confB);
    }
    
    if (union == 0) return 0.0;
    return intersection / union;
  }

  @override
  String toString() {
    return 'ProductSignature(name=$displayName, label=$label, ratio=$aspectRatioValue, hsv=[${colorHSV[0].toStringAsFixed(0)}°, ${(colorHSV[1] * 100).toStringAsFixed(0)}%, ${(colorHSV[2] * 100).toStringAsFixed(0)}%])';
  }
}

/// Detection result from ProductRecognitionService / HybridDetector
class HybridDetectionResult {
  final String? detectedProductName; // e.g., "Ketchup" (from signature database)
  final String label; // ML Kit label e.g., "Bottle"
  final String aspectRatio; // "tall", "wide", "square"
  final double aspectRatioValue; // Numeric ratio (Height/Width)
  final Color dominantColor;
  final String colorName; // "red", "blue", etc.
  final List<double> colorHSV; // [H, S, V]
  final double confidence; // 0.0 to 1.0
  final ProductSignature? matchedSignature; // Matched from database
  final Rect? boundingBox; // Bounding box in image coordinates
  final Rect? normalizedBox; // Normalized bounding box (0..1) relative to frame
  final int trackingId; // Tracking ID for tapping specific detections
  final Map<String, double> visualTags; // From Image Labeling
  final String detectedText; // OCR results

  HybridDetectionResult({
    this.detectedProductName,
    required this.label,
    required this.aspectRatio,
    this.aspectRatioValue = 1.0,
    required this.dominantColor,
    required this.colorName,
    this.colorHSV = const [0.0, 0.0, 0.0],
    this.confidence = 0.5,
    this.matchedSignature,
    this.boundingBox,
    this.normalizedBox,
    this.trackingId = 0,
    this.visualTags = const {},
    this.detectedText = '',
  });

  /// Legacy getter for backward compatibility
  String get yoloLabel => label;

  /// Whether this is a known (matched) product or unknown
  bool get isKnown => matchedSignature != null;

  /// Get display text for UI
  String getDisplayText() {
    if (detectedProductName != null) {
      return '$detectedProductName\n($label, $aspectRatio, $colorName)';
    }
    return '$label ($aspectRatio, $colorName)';
  }

  /// Get short display name
  String get displayName {
    if (detectedProductName != null) return detectedProductName!;
    // Return generic name if no specific label
    if (label == 'Unknown' || label == 'Nesne' || label.isEmpty) return 'Nesne';
    return label;
  }

  /// Create a ProductSignature from this detection result
  ProductSignature toSignature({
    required String id,
    required String userGivenName,
    String? barcode,
  }) {
    return ProductSignature(
      id: id,
      barcode: barcode,
      productName: userGivenName,
      userGivenName: userGivenName,
      label: label,
      aspectRatio: aspectRatio,
      aspectRatioValue: aspectRatioValue,
      dominantColor: dominantColor,
      colorName: colorName,
      colorHSV: colorHSV,

      visualTags: visualTags,
      detectedText: detectedText,
    );
  }

  @override
  String toString() {
    return 'HybridDetectionResult(product=$detectedProductName, label=$label, ratio=$aspectRatioValue, confidence=${(confidence * 100).toStringAsFixed(1)}%)';
  }
}

/// Utility class for color conversions
class ColorUtils {
  /// Convert RGB Color to HSV [Hue (0-360), Saturation (0-1), Value (0-1)]
  static List<double> rgbToHsv(Color color) {
    final r = color.red / 255.0;
    final g = color.green / 255.0;
    final b = color.blue / 255.0;

    final max = math.max(r, math.max(g, b));
    final min = math.min(r, math.min(g, b));
    final delta = max - min;

    double h = 0.0;
    double s = 0.0;
    double v = max;

    if (delta != 0) {
      s = delta / max;
      if (max == r) {
        h = 60 * (((g - b) / delta) % 6);
      } else if (max == g) {
        h = 60 * (((b - r) / delta) + 2);
      } else {
        h = 60 * (((r - g) / delta) + 4);
      }
    }

    if (h < 0) h += 360;

    return [h, s, v];
  }

  /// Convert HSV to RGB Color
  static Color hsvToRgb(double h, double s, double v) {
    final c = v * s;
    final x = c * (1 - ((h / 60) % 2 - 1).abs());
    final m = v - c;

    double r, g, b;

    if (h < 60) {
      r = c; g = x; b = 0;
    } else if (h < 120) {
      r = x; g = c; b = 0;
    } else if (h < 180) {
      r = 0; g = c; b = x;
    } else if (h < 240) {
      r = 0; g = x; b = c;
    } else if (h < 300) {
      r = x; g = 0; b = c;
    } else {
      r = c; g = 0; b = x;
    }

    return Color.fromARGB(
      255,
      ((r + m) * 255).round(),
      ((g + m) * 255).round(),
      ((b + m) * 255).round(),
    );
  }

  /// Get a human-readable color name from HSV
  static String getColorName(List<double> hsv) {
    final h = hsv[0];
    final s = hsv[1];
    final v = hsv[2];

    // Handle achromatic colors (low saturation or very dark/light)
    if (s < 0.1) {
      if (v < 0.2) return 'black';
      if (v > 0.8) return 'white';
      return 'gray';
    }

    if (v < 0.2) return 'black';

    // Map hue to color names
    if (h < 15 || h >= 345) return 'red';
    if (h < 45) return 'orange';
    if (h < 75) return 'yellow';
    if (h < 150) return 'green';
    if (h < 210) return 'cyan';
    if (h < 270) return 'blue';
    if (h < 330) return 'purple';
    return 'red';
  }

  /// Calculate categorical aspect ratio from numeric value
  static String getCategoricalAspectRatio(double ratio) {
    if (ratio > 1.3) return 'tall';
    if (ratio < 0.77) return 'wide';
    return 'square';
  }
}
