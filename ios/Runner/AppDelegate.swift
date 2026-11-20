import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    registerCameraInfoChannel()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Read-only facts about the back wide camera that the `camera` plugin does
  /// not expose. Used by the guided scan to cap its zoom at the point where
  /// the sensor still delivers real detail.
  private func registerCameraInfoChannel() {
    guard let messenger = registrar(forPlugin: "MarketGozCameraInfo")?.messenger() else {
      return
    }
    let channel = FlutterMethodChannel(name: "marketgoz/camera_info", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "backCameraInfo" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
      else {
        result(nil)
        return
      }
      var info: [String: Double] = [
        // Zoom factor above which the active format is upsampled (no new detail).
        "upscaleThreshold": Double(device.activeFormat.videoZoomFactorUpscaleThreshold)
      ]
      if #available(iOS 15.0, *) {
        info["minFocusDistanceMm"] = Double(device.minimumFocusDistance)  // -1 = unknown
      }
      result(info)
    }
  }
}
