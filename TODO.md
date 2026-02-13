# TODO: MarketGöz Development Checklist

## ✅ Completed

- [x] Flutter project structure created
- [x] All core services implemented (ML Kit, Firebase, TTS)
- [x] Platform-specific permissions configured
- [x] Barcode scanner feature implemented
- [x] OCR date recognition feature implemented
- [x] Result screen with accessibility features
- [x] Home screen and navigation
- [x] High-contrast UI with large buttons
- [x] Turkish language support
- [x] Semantic labels for screen readers

## 🔄 Next Steps

### 1. Firebase Setup (REQUIRED)
- [ ] Create Firebase project at https://console.firebase.google.com/
- [ ] Add iOS app with bundle ID: `com.mekagoz.marketgoz`
- [ ] Add Android app with package: `com.mekagoz.marketgoz`
- [ ] Download and place `GoogleService-Info.plist` in `ios/Runner/`
- [ ] Download and place `google-services.json` in `android/app/`
- [ ] Enable Realtime Database in Firebase Console
- [ ] Import sample data from `firebase_sample_data.json`
- [ ] Run: `flutterfire configure` (optional but recommended)

### 2. Install Dependencies
```bash
flutter pub get
cd ios && pod install && cd ..
```

### 3. Test on Device/Emulator
```bash
flutter run
```

### 4. Database Population
- [ ] Add more Turkish products to Firebase (target: 1000+)
- [ ] Consider integrating GS1 Turkey database
- [ ] Implement "Report Missing Product" feature
- [ ] Add product images (optional)

### 5. UI/UX Improvements
- [ ] Add loading animations
- [ ] Implement error recovery flows
- [ ] Add onboarding tutorial for first-time users
- [ ] Create app icon and splash screen
- [ ] Add haptic feedback patterns
- [ ] Implement flashlight toggle for barcode scanner

### 6. Accessibility Testing
- [ ] Test with TalkBack on Android
- [ ] Test with VoiceOver on iOS
- [ ] Verify all Semantics labels
- [ ] Test with different font sizes
- [ ] Test color contrast ratios
- [ ] Get feedback from visually impaired users

### 7. OCR Accuracy Improvements
- [ ] Test with various product packaging
- [ ] Implement image preprocessing (contrast, grayscale)
- [ ] Add multi-capture mode (take 3 photos, use best)
- [ ] Allow manual date input as fallback
- [ ] Fine-tune regex patterns for edge cases

### 8. Performance Optimization
- [ ] Implement Firebase caching
- [ ] Reduce ML Kit processing time
- [ ] Optimize camera resolution
- [ ] Test battery consumption
- [ ] Profile app performance

### 9. Additional Features
- [ ] Shopping history
- [ ] Favorites/bookmarks
- [ ] Share product info
- [ ] Multi-language support (English)
- [ ] Offline mode improvements
- [ ] Settings screen (TTS speed, voice selection)

### 10. Testing
- [ ] Unit tests for core services
- [ ] Widget tests for UI components
- [ ] Integration tests for scanning flows
- [ ] Accessibility audit
- [ ] Performance testing

### 11. Deployment
- [ ] Create app icon
- [ ] Create splash screen
- [ ] Configure signing certificates
- [ ] Build release APK/IPA
- [ ] Submit to Google Play Store
- [ ] Submit to Apple App Store
- [ ] Prepare store listings (screenshots, descriptions)

## 🐛 Known Issues

- Camera image conversion needs rotation handling for different device orientations
- Firebase Realtime Database security rules are in test mode (not production-ready)
- TTS voice quality varies between iOS and Android
- OCR may struggle with curved or reflective surfaces

## 📝 Notes

- Target completion date: According to project plan (4 months)
- Team: Onur Sabri Yıldız, Tuğba Asude Nacar
- Competition: İSTEFEST 2025 - Engelsiz Yaşam Teknolojileri
