import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:provider/provider.dart';

import '../../app/app.dart';
import '../../core/expiry/expiry_guidance_engine.dart';
import '../../core/services/tts_service.dart';
import 'guided_scan_controller.dart';

const _months = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', 'Temmuz', 'Ağustos',
  'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

String phaseLabel(GuidancePhase p) {
  switch (p) {
    case GuidancePhase.waitingForItem:
      return 'Ürün bekleniyor';
    case GuidancePhase.searching:
      return 'Tarih aranıyor';
    case GuidancePhase.homingIn:
      return 'Tarihe yaklaşılıyor';
    case GuidancePhase.confirming:
      return 'Tarih doğrulanıyor';
    case GuidancePhase.found:
      return 'Tarih bulundu';
    case GuidancePhase.tooDark:
      return 'Ortam karanlık';
  }
}

String statusLabel(ExpiryStatus s) {
  switch (s) {
    case ExpiryStatus.expired:
      return 'SÜRESİ GEÇMİŞ';
    case ExpiryStatus.expiresToday:
      return 'BUGÜN SON GÜN';
    case ExpiryStatus.soon:
      return 'YAKINDA BİTECEK';
    case ExpiryStatus.ok:
      return 'GÜVENLİ';
  }
}

Color statusColor(ExpiryStatus s) {
  switch (s) {
    case ExpiryStatus.expired:
      return const Color(0xFFD32F2F);
    case ExpiryStatus.expiresToday:
    case ExpiryStatus.soon:
      return const Color(0xFFFF9800);
    case ExpiryStatus.ok:
      return const Color(0xFF00C853);
  }
}

String formatResultDate(ExpiryResult r) {
  final m = _months[r.date.month - 1];
  return r.precision.name == 'monthYear'
      ? '$m ${r.date.year} sonu'
      : '${r.date.day} $m ${r.date.year}';
}

String daysText(ExpiryResult r) {
  final d = r.daysRemaining;
  if (d < 0) return '${-d} gün önce geçmiş';
  if (d == 0) return 'Bugün son gün';
  if (d == 1) return 'Yarın son gün';
  return '$d gün kaldı';
}

class GuidedScanScreen extends StatelessWidget {
  const GuidedScanScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GuidedScanController>(
      create: (ctx) =>
          GuidedScanController(tts: ctx.read<TTSService>())..start(),
      child: const _GuidedScanView(),
    );
  }
}

class _GuidedScanView extends StatelessWidget {
  const _GuidedScanView();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GuidedScanController>();
    final screenReader = MediaQuery.of(context).accessibleNavigation;
    c.screenReaderActive = screenReader;
    c.onAnnounce = (text) =>
        SemanticsService.announce(text, Directionality.of(context));

    return Scaffold(
      backgroundColor: MarketGozApp.hcBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background layer = the "one big target". Sits behind the controls
          // so the torch button and result buttons stay separate nodes.
          ScanGestureArea(
            onRestart: c.restart,
            child: _Preview(controller: c),
          ),
          SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Overlay(controller: c, screenReader: screenReader),
                const Spacer(),
                if (c.status == ScanStatus.found && c.result != null)
                  Semantics(
                    sortKey: const OrdinalSortKey(1),
                    child: _ResultPanel(controller: c),
                  ),
                if (c.status == ScanStatus.permissionDenied ||
                    c.status == ScanStatus.error ||
                    c.status == ScanStatus.noCamera)
                  _Problem(controller: c),
                Semantics(
                  sortKey: const OrdinalSortKey(2),
                  child: _TorchButton(controller: c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen restart target. Sighted users double-tap; a screen reader
/// consumes the double tap, so the same action is exposed as a semantics tap
/// on a button that VoiceOver/TalkBack can activate.
class ScanGestureArea extends StatelessWidget {
  const ScanGestureArea({
    super.key,
    required this.onRestart,
    required this.child,
  });

  final VoidCallback onRestart;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Semantics(
        button: true,
        label: 'Taramayı yeniden başlat',
        hint: 'Yeni bir tarama başlatmak için çift dokunun',
        sortKey: const OrdinalSortKey(3),
        onTap: onRestart,
        excludeSemantics: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onDoubleTap: onRestart,
          child: child,
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.controller});
  final GuidedScanController controller;

  @override
  Widget build(BuildContext context) {
    final cam = controller.camera;
    if (cam == null || !controller.cameraReady) {
      return const ColoredBox(color: Colors.black);
    }
    return ExcludeSemantics(
      child: ClipRect(
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.cover,
            child: SizedBox(
              width: 1000,
              height: 1000 / cam.value.aspectRatio,
              child: CameraPreview(cam),
            ),
          ),
        ),
      ),
    );
  }
}

class _Overlay extends StatelessWidget {
  const _Overlay({required this.controller, required this.screenReader});
  final GuidedScanController controller;
  final bool screenReader;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final phase = c.status == ScanStatus.backgrounded
        ? 'Duraklatıldı'
        : phaseLabel(c.phase);
    final text = StringBuffer(phase);
    if (c.lastPrompt.isNotEmpty) text.write('\n${c.lastPrompt}');
    if (kDebugMode && c.debugLine != null) text.write('\n${c.debugLine}');

