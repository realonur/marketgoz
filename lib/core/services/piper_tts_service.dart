/// Deprecated placeholder: Piper TTS is not used on iOS.
/// Kept to avoid breaking imports during cleanup.
class PiperTTSService {
  static final PiperTTSService _instance = PiperTTSService._internal();
  factory PiperTTSService() => _instance;
  PiperTTSService._internal();
  Future<void> initialize() async {}
  Future<void> speak(String text) async {}
  Future<void> stop() async {}
  Future<void> dispose() async {}
}
