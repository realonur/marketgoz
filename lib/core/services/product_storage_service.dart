import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/product_signature.dart';

/// Service for persisting product signatures using Hive
/// Provides CRUD operations and statistics tracking
class ProductStorageService {
  static const String _boxName = 'product_signatures';
  static const String _statsBoxName = 'signature_stats';
  
  static ProductStorageService? _instance;
  Box<String>? _signaturesBox;
  Box<dynamic>? _statsBox;
  bool _initialized = false;

  ProductStorageService._();

  /// Get singleton instance
  static ProductStorageService get instance {
    _instance ??= ProductStorageService._();
    return _instance!;
  }

  /// Initialize Hive and open boxes
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      await Hive.initFlutter();
      _signaturesBox = await Hive.openBox<String>(_boxName);
      _statsBox = await Hive.openBox<dynamic>(_statsBoxName);
      _initialized = true;
      debugPrint('ProductStorageService: Initialized successfully');
    } catch (e) {
      debugPrint('ProductStorageService: Initialization error: $e');
      rethrow;
    }
  }

  /// Ensure service is initialized
  void _ensureInitialized() {
    if (!_initialized || _signaturesBox == null) {
      throw StateError('ProductStorageService not initialized. Call initialize() first.');
    }
  }

  /// Save a product signature
  Future<void> saveSignature(ProductSignature signature) async {
    _ensureInitialized();
    
    final json = jsonEncode(signature.toJson());
    await _signaturesBox!.put(signature.id, json);
    
    // Update stats
    final totalSaved = _statsBox!.get('totalSaved', defaultValue: 0) as int;
    await _statsBox!.put('totalSaved', totalSaved + 1);
    
    debugPrint('ProductStorageService: Saved signature "${signature.displayName}"');
  }

  /// Get a signature by ID
  ProductSignature? getSignature(String id) {
    _ensureInitialized();
    
    final json = _signaturesBox!.get(id);
    if (json == null) return null;
    
    try {
      return ProductSignature.fromJson(jsonDecode(json));
    } catch (e) {
      debugPrint('ProductStorageService: Error parsing signature $id: $e');
      return null;
    }
  }

  /// Get all saved signatures
  List<ProductSignature> getAllSignatures() {
    _ensureInitialized();
    
    final signatures = <ProductSignature>[];
    for (final key in _signaturesBox!.keys) {
      final json = _signaturesBox!.get(key);
      if (json != null) {
        try {
          signatures.add(ProductSignature.fromJson(jsonDecode(json)));
        } catch (e) {
          debugPrint('ProductStorageService: Error parsing signature $key: $e');
        }
      }
    }
    
    // Sort by last used (most recent first), then by detection count
    signatures.sort((a, b) {
      if (a.lastUsedAt != null && b.lastUsedAt != null) {
        return b.lastUsedAt!.compareTo(a.lastUsedAt!);
      }
      if (a.lastUsedAt != null) return -1;
      if (b.lastUsedAt != null) return 1;
      return b.detectionCount.compareTo(a.detectionCount);
    });
    
    return signatures;
  }

  /// Find signatures matching a label
  List<ProductSignature> findByLabel(String label) {
    _ensureInitialized();
    
    return getAllSignatures()
        .where((s) => s.label.toLowerCase() == label.toLowerCase())
        .toList();
  }

  /// Find the best matching signature for a detection result
  /// Returns null if no match found within tolerance
  ProductSignature? findBestMatch(
    HybridDetectionResult detection, {
    double ratioTolerance = 0.2,
    double hueTolerance = 20.0,
  }) {
    _ensureInitialized();
    
    final candidates = findByLabel(detection.label);
    if (candidates.isEmpty) return null;

    // Create a temporary signature for comparison
    final tempSignature = detection.toSignature(
      id: 'temp',
      userGivenName: '',
    );

    ProductSignature? bestMatch;
    double bestScore = 0;

    for (final candidate in candidates) {
      if (candidate.matchesWithTolerance(
        tempSignature,
        ratioTolerance: ratioTolerance,
        hueTolerance: hueTolerance,
      )) {
        final score = candidate.matchScore(tempSignature);
        if (score > bestScore) {
          bestScore = score;
          bestMatch = candidate;
        }
      }
    }

    return bestMatch;
  }

  /// Update a signature's usage statistics
  Future<void> recordDetectionHit(String id) async {
    _ensureInitialized();
    
    final signature = getSignature(id);
    if (signature == null) return;

    final updated = signature.copyWith(
      lastUsedAt: DateTime.now(),
      detectionCount: signature.detectionCount + 1,
    );

    await saveSignature(updated);
    
    // Update global stats
    final totalDetections = _statsBox!.get('totalDetections', defaultValue: 0) as int;
    await _statsBox!.put('totalDetections', totalDetections + 1);
  }

  /// Improve a signature's accuracy by averaging with new detection data
  /// This allows users to add more samples to make recognition more reliable
  Future<void> improveSignature(String id, HybridDetectionResult newSample) async {
    _ensureInitialized();
    
    final existing = getSignature(id);
    if (existing == null) {
      debugPrint('ProductStorageService: Cannot improve - signature $id not found');
      return;
    }
    
    // Calculate weighted average of visual features
    // Give more weight to existing data (based on sample count)
    final newSampleCount = existing.sampleCount + 1;  // Use sampleCount, not detectionCount
    final existingWeight = existing.sampleCount.toDouble();
    final newWeight = 1.0;
    final totalWeight = existingWeight + newWeight;
    
    // Average aspect ratio
    final newAspectRatio = (existing.aspectRatioValue * existingWeight + 
                            newSample.aspectRatioValue * newWeight) / totalWeight;
    
    // Average HSV color (handle hue wrap-around)
    final existingHsv = existing.colorHSV;
    final newHsv = newSample.colorHSV;
    
    // For hue, handle circular averaging
    double avgHue;
    if ((existingHsv[0] - newHsv[0]).abs() > 180) {
      // Hue values are on opposite sides of the circle
      avgHue = ((existingHsv[0] + 360) * existingWeight + newHsv[0] * newWeight) / totalWeight;
      if (avgHue >= 360) avgHue -= 360;
    } else {
      avgHue = (existingHsv[0] * existingWeight + newHsv[0] * newWeight) / totalWeight;
    }
    
    final avgSat = (existingHsv[1] * existingWeight + newHsv[1] * newWeight) / totalWeight;
    final avgVal = (existingHsv[2] * existingWeight + newHsv[2] * newWeight) / totalWeight;
    
    // Merge Visual Tags (Weighted Average to learn/decay features)
    Map<String, double> mergedTags = {};
    if (existing.visualTags.isNotEmpty || newSample.visualTags.isNotEmpty) {
      Set<String> allTags = {...existing.visualTags.keys, ...newSample.visualTags.keys};
      for (String tag in allTags) {
         double oldConf = existing.visualTags[tag] ?? 0.0;
         double newConf = newSample.visualTags[tag] ?? 0.0;
         
         double avgConf = (oldConf * existingWeight + newConf * newWeight) / totalWeight;
         // Keep if significant
         if (avgConf > 0.05) { 
            mergedTags[tag] = avgConf;
         }
      }
    }
    
    // Create updated signature with averaged values
    // Update sampleCount (training samples), NOT detectionCount (recognition hits)
    final updated = existing.copyWith(
      aspectRatioValue: newAspectRatio,
      colorHSV: [avgHue, avgSat, avgVal],
      visualTags: mergedTags,
      lastUsedAt: DateTime.now(),
      sampleCount: newSampleCount,  // Fixed: update sampleCount, not detectionCount
    );
    
    await saveSignature(updated);
    debugPrint('ProductStorageService: Improved signature "${existing.displayName}" with sample #$newSampleCount');
    debugPrint('  - Aspect ratio: ${existing.aspectRatioValue.toStringAsFixed(2)} -> ${newAspectRatio.toStringAsFixed(2)}');
    debugPrint('  - Hue: ${existingHsv[0].toStringAsFixed(0)}° -> ${avgHue.toStringAsFixed(0)}°');
  }

  /// Delete a signature by ID
  Future<void> deleteSignature(String id) async {
    _ensureInitialized();
    
    await _signaturesBox!.delete(id);
    debugPrint('ProductStorageService: Deleted signature $id');
  }

  /// Delete all signatures
  Future<void> clearAll() async {
    _ensureInitialized();
    
    await _signaturesBox!.clear();
    await _statsBox!.clear();
    debugPrint('ProductStorageService: Cleared all signatures');
  }

  /// Get storage statistics
  Map<String, dynamic> getStatistics() {
    _ensureInitialized();
    
    final signatures = getAllSignatures();
    
    // Find most frequently detected signature
    String? topSignature;
    int topCount = 0;
    for (final sig in signatures) {
      if (sig.detectionCount > topCount) {
        topCount = sig.detectionCount;
        topSignature = sig.displayName;
      }
    }

    // Count unique labels
    final labels = <String>{};
    for (final sig in signatures) {
      labels.add(sig.label.toLowerCase());
    }

    return {
      'totalSignatures': signatures.length,
      'totalDetections': _statsBox!.get('totalDetections', defaultValue: 0),
      'totalSaved': _statsBox!.get('totalSaved', defaultValue: 0),
      'topSignature': topSignature,
      'topSignatureCount': topCount,
      'uniqueLabels': labels.length,
      'labels': labels.toList(),
    };
  }

  /// Generate a unique signature ID
  String generateId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 1000).toString().padLeft(3, '0');
    return 'sig_${timestamp}_$random';
  }

  /// Check if service is initialized
  bool get isInitialized => _initialized;

  /// Close Hive boxes
  Future<void> dispose() async {
    await _signaturesBox?.close();
    await _statsBox?.close();
    _initialized = false;
  }
}
