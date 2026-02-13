import 'lib/core/services/firebase_service.dart';

void main() async {
  print('🎯 MarketGöz Offline Demo Test\n');
  print('=================================\n');
  
  final firebaseService = FirebaseService();
  
  // Test barcodes
  final testBarcodes = [
    '8690504001016', // Pınar Süt
    '8690632007014', // Uno Ekmek
    '8690777001014', // Tamek Salça
    '9999999999999', // Not found
  ];
  
  for (final barcode in testBarcodes) {
    print('📦 Scanning barcode: $barcode');
    final product = await firebaseService.getProduct(barcode);
    
    if (product != null) {
      print('✅ Product found!');
      print('   Name: ${product.brand} ${product.name}');
      print('   Price: ${product.price} TL');
      print('   Category: ${product.category}');
      print('   Weight: ${product.weight}\n');
    } else {
      print('❌ Product not found in database\n');
    }
  }
  
  print('=================================');
  print('🎉 Demo test complete!');
  print('\nTo run the full app, you need:');
  print('1. Install Xcode from App Store');
  print('2. Run: flutter run');
  print('   OR');
  print('3. Connect a physical iPhone/Android device');
}
