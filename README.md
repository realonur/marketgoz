# MarketGöz

AI-powered shopping assistant for visually impaired users in Turkey. Provides barcode scanning, product identification, and expiry date detection with Turkish voice feedback.

## Features

- 📱 Barcode scanning (EAN-13, UPC-A)
- 🔍 OCR text recognition for expiry dates (SKT/TETT)
- 🔊 Turkish text-to-speech announcements
- ♿ Full accessibility support (TalkBack/VoiceOver)
- 🎨 High-contrast UI with large touch targets
- 🔥 Firebase Realtime Database integration

## Requirements

- Flutter SDK 3.2.0 or higher
- Dart 3.2.0 or higher
- iOS 12.0+ / Android 21+
- Camera permission

## Getting Started

1. Install dependencies:
```bash
flutter pub get
```

2. Configure Firebase:
   - Create a Firebase project
   - Add iOS and Android apps
   - Download and add configuration files
   - Run: `flutterfire configure`

3. Run the app:
```bash
flutter run
```

## Project Structure

```
lib/
├── main.dart
├── app/
├── core/
│   ├── constants/
│   ├── services/
│   ├── utils/
│   └── models/
├── features/
│   ├── home/
│   ├── barcode_scanner/
│   ├── ocr_scanner/
│   └── result/
└── shared/
    └── widgets/
```

## Team

**MekaGöz** - İSTEFEST 2025
- Onur Sabri Yıldız
- Tuğba Asude Nacar

Mechatronics Engineering, 3rd Year