    // Coaching prompts are spoken by TTS, so the live region only carries the
    // phase name (changes rarely); the result itself goes through
    // SemanticsService.announce when a screen reader is on.
    return Semantics(
      liveRegion: true,
      sortKey: const OrdinalSortKey(0),
      label: phase,
      excludeSemantics: true,
      child: GestureDetector(
        onLongPress: kDebugMode ? c.exportRecording : null,
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.75),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MarketGozApp.hcText, width: 2),
          ),
          child: Text(
            text.toString(),
            style: const TextStyle(color: MarketGozApp.hcText, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class _TorchButton extends StatelessWidget {
  const _TorchButton({required this.controller});
  final GuidedScanController controller;

  @override
  Widget build(BuildContext context) {
    final on = controller.torchOn;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Semantics(
        button: true,
        label: on ? 'Feneri kapat' : 'Feneri aç',
        excludeSemantics: true,
        child: SizedBox(
          height: 96,
          child: ElevatedButton.icon(
            onPressed: controller.toggleTorch,
            icon: Icon(on ? Icons.flashlight_off : Icons.flashlight_on,
                size: 40),
            label: Text(on ? 'FENERİ KAPAT' : 'FENERİ AÇ'),
          ),
        ),
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.controller});
  final GuidedScanController controller;

  @override
  Widget build(BuildContext context) {
    final r = controller.result!;
    final color = statusColor(r.status);
    final name = controller.productName;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 6),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            container: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(statusLabel(r.status),
                    style: TextStyle(
                        color: color,
                        fontSize: 26,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(formatResultDate(r),
                    style: const TextStyle(
                        color: MarketGozApp.hcText,
                        fontSize: 32,
                        fontWeight: FontWeight.bold)),
                Text(daysText(r),
                    style: const TextStyle(
                        color: MarketGozApp.hcText, fontSize: 22)),
                if (name != null) ...[
                  const SizedBox(height: 8),
                  Text('Ürün: $name',
                      style: const TextStyle(
                          color: MarketGozApp.hcText, fontSize: 20)),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 72,
                  child: ElevatedButton(
                    onPressed: controller.repeatResult,
                    child: const Text('Tekrar oku',
                        style: TextStyle(fontSize: 20)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 72,
                  child: ElevatedButton(
                    onPressed: controller.restart,
                    child: const Text('Yeni ürün',
                        style: TextStyle(fontSize: 20)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Problem extends StatelessWidget {
  const _Problem({required this.controller});
  final GuidedScanController controller;

  @override
  Widget build(BuildContext context) {
    final msg = switch (controller.status) {
      ScanStatus.permissionDenied =>
        'Kamera izni verilmedi. Ayarlardan kamera iznini açın.',
      ScanStatus.noCamera => 'Bu cihazda kamera bulunamadı.',
      _ => 'Kamera başlatılamadı.',
    };
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MarketGozApp.hcText, width: 3),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(msg,
                style: const TextStyle(
                    color: MarketGozApp.hcText, fontSize: 20),
                textAlign: TextAlign.center),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 72,
            child: ElevatedButton(
              onPressed: controller.start,
              child: const Text('Tekrar dene'),
            ),
          ),
        ],
      ),
    );
  }
}
