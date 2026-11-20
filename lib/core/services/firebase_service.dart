import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';

/// Local product database service with persistent storage
/// Products are saved to device and persist across app restarts
class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  static const String _storageKey = 'marketgoz_products';
  SharedPreferences? _prefs;
  bool _isInitialized = false;

  // In-memory cache + persistent storage
  final Map<String, Map<String, dynamic>> _productDatabase = {};

  // Default products (pre-loaded)
  static final Map<String, Map<String, dynamic>> _defaultProducts = {
    '8696368944005': {
      'name': 'UHT Krema %18 Yağlı',
      'brand': 'Tikveşli',
      'category': 'Süt Ürünleri',
      'price': 32.90,
      'weight': '200ml',
    },
    '8692971478791': {
      'name': 'İçim çikolatalı süt 1L',
      'brand': 'İçim',
      'category': 'Süt Ürünleri',
      'price': 20.50,
      'weight': '189ml',
    },
    '8690504002020': {
      'name': 'Yoğurt 500g',
      'brand': 'Pınar',
      'category': 'Süt Ürünleri',
      'price': 18.75,
      'weight': '500g',
    },
    '8690632007014': {
      'name': 'Ekmek',
      'brand': 'Uno',
      'category': 'Fırın Ürünleri',
      'price': 5.50,
      'weight': '350g',
    },
    '8690632010014': {
      'name': 'Tost Ekmeği',
      'brand': 'Uno',
      'category': 'Fırın Ürünleri',
      'price': 12.00,
      'weight': '500g',
    },
    '8690504005014': {
      'name': 'Peynir Beyaz',
      'brand': 'Pınar',
      'category': 'Süt Ürünleri',
      'price': 85.00,
      'weight': '500g',
    },
    '8690777001014': {
      'name': 'Domates Salçası',
      'brand': 'Tamek',
      'category': 'Konserve',
      'price': 22.50,
      'weight': '700g',
    },
    '8690888001014': {
      'name': 'Şeker',
      'brand': 'Türk Şeker',
      'category': 'Şeker',
      'price': 18.00,
      'weight': '1000g',
    },
    '8690999001014': {
      'name': 'Çay',
      'brand': 'Çaykur',
      'category': 'İçecek',
      'price': 48.00,
      'weight': '500g',
    },
  };

  /// Initialize the service - must be called before using
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _prefs = await SharedPreferences.getInstance();

      // Load saved products from storage
      final savedData = _prefs?.getString(_storageKey);
      if (savedData != null) {
        final Map<String, dynamic> decoded = jsonDecode(savedData);
        decoded.forEach((key, value) {
          _productDatabase[key] = Map<String, dynamic>.from(value);
        });
        debugPrint(
            '📦 Loaded ${_productDatabase.length} products from storage');
      }

      // Merge default products (don't overwrite user-saved ones)
      _defaultProducts.forEach((barcode, data) {
        if (!_productDatabase.containsKey(barcode)) {
          _productDatabase[barcode] = Map<String, dynamic>.from(data);
        }
      });

      _isInitialized = true;
      debugPrint(
          '✅ Product database initialized with ${_productDatabase.length} products');
    } catch (e) {
      debugPrint('❌ Error initializing product database: $e');
      // Fall back to default products only
      _productDatabase.addAll(_defaultProducts);
      _isInitialized = true;
    }
  }

  /// Save database to persistent storage
  Future<void> _saveToStorage() async {
    try {
      if (_prefs == null) {
        _prefs = await SharedPreferences.getInstance();
      }

      final jsonData = jsonEncode(_productDatabase);
      await _prefs?.setString(_storageKey, jsonData);
      debugPrint('💾 Saved ${_productDatabase.length} products to storage');
    } catch (e) {
      debugPrint('❌ Error saving to storage: $e');
    }
  }

  /// Get product by barcode
  Future<Product?> getProduct(String barcode) async {
    // Ensure initialized
    if (!_isInitialized) {
      await initialize();
    }

    try {
      if (_productDatabase.containsKey(barcode)) {
        final data = Map<String, dynamic>.from(_productDatabase[barcode]!);
        data['barcode'] = barcode;
        debugPrint(
            '✅ Found product in database: ${data['brand']} ${data['name']}');
        return Product.fromJson(data);
      }
      debugPrint('❌ Product not found in database: $barcode');
      return null;
    } catch (e) {
      debugPrint('Error fetching product: $e');
      return null;
    }
  }

  /// Add a new product to database (persisted to device)
  Future<void> addProduct(Product product) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _productDatabase[product.barcode] = {
        'name': product.name,
        'brand': product.brand,
        'category': product.category,
        'price': product.price,
        'weight': product.weight,
      };

      // Save to persistent storage
      await _saveToStorage();

      debugPrint('');
      debugPrint('╔════════════════════════════════════════╗');
      debugPrint('║  💾 PRODUCT SAVED TO DEVICE            ║');
      debugPrint('╠════════════════════════════════════════╣');
      debugPrint('║ Barcode: ${product.barcode}');
      debugPrint('║ Brand: ${product.brand}');
      debugPrint('║ Name: ${product.name}');
      debugPrint('║ Category: ${product.category}');
      debugPrint('║ Price: ${product.price} TL');
      debugPrint('╚════════════════════════════════════════╝');
    } catch (e) {
      debugPrint('Error adding product: $e');
    }
  }

  /// Update existing product
  Future<void> updateProduct(Product product) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _productDatabase[product.barcode] = {
        'name': product.name,
        'brand': product.brand,
        'category': product.category,
        'price': product.price,
        'weight': product.weight,
      };

      // Save to persistent storage
      await _saveToStorage();

      debugPrint('📝 Product updated: ${product.barcode}');
    } catch (e) {
      debugPrint('Error updating product: $e');
    }
  }

  /// Delete a product from database
  Future<void> deleteProduct(String barcode) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      _productDatabase.remove(barcode);
      await _saveToStorage();
      debugPrint('🗑️ Product deleted: $barcode');
    } catch (e) {
      debugPrint('Error deleting product: $e');
    }
  }

  /// Get all products in database
  Future<List<Product>> getAllProducts() async {
    if (!_isInitialized) {
      await initialize();
    }

    final products = <Product>[];
    for (var entry in _productDatabase.entries) {
      final data = Map<String, dynamic>.from(entry.value);
      data['barcode'] = entry.key;
      products.add(Product.fromJson(data));
    }
    return products;
  }

  /// Search products by name or brand
  Future<List<Product>> searchProducts(String query) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final products = <Product>[];
      final lowerQuery = query.toLowerCase();

      for (var entry in _productDatabase.entries) {
        final data = Map<String, dynamic>.from(entry.value);
        data['barcode'] = entry.key;
        final product = Product.fromJson(data);

        if (product.name.toLowerCase().contains(lowerQuery) ||
            product.brand.toLowerCase().contains(lowerQuery) ||
            product.category.toLowerCase().contains(lowerQuery)) {
          products.add(product);
        }
      }

      return products;
    } catch (e) {
      debugPrint('Error searching products: $e');
      return [];
    }
  }

  /// Get database stats
  Map<String, int> getStats() {
    return {
      'total': _productDatabase.length,
      'userAdded': _productDatabase.length - _defaultProducts.length,
    };
  }

  /// Export entire database as JSON string
  Future<String> exportDatabaseAsJson() async {
    if (!_isInitialized) {
      await initialize();
    }

    final exportData = <String, dynamic>{
      'exportDate': DateTime.now().toIso8601String(),
      'version': '1.0',
      'productCount': _productDatabase.length,
      'products': {},
    };

    for (var entry in _productDatabase.entries) {
      exportData['products'][entry.key] = Map<String, dynamic>.from(entry.value);
    }

    final jsonString = const JsonEncoder.withIndent('  ').convert(exportData);
    debugPrint('📤 Database exported: ${_productDatabase.length} products');
    return jsonString;
  }

  /// Import database from JSON string
  Future<int> importDatabaseFromJson(String jsonString) async {
    if (!_isInitialized) {
      await initialize();
    }

    try {
      final Map<String, dynamic> importData = jsonDecode(jsonString);
      final products = importData['products'] as Map<String, dynamic>?;
      
      if (products == null) {
        debugPrint('❌ Invalid import data: no products found');
        return 0;
      }

      int importedCount = 0;
      for (var entry in products.entries) {
        _productDatabase[entry.key] = Map<String, dynamic>.from(entry.value);
        importedCount++;
      }

      await _saveToStorage();
      debugPrint('📥 Database imported: $importedCount products');
      return importedCount;
    } catch (e) {
      debugPrint('❌ Error importing database: $e');
      return 0;
    }
  }

  /// Clear all user-added products (keep defaults)
  Future<void> resetToDefaults() async {
    _productDatabase.clear();
    _productDatabase.addAll(_defaultProducts);
    await _saveToStorage();
    debugPrint('🔄 Database reset to defaults');
  }
}
