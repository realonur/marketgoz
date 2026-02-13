import 'package:flutter/material.dart';

import '../../../core/models/product_signature.dart';
import '../../../core/services/product_storage_service.dart';
import '../../../core/services/smart_vision_service.dart';
import '../../barcode_scanner/presentation/barcode_scanner_screen.dart';

/// Dialog for teaching/mapping a visual signature to a product
/// Supports:
/// - Creating new product signatures
/// - Adding samples to existing products (improving accuracy)
/// - Linking to barcode/product data
class ProductMapperDialog extends StatefulWidget {
  final HybridDetectionResult detectionResult;
  final SmartVisionService visionService;
  final VoidCallback? onSaved;
  final String? linkedBarcode; // Optional barcode to link
  final String? linkedProductName; // Optional product name from barcode

  const ProductMapperDialog({
    super.key,
    required this.detectionResult,
    required this.visionService,
    this.onSaved,
    this.linkedBarcode,
    this.linkedProductName,
  });

  @override
  State<ProductMapperDialog> createState() => _ProductMapperDialogState();
}

class _ProductMapperDialogState extends State<ProductMapperDialog> {
  late TextEditingController _productNameController;
  bool _isSaving = false;
  List<ProductSignature> _existingSignatures = [];
  ProductSignature? _selectedSignature; // For adding samples to existing
  bool _addToExisting = false;
  String? _scannedBarcode; // Barcode scanned during this dialog
  
  // Tag state: 0 = neutral, 1 = required (green), 2 = excluded (red)
  Map<String, int> _tagStates = {};

  @override
  void initState() {
    super.initState();
    _productNameController = TextEditingController(
      text: widget.linkedProductName ?? widget.detectionResult.detectedProductName ?? '',
    );
    // Initialize all detected tags as neutral (0)
    for (final tag in widget.detectionResult.visualTags.keys) {
      _tagStates[tag] = 0;
    }
    _loadExistingSignatures();
  }

  void _loadExistingSignatures() async {
    final storage = ProductStorageService.instance;
    if (storage.isInitialized) {
      setState(() {
        _existingSignatures = storage.getAllSignatures();
      });
    }
    
    // Also load products from Firebase (barcoded products)
    // These can be linked to visual signatures
    _loadFirebaseProducts();
  }
  
  void _loadFirebaseProducts() async {
    // Firebase products are already loaded in the global list
    // We'll add them as options if they don't already have visual signatures
    // For now, just ensure existing signatures are loaded
    // Future: Add Firebase product list here
  }

  @override
  void dispose() {
    _productNameController.dispose();
    super.dispose();
  }

