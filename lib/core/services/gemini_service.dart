import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Service for Gemini AI integration
class GeminiService {
  static final GeminiService _instance = GeminiService._internal();
  factory GeminiService() => _instance;
  GeminiService._internal();

  // TODO: Set your Gemini API key here or use an environment variable
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');

  // Model fallback chain - try in order when rate limited
  // Each model has separate rate limits!
  static const List<String> _modelFallbackChain = [
    'gemini-3-flash-preview',
    'gemini-2.5-flash', // Primary - fast
    'gemini-2.5-flash-preview-09-2025', // Fallback 1 - stable
    'gemini-2.5-flash-lite',
  ];

  // Track which models are currently rate limited
  final Map<String, DateTime> _rateLimitedModels = {};

  int _currentModelIndex = 0;

  String get _currentModel => _modelFallbackChain[_currentModelIndex];

  String _getUrlForModel(String model) =>
      'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent';

  String get _baseUrl => _getUrlForModel(_currentModel);

  /// System prompt for product analysis - kept minimal for speed
  static const String _systemPrompt = '''Market asistanı. Türkçe kısa cevap ver.
- Son kullanma tarihini bul, "15 Aralık 2025" formatında söyle
- Tarihi geçmişse UYARI ver
- Maksimum 2 cümle''';

  /// Detailed product analysis prompt for expiry date context
  static const String _productAnalysisPrompt =
      '''Ürün fotoğrafını incele ve şu bilgileri ver:
1. Ürün güvenli mi? (Kullanılabilir/Tarihi Geçmiş)
2. Ne kadar süre kaldı son kullanma tarihine kadar
3. Ne tür bir ürün (örn: süt ürünü, konserve, içecek)
4. Hangi marka

Cevabını şu formatta ver:
- Durum: [Kullanılabilir veya Tarihi Geçmiş]
- Süre: [X gün/ay kaldı veya X gün/ay önce tarihi geçmiş]
- Ürün Tipi: [ürün kategorisi]
- Marka: [marka adı]

Kısa ve öz tut. Eğer bilgi bulamazsan "Bulunamadı" yaz.''';

  /// Analyze product image with Gemini AI
  /// Returns a short Turkish response about the product
  Future<String> analyzeProduct(Uint8List imageBytes) async {
    // Reset to first model on each new request
    _currentModelIndex = 0;

    return _tryAnalyzeWithFallback(imageBytes);
  }

  Future<String> _tryAnalyzeWithFallback(Uint8List imageBytes) async {
    try {
      // Compress image to reduce bandwidth (max 512px, 60% quality)
      final compressedImage = await _compressImage(imageBytes);

      // Convert to base64
      final base64Image = base64Encode(compressedImage);

      debugPrint('Trying model: $_currentModel');

      // Build request
      final response = await http
          .post(
            Uri.parse('$_baseUrl?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text':
                          '$_systemPrompt\n\nBu ürün fotoğrafını analiz et. Son kullanma tarihini ve ürün adını kısaca söyle.'
                    },
                    {
                      'inline_data': {
                        'mime_type': 'image/jpeg',
                        'data': base64Image
                      }
                    }
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.1, // Low for consistency
                'maxOutputTokens': 150, // Reduced for speed
                'topP': 0.5, // More focused
              },
              'safetySettings': [
                {
                  'category': 'HARM_CATEGORY_HARASSMENT',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_HATE_SPEECH',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
                  'threshold': 'BLOCK_NONE'
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Debug logging
        debugPrint('=== GEMINI API RESPONSE ===');
        debugPrint('Status: ${response.statusCode}');
        debugPrint('Full response body: ${response.body}');
        debugPrint('Candidates: ${data['candidates']}');

        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];

        debugPrint('Extracted text: $text');
        debugPrint('Text length: ${text?.toString().length ?? 0}');
        debugPrint('=== END GEMINI RESPONSE ===');

        if (text != null && text.isNotEmpty) {
          final result = text.toString().trim();
          debugPrint('Returning result: $result');
          return result;
        }
        debugPrint('No text found in response, returning error message');
        return 'Ürün analiz edilemedi. Lütfen tekrar deneyin.';
      } else if (response.statusCode == 429) {
        // Rate limit - try next model
        debugPrint('Rate limited on $_currentModel, trying fallback...');
        if (_currentModelIndex < _modelFallbackChain.length - 1) {
          _currentModelIndex++;
          return _tryAnalyzeWithFallback(imageBytes);
        }
        return 'Yapay zeka şu an meşgul. Lütfen birkaç saniye bekleyip tekrar deneyin.';
      } else {
        debugPrint(
            'Gemini API Error: ${response.statusCode} - ${response.body}');
        // Try next model on error
        if (_currentModelIndex < _modelFallbackChain.length - 1) {
          _currentModelIndex++;
          return _tryAnalyzeWithFallback(imageBytes);
        }
        return 'Bağlantı hatası. Lütfen tekrar deneyin.';
      }
    } catch (e) {
      debugPrint('Gemini Service Error: $e');
      // Try next model on error
      if (_currentModelIndex < _modelFallbackChain.length - 1) {
        _currentModelIndex++;
        return _tryAnalyzeWithFallback(imageBytes);
      }
      return 'Bir hata oluştu. Lütfen tekrar deneyin.';
    }
  }

