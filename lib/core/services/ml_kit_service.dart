import 'dart:ui' show Size;
import 'package:google_mlkit_barcode_scanning/google_mlkit_barcode_scanning.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:camera/camera.dart';

class MLKitService {
  static final MLKitService _instance = MLKitService._internal();
  factory MLKitService() => _instance;
  MLKitService._internal();

  // Barcode scanner configured for common retail formats
  final BarcodeScanner _barcodeScanner = BarcodeScanner(
    formats: [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upca,
      BarcodeFormat.upce,
    ],
  );

  // Text recognizer for OCR (Latin script for Turkish)
  final TextRecognizer _textRecognizer = TextRecognizer(
    script: TextRecognitionScript.latin,
  );

  /// Scan barcode from camera image
  Future<List<Barcode>> scanBarcodes(CameraImage image) async {
    try {
      final inputImage = _convertCameraImage(image);
      if (inputImage == null) return [];

      final barcodes = await _barcodeScanner.processImage(inputImage);
      return barcodes;
    } catch (e) {
      print('Error scanning barcodes: $e');
      return [];
    }
  }

  /// Scan barcode from input image
  Future<List<Barcode>> scanBarcodesFromImage(InputImage inputImage) async {
    try {
      final barcodes = await _barcodeScanner.processImage(inputImage);
      return barcodes;
    } catch (e) {
      print('Error scanning barcodes from image: $e');
      return [];
    }
  }

  /// Recognize text from camera image
  Future<RecognizedText?> recognizeText(InputImage inputImage) async {
    try {
      final recognizedText = await _textRecognizer.processImage(inputImage);
      return recognizedText;
    } catch (e) {
      print('Error recognizing text: $e');
      return null;
    }
  }

  /// Extract all text blocks from recognized text
  List<String> extractTextBlocks(RecognizedText recognizedText) {
    final textBlocks = <String>[];
    
    for (final block in recognizedText.blocks) {
      textBlocks.add(block.text);
      
      // Also add individual lines for better date detection
      for (final line in block.lines) {
        textBlocks.add(line.text);
      }
    }
    
    return textBlocks;
  }

  /// Convert CameraImage to InputImage (helper method)
  InputImage? _convertCameraImage(CameraImage image) {
    try {
      // Note: This is a simplified conversion
      // For production, implement proper rotation and format handling
      return InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );
    } catch (e) {
      print('Error converting camera image: $e');
      return null;
    }
  }

  /// Dispose of ML Kit resources
  void dispose() {
    _barcodeScanner.close();
    _textRecognizer.close();
  }
}
