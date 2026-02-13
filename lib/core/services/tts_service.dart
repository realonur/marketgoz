import 'dart:async';
import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';

class TTSService {
  static final TTSService _instance = TTSService._internal();
  factory TTSService() => _instance;
  TTSService._internal();

  final FlutterTts _flutterTts = FlutterTts();
  bool _isInitialized = false;
  String? _selectedVoice;
  
  // Completer for waiting on speech completion
  Completer<void>? _speechCompleter;

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Set Turkish language
    await _flutterTts.setLanguage('tr-TR');
    
    // Try to find a good Turkish voice
    await _selectBestTurkishVoice();
    
    // iOS-specific settings for better quality
    if (Platform.isIOS) {
      await _flutterTts.setSharedInstance(true);
      await _flutterTts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.allowBluetooth,
          IosTextToSpeechAudioCategoryOptions.allowBluetoothA2DP,
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
    
    // Optimal speech settings for Turkish
    await _flutterTts.setSpeechRate(Platform.isIOS ? 0.45 : 0.4); // Slightly slower for clarity
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0); // Natural pitch
    
    // Set up completion handler
    _flutterTts.setCompletionHandler(() {
      _speechCompleter?.complete();
      _speechCompleter = null;
    });
    
    _flutterTts.setErrorHandler((error) {
      print('TTS Error: $error');
      _speechCompleter?.complete();
      _speechCompleter = null;
    });

    _isInitialized = true;
  }
  
  Future<void> _selectBestTurkishVoice() async {
    try {
      final voices = await _flutterTts.getVoices;
      if (voices == null) return;
      
      final voiceList = List<Map<dynamic, dynamic>>.from(voices);
      
      // Filter Turkish voices
      final turkishVoices = voiceList.where((voice) {
        final locale = voice['locale']?.toString().toLowerCase() ?? '';
        final name = voice['name']?.toString().toLowerCase() ?? '';
        return locale.contains('tr') || name.contains('turk') || name.contains('yelda') || name.contains('cem');
      }).toList();
      
      if (turkishVoices.isNotEmpty) {
        // Prefer enhanced/premium voices
        final premiumVoice = turkishVoices.firstWhere(
          (v) {
            final name = v['name']?.toString().toLowerCase() ?? '';
            return name.contains('premium') || name.contains('enhanced') || name.contains('compact');
          },
          orElse: () => turkishVoices.first,
        );
        
        _selectedVoice = premiumVoice['name']?.toString();
        if (_selectedVoice != null) {
          await _flutterTts.setVoice({'name': _selectedVoice!, 'locale': 'tr-TR'});
        }
      }
    } catch (e) {
      // Fall back to default if voice selection fails
      print('Voice selection error: $e');
    }
  }

  Future<void> speak(String text) async {
    print('=== TTS SPEAK CALLED ===');
    print('Text to speak: $text');
    print('Text length: ${text.length}');
    
    if (!_isInitialized) {
      print('TTS not initialized, initializing...');
      await initialize();
    }
    
    // Create completer to wait for speech to finish
    _speechCompleter = Completer<void>();
    
    print('Calling flutter_tts.speak()...');
    final result = await _flutterTts.speak(text);
    print('flutter_tts.speak() returned: $result');
    
    // Wait for speech to complete (with timeout)
    print('Waiting for speech to complete...');
    await _speechCompleter?.future.timeout(
      const Duration(seconds: 60),
      onTimeout: () {
        print('TTS TIMEOUT - speech took too long');
        _speechCompleter = null;
      },
    );
    print('=== TTS SPEAK FINISHED ===');
  }

  Future<void> stop() async {
    await _flutterTts.stop();
  }

  /// Stops current speech and clears any queued announcements
  /// Call this when user makes any interaction to prevent stale TTS
  Future<void> clearAndSpeak(String text) async {
    await stop();
    await speak(text);
  }

  /// Just clear/stop without speaking anything new
  Future<void> cancelAll() async {
    await stop();
  }

  Future<void> announceProductFound(String productName, double price) async {
    final message = 'Ürün bulundu. $productName. Fiyat: ${_formatPrice(price)}';
    await speak(message);
  }

  Future<void> announceProductNotFound() async {
    await speak('Ürün veritabanında bulunamadı. Lütfen tekrar deneyin.');
  }

  Future<void> announceExpiryDate(String statusMessage) async {
    await speak('Son kullanma tarihi durumu: $statusMessage');
  }

  Future<void> announceScanResult({
    required String productName,
    required String brand,
    required double price,
    String? expiryStatus,
  }) async {
    final message = StringBuffer();
    message.write('Ürün: $brand $productName. ');
    message.write('Fiyat: ${_formatPrice(price)}. ');
    
    if (expiryStatus != null) {
      message.write(expiryStatus);
    }

    await speak(message.toString());
  }

  Future<void> announceError(String error) async {
    await speak('Hata: $error');
  }

  Future<void> announceScanningMode(String mode) async {
    final message = mode == 'barcode'
        ? 'Barkod tarama modu. Kamerayı ürün barkoduna doğru tutun.'
        : 'Son kullanma tarihi tarama modu. Kamerayı ürün üzerindeki tarihe doğru tutun.';
    await speak(message);
  }

  String _formatPrice(double price) {
    final lira = price.floor();
    final kurus = ((price - lira) * 100).round();
    
    if (kurus == 0) {
      return '$lira lira';
    } else {
      return '$lira lira $kurus kuruş';
    }
  }

  void dispose() {
    _flutterTts.stop();
  }
}
