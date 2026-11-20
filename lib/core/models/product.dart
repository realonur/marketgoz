class Product {
  final String barcode;
  final String name;
  final String brand;
  final String category;
  final double price;
  final String weight;
  final DateTime? lastUpdated;

  const Product({
    required this.barcode,
    required this.name,
    required this.brand,
    required this.category,
    required this.price,
    required this.weight,
    this.lastUpdated,
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
  }) {
    return Product(
      barcode: barcode ?? this.barcode,
      name: name ?? this.name,
      brand: brand ?? this.brand,
      category: category ?? this.category,
      price: price ?? this.price,
      weight: weight ?? this.weight,
      lastUpdated: lastUpdated ?? this.lastUpdated,
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
    };
  }

  @override
  String toString() {
    return 'Product(name: $name, brand: $brand, price: $price TL)';
  }
}
