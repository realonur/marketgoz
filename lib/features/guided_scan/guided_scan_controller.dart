import 'dart:async';
import 'dart:io' show File, Platform;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/expiry/expiry_guidance_engine.dart';
import '../../core/expiry/ocr_frame.dart';
import '../../core/services/permission_service.dart';
import '../../core/services/tts_service.dart';
import '../../core/utils/haptic_helper.dart';
import 'frame_math.dart';
import 'frame_recorder.dart';
import 'geiger_haptics.dart';
import 'guided_speaker.dart';
import 'product_name_lookup.dart';
import 'zoom_policy.dart';

enum ScanStatus {
  initializing,
  permissionDenied,
  noCamera,
  error,
  scanning,
  found,
  backgrounded,
}

/// Camera -> ML Kit -> [ExpiryGuidanceEngine] -> speech / haptics / torch.
class GuidedScanController extends ChangeNotifier with WidgetsBindingObserver {
  GuidedScanController({
    required TTSService tts,
    ExpiryGuidanceEngine? engine,
    ProductNameLookup? lookup,
    PermissionService? permissions,
  })  : _speaker = GuidedSpeaker(TtsSpeechSink(tts)),
        _engine = engine ?? ExpiryGuidanceEngine(),
        _lookup = lookup ?? ProductNameLookup(),
        _permissions = permissions ?? PermissionService();

  final GuidedSpeaker _speaker;
  final ExpiryGuidanceEngine _engine;
  final ProductNameLookup _lookup;
  final PermissionService _permissions;
  final GeigerHaptics _haptics = GeigerHaptics();

  /// ~3.5 fps.
  static const _minFrameGap = Duration(milliseconds: 280);

  // ---- public state
  ScanStatus _status = ScanStatus.initializing;
  GuidancePhase _phase = GuidancePhase.waitingForItem;
  String _lastPrompt = '';
  ExpiryResult? _result;
  String? _productName;
  bool _torchOn = false;
  String? _debugLine;

  ScanStatus get status => _status;
  GuidancePhase get phase => _phase;
  String get lastPrompt => _lastPrompt;
  ExpiryResult? get result => _result;
  String? get productName => _productName;
  bool get torchOn => _torchOn;
  String? get debugLine => _debugLine;
  CameraController? get camera => _camera;
  bool get cameraReady => _camera?.value.isInitialized ?? false;

  /// Set by the screen from MediaQuery.accessibleNavigation.
  bool screenReaderActive = false;

  /// Used instead of TTS for the found result when a screen reader is active.
  void Function(String text)? onAnnounce;

  // ---- internals
  CameraController? _camera;
  CameraDescription? _description;
  TextRecognizer? _recognizer;
  BarcodeScanner? _barcodes;
  final BarcodeConfirmer _confirmer = BarcodeConfirmer();
  final FrameRecorder? recorder = kDebugMode ? FrameRecorder() : null;

  bool _busy = false;
  bool _disposed = false;
  bool _streaming = false;
  bool _torchManual = false;
  bool _torchSuggested = false;
  int _epoch = 0; // bumped on reset/pause so stale async work is discarded
  int _processed = 0;
  DateTime _lastStart = DateTime.fromMillisecondsSinceEpoch(0);
  DateTime? _fpsWindowStart;
  int _fpsCount = 0;
  double _fps = 0;

  final FocusThrottle _focusThrottle = FocusThrottle();
  ZoomPolicy? _zoom;
  double _zoomApplied = 1.0;
  static const _cameraInfo = MethodChannel('marketgoz/camera_info');
  UprightGeometry? _geo;

  bool _barcodeDone = false;
  String? _barcode;

  // ------------------------------------------------------------------ start

  bool _observing = false;

  Future<void> start() async {
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
    }
    _setStatus(ScanStatus.initializing);

    final granted = await _permissions.requestCameraPermission();
    if (_disposed) return;
    if (!granted) {
      _setStatus(ScanStatus.permissionDenied);
      unawaited(_speaker.intro(
        'Kamera izni verilmedi. Son kullanma tarihini okuyabilmem için '
        'kameraya ihtiyacım var. Lütfen ayarlardan kamera iznini açın.',
      ));
      return;
    }

