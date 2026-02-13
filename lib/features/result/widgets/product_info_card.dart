import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/models/product.dart';

class ProductInfoCard extends StatelessWidget {
  final Product product;

  const ProductInfoCard({
    super.key,
    required this.product,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Ürün bilgileri: ${product.brand} ${product.name}, Fiyat: ${product.price} lira',
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(
            color: AppColors.primary,
            width: 3,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Success icon
              const Center(
                child: Icon(
                  Icons.check_circle,
                  color: AppColors.success,
                  size: 64,
                ),
              ),
              const SizedBox(height: 16),
              
              // Product name
              Text(
                product.name,
                style: AppTextStyles.productName,
              ),
              const SizedBox(height: 8),
              
              // Brand
              if (product.brand.isNotEmpty)
                Text(
                  'Marka: ${product.brand}',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 8),
              
              // Category
              if (product.category.isNotEmpty)
                Text(
                  'Kategori: ${product.category}',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 8),
              
              // Weight
              if (product.weight.isNotEmpty)
                Text(
                  'Gramaj: ${product.weight}',
                  style: AppTextStyles.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              const SizedBox(height: 16),
              
              // Divider
              const Divider(thickness: 2),
              const SizedBox(height: 16),
              
              // Price
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Fiyat:',
                    style: AppTextStyles.heading3,
                  ),
                  Text(
                    product.price % 1 == 0
                      ? '${product.price.toInt()} ₺'
                      : '${product.price.toStringAsFixed(2)} ₺',
                    style: AppTextStyles.productPrice,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
