import 'package:flutter/foundation.dart';

/// Service to maintain context of scanned products for better AI recognition
class ProductContextService {
  static final ProductContextService _instance = ProductContextService._internal();
  factory ProductContextService() => _instance;
  ProductContextService._internal();

  // In-memory storage of product information
  final List<ScannedProduct> _productHistory = [];
  final Set<String> _knownBrands = {};
  final Set<String> _knownProductTypes = {};
  final Set<String> _knownProductNames = {};
  
  static const int _maxHistorySize = 50; // Keep last 50 products

  /// Add a successfully analyzed product to context
  void addProduct({
    required String? brand,
    required String? productType,
    required String? productName,
    required String expiryDate,
  }) {
    // Add to history
    final product = ScannedProduct(
      brand: brand ?? '',
      productType: productType ?? '',
      productName: productName ?? '',
      expiryDate: expiryDate,
      timestamp: DateTime.now(),
    );
    
    _productHistory.insert(0, product); // Add to front
    
    // Trim history if too large
    if (_productHistory.length > _maxHistorySize) {
      _productHistory.removeRange(_maxHistorySize, _productHistory.length);
    }
    
    // Update known sets
    if (brand != null && brand.isNotEmpty && brand != 'Bulunamadı') {
      _knownBrands.add(brand);
    }
    if (productType != null && productType.isNotEmpty && productType != 'Bulunamadı') {
      _knownProductTypes.add(productType);
    }
    if (productName != null && productName.isNotEmpty && productName != 'Bulunamadı') {
      _knownProductNames.add(productName);
    }
    
    debugPrint('Product added to context. Total history: ${_productHistory.length}');
    debugPrint('Known brands: ${_knownBrands.length}, Types: ${_knownProductTypes.length}');
  }

  /// Get context string for AI to improve recognition
  String getContextForAI() {
    if (_productHistory.isEmpty) {
      return '';
    }
    
    final context = StringBuffer();
    context.writeln('Daha önce taranan ürünler hakkında bilgi (kullanıcının alışveriş geçmişi):');
    
    // Add known brands
    if (_knownBrands.isNotEmpty) {
      context.writeln('Bilinen markalar: ${_knownBrands.take(10).join(", ")}');
    }
    
    // Add known product types
    if (_knownProductTypes.isNotEmpty) {
      context.writeln('Bilinen ürün tipleri: ${_knownProductTypes.take(10).join(", ")}');
    }
    
    // Add recent products (last 5)
    if (_productHistory.isNotEmpty) {
      context.writeln('Son taranan ürünler:');
      for (var i = 0; i < _productHistory.length && i < 5; i++) {
        final p = _productHistory[i];
        if (p.brand.isNotEmpty || p.productType.isNotEmpty) {
          context.writeln('- ${p.brand} ${p.productType}${p.productName.isNotEmpty ? " (${p.productName})" : ""}');
        }
      }
    }
    
    return context.toString();
  }

  /// Get statistics for debugging
  Map<String, dynamic> getStats() {
    return {
      'totalScanned': _productHistory.length,
      'uniqueBrands': _knownBrands.length,
      'uniqueTypes': _knownProductTypes.length,
      'uniqueProducts': _knownProductNames.length,
    };
  }

  /// Clear all context (useful for testing or user privacy)
  void clearContext() {
    _productHistory.clear();
    _knownBrands.clear();
    _knownProductTypes.clear();
    _knownProductNames.clear();
    debugPrint('Product context cleared');
  }
}

/// Model for a scanned product
class ScannedProduct {
  final String brand;
  final String productType;
  final String productName;
  final String expiryDate;
  final DateTime timestamp;

  ScannedProduct({
    required this.brand,
    required this.productType,
    required this.productName,
    required this.expiryDate,
    required this.timestamp,
  });
}
