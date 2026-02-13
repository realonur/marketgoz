import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:hive_flutter/hive_flutter.dart';
// import 'package:firebase_core/firebase_core.dart'; // OFFLINE DEMO MODE
import 'app/app.dart';
import 'core/services/tts_service.dart';
import 'core/services/product_storage_service.dart';
import 'features/barcode_scanner/provider/barcode_scanner_provider.dart';
import 'features/ocr_scanner/provider/ocr_scanner_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase - DISABLED FOR OFFLINE DEMO
  // await Firebase.initializeApp();
  
  // Set portrait orientation only
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  // Initialize Hive for local storage
  await Hive.initFlutter();
  
  // Initialize Product Storage Service
  await ProductStorageService.instance.initialize();
  
  // Initialize TTS Service
  final ttsService = TTSService();
  await ttsService.initialize();
  
  runApp(
    MultiProvider(
      providers: [
        Provider<TTSService>.value(value: ttsService),
        ChangeNotifierProvider<BarcodeScannerProvider>(
          create: (_) => BarcodeScannerProvider(),
        ),
        ChangeNotifierProvider<OcrScannerProvider>(
          create: (_) => OcrScannerProvider(),
        ),
      ],
      child: const MarketGozApp(),
    ),
  );
}
