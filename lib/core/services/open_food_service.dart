import 'dart:developer' as dev;
import 'package:openfoodfacts/openfoodfacts.dart';

/// Service to fetch basic product info from barcode using OpenFoodFacts
/// - Localized for Turkey (TR) and Turkish language
/// - Optimized to fetch only name + brand
class OpenFoodService {
  OpenFoodService() {
    // Configure global settings once
    OpenFoodAPIConfiguration.userAgent = UserAgent(
      name: 'MarketGoz',
      version: '1.0.0',
    );
    OpenFoodAPIConfiguration.globalCountry = OpenFoodFactsCountry.TURKEY;
    OpenFoodAPIConfiguration.globalLanguages = [
      OpenFoodFactsLanguage.TURKISH,
    ];
  }

  /// Returns "Brand - Product Name" or null if not found or on error.
  Future<String?> getProductInfo(String barcode) async {
    try {
      if (barcode.trim().isEmpty) return null;

      final query = ProductQueryConfiguration(
        barcode,
        // Only fetch the fields we need to save bandwidth
        fields: const <ProductField>[
          ProductField.NAME,
          ProductField.BRANDS,
        ],
        // Ensure TR + Turkish for local names
        country: OpenFoodAPIConfiguration.globalCountry,
        languages: OpenFoodAPIConfiguration.globalLanguages,
        version: ProductQueryVersion.v3,
      );

      final result = await OpenFoodAPIClient.getProductV3(query);
      final product = result.product;

      if (product == null) return null;

      final name = (product.productName?.trim() ?? '');
      final brand = (product.brands?.trim() ?? '');

      if (name.isEmpty && brand.isEmpty) return null;

      if (brand.isNotEmpty && name.isNotEmpty) {
        return '$brand - $name';
      } else if (brand.isNotEmpty) {
        return brand;
      } else {
        return name;
      }
    } catch (e, st) {
      dev.log(
        'OpenFoodService.getProductInfo error: $e',
        name: 'OpenFoodService',
        stackTrace: st,
      );
      return null;
    }
  }
}
