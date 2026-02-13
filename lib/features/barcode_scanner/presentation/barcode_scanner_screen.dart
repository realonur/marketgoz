import 'dart:typed_data';
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/haptic_helper.dart';
import '../../result/presentation/result_screen.dart';
import '../provider/barcode_scanner_provider.dart';

class BarcodeScannerScreen extends StatefulWidget {
  final bool returnBarcodeOnly;

  const BarcodeScannerScreen({
    super.key,
    this.returnBarcodeOnly = false,
  });

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> with WidgetsBindingObserver {
  CameraController? _cameraController;
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  bool _isInitialized = false;
  bool _isDetecting = false;
  bool _showDebugOverlay = false;
  bool _permissionDenied = false;
  String _debugInfo = 'Initializing...';
  int _frameCount = 0;
  String _lastDetectedBarcode = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkAndRequestPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _permissionDenied) {
      _checkAndRequestPermission();
    }
  }

  Future<void> _checkAndRequestPermission() async {
    setState(() {
      _debugInfo = 'Checking camera permission...';
      _permissionDenied = false;
    });

    var status = await Permission.camera.status;
    debugPrint('📷 Camera status: $status');

    if (status.isGranted) {
      _initializeCamera();
      return;
    }

    setState(() {
      _debugInfo = 'Requesting camera permission...';
    });

    status = await Permission.camera.request();
    debugPrint('📷 After request: $status');

    if (status.isGranted) {
      _initializeCamera();
    } else {
      setState(() {
        _permissionDenied = true;
        _debugInfo = status.isPermanentlyDenied
            ? 'Kamera izni kalıcı olarak reddedildi.\nAyarlardan etkinleştirin.'
            : 'Kamera izni reddedildi.';
      });
    }
  }

  Future<void> _initializeCamera() async {
    try {
      setState(() {
        _debugInfo = 'Getting available cameras...';
      });

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _debugInfo = 'No cameras found';
        });
        return;
      }

      // Prefer the back camera for better barcode focus
      final selected = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      setState(() {
        _debugInfo = 'Initializing camera controller...';
      });

      _cameraController = CameraController(
        selected,
        ResolutionPreset.medium,
        enableAudio: false,
        // BGRA8888 is more universally supported across devices
        imageFormatGroup: ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      await _cameraController!.setFlashMode(FlashMode.off);

      if (mounted) {
        setState(() {
          _isInitialized = true;
          _debugInfo = 'Camera ready. Starting scan...';
        });

        if (!widget.returnBarcodeOnly) {
          final provider = Provider.of<BarcodeScannerProvider?>(context, listen: false);
          provider?.startScanning();
        }
        _startImageStream();
      }
    } catch (e) {
      setState(() {
        _debugInfo = 'Camera error: $e';
      });
      debugPrint('Error initializing camera: $e');
    }
  }

  void _startImageStream() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _cameraController!.startImageStream((image) async {
      _frameCount++;
      if (_isDetecting) return;
      _isDetecting = true;

      BarcodeScanner? barcodeScanner;
      try {
        if (mounted && _showDebugOverlay) {
          setState(() {
            _debugInfo = 'Frame #$_frameCount - Processing...\nSize: ${image.width}x${image.height}';
          });
        }

        final inputImage = _convertCameraImage(image);
        if (inputImage == null) {
          _isDetecting = false;
          return;
        }

        // Only scan product barcodes (EAN/UPC), not QR codes
        barcodeScanner = BarcodeScanner(formats: [
          BarcodeFormat.ean13,
          BarcodeFormat.ean8,
          BarcodeFormat.upca,
          BarcodeFormat.upce,
        ]);

        final barcodes = await barcodeScanner.processImage(inputImage);

        String? detectedCode;
        String detectionSource = 'barcode';

        if (barcodes.isNotEmpty && mounted) {
          final barcode = barcodes.first;
          if (barcode.rawValue != null) {
            detectedCode = barcode.rawValue!;
            _lastDetectedBarcode = detectedCode;

            if (_showDebugOverlay) {
              setState(() {
                _debugInfo = 'BARCODE FOUND!\n${barcode.rawValue}\nType: ${barcode.format.name}';
              });
            }
          }
        }

        if (detectedCode == null) {
          final recognizedText = await _textRecognizer.processImage(inputImage);
          final ocrCandidate = _extractNumericBarcode(recognizedText);
          if (ocrCandidate != null) {
            detectedCode = ocrCandidate;
            detectionSource = 'ocr_digits';
            _lastDetectedBarcode = detectedCode;

            if (_showDebugOverlay) {
              setState(() {
                _debugInfo = 'OCR DIGITS FOUND!\n$detectedCode';
              });
            }
          }
        }

        if (mounted && _showDebugOverlay) {
          setState(() {
            _debugInfo = 'Frame #$_frameCount\nSize: ${image.width}x${image.height}\nBarcodes found: ${barcodes.length}\nLast detected: ${_lastDetectedBarcode.isEmpty ? "-" : _lastDetectedBarcode}\nSource: $detectionSource';
          });
        }

        if (detectedCode != null && mounted) {
          await HapticHelper.scanSuccess();
          await _cameraController?.stopImageStream();

          if (widget.returnBarcodeOnly) {
            Navigator.of(context).pop(detectedCode);
            return;
          }

          final provider = Provider.of<BarcodeScannerProvider?>(context, listen: false);

          if (provider == null) {
            Navigator.of(context).pop(detectedCode);
            return;
          }

          await provider.processBarcode(detectedCode);

          if (mounted && _showDebugOverlay) {
            final product = provider.lastScanResult?.product;
            final source = provider.lastSource ?? detectionSource;
            final status = provider.error ?? 'found';
            setState(() {
              _debugInfo = 'RESULT\nBarcode: $detectedCode\nSource: $source\nProduct: ${product?.name ?? '-'}\nStatus: $status';
            });
          }

          if (mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(
                builder: (context) => const ResultScreen(),
              ),
            );
          }
        }
      } catch (e) {
        if (mounted && _showDebugOverlay) {
          setState(() {
            _debugInfo = 'Error: $e';
          });
        }
        debugPrint('Error detecting barcode: $e');
      } finally {
        await barcodeScanner?.close();
        _isDetecting = false;
      }
    });
  }

  InputImage? _convertCameraImage(CameraImage image) {
    try {
      final camera = _cameraController?.description;
      final rotation = InputImageRotationValue.fromRawValue(camera?.sensorOrientation ?? 0) ??
          InputImageRotation.rotation0deg;

      // Concatenate planes for BGRA8888 input
      final buffer = <int>[];
      for (final plane in image.planes) {
        buffer.addAll(plane.bytes);
      }
      final bytes = Uint8List.fromList(buffer);

      return InputImage.fromBytes(
        bytes: bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.bgra8888,
          bytesPerRow: image.planes.first.bytesPerRow,
        ),
      );
    } catch (e) {
      debugPrint('Error converting image: $e');
      return null;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cameraController?.dispose();
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            if (_isInitialized && _cameraController != null && _cameraController!.value.isInitialized)
              Positioned.fill(child: CameraPreview(_cameraController!))
            else if (_permissionDenied)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.camera_alt_outlined, size: 80, color: Colors.yellow),
                      const SizedBox(height: 24),
                      const Text(
                        'Kamera İzni Gerekli',
                        style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _debugInfo,
                        style: const TextStyle(color: Colors.white70, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
                      ElevatedButton.icon(
                        onPressed: () async {
                          final status = await Permission.camera.status;
                          if (status.isPermanentlyDenied) {
                            openAppSettings();
                          } else {
                            _checkAndRequestPermission();
                          }
                        },
                        icon: const Icon(Icons.settings),
                        label: const Text('İzin Ver', style: TextStyle(fontSize: 18)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellow,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.yellow),
                    const SizedBox(height: 20),
                    Text(
                      _debugInfo,
                      style: const TextStyle(color: Colors.white),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),

            if (_isInitialized)
              Center(
                child: Container(
                  width: 300,
                  height: 200,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.yellow, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),

            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Semantics(
                liveRegion: true,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  color: Colors.black54,
                  child: const Text(
                    'Barkodu çerçeve içine hizalayın',
                    style: TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),

            Positioned(
              top: 16,
              left: 16,
              child: Semantics(
                label: 'Geri',
                button: true,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, size: 32),
                  color: Colors.white,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),

            Positioned(
              bottom: 30,
              right: 20,
              child: GestureDetector(
                onTap: () {
                  setState(() {
                    _showDebugOverlay = !_showDebugOverlay;
                  });
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _showDebugOverlay ? Colors.green : Colors.grey.withOpacity(0.7),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: const Icon(Icons.bug_report, color: Colors.white, size: 30),
                ),
              ),
            ),

            if (_showDebugOverlay)
              Positioned(
                bottom: 100,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green, width: 2),
                  ),
                  child: Consumer<BarcodeScannerProvider>(
                    builder: (context, provider, _) {
                      final product = provider.lastScanResult?.product;
                      final status = provider.error ?? 'ok';
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '🔧 DEBUG INFO',
                            style: TextStyle(color: Colors.green, fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _debugInfo,
                            style: const TextStyle(color: Colors.white, fontSize: 14, fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Camera: ${_isInitialized ? "Ready" : "Not ready"}',
                            style: TextStyle(color: _isInitialized ? Colors.green : Colors.red, fontSize: 14),
                          ),
                          if (_lastDetectedBarcode.isNotEmpty)
                            Text(
                              'Last barcode: $_lastDetectedBarcode',
                              style: const TextStyle(color: Colors.yellow, fontSize: 14),
                            ),
                          if (provider.lastSource != null)
                            Text(
                              'Source: ${provider.lastSource}',
                              style: const TextStyle(color: Colors.cyan, fontSize: 14),
                            ),
                          if (product != null)
                            Text(
                              'Product: ${product.brand} ${product.name}'.trim(),
                              style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
                            ),
                          if (provider.error != null)
                            Text(
                              'Error: $status',
                              style: const TextStyle(color: Colors.redAccent, fontSize: 14),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Extracts a likely barcode number from recognized text (EAN8/12/13/14 sized).
  String? _extractNumericBarcode(RecognizedText recognizedText) {
    final cleaned = recognizedText.text.replaceAll(RegExp(r'\s'), '');
    final matches = RegExp(r'\d{8,14}').allMatches(cleaned);
    for (final match in matches) {
      final candidate = match.group(0);
      if (candidate == null) continue;
      if (candidate.length == 8 || candidate.length == 12 || candidate.length == 13 || candidate.length == 14) {
        return candidate;
      }
    }
    return null;
  }
}
