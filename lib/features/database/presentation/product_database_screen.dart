import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/product.dart';
import '../../../core/services/firebase_service.dart';

class ProductDatabaseScreen extends StatefulWidget {
  const ProductDatabaseScreen({super.key});

  @override
  State<ProductDatabaseScreen> createState() => _ProductDatabaseScreenState();
}

class _ProductDatabaseScreenState extends State<ProductDatabaseScreen> {
  final FirebaseService _db = FirebaseService();
  List<Product> _products = [];
  List<Product> _filtered = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await _db.initialize();
    final items = await _db.getAllProducts();
    setState(() {
      _products = items;
      _applyFilter();
      _loading = false;
    });
  }

  void _applyFilter() {
    if (_query.isEmpty) {
      _filtered = List.of(_products);
    } else {
      final q = _query.toLowerCase();
      _filtered = _products.where((p) {
        return p.barcode.contains(q) ||
            p.name.toLowerCase().contains(q) ||
            p.brand.toLowerCase().contains(q) ||
            p.category.toLowerCase().contains(q);
      }).toList();
    }
  }

  Future<void> _addOrEditProduct([Product? product]) async {
    final result = await showDialog<Product>(
      context: context,
      builder: (_) => _ProductEditorDialog(product: product),
    );
    if (result != null) {
      if (_products.any((p) => p.barcode == result.barcode)) {
        await _db.updateProduct(result);
      } else {
        await _db.addProduct(result);
      }
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ürün kaydedildi')),
        );
      }
    }
  }

  Future<void> _editExpiry(Product product) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 1825)), // 5 years ago
      lastDate: now.add(const Duration(days: 1825)),    // 5 years later
      initialDate: product.expiryDate ?? now,
    );
    if (picked != null) {
      await _db.updateProductExpiry(product.barcode, picked);
      await _load();
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Silinsin mi?'),
        content: Text('Barkod ${product.barcode} silinecek.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Sil')),
        ],
      ),
    );
    if (ok == true) {
      await _db.deleteProduct(product.barcode);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ürün Veritabanı'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEditProduct(),
            tooltip: 'Ürün Ekle',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Barkod, marka ya da ürün adı ara...',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                setState(() {
                  _query = v;
                  _applyFilter();
                });
              },
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('Kayıt bulunamadı'))
                    : ListView.separated(
                        itemBuilder: (_, i) {
                          final p = _filtered[i];
                          return ListTile(
                            leading: const Icon(Icons.inventory_2_outlined),
                            title: Text('${p.brand} ${p.name}'),
                            subtitle: Text('${p.barcode} • ${p.category} • ${p.weight}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'SKT',
                                  icon: const Icon(Icons.calendar_month),
                                  onPressed: () => _editExpiry(p),
                                ),
                                IconButton(
                                  tooltip: 'Düzenle',
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _addOrEditProduct(p),
                                ),
                                IconButton(
                                  tooltip: 'Sil',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () => _deleteProduct(p),
                                ),
                              ],
                            ),
                          );
                        },
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemCount: _filtered.length,
                      ),
          ),
        ],
      ),
    );
  }
}

class _ProductEditorDialog extends StatefulWidget {
  final Product? product;
  const _ProductEditorDialog({this.product});

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _barcode;
  late final TextEditingController _brand;
  late final TextEditingController _name;
  late final TextEditingController _category;
  late final TextEditingController _price;
  late final TextEditingController _weight;

  @override
  void initState() {
    super.initState();
    final p = widget.product;
    _barcode = TextEditingController(text: p?.barcode ?? '');
    _brand = TextEditingController(text: p?.brand ?? '');
    _name = TextEditingController(text: p?.name ?? '');
    _category = TextEditingController(text: p?.category ?? '');
    _price = TextEditingController(text: p?.price.toString() ?? '0');
    _weight = TextEditingController(text: p?.weight ?? '');
  }

  @override
  void dispose() {
    _barcode.dispose();
    _brand.dispose();
    _name.dispose();
    _category.dispose();
    _price.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.product == null ? 'Ürün Ekle' : 'Ürünü Düzenle'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _barcode,
                decoration: const InputDecoration(labelText: 'Barkod'),
                keyboardType: TextInputType.number,
                validator: (v) => (v == null || v.isEmpty) ? 'Gerekli' : null,
              ),
              TextFormField(
                controller: _brand,
                decoration: const InputDecoration(labelText: 'Marka'),
                validator: (v) => (v == null || v.isEmpty) ? 'Gerekli' : null,
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Ürün Adı'),
                validator: (v) => (v == null || v.isEmpty) ? 'Gerekli' : null,
              ),
              TextFormField(
                controller: _category,
                decoration: const InputDecoration(labelText: 'Kategori'),
              ),
              TextFormField(
                controller: _price,
                decoration: const InputDecoration(labelText: 'Fiyat (TL)'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
              TextFormField(
                controller: _weight,
                decoration: const InputDecoration(labelText: 'Ağırlık/Hacim'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('İptal'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState?.validate() != true) return;
            final price = double.tryParse(_price.text.trim()) ?? 0.0;
            final p = Product(
              barcode: _barcode.text.trim(),
              name: _name.text.trim(),
              brand: _brand.text.trim(),
              category: _category.text.trim(),
              price: price,
              weight: _weight.text.trim(),
            );
            Navigator.pop(context, p);
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
