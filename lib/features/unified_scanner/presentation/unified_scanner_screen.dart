import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math' as math;
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/haptic_helper.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/product_recognition_service.dart';
import '../../../core/services/product_storage_service.dart';
import '../../../core/services/smart_vision_service.dart';
import '../../../core/services/app_settings_service.dart';
import '../../../core/models/product.dart';
import '../../../core/models/product_signature.dart';
import '../../home/presentation/home_screen.dart'; // For EditingMode
import '../../smart_vision/presentation/product_mapper_dialog.dart';
import '../widgets/object_box_overlay.dart';

enum ScanMode { barcode, ocr, both }

class UnifiedScannerScreen extends StatefulWidget {
  const UnifiedScannerScreen({super.key});

  @override
  State<UnifiedScannerScreen> createState() => _UnifiedScannerScreenState();
}

class _UnifiedScannerScreenState extends State<UnifiedScannerScreen>
    with WidgetsBindingObserver {
  CameraController? _cameraController;
  // Only scan product barcodes (EAN/UPC), not QR codes
  final BarcodeScanner _barcodeScanner = BarcodeScanner(
    formats: [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upca,
      BarcodeFormat.upce,
    ],
  );
  final TextRecognizer _textRecognizer =
      TextRecognizer(script: TextRecognitionScript.latin);
  final TTSService _tts = TTSService();
  final GeminiService _gemini = GeminiService();
  final FirebaseService _firebase = FirebaseService();

  // State
  bool _isInitialized = false;
  bool _isDetecting = false;
  bool _permissionDenied = false;
  String _debugInfo = 'Başlatılıyor...';

  // Detection state
  String _lastDetectedBarcode = '';
  String? _lastBarcodeConfirmed = '';
  bool _dateFound = false;
  bool _barcodeFound = false;
  String _rawDateString = '';
  Uint8List? _capturedSnapshot;
  List<Map<String, dynamic>> _detectedItems = [];

  // Date confirmation
  String? _pendingDateStr;
  int _dateConfirmationCount = 0;
  static const int _requiredConfirmations = 3;
  DateTime? _foundExpiryDate;
  
  // For linking: store date when scanning barcode to link
  String? _pendingExpiryDateStr;
  DateTime? _pendingExpiryDate;

  // UI state
  bool _previewPaused = false;
  bool _isFlashlightOn = false;
  bool _isAnalyzing = false;
  bool _showDebugOverlay = false;
  bool _isPausedForDialog = false;

  // Smart Vision state
  bool _smartVisionEnabled = false;
  bool _dataCollectionMode = false; // Disables barcode/TTS for rapid sampling
  bool _showBoundingBoxes = true; // Show/hide detection boxes
  List<HybridDetectionResult> _smartVisionDetections = [];
  final ProductRecognitionService _productRecognition = ProductRecognitionService.instance;
  final AppSettingsService _appSettings = AppSettingsService.instance;

  // Shake detection
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  DateTime? _lastShakeTime;
  static const _shakeThreshold = 15.0;
  static const _shakeCooldown = Duration(milliseconds: 1000);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tts.initialize();
    _startShakeDetection();
    _loadSmartVisionSetting();
    _checkAndRequestPermission();
  }

  Future<void> _loadSmartVisionSetting() async {
    final prefs = await SharedPreferences.getInstance();
    final enabled = prefs.getBool('smart_vision_enabled') ?? false;
    final fps = prefs.getInt('smart_vision_fps') ?? 2;
    final dataCollection = prefs.getBool('data_collection_mode') ?? false;
    final showBoxes = prefs.getBool('show_bounding_boxes') ?? true;
    
    setState(() {
      _smartVisionEnabled = enabled;
      _dataCollectionMode = dataCollection;
      _showBoundingBoxes = showBoxes;
    });
    
    if (_smartVisionEnabled) {
      // Initialize service if needed and apply FPS setting
      if (!_productRecognition.isInitialized) {
        await _productRecognition.initialize();
      }
      _productRecognition.setFPS(fps);
      debugPrint('Smart Vision: Loaded settings - enabled=$enabled, fps=$fps, dataCollection=$dataCollection');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _permissionDenied) {
      _checkAndRequestPermission();
    }
  }

  Future<void> _checkAndRequestPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      status = await Permission.camera.request();
    }

    if (status.isGranted) {
      // Initialize camera for barcode + date mode
      _initializeCamera();
    } else {
      setState(() {
        _permissionDenied = true;
        _debugInfo = status.isDenied
            ? 'Kamera izni gerekli'
            : 'Ayarlardan kamera iznini etkinleştirin';
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _debugInfo = 'Kamera bulunamadı');
        return;
      }

      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        selected,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(FlashMode.off);
      
      // Set zoom to 1.0 (standard lens) instead of 0.5x (ultra-wide)
      // This gives a focused view suitable for product detection
      try {
        final minZoom = await _cameraController!.getMinZoomLevel();
        final maxZoom = await _cameraController!.getMaxZoomLevel();
        // Use 1.0 which typically corresponds to 1x zoom (standard lens)
        // If minZoom is higher, use that instead
        final targetZoom = minZoom > 1.0 ? minZoom : 1.0;
        await _cameraController!.setZoomLevel(targetZoom.clamp(minZoom, maxZoom));
        debugPrint('Camera zoom set to ${targetZoom.clamp(minZoom, maxZoom)} (min: $minZoom, max: $maxZoom)');
      } catch (e) {
        debugPrint('Could not set zoom level: $e');
      }

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _debugInfo = 'Hazır. Kamera açık.';
        });
        _startImageStream();
      }
    } catch (e) {
      setState(() => _debugInfo = 'Kamera hatası: $e');
      debugPrint('Error initializing camera: $e');
    }
  }

  void _hapticFeedback() {
    HapticHelper.medium();
  }

  Future<void> _toggleFlashlight() async {
    try {
      if (_cameraController == null) return;

      if (_isFlashlightOn) {
        await _cameraController!.setFlashMode(FlashMode.off);
      } else {
        await _cameraController!.setFlashMode(FlashMode.torch);
      }

      setState(() => _isFlashlightOn = !_isFlashlightOn);
    } catch (e) {
      debugPrint('Error toggling flashlight: $e');
    }
  }

  // Smart Vision removed

  Future<void> _pauseImageStream() async {
    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      await _cameraController!.stopImageStream();
    }
  }

  Future<void> _resumeImageStream() async {
    if (_cameraController != null &&
        _cameraController!.value.isInitialized &&
        !_cameraController!.value.isStreamingImages &&
        !_barcodeFound &&
        !_dateFound) {
      _startImageStream();
    }
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;

    _cameraController!.startImageStream((image) async {
      if (_isDetecting ||
          _previewPaused ||
          _barcodeFound ||
          _dateFound ||
          _isPausedForDialog) return;
      _isDetecting = true;

      try {
        final inputImage = _convertCameraImage(image);
        if (inputImage == null) {
          _isDetecting = false;
          return;
        }

        // Data Collection Mode: Skip barcode and date detection for rapid object sampling
        if (!_dataCollectionMode) {
          // Normal mode: Detect barcodes and dates
          await _detectBarcodes(inputImage);
          if (!_barcodeFound) {
            await _detectDates(inputImage);
          }
        }

        // Smart Vision: Object detection with visual signature matching
        // In Data Collection Mode, this is the ONLY detection that runs
        if (_smartVisionEnabled && !_barcodeFound && !_dateFound) {
          await _processSmartVision(image);
        }
      } catch (e) {
        debugPrint('Error processing frame: $e');
      } finally {
        _isDetecting = false;
      }
    });
  }

  /// Process Smart Vision detection with throttling (handled by service)
  Future<void> _processSmartVision(CameraImage image) async {
    try {
      // Make sure service is initialized
      if (!_productRecognition.isInitialized) {
        debugPrint('⚠️ Smart Vision: Service not initialized, initializing now...');
        await _productRecognition.initialize();
      }
      
      // Use local ML Kit detection
    // iOS/Android back camera sensor is usually landscape (90 deg from portrait)
    // We need to tell ML Kit the image is rotated so it returns boxes in Portrait coordinates
    final detections = await _productRecognition.processFrame(
      image, 
      rotation: InputImageRotation.rotation90deg,
    );
    
    if (detections != null && detections.isNotEmpty) {
        debugPrint('✅ Smart Vision: Detected ${detections.length} objects');
        for (final d in detections) {
          debugPrint('   - ${d.label}: box=(${d.normalizedBox?.left.toStringAsFixed(2)}, ${d.normalizedBox?.top.toStringAsFixed(2)}) ${d.normalizedBox?.width.toStringAsFixed(2)}x${d.normalizedBox?.height.toStringAsFixed(2)}');
        }
        if (mounted) {
          setState(() {
            _smartVisionDetections = detections;
          });
          
          // Check if any detection has a linked barcode - if so, trigger barcode scan behavior
          _checkForLinkedProducts(detections);
        }
      } else if (detections != null && detections.isEmpty) {
        // Actually empty (not throttled) - clear the display
        if (mounted && _smartVisionDetections.isNotEmpty) {
          setState(() {
            _smartVisionDetections = [];
          });
          debugPrint('🔍 Smart Vision: Cleared detections (empty frame)');
        }
      }
    } catch (e, stack) {
      debugPrint('❌ Smart Vision error: $e');
      debugPrint('Stack: $stack');
    }
  }
  
  // Cloud Vision removed - using on-device ML Kit only

  /// Handle tap on an unknown product bounding box
  void _showTeachProductDialog(HybridDetectionResult detection) {
    if (detection.isKnown) {
      // Already known product - announce it and show info
      _tts.speak('Ürün: ${detection.displayName}');
      // Show option to add more samples
      _showKnownProductOptions(detection);
      return;
    }

    // Unknown product - pause camera and show teaching dialog
    setState(() => _isPausedForDialog = true);
    _pauseImageStream(); // Actually stop the camera processing
    
    // Pass barcode info if we've recently scanned one
    final linkedBarcode = _lastDetectedBarcode;
    // Product name will be entered manually or auto-filled if available
    
    showDialog(
      context: context,
      builder: (context) => ProductMapperDialog(
        detectionResult: detection,
        visionService: SmartVisionService.instance,
        linkedBarcode: linkedBarcode,
        onSaved: () {
          _tts.speak('Ürün kaydedildi');
          setState(() {
            _isPausedForDialog = false;
            _smartVisionDetections = []; // Clear to refresh
          });
        },
      ),
    ).then((_) {
      setState(() => _isPausedForDialog = false);
      _resumeImageStream(); // Resume camera when dialog closes
    });
  }
  
  /// Show options for known products (add more samples, view info)
  void _showKnownProductOptions(HybridDetectionResult detection) {
    setState(() => _isPausedForDialog = true);
    _pauseImageStream(); // Pause camera processing
    
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: detection.dominantColor,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green, width: 2),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            detection.displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          Text(
                            '${detection.colorName} • ${detection.aspectRatio}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.check_circle, color: Colors.green, size: 32),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.add_photo_alternate, color: Colors.blue),
                title: const Text('Daha Fazla Örnek Ekle'),
                subtitle: const Text('Tanıma doğruluğunu artırır'),
                onTap: () {
                  Navigator.pop(context);
                  _showAddSampleDialog(detection);
                },
              ),
              // Link barcode option
              if (_lastDetectedBarcode.isNotEmpty && detection.matchedSignature != null)
                ListTile(
                  leading: const Icon(Icons.link, color: Colors.purple),
                  title: const Text('Barkod Bağla'),
                  subtitle: Text('Barkod: $_lastDetectedBarcode'),
                  onTap: () async {
                    Navigator.pop(context);
                    await _linkBarcodeToSignature(detection.matchedSignature!, _lastDetectedBarcode);
                  },
                ),
              // Edit product info option (if barcode linked)
              if (detection.matchedSignature?.barcode != null)
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.teal),
                  title: const Text('Ürün Bilgilerini Düzenle'),
                  subtitle: const Text('SKT ve fiyat bilgilerini güncelleyin'),
                  onTap: () async {
                    Navigator.pop(context);
                    final barcode = detection.matchedSignature!.barcode!;
                    final product = await _firebase.getProduct(barcode);
                    if (product != null) {
                      await _showEditProductDialog(
                        barcode: barcode,
                        currentName: product.name,
                        currentType: product.category,
                        currentPrice: product.price.toString(),
                      );
                    } else {
                      // If product not in Firebase yet, create it
                      await _showEditProductDialog(
                        barcode: barcode,
                        currentName: detection.displayName,
                        currentType: '',
                        currentPrice: '',
                      );
                    }
                  },
                ),
              ListTile(
                leading: const Icon(Icons.volume_up, color: Colors.orange),
                title: const Text('Sesli Oku'),
                onTap: () {
                  Navigator.pop(context);
                  _tts.speak(detection.displayName);
                },
              ),
            ],
          ),
        ),
      ),
    ).then((_) {
      setState(() => _isPausedForDialog = false);
      _resumeImageStream(); // Resume camera when dialog closes
    });
  }
  
  /// Show dialog to add more samples to an existing signature
  void _showAddSampleDialog(HybridDetectionResult detection) {
    setState(() => _isPausedForDialog = true);
    _pauseImageStream(); // Pause camera processing
    
    showDialog(
      context: context,
      builder: (context) => ProductMapperDialog(
        detectionResult: detection,
        visionService: SmartVisionService.instance,
        onSaved: () {
          _tts.speak('Örnek eklendi');
          setState(() {
            _isPausedForDialog = false;
            _smartVisionDetections = [];
          });
        },
      ),
    ).then((_) {
      setState(() => _isPausedForDialog = false);
      _resumeImageStream(); // Resume camera when dialog closes
    });
  }

  /// Handle detection of a product linked to a barcode
  /// Triggers the same behavior as a successful barcode scan
  Future<void> _handleLinkedProductRecognition(ProductSignature signature) async {
    // Prevent multiple triggers
    if (_barcodeFound || _isPausedForDialog) return;
    
    final barcode = signature.barcode;
    if (barcode == null || barcode.isEmpty) return;

    debugPrint('');
    debugPrint('╔════════════════════════════════════════╗');
    debugPrint('║  👁️ VISUAL PRODUCT RECOGNITION          ║');
    debugPrint('╠════════════════════════════════════════╣');
    debugPrint('║ Product: ${signature.displayName}');
    debugPrint('║ Barcode: $barcode');
    debugPrint('║ Samples: ${signature.sampleCount}');
    debugPrint('╚════════════════════════════════════════╝');
    
    // 1. Set barcode found - stops further processing
    setState(() {
      _barcodeFound = true;
      _lastDetectedBarcode = barcode;
      _lastBarcodeConfirmed = barcode;
    });

    // 2. Stop camera stream
    await _cameraController?.stopImageStream();
    
    // 3. Haptic feedback
    await HapticHelper.scanSuccess();
    
    // 4. Take snapshot
    Uint8List? snapshot;
    try {
      final xFile = await _cameraController?.takePicture();
      if (xFile != null) {
        snapshot = await xFile.readAsBytes();
        _capturedSnapshot = snapshot;
        debugPrint('📸 Visual scan snapshot captured');
      }
    } catch (e) {
      debugPrint('Snapshot error: $e');
    }
    
    // 5. Process as if barcode was scanned - use linked barcode (mark as visual detection)
    await _processBarcodeDetection(barcode, snapshot, isVisualDetection: true);
    
    // 6. Update detection count for the signature
    final storage = ProductStorageService.instance;
    await storage.recordDetectionHit(signature.id);
  }
  
  /// Check if any detected object matches a linked product and trigger auto-scan
  void _checkForLinkedProducts(List<HybridDetectionResult> detections) {
    // Skip in Data Collection Mode - no TTS, no auto-processing
    if (_dataCollectionMode) return;
    if (_barcodeFound || _isPausedForDialog) return;
    
    final storage = ProductStorageService.instance;
    
    for (final detection in detections) {
      if (detection.isKnown && detection.matchedSignature != null) {
        final sig = detection.matchedSignature!;
        
        // Check if this signature has a linked barcode
        if (sig.barcode != null && sig.barcode!.isNotEmpty) {
          // Found a linked product - trigger barcode-like behavior
          _handleLinkedProductRecognition(sig);
          break; // Only process one at a time
        }
      }
    }
  }
  
  /// Link a barcode to an existing visual signature
  Future<void> _linkBarcodeToSignature(ProductSignature signature, String barcode) async {
    try {
      final storage = ProductStorageService.instance;
      
      // Update the signature with the barcode
      final updated = signature.copyWith(barcode: barcode);
      await storage.saveSignature(updated);
      
      // Announce success
      await _tts.speak('Barkod ${signature.displayName} ürününe bağlandı');
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.link, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text('Barkod "${signature.displayName}" ürününe bağlandı')),
              ],
            ),
            backgroundColor: Colors.purple,
          ),
        );
        
        // Clear detections to refresh
        setState(() => _smartVisionDetections = []);
      }
    } catch (e) {
      debugPrint('Error linking barcode: $e');
      await _tts.speak('Barkod bağlanırken hata oluştu');
    }
  }

  // Smart Vision configuration
  Future<void> _detectBarcodes(InputImage inputImage) async {
    try {
      final barcodes = await _barcodeScanner.processImage(inputImage);
      if (barcodes.isEmpty) return;

      for (final barcode in barcodes) {
        final code = barcode.rawValue;
        if (code == null || code.isEmpty) continue;

        if (mounted) {
          setState(() => _lastDetectedBarcode = code);
        }

        // Require multiple detections for confirmation
        if (_lastBarcodeConfirmed != code) {
          _lastBarcodeConfirmed = code;
          _hapticFeedback();
        } else {
          // Confirmed barcode - fetch product
          _hapticFeedback();
          await _confirmBarcode(code);
        }
      }
    } catch (e) {
      debugPrint('Barcode detection error: $e');
    }
  }

  Future<void> _confirmBarcode(String barcode) async {
    setState(() {
      _barcodeFound = true;
      _lastBarcodeConfirmed =
          barcode; // Store for later linking with expiry date
    });

    debugPrint('');
    debugPrint('╔════════════════════════════════════════╗');
    debugPrint('║  BARCODE SCAN DEBUG                    ║');
    debugPrint('╠════════════════════════════════════════╣');
    debugPrint('║ Barcode: $barcode');
    debugPrint('║ 💾 Stored for expiry linking');
    if (_pendingExpiryDate != null) {
      debugPrint('║ 📅 Pending expiry to link: $_pendingExpiryDateStr');
    }
    debugPrint('╚════════════════════════════════════════╝');

    // 1. IMMEDIATELY stop camera stream - don't wait for anything
    await _cameraController?.stopImageStream();
    
    // 2. Take snapshot right away
    Uint8List? snapshot;
    try {
      final xFile = await _cameraController?.takePicture();
      if (xFile != null) {
        snapshot = await xFile.readAsBytes();
        _capturedSnapshot = snapshot;
        debugPrint('📸 Snapshot captured: ${snapshot.length} bytes');
      }
    } catch (e) {
      debugPrint('Snapshot error: $e');
    }
    
    // 3. Haptic feedback immediately
    await HapticHelper.scanSuccess();
    
    // 4. Process barcode data asynchronously
    _processBarcodeDetection(barcode, snapshot);
  }

  /// Process barcode detection asynchronously after camera is stopped
  /// [isVisualDetection] - true if product was detected via Smart Vision, false if via barcode scan
  Future<void> _processBarcodeDetection(String barcode, Uint8List? snapshot, {bool isVisualDetection = false}) async {
    try {
      // Get product info from database
      final detectionMethod = isVisualDetection ? 'görsel tanıma' : 'barkod';
      debugPrint('🔍 Looking up barcode in database... (detected via $detectionMethod)');
      final product = await _firebase.getProduct(barcode);

      String displayName = '';
      String displayType = '';
      String displayPrice = '';
      String ttsText = '';
      bool isUnregistered = (product == null);
      DateTime? expiryToShow;

      // Check if we have a pending expiry date from previous date scan
      if (_pendingExpiryDate != null) {
        // Auto-link the pending expiry date to this barcode (only if editing enabled)
        expiryToShow = _pendingExpiryDate;
        if (EditingMode.enabled) {
          await _firebase.updateProductExpiry(barcode, _pendingExpiryDate!);
          debugPrint('🔗 Auto-linked pending expiry date to barcode: $barcode');
        } else {
          debugPrint('🔒 Editing disabled: expiry will not be saved to database');
        }
      }

      if (product != null) {
        // === REGISTERED PRODUCT ===
        debugPrint('✅ Product FOUND in database');
        debugPrint('   Name: ${product.name}');
        debugPrint('   Brand: ${product.brand}');
        debugPrint('   Price: ${product.price} TL');
        debugPrint('   Category: ${product.category}');
        if (product.expiryDate != null) {
          debugPrint('   Expiry: ${product.expiryDate}');
        }

        displayName = '${product.brand} ${product.name}';
        displayType = product.category;
        displayPrice =
          product.price > 0
            ? ((product.price % 1 == 0)
              ? '${product.price.toInt()} TL'
              : '${product.price.toStringAsFixed(2)} TL')
            : '';

        // Generate TTS using light model
        ttsText = await _gemini.generateTTSText(
          productName: displayName,
          productType: displayType,
          price: displayPrice,
          barcode: barcode,
        );

        // Visual detection - no special prefix needed (user preference)

        // Use pending expiry if available, otherwise use product's expiry
        expiryToShow ??= product.expiryDate;
        
        // NEW: If date missing and we have a snapshot from visual detection, try to extract it
        if (expiryToShow == null && snapshot != null && isVisualDetection) {
          debugPrint('🔍 Expiry missing in DB, trying to extract from visual scan snapshot...');
          final dateStr = await _gemini.quickDateAnalysis(snapshot);
          if (dateStr.isNotEmpty && dateStr != 'Tarih bulunamadı' && !dateStr.contains('Hata')) {
            final parsedDate = _parseDateString(dateStr);
            if (parsedDate != null) {
              expiryToShow = parsedDate;
              debugPrint('📅 Extracted expiry from snapshot: $dateStr');
              // Automatically save to DB if editing is enabled
              if (EditingMode.enabled) {
                await _firebase.updateProductExpiry(barcode, parsedDate);
                debugPrint('🔗 Auto-saved extracted expiry to database');
              }
            }
          }
        }

        // Add expiry date to TTS if available
        if (expiryToShow != null) {
          final expiryText = _getExpiryAnnouncementText(expiryToShow);
          ttsText += ' $expiryText';
          debugPrint('📅 Expiry announcement added: $expiryText');
        }

        debugPrint('🔊 TTS Text: $ttsText');
      } else {
        // === UNREGISTERED PRODUCT - Scrape web + Use Gemini ===
        debugPrint('❌ Product NOT found in database');
        debugPrint('🌐 Starting web search...');

        if (_capturedSnapshot != null) {
          setState(() => _isAnalyzing = true);

          // Announce that we're searching
          await _tts.speak('Ürün aranıyor, lütfen bekleyin.');

          // Scrape Google for barcode info
          String? webData;
          try {
            webData = await _scrapeGoogleForBarcode(barcode);
            debugPrint('🌐 Web scrape result:');
            debugPrint('   ${webData ?? "No data found"}');
          } catch (e) {
            debugPrint('🌐 Web scrape error: $e');
          }

          // Send to Gemini with web data
          debugPrint('🤖 Calling Gemini for analysis...');
          final geminiResult = await _gemini.analyzeUnregisteredBarcode(
            _capturedSnapshot!,
            barcode,
            webScrapedData: webData,
          );

          displayName = geminiResult['name'] ?? 'Bilinmeyen Ürün';
          displayType = geminiResult['type'] ?? 'Bilinmiyor';
          displayPrice = geminiResult['price'] ?? '';

          debugPrint('🤖 Gemini result:');
          debugPrint('   Name: $displayName');
          debugPrint('   Type: $displayType');
          debugPrint('   Price: $displayPrice');
          if (geminiResult.containsKey('expiryDate')) {
            debugPrint('   Expiry: ${geminiResult['expiryDate']}');
            final parsedDate = _parseDateString(geminiResult['expiryDate']!);
            if (parsedDate != null) {
              expiryToShow = parsedDate;
              debugPrint('📅 Extracted expiry from Gemini analysis: ${geminiResult['expiryDate']}');
            }
          }

          // Generate TTS using light model
          ttsText = await _gemini.generateTTSText(
            productName: displayName,
            productType: displayType,
            price: displayPrice,
            barcode: barcode,
          );
          
          // Add expiry to TTS if available
          if (expiryToShow != null) {
            final expiryText = _getExpiryAnnouncementText(expiryToShow);
            ttsText += ' $expiryText';
            debugPrint('📅 Expiry announcement added: $expiryText');
          }

          debugPrint('🔊 TTS Text: $ttsText');

          setState(() => _isAnalyzing = false);
        } else {
          displayName = 'Bilinmeyen Ürün';
          ttsText = 'Barkod tarandı. Ürün bilgisi alınamadı.';
          
          // Still add expiry if pending
          if (expiryToShow != null) {
            final expiryText = _getExpiryAnnouncementText(expiryToShow);
            ttsText += ' $expiryText';
          }
        }
      }

      // Add to detected items with full data for editing
      final detectedItem = {
        'type': 'BARKOD',
        'value': barcode,
        'analysis': ttsText,
        'unregistered': isUnregistered,
        'productName': displayName,
        'productType': displayType,
        'productPrice': displayPrice,
      };

      if (mounted) {
        setState(() {
          _detectedItems.add(detectedItem);
        });
      }

      // Clear pending expiry after linking
      _pendingExpiryDate = null;
      _pendingExpiryDateStr = null;

      // Speak TTS in background (don't wait)
      debugPrint('');
      debugPrint('═══════════════════════════════════════');
      debugPrint('🔊 TTS SPEAKING: $ttsText');
      debugPrint('═══════════════════════════════════════');
      _tts.speak(ttsText); // No await - speaks while UI shows

      // Show snapshot with AR overlay IMMEDIATELY
      if (mounted && snapshot != null) {
        await _showSnapshotOverlay(
          snapshot,
          expiryToShow != null ? 'BARKOD + TARİH' : 'BARKOD',
          displayName,
          expiryToShow,
          barcode: barcode,
          isUnregistered: isUnregistered,
          productType: displayType,
          productPrice: displayPrice,
        );
      }
    } catch (e) {
      debugPrint('Error processing barcode: $e');
      setState(() => _barcodeFound = false);
      _restartScanning();
    }
  }

  /// Scrape Google search results for barcode product info
  /// Uses multiple extraction methods for better reliability
  Future<String?> _scrapeGoogleForBarcode(String barcode) async {
    try {
      // Try multiple search queries for better results
      final queries = [
        '$barcode ürün',
        '$barcode barkod',
        '$barcode fiyat market',
      ];

      final resultBuffer = StringBuffer();

      for (final query in queries) {
        if (resultBuffer.length > 200) break; // Got enough data

        final searchQuery = Uri.encodeComponent(query);
        final url = 'https://www.google.com/search?q=$searchQuery&hl=tr&gl=tr';

        debugPrint('🌐 Scraping: $url');

        try {
          final response = await http.get(
            Uri.parse(url),
            headers: {
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
              'Accept':
                  'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
              'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
              'Accept-Encoding': 'gzip, deflate',
              'Cache-Control': 'no-cache',
            },
          ).timeout(const Duration(seconds: 10));

          if (response.statusCode == 200) {
            final body = response.body;
            final document = html_parser.parse(body);

            // Method 1: BNeawe class (Google's mobile snippet class)
            final bneaweElements = document.querySelectorAll('.BNeawe');
            for (final el in bneaweElements.take(8)) {
              final text = el.text.trim();
              if (text.isNotEmpty &&
                  text.length > 15 &&
                  text.length < 300 &&
                  !text.contains('Google') &&
                  !text.contains('http')) {
                resultBuffer.writeln(text);
              }
            }

            // Method 2: Extract from data-snf attribute divs
            final snfDivs = document.querySelectorAll('div[data-snf]');
            for (final div in snfDivs.take(5)) {
              final text = div.text.trim();
              if (text.isNotEmpty && text.length > 20 && text.length < 200) {
                resultBuffer.writeln(text);
              }
            }

            // Method 3: Look for specific product patterns in raw HTML
            // Product names often appear in specific patterns
            final productPatterns = [
              RegExp(r'>([A-ZÇĞİÖŞÜa-zçğıöşü\s]+(?:ml|gr|g|kg|lt|L|adet))<',
                  caseSensitive: false),
              RegExp(
                  r'"([^"]*(?:Deodorant|Şampuan|Süt|Peynir|Yoğurt|Ekmek|Çikolata|Bisküvi|Deterjan|Sabun)[^"]*)"',
                  caseSensitive: false),
            ];

            for (final pattern in productPatterns) {
              final matches = pattern.allMatches(body);
              for (final match in matches.take(3)) {
                final text = match.group(1)?.trim();
                if (text != null && text.length > 5 && text.length < 100) {
                  resultBuffer.writeln('Ürün: $text');
                }
              }
            }

            // Method 4: Extract prices from raw HTML
            final pricePatterns = [
              RegExp(r'(\d{1,4})[.,](\d{2})\s*(TL|₺|lira)',
                  caseSensitive: false),
              RegExp(r'(TL|₺)\s*(\d{1,4})[.,](\d{2})', caseSensitive: false),
              RegExp(
                  r'fiyat[ıi]?\s*:?\s*(\d{1,4})[.,]?(\d{0,2})\s*(TL|₺|lira)?',
                  caseSensitive: false),
            ];

            final Set<String> foundPrices = {};
            for (final pattern in pricePatterns) {
              final matches = pattern.allMatches(body);
              for (final match in matches.take(5)) {
                final priceText = match.group(0)?.trim();
                if (priceText != null && !foundPrices.contains(priceText)) {
                  foundPrices.add(priceText);
                  // Extract just the number
                  final numMatch =
                      RegExp(r'(\d{1,4})[.,]?(\d{0,2})').firstMatch(priceText);
                  if (numMatch != null) {
                    final price =
                        '${numMatch.group(1)}.${numMatch.group(2) ?? "00"}';
                    final priceNum = double.tryParse(price);
                    // Filter out unrealistic prices (between 1 and 5000 TL)
                    if (priceNum != null && priceNum > 1 && priceNum < 5000) {
                      resultBuffer.writeln('Fiyat: $price TL');
                    }
                  }
                }
              }
            }

            // Method 5: Extract from title tags
            final titles = document.querySelectorAll('h3, title');
            for (final title in titles.take(5)) {
              final text = title.text.trim();
              if (text.isNotEmpty &&
                  text.length > 10 &&
                  text.length < 150 &&
                  !text.contains('Google') &&
                  (text.contains(barcode) ||
                      text.toLowerCase().contains('fiyat') ||
                      text.toLowerCase().contains('ürün'))) {
                resultBuffer.writeln(text);
              }
            }
          }
        } catch (e) {
          debugPrint('Query "$query" failed: $e');
        }

        // Small delay between requests
        await Future.delayed(const Duration(milliseconds: 200));
      }

      final result = resultBuffer.toString().trim();
      if (result.isNotEmpty) {
        debugPrint(
            '✅ Google scrape found: ${result.substring(0, result.length.clamp(0, 100))}...');
        // Limit to 800 chars
        return result.length > 800 ? result.substring(0, 800) : result;
      }

      debugPrint('❌ Google scrape found no useful data');
      return null;
    } catch (e) {
      debugPrint('Google scrape error: $e');
      return null;
    }
  }

  Future<void> _detectDates(InputImage inputImage) async {
    try {
      final recognizedText = await _textRecognizer.processImage(inputImage);

      final datePattern = RegExp(
        r'(\d{1,2}[./\-]\d{1,2}[./\-](\d{4}|\d{2}))',
        multiLine: true,
      );

      final matches = datePattern.allMatches(recognizedText.text);
      if (matches.isEmpty) return;

      for (final match in matches) {
        final dateStr = match.group(0) ?? '';
        if (dateStr.isEmpty) continue;

        setState(() => _rawDateString = dateStr);

        // Confirmation logic
        if (_pendingDateStr == dateStr) {
          _dateConfirmationCount++;
        } else {
          _pendingDateStr = dateStr;
          _dateConfirmationCount = 1;
        }

        // Lock after 3 confirmations
        if (_dateConfirmationCount >= _requiredConfirmations && !_dateFound) {
          setState(() => _dateFound = true);

          // 1. IMMEDIATELY stop camera stream - don't wait for anything
          await _cameraController?.stopImageStream();
          
          // 2. Take snapshot right away
          Uint8List? snapshot;
          try {
            final xFile = await _cameraController?.takePicture();
            if (xFile != null) {
              snapshot = await xFile.readAsBytes();
              _capturedSnapshot = snapshot;
            }
          } catch (e) {
            debugPrint('Snapshot error: $e');
          }

          // 3. Haptic feedback immediately
          await HapticHelper.scanSuccess();

          // 4. Parse the expiry date
          _parseExpiryDate(dateStr);
          
          // 5. Now do the async work (product lookup) in background
          _processDateDetection(dateStr, snapshot);
        }
      }
    } catch (e) {
      debugPrint('OCR detection error: $e');
    }
  }

  /// Process date detection asynchronously after camera is stopped
  Future<void> _processDateDetection(String dateStr, Uint8List? snapshot) async {
    try {
      String? linkedBarcode;
      Product? linkedProduct;
      
      // Check if we have a recently scanned barcode to link with
      if (_lastBarcodeConfirmed != null && _lastBarcodeConfirmed!.isNotEmpty) {
        linkedBarcode = _lastBarcodeConfirmed;
        linkedProduct = await _firebase.getProduct(linkedBarcode!);
        
        // Auto-save the expiry date to the product if found
        if (linkedProduct != null && _foundExpiryDate != null) {
          if (EditingMode.enabled) {
            await _firebase.updateProductExpiry(linkedBarcode, _foundExpiryDate!);
            debugPrint('📅 Auto-linked expiry date to barcode: $linkedBarcode');
          } else {
            debugPrint('🔒 Editing disabled: expiry will not be saved to database');
          }
        }
      } else if (_foundExpiryDate != null) {
        // No barcode scanned yet - search for products with this expiry date
        linkedProduct = await _firebase.findProductByExpiryDate(_foundExpiryDate!);
        if (linkedProduct != null) {
          linkedBarcode = linkedProduct.barcode;
          debugPrint('🔍 Found product by expiry date: ${linkedProduct.name}');
        }
      }

      // Build TTS text with product info if available
      String ttsText;
      final expiryInfo = _getExpiryStatus();
      
      if (linkedProduct != null) {
        // We have a linked product - announce with product name
        final productName = '${linkedProduct.brand} ${linkedProduct.name}'.trim();
        ttsText = '$productName. Son kullanma tarihi: $dateStr.';
        if (expiryInfo.isNotEmpty) {
          ttsText += ' $expiryInfo.';
        }
        debugPrint('🔗 Date linked to product: $productName');
      } else {
        // No linked product - just announce the date
        ttsText = 'Son kullanma tarihi: $dateStr.';
        if (expiryInfo.isNotEmpty) {
          ttsText += ' $expiryInfo.';
        }
      }
      
      // Add to detected items
      if (mounted) {
        setState(() {
          _detectedItems.add({
            'type': 'TARİH',
            'value': dateStr,
            'analysis': ttsText,
            'linkedBarcode': linkedBarcode,
          });
        });
      }
      
      // Speak TTS in background (don't wait)
      debugPrint('🔊 TTS: $ttsText');
      _tts.speak(ttsText); // No await - speaks while UI shows

      // Show snapshot with AR overlay IMMEDIATELY
      if (mounted && snapshot != null) {
        await _showSnapshotOverlay(
          snapshot,
          linkedProduct != null ? 'TARİH + ÜRÜN' : 'TARİH',
          linkedProduct != null 
              ? '${linkedProduct.brand} ${linkedProduct.name}\n$dateStr'
              : dateStr,
          _foundExpiryDate,
          barcode: linkedBarcode,
        );
      }
    } catch (e) {
      debugPrint('Error processing date: $e');
      setState(() => _dateFound = false);
      _restartScanning();
    }
  }

  void _parseExpiryDate(String dateStr) {
    final date = _parseDateString(dateStr);
    if (date != null) {
      _foundExpiryDate = date;
      final now = DateTime.now();
      final difference = _foundExpiryDate!.difference(now).inDays;
      debugPrint('Expiry date: $_foundExpiryDate, Days remaining: $difference');
    }
  }

  DateTime? _parseDateString(String dateStr) {
    try {
      // Parse date format: 15.12.2025 or 15/12/25
      final cleanStr = dateStr.replaceAll('-', '.').replaceAll('/', '.');
      final parts = cleanStr.split('.');
      if (parts.length != 3) return null;

      int day = int.parse(parts[0]);
      int month = int.parse(parts[1]);
      int year = int.parse(parts[2]);

      // Handle 2-digit year
      if (year < 100) {
        year = year < 50 ? 2000 + year : 1900 + year;
      }

      return DateTime(year, month, day);
    } catch (e) {
      debugPrint('Error parsing date string "$dateStr": $e');
      return null;
    }
  }

  String _getExpiryStatus([DateTime? expiryDate]) {
    final date = expiryDate ?? _foundExpiryDate;
    if (date == null) return '';

    final now = DateTime.now();
    final difference = date.difference(now);

    if (difference.isNegative) {
      return 'SONA ERDİ ${difference.inDays.abs()} gün önce';
    }

    final days = difference.inDays;
    if (days == 0) return 'BUGÜN SONA ERIYOR!';
    if (days == 1) return '1 GÜN KALDI';
    if (days < 30) return '$days GÜN KALDI';

    final months = (days / 30).floor();
    return '$months AY KALDI';
  }

  /// Generate TTS text for expiry date announcement
  String _getExpiryAnnouncementText(DateTime expiryDate) {
    final now = DateTime.now();
    final difference = expiryDate.difference(now).inDays;

    if (difference < 0) {
      return 'DİKKAT! Bu ürünün son kullanma tarihi dolmuş! ${-difference} gün önce süresi bitmiş. Lütfen tüketmeyiniz!';
    } else if (difference == 0) {
      return 'Dikkat! Bu ürünün son kullanma tarihi bugün!';
    } else if (difference == 1) {
      return 'Dikkat! Bu ürünün son kullanma tarihi yarın!';
    } else if (difference <= 3) {
      return 'Dikkat! Bu ürünün son kullanma tarihine $difference gün kaldı!';
    } else if (difference <= 7) {
      return 'Bu ürünün son kullanma tarihine $difference gün kaldı.';
    } else if (difference <= 30) {
      return 'Son kullanma tarihine $difference gün var.';
    } else {
      final months = (difference / 30).floor();
      if (months == 1) {
        return 'Son kullanma tarihine yaklaşık 1 ay var.';
      } else {
        return 'Son kullanma tarihine yaklaşık $months ay var.';
      }
    }
  }

  /// Build expiry status badge for the edit dialog
  Widget _buildExpiryStatusBadge(DateTime expiryDate) {
    final now = DateTime.now();
    final difference = expiryDate.difference(now).inDays;

    Color badgeColor;
    IconData badgeIcon;
    String statusText;

    if (difference < 0) {
      badgeColor = Colors.red;
      badgeIcon = Icons.error;
      statusText = '${-difference} gün önce süresi dolmuş!';
    } else if (difference == 0) {
      badgeColor = Colors.red;
      badgeIcon = Icons.warning;
      statusText = 'Bugün son kullanma tarihi!';
    } else if (difference <= 3) {
      badgeColor = Colors.red;
      badgeIcon = Icons.warning;
      statusText = '$difference gün kaldı!';
    } else if (difference <= 7) {
      badgeColor = Colors.orange;
      badgeIcon = Icons.schedule;
      statusText = '$difference gün kaldı';
    } else if (difference <= 30) {
      badgeColor = Colors.amber;
      badgeIcon = Icons.calendar_today;
      statusText = '$difference gün kaldı';
    } else {
      badgeColor = Colors.green;
      badgeIcon = Icons.check_circle;
      statusText = '$difference gün kaldı';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: badgeColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(badgeIcon, color: badgeColor, size: 18),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  void _startShakeDetection() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      final acceleration =
          (event.x.abs() + event.y.abs() + event.z.abs()) - 9.8;

      if (acceleration > _shakeThreshold) {
        final now = DateTime.now();
        if (_lastShakeTime == null ||
            now.difference(_lastShakeTime!) > _shakeCooldown) {
          _lastShakeTime = now;
          if (_dateFound || _barcodeFound) {
            _restartScanning();
          }
        }
      }
    });
  }

  void _restartScanning() {
    setState(() {
      _dateFound = false;
      _barcodeFound = false;
      _rawDateString = '';
      _lastDetectedBarcode = '';
      _lastBarcodeConfirmed = '';
      _capturedSnapshot = null;
      _detectedItems = [];
      _pendingDateStr = null;
      _dateConfirmationCount = 0;
      _foundExpiryDate = null;
      _previewPaused = false;
      // Clear pending linking data
      _pendingExpiryDate = null;
      _pendingExpiryDateStr = null;
    });

    _cameraController?.resumePreview();
    _startImageStream();
    HapticFeedback.mediumImpact();
  }

  /// Soft restart - keeps barcode info for date linking
  /// Use this after barcode scan to continue scanning for expiry dates
  void _softRestartForDateScan() {
    final savedBarcode = _lastBarcodeConfirmed;
    setState(() {
      _dateFound = false;
      _barcodeFound = false; // Allow date detection
      _rawDateString = '';
      _lastDetectedBarcode = '';
      _capturedSnapshot = null;
      _pendingDateStr = null;
      _dateConfirmationCount = 0;
      _foundExpiryDate = null;
      _previewPaused = false;
      // Keep _lastBarcodeConfirmed for date linking!
      _lastBarcodeConfirmed = savedBarcode;
    });

    _cameraController?.resumePreview();
    _startImageStream();
    HapticFeedback.lightImpact();
    
    // Announce that we're ready for date scan
    if (savedBarcode != null && savedBarcode.isNotEmpty) {
      _tts.speak('Son kullanma tarihi taramaya hazır.');
    }
  }

  /// Soft restart - keeps date info for barcode linking
  /// Use this after date scan to continue scanning for barcode
  void _softRestartForBarcodeScan() {
    final savedDateStr = _rawDateString.isNotEmpty ? _rawDateString : _pendingDateStr;
    final savedDate = _foundExpiryDate;
    setState(() {
      _dateFound = false;
      _barcodeFound = false;
      _lastDetectedBarcode = '';
      _lastBarcodeConfirmed = '';
      _capturedSnapshot = null;
      _detectedItems = [];
      _previewPaused = false;
      // Keep date info for barcode linking!
      _pendingExpiryDateStr = savedDateStr;
      _pendingExpiryDate = savedDate;
    });

    _cameraController?.resumePreview();
    _startImageStream();
    HapticFeedback.lightImpact();
    
    // Announce that we're ready for barcode scan
    _tts.speak('Barkod taramaya hazır. Ürün barkodunu okutun.');
  }

  Future<void> _showSnapshotOverlay(
    Uint8List imageBytes,
    String detectionType,
    String detectionValue,
    DateTime? expiryDate, {
    String? barcode,
    bool isUnregistered = false,
    String? productType,
    String? productPrice,
  }) async {
    await showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.transparent, // We'll create our own barrier
      builder: (context) => Material(
        color: Colors.transparent,
        child: GestureDetector(
          // Horizontal swipe anywhere = ÇIKIŞ (exit to main menu)
          onHorizontalDragEnd: (details) {
            if (details.primaryVelocity != null && details.primaryVelocity!.abs() > 300) {
              Navigator.pop(context); // Close dialog
              Navigator.pop(context); // Exit to main menu
            }
          },
          child: Stack(
            children: [
              // Full-screen tappable background = TEKRAR (restart)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _restartScanning();
                  },
                  child: Container(color: Colors.black54),
                ),
              ),
              // Centered dialog content
              Center(
                child: GestureDetector(
                  // Absorb taps on dialog content so they don't trigger restart
                  onTap: () {},
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500, maxHeight: 800),
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dialogBackgroundColor,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                // Image with constrained height
                SizedBox(
                  height: 280,
                  width: double.infinity,
                  child: Stack(
                    children: [
                      Image.memory(
                        imageBytes,
                        fit: BoxFit.cover,
                        width: double.infinity,
                        height: 280,
                      ),
                      // AR Overlay
                      Positioned.fill(
                        child: CustomPaint(
                          painter: _AROverlayPainter(
                            detectionType: detectionType,
                            detectionValue: detectionValue,
                            expiryStatus: _getExpiryStatus(expiryDate),
                          ),
                        ),
                      ),
                      // Unregistered badge
                      if (isUnregistered)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'KAYITLI DEĞİL',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        detectionValue,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      if (barcode != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Barkod: $barcode',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                      if (productType != null &&
                          productType.isNotEmpty &&
                          productType != 'Bilinmiyor') ...[
                        const SizedBox(height: 4),
                        Text(
                          'Kategori: $productType',
                          style:
                              TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ],
                      if (productPrice != null && productPrice.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          'Fiyat: $productPrice',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.green),
                        ),
                      ],
                      if (expiryDate != null) ...[
                        const SizedBox(height: 12),
                        _buildExpiryStatusBadge(expiryDate),
                      ],
                      // Info text for unregistered products
                      if (isUnregistered) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.orange.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: Colors.orange.withOpacity(0.3)),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline,
                                  color: Colors.orange, size: 16),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'İnternet araması yapıldı',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.orange,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // Link to barcode button (when date detected and barcode was scanned, only if editing enabled)
                      if (barcode == null &&
                          expiryDate != null &&
                          _lastBarcodeConfirmed != null &&
                          _lastBarcodeConfirmed!.isNotEmpty &&
                          EditingMode.enabled) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              await _linkBarcodeWithExpiry(
                                  _lastBarcodeConfirmed!, expiryDate);
                              if (mounted) Navigator.pop(context);
                              _restartScanning();
                            },
                            icon: const Icon(Icons.link, size: 20),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.purple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            label: const Text(
                              'BARKOD İLE EŞLEŞTIR',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Edit & Save button for barcodes (only if editing mode is enabled)
                      if (barcode != null && EditingMode.enabled) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              Navigator.pop(context);
                              await _showEditProductDialog(
                                barcode: barcode,
                                currentName: detectionValue,
                                currentType: productType ?? '',
                                currentPrice: productPrice ?? '',
                              );
                            },
                            icon: const Icon(Icons.edit, size: 20),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            label: Text(
                              isUnregistered ? 'DÜZENLE VE KAYDET' : 'BİLGİLERİ DÜZENLE',
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Scan Date button for barcodes (to link with expiry) - only if editing enabled
                      if (barcode != null && expiryDate == null && EditingMode.enabled) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _softRestartForDateScan();
                            },
                            icon: const Icon(Icons.calendar_month, size: 20),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            label: const Text(
                              'TARİH TARA',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Scan Barcode button for dates (to link with product) - only if editing enabled
                      if (barcode == null && expiryDate != null && EditingMode.enabled) ...[
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context);
                              _softRestartForBarcodeScan();
                            },
                            icon: const Icon(Icons.qr_code_scanner, size: 20),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            label: const Text(
                              'BARKOD TARA',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Main action buttons
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  _restartScanning();
                                },
                                icon: const Icon(Icons.refresh, size: 20),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue.shade700,
                                  foregroundColor: Colors.white,
                                ),
                                label: const Text(
                                  'TEKRAR',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: SizedBox(
                              height: 48,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.pop(context);
                                  Navigator.pop(context);
                                },
                                icon: const Icon(Icons.close, size: 20),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.grey.shade600,
                                  foregroundColor: Colors.white,
                                ),
                                label: const Text(
                                  'ÇIKIŞ',
                                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ),
                          ),
                        ], // Row children ends
                      ), // Row ends
                    ], // Padding Column children ends
                  ), // Padding Column ends
                ), // Padding ends
              ], // outer Column children ends
            ), // outer Column ends
          ), // SingleChildScrollView ends
        ), // Container ends
      ), // ConstrainedBox ends
    ), // GestureDetector (content) ends
  ), // Center ends
], // Stack children ends
), // Stack ends
), // GestureDetector (swipe) ends
), // Material ends
    );
  }

  /// Show edit dialog for product data
  Future<void> _showEditProductDialog({
    required String barcode,
    required String currentName,
    required String currentType,
    required String currentPrice,
  }) async {
    final nameController = TextEditingController(text: currentName);
    final brandController = TextEditingController();
    final typeController = TextEditingController(text: currentType);
    final priceController = TextEditingController(
      text: currentPrice.replaceAll(RegExp(r'[^\d.,]'), ''),
    );

    // Try to split brand from name
    final nameParts = currentName.split(' ');
    if (nameParts.length > 1) {
      brandController.text = nameParts.first;
      nameController.text = nameParts.skip(1).join(' ');
    }

    // Expiry date state
    DateTime? selectedExpiryDate = _foundExpiryDate;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.edit, color: Colors.blue),
              SizedBox(width: 8),
              Text('Ürün Bilgilerini Düzenle'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Barcode (read-only)
                TextField(
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Barkod',
                    hintText: barcode,
                    prefixIcon: const Icon(Icons.qr_code),
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey[100],
                  ),
                  controller: TextEditingController(text: barcode),
                ),
                const SizedBox(height: 12),
                // Brand
                TextField(
                  controller: brandController,
                  decoration: const InputDecoration(
                    labelText: 'Marka',
                    hintText: 'örn: Ülker, Pınar, Tamek',
                    prefixIcon: Icon(Icons.business),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                // Product Name
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Ürün Adı *',
                    hintText: 'örn: Tam Yağlı Süt 1L',
                    prefixIcon: Icon(Icons.shopping_bag),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                ),
                const SizedBox(height: 12),
                // Category
                TextField(
                  controller: typeController,
                  decoration: const InputDecoration(
                    labelText: 'Kategori',
                    hintText: 'örn: Süt Ürünleri, İçecek, Atıştırmalık',
                    prefixIcon: Icon(Icons.category),
                    border: OutlineInputBorder(),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),
                // Price
                TextField(
                  controller: priceController,
                  decoration: const InputDecoration(
                    labelText: 'Fiyat (TL)',
                    hintText: 'örn: 25.90',
                    prefixIcon: Icon(Icons.attach_money),
                    suffixText: 'TL',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                ),
                const SizedBox(height: 12),
                // Expiry Date Picker
                InkWell(
                  onTap: () async {
                    final DateTime? picked = await showDatePicker(
                      context: context,
                      initialDate: selectedExpiryDate ?? DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
                      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
                      locale: const Locale('tr', 'TR'),
                      helpText: 'Son Kullanma Tarihi Seçin',
                      cancelText: 'İPTAL',
                      confirmText: 'TAMAM',
                      fieldLabelText: 'Tarih girin',
                      fieldHintText: 'GG/AA/YYYY',
                    );
                    if (picked != null) {
                      setDialogState(() {
                        selectedExpiryDate = picked;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Son Kullanma Tarihi',
                      prefixIcon: const Icon(Icons.calendar_today, color: Colors.orange),
                      border: const OutlineInputBorder(),
                      suffixIcon: selectedExpiryDate != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 20),
                              onPressed: () {
                                setDialogState(() {
                                  selectedExpiryDate = null;
                                });
                              },
                            )
                          : const Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(
                      selectedExpiryDate != null
                          ? '${selectedExpiryDate!.day.toString().padLeft(2, '0')}/${selectedExpiryDate!.month.toString().padLeft(2, '0')}/${selectedExpiryDate!.year}'
                          : 'Tarih seçmek için dokunun',
                      style: TextStyle(
                        color: selectedExpiryDate != null
                            ? Colors.black87
                            : Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                // Expiry status indicator
                if (selectedExpiryDate != null) ...[
                  const SizedBox(height: 8),
                  _buildExpiryStatusBadge(selectedExpiryDate!),
                ],
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.withOpacity(0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline, color: Colors.blue, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bu bilgiler yerel veritabanına kaydedilecek ve gelecek taramalarda kullanılacak.',
                          style: TextStyle(fontSize: 12, color: Colors.blue),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İPTAL'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ürün adı gerekli!'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // Parse price
                double price = 0.0;
                try {
                  final priceStr =
                      priceController.text.replaceAll(',', '.').trim();
                  if (priceStr.isNotEmpty) {
                    price = double.parse(priceStr);
                  }
                } catch (e) {
                  debugPrint('Price parse error: $e');
                }

                // Create product with expiry date
                final product = Product(
                  barcode: barcode,
                  name: nameController.text.trim(),
                  brand: brandController.text.trim(),
                  category: typeController.text.trim().isNotEmpty
                      ? typeController.text.trim()
                      : 'Diğer',
                  price: price,
                  weight: '',
                  expiryDate: selectedExpiryDate,
                );

                // Save to database
                await _firebase.addProduct(product);

                debugPrint('');
                debugPrint('╔════════════════════════════════════════╗');
                debugPrint('║  PRODUCT SAVED TO DATABASE             ║');
                debugPrint('╠════════════════════════════════════════╣');
                debugPrint('║ Barcode: $barcode');
                debugPrint('║ Brand: ${product.brand}');
                debugPrint('║ Name: ${product.name}');
                debugPrint('║ Category: ${product.category}');
                debugPrint('║ Price: ${product.price} TL');
                if (selectedExpiryDate != null) {
                  debugPrint('║ Expiry: ${selectedExpiryDate!.day}/${selectedExpiryDate!.month}/${selectedExpiryDate!.year}');
                }
                debugPrint('╚════════════════════════════════════════╝');

                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              },
              icon: const Icon(Icons.save),
              label: const Text('KAYDET'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 8),
              Text('Ürün veritabanına kaydedildi!'),
            ],
          ),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
      await _tts.speak('Ürün kaydedildi.');
    }

    _restartScanning();
  }

  /// Link barcode with expiry date
  Future<void> _linkBarcodeWithExpiry(
      String barcode, DateTime expiryDate) async {
    debugPrint('');
    debugPrint('╔════════════════════════════════════════╗');
    debugPrint('║  🔗 LINKING BARCODE WITH EXPIRY DATE   ║');
    debugPrint('╠════════════════════════════════════════╣');
    debugPrint('║ Barcode: $barcode');
    debugPrint(
        '║ Expiry: ${expiryDate.day}/${expiryDate.month}/${expiryDate.year}');
    debugPrint('╚════════════════════════════════════════╝');

    try {
      // Update the product with expiry date
      await _firebase.updateProductExpiry(barcode, expiryDate);

      // Calculate days until expiry
      final daysUntilExpiry = expiryDate.difference(DateTime.now()).inDays;

      String statusText;
      if (daysUntilExpiry < 0) {
        statusText = 'Son kullanma tarihi ${-daysUntilExpiry} gün önce dolmuş!';
      } else if (daysUntilExpiry == 0) {
        statusText = 'Bugün son kullanma tarihi!';
      } else if (daysUntilExpiry == 1) {
        statusText = 'Yarın son kullanma tarihi.';
      } else if (daysUntilExpiry <= 7) {
        statusText = '$daysUntilExpiry gün içinde süresi dolacak.';
      } else {
        statusText = '$daysUntilExpiry gün sonra süresi dolacak.';
      }

      // Announce and show feedback
      await _tts.speak('Tarih barkoda kaydedildi. $statusText');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.link, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tarih $barcode barkoduna bağlandı!\n$statusText',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.purple,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error linking barcode with expiry: $e');
      await _tts.speak('Tarih kaydedilirken hata oluştu.');
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final WriteBuffer allBytes = WriteBuffer();
      for (final Plane plane in image.planes) {
        allBytes.putUint8List(plane.bytes);
      }
      final bytes = allBytes.done().buffer.asUint8List();

      final Size imageSize =
          Size(image.width.toDouble(), image.height.toDouble());

      const inputImageFormat = InputImageFormat.bgra8888;

      final inputImage = InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.rotation0deg,
          format: inputImageFormat,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      return inputImage;
    } catch (e) {
      debugPrint('Error converting camera image: $e');
      return null;
    }
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _cameraController?.dispose();
    _barcodeScanner.close();
    _textRecognizer.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasCameraPreview =
        _cameraController != null && _cameraController!.value.isInitialized;

    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 16),
              Text(_debugInfo),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Camera preview
          if (hasCameraPreview)
            CameraPreview(_cameraController!)
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),

          // Top controls
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back button
                    IconButton(
                      icon: const Icon(Icons.arrow_back, color: Colors.white),
                      onPressed: () => Navigator.pop(context),
                    ),

                    // Mode display
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.54),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'BARKOD + TARİH',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),

                    // Flashlight button
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isFlashlightOn ? Icons.flash_on : Icons.flash_off,
                            color: Colors.white,
                          ),
                          onPressed: _toggleFlashlight,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Center guide circle (hidden when Smart Vision is active)
          if (!_smartVisionEnabled)
            Center(
              child: Container(
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white24, width: 2),
                ),
              ),
            ),

          // Bottom controls
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    // Status info
                    if (_lastDetectedBarcode.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.9),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Barkod: $_lastDetectedBarcode',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                      ),
                    if (_rawDateString.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.9),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Tarih: $_rawDateString',
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14),
                          ),
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Status display only, no mode toggle
                    if (_isAnalyzing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text(
                          'Analiz yapılıyor...',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          // Debug info
          if (_showDebugOverlay)
            Positioned(
              bottom: 100,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _debugInfo,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),

          // Smart Vision object detection overlays - using new ObjectBoxOverlay
          if (_smartVisionEnabled && _showBoundingBoxes && _smartVisionDetections.isNotEmpty)
            ObjectBoxOverlay(
              detections: _smartVisionDetections,
              previewSize: Size(
                _cameraController!.value.previewSize?.height ?? 1280,
                _cameraController!.value.previewSize?.width ?? 720,
              ),
              screenSize: MediaQuery.of(context).size,
              dataCollectionMode: _dataCollectionMode,
              onBoxTap: (detection) {
                if (detection.isKnown) {
                  _showKnownProductOptions(detection);
                } else {
                  _showTeachProductDialog(detection);
                }
              },
            ),
        ],
      ),
    );
  }

  /// Build Smart Vision bounding box overlays
  List<Widget> _buildSmartVisionOverlays() {
    if (_cameraController == null ||
        !_cameraController!.value.isInitialized ||
        _smartVisionDetections.isEmpty) {
      return [];
    }
    
    // Get screen size from context
    final screenSize = MediaQuery.of(context).size;
    final screenWidth = screenSize.width;
    final screenHeight = screenSize.height;

    final List<Widget> overlays = [];
    
    for (int i = 0; i < _smartVisionDetections.length; i++) {
      final detection = _smartVisionDetections[i];
      if (detection.normalizedBox == null) continue;

      final box = detection.normalizedBox!;
      final isKnown = detection.isKnown;
      final borderColor = isKnown ? Colors.green : Colors.orange;
      final bgColor = isKnown 
          ? Colors.green.withOpacity(0.15) 
          : Colors.orange.withOpacity(0.15);

      // Convert normalized coordinates to screen coordinates
      final left = box.left * screenWidth;
      final top = box.top * screenHeight;
      final width = box.width * screenWidth;
      final height = box.height * screenHeight;
      
      // Skip invalid boxes
      if (width < 20 || height < 20) continue;
      if (left + width < 0 || top + height < 0 ||
          left > screenWidth || top > screenHeight) continue;

      // Main bounding box
      overlays.add(
        Positioned(
          key: ValueKey('box_$i'),
          left: left,
          top: top,
          width: width,
          height: height,
          child: GestureDetector(
            onTap: () => _showTeachProductDialog(detection),
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: borderColor, width: 2),
                color: bgColor,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
        ),
      );
      
      // Label above the box
      overlays.add(
        Positioned(
          key: ValueKey('label_$i'),
          left: left,
          top: top - 26,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: borderColor,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              detection.displayName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
      
      // Color swatch at bottom right
      overlays.add(
        Positioned(
          key: ValueKey('swatch_$i'),
          left: left + width - 24,
          top: top + height - 24,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: detection.dominantColor,
              border: Border.all(color: Colors.white, width: 1),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      );
      
      // Tap hint for unknown products
      if (!isKnown) {
        overlays.add(
          Positioned(
            key: ValueKey('hint_$i'),
            left: left + 4,
            top: top + height - 22,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.touch_app, color: Colors.white, size: 12),
                  SizedBox(width: 4),
                  Text(
                    'Dokunun',
                    style: TextStyle(color: Colors.white, fontSize: 9),
                  ),
                ],
              ),
            ),
          ),
        );
      }
    }
    
    return overlays;
  }
}

class _AROverlayPainter extends CustomPainter {
  final String detectionType;
  final String detectionValue;
  final String expiryStatus;

  _AROverlayPainter({
    required this.detectionType,
    required this.detectionValue,
    required this.expiryStatus,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.green.withValues(alpha: 0.3)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    final centerY = size.height / 2;

    // Draw circle
    canvas.drawCircle(Offset(centerX, centerY), 80, paint);

    // Draw crosshair
    final crossPaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 2;

    canvas.drawLine(Offset(centerX - 20, centerY),
        Offset(centerX + 20, centerY), crossPaint);
    canvas.drawLine(Offset(centerX, centerY - 20),
        Offset(centerX, centerY + 20), crossPaint);

    // Draw text info
    final textPainter = TextPainter(
      text: TextSpan(
        text: '$detectionType\n$detectionValue\n$expiryStatus',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 3)],
        ),
      ),
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, const Offset(16, 16));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
