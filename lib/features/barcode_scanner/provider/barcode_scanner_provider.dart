import 'package:flutter/material.dart';
import '../../../core/models/scan_result.dart';
import '../../../core/services/ml_kit_service.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/open_food_service.dart';
import '../../../core/models/product.dart';
import '../../../core/services/google_search_service.dart';

class BarcodeScannerProvider extends ChangeNotifier {
  final MLKitService _mlKitService = MLKitService();
  final FirebaseService _firebaseService = FirebaseService();
  final OpenFoodService _openFoodService = OpenFoodService();

  bool _isScanning = false;
  bool _isProcessing = false;
  ScanResult? _lastScanResult;
  String? _error;
  String? _lastScannedBarcode;
  String? _lastSource;

  bool get isScanning => _isScanning;
  bool get isProcessing => _isProcessing;
  ScanResult? get lastScanResult => _lastScanResult;
  String? get error => _error;
  String? get lastSource => _lastSource;

  void startScanning() {
    _isScanning = true;
    _error = null;
    // No TTS - haptic feedback handled in UI
    notifyListeners();
  }

  void stopScanning() {
    _isScanning = false;
    notifyListeners();
  }

  Future<void> processBarcode(String barcode) async {
    // Prevent duplicate scans
    if (_isProcessing || _lastScannedBarcode == barcode) {
      debugPrint('BarcodeProvider: Skip duplicate $barcode');
      return;
    }

    _isProcessing = true;
    _lastScannedBarcode = barcode;
    _error = null;
    _lastSource = 'processing';
    notifyListeners();

    try {
      // Fetch product from Firebase
      final product = await _firebaseService.getProduct(barcode);

      if (product != null) {
        debugPrint('BarcodeProvider: Firebase hit for $barcode');
        _lastSource = 'firebase';
        _lastScanResult = ScanResult.success(
          barcode: barcode,
          product: product,
        );
      } else {
        debugPrint('BarcodeProvider: Firebase miss for $barcode, trying OpenFoodFacts');
        // Fallback to OpenFoodFacts for TR/Turkish products
        final externalInfo = await _openFoodService.getProductInfo(barcode);

        if (externalInfo != null) {
          debugPrint('BarcodeProvider: OpenFoodFacts hit for $barcode -> $externalInfo');
          _lastSource = 'openfoodfacts';
          final parsed = _parseBrandAndName(externalInfo);
          final fallbackProduct = Product(
            barcode: barcode,
            name: parsed.$2,
            brand: parsed.$1,
            category: '',
            price: 0.0,
            weight: '',
          );

          _lastScanResult = ScanResult.success(
            barcode: barcode,
            product: fallbackProduct,
          );
        } else {
          debugPrint('BarcodeProvider: OpenFoodFacts miss for $barcode, trying Google scrape');
          // Last-chance: scrape Google for product title
          final scraped = await GoogleSearchService.fetchProductTitle(barcode);
          if (scraped != null) {
            debugPrint('BarcodeProvider: Google scrape hit for $barcode -> $scraped');
            _lastSource = 'google';
            final parsed = _parseBrandAndName(scraped);
            final fallbackProduct = Product(
              barcode: barcode,
              name: parsed.$2,
              brand: parsed.$1,
              category: '',
              price: 0.0,
              weight: '',
            );

            _lastScanResult = ScanResult.success(
              barcode: barcode,
              product: fallbackProduct,
            );
          } else {
            debugPrint('BarcodeProvider: Google scrape miss for $barcode');
            _lastSource = 'not_found';
            _error = 'Ürün bulunamadı';
            _lastScanResult = ScanResult.error(
              barcode: barcode,
              errorMessage: _error!,
            );
          }
        }
      }
    } catch (e) {
      debugPrint('BarcodeProvider: error for $barcode -> $e');
      _lastSource = 'error';
      _error = 'Hata: ${e.toString()}';
      _lastScanResult = ScanResult.error(
        barcode: barcode,
        errorMessage: _error!,
      );
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  /// Parses "Brand - Name" or single token into (brand, name)
  (String, String) _parseBrandAndName(String value) {
    final parts = value.split(' - ');
    if (parts.length >= 2) {
      return (parts.first.trim(), parts.sublist(1).join(' - ').trim());
    }
    // If no delimiter, treat entire string as name
    return ('', value.trim());
  }

  void clearResult() {
    _lastScanResult = null;
    _lastScannedBarcode = null;
    _error = null;
    _lastSource = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _mlKitService.dispose();
    super.dispose();
  }
}