  /// Generate natural TTS text using lighter Gemini model (text-only, cheaper)
  /// Takes product data and generates a natural Turkish announcement
  Future<String> generateTTSText({
    required String productName,
    String? productType,
    String? price,
    String? barcode,
  }) async {
    // For TTS, just use simple fallback - no need to waste Gemini calls
    // This is more reliable and doesn't hit rate limits
    debugPrint('🔊 Generating TTS text...');
    return _buildSimpleTTS(productName, productType, price);
  }

  /// Simple TTS fallback - reliable and rate-limit friendly
  String _buildSimpleTTS(
      String productName, String? productType, String? price) {
    final buffer = StringBuffer(productName);
    if (productType != null &&
        productType != 'Bilinmiyor' &&
        productType.isNotEmpty) {
      buffer.write('. $productType');
    }
    if (price != null && price.isNotEmpty) {
      // Clean up price format
      final cleanPrice = price.replaceAll(RegExp(r'[^\d.,]'), '').trim();
      if (cleanPrice.isNotEmpty) {
        buffer.write('. Fiyatı $cleanPrice lira');
      }
    }
    buffer.write('.');
    return buffer.toString();
  }

  /// Compress image for bandwidth efficiency
  Future<Uint8List> _compressImage(Uint8List imageBytes) async {
    try {
      final result = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 512,
        minHeight: 512,
        quality: 60,
        format: CompressFormat.jpeg,
      );
      debugPrint(
          'Image compressed: ${imageBytes.length} -> ${result.length} bytes');
      return result;
    } catch (e) {
      debugPrint('Image compression failed: $e');
      return imageBytes; // Return original if compression fails
    }
  }

  /// Super fast video frame analysis - minimal prompt, fastest response
  /// Returns just: "MARKA ÜRÜN. SKT: TARİH. DURUM" or empty if nothing found
  Future<String> analyzeVideoFrame(Uint8List imageBytes) async {
    try {
      // Aggressive compression for speed (256px, 40% quality)
      final compressed = await FlutterImageCompress.compressWithList(
        imageBytes,
        minWidth: 256,
        minHeight: 256,
        quality: 40,
        format: CompressFormat.jpeg,
      );
      final base64Image = base64Encode(compressed);

      final response = await http
          .post(
            Uri.parse('$_baseUrl?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text':
                          'Son kullanma tarihi? Sadece tarih yaz. Örnek: 15.12.2025'
                    },
                    {
                      'inline_data': {
                        'mime_type': 'image/jpeg',
                        'data': base64Image
                      }
                    }
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.0,
                'maxOutputTokens': 30,
                'topP': 0.3,
              },
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        return text?.toString().trim() ?? '';
      }
      return '';
    } catch (e) {
      debugPrint('Video frame analysis error: $e');
      return '';
    }
  }

  /// Quick analysis - just get the expiry date (uses first model only for speed)
  Future<String> quickDateAnalysis(Uint8List imageBytes) async {
    try {
      final compressedImage = await _compressImage(imageBytes);
      final base64Image = base64Encode(compressedImage);

      // Use first (most reliable) model for quick analysis
      final url =
          'https://generativelanguage.googleapis.com/v1beta/models/${_modelFallbackChain[0]}:generateContent';

      final response = await http
          .post(
            Uri.parse('$url?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {
                      'text':
                          'Son kullanma tarihi? Sadece tarih. Örnek: 15.12.2025'
                    },
                    {
                      'inline_data': {
                        'mime_type': 'image/jpeg',
                        'data': base64Image
                      }
                    }
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.0,
                'maxOutputTokens': 30,
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        return text?.toString().trim() ?? 'Tarih bulunamadı';
      } else if (response.statusCode == 429) {
        return 'Yapay zeka meşgul. Lütfen bekleyin.';
      }
      return 'Bağlantı hatası';
    } catch (e) {
      debugPrint('Quick analysis error: $e');
      return 'Hata oluştu';
    }
  }

  /// Analyze product with expiry date context
  /// Returns detailed info: safety status, time until expiry, product type, brand
  Future<String> analyzeProductWithDate(
      Uint8List imageBytes, String detectedDate,
      {String? userContext}) async {
    try {
      final compressedImage = await _compressImage(imageBytes);
      final base64Image = base64Encode(compressedImage);

      debugPrint('Analyzing product with detected date: $detectedDate');
      if (userContext != null && userContext.isNotEmpty) {
        debugPrint('Using user context for better recognition');
      }

      // Build prompt with optional user context
      final promptText = StringBuffer();
      promptText.writeln(_productAnalysisPrompt);

      // Add user shopping context if available
      if (userContext != null && userContext.isNotEmpty) {
        promptText.writeln('\n$userContext');
        promptText.writeln(
            '\nBu bilgileri kullanarak ürünü daha doğru tanımla (benzer markaları ve ürün tiplerini önceliklendir).');
      }

      promptText.writeln('\nAlgılanan son kullanma tarihi: $detectedDate');
      promptText.writeln(
          'Bugünün tarihi: ${DateTime.now().day} ${_getMonthName(DateTime.now().month)} ${DateTime.now().year}');

      final response = await http
          .post(
            Uri.parse('$_baseUrl?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': promptText.toString()},
                    {
                      'inline_data': {
                        'mime_type': 'image/jpeg',
                        'data': base64Image
                      }
                    }
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.2,
                'maxOutputTokens': 150,
                'topP': 0.5,
              },
              'safetySettings': [
                {
                  'category': 'HARM_CATEGORY_HARASSMENT',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_HATE_SPEECH',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
                  'threshold': 'BLOCK_NONE'
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (text != null && text.isNotEmpty) {
          return text.toString().trim();
        }
        return 'Ürün bilgisi alınamadı';
      } else if (response.statusCode == 429) {
        return 'Yapay zeka meşgul. Ürün: Tarih $detectedDate';
      } else {
        debugPrint('Product analysis error: ${response.statusCode}');
        return 'Bağlantı hatası';
      }
    } catch (e) {
      debugPrint('Product analysis exception: $e');
      return 'Analiz hatası oluştu';
    }
  }

  /// Helper to get Turkish month name
  String _getMonthName(int month) {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık'
    ];
    return months[month - 1];
  }

  /// Simple continuous analysis - look for expiry date and product info
  /// Returns natural Turkish description of what's visible
  Future<String> analyzeProductForExpiry(Uint8List imageBytes) async {
    try {
      final compressedImage = await _compressImage(imageBytes);
      final base64Image = base64Encode(compressedImage);

      final today = DateTime.now();
      final prompt = '''Fotoğraftaki ürünü incele ve şunları söyle:

1. Ürün adı ve marka (varsa)
2. Son kullanma tarihi (SKT) - fotoğrafta görünen tarih formatını oku
3. Ürün tipi (örn: süt, peynir, konserve, içecek, vb)

Bugünün tarihi: ${today.day} ${_getMonthName(today.month)} ${today.year}

Cevabını şu şekilde ver:
"[Marka] [Ürün tipi]. Son kullanma tarihi: [tarih]. [Durum - kullanılabilir/tarihi geçmiş/yakında bitecek]"

Örnek: "Pınar süt. Son kullanma tarihi: 25 Aralık 2025. Kullanılabilir, 7 gün kaldı."

Eğer tarih göremiyorsan veya okumazsan "Tarih bulunamadı" de.
Kısa ve öz tut.''';

      final response = await http
          .post(
            Uri.parse('$_baseUrl?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'parts': [
                    {'text': prompt},
                    {
                      'inline_data': {
                        'mime_type': 'image/jpeg',
                        'data': base64Image
                      }
                    }
                  ]
                }
              ],
              'generationConfig': {
                'temperature': 0.2,
                'maxOutputTokens': 200,
                'topP': 0.8,
              },
              'safetySettings': [
                {
                  'category': 'HARM_CATEGORY_HARASSMENT',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_HATE_SPEECH',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
                  'threshold': 'BLOCK_NONE'
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];

        if (text != null && text.isNotEmpty) {
          return text.toString().trim();
        }
      }

      return '';
    } catch (e) {
      debugPrint('Gemini expiry analysis error: $e');
      return '';
    }
  }

  /// Analyze multiple angles to extract expiry info
  Future<String> analyzeExpiryFromImages(List<Uint8List> images) async {
    if (images.isEmpty) return '';

    try {
      final today = DateTime.now();
      final prompt =
          '''Birden fazla açıdan ürün fotoğrafları veriyorum. Görevlerin:

1) Marka ve ürün tipini söyle
2) Son kullanma tarihini bulup söyle (görebiliyorsan tam tarih ver)
3) Tarihi değerlendirme: kullanilabilir / tarihi geçmiş / yakında bitecek

Bugünün tarihi: ${today.day} ${_getMonthName(today.month)} ${today.year}
Kısa, tek paragraf cevap ver. Tarih göremiyorsan "Tarih bulunamadı" de.''';

      final parts = <Map<String, dynamic>>[
        {'text': prompt},
      ];
      for (final img in images.take(5)) {
        final compressed = await _compressImage(img);
        parts.add({
          'inline_data': {
            'mime_type': 'image/jpeg',
            'data': base64Encode(compressed)
          }
        });
      }

      final response = await http
          .post(
            Uri.parse('$_baseUrl?key=$_apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {'parts': parts}
              ],
              'generationConfig': {
                'temperature': 0.2,
                'maxOutputTokens': 220,
                'topP': 0.8,
              },
              'safetySettings': [
                {
                  'category': 'HARM_CATEGORY_HARASSMENT',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_HATE_SPEECH',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                  'threshold': 'BLOCK_NONE'
                },
                {
                  'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
                  'threshold': 'BLOCK_NONE'
                }
              ]
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates']?[0]?['content']?['parts']?[0]?['text'];
        if (text != null && text.isNotEmpty) {
          return text.toString().trim();
        }
      }

      debugPrint(
          'Gemini multi-image expiry analysis failed: ${response.statusCode}');
      return '';
    } catch (e) {
      debugPrint('Gemini multi-image expiry analysis error: $e');
      return '';
    }
  }

  /// Mark a model as rate limited
  void _markModelRateLimited(String model, {int seconds = 60}) {
    final limitedUntil = DateTime.now().add(Duration(seconds: seconds));
    _rateLimitedModels[model] = limitedUntil;
    debugPrint('🚫 Model $model rate limited for $seconds seconds');
  }

  /// Analyze unregistered barcode product from image with model fallback
  /// Returns: {name, type, price_estimate} in Turkish
  /// Uses Open Food Facts API + web scraping + Gemini with fallback chain
  Future<Map<String, String>> analyzeUnregisteredBarcode(
      Uint8List imageBytes, String barcode,
      {String? webScrapedData}) async {
    try {
      final compressedImage = await _compressImage(imageBytes);
      final base64Image = base64Encode(compressedImage);

      debugPrint('');
      debugPrint('🔍 Analyzing unregistered barcode: $barcode');

      // Try Open Food Facts API first (free, no rate limits)
      String? openFoodFactsData;
      try {
        openFoodFactsData = await _lookupOpenFoodFacts(barcode);
        if (openFoodFactsData != null) {
          debugPrint('✅ Open Food Facts: $openFoodFactsData');
        }
      } catch (e) {
        debugPrint('❌ Open Food Facts lookup failed: $e');
      }

      // Build prompt with all available data
      final promptBuffer = StringBuffer();
      promptBuffer
          .writeln('Bu ürün fotoğrafını incele. Barkod numarası: $barcode');

      if (openFoodFactsData != null && openFoodFactsData.isNotEmpty) {
        promptBuffer.writeln('\nÜrün veritabanı bilgisi:');
        promptBuffer.writeln(openFoodFactsData);
      }

      if (webScrapedData != null && webScrapedData.isNotEmpty) {
        promptBuffer.writeln('\nİnternet araması sonucu:');
        promptBuffer.writeln(webScrapedData);
      }

      promptBuffer.writeln('''

Yukarıdaki TÜM bilgileri ve fotoğrafı kullanarak ürünü TAM OLARAK tanımla.

Ürün hakkında şu bilgileri ver:
1. ÜRÜN ADI (marka + tam ürün ismi, örn: "Axe Dark Temptation Deodorant Sprey 150ml")
2. ÜRÜN TİPİ (örn: deodorant, şampuan, süt ürünü, içecek, atıştırmalık, temizlik, kişisel bakım vb)
3. FİYAT (Türkiye market fiyatı, TL cinsinden - tahmini olabilir)
4. SON KULLANMA TARİHİ (fotoğrafta görünen tarihi "DD.MM.YYYY" formatında yaz)

Cevabını TAM OLARAK şu formatta ver, başka bir şey yazma:
ÜRÜN: [tam ürün adı]
TİP: [ürün tipi]
FİYAT: [fiyat] TL
SKT: [tarih veya "Bulunamadı"]

Fotoğraftan ve verilen bilgilerden en iyi tahmini yap. "Bilinmiyor" yazma, her zaman bir cevap ver.''');

      final prompt = promptBuffer.toString();

      // Try models in fallback chain
      for (final model in _modelFallbackChain) {
        // Skip rate limited models
        final now = DateTime.now();
        if (_rateLimitedModels.containsKey(model)) {
          final limitedUntil = _rateLimitedModels[model]!;
          if (now.isBefore(limitedUntil)) {
            debugPrint('⏳ Skipping $model (rate limited)');
            continue;
          } else {
            _rateLimitedModels.remove(model);
          }
        }

        debugPrint('🤖 Trying model: $model');

        try {
          final response = await http
              .post(
                Uri.parse('${_getUrlForModel(model)}?key=$_apiKey'),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'contents': [
                    {
                      'parts': [
                        {'text': prompt},
                        {
                          'inline_data': {
                            'mime_type': 'image/jpeg',
                            'data': base64Image
                          }
                        }
                      ]
                    }
                  ],
                  'generationConfig': {
                    'temperature': 0.4,
                    'maxOutputTokens': 200,
                    'topP': 0.8,
                  },
                  'safetySettings': [
                    {
                      'category': 'HARM_CATEGORY_HARASSMENT',
                      'threshold': 'BLOCK_NONE'
                    },
                    {
                      'category': 'HARM_CATEGORY_HATE_SPEECH',
                      'threshold': 'BLOCK_NONE'
                    },
                    {
                      'category': 'HARM_CATEGORY_SEXUALLY_EXPLICIT',
                      'threshold': 'BLOCK_NONE'
                    },
                    {
                      'category': 'HARM_CATEGORY_DANGEROUS_CONTENT',
                      'threshold': 'BLOCK_NONE'
                    }
                  ]
                }),
              )
              .timeout(const Duration(seconds: 20));

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            final text =
                data['candidates']?[0]?['content']?['parts']?[0]?['text'];

            if (text != null && text.isNotEmpty) {
              debugPrint(
                  '✅ $model returned: ${text.toString().substring(0, text.toString().length.clamp(0, 100))}...');
              final result = _parseUnregisteredProduct(text.toString());
            // Log if SKT was found
            if (result.containsKey('expiryDate') && result['expiryDate'] != 'Bulunamadı') {
              debugPrint('📅 Found expiry date in Gemini analysis: ${result['expiryDate']}');
            }
            debugPrint('📦 Parsed product: $result');
            return result;
            }
          } else if (response.statusCode == 429) {
            // Rate limited - mark this model and try next
            debugPrint('🚫 $model rate limited (429)');

            // Parse retry delay if available
            int retrySeconds = 60;
            try {
              final errorData = jsonDecode(response.body);
              final retryDelay = errorData['error']?['details']?.firstWhere(
                (d) => d['@type'] == 'type.googleapis.com/google.rpc.RetryInfo',
                orElse: () => null,
              )?['retryDelay'];
              if (retryDelay != null) {
                retrySeconds = int.tryParse(
                        retryDelay.replaceAll(RegExp(r'[^0-9]'), '')) ??
                    60;
              }
            } catch (_) {}

            _markModelRateLimited(model, seconds: retrySeconds);
            continue; // Try next model
          } else {
            debugPrint('❌ $model failed: ${response.statusCode}');
            continue; // Try next model
          }
        } catch (e) {
          debugPrint('❌ $model error: $e');
          continue; // Try next model
        }
      }

      // All models failed - return what we have from APIs
      debugPrint('⚠️ All Gemini models exhausted, using API data only');
      if (openFoodFactsData != null) {
        return _parseOpenFoodFactsToResult(openFoodFactsData);
      }
      if (webScrapedData != null) {
        return _parseWebScrapedToResult(webScrapedData, barcode);
      }

      return {'name': 'Bilinmeyen Ürün', 'type': 'Bilinmiyor', 'price': ''};
    } catch (e) {
      debugPrint('Unregistered barcode analysis error: $e');
      return {'name': 'Bilinmeyen Ürün', 'type': 'Bilinmiyor', 'price': ''};
    }
  }

  /// Parse web scraped data into result (when Gemini unavailable)
  Map<String, String> _parseWebScrapedToResult(String webData, String barcode) {
    final result = <String, String>{
      'name': 'Bilinmeyen Ürün',
      'type': 'Bilinmiyor',
      'price': '',
    };

    // Extract price if found
    final priceMatch =
        RegExp(r'Fiyat:\s*(\d+[.,]?\d*)\s*(TL|₺|lira)?', caseSensitive: false)
            .firstMatch(webData);
    if (priceMatch != null) {
      result['price'] = '${priceMatch.group(1)} TL';
    }

    // Try to extract product name from web data
    final lines = webData.split('\n');
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isNotEmpty &&
          trimmed.length > 5 &&
          !trimmed.toLowerCase().startsWith('fiyat') &&
          !RegExp(r'^\d').hasMatch(trimmed)) {
        // Use first meaningful line as product name
        result['name'] =
            trimmed.length > 50 ? trimmed.substring(0, 50) : trimmed;
        break;
      }
    }

    return result;
  }

  /// Look up barcode in Open Food Facts database (free, no rate limits)
  Future<String?> _lookupOpenFoodFacts(String barcode) async {
    try {
      final url =
          'https://world.openfoodfacts.org/api/v2/product/$barcode.json';
      debugPrint('Looking up Open Food Facts: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {'User-Agent': 'MarketGoz/1.0'},
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 1 && data['product'] != null) {
          final product = data['product'];
          final buffer = StringBuffer();

          // Product name
          final productName = product['product_name_tr'] ??
              product['product_name'] ??
              product['generic_name_tr'] ??
              product['generic_name'];
          if (productName != null && productName.isNotEmpty) {
            buffer.writeln('Ürün: $productName');
          }

          // Brand
          final brands = product['brands'];
          if (brands != null && brands.isNotEmpty) {
            buffer.writeln('Marka: $brands');
          }

          // Categories
          final categories =
              product['categories_tags_tr'] ?? product['categories'];
          if (categories != null && categories.isNotEmpty) {
            final categoryStr =
                categories is List ? categories.take(3).join(', ') : categories;
            buffer.writeln('Kategori: $categoryStr');
          }

          // Quantity/Size
          final quantity = product['quantity'];
          if (quantity != null && quantity.isNotEmpty) {
            buffer.writeln('Miktar: $quantity');
          }

          final result = buffer.toString().trim();
          return result.isNotEmpty ? result : null;
        }
      }

      debugPrint('Open Food Facts: Product not found');
      return null;
    } catch (e) {
      debugPrint('Open Food Facts error: $e');
      return null;
    }
  }

  /// Parse Open Food Facts data into result map (fallback when Gemini is rate limited)
  Map<String, String> _parseOpenFoodFactsToResult(String data) {
    final result = <String, String>{
      'name': 'Bilinmeyen Ürün',
      'type': 'Bilinmiyor',
      'price': '',
    };

    // Extract product name
    final nameMatch =
        RegExp(r'Ürün:\s*(.+)', caseSensitive: false).firstMatch(data);
    final brandMatch =
        RegExp(r'Marka:\s*(.+)', caseSensitive: false).firstMatch(data);

    if (brandMatch != null && nameMatch != null) {
      result['name'] =
          '${brandMatch.group(1)?.trim()} ${nameMatch.group(1)?.trim()}';
    } else if (nameMatch != null) {
      result['name'] = nameMatch.group(1)?.trim() ?? 'Bilinmeyen Ürün';
    } else if (brandMatch != null) {
      result['name'] = brandMatch.group(1)?.trim() ?? 'Bilinmeyen Ürün';
    }

    // Extract category
    final categoryMatch =
        RegExp(r'Kategori:\s*(.+)', caseSensitive: false).firstMatch(data);
    if (categoryMatch != null) {
      result['type'] = categoryMatch.group(1)?.trim() ?? 'Bilinmiyor';
    }

    return result;
  }

  /// Parse Gemini response for unregistered product
  Map<String, String> _parseUnregisteredProduct(String response) {
    final result = <String, String>{
      'name': 'Bilinmeyen Ürün',
      'type': 'Bilinmiyor',
      'price': '',
    };

    // Parse ÜRÜN:
    final nameMatch =
        RegExp(r'ÜRÜN:\s*(.+)', caseSensitive: false).firstMatch(response);
    if (nameMatch != null) {
      final name = nameMatch.group(1)?.trim() ?? '';
      if (name.isNotEmpty && !name.toLowerCase().contains('bilinmiyor')) {
        result['name'] = name;
      }
    }

    // Parse TİP:
    final typeMatch =
        RegExp(r'TİP:\s*(.+)', caseSensitive: false).firstMatch(response);
    if (typeMatch != null) {
      final type = typeMatch.group(1)?.trim() ?? '';
      if (type.isNotEmpty && !type.toLowerCase().contains('bilinmiyor')) {
        result['type'] = type;
      }
    }

    // Parse FİYAT:
    final priceMatch =
        RegExp(r'FİYAT:\s*(.+)', caseSensitive: false).firstMatch(response);
    if (priceMatch != null) {
      final price = priceMatch.group(1)?.trim() ?? '';
      if (price.isNotEmpty && !price.toLowerCase().contains('bilinmiyor')) {
        result['price'] = price;
      }
    }

    // Parse SKT:
    final sktMatch =
        RegExp(r'SKT:\s*(.+)', caseSensitive: false).firstMatch(response);
    if (sktMatch != null) {
      final skt = sktMatch.group(1)?.trim() ?? '';
      if (skt.isNotEmpty && !skt.toLowerCase().contains('bulunamadı')) {
        result['expiryDate'] = skt;
      }
    }

    return result;
  }
}
