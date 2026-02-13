# MarketGoz - Object Detection Architecture

## Overview

MarketGoz uses a **multi-layered approach** to product detection and recognition, combining multiple AI/ML technologies for robust product identification.

---

## Detection Methods

### 1. ML Kit Object Detection (Primary)

**Package:** `google_mlkit_object_detection`

**How it works:**
- Runs on every camera frame (configurable FPS: 1-10)
- Provides bounding boxes for detected objects
- Generic labels: "Food", "Home good", "Fashion good", etc.
- Uses Google's pre-trained base model

**Pros:**
- Fast and lightweight
- Works offline
- Well-integrated with Flutter

**Cons:**
- Generic labels (not specific product names)
- Sometimes inaccurate bounding boxes

---

### 2. Visual Fingerprinting (Color + Shape Matching)

**Files:** 
- `lib/core/models/product_signature.dart`
- `lib/core/services/product_storage_service.dart`

**How it works:**
1. From each detected object, extract:
   - **Dominant Color** (HSV color space)
   - **Aspect Ratio** (height/width)
   - **ML Kit Label** (object category)

2. Compare against saved signatures using weighted matching:
   - Hue: 40%
   - Aspect Ratio: 30%
   - Saturation: 15%
   - Brightness: 15%

3. Special handling for achromatic colors (white/gray/black)

**Pros:**
- Custom product recognition without training
- Works with any product

**Cons:**
- Requires manual product registration
- Similar colors can confuse it

---

### 3. Visual Tags (ML Kit Image Labeling)

**Package:** `google_mlkit_image_labeling`

**How it works:**
- Runs on cropped detection regions
- Returns semantic labels: "Bottle", "Plastic", "Beverage", etc.
- 400+ class labels available

**Usage in matching:**
- Tags stored with each signature
- Can set **Required Tags** (AND) - must be present
- Can set **Excluded Tags** (NOT) - must NOT be present

**Example:**
```
Product: "Coca-Cola 1L"
Required Tags: [bottle, plastic]
Excluded Tags: [can, metal]
```

---

### 4. Text Recognition (OCR) 
 **Package:** `google_mlkit_text_recognition` 
 
 **How it works:** 
 - Runs on cropped object regions 
 - Extracts text found on the product packaging 
 - Enhances matching accuracy for products with identical distinct packaging but different text 
 
 **Usage in matching:** 
 - `textKeywords` stored in signature 
 - Detections containing these keywords get a massive confidence boost 
 
 **Example:** 
 ``` 
 Product: "Coca-Cola Zero" 
 Text Keywords: [zero, sugar, coke] 
 ``` 
 
 ---

## Product Signature Structure

```dart
class ProductSignature {
  String id;
  String? barcode;
  String productName;
  String? userGivenName;
  String label;              // ML Kit class
  String aspectRatio;        // "tall", "wide", "square"
  double aspectRatioValue;   // numeric H/W ratio
  Color dominantColor;       // RGB
  List<double> colorHSV;     // [H, S, V]
  String colorName;          // "red", "blue", etc.
  Map<String, double> visualTags;  // from Image Labeling
  List<String> requiredTags;       // AND conditions
  List<String> excludedTags;       // NOT conditions
  List<String> textKeywords;       // OCR keywords to match
}
```

---

## Matching Logic

### Step 1: Tag Filter (AND/NOT)
```
IF requiredTags is not empty:
   ALL requiredTags must be present in detected visualTags
   
IF excludedTags is not empty:
   NONE of excludedTags should be present in detected visualTags
```

### Step 2: Text Keyword Match (Boost)
```
IF textKeywords is not empty AND detectedText contains ANY keyword:
   Score = MAX(1.0, BaseScore * 1.5)
IF textKeywords is not empty AND detectedText does NOT contain ANY keyword:
   Match Fails (Score = 0)
```

### Step 3: Label Match
```
signature.label must equal detected.label (case-insensitive)
```

### Step 4: Aspect Ratio Match
```
|signature.aspectRatio - detected.aspectRatio| <= 0.15
```

### Step 5: Color Match (HSV)
```
For chromatic colors:
   Hue difference <= 20°
   Saturation difference <= 0.3
   Value difference <= 0.3

For achromatic colors (white/gray/black):
   Ignore Hue
   Saturation must be low for both
   Value difference <= 0.3
```

---

## Data Flow

```
Camera Frame
     │
     ▼
┌─────────────────┐
│  ML Kit Object  │──────────────────┐
│   Detection     │                  │
└────────┬────────┘                  │
         │                           │
         ▼                           ▼
┌─────────────────┐         ┌─────────────────┐
│  Bounding Box   │         │  Visual Tags    │
│  + Generic Label│         │  (Image Labeler)│
└────────┬────────┘         └────────┬────────┘
         │                           │
         ▼                           ▼
┌─────────────────────────────────────────────┐
│           Color Extraction (HSV)            │
└─────────────────────┬───────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────┐
│         Signature Matching Engine           │
│  (Compare against stored ProductSignatures) │
└─────────────────────┬───────────────────────┘
                      │
                      ▼
         ┌────────────┴────────────┐
         │                         │
    ┌────▼────┐               ┌────▼────┐
    │ MATCHED │               │ UNKNOWN │
    │ (Green) │               │ (Orange)│
    └─────────┘               └─────────┘
```

---

## Settings & Configuration

| Setting | Location | Description |
|---------|----------|-------------|
| Smart Vision Toggle | Settings | Enable/disable ML detection |
| FPS (1-10) | Settings | Detection frequency |
| Bounding Boxes | Settings | Show/hide detection boxes |
| High Accuracy Mode | Settings | Single frame mode (slower) |
| Data Collection Mode | Settings | Disable TTS for rapid testing |

---

## Files Overview

| File | Purpose |
|------|---------|
| `product_recognition_service.dart` | Main detection orchestration |
| `product_signature.dart` | Signature model & matching logic |
| `product_storage_service.dart` | Hive database for signatures |
| `smart_vision_service.dart` | ML Kit initialization |
| `product_mapper_dialog.dart` | Save signature dialog (with clickable tags) |
| `unified_scanner_screen.dart` | Main scanner with bounding boxes |

---

## Future Improvements

1. **Barcode + Visual Fusion** - Combine barcode data with visual signatures
2. **Cloud Sync** - Share signatures between devices
3. **Advanced OCR Filtering** - Use regex for specific text patterns (dates, weights)