    try {
      final cams = await availableCameras();
      if (_disposed) return;
      if (cams.isEmpty) {
        _setStatus(ScanStatus.noCamera);
        unawaited(_speaker.intro('Bu cihazda kamera bulunamadı.'));
        return;
      }
      _description = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );
      await _openCamera();
      if (_disposed) return;
      unawaited(_speaker.intro(
        'Tarih tarama başladı. Ürünü kameranın önüne tutun ve yavaşça çevirin.',
      ));
    } catch (e) {
      debugPrint('GuidedScan start error: $e');
      if (_disposed) return;
      _setStatus(ScanStatus.error);
      unawaited(_speaker.intro('Kamera başlatılamadı. Uygulamayı yeniden açın.'));
    }
  }

  Future<void> _openCamera() async {
    final desc = _description!;
    final cam = CameraController(
      desc,
      ResolutionPreset.high,
      enableAudio: false,
      imageFormatGroup: Platform.isAndroid
          ? ImageFormatGroup.nv21
          : ImageFormatGroup.bgra8888,
    );
    await cam.initialize();
    if (_disposed) {
      await cam.dispose();
      return;
    }
    _camera = cam;
    _recognizer ??= TextRecognizer(script: TextRecognitionScript.latin);
    _barcodes ??= BarcodeScanner(formats: [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upca,
      BarcodeFormat.upce,
    ]);
    await _initZoom(cam);
    if (_disposed) return;
    if (_torchOn) {
      await _applyTorch(true);
    }
    _setStatus(ScanStatus.scanning);
    await _startStream();
  }

  /// Sets up the zoom policy from the controller's range and, on iOS, the
  /// active format's real-detail limit (not exposed by the camera plugin).
  Future<void> _initZoom(CameraController cam) async {
    _zoom = null;
    _zoomApplied = 1.0;
    try {
      final min = await cam.getMinZoomLevel();
      final max = await cam.getMaxZoomLevel();
      double? upscale;
      if (Platform.isIOS) {
        try {
          final info = await _cameraInfo
              .invokeMapMethod<String, double>('backCameraInfo');
          upscale = info?['upscaleThreshold'];
          final focus = info?['minFocusDistanceMm'];
          if (kDebugMode) {
            debugPrint('camera info: upscale=$upscale minFocusMm=$focus');
          }
        } on PlatformException catch (_) {
        } on MissingPluginException catch (_) {}
      }
      _zoom = ZoomPolicy(
        floor: min < 1.0 ? 1.0 : min,
        ceiling: zoomCeiling(pluginMax: max, upscaleThreshold: upscale),
      );
    } catch (e) {
      debugPrint('zoom unavailable: $e'); // scanning still works at 1x
    }
  }

  void _updateZoom(GuidanceOutput out) {
    final cam = _camera, zoom = _zoom, geo = _geo;
    if (cam == null || zoom == null || geo == null) return;
    final next = zoom.decide(
      now: DateTime.now(),
      phase: out.phase,
      targetBox: out.targetBox,
      frameW: geo.width,
      frameH: geo.height,
    );
    if (next != null) unawaited(_setZoom(cam, zoom, next));
  }

  Future<void> _setZoom(
      CameraController cam, ZoomPolicy zoom, double value) async {
    try {
      await cam.setZoomLevel(value);
      _zoomApplied = value;
    } catch (e) {
      debugPrint('setZoomLevel($value): $e');
      zoom.syncTo(_zoomApplied);
    }
  }

  Future<void> _startStream() async {
    final cam = _camera;
    if (cam == null || _streaming || !cam.value.isInitialized) return;
    _streaming = true;
    await cam.startImageStream(_onImage);
  }

  Future<void> _stopStream() async {
    final cam = _camera;
    if (cam == null || !_streaming) return;
    _streaming = false;
    try {
      if (cam.value.isStreamingImages) await cam.stopImageStream();
    } catch (e) {
      debugPrint('stopImageStream: $e');
    }
  }

  Future<void> _closeCamera() async {
    await _stopStream();
    final cam = _camera;
    _camera = null;
    _busy = false;
    try {
      await cam?.dispose();
    } catch (_) {}
  }

  // ------------------------------------------------------------- frame loop

  void _onImage(CameraImage image) {
    if (_busy || _disposed || _status != ScanStatus.scanning) return;
    final now = DateTime.now();
    if (now.difference(_lastStart) < _minFrameGap) return;
    _lastStart = now;
    _busy = true;
    _process(image).whenComplete(() => _busy = false);
  }

  Future<void> _process(CameraImage image) async {
    final epoch = _epoch;
    try {
      final built = _inputImage(image);
      if (built == null) return;
      final (input, rotation) = built;
      final recognizer = _recognizer;
      final barcodes = _barcodes;
      if (recognizer == null) return;

      final runBarcode = !_barcodeDone && barcodes != null && _processed.isEven;
      _processed++;

      final results = await Future.wait<Object?>([
        recognizer.processImage(input),
        if (runBarcode) barcodes.processImage(input),
      ]);
      if (_disposed || epoch != _epoch) return;

      final geo = UprightGeometry.resolve(
        rotationDegrees: rotation,
        bufferWidth: image.width.toDouble(),
        bufferHeight: image.height.toDouble(),
        recognizerAppliesRotation: Platform.isAndroid,
      );
      _geo = geo;
      final text = results[0] as RecognizedText;
      final lines = <OcrLine>[
        for (final b in text.blocks)
          for (final l in b.lines)
            OcrLine(
              text: l.text,
              box: geo.convert(l.boundingBox.left, l.boundingBox.top,
                  l.boundingBox.right, l.boundingBox.bottom),
              confidence: l.confidence,
            ),
      ];
      final plane = image.planes.first;
      final frame = OcrFrame(
        timestamp: DateTime.now(),
        imageWidth: geo.width,
        imageHeight: geo.height,
        lines: lines,
        brightness: meanLuma(
          bytes: plane.bytes,
          width: image.width,
          height: image.height,
          bytesPerRow: plane.bytesPerRow,
          format: Platform.isAndroid ? LumaFormat.nv21 : LumaFormat.bgra8888,
        ),
      );
      recorder?.add(frame);

      if (runBarcode) {
        final list = results[1] as List<Barcode>;
        _onBarcodes(list);
      }

      final out = _engine.process(frame);
      _trackFps(frame, out);
      _handle(out);
    } catch (e, st) {
      debugPrint('GuidedScan frame error: $e\n$st');
    }
  }

  /// Builds the ML Kit input. See [UprightGeometry] for the coordinate rules.
  (InputImage, int)? _inputImage(CameraImage image) {
    final cam = _camera;
    final desc = _description;
    if (cam == null || desc == null) return null;

    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null ||
        (Platform.isAndroid && format != InputImageFormat.nv21) ||
        (Platform.isIOS && format != InputImageFormat.bgra8888)) {
      return null;
    }
    if (image.planes.length != 1) return null;

    final comp = _deviceDegrees[cam.value.deviceOrientation];
    if (comp == null) return null;
    final rotationDegrees = streamRotationDegrees(
      sensorOrientation: desc.sensorOrientation,
      deviceDegrees: comp,
      frontCamera: desc.lensDirection == CameraLensDirection.front,
      isIOS: Platform.isIOS,
    );
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees);
    if (rotation == null) return null;

    final plane = image.planes.first;
    final input = InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
    return (input, rotationDegrees);
  }

  static const _deviceDegrees = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  // ---------------------------------------------------------------- output

  void _handle(GuidanceOutput out) {
    if (_disposed) return;
    _phase = out.phase;

    if (out.justFound && out.result != null) {
      _onFound(out.result!);
      return;
    }

    final p = out.prompt;
    if (p != null && p.text.isNotEmpty) {
      _lastPrompt = p.text;
      _speaker.coach(p.text);
    }
    _haptics.update(out.hapticIntensity);
    _updateTorch(out.torchSuggested);
    _updateZoom(out);
    if (out.phase == GuidancePhase.homingIn ||
        out.phase == GuidancePhase.confirming) {
      _focusOn(out.targetBox);
    }
    notifyListeners();
  }

  void _onFound(ExpiryResult result) {
    _epoch++;
    _result = result;
    _lastPrompt = result.spokenSummary;
    _status = ScanStatus.found;
    _phase = GuidancePhase.found;
    _haptics.stop();
    unawaited(HapticHelper.foundPattern());
    unawaited(_stopStream());
    if (_torchOn) {
      unawaited(_applyTorch(false));
    }
    _announceFound(result.spokenSummary);
    notifyListeners();
  }

  void _announceFound(String text) {
    if (screenReaderActive && onAnnounce != null) {
      onAnnounce!(text);
    } else {
      unawaited(_speaker.found(text));
    }
  }

  // ----------------------------------------------------------------- focus

  void _focusOn(BoxD? box) {
    final cam = _camera, geo = _geo;
    if (box == null || cam == null || geo == null || !cam.value.isInitialized) {
      return;
    }
    final c = normalizedCenter(box, geo);
    final p = c == null
        ? null
        : focusPointForZoom(c, _zoom?.current ?? 1.0,
            fullFieldCoordinates: Platform.isIOS);
    if (p == null || !_focusThrottle.shouldFire(DateTime.now(), p)) return;
    final pt = Offset(p.$1, p.$2);
    unawaited(() async {
      try {
        await cam.setFocusPoint(pt);
        await cam.setExposurePoint(pt);
      } catch (_) {
        // Not supported on every device.
      }
    }());
  }

  // ----------------------------------------------------------------- torch

  /// Auto-on only. When the torch lights the scene the engine stops asking for
  /// it, so honouring the flip back to false would make it flicker; auto-off
  /// happens on found / restart. A manual toggle always wins.
  void _updateTorch(bool suggested) {
    final flipped = suggested != _torchSuggested;
    _torchSuggested = suggested;
    if (flipped && suggested && !_torchManual && !_torchOn) {
      unawaited(_applyTorch(true));
    }
  }

  Future<void> toggleTorch() async {
    _torchManual = true;
    await _applyTorch(!_torchOn);
  }

  Future<void> _applyTorch(bool on) async {
    final cam = _camera;
    _torchOn = on;
    notifyListeners();
    if (cam == null || !cam.value.isInitialized) return;
    try {
      await cam.setFlashMode(on ? FlashMode.torch : FlashMode.off);
    } catch (e) {
      debugPrint('torch error: $e');
      _torchOn = false;
      notifyListeners();
    }
  }

  // --------------------------------------------------------------- barcode

  void _onBarcodes(List<Barcode> list) {
    String? seen;
    for (final b in list) {
      final v = b.rawValue;
      if (v != null && v.isNotEmpty) {
        seen = normalizeBarcode(v);
        break;
      }
    }
    final confirmed = _confirmer.add(seen);
    if (confirmed == null || _barcodeDone) return;
    _barcodeDone = true;
    _barcode = confirmed;
    unawaited(_resolveName(confirmed, _barcodeGeneration));
  }

  int _barcodeGeneration = 0;

  Future<void> _resolveName(String barcode, int generation) async {
    final name = await _lookup.lookup(barcode);
    if (_disposed || generation != _barcodeGeneration || name == null) return;
    _productName = name;
    final text = 'Ürün: $name';
    if (_status == ScanStatus.found && screenReaderActive && onAnnounce != null) {
      onAnnounce!(text);
    } else {
      _speaker.productName(text);
    }
    notifyListeners();
  }

  // --------------------------------------------------------------- actions

  /// Double-tap / "Yeni ürün": forget everything and scan again.
  Future<void> restart() async {
    _epoch++;
    _barcodeGeneration++;
    _engine.reset();
    _focusThrottle.reset();
    _confirmer.reset();
    _haptics.stop();
    recorder?.clear();
    _result = null;
    _productName = null;
    _barcode = null;
    _barcodeDone = false;
    _lastPrompt = '';
    _phase = GuidancePhase.waitingForItem;
    _torchManual = false;
    _torchSuggested = false;
    _processed = 0;
    await _speaker.stop();
    if (_disposed) return;
    if (_camera == null) {
      await start();
      return;
    }
    if (_torchOn) await _applyTorch(false);
    final zoom = _zoom;
    if (zoom != null && _camera != null) {
      zoom.reset();
      await _setZoom(_camera!, zoom, zoom.floor);
    }
    _setStatus(ScanStatus.scanning);
    await _startStream();
    unawaited(_speaker.intro('Yeniden başlıyorum. Ürünü yavaşça çevirin.'));
  }

  /// "Tekrar oku".
  void repeatResult() {
    final r = _result;
    if (r == null) return;
    final n = _productName;
    _announceFound(n == null ? r.spokenSummary : '${r.spokenSummary} Ürün: $n.');
  }

  // ------------------------------------------------------------- lifecycle

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    switch (state) {
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        unawaited(_background());
      case AppLifecycleState.resumed:
        unawaited(_foreground());
      case AppLifecycleState.detached:
        break;
    }
  }

  bool _wasScanning = false;

  Future<void> _background() async {
    if (_status == ScanStatus.backgrounded) return;
    _wasScanning = _status == ScanStatus.scanning;
    if (_status == ScanStatus.scanning) {
      _epoch++;
      _haptics.stop();
      await _speaker.stop();
      await _closeCamera();
      _setStatus(ScanStatus.backgrounded);
    } else if (_status == ScanStatus.found) {
      await _speaker.stop();
    }
  }

  Future<void> _foreground() async {
    if (_status == ScanStatus.backgrounded && _wasScanning) {
      try {
        await _openCamera();
      } catch (e) {
        debugPrint('resume camera error: $e');
        if (!_disposed) _setStatus(ScanStatus.error);
      }
    } else if (_status == ScanStatus.permissionDenied ||
        _status == ScanStatus.error) {
      await start();
    }
  }

  // ----------------------------------------------------------------- debug

  void _trackFps(OcrFrame f, GuidanceOutput out) {
    if (!kDebugMode) return;
    final now = DateTime.now();
    _fpsWindowStart ??= now;
    _fpsCount++;
    final dt = now.difference(_fpsWindowStart!).inMilliseconds;
    if (dt >= 2000) {
      _fps = _fpsCount * 1000 / dt;
      _fpsWindowStart = now;
      _fpsCount = 0;
    }
    _debugLine = '${_fps.toStringAsFixed(1)} fps  '
        '${f.imageWidth.toInt()}x${f.imageHeight.toInt()}  '
        'lines ${f.lines.length}  '
        'lum ${f.brightness?.toStringAsFixed(2) ?? '-'}  '
        'hap ${out.hapticIntensity.toStringAsFixed(2)}'
        '${_barcode != null ? '  bc $_barcode' : ''}';
  }

  /// Debug only: write the recorded frames to a JSON file and share it.
  Future<void> exportRecording() async {
    final rec = recorder;
    if (!kDebugMode || rec == null || rec.length == 0) return;
    final dir = await getApplicationDocumentsDirectory();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final file = File('${dir.path}/marketgoz_frames_$ts.json');
    await file.writeAsString(rec.toJsonString());
    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'MarketGöz frame kaydı (${rec.length} kare)',
    );
  }

  // --------------------------------------------------------------- cleanup

  void _setStatus(ScanStatus s) {
    _status = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    WidgetsBinding.instance.removeObserver(this);
    _haptics.stop();
    unawaited(_speaker.stop());
    unawaited(_closeCamera());
    _recognizer?.close();
    _barcodes?.close();
    super.dispose();
  }
}
