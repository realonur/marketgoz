import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/product_signature.dart';
import '../../../core/services/product_storage_service.dart';
import '../../../core/services/smart_vision_service.dart';
import '../../barcode_scanner/presentation/barcode_scanner_screen.dart';

/// Smart Vision signature database dialog removed.
/// Placeholder kept to avoid import breakage.
class SmartVisionDatabaseDialog extends StatefulWidget {
  final SmartVisionService visionService;

  const SmartVisionDatabaseDialog({
    super.key,
    required this.visionService,
  });

  @override
  State<SmartVisionDatabaseDialog> createState() => _SmartVisionDatabaseDialogState();
}

class _SmartVisionDatabaseDialogState extends State<SmartVisionDatabaseDialog> {
  late List<ProductSignature> _signatures;
  String _sortBy = 'detections'; // 'detections', 'name', 'label'

  @override
  void initState() {
    super.initState();
    _loadSignatures();
  }

  void _loadSignatures() {
    _signatures = widget.visionService.getAllSignatures();
    _sortSignatures();
  }

  void _sortSignatures() {
    switch (_sortBy) {
      case 'detections':
        _signatures.sort((a, b) => b.detectionCount.compareTo(a.detectionCount));
        break;
      case 'name':
        _signatures.sort((a, b) => a.productName.compareTo(b.productName));
        break;
      case 'label':
        _signatures.sort((a, b) => a.yoloLabel.compareTo(b.yoloLabel));
        break;
    }
  }

  Future<void> _deleteSignature(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sil'),
        content: const Text('Bu ürün imzasını silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Sil',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await widget.visionService.deleteSignature(id);
      _loadSignatures();
      setState(() {});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ürün imzası silindi'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Smart Vision İmzaları'),
      content: SizedBox(
        width: double.maxFinite,
        height: 480,
        child: _signatures.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(32.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz ürün imzası kaydedilmedi',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Ürün özellikleri algılanınca burada görünecek',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[500],
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        FilterChip(
                          label: const Text('Sıkça Algılandı'),
                          selected: _sortBy == 'detections',
                          onSelected: (_) {
                            setState(() {
                              _sortBy = 'detections';
                              _sortSignatures();
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Ad'),
                          selected: _sortBy == 'name',
                          onSelected: (_) {
                            setState(() {
                              _sortBy = 'name';
                              _sortSignatures();
                            });
                          },
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Label'),
                          selected: _sortBy == 'label',
                          onSelected: (_) {
                            setState(() {
                              _sortBy = 'label';
                              _sortSignatures();
                            });
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Divider(),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _signatures.length,
                      itemBuilder: (context, index) {
                        final sig = _signatures[index];
                        return _SignatureListItem(
                          signature: sig,
                          visionService: widget.visionService,
                          onDelete: () => _deleteSignature(sig.id),
                          onUpdated: () {
                            _loadSignatures();
                            setState(() {});
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

/// Individual signature list item
class _SignatureListItem extends StatelessWidget {
  final ProductSignature signature;
  final SmartVisionService visionService;
  final VoidCallback onDelete;
  final VoidCallback onUpdated;

  const _SignatureListItem({
    required this.signature,
    required this.visionService,
    required this.onDelete,
    required this.onUpdated,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: signature.dominantColor.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: signature.dominantColor, width: 2),
                  ),
                  child: Center(
                    child: Text(
                      '${signature.sampleCount}',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(signature.productName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('${signature.yoloLabel} • ${signature.colorName}', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                      if (signature.barcode != null)
                        Row(
                          children: [
                            const Icon(Icons.qr_code, size: 12, color: Colors.green),
                            const SizedBox(width: 4),
                            Text(signature.barcode!, style: const TextStyle(fontSize: 11, color: Colors.green)),
                          ],
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Buttons row - ALWAYS VISIBLE
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _bindBarcode(context),
                  icon: Icon(signature.barcode == null ? Icons.link : Icons.edit, size: 18),
                  label: Text(signature.barcode == null ? 'Barkod Bağla' : 'Güncelle'),
                  style: TextButton.styleFrom(foregroundColor: Colors.green),
                ),
                IconButton(onPressed: onDelete, icon: const Icon(Icons.delete, color: Colors.red)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _bindBarcode(BuildContext context) async {
    final controller = TextEditingController(text: signature.barcode ?? '');

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(signature.barcode == null ? 'Barkod Bağla' : 'Barkodu Güncelle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Barkod',
                  hintText: 'Örn. 8691234567890',
                ),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final scanned = await Navigator.of(context).push<String>(
                      MaterialPageRoute(
                        builder: (_) => const BarcodeScannerScreen(returnBarcodeOnly: true),
                        fullscreenDialog: true,
                      ),
                    );

                    if (scanned != null && scanned.isNotEmpty) {
                      controller.text = scanned;
                    }
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Barkodu Tara'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        );
      },
    );

    if (result == null || result.isEmpty) return;

    final updated = signature.copyWith(barcode: result);
    await ProductStorageService.instance.saveSignature(updated);
    onUpdated();

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Barkod bağlandı: $result'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  String _formatDateTime(DateTime dt) {
    final twoDigits = (int n) => n.toString().padLeft(2, '0');
    final date = '${twoDigits(dt.day)}.${twoDigits(dt.month)}.${dt.year}';
    final time = '${twoDigits(dt.hour)}:${twoDigits(dt.minute)}';
    return '$date $time';
  }

  String _formatSignatureAsText(ProductSignature sig) {
    final buffer = StringBuffer()
      ..writeln('ID: ${sig.id}')
      ..writeln('Ürün: ${sig.productName}')
      ..writeln('Label: ${sig.yoloLabel}')
      ..writeln('Oran: ${sig.aspectRatio}')
      ..writeln('Renk: ${sig.colorName}')
      ..writeln('Algılanma: ${sig.detectionCount}x');

    if (sig.barcode != null && sig.barcode!.isNotEmpty) {
      buffer.writeln('Barkod: ${sig.barcode}');
    }

    if (sig.lastUsedAt != null) {
      buffer.writeln('Son Kullanım: ${_formatDateTime(sig.lastUsedAt!)}');
    }

    return buffer.toString();
  }
}

/// Detail row for signature information
class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontFamily: 'monospace',
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
