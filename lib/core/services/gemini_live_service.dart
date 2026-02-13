import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:http/http.dart' as http;

/// Real-time guidance service using Gemini Live API
/// Provides directional audio guidance to help users find expiry dates
class GeminiLiveService {
  static final GeminiLiveService _instance = GeminiLiveService._internal();
  factory GeminiLiveService() => _instance;
  GeminiLiveService._internal();

  // TODO: Set your Gemini API key here or use an environment variable
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String _model = 'gemini-2.5-flash-native-audio-preview-12-2025';  // Try experimental model instead
  
  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isSessionActive = false;
  String _connectionStatus = 'Bağlantı yok';
  
  // Audio player for Gemini's native voice
  final AudioPlayer _audioPlayer = AudioPlayer();
  List<int> _audioBuffer = [];
  bool _isPlayingAudio = false;
  
  // Callbacks
  Function(String)? onTextResponse;
  Function(Uint8List)? onAudioResponse;
  Function(String)? onGuidance;  // Directional guidance callback
  Function()? onDateFound;
  Function(String)? onError;
  Function(String)? onStatusChange;  // Connection status callback
  
  // Throttling
  DateTime? _lastFrameSent;
  static const Duration _frameInterval = Duration(milliseconds: 3000);  // Send every 3 seconds
  
  /// System instruction for real-time guidance
  static const String _systemInstruction = '''Sen görme engelli kullanıcılara yardımcı olan bir market asistanısın.
Görevin: Kullanıcının kamerasını ürün üzerindeki son kullanma tarihine (SKT) yönlendirmek.

ÜRÜN PAKETLERİNDE TARİH NEREDE OLUR:
- Genellikle paketin üst kısmında veya yan tarafında
- Kapak veya kapatma yerinin yakınında
- Barkodun yanında veya altında
- "SKT", "Son Kullanma", "EXP", "BB" yazılarının yanında
- Tarih formatları: GG.AA.YYYY veya AA/YY şeklinde

YÖNLENDİRME KURALLARI:
- Çok kısa ve net komutlar ver (2-4 kelime)
- Türkçe konuş, samimi ol
- Ürün görünmüyorsa: "Ürünü göster"
- Ürün görünüyorsa ama tarih yoksa: "Paketi çevir" veya "Yukarı bak" veya "Kapağa bak"
- Metin görünce ama tarih değilse: "Biraz sola" veya "Biraz sağa"
- Tarih gördüğünde: "Tarih buldum!" ve tarihi sesli oku
- Bulanıksa: "Sabit tut" veya "Biraz uzaklaş"

YÖN KOMUTLARI:
- "Sola kaydır", "Sağa kaydır"
- "Yukarı çık", "Aşağı in"
- "Yaklaş", "Uzaklaş"
- "Paketi çevir", "Kapağa bak"
- "Sabit tut", "İyi gidiyorsun"

ÖNEMLİ: Kısa, net ve cesaretlendirici ol. Her 2-3 saniyede bir komut ver.''';

