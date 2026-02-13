import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_text_styles.dart';
import '../../../core/utils/haptic_helper.dart';
import '../../barcode_scanner/provider/barcode_scanner_provider.dart';
import '../../ocr_scanner/provider/ocr_scanner_provider.dart';
import '../widgets/expiry_status_card.dart';
import '../widgets/product_info_card.dart';

class ResultScreen extends StatefulWidget {
  final bool showExpiryOnly;

  const ResultScreen({
    super.key,
    this.showExpiryOnly = false,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  @override
  void initState() {
    super.initState();
    // Announce result when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _announceResult();
    });
  }

  Future<void> _announceResult() async {
    // Just haptic feedback on result screen, no TTS
    await HapticHelper.light();
  }

  Future<void> _repeatAnnouncement() async {
    await HapticHelper.light();
    await _announceResult();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Semantics(
          header: true,
          child: const Text(
            'Tarama Sonucu',
            style: TextStyle(
              color: AppColors.onPrimary,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        leading: Semantics(
          label: 'Geri',
          button: true,
          child: IconButton(
            icon: const Icon(Icons.arrow_back, size: 28),
            color: AppColors.onPrimary,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ),
      body: SafeArea(
        child: widget.showExpiryOnly
            ? _buildExpiryOnlyResult()
            : _buildProductResult(),
      ),
    );
  }

  Widget _buildProductResult() {
    return Consumer<BarcodeScannerProvider>(
      builder: (context, provider, child) {
        if (provider.lastScanResult == null) {
          return const Center(
            child: Text('Sonuç bulunamadı'),
          );
        }

        final result = provider.lastScanResult!;

        if (!result.success || result.product == null) {
          return _buildErrorView(result.errorMessage ?? 'Bilinmeyen hata');
        }

        final product = result.product!;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ProductInfoCard(product: product),
              const SizedBox(height: 24),
              _buildRepeatButton(),
              const SizedBox(height: 16),
              _buildNewScanButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildExpiryOnlyResult() {
    return Consumer<OcrScannerProvider>(
      builder: (context, provider, child) {
        if (provider.detectedExpiryDate == null) {
          return _buildErrorView(
            provider.error ?? 'Son kullanma tarihi bulunamadı',
          );
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExpiryStatusCard(expiryDate: provider.detectedExpiryDate!),
              const SizedBox(height: 24),
              _buildRepeatButton(),
              const SizedBox(height: 16),
              _buildNewScanButton(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorView(String errorMessage) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Semantics(
              label: 'Hata: $errorMessage',
              child: const Icon(
                Icons.error_outline,
                size: 80,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              errorMessage,
              style: AppTextStyles.heading2.copyWith(
                color: AppColors.error,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildNewScanButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildRepeatButton() {
    return Semantics(
      label: 'Bilgileri tekrar dinle',
      button: true,
      child: ElevatedButton.icon(
        onPressed: _repeatAnnouncement,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: AppColors.onPrimary,
          minimumSize: const Size(double.infinity, 80),
        ),
        icon: const Icon(Icons.volume_up, size: 32),
        label: const Text(
          'TEKRAR DİNLE',
          style: AppTextStyles.buttonText,
        ),
      ),
    );
  }

  Widget _buildNewScanButton() {
    return Semantics(
      label: 'Ana sayfaya dön',
      button: true,
      child: ElevatedButton.icon(
        onPressed: () {
          HapticHelper.light();
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 80),
        ),
        icon: const Icon(Icons.home, size: 32),
        label: const Text(
          'ANA SAYFA',
          style: AppTextStyles.buttonText,
        ),
      ),
    );
  }
}