  /// Save as new signature
  void _saveNewSignature() async {
    final productName = _productNameController.text.trim();
    if (productName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen ürün adı girin')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Create new signature with barcode link if available
      final storage = ProductStorageService.instance;
      final id = storage.generateId();
      
      // Get required (state=1) and excluded (state=2) tags from clickable tags
      final requiredTags = _tagStates.entries
          .where((e) => e.value == 1)
          .map((e) => e.key)
          .toList();
      final excludedTags = _tagStates.entries
          .where((e) => e.value == 2)
          .map((e) => e.key)
          .toList();
      
      final signature = ProductSignature(
        id: id,
        barcode: _scannedBarcode ?? widget.linkedBarcode, // Use scanned or linked barcode
        productName: productName,
        userGivenName: productName,
        label: widget.detectionResult.label,
        aspectRatio: widget.detectionResult.aspectRatio,
        aspectRatioValue: widget.detectionResult.aspectRatioValue,
        dominantColor: widget.detectionResult.dominantColor,
        colorName: widget.detectionResult.colorName,
        colorHSV: widget.detectionResult.colorHSV,
        visualTags: widget.detectionResult.visualTags, // Capture semantic fingerprint
        requiredTags: requiredTags, // AND conditions (green tags)
        excludedTags: excludedTags, // NOT conditions (red tags)
        textKeywords: widget.detectionResult.detectedText.isNotEmpty
            ? widget.detectionResult.detectedText
                .split(RegExp(r'\s+'))
                .where((w) => w.length > 3)
                .map((w) => w.toLowerCase())
                .toSet()
                .toList()
            : [],
        sampleCount: 1,
      );
      
      await storage.saveSignature(signature);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ "$productName" kaydedildi')),
        );
        widget.onSaved?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Add sample to existing signature (improves accuracy)
  void _addSampleToExisting() async {
    if (_selectedSignature == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen bir ürün seçin')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final storage = ProductStorageService.instance;
      await storage.improveSignature(_selectedSignature!.id, widget.detectionResult);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✓ "${_selectedSignature!.displayName}" için örnek eklendi (${_selectedSignature!.sampleCount + 1} örnek)')),
        );
        widget.onSaved?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(
            widget.linkedBarcode != null ? Icons.link : Icons.add_a_photo,
            color: Colors.purple,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.linkedBarcode != null ? 'Görsel İmza Ekle' : 'Ürün Tanıt',
              style: const TextStyle(fontSize: 18),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Display detected visual signature
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  // Color preview
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: widget.detectionResult.dominantColor,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Algılanan: ${widget.detectionResult.label}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          'Renk: ${widget.detectionResult.colorName}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        Text(
                          'Oran: ${widget.detectionResult.aspectRatio}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                        if (widget.detectionResult.detectedText.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Metin: "${widget.detectionResult.detectedText.replaceAll('\n', ' ')}"',
                              style: const TextStyle(
                                color: Colors.indigo,
                                fontSize: 11,
                                fontStyle: FontStyle.italic,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Toggle: New vs Existing
            if (_existingSignatures.isNotEmpty) ...[
              Container(
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _addToExisting = false),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: !_addToExisting ? Colors.blue : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Yeni Ürün',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: !_addToExisting ? Colors.white : Colors.blue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _addToExisting = true),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: _addToExisting ? Colors.green : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'Mevcut Ürün',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: _addToExisting ? Colors.white : Colors.green,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            
            // Option 1: New product
            if (!_addToExisting) ...[
              const Text(
                'Ürün Adı:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _productNameController,
                autofocus: widget.linkedProductName == null,
                decoration: InputDecoration(
                  hintText: 'Ürün adını girin',
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.shopping_bag),
                  suffixIcon: widget.linkedBarcode != null
                      ? const Icon(Icons.link, color: Colors.green)
                      : null,
                ),
              ),
              if (widget.linkedBarcode != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    const Icon(Icons.qr_code, size: 16, color: Colors.grey),
                    const SizedBox(width: 4),
                    Text(
                      'Barkod: ${widget.linkedBarcode}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ],
              
              // Show scanned barcode if available
              if (_scannedBarcode != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, size: 16, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Barkod: $_scannedBarcode',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        onPressed: () => setState(() => _scannedBarcode = null),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
              ],
              
              // Barcode scan button (if no barcode linked yet)
              if (widget.linkedBarcode == null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final result = await Navigator.push<String>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BarcodeScannerScreen(),
                        ),
                      );
                      if (result != null && mounted) {
                        setState(() {
                          _scannedBarcode = result;
                        });
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner),
                    label: Text(_scannedBarcode == null 
                        ? 'Barkod Tara' 
                        : 'Barkodu Değiştir'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.indigo,
                      side: const BorderSide(color: Colors.indigo),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
              
              // Clickable Tag Selection (3-state: neutral → required → excluded)
              if (widget.detectionResult.visualTags.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Etiket Seçimi (Dokunarak Değiştir):',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            width: 12, height: 12,
                            decoration: BoxDecoration(
                              color: Colors.grey[400],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('Nötr', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 12),
                          Container(
                            width: 12, height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('Zorunlu (AND)', style: TextStyle(fontSize: 11)),
                          const SizedBox(width: 12),
                          Container(
                            width: 12, height: 12,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Text('Hariç (NOT)', style: TextStyle(fontSize: 11)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: _tagStates.entries.map((entry) {
                          final tag = entry.key;
                          final state = entry.value;
                          
                          Color bgColor;
                          Color textColor;
                          IconData? icon;
                          
                          switch (state) {
                            case 1: // Required (green)
                              bgColor = Colors.green;
                              textColor = Colors.white;
                              icon = Icons.check;
                              break;
                            case 2: // Excluded (red)
                              bgColor = Colors.red;
                              textColor = Colors.white;
                              icon = Icons.close;
                              break;
                            default: // Neutral (gray)
                              bgColor = Colors.grey[300]!;
                              textColor = Colors.black87;
                              icon = null;
                          }
                          
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                // Cycle: 0 (neutral) → 1 (required) → 2 (excluded) → 0
                                _tagStates[tag] = (state + 1) % 3;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: state == 0 ? Colors.grey : bgColor,
                                  width: 1.5,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (icon != null) ...[
                                    Icon(icon, size: 14, color: textColor),
                                    const SizedBox(width: 4),
                                  ],
                                  Text(
                                    tag,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: textColor,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ],
            ],
            
            // Option 2: Add to existing product
            if (_addToExisting) ...[
              const Text(
                'Mevcut Ürüne Örnek Ekle:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Bu, ürün tanıma doğruluğunu artırır',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
              const SizedBox(height: 8),
              // Use Column instead of ListView to avoid intrinsic dimension issues in AlertDialog
              if (_existingSignatures.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  child: const Text(
                    'Henüz kayıtlı ürün yok.\nÖnce yeni bir ürün ekleyin.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              else
                ...(_existingSignatures.take(5).map((sig) {
                  final isSelected = _selectedSignature?.id == sig.id;
                  return InkWell(
                    onTap: () => setState(() => _selectedSignature = sig),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.green.withOpacity(0.2) : null,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              color: sig.dominantColor,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.grey),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(sig.displayName, style: const TextStyle(fontWeight: FontWeight.w500)),
                                Text(
                                  '${sig.sampleCount} örnek • ${sig.colorName}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(Icons.check_circle, color: Colors.green, size: 20),
                        ],
                      ),
                    ),
                  );
                }).toList()),
              if (_existingSignatures.length > 5)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '+${_existingSignatures.length - 5} daha fazla ürün...',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton.icon(
          onPressed: _isSaving
              ? null
              : (_addToExisting ? _addSampleToExisting : _saveNewSignature),
          icon: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_addToExisting ? Icons.add_photo_alternate : Icons.save),
          label: Text(_addToExisting ? 'Örnek Ekle' : 'Kaydet'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _addToExisting ? Colors.green : Colors.purple,
            foregroundColor: Colors.white,
          ),
        ),
      ],
    );
  }
}

/// Dialog to view and manage all stored product signatures
class SignatureDatabaseDialog extends StatefulWidget {
  final SmartVisionService visionService;

  const SignatureDatabaseDialog({
    super.key,
    required this.visionService,
  });

  @override
  State<SignatureDatabaseDialog> createState() => _SignatureDatabaseDialogState();
}

class _SignatureDatabaseDialogState extends State<SignatureDatabaseDialog> {
  List<ProductSignature> _signatures = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _loadData() {
    final storage = ProductStorageService.instance;
    if (storage.isInitialized) {
      setState(() {
        _signatures = storage.getAllSignatures();
      });
    }
  }

  Future<void> _deleteSignature(String id) async {
    final storage = ProductStorageService.instance;
    await storage.deleteSignature(id);
    _loadData();
  }

  Future<void> _bindBarcodeToSignature(BuildContext context, ProductSignature sig) async {
    final controller = TextEditingController(text: sig.barcode ?? '');
    
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(sig.barcode == null ? 'Barkod Bağla' : 'Barkodu Güncelle'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('${sig.displayName} için barkod girin:'),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Barkod',
                  hintText: 'Örn: 8690000000000',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              // Scan barcode button
              OutlinedButton.icon(
                onPressed: () async {
                  // Close this dialog, open scanner, then reopen with result
                  Navigator.pop(ctx);
                  
                  final scanned = await Navigator.push<String>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const BarcodeScannerScreen(returnBarcodeOnly: true),
                    ),
                  );
                  
                  if (scanned != null && scanned.isNotEmpty && context.mounted) {
                    // Directly save the scanned barcode
                    final updated = sig.copyWith(barcode: scanned);
                    await ProductStorageService.instance.saveSignature(updated);
                    _loadData();
                    
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Barkod "$scanned" bağlandı'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Barkod Tara'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, controller.text.trim()),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    
    if (result != null && result.isNotEmpty) {
      final updated = sig.copyWith(barcode: result);
      await ProductStorageService.instance.saveSignature(updated);
      _loadData();
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Barkod "${sig.displayName}" ürününe bağlandı'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.fingerprint, color: Colors.purple),
          const SizedBox(width: 8),
          const Text('Ürün İmzaları'),
          const Spacer(),
          Text(
            '${_signatures.length}',
            style: TextStyle(color: Colors.grey[600], fontSize: 14),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: _signatures.isEmpty
            ? const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.inbox, size: 48, color: Colors.grey),
                    SizedBox(height: 8),
                    Text('Henüz ürün kaydedilmedi'),
                  ],
                ),
              )
            : ListView.builder(
                itemCount: _signatures.length,
                itemBuilder: (context, index) {
                  final sig = _signatures[index];
                  return Card(
                    child: ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: sig.dominantColor,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey),
                        ),
                        child: Center(
                          child: Text(
                            '${sig.sampleCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              shadows: [Shadow(color: Colors.black, blurRadius: 2)],
                            ),
                          ),
                        ),
                      ),
                      title: Text(sig.displayName),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${sig.label} • ${sig.colorName} • ${sig.aspectRatio}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          if (sig.barcode != null)
                            Text(
                              '📊 ${sig.barcode}',
                              style: const TextStyle(fontSize: 10, color: Colors.blue),
                            ),
                          Text(
                            '${sig.sampleCount} örnek • ${sig.detectionCount} algılama',
                            style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                          ),
                        ],
                      ),
                      isThreeLine: true,
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Barkod Bağla button
                          IconButton(
                            icon: Icon(
                              sig.barcode == null ? Icons.link : Icons.edit,
                              color: Colors.green,
                              size: 20,
                            ),
                            tooltip: sig.barcode == null ? 'Barkod Bağla' : 'Barkodu Güncelle',
                            onPressed: () => _bindBarcodeToSignature(context, sig),
                          ),
                          // Delete button
                          IconButton(
                            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            tooltip: 'Sil',
                            onPressed: () async {
                              final confirm = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: const Text('Silmek istediğinize emin misiniz?'),
                                  content: Text('"${sig.displayName}" silinecek.'),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, false),
                                      child: const Text('İptal'),
                                    ),
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Sil', style: TextStyle(color: Colors.red)),
                                    ),
                                  ],
                                ),
                              );
                              if (confirm == true) {
                                await _deleteSignature(sig.id);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
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
