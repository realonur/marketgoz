# MarketGöz - Geliştirici Kılavuzu

## Proje Mimarisi

MarketGöz, Clean Architecture prensipleriyle ve feature-first yaklaşımıyla tasarlanmıştır.

### Klasör Yapısı

```
lib/
├── main.dart                 # Uygulama giriş noktası
├── app/
│   └── app.dart             # MaterialApp yapılandırması
├── core/                    # Paylaşılan temel bileşenler
│   ├── constants/          # Renkler, stiller, regex pattern'ler
│   ├── models/             # Veri modelleri (Product, ExpiryDate, ScanResult)
│   ├── services/           # İş mantığı servisleri
│   └── utils/              # Yardımcı fonksiyonlar
├── features/               # Özellik bazlı modüller
│   ├── home/              # Ana sayfa
│   ├── barcode_scanner/   # Barkod tarama
│   ├── ocr_scanner/       # SKT tarama
│   └── result/            # Sonuç ekranı
└── shared/                # Paylaşılan UI bileşenleri
    └── widgets/
```

## Temel Servisler

### 1. MLKitService

Google ML Kit entegrasyonu için wrapper servisi.

**Yetenekler:**
- Barkod tarama (EAN-13, UPC-A)
- OCR metin tanıma (Latin script)
- CameraImage → InputImage dönüşümü

**Kullanım:**
```dart
final mlKit = MLKitService();
final barcodes = await mlKit.scanBarcodesFromImage(inputImage);
final text = await mlKit.recognizeText(inputImage);
```

### 2. FirebaseService

Firebase Realtime Database işlemleri.

**Yetenekler:**
- Barkod ile ürün sorgulama
- Ürün ekleme/güncelleme
- Offline persistence
- Ürün arama

**Kullanım:**
```dart
final firebase = FirebaseService();
final product = await firebase.getProduct('8690504001016');
await firebase.addProduct(newProduct);
```

**Veritabanı Şeması:**
```json
{
  "products": {
    "BARCODE": {
      "name": "Ürün Adı",
      "brand": "Marka",
      "category": "Kategori",
      "price": 25.50,
      "weight": "1000ml"
    }
  }
}
```

### 3. TTSService

Türkçe sesli geri bildirim.

**Yetenekler:**
- Ürün bilgisi duyurusu
- SKT durumu duyurusu
- Hata mesajları
- Özelleştirilebilir hız/pitch

**Kullanım:**
```dart
final tts = TTSService();
await tts.initialize();
await tts.announceProductFound('Süt', 25.50);
await tts.announceExpiryDate('Güvenli: 45 gün kaldı');
```

### 4. PermissionService

Kamera ve diğer izinler.

**Kullanım:**
```dart
final permission = PermissionService();
final granted = await permission.requestCameraPermission();
if (!granted) {
  // Kullanıcıyı ayarlara yönlendir
}
```

## State Management - Provider Pattern

Provider pattern kullanılarak state yönetimi yapılmaktadır.

### BarcodeScannerProvider

```dart
class BarcodeScannerProvider extends ChangeNotifier {
  bool _isScanning = false;
  ScanResult? _lastScanResult;
  
  Future<void> processBarcode(String barcode) async {
    // 1. Firebase'den ürün getir
    // 2. TTS ile duyuru yap
    // 3. State'i güncelle
    notifyListeners();
  }
}
```

**Kullanım:**
```dart
// Provider ekle
ChangeNotifierProvider(
  create: (_) => BarcodeScannerProvider(),
  child: BarcodeScannerScreen(),
)

// State'e eriş
final provider = context.read<BarcodeScannerProvider>();
await provider.processBarcode(barcode);

// State dinle
Consumer<BarcodeScannerProvider>(
  builder: (context, provider, child) {
    return Text(provider.lastScanResult?.product?.name ?? '');
  },
)
```

## Tarih Tespit Algoritması

### Desteklenen Formatlar

```dart
SKT: 15.12.2025        // Gün.Ay.Yıl
SKT: 12.2025           // Ay.Yıl
TETT: 12/25            // Ay/Yıl (US)
Son Kullanma Tarihi: 15.12.2025
BB: 15.12.2025         // Best Before
```

### DateParser Kullanımı

```dart
final textBlocks = ['SKT: 15.12.2025', 'Diğer metin...'];
final expiryDate = DateParser.parseExpiryDate(textBlocks);

if (expiryDate != null) {
  print(expiryDate.formattedDate);    // "15.12.2025"
  print(expiryDate.statusMessage);     // "Güvenli: 45 gün kaldı"
  print(expiryDate.status.color);      // Green/Yellow/Orange/Red
}
```

### Durum Hesaplama

```dart
// Kalan gün sayısına göre durum belirlenir:
daysRemaining < 0    → EXPIRED (Kırmızı)
daysRemaining < 7    → DANGER (Turuncu)
daysRemaining < 30   → WARNING (Sarı)
daysRemaining >= 30  → SAFE (Yeşil)
```

## Erişilebilirlik Rehberi

### Semantics Widget Kullanımı

**Her interaktif eleman için:**
```dart
Semantics(
  label: 'Barkod Tara',                    // Ne olduğu
  hint: 'Barkod tarama ekranını açar',     // Ne yapar
  button: true,                             // Eleman tipi
  child: ElevatedButton(...),
)
```

**Başlıklar için:**
```dart
Semantics(
  header: true,
  child: Text('MarketGöz'),
)
```

**Dinamik içerik için:**
```dart
Semantics(
  liveRegion: true,  // Değişiklikleri duyur
  child: Text('Tarama tamamlandı'),
)
```

### Renk Kontrastı

WCAG AAA standardına uygun (7:1 minimum):

