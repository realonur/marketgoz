import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/services/product_recognition_service.dart';
import '../../../core/services/product_storage_service.dart';
import '../../../core/services/smart_vision_service.dart';
import '../../smart_vision/presentation/product_mapper_dialog.dart';


/// Smart Vision settings widget with toggle, FPS control, and signature management
class SmartVisionSettingsWidget extends StatefulWidget {
  const SmartVisionSettingsWidget({super.key});

  @override
  State<SmartVisionSettingsWidget> createState() => _SmartVisionSettingsWidgetState();
}

class _SmartVisionSettingsWidgetState extends State<SmartVisionSettingsWidget> {
  bool _isSmartVisionEnabled = false;
  bool _isLoading = true;
  int _signatureCount = 0;
  int _fps = 2; // Default 2 FPS
  bool _dataCollectionMode = false; // Disables barcode/TTS for rapid sampling
  bool _showBoundingBoxes = true; // Show/hide detection boxes
  bool _highAccuracyMode = false; // Single image mode

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    final storage = ProductStorageService.instance;
    
    if (!storage.isInitialized) {
      await storage.initialize();
    }
    
    setState(() {
      _isSmartVisionEnabled = prefs.getBool('smart_vision_enabled') ?? false;
      _fps = prefs.getInt('smart_vision_fps') ?? 2;
      _dataCollectionMode = prefs.getBool('data_collection_mode') ?? false;
      _showBoundingBoxes = prefs.getBool('show_bounding_boxes') ?? true;
      _highAccuracyMode = prefs.getBool('high_accuracy_mode') ?? false;
      _signatureCount = storage.getAllSignatures().length;
      _isLoading = false;
    });
    
