import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../core/utils/haptic_helper.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/services/gemini_service.dart';
import '../../../core/services/product_context_service.dart';
// Using built-in iOS TTS via flutter_tts (see TTSService)

class OcrScannerScreen extends StatefulWidget {
  const OcrScannerScreen({super.key});

  @override
  State<OcrScannerScreen> createState() => _OcrScannerScreenState();
}

class _OcrScannerScreenState extends State<OcrScannerScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
  final TTSService _tts = TTSService();
  final GeminiService _gemini = GeminiService();
  final ProductContextService _productContext = ProductContextService();
  
  bool _isInitialized = false;
  bool _isDetecting = false;
  bool _showDebugOverlay = false;
  bool _permissionDenied = false;
  bool _dateFound = false;
  String _debugInfo = 'Baslatiliyor...';
  int _frameCount = 0;
  String _lastRecognizedText = '';
  List<String> _detectedDates = [];
  DateTime? _foundExpiryDate;
  DateTime? _foundProductionDate;  // ÜT - Üretim Tarihi
  Uint8List? _capturedSnapshot;
  String _rawDateString = '';
  String _rawProductionDateString = '';  // Store production date string
  
  // Track all found dates with their types
  Map<String, String> _dateTypes = {};  // date string -> type (expiry/production)
  
  // Debug tracking
  int _imageWidth = 0;
  int _imageHeight = 0;
  int _textBlockCount = 0;
  int _processedFrames = 0;
  double _lastProcessTime = 0;
  
  // AR overlay - store text blocks with positions
  List<TextBlock> _textBlocks = [];
  List<TextBlock> _resultTextBlocks = [];
  List<_ResultBlock> _resultBlocks = [];
  
  // Date confirmation - require seeing same date multiple times
  String? _pendingDateStr;
  int _dateConfirmationCount = 0;
  static const int _requiredConfirmations = 3;  // Need to see same date 3 times
  
  Timer? _guidanceTimer;
  int _framesWithoutText = 0;
  int _framesWithText = 0;
  bool _hasSpokenInitialGuidance = false;
  DateTime? _lastGuidanceTime;
  
  // Haptic feedback throttling ("Geiger Counter")
  DateTime? _lastHapticTime;
  static const Duration _hapticThrottleDuration = Duration(milliseconds: 150);  // More responsive
  
  // Flashlight state
  bool _isFlashlightOn = false;
  bool _isDisposing = false;
  DateTime? _lastFlashToggleTime;
  static const Duration _flashToggleCooldown = Duration(seconds: 2);
  static const double _flashLumaLowThreshold = 45;   // Turn on below this
  static const double _flashLumaHighThreshold = 70;  // Turn off above this

  bool _previewPaused = false;
  
  // Shake detection for new scan
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  DateTime? _lastShakeTime;
  static const _shakeThreshold = 15.0;
  static const _shakeCooldown = Duration(milliseconds: 1000);
  
  // AI analysis state
  bool _isAiAnalyzing = false;
  
  // Gemini AI snapshot after date found only
  String _geminiLatestAnalysis = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tts.initialize();
    _startShakeDetection();
    _checkAndRequestPermission();
  }
  
  void _startShakeDetection() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      final acceleration = (event.x.abs() + event.y.abs() + event.z.abs()) - 9.8;
      
      if (acceleration > _shakeThreshold) {
        final now = DateTime.now();
        if (_lastShakeTime == null || 
            now.difference(_lastShakeTime!) > _shakeCooldown) {
          _lastShakeTime = now;
          _onShake();
        }
      }
    });
  }
  
  void _onShake() {
    HapticFeedback.mediumImpact();
    if (_dateFound) {
      _restartScanning();
    }
    // No TTS - haptic feedback is enough
  }
  
  /// Double-tap triggers AI analysis
  Future<void> _triggerAiAnalysis() async {
    if (_isAiAnalyzing) {
      // Just haptic to indicate already in progress
      HapticFeedback.lightImpact();
      return;
    }
    
    setState(() => _isAiAnalyzing = true);
    
    // Heavy haptic to confirm AI starting - no TTS
    HapticFeedback.heavyImpact();
    
    try {
      // Capture image
      Uint8List? imageBytes;
      
      if (_capturedSnapshot != null) {
        imageBytes = _capturedSnapshot;
      } else if (_cameraController != null && _cameraController!.value.isInitialized) {
        // Take a picture for AI
        final xFile = await _cameraController!.takePicture();
        imageBytes = await xFile.readAsBytes();
      }
      
      if (imageBytes == null) {
        // Error haptic pattern
        HapticFeedback.heavyImpact();
        await Future.delayed(const Duration(milliseconds: 100));
        HapticFeedback.heavyImpact();
        setState(() => _isAiAnalyzing = false);
        return;
      }
      
      // Call Gemini AI
      debugPrint('=== CALLING GEMINI AI ===');
      final result = await _gemini.analyzeProduct(imageBytes);
      debugPrint('=== AI RESULT RECEIVED ===');
      debugPrint('Result: $result');
      debugPrint('Result length: ${result.length}');
      
      // Keep haptic feedback only; no TTS for AI result
      HapticFeedback.heavyImpact();
      
    } catch (e) {
      debugPrint('AI Analysis error: $e');
      // Error haptic pattern (double buzz)
      HapticFeedback.heavyImpact();
      await Future.delayed(const Duration(milliseconds: 100));
      HapticFeedback.heavyImpact();
    } finally {
      setState(() => _isAiAnalyzing = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _permissionDenied) {
      _checkAndRequestPermission();
    }
  }

  Future<void> _checkAndRequestPermission() async {
    setState(() {
      _debugInfo = 'Kamera izni kontrol ediliyor...';
      _permissionDenied = false;
    });

    var status = await Permission.camera.status;

    if (status.isGranted) {
      _initializeCamera();
      return;
    }

    setState(() {
      _debugInfo = 'Kamera izni isteniyor...';
    });

    status = await Permission.camera.request();

    if (status.isGranted) {
      _initializeCamera();
    } else {
      setState(() {
        _permissionDenied = true;
        _debugInfo = status.isPermanentlyDenied 
            ? 'Kamera izni kalici olarak reddedildi.'
            : 'Kamera izni reddedildi.';
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      setState(() {
        _debugInfo = 'Kameralar araniyor...';
      });
      
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _debugInfo = 'Kamera bulunamadi';
        });
        return;
      }

      _cameraController = CameraController(
        cameras.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _debugInfo = 'Kamera hazir. Tarama basliyor...';
        });
        
        // Start scanning (provider removed to fix navigation issue)
        
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted && !_hasSpokenInitialGuidance) {
            _hasSpokenInitialGuidance = true;
            // Just haptic feedback, no TTS
            HapticFeedback.mediumImpact();
          }
        });
        
        _startImageStream();
        _startGuidanceTimer();
      }
    } catch (e) {
      setState(() {
        _debugInfo = 'Kamera hatasi: $e';
      });
    }
  }

  void _startGuidanceTimer() {
    _guidanceTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!mounted || _dateFound) {
        timer.cancel();
        return;
      }
      _provideGuidance();
    });
  }

  void _provideGuidance() {
    final now = DateTime.now();
    if (_lastGuidanceTime != null && now.difference(_lastGuidanceTime!).inSeconds < 5) {
      return;
    }
    _lastGuidanceTime = now;
    
    // Use distinct haptic patterns instead of TTS
    if (_framesWithoutText > 20) {
      // Double light buzz - "get closer"
      HapticFeedback.lightImpact();
      Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.lightImpact());
      _framesWithoutText = 0;
    } else if (_framesWithText > 30 && _detectedDates.isEmpty) {
      // Triple light buzz - "move slowly"
      HapticFeedback.lightImpact();
      Future.delayed(const Duration(milliseconds: 150), () => HapticFeedback.lightImpact());
      Future.delayed(const Duration(milliseconds: 300), () => HapticFeedback.lightImpact());
      _framesWithText = 0;
    }
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((image) async {
      _frameCount++;
      _evaluateAmbientLight(image);
      
      // In debug mode, always continue scanning. In normal mode, stop when date found.
      if (_isDetecting) return;
      if (!_showDebugOverlay && _dateFound) return;
      if (_frameCount % 3 != 0) return;

      _isDetecting = true;

      try {
        final stopwatch = Stopwatch()..start();
        
        // Track image dimensions
        _imageWidth = image.width;
        _imageHeight = image.height;
        
        final inputImage = _convertCameraImage(image);
        if (inputImage != null) {
          final recognizedText = await _textRecognizer.processImage(inputImage);
          
          stopwatch.stop();
          _lastProcessTime = stopwatch.elapsedMilliseconds.toDouble();
          _processedFrames++;
          
          if (mounted) {
            _textBlockCount = recognizedText.blocks.length;
            _textBlocks = recognizedText.blocks;
            
            if (recognizedText.text.isEmpty) {
              _framesWithoutText++;
              _framesWithText = 0;
            } else {
              _framesWithText++;
              _framesWithoutText = 0;
              _lastRecognizedText = recognizedText.text;
              
              // Haptic "Geiger Counter": vibrate when text is detected
              _triggerTextPresenceHaptic();
            }
            
            // Extract dates with their types
            final dateInfo = _extractDatesWithTypes(recognizedText.text);
            _detectedDates = dateInfo.keys.toList();
            _dateTypes = dateInfo;
            
            // Always update debug info
            setState(() {
              _debugInfo = 'Kare: $_frameCount | Islenen: $_processedFrames\n'
                  'Goruntu: ${_imageWidth}x${_imageHeight}\n'
                  'Islem suresi: ${_lastProcessTime.toStringAsFixed(0)}ms\n'
                  'Metin bloklari: $_textBlockCount\n'
                  'Tarih: ${_detectedDates.length} adet';
            });
            
            // Find expiry date (not production date)
            if (_detectedDates.isNotEmpty && !_dateFound) {
              // Look for expiry dates first (TETT, SKT, EXP, BB)
              String? expiryDateStr;
              String? productionDateStr;
              
              for (final entry in _dateTypes.entries) {
                if (entry.value == 'expiry') {
                  expiryDateStr = entry.key;
                } else if (entry.value == 'production') {
                  productionDateStr = entry.key;
                }
              }
              
              // If no labeled expiry, but we have multiple dates, pick the later one
              if (expiryDateStr == null && _detectedDates.length >= 2) {
                final dates = _detectedDates.map((d) => MapEntry(d, _parseDate(d))).where((e) => e.value != null).toList();
                if (dates.length >= 2) {
                  dates.sort((a, b) => a.value!.compareTo(b.value!));
                  expiryDateStr = dates.last.key;  // Later date is expiry
                  productionDateStr = dates.first.key;  // Earlier date is production
                }
              }
              
              // If still no expiry, use first date that's not marked as production
              if (expiryDateStr == null) {
                for (final d in _detectedDates) {
                  if (_dateTypes[d] != 'production') {
                    expiryDateStr = d;
                    break;
                  }
                }
              }
              
              if (expiryDateStr != null) {
                final expiryDate = _parseDate(expiryDateStr);
                
                if (expiryDate != null) {
                  // Confirmation logic - require seeing same date multiple times
                  if (_pendingDateStr == expiryDateStr) {
                    _dateConfirmationCount++;
                  } else {
                    _pendingDateStr = expiryDateStr;
                    _dateConfirmationCount = 1;
                  }
                  
                  // Update UI to show pending detection
                  setState(() {
                    _rawDateString = expiryDateStr ?? '';
                    _debugInfo = 'Tarih algilandi: $expiryDateStr\n'
                        'Onay: $_dateConfirmationCount/$_requiredConfirmations';
                  });
                  
                  // Only lock if we've seen the same date enough times
                  if (_dateConfirmationCount >= _requiredConfirmations && !_showDebugOverlay) {
                    // Store production date if found
                    if (productionDateStr != null) {
                      _foundProductionDate = _parseDate(productionDateStr);
                      _rawProductionDateString = productionDateStr;
                    }
                    
                    _foundExpiryDate = expiryDate;
                    _dateFound = true;
                    
                    // Capture snapshot BEFORE stopping stream
                    try {
                      final xFile = await _cameraController?.takePicture();
                      if (xFile != null) {
                        _capturedSnapshot = await xFile.readAsBytes();
                        await _prepareSnapshotOverlay(_capturedSnapshot!, xFile.path);
                        
                        // Analyze product with Gemini AI
                        _analyzeProductWithAI(expiryDateStr);
                      }
                    } catch (e) {
                      debugPrint('Snapshot capture failed: $e');
                    }
                    
                    await _cameraController?.stopImageStream();
                    try {
                      await _cameraController?.pausePreview();
                      _previewPaused = true;
                    } catch (e) {
                      debugPrint('Pause preview failed: $e');
                    }
                    // Cache normalized blocks from the live frame for reuse on snapshot overlay
                    final previewSize = _cameraController?.value.previewSize;
                    if (previewSize != null) {
                      _cacheResultBlocksForSnapshot(previewSize);
                    }
                    // Strong success haptic - no TTS needed
                    await HapticHelper.scanSuccess();
                    HapticFeedback.heavyImpact();
                  }
                  
                  setState(() {
                    _debugInfo = 'TARIH BULUNDU!\n'
                        'SKT: $expiryDateStr\n'
                        '${productionDateStr != null ? "ÜT: $productionDateStr\n" : ""}'
                        '${_getExpiryMessage(expiryDate)}';
                  });
                }
              }
            }
          }
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _debugInfo = 'Hata: $e';
          });
        }
      } finally {
        _isDetecting = false;
      }
    });
  }

  // Extract dates with their types (expiry vs production)
  Map<String, String> _extractDatesWithTypes(String text) {
    final dateTypes = <String, String>{};
    
    // Normalize text
    String normalized = text.toUpperCase();
    
    // EXPIRY DATE patterns (Son Kullanma Tarihi)
    // T.E.T.T, TETT = Tavsiye Edilen Tüketim Tarihi (Best Before)
    // SKT, S.K.T = Son Kullanma Tarihi
    // EXP = Expiry
    // BB, BBD = Best Before Date
    final expiryPatterns = [
      RegExp(r'T\.?E\.?T\.?T\.?[:\s]*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})', caseSensitive: false),
      RegExp(r'(?:SKT|S\.K\.T|S\.?K\.?T\.?)[:\s]*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})', caseSensitive: false),
      RegExp(r'(?:EXP|BB|BBD|BEST\s*BEFORE)[:\s]*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})', caseSensitive: false),
      RegExp(r'SON\s*KULLANMA[:\s]*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})', caseSensitive: false),
    ];
    
    // PRODUCTION DATE patterns (Üretim Tarihi)
    // ÜT, Ü.T = Üretim Tarihi
    // UT (OCR misread of ÜT)
    // PT, P.T = Production date (unlikely but possible)
    final productionPatterns = [
      RegExp(r'[ÜU]\.?T\.?[:\s]*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})', caseSensitive: false),
      RegExp(r'URETIM[:\s]*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})', caseSensitive: false),
      RegExp(r'PROD(?:UCTION)?[:\s]*(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})', caseSensitive: false),
    ];
    
    // Extract expiry dates
    for (final pattern in expiryPatterns) {
      for (final match in pattern.allMatches(normalized)) {
        final dateStr = match.group(0)!;
        // Extract just the date part
        final dateMatch = RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})').firstMatch(dateStr);
        if (dateMatch != null) {
          dateTypes[dateMatch.group(0)!] = 'expiry';
        }
      }
    }
    
    // Extract production dates
    for (final pattern in productionPatterns) {
      for (final match in pattern.allMatches(normalized)) {
        final dateStr = match.group(0)!;
        final dateMatch = RegExp(r'(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})').firstMatch(dateStr);
        if (dateMatch != null) {
          final dStr = dateMatch.group(0)!;
          // Don't override if already marked as expiry
          if (!dateTypes.containsKey(dStr)) {
            dateTypes[dStr] = 'production';
          }
        }
      }
    }
    
    // Also find any unlabeled dates
    final genericDatePattern = RegExp(r'\b(\d{1,2})[/.-](\d{1,2})[/.-](20\d{2})\b');
    for (final match in genericDatePattern.allMatches(text)) {
      final dateStr = match.group(0)!;
      if (!dateTypes.containsKey(dateStr)) {
        dateTypes[dateStr] = 'unknown';
      }
    }
    
    // Short year format
    final shortYearPattern = RegExp(r'\b(\d{2})[/.-](\d{2})[/.-](\d{2})\b');
    for (final match in shortYearPattern.allMatches(text)) {
      final dateStr = match.group(0)!;
      if (!dateTypes.containsKey(dateStr)) {
        dateTypes[dateStr] = 'unknown';
      }
    }
    
    return dateTypes;
  }

  DateTime? _parseDate(String dateStr) {
    try {
      String cleaned = dateStr.toUpperCase()
          .replaceAll(RegExp(r'SKT|S\.K\.T|EXP|BB|BBD|UFE'), '')
          .replaceAll(RegExp(r'[:\s]'), '')
          .trim();
      
      final formats = [
        RegExp(r'^(\d{2})[./-](\d{2})[./-](20\d{2})$'),
        RegExp(r'^(\d{2})[./-](\d{2})[./-](\d{2})$'),
        RegExp(r'^(\d{2})[./-](20\d{2})$'),
        RegExp(r'^(20\d{2})[./-](\d{2})[./-](\d{2})$'),
      ];
      
      for (final format in formats) {
        final match = format.firstMatch(cleaned);
        if (match != null) {
          if (match.groupCount == 3) {
            final g1 = int.parse(match.group(1)!);
            final g2 = int.parse(match.group(2)!);
            final g3 = int.parse(match.group(3)!);
            
            if (g1 > 2000) {
              return DateTime(g1, g2, g3);
            }
            
            int year = g3;
            if (year < 100) year += 2000;
            return DateTime(year, g2, g1);
          } else if (match.groupCount == 2) {
            final month = int.parse(match.group(1)!);
            final year = int.parse(match.group(2)!);
            return DateTime(year, month + 1, 0);
          }
        }
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  String _getExpiryMessage(DateTime expiryDate) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    final difference = expiry.difference(today).inDays;
    
    if (difference < 0) {
      final daysPast = -difference;
      if (daysPast == 1) return 'DIKKAT! Urunun son kullanma tarihi dun gecti!';
      if (daysPast < 7) return 'DIKKAT! Urunun son kullanma tarihi $daysPast gun once gecti!';
      if (daysPast < 30) return 'DIKKAT! Urunun son kullanma tarihi ${(daysPast / 7).floor()} hafta once gecti!';
      return 'DIKKAT! Urunun son kullanma tarihi ${(daysPast / 30).floor()} ay once gecti!';
    } else if (difference == 0) {
      return 'DIKKAT! Son kullanma tarihi bugun!';
    } else if (difference == 1) {
      return 'DIKKAT! Son kullanma tarihi yarin!';
    } else if (difference < 7) {
      return 'Son kullanma tarihine $difference gun kaldi.';
    } else if (difference < 30) {
      final weeks = (difference / 7).floor();
      final days = difference % 7;
      if (days == 0) return 'Son kullanma tarihine $weeks hafta kaldi.';
      return 'Son kullanma tarihine $weeks hafta $days gun kaldi.';
    } else if (difference < 365) {
      return 'Son kullanma tarihine yaklasik ${(difference / 30).floor()} ay kaldi.';
    } else {
      final years = (difference / 365).floor();
      final months = ((difference % 365) / 30).floor();
      if (months == 0) return 'Son kullanma tarihine $years yil kaldi.';
      return 'Son kullanma tarihine $years yil $months ay kaldi.';
    }
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final imageSize = Size(image.width.toDouble(), image.height.toDouble());
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: imageSize,
          rotation: InputImageRotation.rotation90deg,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      return null;
    }
  }

  bool _isExpired(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(date.year, date.month, date.day);
    return expiry.isBefore(today);
  }

  /// Analyze captured product image with Gemini AI
  Future<void> _analyzeProductWithAI(String detectedDate) async {
    if (_capturedSnapshot == null) return;
    
    try {
      debugPrint('=== STARTING PRODUCT ANALYSIS WITH AI ===');
      
      // Get user's shopping context for better recognition
      final userContext = _productContext.getContextForAI();
      
      debugPrint('User context: $userContext');
      
      // Call Gemini for detailed analysis with context
      final analysis = await _gemini.analyzeProductWithDate(
        _capturedSnapshot!,
        detectedDate,
        userContext: userContext.isNotEmpty ? userContext : null,
      );
      
      debugPrint('AI Analysis Result: $analysis');

      if (mounted && analysis.isNotEmpty) {
        setState(() {
          _geminiLatestAnalysis = analysis;
        });
        
        // Convert AI analysis to natural speech and announce it
        final speechText = _convertAnalysisToSpeech(analysis, detectedDate);
        debugPrint('TTS Speech text: $speechText');
        await _tts.speak(speechText);
      }
      
      // Extract and store product info for future context
      _storeProductContext(analysis, detectedDate);
      
      debugPrint('=== PRODUCT ANALYSIS COMPLETE ===');
    } catch (e) {
      debugPrint('Product analysis error: $e');
    }
  }

  /// Store analyzed product info in context for future scans
  void _storeProductContext(String analysis, String detectedDate) {
    try {
      // Parse the structured response
      final lines = analysis.split('\n').where((l) => l.trim().isNotEmpty).toList();
      
      String? productType;
      String? brand;
      
      for (final line in lines) {
        final lower = line.toLowerCase();
        if (lower.contains('ürün tipi:') || lower.contains('ürün:')) {
          productType = line.split(':').last.trim();
        } else if (lower.contains('marka:')) {
          brand = line.split(':').last.trim();
        }
      }
      
      // Add to context service
      _productContext.addProduct(
        brand: brand,
        productType: productType,
        productName: null, // Could extract from image if needed
        expiryDate: detectedDate,
      );
      
      // Log stats
      final stats = _productContext.getStats();
      debugPrint('Product context updated: $stats');
      
    } catch (e) {
      debugPrint('Error storing product context: $e');
    }
  }

  // Gemini analysis is triggered only once after expiry is confirmed (see _analyzeProductWithAI)

  /// Convert AI analysis response to natural Turkish speech
  String _convertAnalysisToSpeech(String analysis, String detectedDate) {
    try {
      // Parse the structured response
      final lines = analysis.split('\n').where((l) => l.trim().isNotEmpty).toList();
      
      String status = '';
      String timeRemaining = '';
      String productType = '';
      String brand = '';
      
      for (final line in lines) {
        final lower = line.toLowerCase();
        if (lower.contains('durum:')) {
          status = line.split(':').last.trim();
        } else if (lower.contains('süre:')) {
          timeRemaining = line.split(':').last.trim();
        } else if (lower.contains('ürün tipi:') || lower.contains('ürün:')) {
          productType = line.split(':').last.trim();
        } else if (lower.contains('marka:')) {
          brand = line.split(':').last.trim();
        }
      }
      
      // Build natural speech
      final speech = StringBuffer();
      
      // Brand and product type first
      if (brand.isNotEmpty && brand != 'Bulunamadı') {
        speech.write('$brand markası. ');
      }
      if (productType.isNotEmpty && productType != 'Bulunamadı') {
        speech.write('$productType. ');
      }
      
      // Safety status
      if (status.contains('Kullanılabilir')) {
        speech.write('Kullanılabilir. ');
      } else if (status.contains('Geçmiş')) {
        speech.write('Dikkat! Tarihi geçmiş. ');
      }
      
      // Time remaining/passed
      if (timeRemaining.isNotEmpty && timeRemaining != 'Bulunamadı') {
        speech.write('$timeRemaining. ');
      }
      
      // Add date for reference
      speech.write('Son kullanma tarihi: $detectedDate');
      
      return speech.toString();
      
    } catch (e) {
      debugPrint('Error converting analysis to speech: $e');
      // Fallback to raw analysis or basic message
      return analysis.isNotEmpty ? analysis : 'Son kullanma tarihi: $detectedDate';
    }
  }

  void _restartScanning() async {
    setState(() {
      _dateFound = false;
      _foundExpiryDate = null;
      _foundProductionDate = null;
      _capturedSnapshot = null;
      _resultTextBlocks = [];
      _resultBlocks = [];
      _rawDateString = '';
      _rawProductionDateString = '';
      _detectedDates = [];
      _dateTypes = {};
      _textBlocks = [];
      _lastRecognizedText = '';
      _framesWithText = 0;
      _framesWithoutText = 0;
      _pendingDateStr = null;
      _dateConfirmationCount = 0;
      _geminiLatestAnalysis = '';
      _debugInfo = 'Yeni tarama baslatiliyor...';
    });
    
    // Just haptic for restart, no TTS
    HapticFeedback.mediumImpact();
    try {
      await _cameraController?.resumePreview();
      _previewPaused = false;
    } catch (e) {
      debugPrint('Resume preview failed: $e');
    }
    
    // Restart the image stream
    _startImageStream();
    _startGuidanceTimer();
  }
  
  /// Haptic feedback when text is detected ("Geiger Counter" effect)
  void _triggerTextPresenceHaptic() {
    final now = DateTime.now();
    if (_lastHapticTime == null || 
        now.difference(_lastHapticTime!) >= _hapticThrottleDuration) {
      HapticFeedback.lightImpact();
      _lastHapticTime = now;
    }
  }
  
  /// Estimate ambient light and auto-toggle flashlight with hysteresis
  void _evaluateAmbientLight(CameraImage image) {
    final luma = _estimateLuma(image);
    final now = DateTime.now();
    if (_lastFlashToggleTime != null &&
        now.difference(_lastFlashToggleTime!) < _flashToggleCooldown) {
      return;  // Prevent rapid toggling
    }

    if (luma < _flashLumaLowThreshold && !_isFlashlightOn) {
      _enableFlashlight();
      _lastFlashToggleTime = now;
    } else if (luma > _flashLumaHighThreshold && _isFlashlightOn) {
      _disableFlashlight();
      _lastFlashToggleTime = now;
    }
  }

  /// Prepare overlay data using the captured snapshot so boxes align with the displayed image
  Future<void> _prepareSnapshotOverlay(Uint8List bytes, String imagePath) async {
    try {
      // Decode image size
      final decoded = await _decodeImage(bytes);
      _imageWidth = decoded.width;
      _imageHeight = decoded.height;

      // Re-run text recognition on the exact captured image for accurate boxes
      final input = InputImage.fromFilePath(imagePath);
      final recognized = await _textRecognizer.processImage(input);
      _resultTextBlocks = recognized.blocks;
    } catch (e) {
      debugPrint('Snapshot overlay prep failed: $e');
    }
  }

  /// Cache normalized blocks from the live frame for reuse on the snapshot overlay
  void _cacheResultBlocksForSnapshot(Size previewSize) {
    // Rotated dimensions used by ML Kit on the live stream
    final mlImageWidth = previewSize.height;
    final mlImageHeight = previewSize.width;
    if (mlImageWidth == 0 || mlImageHeight == 0) return;

    _resultBlocks = _textBlocks.map((block) {
      final bbox = block.boundingBox;
      final rect = Rect.fromLTWH(
        bbox.left / mlImageWidth,
        bbox.top / mlImageHeight,
        bbox.width / mlImageWidth,
        bbox.height / mlImageHeight,
      );
      return _ResultBlock(rect, block.text);
    }).toList();
  }

  Future<ui.Image> _decodeImage(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  /// Compute average luma (Y plane) using a sampled subset to stay fast
  double _estimateLuma(CameraImage image) {
    if (image.planes.isEmpty) return 0;
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return 0;

    int stride = (bytes.length / 4000).ceil();
    if (stride < 1) stride = 1;
    if (stride > 50) stride = 50;

    int sum = 0;
    int count = 0;
    for (int i = 0; i < bytes.length; i += stride) {
      sum += bytes[i];
      count++;
    }
    return count == 0 ? 0 : sum / count;
  }
  
  /// Enable flashlight (torch mode)
  Future<void> _enableFlashlight() async {
    if (_isFlashlightOn || _isDisposing) return;
    
    try {
      if (_cameraController != null && 
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isTakingPicture) {
        await _cameraController!.setFlashMode(FlashMode.torch);
        _isFlashlightOn = true;
        debugPrint('Flashlight enabled');
      }
    } catch (e) {
      // Device may not have flash, ignore silently
      debugPrint('Flashlight not available: $e');
    }
  }
  
  /// Disable flashlight
  Future<void> _disableFlashlight() async {
    if (!_isFlashlightOn || _isDisposing) return;
    
    try {
      if (_cameraController != null && 
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isTakingPicture) {
        await _cameraController!.setFlashMode(FlashMode.off);
        _isFlashlightOn = false;
        debugPrint('Flashlight disabled');
      }
    } catch (e) {
      debugPrint('Could not disable flashlight: $e');
    }
  }
  
  /// Toggle flashlight
  Future<void> _toggleFlashlight() async {
    // Manual toggle disables auto mode for the current state until ambient check flips it
    if (_isFlashlightOn) {
      await _disableFlashlight();
    } else {
      await _enableFlashlight();
    }
    setState(() {});
  }

  /// Compute where the camera preview is drawn on screen (using contain fit)
  Rect _previewRect(Size screenSize) {
    final previewSize = _cameraController?.value.previewSize;
    if (previewSize == null) return Rect.fromLTWH(0, 0, screenSize.width, screenSize.height);
    // Preview is already rotated to portrait (height is original width)
    final source = Size(previewSize.height, previewSize.width);
    final fitted = applyBoxFit(BoxFit.contain, source, screenSize);
    final left = (screenSize.width - fitted.destination.width) / 2;
    final top = (screenSize.height - fitted.destination.height) / 2;
    return Rect.fromLTWH(left, top, fitted.destination.width, fitted.destination.height);
  }

  /// Compute where the result snapshot is drawn on screen (contain fit using rotated source size)
  Rect _resultRect(Size screenSize) {
    if (_imageWidth == 0 || _imageHeight == 0) {
      return _previewRect(screenSize);
    }
    final source = Size(_imageWidth.toDouble(), _imageHeight.toDouble());
    final fitted = applyBoxFit(BoxFit.contain, source, screenSize);
    final left = (screenSize.width - fitted.destination.width) / 2;
    final top = (screenSize.height - fitted.destination.height) / 2;
    return Rect.fromLTWH(left, top, fitted.destination.width, fitted.destination.height);
  }

  @override
  void dispose() {
    _isDisposing = true;
    _guidanceTimer?.cancel();
    _accelerometerSubscription?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _disableFlashlight();  // Turn off flashlight when leaving
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  // Build AR-style text block overlays - positioned directly on camera feed
  List<Widget> _buildTextBlockOverlays(Rect previewRect, Size screenSize) {
    if (_textBlocks.isEmpty || _cameraController == null) return [];
    final previewSize = _cameraController!.value.previewSize;
    if (previewSize == null) return [];

    // Rotated dimensions (ML Kit works on portrait-rotated frame)
    final mlImageWidth = previewSize.height;  // 1080 after rotation
    final mlImageHeight = previewSize.width;  // 1920 after rotation

    final scaleX = previewRect.width / mlImageWidth;
    final scaleY = previewRect.height / mlImageHeight;
    final offsetLeft = previewRect.left;
    final offsetTop = previewRect.top;

    List<Widget> overlays = [];
    
    // Add debug info overlay showing coordinate system
    if (_showDebugOverlay) {
      overlays.add(
        Positioned(
          top: 120,
          left: 10,
          child: Container(
            padding: const EdgeInsets.all(6),
            color: Colors.black87,
            child: Text(
              'Screen: ${screenSize.width.toInt()}x${screenSize.height.toInt()}\n'
              'Preview: ${previewSize.width.toInt()}x${previewSize.height.toInt()}\n'
              'ML Image: ${mlImageWidth.toInt()}x${mlImageHeight.toInt()}\n'
              'Scale: ${scaleX.toStringAsFixed(2)}x${scaleY.toStringAsFixed(2)}',
              style: const TextStyle(color: Colors.lime, fontSize: 10, fontFamily: 'monospace'),
            ),
          ),
        ),
      );
    }
    
    for (final block in _textBlocks) {
      final bbox = block.boundingBox;
      
      // Check if this block contains a date pattern
      final blockText = block.text.toLowerCase();
      final containsDate = _detectedDates.any((date) {
        final digits = date.replaceAll(RegExp(r'[^\d]'), '');
        return blockText.contains(digits) || block.text.contains(date);
      });
      
      // Check for date-related keywords
      final hasDateKeyword = blockText.contains('skt') || 
                             blockText.contains('exp') || 
                             blockText.contains('bb') ||
                             blockText.contains('ut') ||
                             blockText.contains('tett') ||
                             blockText.contains('t.e.t.t') ||
                             RegExp(r'\d{2}[.:/]\d{2}[.:/]\d{2,4}').hasMatch(block.text);
      
      // In normal mode (not debug), only show date-related blocks
      if (!_showDebugOverlay && !containsDate && !hasDateKeyword) {
        continue;
      }
      
      // ML Kit bbox is already in rotated space, just scale to screen
      // But we need to mirror horizontally for front camera behavior
      // For back camera with 90° rotation, coords should map directly
      final screenLeft = offsetLeft + bbox.left * scaleX;
      final screenTop = offsetTop + bbox.top * scaleY;
      final screenWidth = bbox.width * scaleX;
      final screenHeight = bbox.height * scaleY;
      
      // Determine color based on content
      Color boxColor;
      Color borderColor;
      if (containsDate) {
        boxColor = Colors.green.withOpacity(0.3);
        borderColor = Colors.green;
      } else if (hasDateKeyword) {
        boxColor = Colors.orange.withOpacity(0.3);
        borderColor = Colors.orange;
      } else {
        boxColor = Colors.blue.withOpacity(0.15);
        borderColor = Colors.cyan.withOpacity(0.6);
      }
      
      // Clamp to valid screen bounds
      final left = screenLeft.clamp(0.0, screenSize.width - 10);
      final top = screenTop.clamp(0.0, screenSize.height - 10);
      final width = screenWidth.clamp(10.0, screenSize.width - left);
      final height = screenHeight.clamp(10.0, screenSize.height - top);
      
      // Main bounding box
      overlays.add(
        Positioned(
          left: left,
          top: top,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: boxColor,
              border: Border.all(color: borderColor, width: containsDate ? 3 : 1),
              borderRadius: BorderRadius.circular(4),
            ),
            // Debug: show raw coords
            child: _showDebugOverlay ? Align(
              alignment: Alignment.bottomRight,
              child: Container(
                padding: const EdgeInsets.all(2),
                color: Colors.black54,
                child: Text(
                  '${bbox.left.toInt()},${bbox.top.toInt()}',
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                ),
              ),
            ) : null,
          ),
        ),
      );
      
      // Add text label above the box for important matches
      if (containsDate || hasDateKeyword) {
        final labelTop = (top - 24).clamp(0.0, screenSize.height - 24);
        
        overlays.add(
          Positioned(
            left: left,
            top: labelTop,
            child: Container(
              constraints: BoxConstraints(maxWidth: screenSize.width - left - 10),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: containsDate ? Colors.green : Colors.orange,
                borderRadius: BorderRadius.circular(4),
                boxShadow: [BoxShadow(color: Colors.black45, blurRadius: 3)],
              ),
              child: Text(
                block.text.length > 30 ? '${block.text.substring(0, 30)}...' : block.text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      }
    }
    
    return overlays;
  }

  // Build AR overlays for the result screen - highlights where date was found
  List<Widget> _buildResultOverlays(Rect resultRect, Size screenSize) {
    // Always use ML Kit results from the captured snapshot image - not live stream
    if (_resultTextBlocks.isEmpty || _capturedSnapshot == null) return [];
    
    // Use captured image dimensions
    final mlImageWidth = _imageWidth.toDouble();
    final mlImageHeight = _imageHeight.toDouble();
    if (mlImageWidth == 0 || mlImageHeight == 0) return [];
    
    final scaleX = resultRect.width / mlImageWidth;
    final scaleY = resultRect.height / mlImageHeight;
    final offsetLeft = resultRect.left;
    final offsetTop = resultRect.top;
    
    List<Widget> overlays = [];
    
    for (final block in _resultTextBlocks) {
      final bbox = block.boundingBox;
      final rawText = block.text;
      final blockText = rawText.toLowerCase();

      final screenLeft = offsetLeft + bbox.left * scaleX;
      final screenTop = offsetTop + bbox.top * scaleY;
      final screenWidth = bbox.width * scaleX;
      final screenHeight = bbox.height * scaleY;
      
      // Only show date-related blocks
      final containsDate = _detectedDates.any((date) {
        final digits = date.replaceAll(RegExp(r'[^\d]'), '');
        if (blockText.contains(digits)) return true;
        return rawText.contains(date);
      });
      
      final hasDateKeyword = blockText.contains('skt') || 
                             blockText.contains('exp') || 
                             blockText.contains('tett') ||
                             blockText.contains('t.e.t.t') ||
                             blockText.contains('ut');
      
      if (!containsDate && !hasDateKeyword) continue;
      
      // Clamp to screen bounds
      final left = screenLeft.clamp(0.0, screenSize.width - 10);
      final top = screenTop.clamp(0.0, screenSize.height - 10);
      final width = screenWidth.clamp(10.0, screenSize.width - left);
      final height = screenHeight.clamp(10.0, screenSize.height - top);
      
      // Highlight box with glow effect for dates
      overlays.add(
        Positioned(
          left: left,
          top: top,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: containsDate ? Colors.green.withOpacity(0.4) : Colors.orange.withOpacity(0.3),
              border: Border.all(
                color: containsDate ? Colors.green : Colors.orange, 
                width: containsDate ? 4 : 2,
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: containsDate ? [
                BoxShadow(color: Colors.green.withOpacity(0.6), blurRadius: 12, spreadRadius: 2),
              ] : null,
            ),
          ),
        ),
      );
      
      // Text label above the box
      final labelTop = (top - 28).clamp(0.0, screenSize.height - 28);
      
      overlays.add(
        Positioned(
          left: left,
          top: labelTop,
          child: Container(
            constraints: BoxConstraints(maxWidth: screenSize.width - left - 10),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: containsDate ? Colors.green : Colors.orange,
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 4),
              ],
            ),
            child: Text(
                rawText.length > 30 ? '${rawText.substring(0, 30)}...' : rawText,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );
    }
    
    return overlays;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final previewRect = _previewRect(screenSize);
    final resultRect = _resultRect(screenSize);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onDoubleTap: _triggerAiAnalysis,  // Double-tap for AI
        onTap: () {
          // Single tap to start new scan if date found
          if (_dateFound) {
            _restartScanning();
          }
        },
        child: SafeArea(
          child: Stack(
            children: [
              // Camera preview with proper aspect ratio
              if (_isInitialized && !_dateFound && _cameraController != null && _cameraController!.value.isInitialized)
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          Positioned(
                            left: previewRect.left,
                            top: previewRect.top,
                            width: previewRect.width,
                            height: previewRect.height,
                            child: CameraPreview(_cameraController!),
                          ),
                        ],
                      );
                    },
                  ),
                )
              else if (_permissionDenied)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.camera_alt_outlined, size: 80, color: Colors.green),
                        const SizedBox(height: 24),
                        const Text('Kamera Izni Gerekli', style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 16),
                        Text(_debugInfo, style: const TextStyle(color: Colors.white70, fontSize: 16), textAlign: TextAlign.center),
                        const SizedBox(height: 32),
                        ElevatedButton.icon(
                          onPressed: () async {
                            final status = await Permission.camera.status;
                            if (status.isPermanentlyDenied) {
                              openAppSettings();
                            } else {
                              _checkAndRequestPermission();
                            }
                          },
                          icon: const Icon(Icons.settings),
                          label: const Text('Izin Ver', style: TextStyle(fontSize: 18)),
                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
                        ),
                      ],
                    ),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.green),
                    const SizedBox(height: 20),
                    Text(_debugInfo, style: const TextStyle(color: Colors.white), textAlign: TextAlign.center),
                  ],
                ),
              ),

            // Result overlay with tap-to-restart - shows snapshot with AR overlay
            if (_dateFound && _foundExpiryDate != null)
              Positioned.fill(
                child: GestureDetector(
                  onTap: _restartScanning,
                  child: Stack(
                    children: [
                      // Show captured snapshot as full background (no dimming)
                      if (_capturedSnapshot != null)
                        Positioned.fill(
                          child: Image.memory(
                            _capturedSnapshot!,
                            fit: BoxFit.contain,
                          ),
                        )
                      else
                        Container(color: Colors.black),
                        
                      // AR-style date highlight overlay on the image
                      ..._buildResultOverlays(resultRect, screenSize),
                      
                      // Result info panel at top
                      Positioned(
                        top: 60,
                        left: 12,
                        right: 12,
                          child: Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.9),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.green, width: 2),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Header
                                Row(
                                  children: [
                                    const Icon(Icons.check_circle, color: Colors.green, size: 24),
                                    const SizedBox(width: 8),
                                    const Expanded(
                                      child: Text('SON KULLANMA TARIHI', style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ),
                                const Divider(color: Colors.green, height: 16),
                                
                                // Expiry date - main result
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: _isExpired(_foundExpiryDate!) 
                                        ? Colors.red.withOpacity(0.2) 
                                        : Colors.green.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: _isExpired(_foundExpiryDate!) ? Colors.red : Colors.green,
                                      width: 2,
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.event_available,
                                            color: _isExpired(_foundExpiryDate!) ? Colors.red : Colors.green,
                                            size: 28,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${_foundExpiryDate!.day.toString().padLeft(2, '0')}.${_foundExpiryDate!.month.toString().padLeft(2, '0')}.${_foundExpiryDate!.year}',
                                            style: TextStyle(
                                              color: _isExpired(_foundExpiryDate!) ? Colors.red : Colors.white,
                                              fontSize: 32,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _getExpiryMessage(_foundExpiryDate!),
                                        style: TextStyle(
                                          color: _isExpired(_foundExpiryDate!) ? Colors.red : Colors.yellow,
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                        textAlign: TextAlign.center,
                                      ),
                                    ],
                                  ),
                                ),
                                
                                // Production date if found
                                if (_foundProductionDate != null) ...[
                                  const SizedBox(height: 10),
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.orange, width: 1),
                                    ),
                                    child: Row(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        const Icon(Icons.factory, color: Colors.orange, size: 20),
                                        const SizedBox(width: 8),
                                        const Text('Üretim: ', style: TextStyle(color: Colors.orange, fontSize: 14)),
                                        Text(
                                          '${_foundProductionDate!.day.toString().padLeft(2, '0')}.${_foundProductionDate!.month.toString().padLeft(2, '0')}.${_foundProductionDate!.year}',
                                          style: const TextStyle(color: Colors.orange, fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                                
                                // Debug info if enabled
                                if (_showDebugOverlay) ...[
                                  const SizedBox(height: 10),
                                  const Divider(color: Colors.grey, height: 1),
                                  const SizedBox(height: 6),
                                  Text(
                                    '🔍 Algilanan: $_rawDateString',
                                    style: const TextStyle(color: Colors.cyan, fontSize: 11, fontFamily: 'monospace'),
                                  ),
                                  Text(
                                    'Kare: $_frameCount | Blok: $_textBlockCount | ${_lastProcessTime.toStringAsFixed(0)}ms',
                                    style: const TextStyle(color: Colors.grey, fontSize: 10, fontFamily: 'monospace'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        
                        // Tap to restart button at bottom
                        Positioned(
                          bottom: 50,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(30),
                                boxShadow: [
                                  BoxShadow(color: Colors.green.withOpacity(0.5), blurRadius: 10, spreadRadius: 2),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: const [
                                  Icon(Icons.refresh, color: Colors.white, size: 24),
                                  SizedBox(width: 8),
                                  Text('Yeni Tarama', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        
                        // Back button on result screen too
                        Positioned(
                          top: 8,
                          left: 8,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.5),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back, size: 28),
                              color: Colors.white,
                              onPressed: () {
                                _tts.stop();
                                Navigator.of(context).pop();
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

            // AR-style text block overlays - show in debug mode OR when dates detected
            if (_isInitialized && !_dateFound && (_showDebugOverlay || _detectedDates.isNotEmpty))
              ..._buildTextBlockOverlays(previewRect, screenSize),

            if (_isInitialized && !_dateFound)
              Positioned(
                bottom: 40,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(30)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: _framesWithText > 0 ? Colors.green : Colors.white)),
                        const SizedBox(width: 12),
                        Text(_framesWithText > 0 ? 'Metin algilaniyor...' : 'Tarih araniyor...', style: const TextStyle(color: Colors.white, fontSize: 18)),
                      ],
                    ),
                  ),
                ),
              ),

            // Header bar at top - only show when not showing result
            if (!_dateFound)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(60, 16, 16, 16),
                  color: Colors.black.withOpacity(0.7),
                  child: Semantics(
                    liveRegion: true,
                    child: const Text(
                      'Son kullanma tarihini kameraya gosterin',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),

            // Back button - always visible
            Positioned(
              top: 8,
              left: 8,
              child: Semantics(
                label: 'Geri',
                button: true,
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.arrow_back, size: 28),
                    color: Colors.white,
                    onPressed: () {
                      _tts.stop();
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
            ),
            
            // Flashlight toggle button
            Positioned(
              top: 8,
              right: 8,
              child: Semantics(
                label: _isFlashlightOn ? 'Flaş kapalı' : 'Flaş açık',
                button: true,
                child: Container(
                  decoration: BoxDecoration(
                    color: _isFlashlightOn ? Colors.amber : Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: IconButton(
                    icon: Icon(
                      _isFlashlightOn ? Icons.flash_on : Icons.flash_off,
                      size: 28,
                    ),
                    color: Colors.white,
                    onPressed: _toggleFlashlight,
                  ),
                ),
              ),
            ),
            

            Positioned(
              bottom: 30,
              right: 20,
              child: GestureDetector(
                onTap: () => setState(() => _showDebugOverlay = !_showDebugOverlay),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: _showDebugOverlay ? Colors.green : Colors.grey.withOpacity(0.7), borderRadius: BorderRadius.circular(30)),
                  child: const Icon(Icons.bug_report, color: Colors.white, size: 30),
                ),
              ),
            ),
            
            // Compact debug info panel at bottom (not covering camera)
            if (_showDebugOverlay && !_dateFound)
              Positioned(
                bottom: 100,
                left: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.green, width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '📊 Blok: $_textBlockCount | ⏱ ${_lastProcessTime.toStringAsFixed(0)}ms',
                            style: const TextStyle(color: Colors.green, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '📅 Tarih: ${_detectedDates.length}',
                            style: TextStyle(
                              color: _detectedDates.isNotEmpty ? Colors.yellow : Colors.grey,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      // Show dates with their types
                      if (_detectedDates.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        ..._dateTypes.entries.map((entry) {
                          final dateStr = entry.key;
                          final dateType = entry.value;
                          Color color;
                          String label;
                          IconData icon;
                          
                          switch (dateType) {
                            case 'expiry':
                              color = Colors.green;
                              label = 'SKT';
                              icon = Icons.event_available;
                              break;
                            case 'production':
                              color = Colors.orange;
                              label = 'ÜT';
                              icon = Icons.factory;
                              break;
                            default:
                              color = Colors.grey;
                              label = '?';
                              icon = Icons.help_outline;
                          }
                          
                          return Container(
                            margin: const EdgeInsets.only(bottom: 4),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: color.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: color, width: 1),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon, color: color, size: 16),
                                const SizedBox(width: 4),
                                Text(
                                  '$label: $dateStr',
                                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                      const SizedBox(height: 6),
                      // Product context stats
                      Builder(
                        builder: (context) {
                          final stats = _productContext.getStats();
                          if (stats['totalScanned'] > 0) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: Colors.purple.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.purple, width: 1),
                              ),
                              child: Text(
                                '🧠 Öğrenilen: ${stats['uniqueBrands']} marka, ${stats['uniqueTypes']} tip (${stats['totalScanned']} ürün)',
                                style: const TextStyle(color: Colors.purple, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 50),
                        child: SingleChildScrollView(
                          child: Text(
                            _lastRecognizedText.isEmpty ? 'Metin bekleniyor...' : _lastRecognizedText,
                            style: TextStyle(
                              color: _lastRecognizedText.isEmpty ? Colors.grey : Colors.cyan,
                              fontSize: 9,
                              fontFamily: 'monospace',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // Gemini analysis display after date is found
              if (_geminiLatestAnalysis.isNotEmpty && _dateFound)
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.deepPurple.withOpacity(0.95),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.purpleAccent, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Colors.white, size: 24),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _geminiLatestAnalysis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              // AI analyzing indicator
              if (_isAiAnalyzing)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withOpacity(0.7),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                          SizedBox(height: 20),
                          Text(
                            'Yapay Zeka Analizi...',
                            style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Lütfen bekleyin',
                            style: TextStyle(color: Colors.white70, fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultBlock {
  final Rect rect;  // normalized (0-1) rect relative to ML image
  final String text;
  _ResultBlock(this.rect, this.text);
}