  /// Connect to Live API
  Future<bool> connect() async {
    if (_isConnected) {
      debugPrint('Already connected');
      return true;
    }
    
    // First, test if the API key works with a simple REST call
    debugPrint('🔍 Testing API key with REST endpoint...');
    try {
      final testUrl = 'https://generativelanguage.googleapis.com/v1beta/models?key=$_apiKey';
      final response = await http.get(Uri.parse(testUrl));
      debugPrint('REST API test status: ${response.statusCode}');
      debugPrint('REST API response (first 200 chars): ${response.body.substring(0, response.body.length > 200 ? 200 : response.body.length)}...');
      
      if (response.statusCode != 200) {
        debugPrint('❌ API key validation failed - status ${response.statusCode}');
        debugPrint('Response: ${response.body}');
        _connectionStatus = 'API anahtarı geçersiz';
        onStatusChange?.call(_connectionStatus);
        return false;
      }
      debugPrint('✅ API key is valid');
    } catch (e) {
      debugPrint('⚠️ Could not validate API key: $e');
    }
    
    try {
      _connectionStatus = 'Bağlanıyor...';
      onStatusChange?.call(_connectionStatus);
      
      final wsUrl = 'wss://generativelanguage.googleapis.com/ws/google.ai.generativelanguage.v1alpha.GenerativeService.BidiGenerateContent?key=$_apiKey';
      
      debugPrint('Connecting to Gemini Live API...');
      debugPrint('URL: $wsUrl');
      debugPrint('API Key (first 20 chars): ${_apiKey.substring(0, 20)}...');
      debugPrint('API Key length: ${_apiKey.length}');
      
      _channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      debugPrint('🔌 WebSocket connection initiated');
      
      // Listen for responses
      _channel!.stream.listen(
        _handleMessage,
        onError: (error, stackTrace) {
          debugPrint('❌ WebSocket error: $error');
          debugPrint('Stack trace: $stackTrace');
          _connectionStatus = 'Hata: $error';
          onStatusChange?.call(_connectionStatus);
          onError?.call('Bağlantı hatası: $error');
          _isConnected = false;
          _isSessionActive = false;
        },
        onDone: () {
          debugPrint('🔴 WebSocket closed (onDone called)');
          debugPrint('Was session active: $_isSessionActive');
          debugPrint('Was connected: $_isConnected');
          
          // Try to get close code/reason if available
          try {
            final closeCode = _channel?.closeCode;
            final closeReason = _channel?.closeReason;
            debugPrint('Close code: $closeCode');
            debugPrint('Close reason: $closeReason');
          } catch (e) {
            debugPrint('Could not get close details: $e');
          }
          
          _connectionStatus = 'Bağlantı kapandı';
          onStatusChange?.call(_connectionStatus);
          _isConnected = false;
          _isSessionActive = false;
        },
        cancelOnError: false,
      );
      
      debugPrint('✅ WebSocket stream listener attached');
      
      _isConnected = true;
      _connectionStatus = 'Bağlandı, kurulum yapılıyor...';
      onStatusChange?.call(_connectionStatus);
      
      // Start session with setup message
      await _sendSetupMessage();
      
      debugPrint('Live API connection successful');
      return true;
    } catch (e) {
      debugPrint('Failed to connect to Live API: $e');
      _connectionStatus = 'Bağlantı hatası: $e';
      onStatusChange?.call(_connectionStatus);
      onError?.call('Bağlantı kurulamadı: $e');
      _isConnected = false;
      return false;
    }
  }
  
  /// Send initial setup message
  Future<void> _sendSetupMessage() async {
    final setup = {
      'setup': {
        'model': 'models/$_model',
        'generationConfig': {
          'responseModalities': ['AUDIO'],  // Only AUDIO, not TEXT
        },
        'systemInstruction': {
          'parts': [
            {'text': _systemInstruction}
          ]
        }
      }
    };
    
    debugPrint('📝 Setup object structure:');
    debugPrint('  - model: ${setup['setup']?['model']}');
    final config = (setup['setup'] as Map?)?['generationConfig'] as Map?;
    debugPrint('  - responseModalities: ${config?['responseModalities']}');
    debugPrint('  - systemInstruction length: ${_systemInstruction.length} chars');
    
    final setupJson = jsonEncode(setup);
    debugPrint('📤 Sending setup message:');
    debugPrint('Setup JSON (${setupJson.length} chars): ${setupJson.substring(0, setupJson.length > 500 ? 500 : setupJson.length)}${setupJson.length > 500 ? "..." : ""}');
    
    _channel?.sink.add(setupJson);
    debugPrint('✅ Setup message sent to WebSocket');
    _connectionStatus = 'Kurulum bekleniyor...';
    onStatusChange?.call(_connectionStatus);
    
    // Don't mark as active yet - wait for setupComplete
  }
  
