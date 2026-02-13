import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Centralized app settings service
/// Manages all user preferences including High Contrast, Data Collection Mode, etc.
class AppSettingsService {
  static AppSettingsService? _instance;
  SharedPreferences? _prefs;
  bool _initialized = false;

  // Settings keys
  static const String _keyHighContrast = 'high_contrast_enabled';
  static const String _keyDataCollectionMode = 'data_collection_mode';
  static const String _keyBoxColorUnknown = 'box_color_unknown';
  static const String _keyBoxColorKnown = 'box_color_known';
  static const String _keyBoxColorLinked = 'box_color_linked';
  static const String _keyLanguage = 'app_language';
  static const String _keySmartVisionEnabled = 'smart_vision_enabled';
  static const String _keySmartVisionFPS = 'smart_vision_fps';

  // Listeners
  final List<VoidCallback> _listeners = [];

  AppSettingsService._();

  static AppSettingsService get instance {
    _instance ??= AppSettingsService._();
    return _instance!;
  }

  bool get isInitialized => _initialized;

  /// Initialize the service
  Future<void> initialize() async {
    if (_initialized) return;
    _prefs = await SharedPreferences.getInstance();
    _initialized = true;
    debugPrint('AppSettingsService: Initialized');
  }

  void _ensureInitialized() {
    if (!_initialized || _prefs == null) {
      throw StateError('AppSettingsService not initialized. Call initialize() first.');
    }
  }

  /// Add listener for settings changes
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }

  /// Remove listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }

  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }

  // ========== HIGH CONTRAST MODE ==========

  bool get highContrastEnabled {
    _ensureInitialized();
    return _prefs!.getBool(_keyHighContrast) ?? false;
  }

  Future<void> setHighContrastEnabled(bool value) async {
    _ensureInitialized();
    await _prefs!.setBool(_keyHighContrast, value);
    _notifyListeners();
  }

  // ========== DATA COLLECTION MODE ==========

  bool get dataCollectionModeEnabled {
    _ensureInitialized();
    return _prefs!.getBool(_keyDataCollectionMode) ?? false;
  }

  Future<void> setDataCollectionModeEnabled(bool value) async {
    _ensureInitialized();
    await _prefs!.setBool(_keyDataCollectionMode, value);
    _notifyListeners();
  }

  // ========== BOX COLORS ==========

  Color get boxColorUnknown {
    _ensureInitialized();
    final colorValue = _prefs!.getInt(_keyBoxColorUnknown);
    return colorValue != null ? Color(colorValue) : const Color(0xFFFF9800);
  }

  Future<void> setBoxColorUnknown(Color color) async {
    _ensureInitialized();
    // ignore: deprecated_member_use
    await _prefs!.setInt(_keyBoxColorUnknown, color.value);
    _notifyListeners();
  }

  Color get boxColorKnown {
    _ensureInitialized();
    final colorValue = _prefs!.getInt(_keyBoxColorKnown);
    return colorValue != null ? Color(colorValue) : const Color(0xFF4CAF50);
  }

  Future<void> setBoxColorKnown(Color color) async {
    _ensureInitialized();
    // ignore: deprecated_member_use
    await _prefs!.setInt(_keyBoxColorKnown, color.value);
    _notifyListeners();
  }

  Color get boxColorLinked {
    _ensureInitialized();
    final colorValue = _prefs!.getInt(_keyBoxColorLinked);
    return colorValue != null ? Color(colorValue) : const Color(0xFF2196F3);
  }

  Future<void> setBoxColorLinked(Color color) async {
    _ensureInitialized();
    // ignore: deprecated_member_use
    await _prefs!.setInt(_keyBoxColorLinked, color.value);
    _notifyListeners();
  }

  // ========== LANGUAGE ==========

  String get language {
    _ensureInitialized();
    return _prefs!.getString(_keyLanguage) ?? 'tr';
  }

  Future<void> setLanguage(String langCode) async {
    _ensureInitialized();
    await _prefs!.setString(_keyLanguage, langCode);
    _notifyListeners();
  }

  // ========== SMART VISION ==========

  bool get smartVisionEnabled {
    _ensureInitialized();
    return _prefs!.getBool(_keySmartVisionEnabled) ?? false;
  }

  Future<void> setSmartVisionEnabled(bool value) async {
    _ensureInitialized();
    await _prefs!.setBool(_keySmartVisionEnabled, value);
    _notifyListeners();
  }

  int get smartVisionFPS {
    _ensureInitialized();
    return _prefs!.getInt(_keySmartVisionFPS) ?? 2;
  }

  Future<void> setSmartVisionFPS(int fps) async {
    _ensureInitialized();
    await _prefs!.setInt(_keySmartVisionFPS, fps);
    _notifyListeners();
  }

  // ========== EXPORT ==========

  /// Export all settings as a map (for debugging)
  Map<String, dynamic> exportSettings() {
    _ensureInitialized();
    return {
      'highContrastEnabled': highContrastEnabled,
      'dataCollectionModeEnabled': dataCollectionModeEnabled,
      'boxColorUnknown': boxColorUnknown.value.toRadixString(16),
      'boxColorKnown': boxColorKnown.value.toRadixString(16),
      'boxColorLinked': boxColorLinked.value.toRadixString(16),
      'language': language,
      'smartVisionEnabled': smartVisionEnabled,
      'smartVisionFPS': smartVisionFPS,
    };
  }
}
