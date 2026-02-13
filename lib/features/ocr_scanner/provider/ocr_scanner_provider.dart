import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';
import '../../../core/models/expiry_date.dart';
import '../../../core/services/ml_kit_service.dart';
import '../../../core/utils/date_parser.dart';

class OcrScannerProvider extends ChangeNotifier {
  final MLKitService _mlKitService = MLKitService();

  bool _isScanning = false;
  bool _isProcessing = false;
  ExpiryDate? _detectedExpiryDate;
  List<String> _detectedText = [];
  String? _error;
  
  // Haptic feedback throttling ("Geiger Counter")
  DateTime? _lastHapticTime;
  static const Duration _hapticThrottleDuration = Duration(milliseconds: 500);
  
  // Result stabilization (debouncing)
  int _stabilityCounter = 0;
  String? _pendingDate;
  static const int _requiredStabilityFrames = 3;
  
  // Smart silence (noise reduction)
  DateTime? _scanStartTime;
  DateTime? _lastHintSpokenTime;
  static const Duration _scanTimeoutBeforeHint = Duration(seconds: 5);
  static const Duration _hintCooldown = Duration(seconds: 8);
  
  // Camera controller reference for flashlight
  CameraController? _cameraController;

  bool get isScanning => _isScanning;
  bool get isProcessing => _isProcessing;
  ExpiryDate? get detectedExpiryDate => _detectedExpiryDate;
  List<String> get detectedText => _detectedText;
  String? get error => _error;
  
  /// Set camera controller for flashlight control
  void setCameraController(CameraController? controller) {
    _cameraController = controller;
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
  
  /// Heavy haptic feedback when date is confirmed
  void _triggerDateConfirmedHaptic() {
    HapticFeedback.heavyImpact();
  }
  
  /// Turn flashlight on
  Future<void> _enableFlashlight() async {
    try {
      if (_cameraController != null && 
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isTakingPicture) {
        await _cameraController!.setFlashMode(FlashMode.torch);
      }
    } catch (e) {
      // Device may not have flash, ignore silently
      debugPrint('Flashlight not available: $e');
    }
  }
  
  /// Turn flashlight off
  Future<void> _disableFlashlight() async {
    try {
      if (_cameraController != null && 
          _cameraController!.value.isInitialized &&
          !_cameraController!.value.isTakingPicture) {
        await _cameraController!.setFlashMode(FlashMode.off);
      }
    } catch (e) {
      debugPrint('Could not disable flashlight: $e');
    }
  }

  void startScanning() {
    _isScanning = true;
    _error = null;
    _scanStartTime = DateTime.now();
    _stabilityCounter = 0;
    _pendingDate = null;
    _lastHintSpokenTime = null;
    // No TTS - haptic feedback in UI
    
    // Turn on flashlight for better OCR
    _enableFlashlight();
    
    notifyListeners();
  }

  void stopScanning() {
    _isScanning = false;
    
    // Turn off flashlight
    _disableFlashlight();
    
    notifyListeners();
  }

  Future<void> processImage(InputImage inputImage) async {
    if (_isProcessing) return;

    _isProcessing = true;
    _error = null;
    notifyListeners();

    try {
      // Recognize text using ML Kit
      final recognizedText = await _mlKitService.recognizeText(inputImage);

      if (recognizedText == null) {
        // Smart silence: Don't speak on every failed frame
        _handleNoTextDetected();
        return;
      }

      // Extract text blocks
      final textBlocks = _mlKitService.extractTextBlocks(recognizedText);
      _detectedText = textBlocks;
      
      // Haptic "Geiger Counter": vibrate when any text is found
      if (textBlocks.isNotEmpty) {
        _triggerTextPresenceHaptic();
      }

      // Parse expiry date from text
      final expiryDate = DateParser.parseExpiryDate(textBlocks);

      if (expiryDate != null) {
        // Result stabilization: require consistent readings
        final currentDateString = expiryDate.rawDateString;
        
        if (currentDateString == _pendingDate) {
          _stabilityCounter++;
        } else {
          _stabilityCounter = 1;
          _pendingDate = currentDateString;
        }
        
        // Only confirm when stable for required frames
        if (_stabilityCounter >= _requiredStabilityFrames) {
          _detectedExpiryDate = expiryDate;
          
          // Heavy haptic to confirm date found - no TTS
          _triggerDateConfirmedHaptic();
          
          // Auto-stop scanning after successful detection
          stopScanning();
        }
      } else {
        // Smart silence: provide helpful hint after timeout
        _handleNoDateFound(textBlocks);
      }
    } catch (e) {
      _error = 'Hata: ${e.toString()}';
      // No TTS for errors - haptic feedback only
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }
  
  /// Handle case when no text is detected (Smart Silence)
  void _handleNoTextDetected() {
    // Reset stability counter when no text found
    _stabilityCounter = 0;
    _pendingDate = null;
    
    // Don't speak anything - just let the user continue scanning
    // The Geiger Counter haptics will guide them to text
  }
  
  /// Handle case when text is found but no date (Smart Silence)
  Future<void> _handleNoDateFound(List<String> textBlocks) async {
    // Reset stability counter
    _stabilityCounter = 0;
    _pendingDate = null;
    
    if (textBlocks.isEmpty) return;
    
    final now = DateTime.now();
    
    // Check if we should provide a helpful hint
    final scanDuration = _scanStartTime != null 
        ? now.difference(_scanStartTime!) 
        : Duration.zero;
    
    final timeSinceLastHint = _lastHintSpokenTime != null 
        ? now.difference(_lastHintSpokenTime!) 
        : _hintCooldown; // Allow first hint
    
    // Conditions for hint:
    // 1. Text is present (we see something)
    // 2. Scanning for more than 5 seconds
    // 3. Haven't given hint in the last 8 seconds
    if (scanDuration >= _scanTimeoutBeforeHint && 
        timeSinceLastHint >= _hintCooldown) {
      _lastHintSpokenTime = now;
      // No TTS - haptic patterns guide the user instead
    }
  }

  /// Store a found date directly (used by continuous scanning)
  Future<void> processFoundDate(DateTime date) async {
    _isProcessing = true;
    notifyListeners();
    
    try {
      final formattedDate = '${date.day}.${date.month}.${date.year}';
      _detectedExpiryDate = ExpiryDate.fromDate(date, formattedDate);
      _detectedText = [formattedDate];
      _error = null;
    } catch (e) {
      _error = 'Tarih işlenirken hata: ${e.toString()}';
    } finally {
      _isProcessing = false;
      notifyListeners();
    }
  }

  void clearResult() {
    _detectedExpiryDate = null;
    _detectedText = [];
    _error = null;
    _stabilityCounter = 0;
    _pendingDate = null;
    _scanStartTime = null;
    _lastHintSpokenTime = null;
    notifyListeners();
  }

  @override
  void dispose() {
    // Ensure flashlight is off
    _disableFlashlight();
    _mlKitService.dispose();
    super.dispose();
  }
}
