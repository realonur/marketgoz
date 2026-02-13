import 'product.dart';
import 'expiry_date.dart';

class ScanResult {
  final String barcode;
  final Product? product;
  final ExpiryDate? expiryDate;
  final DateTime timestamp;
  final bool success;
  final String? errorMessage;

  const ScanResult({
    required this.barcode,
    this.product,
    this.expiryDate,
    required this.timestamp,
    required this.success,
    this.errorMessage,
  });

  factory ScanResult.success({
    required String barcode,
    Product? product,
    ExpiryDate? expiryDate,
  }) {
    return ScanResult(
      barcode: barcode,
      product: product,
      expiryDate: expiryDate,
      timestamp: DateTime.now(),
      success: true,
    );
  }

  factory ScanResult.error({
    required String barcode,
    required String errorMessage,
  }) {
    return ScanResult(
      barcode: barcode,
      timestamp: DateTime.now(),
      success: false,
      errorMessage: errorMessage,
    );
  }

  @override
  String toString() {
    return 'ScanResult(barcode: $barcode, success: $success, product: ${product?.name})';
  }
}
