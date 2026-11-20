/// Barcode -> product name. Local catalogue first, then Open Food Facts with
/// a short timeout. Fails silently (null) when offline.
library;

import 'dart:async';

import '../../core/services/firebase_service.dart';
import '../../core/services/open_food_service.dart';

typedef NameSource = Future<String?> Function(String barcode);

class ProductNameLookup {
  ProductNameLookup({
    NameSource? local,
    NameSource? remote,
    this.remoteTimeout = const Duration(seconds: 4),
  })  : _local = local ?? _defaultLocal,
        _remote = remote ?? _defaultRemote;

  final NameSource _local;
  final NameSource _remote;
  final Duration remoteTimeout;

  Future<String?> lookup(String barcode) async {
    try {
      final l = (await _local(barcode))?.trim();
      if (l != null && l.isNotEmpty) return l;
    } catch (_) {}
    try {
      final r = (await _remote(barcode).timeout(remoteTimeout))?.trim();
      if (r != null && r.isNotEmpty) return r;
    } catch (_) {}
    return null;
  }

  static Future<String?> _defaultLocal(String barcode) async {
    final p = await FirebaseService().getProduct(barcode);
    if (p == null) return null;
    return '${p.brand} ${p.name}'.trim();
  }

  static Future<String?> _defaultRemote(String barcode) =>
      OpenFoodService().getProductInfo(barcode);
}
