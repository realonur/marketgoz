import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/product_signature.dart';

/// Lightweight, clean UltralyticsSmartVision wrapper used for debugging
class UltralyticsSmartVision extends StatefulWidget {
  final String modelPath;

  const UltralyticsSmartVision({
    super.key,
    required this.modelPath,
    this.task,
    this.onDetection,
  });

  @override
  State<UltralyticsSmartVision> createState() => _UltralyticsSmartVisionState();
}

class _UltralyticsSmartVisionState extends State<UltralyticsSmartVision> {
  bool _modelOk = false;
  String _info = '';
  String _lastResultInfo = '';

  @override
  void initState() {
    super.initState();
    _checkAsset();
  }

  import 'package:flutter/material.dart';

  /// Smart Vision removed
  /// Placeholder widget kept to avoid build breakage during cleanup.
  class UltralyticsSmartVision extends StatelessWidget {
    const UltralyticsSmartVision({super.key});

    @override
    Widget build(BuildContext context) {
      return Center(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Smart Vision removed',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }
  }
          task: widget.task,
