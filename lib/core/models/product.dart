class Product {
  final String barcode;
  final String name;
  final String brand;
  final String category;
  final double price;
  final String weight;
  final DateTime? lastUpdated;
  final DateTime? expiryDate;

  const Product({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.category,
    required this.price,
    required this.weight,
    this.lastUpdated,
    this.expiryDate,
  });

  /// Create a copy with updated fields
  Product copyWith({
    String? barcode,
    String? name,
    String? brand,
    String? category,
    double? price,
    String? weight,
    DateTime? lastUpdated,
    DateTime? expiryDate,
  }) {
    return Product(
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      price: price ?? this.price,
      weight: weight ?? this.weight,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      expiryDate: expiryDate ?? this.expiryDate,
    );
  }

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      barcode: json['barcode'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String? ?? '',
      category: json['category'] as String? ?? '',
      price: (json['price'] as num?)?.toDouble() ?? 0.0,
      weight: json['weight'] as String? ?? '',
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['lastUpdated'] as int)
          : null,
      expiryDate: json['expiryDate'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['expiryDate'] as int)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'barcode': barcode,
      'name': name,
      'brand': brand,
      'category': category,
      'price': price,
      'weight': weight,
      'lastUpdated': lastUpdated?.millisecondsSinceEpoch,
      'expiryDate': expiryDate?.millisecondsSinceEpoch,
    };
  }

  /// Check if product is expired
  bool get isExpired {
    if (expiryDate == null) return false;
    return DateTime.now().isAfter(expiryDate!);
  }

  /// Get days until expiry (negative if expired)
  int? get daysUntilExpiry {
    if (expiryDate == null) return null;
    return expiryDate!.difference(DateTime.now()).inDays;
  }

  /// Get expiry status text in Turkish
  String get expiryStatusText {
    if (expiryDate == null) return 'Son kullanma tarihi bilinmiyor';

    final days = daysUntilExpiry!;
    if (days < 0) {
      return '${-days} gün önce süresi dolmuş!';
    } else if (days == 0) {
      return 'Bugün son kullanma tarihi!';
    } else if (days == 1) {
      return 'Yarın son kullanma tarihi';
    } else if (days <= 7) {
      return '$days gün içinde süresi dolacak';
    } else if (days <= 30) {
      return '${(days / 7).floor()} hafta içinde süresi dolacak';
    } else {
      return '$days gün sonra süresi dolacak';
    }
  }

  @override
  String toString() {
    return 'Product(name: $name, brand: $brand, price: $price TL, expiry: $expiryDate)';
  }
}