    // Apply saved FPS setting
    if (_isSmartVisionEnabled) {
      ProductRecognitionService.instance.setFPS(_fps);
    }
  }

  Future<void> _toggleSmartVision(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('smart_vision_enabled', value);
    
    if (value) {
      await SmartVisionService.instance.initialize(highAccuracy: _highAccuracyMode);
      ProductRecognitionService.instance.setFPS(_fps);
    }
    
    setState(() {
      _isSmartVisionEnabled = value;
    });
  }

  Future<void> _setFPS(int fps) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('smart_vision_fps', fps);
    ProductRecognitionService.instance.setFPS(fps);
    setState(() {
      _fps = fps;
    });
  }

  Future<void> _toggleDataCollectionMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('data_collection_mode', value);
    setState(() {
      _dataCollectionMode = value;
    });
  }

  Future<void> _toggleBoundingBoxes(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('show_bounding_boxes', value);
    setState(() {
      _showBoundingBoxes = value;
    });
  }
  
  Future<void> _toggleAccuracyMode(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('high_accuracy_mode', value);
    setState(() {
      _highAccuracyMode = value;
    });
    
    // Check if we need to reinitialize services
    if (_isSmartVisionEnabled) {
      await SmartVisionService.instance.setAccuracyMode(value);
      // Mode change might reset FPS, so re-apply strictly if needed
      // But typically High Accuracy enforces its own FPS (1 FPS), so we might want to respect that.
      // Or we can let the user override FPS even in high accuracy mode.
      // Let's re-apply user preference but respect that High Accuracy might mean lower max FPS.
    }
  }

  void _showSignatureDatabase() {
    showDialog(
      context: context,
      builder: (context) => SignatureDatabaseDialog(
        visionService: SmartVisionService.instance,
      ),
    ).then((_) => _loadSettings());
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Title and Toggle Row
          Row(
            children: [
              const Icon(Icons.visibility, color: Colors.purple, size: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Smart Vision',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Ürün şekil ve renk ile tanıma',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: _isSmartVisionEnabled,
                activeTrackColor: Colors.purple.withValues(alpha: 0.5),
                activeColor: Colors.purple,
                onChanged: _toggleSmartVision,
              ),
            ],
          ),

          // Additional options when enabled
          if (_isSmartVisionEnabled) ...[
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            
            // FPS Slider
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speed, color: Colors.orange, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Tarama Hızı: $_fps FPS',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.orange,
                      thumbColor: Colors.orange,
                      inactiveTrackColor: Colors.orange.withValues(alpha: 0.3),
                    ),
                    child: Slider(
                      value: _fps.toDouble(),
                      min: 1,
                      max: 10,
                      divisions: 9,
                      label: '$_fps FPS',
                      onChanged: (value) => _setFPS(value.round()),
                    ),
                  ),
                  Text(
                    'Düşük = Pil tasarrufu, Yüksek = Daha hızlı algılama',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Signature database info
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.fingerprint, color: Colors.purple, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$_signatureCount ürün kaydedildi',
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                        const Text(
                          'Öğretilen ürün imzaları',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            
            // Manage signatures button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _showSignatureDatabase,
                icon: const Icon(Icons.storage, size: 18),
                label: const Text('İmza Veritabanını Yönet'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Usage instructions
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Nasıl kullanılır?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '1. Tarayıcıyı açın ve ürüne tutun\n'
                    '2. Turuncu kutu = bilinmeyen ürün\n'
                    '3. Kutuya dokunun ve isim girin\n'
                    '4. Yeşil kutu = tanınan ürün',
                    style: TextStyle(fontSize: 13, height: 1.4),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            
            // Data Collection Mode
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.science, color: Colors.teal, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Veri Toplama Modu',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Switch(
                        value: _dataCollectionMode,
                        onChanged: _toggleDataCollectionMode,
                        activeColor: Colors.teal,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Barkod ve TTS devre dışı bırakır. Hızlı örnek ekleme için ideal.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Show Bounding Boxes Toggle
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.crop_square, color: Colors.blue, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Sınırlayıcı Kutuları Göster',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Switch(
                        value: _showBoundingBoxes,
                        onChanged: _toggleBoundingBoxes,
                        activeColor: Colors.blue,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Tespit edilen nesnelerin etrafında renkli kutular gösterir.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // High Accuracy Mode
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.purple.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.high_quality, color: Colors.purple, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Yüksek Doğruluk Modu',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                      ),
                      Switch(
                        value: _highAccuracyMode,
                        onChanged: _toggleAccuracyMode,
                        activeColor: Colors.purple,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Daha hassas kutu tespiti yapar ancak yavaştır (1 FPS).',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            

            
            const SizedBox(height: 16),
            
            // Developer Options - Console Dump
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.developer_mode, color: Colors.grey, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Geliştirici Seçenekleri',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _dumpDatabaseToConsole,
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Veritabanını Konsola Yazdır'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey,
                        side: const BorderSide(color: Colors.grey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Tüm imza ve ürün verilerini debug konsoluna JSON olarak yazdırır.',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
  
  void _dumpDatabaseToConsole() {
    final storage = ProductStorageService.instance;
    final signatures = storage.getAllSignatures();
    
    debugPrint('');
    debugPrint('╔════════════════════════════════════════════════════════════════╗');
    debugPrint('║                    DATABASE EXPORT                              ║');
    debugPrint('╠════════════════════════════════════════════════════════════════╣');
    debugPrint('');
    
    // Export signatures as JSON
    final exportData = {
      'exportDate': DateTime.now().toIso8601String(),
      'signatureCount': signatures.length,
      'signatures': signatures.map((s) => s.toJson()).toList(),
    };
    
    // Pretty print JSON
    const encoder = JsonEncoder.withIndent('  ');
    final jsonString = encoder.convert(exportData);
    
    // Print in chunks to avoid truncation
    const chunkSize = 800;
    for (var i = 0; i < jsonString.length; i += chunkSize) {
      final end = (i + chunkSize < jsonString.length) ? i + chunkSize : jsonString.length;
      debugPrint(jsonString.substring(i, end));
    }
    
    debugPrint('');
    debugPrint('╚════════════════════════════════════════════════════════════════╝');
    debugPrint('');
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${signatures.length} imza konsola yazdırıldı'),
        backgroundColor: Colors.green,
      ),
    );
  }
}
