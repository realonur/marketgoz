import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/haptic_helper.dart';
import '../../../core/services/firebase_service.dart';
import '../../../core/services/tts_service.dart';
import '../../../core/services/product_storage_service.dart';
import '../../settings/presentation/smart_vision_settings_widget.dart';
import '../../unified_scanner/presentation/unified_scanner_screen.dart';
import '../../database/presentation/product_database_screen.dart';

// Global editing mode flag - can be toggled secretly
class EditingMode {
  static bool enabled = true;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Shake detection
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  DateTime? _lastShakeTime;
  static const _shakeThreshold = 15.0;
  static const _shakeCooldown = Duration(milliseconds: 1000);

  // Secret tap counter for toggling edit mode
  int _secretTapCount = 0;
  DateTime? _lastSecretTap;

  final FirebaseService _firebase = FirebaseService();
  final TTSService _tts = TTSService();
  // Smart Vision removed

  @override
  void initState() {
    super.initState();


    // Start shake detection
    _startShakeDetection();

    // Initialize TTS and announce app open
    WidgetsBinding.instance.addPostFrameCallback((_) {
      HapticFeedback.mediumImpact();
      _announceAppOpen();
    });
  }


  // Smart Vision removed

  /// Announce app is open and how to start scanning
  Future<void> _announceAppOpen() async {
    await _tts.initialize();
    await Future.delayed(const Duration(milliseconds: 500));
    _tts.speak('MarketGöz açıldı. Barkod, tarih ve görsel tanıma için tarama başlatmak için ekrana dokunun veya telefonu sallayın.');
  }
  void _startShakeDetection() {
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      final acceleration = (event.x.abs() + event.y.abs() + event.z.abs()) - 9.8;
      if (acceleration > _shakeThreshold) {
        final now = DateTime.now();
        if (_lastShakeTime == null || now.difference(_lastShakeTime!) > _shakeCooldown) {
          _lastShakeTime = now;
          _onShake();
        }
      }
    });
  }

  void _onShake() {
    HapticFeedback.mediumImpact();
    _navigateToUnifiedScanner();
  }

  /// Secret triple-tap on title to toggle editing mode
  void _onSecretTap() {
    final now = DateTime.now();
    
    // Reset counter if too much time passed
    if (_lastSecretTap != null && now.difference(_lastSecretTap!).inSeconds > 2) {
      _secretTapCount = 0;
    }
    
    _secretTapCount++;
    _lastSecretTap = now;
    
    if (_secretTapCount >= 5) {
      _secretTapCount = 0;
      setState(() {
        EditingMode.enabled = !EditingMode.enabled;
      });
      HapticFeedback.heavyImpact();
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                EditingMode.enabled ? Icons.edit : Icons.edit_off,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(EditingMode.enabled ? 'Düzenleme modu açık' : 'Düzenleme modu kapalı'),
            ],
          ),
          backgroundColor: EditingMode.enabled ? Colors.green : Colors.orange,
          duration: const Duration(seconds: 2),
        ),
      );
      
      debugPrint('🔐 Editing mode: ${EditingMode.enabled ? "ENABLED" : "DISABLED"}');
    }
  }

  // Smart Vision removed

  // Smart Vision removed

  /// Long press on title to show admin menu
  void _showAdminMenu() {
    HapticFeedback.mediumImpact();
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Veritabanı Yönetimi',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.upload_file, color: Colors.blue),
              title: const Text('Veritabanını Dışa Aktar'),
              subtitle: const Text('JSON dosyası olarak paylaş'),
              onTap: () {
                Navigator.pop(context);
                _exportDatabase();
              },
            ),
            ListTile(
              leading: const Icon(Icons.storage_rounded, color: Colors.teal),
              title: const Text('Ürün Veritabanını Yönet'),
              subtitle: const Text('Barkod ve SKT düzenleme'),
              onTap: () async {
                Navigator.pop(context);
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ProductDatabaseScreen(),
                  ),
                );
                // Stop any TTS when returning to home screen
                _tts.stop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy, color: Colors.green),
              title: const Text('JSON\'u Panoya Kopyala'),
              subtitle: const Text('Veritabanını panoya kopyala'),
              onTap: () {
                Navigator.pop(context);
                _copyDatabaseToClipboard();
              },
            ),
            ListTile(
              leading: Icon(
                EditingMode.enabled ? Icons.edit_off : Icons.edit,
                color: EditingMode.enabled ? Colors.orange : Colors.green,
              ),
              title: Text(EditingMode.enabled ? 'Düzenleme Modunu Kapat' : 'Düzenleme Modunu Aç'),
              subtitle: Text(EditingMode.enabled ? 'Kullanıcılar ürün düzenleyemez' : 'Kullanıcılar ürün düzenleyebilir'),
              onTap: () async {
                Navigator.pop(context);
                final prefs = await SharedPreferences.getInstance();
                setState(() {
                  EditingMode.enabled = !EditingMode.enabled;
                });
                await prefs.setBool('editing_enabled', EditingMode.enabled);
                HapticFeedback.mediumImpact();
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.grey),
              title: const Text('Veritabanı Bilgisi'),
              onTap: () {
                Navigator.pop(context);
                _showDatabaseInfo();
              },
            ),
            const Divider(),
            // Smart Vision settings
            ListTile(
              leading: const Icon(Icons.visibility, color: Colors.purple),
              title: const Text('Smart Vision Ayarları'),
              subtitle: const Text('Görsel ürün tanıma'),
              onTap: () {
                Navigator.pop(context);
                _showSmartVisionSettings();
              },
            ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _exportDatabase() async {
    try {
      final jsonData = await _firebase.exportDatabaseAsJson();
      
      await Share.share(
        jsonData,
        subject: 'MarketGöz Veritabanı - ${DateTime.now().toString().split('.').first}',
      );
    } catch (e) {
      debugPrint('Export error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Dışa aktarma hatası!'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _copyDatabaseToClipboard() async {
    try {
      final jsonData = await _firebase.exportDatabaseAsJson();
      await Clipboard.setData(ClipboardData(text: jsonData));
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check, color: Colors.white),
                SizedBox(width: 8),
                Text('Veritabanı panoya kopyalandı!'),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Copy error: $e');
    }
  }

  void _showDatabaseInfo() {
    final stats = _firebase.getStats();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.storage, color: Colors.blue),
            SizedBox(width: 8),
            Text('Veritabanı'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Toplam ürün: ${stats['total']}'),
            Text('Kullanıcı ekledi: ${stats['userAdded']}'),
            const SizedBox(height: 8),
            Text(
              'Düzenleme modu: ${EditingMode.enabled ? "Açık" : "Kapalı"}',
              style: TextStyle(
                color: EditingMode.enabled ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('TAMAM'),
          ),
        ],
      ),
    );
  }

  void _showSmartVisionSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            // Drag handle
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const Text(
              'Smart Vision Ayarları',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.only(bottom: 24),
                child: const SmartVisionSettingsWidget(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToUnifiedScanner() async {
    await HapticHelper.light();

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const UnifiedScannerScreen(),
      ),
    );
    
    // Stop any TTS when returning to home screen
    _tts.stop();
  }

  @override
  void dispose() {
    _accelerometerSubscription?.cancel();
    _tts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // High contrast black background
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Tap anywhere on screen to start scanning
        onTap: _navigateToUnifiedScanner,
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App title - tap 5 times to toggle edit mode, long press for admin menu
                    GestureDetector(
                      onTap: () {
                        _onSecretTap();
                        // Don't navigate when tapping title (for secret mode)
                      },
                      onLongPress: _showAdminMenu,
                      child: Text(
                        'MarketGöz',
                        style: AppTextStyles.heading1.copyWith(
                          color: AppColors.primary, // Yellow/Gold remains
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                  const SizedBox(height: 8),

                  Text(
                    'Alışveriş Asistanınız',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: Colors.white, // White for high contrast on black
                      fontSize: 18,
                    ),
                  ),

                  const SizedBox(height: 48),

                  // Main unified scanner button
                  GestureDetector(
                    onTap: _navigateToUnifiedScanner,
                    child: Container(
                      padding: const EdgeInsets.all(48),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.primary, width: 6), // Thicker border
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.primary.withValues(alpha: 0.4), // Stronger glow
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        Icons.camera_alt,
                        size: 120,
                        color: AppColors.primary,
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  Text(
                    'TARAYICIYI AÇ',
                    style: AppTextStyles.heading1.copyWith(
                      color: AppColors.primary,
                      fontSize: 28,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 8),

                  Text(
                    'Barkod • Tarih • Görsel Tanıma',
                    style: AppTextStyles.bodyLarge.copyWith(
                      color: Colors.white, // White text
                      fontSize: 18,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 40),

                  // Tap instruction
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(40),
                    ),
                    child: GestureDetector(
                      onTap: _navigateToUnifiedScanner,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.touch_app,
                              color: Colors.black, size: 28), // Black icon on yellow
                          const SizedBox(width: 12),
                          Text(
                            'DOKUN VE BAŞLA',
                            style: AppTextStyles.buttonText.copyWith(
                              color: Colors.black, // Black text on yellow button
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Shake instruction
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.vibration,
                          color: Colors.grey, size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'veya telefonu sallayın',
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: Colors.grey,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 48),

                  // Feature highlights - High contrast box
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey[900], // Dark gray surface
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey[800]!),
                    ),
                    child: Column(
                      children: [
                        _buildFeatureRow(
                            Icons.qr_code_scanner, 'Barkod Tarama'),
                        const SizedBox(height: 12),
                        _buildFeatureRow(Icons.calendar_today, 'Tarih Okuma'),
                        const SizedBox(height: 12),
                        _buildFeatureRow(Icons.link, 'Barkod-Tarih Eşleştirme'),
                        const SizedBox(height: 12),
                        _buildFeatureRow(
                            Icons.volume_up, 'Sesli Bilgilendirme'),
                        const SizedBox(height: 12),
                        _buildFeatureRow(
                            Icons.visibility, 'Görsel Ürün Tanıma'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ), // SafeArea
    ), // GestureDetector + Scaffold body
  ); // Scaffold return
  }

  Widget _buildFeatureRow(IconData icon, String text) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 12),
        Text(
          text,
          style: AppTextStyles.bodyMedium.copyWith(
            color: Colors.white,
            fontSize: 16,
          ),
        ),
      ],
    );
  }
}
