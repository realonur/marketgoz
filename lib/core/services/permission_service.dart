import 'package:permission_handler/permission_handler.dart';

class PermissionService {
  static final PermissionService _instance = PermissionService._internal();
  factory PermissionService() => _instance;
  PermissionService._internal();

  /// Request camera permission
  Future<bool> requestCameraPermission() async {
    print('📷 Checking camera permission...');
    final status = await Permission.camera.status;
    print('📷 Current camera status: $status');

    if (status.isGranted) {
      print('📷 Camera permission already granted');
      return true;
    }

    if (status.isDenied || status.isRestricted || status.isLimited) {
      print('📷 Requesting camera permission...');
      final result = await Permission.camera.request();
      print('📷 Camera permission result: $result');
      return result.isGranted;
    }

    if (status.isPermanentlyDenied) {
      print('📷 Camera permission permanently denied, opening settings...');
      // Open app settings
      await openAppSettings();
      return false;
    }

    // For any other status, try requesting anyway
    print('📷 Unknown status, requesting camera permission...');
    final result = await Permission.camera.request();
    print('📷 Camera permission result: $result');
    return result.isGranted;
  }
  
  /// Request microphone permission (needed for some camera features)
  Future<bool> requestMicrophonePermission() async {
    print('🎤 Checking microphone permission...');
    final status = await Permission.microphone.status;
    print('🎤 Current microphone status: $status');

    if (status.isGranted) {
      return true;
    }

    final result = await Permission.microphone.request();
    print('🎤 Microphone permission result: $result');
    return result.isGranted;
  }

  /// Check if camera permission is granted
  Future<bool> isCameraPermissionGranted() async {
    return await Permission.camera.isGranted;
  }

  /// Request multiple permissions at once
  Future<Map<Permission, PermissionStatus>> requestPermissions(
    List<Permission> permissions,
  ) async {
    return await permissions.request();
  }

  /// Check permission status
  Future<PermissionStatus> getPermissionStatus(Permission permission) async {
    return await permission.status;
  }
}