  /// Handle incoming messages from Live API
  void _handleMessage(dynamic message) {
    try {
      debugPrint('📥 Raw message received (${message.toString().length} chars)');
      
      // Handle both String and Uint8List (binary) messages
      late String messageStr;
      if (message is String) {
        messageStr = message;
      } else if (message is List<int>) {
        // Decode binary data to UTF-8 string
        messageStr = utf8.decode(message);
        debugPrint('📦 Decoded binary message to UTF-8');
      } else {
        debugPrint('❌ Unknown message type: ${message.runtimeType}');
        return;
      }
      
      debugPrint('Message preview: ${messageStr.substring(0, messageStr.length > 200 ? 200 : messageStr.length)}${messageStr.length > 200 ? "..." : ""}');
      
      final data = jsonDecode(messageStr);
      debugPrint('📋 Parsed JSON keys: ${data.keys.toList()}');
      
      // Check for setup complete
      if (data['setupComplete'] != null) {
        debugPrint('✅ Session setup complete! setupComplete = ${data['setupComplete']}');
        _isSessionActive = true;
        _connectionStatus = 'Bağlandı ✓';
        onStatusChange?.call(_connectionStatus);
        
        // Send initial prompt to start guidance (fire and forget)
        debugPrint('📨 Sending initial guidance prompt...');
        sendText('Merhabalar! Türkçe rehberlik ver. Kamerayı bana göster. Ürün paketi nerede? Lütfen kamerayı paketin üzerine yönelt ve son kullanma tarihini bulmakta bana yardım et. TÜM CEVAPLARINI TÜRKÇE VER!');
        return;
      }
      
      // Check for errors
      if (data['error'] != null) {
        final error = data['error'];
        debugPrint('❌ Live API error object: $error');
        debugPrint('Error message: ${error['message']}');
        debugPrint('Error code: ${error['code']}');
        debugPrint('Error status: ${error['status']}');
        _connectionStatus = 'Hata: ${error['message'] ?? error}';
        onStatusChange?.call(_connectionStatus);
        onError?.call('API hatası: ${error['message'] ?? error}');
        return;
      }
      
      // Check for server content (response)
      final serverContent = data['serverContent'];
      if (serverContent != null) {
        debugPrint('🔊 Received serverContent from Gemini');
        final modelTurn = serverContent['modelTurn'];
        if (modelTurn != null) {
          final parts = modelTurn['parts'] as List?;
          if (parts != null) {
            for (final part in parts) {
              // Text response
              if (part['text'] != null) {
                final text = part['text'] as String;
                debugPrint('Guidance text: $text');
                onTextResponse?.call(text);
                onGuidance?.call(text);
                
                // Check if date was found
                if (text.contains('TARİH BULDUM') || text.contains('tarih buldum')) {
                  onDateFound?.call();
                }
              }
              
              // Audio response - play Gemini's native voice
              if (part['inlineData'] != null) {
                final inlineData = part['inlineData'];
                final mimeType = inlineData['mimeType'] as String?;
                final audioData = inlineData['data'] as String?;
                
                if (audioData != null && mimeType != null && mimeType.contains('audio')) {
                  final audioBytes = base64Decode(audioData);
                  _audioBuffer.addAll(audioBytes);
                  onAudioResponse?.call(Uint8List.fromList(audioBytes));
                }
              }
            }
          }
        }
        
        // Check if turn is complete - play buffered audio
        if (serverContent['turnComplete'] == true) {
          debugPrint('Turn complete');
          if (_audioBuffer.isNotEmpty) {
            _playBufferedAudio();
          }
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Error parsing Live API message: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('Raw message that caused error: $message');
    }
  }
  
  /// Send a camera frame for analysis
  Future<void> sendFrame(Uint8List imageBytes) async {
    if (!_isConnected || !_isSessionActive) {
      debugPrint('Not connected or session not active');
      return;
    }
    
    // Throttle frame sending
    final now = DateTime.now();
    if (_lastFrameSent != null && 
        now.difference(_lastFrameSent!) < _frameInterval) {
      return;  // Skip this frame
    }
    _lastFrameSent = now;
    
    try {
      // Compress image for faster transmission
      final compressed = await _compressFrame(imageBytes);
      final base64Image = base64Encode(compressed);
      
      // Send as realtime input
      final message = {
        'realtimeInput': {
          'mediaChunks': [
            {
              'mimeType': 'image/jpeg',
              'data': base64Image
            }
          ]
        }
      };
      
      _channel?.sink.add(jsonEncode(message));
      debugPrint('📤 Frame sent (${compressed.length} bytes, session active: $_isSessionActive)');
    } catch (e, stackTrace) {
      debugPrint('❌ Error sending frame: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }
  
  /// Send a text prompt (for asking specific questions)
  Future<void> sendText(String text) async {
    if (!_isConnected || !_isSessionActive) return;
    
    final message = {
      'clientContent': {
        'turns': [
          {
            'role': 'user',
            'parts': [
              {'text': text}
            ]
          }
        ],
        'turnComplete': true
      }
    };
    
    _channel?.sink.add(jsonEncode(message));
    debugPrint('Text sent: $text');
  }
  
  /// Compress frame for transmission
  Future<Uint8List> _compressFrame(Uint8List imageBytes) async {
    try {
      return await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 640,   // Better quality for guidance
        minHeight: 640,
        quality: 70,     // Better quality for reading text
        format: CompressFormat.jpeg,
      );
    } catch (e) {
      return imageBytes;
    }
  }
  
  /// Play buffered audio from Gemini
  Future<void> _playBufferedAudio() async {
    if (_audioBuffer.isEmpty || _isPlayingAudio) return;
    
    _isPlayingAudio = true;
    try {
      final audioData = Uint8List.fromList(_audioBuffer);
      _audioBuffer.clear();
      
      // Gemini returns audio/pcm at 24kHz 16-bit mono
      // We need to wrap it in a WAV header for playback
      final wavData = _createWavFromPcm(audioData, 24000, 16, 1);
      await _audioPlayer.play(BytesSource(wavData));
      debugPrint('Playing Gemini audio: ${audioData.length} bytes PCM -> ${wavData.length} bytes WAV');
    } catch (e) {
      debugPrint('Error playing audio: $e');
    } finally {
      _isPlayingAudio = false;
    }
  }
  
  /// Create WAV file from raw PCM data
  Uint8List _createWavFromPcm(Uint8List pcmData, int sampleRate, int bitsPerSample, int channels) {
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = 36 + dataSize;
    
    final header = ByteData(44);
    // RIFF header
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, fileSize, Endian.little);
    header.setUint8(8, 0x57);  // W
    header.setUint8(9, 0x41);  // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    // fmt chunk
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // space
    header.setUint32(16, 16, Endian.little); // chunk size
    header.setUint16(20, 1, Endian.little);  // PCM format
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    // data chunk
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);
    
    // Combine header and PCM data
    final wavData = Uint8List(44 + pcmData.length);
    wavData.setAll(0, header.buffer.asUint8List());
    wavData.setAll(44, pcmData);
    return wavData;
  }
  
  /// Disconnect from Live API
  void disconnect() {
    _audioPlayer.stop();
    _audioBuffer.clear();
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _isSessionActive = false;
    _connectionStatus = 'Bağlantı yok';
    onStatusChange?.call(_connectionStatus);
    debugPrint('Disconnected from Live API');
  }
  
  /// Dispose resources
  void dispose() {
    disconnect();
    _audioPlayer.dispose();
  }
  
  /// Check if connected
  bool get isConnected => _isConnected && _isSessionActive;
  
  /// Get current connection status
  String get connectionStatus => _connectionStatus;
}