```dart
// ✅ İyi kontrast
Text('Metin', style: TextStyle(color: Colors.black))  // #000000
Container(color: Colors.white)                         // #FFFFFF

// ❌ Kötü kontrast
Text('Metin', style: TextStyle(color: Colors.grey))
Container(color: Colors.lightGrey)
```

### Dokunma Hedefleri

Minimum 60x60 dp, önerilen 80x80 dp:

```dart
ElevatedButton(
  style: ElevatedButton.styleFrom(
    minimumSize: Size(double.infinity, 80),  // ✅ Yeterince büyük
  ),
  child: Text('BUTON', style: TextStyle(fontSize: 28)),
)
```

## Kamera Entegrasyonu

### Temel Akış

1. **İzin kontrolü**
```dart
final hasPermission = await PermissionService().requestCameraPermission();
```

2. **Kamera başlatma**
```dart
final cameras = await availableCameras();
_controller = CameraController(
  cameras.first,
  ResolutionPreset.high,
  enableAudio: false,
);
await _controller.initialize();
```

3. **Stream işleme (Barkod için)**
```dart
_controller.startImageStream((CameraImage image) async {
  if (_isDetecting) return;
  _isDetecting = true;
  
  final inputImage = _convertCameraImage(image);
  final barcodes = await mlKit.scanBarcodes(inputImage);
  
  if (barcodes.isNotEmpty) {
    await _controller.stopImageStream();
    // Sonucu işle
  }
  
  _isDetecting = false;
});
```

4. **Tek çekim (OCR için)**
```dart
final image = await _controller.takePicture();
final inputImage = InputImage.fromFilePath(image.path);
final text = await mlKit.recognizeText(inputImage);
```

## Test Stratejileri

### Unit Tests

```dart
// test/core/utils/date_parser_test.dart
test('SKT formatını doğru parse eder', () {
  final textBlocks = ['SKT: 15.12.2025'];
  final result = DateParser.parseExpiryDate(textBlocks);
  
  expect(result, isNotNull);
  expect(result!.date!.year, 2025);
  expect(result.date!.month, 12);
  expect(result.date!.day, 15);
});
```

### Widget Tests

```dart
testWidgets('Barkod tara butonu dokunulabilir', (tester) async {
  await tester.pumpWidget(MaterialApp(home: HomeScreen()));
  
  final button = find.text('BARKOD TARA');
  expect(button, findsOneWidget);
  
  await tester.tap(button);
  await tester.pumpAndSettle();
  
  // Navigator push kontrolü
});
```

### Integration Tests

```dart
// integration_test/app_test.dart
testWidgets('Tam tarama akışı', (tester) async {
  app.main();
  await tester.pumpAndSettle();
  
  // Home → Scanner → Result akışını test et
});
```

## Performans Optimizasyonu

### Firebase Caching

```dart
// Offline persistence aktif et
await FirebaseDatabase.instance.setPersistenceEnabled(true);
await FirebaseDatabase.instance.setPersistenceCacheSizeBytes(10000000);
```

### ML Kit Optimizasyonu

```dart
// Her frame yerine her 3. frame'i işle
int _frameCount = 0;
_controller.startImageStream((image) {
  if (++_frameCount % 3 != 0) return;
  // İşle
});
```

### Memory Management

```dart
@override
void dispose() {
  _controller?.dispose();
  _mlKitService.dispose();
  _ttsService.dispose();
  super.dispose();
}
```

## Debugging İpuçları

### Firebase Bağlantı Kontrolü

```dart
print('Firebase initialized: ${Firebase.apps.isNotEmpty}');
```

### ML Kit Hata Ayıklama

```dart
try {
  final text = await mlKit.recognizeText(inputImage);
  print('Detected text blocks: ${text.blocks.length}');
  for (final block in text.blocks) {
    print('Text: ${block.text}');
  }
} catch (e) {
  print('ML Kit error: $e');
}
```

### TTS Test

```dart
// Test mod için hızlı konuşma
await tts.setSpeechRate(2.0);  // 2x hız
```

## Deployment Checklist

### Pre-Release

- [ ] Firebase production security rules
- [ ] Remove debug print statements
- [ ] Update version in pubspec.yaml
- [ ] Test on multiple devices
- [ ] Accessibility audit
- [ ] Performance profiling

### Android

```bash
# Release APK
flutter build apk --release

# App Bundle (Play Store için)
flutter build appbundle --release

# Konum: build/app/outputs/
```

### iOS

```bash
# Archive
flutter build ios --release

# Xcode ile:
# Product → Archive → Distribute
```

## Yaygın Hatalar ve Çözümler

### "Camera permission denied"
**Neden**: İzinler doğru yapılandırılmamış.
**Çözüm**: AndroidManifest.xml ve Info.plist kontrol edin.

### "Firebase not initialized"
**Neden**: Firebase yapılandırma dosyaları eksik.
**Çözüm**: google-services.json ve GoogleService-Info.plist ekleyin.

### "Text recognition failed"
**Neden**: Görüntü kalitesi düşük.
**Çözüm**: Auto-focus aktif olduğundan, ışıklandırmanın yeterli olduğundan emin olun.

### "Product not found"
**Neden**: Barkod veritabanında yok.
**Çözüm**: Firebase Console'dan ürün ekleyin.

## Katkıda Bulunma

1. Feature branch oluşturun
2. Değişikliklerinizi commit edin
3. Test yazın
4. Pull request gönderin

## Kaynaklar

- [Flutter Docs](https://docs.flutter.dev/)
- [Firebase Docs](https://firebase.google.com/docs)
- [ML Kit Docs](https://developers.google.com/ml-kit)
- [Accessibility Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)
