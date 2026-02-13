import 'package:flutter/material.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/models/expiry_date.dart';

class ExpiryStatusCard extends StatelessWidget {
  final ExpiryDate expiryDate;

  const ExpiryStatusCard({
    super.key,
    required this.expiryDate,
  });

  @override
  Widget build(BuildContext context) {
    final statusColor = expiryDate.status.color;

    return Semantics(
      label: 'Son kullanma tarihi durumu: ${expiryDate.statusMessage}',
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: statusColor,
            width: 4,
          ),
        ),
        color: statusColor.withOpacity(0.1),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              // Status icon
              Icon(
                _getStatusIcon(),
                color: statusColor,
                size: 72,
              ),
              const SizedBox(height: 16),
              
              // Status label
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  expiryDate.status.label,
                  style: AppTextStyles.heading2.copyWith(
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              
              // Status message
              Text(
                expiryDate.statusMessage,
                style: AppTextStyles.expiryStatus.copyWith(
                  color: statusColor,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              
              // Date
              if (expiryDate.date != null)
                Text(
                  'Tarih: ${expiryDate.formattedDate}',
                  style: AppTextStyles.bodyLarge.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getStatusIcon() {
    switch (expiryDate.status) {
      case ExpiryStatus.safe:
        return Icons.check_circle;
      case ExpiryStatus.warning:
        return Icons.warning;
      case ExpiryStatus.danger:
        return Icons.error;
      case ExpiryStatus.expired:
        return Icons.block;
      case ExpiryStatus.unknown:
        return Icons.help;
    }
  }
}
