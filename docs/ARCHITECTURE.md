# MarketGöz - System Architecture

## Complete Tech Stack Visualization

```
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                         │
│   📱  M A R K E T G Ö Z  -  AI Shopping Assistant for the Visually Impaired            │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘

                                    ┌─────────────────┐
                                    │   📷 CAMERA     │
                                    │   Live Feed     │
                                    │   (30 FPS)      │
                                    └────────┬────────┘
                                             │
                                             ▼
                    ┌────────────────────────────────────────────────┐
                    │              🎯 FRAME DISPATCHER               │
                    │         UnifiedScannerScreen.dart              │
                    │                                                │
                    │  • Receives raw CameraImage (YUV420)          │
                    │  • Routes to parallel processing pipelines    │
                    │  • Manages detection state & UI overlays      │
                    └───────┬───────────────┬───────────────┬───────┘
                            │               │               │
            ┌───────────────┘               │               └───────────────┐
            │                               │                               │
            ▼                               ▼                               ▼
┌───────────────────────┐     ┌───────────────────────┐     ┌───────────────────────┐
│   📊 BARCODE SCAN     │     │   📅 DATE DETECTION   │     │   🧠 SMART VISION     │
│                       │     │                       │     │                       │
│  ML Kit Barcode API   │     │  ML Kit Text + Regex  │     │  ProductRecognition   │
│                       │     │                       │     │      Service          │
│  • EAN-13/8, UPC-A/E  │     │  • SKT/Son Kullanma   │     │                       │
│  • QR Code, DataMatrix│     │  • DD.MM.YYYY         │     │  ┌─────────────────┐  │
│  • ITF, Code128/39    │     │  • MM/YYYY patterns   │     │  │ Object Detector │  │
│                       │     │  • Turkish months     │     │  │   (ML Kit)      │  │
└───────────┬───────────┘     └───────────┬───────────┘     │  └────────┬────────┘  │
            │                             │                 │           │           │
            │                             │                 │           ▼           │
            │                             │                 │  ┌─────────────────┐  │
            ▼                             │                 │  │ Image Labeler   │  │
┌───────────────────────┐                 │                 │  │ (Visual Tags)   │  │
│   🔍 PRODUCT LOOKUP   │                 │                 │  └────────┬────────┘  │
│                       │                 │                 │           │           │
│  ┌─────────────────┐  │                 │                 │           ▼           │
│  │ Firebase Cloud  │  │                 │                 │  ┌─────────────────┐  │
│  │   Firestore     │  │                 │                 │  │  Text Reader    │  │
│  │                 │  │                 │                 │  │    (OCR)        │  │
│  │ products/       │  │                 │                 │  └────────┬────────┘  │
│  │  └─{barcode}    │  │                 │                 │           │           │
│  │     ├─name      │  │                 │                 │           ▼           │
│  │     ├─type      │  │                 │                 │  ┌─────────────────┐  │
│  │     └─price     │  │                 │                 │  │ Color Extractor │  │
│  └─────────────────┘  │                 │                 │  │  (HSV Dominant) │  │
│                       │                 │                 │  └────────┬────────┘  │
│  ┌─────────────────┐  │                 │                 │           │           │
│  │ Open Food Facts │  │                 │                 │           ▼           │
│  │   API (Backup)  │  │                 │                 │  ┌─────────────────┐  │
│  └─────────────────┘  │                 │                 │  │  Aspect Ratio   │  │
│                       │                 │                 │  │   Calculator    │  │
└───────────┬───────────┘                 │                 │  └────────┬────────┘  │
            │                             │                 │           │           │
            │   ┌─────────────────────────┘                 └───────────┼───────────┘
            │   │                                                       │
            │   │                                                       ▼
            │   │                                     ┌─────────────────────────────────┐
            │   │                                     │   🧬 SIGNATURE MATCHING ENGINE  │
            │   │                                     │                                 │
            │   │                                     │  ┌───────────────────────────┐  │
            │   │                                     │  │   Weighted Fusion Score   │  │
            │   │                                     │  │                           │  │
            │   │                                     │  │  ┌─────────┐ ┌─────────┐  │  │
            │   │                                     │  │  │  TEXT   │ │SEMANTIC │  │  │
            │   │                                     │  │  │  MATCH  │ │  TAGS   │  │  │
            │   │                                     │  │  │  (70%)  │ │  (50%)  │  │  │
            │   │                                     │  │  └────┬────┘ └────┬────┘  │  │
            │   │                                     │  │       │           │       │  │
            │   │                                     │  │       ▼           ▼       │  │
            │   │                                     │  │  ┌─────────────────────┐  │  │
            │   │                                     │  │  │   PHYSICAL MATCH    │  │  │
            │   │                                     │  │  │  Color + Ratio      │  │  │
            │   │                                     │  │  │      (30%)          │  │  │
            │   │                                     │  │  └─────────────────────┘  │  │
            │   │                                     │  └───────────────────────────┘  │
            │   │                                     │                                 │
            │   │                                     │  ┌───────────────────────────┐  │
            │   │                                     │  │    ProductSignature DB    │  │
            │   │                                     │  │      (SharedPrefs)        │  │
            │   │                                     │  │                           │  │
            │   │                                     │  │  • ID, Label, Barcode     │  │
            │   │                                     │  │  • HSV Color [H,S,V]      │  │
            │   │                                     │  │  • Aspect Ratio (float)   │  │
            │   │                                     │  │  • Visual Tags {tag:conf} │  │
            │   │                                     │  │  • Text Keywords []       │  │
            │   │                                     │  │  • Required/Excluded Tags │  │
            │   │                                     │  └───────────────────────────┘  │
            │   │                                     └───────────────┬─────────────────┘
            │   │                                                     │
            ▼   ▼                                                     ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                         │
│                              🤖 GEMINI AI INTEGRATION                                   │
│                                  (Cloud Intelligence)                                   │
│                                                                                         │
│   ┌───────────────────┐   ┌───────────────────┐   ┌───────────────────┐                │
│   │  Unknown Barcode  │   │   Expiry Analysis │   │   Product Image   │                │
│   │    Recognition    │   │    with Context   │   │     Analysis      │                │
│   │                   │   │                   │   │                   │                │
│   │ • Open Food Facts │   │ • Date parsing    │   │ • Brand detection │                │
│   │ • Web scraping    │   │ • Days remaining  │   │ • Package type    │                │
│   │ • Vision analysis │   │ • Safety status   │   │ • Price estimate  │                │
│   └───────────────────┘   └───────────────────┘   └───────────────────┘                │
│                                                                                         │
│   Model Fallback Chain: gemini-3-flash → gemini-2.5-flash → gemini-2.5-lite           │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘
                                             │
                                             ▼
┌─────────────────────────────────────────────────────────────────────────────────────────┐
│                                                                                         │
│                               📢 OUTPUT LAYER                                           │
│                                                                                         │
│  ┌─────────────────────┐   ┌─────────────────────┐   ┌─────────────────────┐           │
│  │    🔊 TTS SERVICE   │   │   📳 HAPTIC LAYER   │   │   🖼️ VISUAL UI      │           │
│  │                     │   │                     │   │                     │           │
│  │  AVSpeechSynthesis  │   │  • Light Impact     │   │  • High Contrast    │           │
│  │  (Turkish/tr-TR)    │   │  • Medium Impact    │   │  • Large Touch      │           │
│  │                     │   │  • Heavy Impact     │   │  • Yellow on Black  │           │
│  │  "Pınar Süt.        │   │  • Success Pattern  │   │  • Bounding Boxes   │           │
│  │   Fiyatı 45 lira.   │   │  • Warning Pattern  │   │  • Color Previews   │           │
│  │   3 gün kaldı."     │   │                     │   │                     │           │
│  └─────────────────────┘   └─────────────────────┘   └─────────────────────┘           │
│                                                                                         │
└─────────────────────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════════════════

                            🛠️  TECHNOLOGY BREAKDOWN

═══════════════════════════════════════════════════════════════════════════════════════════

┌─────────────────────────────────────────────────────────────────────────────────────────┐
│  LAYER             │  TECHNOLOGY                  │  PURPOSE                           │
├─────────────────────────────────────────────────────────────────────────────────────────┤
│  Framework         │  Flutter 3.x + Dart          │  Cross-platform native UI          │
│  State Management  │  Provider + setState         │  Reactive UI updates               │
│  Camera            │  camera: ^0.11.x             │  Real-time YUV420 frame access     │
│  Barcode           │  google_mlkit_barcode        │  On-device barcode detection       │
│  Text (OCR)        │  google_mlkit_text           │  On-device text recognition        │
│  Objects           │  google_mlkit_object         │  Bounding box detection            │
│  Labels            │  google_mlkit_image_labeling │  Semantic tagging                  │
│  Cloud AI          │  Gemini API (REST)           │  Advanced product analysis         │
│  Database          │  Cloud Firestore             │  Product catalog sync              │
│  Local Storage     │  SharedPreferences           │  Signature persistence             │
│  Voice             │  flutter_tts                 │  Turkish speech synthesis          │
│  Sensors           │  sensors_plus                │  Shake detection                   │
│  Image Processing  │  image, flutter_image_compress│  Color extraction, resize         │
│  External APIs     │  Open Food Facts             │  Barcode product lookup            │
└─────────────────────────────────────────────────────────────────────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════════════════

                              🔄 DATA FLOW SEQUENCE

═══════════════════════════════════════════════════════════════════════════════════════════

 USER           CAMERA         ML KIT         SIGNATURE         FIREBASE        GEMINI
   │               │              │               │                │              │
   │  Point Phone  │              │               │                │              │
   │──────────────>│              │               │                │              │
   │               │  Frame       │               │                │              │
   │               │─────────────>│               │                │              │
   │               │              │               │                │              │
   │               │              │──┐  Barcode?  │                │              │
   │               │              │  │─────────────────────────────>│              │
   │               │              │<─┘            │                │              │
   │               │              │               │  Match Score?  │              │
   │               │              │──┐  Objects ─>│───────────────>│              │
   │               │              │  │            │                │              │
   │               │              │<─┘            │                │              │
   │               │              │               │   Unknown?     │              │
   │               │              │               │────────────────────────────────>│
   │               │              │               │                │              │
   │  TTS + Haptic │              │               │                │  Analysis    │
   │<──────────────────────────────────────────────────────────────────────────────│
   │               │              │               │                │              │
   │  "Coca Cola,  │              │               │                │              │
   │   3 gün kaldı"│              │               │                │              │
   │               │              │               │                │              │


═══════════════════════════════════════════════════════════════════════════════════════════

                         🎯 SMART VISION MATCHING PIPELINE

═══════════════════════════════════════════════════════════════════════════════════════════

                         ┌────────────────────────────┐
                         │     Detected Object        │
                         │                            │
                         │  • Label: "Bottle"         │
                         │  • Ratio: 2.3 (tall)       │
                         │  • HSV: [15°, 85%, 90%]    │
                         │  • Tags: {Bottle: 0.9}     │
                         │  • Text: "COCA COLA"       │
                         └─────────────┬──────────────┘
                                       │
                                       ▼
                    ╔══════════════════════════════════════╗
                    ║       FOR EACH SAVED SIGNATURE       ║
                    ╚══════════════════════════════════════╝
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                  │
                    ▼                  ▼                  ▼
            ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
            │  PRE-CHECK    │  │  PRE-CHECK    │  │  PRE-CHECK    │
            │               │  │               │  │               │
            │ Label Match?  │  │ Required Tags │  │ Excluded Tags │
            │ ───────────── │  │ ───────────── │  │ ───────────── │
            │ "Bottle" ==   │  │ All present?  │  │ None present? │
            │ "Bottle" ✓    │  │     ✓         │  │     ✓         │
            └───────┬───────┘  └───────┬───────┘  └───────┬───────┘
                    │                  │                  │
                    └──────────────────┼──────────────────┘
                                       │
                                       ▼
                         ┌─────────────────────────┐
                         │    CALCULATE SCORES     │
                         └─────────────────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                  │
                    ▼                  ▼                  ▼
            ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
            │  TEXT SCORE   │  │ SEMANTIC SCORE│  │ PHYSICAL SCORE│
            │               │  │               │  │               │
            │ Keywords:     │  │ Tag Overlap:  │  │ HSV Distance: │
            │ ["coca","cola"]│  │ Jaccard Index │  │ ΔH, ΔS, ΔV   │
            │               │  │               │  │               │
            │ Found: 2/2    │  │ 0.85          │  │ Ratio Diff:   │
            │ Score: 1.0    │  │               │  │ |2.3 - 2.4|   │
            └───────┬───────┘  └───────┬───────┘  └───────┬───────┘
                    │                  │                  │
                    └──────────────────┼──────────────────┘
                                       │
                                       ▼
                    ╔══════════════════════════════════════╗
                    ║         WEIGHTED FUSION              ║
                    ║                                      ║
                    ║  IF textScore >= 0.5:                ║
                    ║    final = text×0.7 + physical×0.3   ║
                    ║    final *= 1.2 (confidence boost)   ║
                    ║                                      ║
                    ║  ELIF semanticScore > 0.6:           ║
                    ║    final = sem×0.5 + phys×0.4 + t×0.1║
                    ║                                      ║
                    ║  ELSE:                               ║
                    ║    final = physical×0.7 + sem×0.3    ║
                    ║                                      ║
                    ╚══════════════════════════════════════╝
                                       │
                                       ▼
                         ┌─────────────────────────┐
                         │   BEST MATCH SELECTION  │
                         │                         │
                         │  Score > 0.65 → KNOWN   │
                         │  Score ≤ 0.65 → UNKNOWN │
                         └─────────────────────────┘


═══════════════════════════════════════════════════════════════════════════════════════════

                              📂 PROJECT STRUCTURE

═══════════════════════════════════════════════════════════════════════════════════════════

MarketGoz/
├── lib/
│   ├── core/
│   │   ├── models/
│   │   │   └── product_signature.dart      # Visual fingerprint model
│   │   ├── services/
│   │   │   ├── product_recognition_service.dart  # ML Kit orchestration
│   │   │   ├── product_storage_service.dart      # Signature persistence
│   │   │   ├── smart_vision_service.dart         # High-level facade
│   │   │   ├── firebase_service.dart             # Firestore sync
│   │   │   ├── gemini_service.dart               # Cloud AI integration
│   │   │   └── tts_service.dart                  # Turkish speech
│   │   ├── constants/
│   │   │   ├── app_colors.dart             # High contrast palette
│   │   │   └── app_text_styles.dart        # Accessibility fonts
│   │   └── utils/
│   │       └── haptic_helper.dart          # Vibration patterns
│   │
│   ├── features/
│   │   ├── home/
│   │   │   └── presentation/
│   │   │       └── home_screen.dart        # Main entry (black UI)
│   │   ├── unified_scanner/
│   │   │   ├── presentation/
│   │   │   │   └── unified_scanner_screen.dart  # Camera + detection
│   │   │   └── widgets/
│   │   │       └── object_box_overlay.dart      # Bounding box renderer
│   │   └── smart_vision/
│   │       └── presentation/
│   │           └── product_mapper_dialog.dart   # Teach new products
│   │
│   └── main.dart
│
├── docs/
│   ├── ARCHITECTURE.md       # ← You are here
│   └── OBJECT_DETECTION.md   # Technical implementation details
│
└── pubspec.yaml              # Dependencies


═══════════════════════════════════════════════════════════════════════════════════════════

  Built with ❤️ for the visually impaired community

  © 2024 MarketGöz - Making grocery shopping accessible

═══════════════════════════════════════════════════════════════════════════════════════════
```
