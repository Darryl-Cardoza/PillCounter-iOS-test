# Photo ID OCR Scan — Implementation Reference

**Feature:** "Scan Photo ID" step of Quick Access (face-auth) user enrollment.
**Purpose of this document:** a language- and framework-agnostic specification, plus the full Android/Kotlin reference implementation, so the same feature can be rebuilt in another project or another language.

Companion document: [ID_SCAN_OCR_FLOW.md](ID_SCAN_OCR_FLOW.md) — end-to-end runtime flow, state machines, sequence diagrams.

---

## 1. What the feature does

The operator holds a photo ID (US driver's license or a staff/employee badge) in front of the device's back camera. The app extracts **the person's first and last name only** and pre-fills two editable text fields. The operator confirms or corrects, then continues into face capture. On completion, the name is persisted as the display identity of a Quick Access user record.

### 1.1 Explicit scope boundaries

| In scope | Out of scope (deliberately) |
|---|---|
| First name | Date of birth |
| Last name | License / ID number |
| Tap-to-fill suggestion words | Address |
| Manual-entry fallback | Expiry / issue date |
| | Sex, height, weight, eye/hair colour |
| | Any image persistence of the ID |

**Why the narrow scope matters:** the PDF417 barcode on the back of a US driver's license (AAMVA payload) *does* carry DOB, address and license number. The implementation reads only the two name fields and discards the rest with the frame. No ID frame is ever written to disk. If you widen the scope when porting, you are widening the privacy/compliance surface — treat it as a deliberate product decision, not a free upgrade.

### 1.2 Product-level design rule

The extracted name **pre-fills editable fields**; it is never committed silently. Heuristics therefore aim at "usually right", not "always right". Every recogniser path is backed by:

1. Editable text fields (the user can retype anything).
2. Tap-to-fill suggestion chips (the user can repair a wrong *pairing* without typing).
3. An "Enter Manually" button (the user can bypass scanning entirely).

Any port must keep all three escape hatches, or OCR failures become dead ends.

---

## 2. Architecture

```
┌──────────────────────────────────────────────────────────────────────┐
│ PRESENTATION                                                         │
│                                                                      │
│  FaceRegistrationScreen  ── flow host, owns firstName/lastName state │
│        │                                                             │
│        └── ScanPhotoIdStep ── camera preview + guide + status +      │
│                               result bottom sheet (fields + chips)   │
└───────────────┬──────────────────────────────────────────────────────┘
                │ frames (ImageProxy)          │ callbacks (name, suggestions)
┌───────────────▼──────────────────────────────▼───────────────────────┐
│ CAPTURE / RECOGNITION                                                │
│                                                                      │
│  CameraHelper  ── CameraX bind, Preview + ImageAnalysis + Capture,   │
│                   conflated frame channel, autofocus, pause/rebind   │
│                                                                      │
│  IdCardAnalyzer ── per-frame orchestration:                          │
│        1. PDF417 barcode decode  (authoritative, fires immediately)  │
│        2. OCR text recognition   (heuristic, two-frame confirmation) │
│        + throttle, single-flight gate, watchdog, bitmap lifecycle    │
└───────────────┬──────────────────────────────────────────────────────┘
                │ List<IdTextLine>
┌───────────────▼──────────────────────────────────────────────────────┐
│ PURE LOGIC (no framework deps — port this first, test this first)    │
│                                                                      │
│  IdNameParser ── 4-tier name extraction + suggestion ranking         │
└───────────────┬──────────────────────────────────────────────────────┘
                │ IdCardName(firstName, lastName)
┌───────────────▼──────────────────────────────────────────────────────┐
│ STATE / PERSISTENCE                                                  │
│                                                                      │
│  FaceAuthViewModel ── holds pendingFirstName/pendingLastName across  │
│                       the face-capture steps, then persists          │
│  FaceProfileRepository ── insert profile + embeddings atomically     │
│  FaceProfileDao / FaceProfileEntity ── Room table `face_profiles`    │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.1 File map (this repo)

| Layer | File |
|---|---|
| Flow host | [FaceRegistrationScreen.kt](../app/src/main/java/com/rite/pillcounting/feature/faceAuth/presentation/FaceRegistrationScreen.kt) |
| Scan UI | [ScanPhotoIdStep.kt](../app/src/main/java/com/rite/pillcounting/feature/faceAuth/presentation/ScanPhotoIdStep.kt) |
| Frame orchestration | [IdCardAnalyzer.kt](../app/src/main/java/com/rite/pillcounting/core/scanning/analyzer/IdCardAnalyzer.kt) |
| Name parsing (pure) | [IdNameParser.kt](../app/src/main/java/com/rite/pillcounting/core/scanning/logic/IdNameParser.kt) |
| Camera wrapper | [CameraHelper.kt](../app/src/main/java/com/rite/pillcounting/core/scanning/logic/CameraHelper.kt) |
| ViewModel | [FaceAuthViewModel.kt](../app/src/main/java/com/rite/pillcounting/feature/faceAuth/presentation/viewmodel/FaceAuthViewModel.kt) |
| Repository | [FaceProfileRepository.kt](../app/src/main/java/com/rite/pillcounting/core/faceAuth/data/FaceProfileRepository.kt) |
| DAO | [FaceProfileDao.kt](../app/src/main/java/com/rite/pillcounting/core/room/dao/FaceProfileDao.kt) |
| Entity | [FaceProfileEntity.kt](../app/src/main/java/com/rite/pillcounting/core/room/models/FaceProfileEntity.kt) |
| Parser tests | [IdNameParserTest.kt](../app/src/test/java/com/rite/pillcounting/core/scanning/logic/IdNameParserTest.kt) |

### 2.2 Dependency inventory (Android)

`libs.versions.toml`:

```toml
[versions]
mlkit-barcode = "17.3.0"
mlkit-text    = "16.0.1"

[libraries]
mlkit-barcode-scanning  = { group = "com.google.mlkit", name = "barcode-scanning",  version.ref = "mlkit-barcode" }
mlkit-text-recognition  = { group = "com.google.mlkit", name = "text-recognition",  version.ref = "mlkit-text" }
```

`app/build.gradle.kts`:

```kotlin
implementation(libs.mlkit.barcode.scanning)
implementation(libs.mlkit.text.recognition)
```

`proguard-rules.pro` (release builds strip ML Kit reflection targets without these):

```proguard
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_vision_barcode.** { *; }
-dontwarn com.google.mlkit.**
```

`AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

### 2.3 Equivalent libraries when porting

| Concern | Android (this repo) | iOS | Flutter | React Native | Web | Server / Python |
|---|---|---|---|---|---|---|
| Camera stream | CameraX `ImageAnalysis` | `AVCaptureVideoDataOutput` | `camera` package `startImageStream` | `react-native-vision-camera` frame processor | `getUserMedia` + `<video>` + canvas | n/a (upload frames) |
| OCR | ML Kit `TextRecognition` | Vision `VNRecognizeTextRequest` | `google_mlkit_text_recognition` | `vision-camera-ocr` / ML Kit bridge | Tesseract.js | Tesseract / PaddleOCR / Cloud Vision |
| PDF417 / AAMVA | ML Kit `BarcodeScanning` (`FORMAT_PDF417`) | Vision `VNDetectBarcodesRequest` (`.pdf417`) | `google_mlkit_barcode_scanning` | `vision-camera-code-scanner` | ZXing-js | `zxing-cpp` / `pdf417decoder` |
| AAMVA field parsing | ML Kit `barcode.driverLicense` | Manual AAMVA parse (see §4.4) | Plugin exposes driverLicense | Manual AAMVA parse | Manual AAMVA parse | Manual AAMVA parse |

**Important portability note:** ML Kit gives you *structured* driver-license fields for free. Most other stacks hand you the raw AAMVA string and you must parse it yourself. See §4.4 for the AAMVA element codes needed to replicate `firstName` / `lastName`.

---

## 3. Data contracts

Port these three types first. Everything else is behaviour around them.

```kotlin
/** A single OCR line with its glyph height, used to rank prominence on the card. */
data class IdTextLine(val text: String, val heightPx: Int = 0)

/** Name extracted from a photo ID (driver's license or staff badge). */
data class IdCardName(val firstName: String, val lastName: String)

/**
 * Result of scanning a photo ID: the parser's best first/last name guess (null
 * when no confident pair was found) plus every name-like word seen on the
 * card, for the user to tap-to-fill when the guess is wrong or missing.
 */
data class IdScanResult(
    val name: IdCardName?,
    val suggestions: List<String>,
)
```

Language-neutral shapes:

```ts
type IdTextLine  = { text: string; heightPx: number };   // heightPx defaults to 0
type IdCardName  = { firstName: string; lastName: string };
type IdScanResult = { name: IdCardName | null; suggestions: string[] };
```

**`heightPx` is load-bearing.** It is the pixel height of the OCR line's bounding box and it is the entire basis of the badge-case heuristic (a person's name is usually the largest text on a badge). If your OCR engine reports bounding boxes rather than heights, compute `boundingBox.height`. If it reports nothing, the prominence tier degrades to "first matching line wins" — acceptable, but noticeably worse on badges.

**`IdScanResult` has three meaningful states**, and the UI must handle all three:

| `name` | `suggestions` | Meaning | UI behaviour |
|---|---|---|---|
| non-null | empty | PDF417/AAMVA hit — authoritative | Fill both fields, no chips |
| non-null | non-empty | OCR parse succeeded | Fill both fields, show chips for correction |
| null | non-empty (≥2) | OCR saw name-like words but could not pair them | Leave fields empty, show chips |

---

## 4. Recognition engine — `IdCardAnalyzer`

### 4.1 Responsibilities

1. Throttle how often frames are analysed (OCR is expensive).
2. Enforce single-flight: never two frames in ML Kit at once.
3. Snapshot the camera frame **synchronously** so the caller can release the camera buffer immediately.
4. Try PDF417 first, fall back to OCR.
5. Require OCR agreement across two consecutive frames before firing.
6. Recover from a dropped ML Kit callback (watchdog).
7. Free the bitmap and the gate on every exit path, including exceptions.
8. Self-pause on a hit; expose `resume()` / `close()`.

### 4.2 Tuning constants

```kotlin
/** OCR is heavier than barcode decode — throttle harder than a plain barcode analyzer. */
private const val MIN_INTERVAL_MS = 400L

/** Covers the barcode + OCR chain before the gate is force-released. */
private const val MLKIT_TIMEOUT_MS = 2500L

/** Suggestion-only fires need at least a plausible first+last pair to pick from. */
private const val MIN_SUGGESTIONS_TO_FIRE = 2
```

| Constant | Value | Rationale | Porting guidance |
|---|---|---|---|
| `MIN_INTERVAL_MS` | 400 ms | ~2.5 analysed frames/sec. Full-frame OCR on a mid-range phone costs 150–400 ms. | Raise on slower hardware; lower only if OCR latency is measured well under it. |
| `MLKIT_TIMEOUT_MS` | 2500 ms | Upper bound for barcode-decode + OCR chained. If the SDK drops a callback, the single-flight gate would latch forever without this. | Set to ≥3× measured p99 of the full chain. |
| `MIN_SUGGESTIONS_TO_FIRE` | 2 | A suggestion-only result is useless unless the user can pick both a first and a last name. | Keep at 2. |
| Two-frame OCR confirmation | — | A single-frame misread never reaches the user. | Keep. This is the main accuracy lever. |

### 4.3 Full source

```kotlin
package com.rite.pillcounting.core.scanning.analyzer

import android.content.Context
import android.graphics.Bitmap
import androidx.camera.core.ImageProxy
import com.google.mlkit.vision.barcode.BarcodeScannerOptions
import com.google.mlkit.vision.barcode.BarcodeScanning
import com.google.mlkit.vision.barcode.common.Barcode
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import com.rite.pillcounting.core.scanning.logic.IdCardName
import com.rite.pillcounting.core.scanning.logic.IdNameParser
import com.rite.pillcounting.core.scanning.logic.IdTextLine
import com.rite.pillcounting.core.utils.common.SoundUtils
import com.rite.pillcounting.core.utils.logger.AppLogger
import kotlinx.coroutines.*
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

data class IdScanResult(
    val name: IdCardName?,
    val suggestions: List<String>,
)

class IdCardAnalyzer(private val appContext: Context) {
    private val logger = AppLogger("IdCardAnalyzer")

    private val barcodeDelegate = lazy {
        BarcodeScanning.getClient(
            BarcodeScannerOptions.Builder()
                .setBarcodeFormats(Barcode.FORMAT_PDF417)
                .build()
        )
    }
    private val barcodeScanner by barcodeDelegate

    private val textDelegate = lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }
    private val textRecognizer by textDelegate

    private val isPaused = AtomicBoolean(false)
    private val isProcessing = AtomicBoolean(false)
    private val released = AtomicBoolean(false)

    /** Token so the watchdog and completion paths only touch their own frame's gate. */
    private val frameToken = AtomicLong(0L)
    private var lastAttemptAtMs = 0L
    private var watchdogJob: Job? = null

    /** Last OCR-parsed candidate; must repeat on the next frame to fire. */
    private var lastOcrCandidate: IdCardName? = null

    /** Last OCR suggestion words; must repeat to fire when no pair was parsed. */
    private var lastSuggestions: List<String> = emptyList()

    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    companion object {
        private const val MIN_INTERVAL_MS = 400L
        private const val MLKIT_TIMEOUT_MS = 2500L
        private const val MIN_SUGGESTIONS_TO_FIRE = 2
    }

    fun pause() {
        isPaused.set(true)
    }

    fun resume() {
        isPaused.set(false)
        isProcessing.set(false)
        watchdogJob?.cancel()
        watchdogJob = null
        lastAttemptAtMs = 0L
        lastOcrCandidate = null
        lastSuggestions = emptyList()
    }

    /** Release ML Kit clients + coroutines. Call from DisposableEffect.onDispose. Idempotent. */
    fun close() {
        if (!released.compareAndSet(false, true)) return
        isPaused.set(true)
        watchdogJob?.cancel()
        watchdogJob = null
        ioScope.cancel()
        if (barcodeDelegate.isInitialized()) barcodeScanner.close()
        if (textDelegate.isInitialized()) textRecognizer.close()
    }

    fun analyze(
        imageProxy: ImageProxy,
        onDetected: (IdScanResult) -> Unit,
    ) {
        if (released.get() || isPaused.get()) return
        val now = System.currentTimeMillis()
        if (now - lastAttemptAtMs < MIN_INTERVAL_MS) return
        if (!isProcessing.compareAndSet(false, true)) return
        lastAttemptAtMs = now

        // Synchronous snapshot — the caller closes the proxy right after we return.
        val rotation = imageProxy.imageInfo.rotationDegrees
        val bitmap: Bitmap? = try {
            imageProxy.toBitmap()
        } catch (e: Exception) {
            logger.w("Could not snapshot frame for ID analysis: ${e.message}")
            null
        }
        if (bitmap == null) {
            isProcessing.set(false)
            return
        }

        val token = frameToken.incrementAndGet()
        watchdogJob?.cancel()
        watchdogJob = ioScope.launch {
            delay(MLKIT_TIMEOUT_MS)
            if (frameToken.get() == token && isProcessing.get()) {
                logger.w("MLKit timeout for frame token=$token — releasing gate")
                isProcessing.set(false)
            }
        }

        // Any synchronous throw from ML Kit (e.g. client already released under
        // race) must free the gate + bitmap, or scanning dies until the step
        // is rebuilt.
        try {
            processFrame(input = InputImage.fromBitmap(bitmap, rotation), bitmap, token, onDetected)
        } catch (t: Throwable) {
            logger.e("ID_SCAN dispatch failed token=$token", t)
            finishFrame(bitmap, token)
        }
    }

    private fun processFrame(
        input: InputImage,
        bitmap: Bitmap,
        token: Long,
        onDetected: (IdScanResult) -> Unit,
    ) {
        barcodeScanner.process(input)
            .addOnSuccessListener { barcodes ->
                val license = barcodes
                    .firstOrNull { it.valueType == Barcode.TYPE_DRIVER_LICENSE }
                    ?.driverLicense
                val first = license?.firstName?.trim().orEmpty()
                val last = license?.lastName?.trim().orEmpty()
                if (first.isNotEmpty() && last.isNotEmpty()) {
                    logger.i("ID_SCAN driver license PDF417 hit")
                    val name = IdCardName(IdNameParser.displayCase(first), IdNameParser.displayCase(last))
                    fire(IdScanResult(name, suggestions = emptyList()), onDetected)
                    finishFrame(bitmap, token)
                } else {
                    runOcr(input, bitmap, token, onDetected)
                }
            }
            .addOnFailureListener { ex ->
                logger.e("ID_SCAN barcode failure token=$token", ex)
                runOcr(input, bitmap, token, onDetected)
            }
    }

    private fun runOcr(
        input: InputImage,
        bitmap: Bitmap,
        token: Long,
        onDetected: (IdScanResult) -> Unit,
    ) {
        if (released.get()) {
            finishFrame(bitmap, token)
            return
        }
        // Same rationale as the try in analyze(): a synchronous throw here
        // (barcode listener context) must not leave the gate locked.
        val task = try {
            textRecognizer.process(input)
        } catch (t: Throwable) {
            logger.e("ID_SCAN OCR dispatch failed token=$token", t)
            finishFrame(bitmap, token)
            return
        }
        task
            .addOnSuccessListener { text ->
                val lines = text.textBlocks.flatMap { block ->
                    block.lines.map { IdTextLine(it.text, it.boundingBox?.height() ?: 0) }
                }
                val parsed = IdNameParser.parse(lines)
                val suggestions = IdNameParser.candidateWords(lines)
                when {
                    parsed != null && parsed == lastOcrCandidate && !isPaused.get() -> {
                        logger.i("ID_SCAN OCR name confirmed on consecutive frame")
                        fire(IdScanResult(parsed, suggestions), onDetected)
                    }
                    // No confident pair, but the same words keep showing up —
                    // surface them and let the user pick.
                    parsed == null && suggestions.size >= MIN_SUGGESTIONS_TO_FIRE &&
                        suggestions == lastSuggestions && !isPaused.get() -> {
                        logger.i("ID_SCAN OCR suggestions confirmed on consecutive frame")
                        fire(IdScanResult(name = null, suggestions = suggestions), onDetected)
                    }
                    // First sighting — hold as candidate; next frame must agree.
                    else -> {
                        lastOcrCandidate = parsed
                        lastSuggestions = suggestions
                    }
                }
            }
            .addOnFailureListener { ex ->
                logger.e("ID_SCAN OCR failure token=$token", ex)
            }
            .addOnCompleteListener {
                finishFrame(bitmap, token)
            }
    }

    private fun fire(result: IdScanResult, onDetected: (IdScanResult) -> Unit) {
        SoundUtils.playBarcodeSound(appContext)
        isPaused.set(true)
        ioScope.launch {
            withContext(Dispatchers.Main) { onDetected(result) }
        }
    }

    private fun finishFrame(bitmap: Bitmap, token: Long) {
        if (!bitmap.isRecycled) bitmap.recycle()
        // Everything below is only ours to touch if no newer frame has taken
        // over: a stale frame completing late must neither free the gate a new
        // frame holds nor cancel that new frame's watchdog (which would leave
        // the gate unrecoverable if the new frame's ML Kit callback is dropped).
        if (frameToken.get() == token) {
            watchdogJob?.cancel()
            isProcessing.set(false)
        }
    }
}
```

### 4.4 Porting notes for the analyzer

These are the non-obvious invariants. Each one exists because of a real failure mode.

**(a) Synchronous frame snapshot.** `imageProxy.toBitmap()` runs inline in `analyze()`, before any async work. The caller then closes the buffer immediately. If you defer the copy into a callback, you must hold the camera buffer open across the whole ML Kit chain — and CameraX's `STRATEGY_KEEP_ONLY_LATEST` buffer pool is small, so the stream stalls permanently once exhausted.

**(b) The single-flight gate must be released on every path.** Paths that release it: success, ML Kit failure listener, ML Kit completion listener, synchronous throw in `analyze()`, synchronous throw in `runOcr()`, watchdog timeout. Miss one and scanning dies silently until the screen is rebuilt. This is the single most common porting bug.

**(c) The frame token.** A stale frame's late callback must not free a gate that a *newer* frame now holds, and must not cancel the newer frame's watchdog. Compare-and-check `frameToken` before touching shared state:

```kotlin
if (frameToken.get() == token) {
    watchdogJob?.cancel()
    isProcessing.set(false)
}
```

**(d) Lazy client init + idempotent close.** `close()` uses `compareAndSet` so double-dispose is safe, and only closes clients that were actually created (`isInitialized()`), avoiding needless SDK init on a screen the user backs out of instantly.

**(e) Bitmap recycling.** Every analysed frame's bitmap is explicitly recycled in `finishFrame`. In a GC-managed port without manual bitmap lifetimes (JS, Swift with ARC) this is a no-op; in Android/Java/native it is mandatory or you OOM within seconds at 2.5 fps.

**(f) Callback thread.** `fire()` marshals the callback to the main/UI thread. The analyzer itself runs off the UI thread. Preserve this split.

**(g) AAMVA parsing when your SDK doesn't do it for you.** The PDF417 payload is a `@`-prefixed, newline-delimited record. Names live in these element IDs:

| Element ID | Meaning |
|---|---|
| `DCS` | Family / last name |
| `DAC` | First name |
| `DAD` | Middle name |
| `DBB` | Date of birth — **do not read** |
| `DAG`/`DAI`/`DAJ` | Address — **do not read** |
| `DAQ` | License number — **do not read** |

Minimal, scope-respecting extraction:

```ts
// Read ONLY the two name fields. Everything else stays untouched in the raw string
// and is discarded with the frame.
function parseAamvaName(raw: string): { firstName: string; lastName: string } | null {
  const line = (id: string) =>
    raw.split(/[\r\n]+/).find(l => l.startsWith(id))?.slice(id.length).trim() ?? '';
  const last = line('DCS');
  const first = line('DAC');
  return last && first ? { firstName: first, lastName: last } : null;
}
```

Legacy AAMVA versions used `DAB` (last) / `DAC` (first); accept both if you must support old cards.

---

## 5. Name parser — `IdNameParser`

Pure, dependency-free, deterministic. **Port and unit-test this before touching a camera.** It is the only part of the feature that can be developed and validated with zero device involvement.

### 5.1 Four-tier strategy, highest confidence first

| Tier | Method | Matches | Guard against |
|---|---|---|---|
| 1 | `labeledName` | AAMVA *printed* labels on a license front: `LN SMITH` / `FN JOHN`, or numbered `1 SMITH` / `2 JOHN` | Requires **both** labels present, so `1 MAIN ST` (an address line) cannot misfire |
| 2 | `nameLabeledName` | Explicit printed labels: `Name: Cole Paulson` inline, a bare `Name` with the value on the next line, or stacked `First Name` / `Last Name` | `\b` in the regex stops `Namesake…` matching `NAME` |
| 3 | `commaName` | `LAST, FIRST` on one line | Both sides must pass name-word validation |
| 4 | `prominentName` | Tallest line of 2–3 name-like words — the badge case | Role/org/license vocabulary filter |

Fallthrough chain:

```kotlin
fun parse(lines: List<IdTextLine>): IdCardName? {
    val cleaned = lines
        .map { it.copy(text = it.text.trim()) }
        .filter { it.text.isNotEmpty() }
    if (cleaned.isEmpty()) return null

    return labeledName(cleaned)
        ?: nameLabeledName(cleaned)
        ?: commaName(cleaned)
        ?: prominentName(cleaned)
}
```

### 5.2 Vocabulary tables

These are the tuning surface. Expect to extend them per deployment region and per badge design.

```kotlin
/** Titles/credentials that may surround a name without disqualifying the line. */
private val STRIPPED_TOKENS = setOf(
    "DR", "MR", "MRS", "MS", "MISS", "PROF",
    "RPH", "PHARMD", "PHD", "MD", "RN", "JR", "SR", "II", "III", "IV",
)

/** Vocabulary that marks a line as NOT a person's name. */
private val EXCLUDED_WORDS = setOf(
    // Roles / org words (badges)
    "PHARMACIST", "PHARMACY", "TECHNICIAN", "TECH", "INTERN", "NURSE", "DOCTOR",
    "MEDICAL", "CENTER", "CENTRE", "HOSPITAL", "CLINIC", "HEALTH", "HEALTHCARE",
    "CARE", "STAFF", "EMPLOYEE", "BADGE", "DEPARTMENT", "DEPT", "ID",
    // License vocabulary (DL fronts)
    "DRIVER", "DRIVERS", "LICENSE", "LICENCE", "IDENTIFICATION", "PERMIT", "CARD",
    "STATE", "USA", "CLASS", "DOB", "EXP", "ISS", "SEX", "HGT", "WGT", "EYES",
    "HAIR", "DONOR", "VETERAN", "ORGAN", "RESTRICTIONS", "ENDORSEMENTS", "REV",
    // Field labels / address words / connectors
    "NAME", "FIRST", "LAST", "MIDDLE", "OF", "THE", "AND",
    "STREET", "AVENUE", "ROAD", "DRIVE", "LANE", "BLVD", "APT", "ST", "AVE", "RD",
)
```

**Semantic difference between the two sets — get this right when porting:**

- `STRIPPED_TOKENS` are **removed** from the line, then the rest is evaluated. `DR COLE PAULSON` → `[COLE, PAULSON]` → valid.
- `EXCLUDED_WORDS` **disqualify the whole line**. `MEDICAL CENTER` → rejected entirely.

`STRIPPED_TOKENS` is domain-specific (this is a pharmacy app — `RPH`, `PHARMD`). `EXCLUDED_WORDS` is the union of badge vocabulary, US-license field labels and address words. When porting to another domain or locale, both need review; non-English deployments need locale-specific entries.

### 5.3 Regexes

```kotlin
private val LAST_NAME_LABEL  = Regex("""^(?:LN|1)[:.]?\s+(.+)$""", RegexOption.IGNORE_CASE)
private val FIRST_NAME_LABEL = Regex("""^(?:FN|2)[:.]?\s+(.+)$""", RegexOption.IGNORE_CASE)

// Explicit printed labels; the value is inline after the label or on the next
// line. \b keeps words that merely START with "name" ("Namesake…") from matching.
private val FIRST_LABEL_LINE     = Regex("""^FIRST\s*NAME\b[:.]?\s*(.*)$""", RegexOption.IGNORE_CASE)
private val LAST_LABEL_LINE      = Regex("""^LAST\s*NAME\b[:.]?\s*(.*)$""",  RegexOption.IGNORE_CASE)
private val FULL_NAME_LABEL_LINE = Regex("""^(?:FULL\s*)?NAME\b[:.]?\s*(.*)$""", RegexOption.IGNORE_CASE)

private val NAME_WORD  = Regex("""^[A-Za-z][A-Za-z'’-]*$""")
private val WHITESPACE = Regex("""\s+""")

private const val MAX_SUGGESTIONS = 8
```

`NAME_WORD` accepts ASCII letters plus apostrophe (both `'` and `’` — ML Kit emits the typographic form), and hyphen. **This regex rejects accented characters.** For non-English deployments widen it to a Unicode letter class:

```kotlin
private val NAME_WORD = Regex("""^\p{L}[\p{L}'’-]*$""")
```

Also note `NAME_WORD` requires a *letter* first — that is what keeps `100` and `8` (address/field-number lines) out.

### 5.4 Full source

```kotlin
package com.rite.pillcounting.core.scanning.logic

/** A single OCR line with its glyph height, used to rank prominence on the card. */
data class IdTextLine(val text: String, val heightPx: Int = 0)

/** Name extracted from a photo ID (driver's license or staff badge). */
data class IdCardName(val firstName: String, val lastName: String)

object IdNameParser {

    private val LAST_NAME_LABEL = Regex("""^(?:LN|1)[:.]?\s+(.+)$""", RegexOption.IGNORE_CASE)
    private val FIRST_NAME_LABEL = Regex("""^(?:FN|2)[:.]?\s+(.+)$""", RegexOption.IGNORE_CASE)

    private val FIRST_LABEL_LINE = Regex("""^FIRST\s*NAME\b[:.]?\s*(.*)$""", RegexOption.IGNORE_CASE)
    private val LAST_LABEL_LINE = Regex("""^LAST\s*NAME\b[:.]?\s*(.*)$""", RegexOption.IGNORE_CASE)
    private val FULL_NAME_LABEL_LINE = Regex("""^(?:FULL\s*)?NAME\b[:.]?\s*(.*)$""", RegexOption.IGNORE_CASE)

    private val NAME_WORD = Regex("""^[A-Za-z][A-Za-z'’-]*$""")

    private val STRIPPED_TOKENS = setOf(
        "DR", "MR", "MRS", "MS", "MISS", "PROF",
        "RPH", "PHARMD", "PHD", "MD", "RN", "JR", "SR", "II", "III", "IV",
    )

    private val EXCLUDED_WORDS = setOf(
        "PHARMACIST", "PHARMACY", "TECHNICIAN", "TECH", "INTERN", "NURSE", "DOCTOR",
        "MEDICAL", "CENTER", "CENTRE", "HOSPITAL", "CLINIC", "HEALTH", "HEALTHCARE",
        "CARE", "STAFF", "EMPLOYEE", "BADGE", "DEPARTMENT", "DEPT", "ID",
        "DRIVER", "DRIVERS", "LICENSE", "LICENCE", "IDENTIFICATION", "PERMIT", "CARD",
        "STATE", "USA", "CLASS", "DOB", "EXP", "ISS", "SEX", "HGT", "WGT", "EYES",
        "HAIR", "DONOR", "VETERAN", "ORGAN", "RESTRICTIONS", "ENDORSEMENTS", "REV",
        "NAME", "FIRST", "LAST", "MIDDLE", "OF", "THE", "AND",
        "STREET", "AVENUE", "ROAD", "DRIVE", "LANE", "BLVD", "APT", "ST", "AVE", "RD",
    )

    fun parse(lines: List<IdTextLine>): IdCardName? {
        val cleaned = lines
            .map { it.copy(text = it.text.trim()) }
            .filter { it.text.isNotEmpty() }
        if (cleaned.isEmpty()) return null

        return labeledName(cleaned)
            ?: nameLabeledName(cleaned)
            ?: commaName(cleaned)
            ?: prominentName(cleaned)
    }

    /**
     * Every name-like word on the card, most prominent line first — shown to
     * the user as tap-to-fill suggestions when [parse]'s single best guess may
     * be wrong (badges with unusual layouts). Looser than [parse]: any line of
     * up to 4 clean words contributes, so multi-part names aren't dropped.
     */
    fun candidateWords(lines: List<IdTextLine>): List<String> {
        val cleaned = lines
            .map { it.copy(text = it.text.trim()) }
            .filter { it.text.isNotEmpty() }
        // Values sitting next to an explicit name label are the most likely
        // name words on the card — surface them ahead of everything else.
        val labeled = nameLabelValues(cleaned).flatMap { suggestionWords(it) }
        val byProminence = cleaned
            .sortedByDescending { it.heightPx }
            .flatMap { suggestionWords(it.text) }
        return (labeled + byProminence).distinct().take(MAX_SUGGESTIONS)
    }

    /**
     * Name-like words from one line, or empty if the line can't be part of a
     * name (too long, digits, or role/org/license vocabulary anywhere in it).
     */
    private fun suggestionWords(text: String): List<String> {
        val words = text.split(WHITESPACE)
            .map { it.trim('.', ',') }
            .filter { it.isNotEmpty() && it.uppercase() !in STRIPPED_TOKENS }
        if (words.size > 4) return emptyList()
        if (words.any { !NAME_WORD.matches(it) || it.uppercase() in EXCLUDED_WORDS }) return emptyList()
        return words.filter { it.length >= 2 }.map { displayCase(it) }
    }

    /** "COLE" → "Cole", "O'BRIEN" → "O'Brien", "SMITH-JONES" → "Smith-Jones". */
    fun displayCase(raw: String): String {
        val lower = raw.trim().lowercase()
        val sb = StringBuilder(lower.length)
        var capitalizeNext = true
        for (c in lower) {
            sb.append(if (capitalizeNext && c.isLetter()) c.uppercaseChar() else c)
            capitalizeNext = !c.isLetter()
        }
        return sb.toString()
    }

    private fun labeledName(lines: List<IdTextLine>): IdCardName? {
        val last = lines.firstNotNullOfOrNull { line ->
            LAST_NAME_LABEL.find(line.text)?.groupValues?.get(1)?.takeIf { isNameText(it) }
        }
        val first = lines.firstNotNullOfOrNull { line ->
            FIRST_NAME_LABEL.find(line.text)?.groupValues?.get(1)?.takeIf { isNameText(it) }
        }
        if (last == null || first == null) return null
        // The FN value may carry a middle name ("JOHN A") — keep only the first word.
        return IdCardName(
            firstName = displayCase(first.split(WHITESPACE).first()),
            lastName = displayCase(last),
        )
    }

    /**
     * A printed name label anywhere on the card: "Name: Cole Paulson" inline,
     * a bare "Name" whose value is the NEXT line, or stacked "First Name" /
     * "Last Name" labels each with an inline or next-line value.
     */
    private fun nameLabeledName(lines: List<IdTextLine>): IdCardName? {
        var first: String? = null
        var last: String? = null
        var full: String? = null
        lines.forEachIndexed { index, line ->
            val firstMatch = FIRST_LABEL_LINE.find(line.text)
            val lastMatch = LAST_LABEL_LINE.find(line.text)
            // FULL anchors at "NAME…", so it can't also match a FIRST/LAST label line.
            val fullMatch = if (firstMatch == null && lastMatch == null) {
                FULL_NAME_LABEL_LINE.find(line.text)
            } else null
            when {
                firstMatch != null && first == null ->
                    first = labelValue(lines, index, firstMatch.groupValues[1])?.takeIf { isNameText(it) }
                lastMatch != null && last == null ->
                    last = labelValue(lines, index, lastMatch.groupValues[1])?.takeIf { isNameText(it) }
                fullMatch != null && full == null ->
                    full = labelValue(lines, index, fullMatch.groupValues[1])
            }
        }
        if (first != null && last != null) {
            return IdCardName(
                firstName = displayCase(first!!.split(WHITESPACE).first()),
                lastName = displayCase(last!!),
            )
        }
        return full?.let { commaNameFromText(it) ?: multiWordName(it) }
    }

    /** Values adjacent to any printed name label, for suggestion ranking. */
    private fun nameLabelValues(lines: List<IdTextLine>): List<String> =
        lines.mapIndexedNotNull { index, line ->
            val match = FIRST_LABEL_LINE.find(line.text)
                ?: LAST_LABEL_LINE.find(line.text)
                ?: FULL_NAME_LABEL_LINE.find(line.text)
                ?: return@mapIndexedNotNull null
            labelValue(lines, index, match.groupValues[1])
        }

    /** Inline remainder of a label line, or the following line when the label stands alone. */
    private fun labelValue(lines: List<IdTextLine>, index: Int, inline: String): String? {
        val value = inline.trim().ifEmpty { lines.getOrNull(index + 1)?.text?.trim().orEmpty() }
        return value.ifEmpty { null }
    }

    private fun commaName(lines: List<IdTextLine>): IdCardName? =
        lines.firstNotNullOfOrNull { commaNameFromText(it.text) }

    private fun commaNameFromText(text: String): IdCardName? {
        val parts = text.split(',')
        if (parts.size != 2) return null
        val lastPart = parts[0].trim()
        val firstPart = parts[1].trim()
        if (!isNameText(lastPart) || !isNameText(firstPart)) return null
        // The first-name side may carry a middle name/initial — keep the first word.
        val firstWord = firstPart.split(WHITESPACE).first()
        if (firstWord.length < 2 || lastPart.length < 2) return null
        return IdCardName(
            firstName = displayCase(firstWord),
            lastName = displayCase(lastPart),
        )
    }

    /**
     * Lenient first+last extraction for a value that a name label vouches for:
     * up to 4 clean words, first word → first name, last word → last name.
     */
    private fun multiWordName(text: String): IdCardName? {
        val words = text.split(WHITESPACE)
            .map { it.trim('.', ',') }
            .filter { it.isNotEmpty() && it.uppercase() !in STRIPPED_TOKENS }
        if (words.size !in 2..4) return null
        if (words.any { !NAME_WORD.matches(it) || it.uppercase() in EXCLUDED_WORDS }) return null
        if (words.first().length < 2 || words.last().length < 2) return null
        return IdCardName(
            firstName = displayCase(words.first()),
            lastName = displayCase(words.last()),
        )
    }

    private fun prominentName(lines: List<IdTextLine>): IdCardName? {
        val best = lines
            .mapNotNull { line -> nameWords(line.text)?.let { line to it } }
            .maxByOrNull { (line, _) -> line.heightPx }
            ?: return null
        val words = best.second
        return IdCardName(
            firstName = displayCase(words.first()),
            lastName = displayCase(words.last()),
        )
    }

    /**
     * Tokenizes a line and returns its 2–3 name words (titles/credentials
     * stripped, single-letter middle initial allowed), or null if the line
     * can't be a person's name.
     */
    private fun nameWords(text: String): List<String>? {
        val words = text.split(WHITESPACE)
            .map { it.trim('.', ',') }
            .filter { it.isNotEmpty() && it.uppercase() !in STRIPPED_TOKENS }
        if (words.size !in 2..3) return null
        if (words.any { !NAME_WORD.matches(it) || it.uppercase() in EXCLUDED_WORDS }) return null
        // First and last words must be real names; only a middle token may be an initial.
        if (words.first().length < 2 || words.last().length < 2) return null
        return words
    }

    private fun isNameText(text: String): Boolean {
        val words = text.trim().split(WHITESPACE)
        return words.isNotEmpty() &&
            words.all { NAME_WORD.matches(it) && it.uppercase() !in EXCLUDED_WORDS }
    }

    private val WHITESPACE = Regex("""\s+""")

    private const val MAX_SUGGESTIONS = 8
}
```

### 5.5 Word-length and word-count rules (summary table)

| Function | Word count accepted | Length rule | Purpose |
|---|---|---|---|
| `nameWords` (tier 4) | 2–3 | first & last ≥ 2 chars; middle may be a 1-char initial | Strict — drives an automatic guess |
| `multiWordName` (tier 2 fallback) | 2–4 | first & last ≥ 2 chars | Lenient — a name label already vouched for the value |
| `suggestionWords` (chips) | ≤ 4 | each emitted word ≥ 2 chars | Loosest — user picks, so false positives are cheap |

The asymmetry is intentional: **confidence required scales with how much autonomy the result gets.**

### 5.6 Suggestion ranking

`candidateWords` produces the chip list in this order:

1. Words adjacent to an explicit name label (`Name:`, `First Name`, `Last Name`) — most likely to be the actual name.
2. All other name-like words, ordered by descending line height (largest text first).
3. `distinct()` then `take(8)`.

The 8-cap keeps the chip row to roughly two rows on a phone. Adjust to your layout.

### 5.7 Test matrix

Existing coverage: [IdNameParserTest.kt](../app/src/test/java/com/rite/pillcounting/core/scanning/logic/IdNameParserTest.kt) — 22 tests. Reproduce **all** of these in the port; they encode the failure modes found during development.

```kotlin
@Test
fun `badge - picks prominent name line, skips org and role`() {
    val lines = listOf(
        IdTextLine("Medical Center", 30),
        IdTextLine("Cole Paulson", 42),
        IdTextLine("ID# 123456", 18),
        IdTextLine("PHARMACIST", 36),
    )
    assertEquals(IdCardName("Cole", "Paulson"), IdNameParser.parse(lines))
}

@Test
fun `license front - labeled LN FN fields`() {
    val lines = listOf(
        IdTextLine("CALIFORNIA DRIVER LICENSE", 20),
        IdTextLine("LN PAULSON", 24),
        IdTextLine("FN COLE ALAN", 24),
        IdTextLine("DOB 01/02/1990", 16),
    )
    assertEquals(IdCardName("Cole", "Paulson"), IdNameParser.parse(lines))
}

@Test
fun `license front - numbered fields with address noise`() {
    val lines = listOf(
        IdTextLine("1 PAULSON", 24),
        IdTextLine("2 COLE", 24),
        IdTextLine("8 100 MAIN ST", 16),
    )
    assertEquals(IdCardName("Cole", "Paulson"), IdNameParser.parse(lines))
}
```

Required cases:

| # | Case | Expectation |
|---|---|---|
| 1 | Badge, name is tallest line, org + role present | Name extracted, org/role skipped |
| 2 | Two 2-word lines, differing heights | Taller wins |
| 3 | `LN`/`FN` labels | Extracted; middle name dropped |
| 4 | Numbered `1`/`2` labels + `8 100 MAIN ST` | Extracted; address ignored |
| 5 | Only `1 MAIN ST` present (no `2` label) | Must **not** produce a name |
| 6 | `Name: Cole Paulson` inline | Extracted |
| 7 | Bare `Name`, value on next line | Extracted |
| 8 | Stacked `First Name` / `Last Name` | Extracted |
| 9 | `Namesake Awards` | Must **not** match the NAME label |
| 10 | No label anywhere | Falls through to prominence tier |
| 11 | `PAULSON, COLE` | Extracted |
| 12 | `DR COLE PAULSON RPH` | Titles/credentials stripped |
| 13 | `COLE A PAULSON` | Middle initial tolerated |
| 14 | `O'BRIEN`, `SMITH-JONES` | `displayCase` preserves punctuation |
| 15 | Empty line list | null |
| 16 | Only excluded vocabulary | null |
| 17–22 | `candidateWords`: label-adjacent ranked first, height ordering, dedupe, 8-cap, digit lines excluded, >4-word lines excluded | As specified |

### 5.8 Known coverage gaps in the source project

Carry these forward as work items when porting:

- No test for `IdCardAnalyzer` — the PDF417 branch, the two-frame OCR confirmation, the watchdog/gate release paths, `close()` idempotency.
- No UI test for `ScanPhotoIdStep` — chip `activeField` advancement, sheet-dismiss resume, session-lock rebind.

The analyzer is testable with a fake recogniser interface; that indirection does not exist in the Android source (ML Kit clients are constructed inline). **In a fresh port, introduce a recogniser interface from the start** so the analyzer's concurrency logic is unit-testable:

```ts
interface Recognizers {
  decodePdf417(frame: Frame): Promise<{ firstName: string; lastName: string } | null>;
  recognizeText(frame: Frame): Promise<IdTextLine[]>;
}
```

---

## 6. Camera layer — `CameraHelper`

Shared with the pill/Rx scanning flows in this repo; only the parts the ID scan depends on are documented here.

### 6.1 The ID scan's requirements of the camera layer

| Requirement | Why |
|---|---|
| Back camera | ID cards are held away from the operator |
| Latest-frame-only backpressure | Analysing a stale frame is worthless; a queue just adds latency |
| YUV output + rotation applied | ML Kit needs correctly-oriented input |
| Conflated frame channel that closes dropped frames | Otherwise the buffer pool exhausts and the stream stalls forever |
| Periodic centre autofocus | A one-shot AF at bind time locks onto the empty startup scene; the card presented afterwards stays soft |
| `pauseCamera()` that fully unbinds | Streaming frames under a bottom sheet drains battery for nothing |
| Rebind-on-demand | Session-lock overlay and stall watchdog both need to bring the camera back |

### 6.2 Frame channel — the critical detail

```kotlin
// onUndeliveredElement closes any frame the CONFLATED buffer overwrites before a slow
// collector reads it — without it, ImageAnalysis's KEEP_ONLY_LATEST strategy stalls
// forever once its buffer pool is exhausted by never-closed ImageProxy instances.
private val _frameChannel = Channel<ImageProxy>(Channel.CONFLATED, onUndeliveredElement = { it.close() })
val frameFlow = _frameChannel.receiveAsFlow()
```

```kotlin
private fun processImageProxy(image: ImageProxy) {
    try {
        if (!isStreaming.get()) {
            image.close()
            return
        }
        if (!_frameChannel.isClosedForSend) {
            if (!_frameChannel.trySend(image).isSuccess) {
                image.close()
            }
        } else image.close()
    } catch (t: Throwable) {
        logger.e("Analyzer error", t)
        image.close()
    }
}
```

**Every path closes the frame.** In any port with explicit buffer lifetimes, replicate this exhaustively.

### 6.3 Use-case configuration

```kotlin
val resolutionSelector = ResolutionSelector.Builder()
    .setResolutionStrategy(
        ResolutionStrategy(targetResolution, ResolutionStrategy.FALLBACK_RULE_CLOSEST_LOWER)
    )
    .build()

preview = Preview.Builder()
    .setResolutionSelector(resolutionSelector)
    .build()
    .also { it.surfaceProvider = previewView.surfaceProvider }

val initialRotation = previewView.display?.rotation ?: 0

imageAnalysis = ImageAnalysis.Builder()
    .setResolutionSelector(resolutionSelector)
    .setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST)
    .setOutputImageFormat(ImageAnalysis.OUTPUT_IMAGE_FORMAT_YUV_420_888)
    .setOutputImageRotationEnabled(true)
    .setTargetRotation(initialRotation)
    .build()
    .also { analysis ->
        val analyzerExec = analyzerExecutor?.takeUnless { it.isShutdown }
            ?: Executors.newSingleThreadExecutor().also { analyzerExecutor = it }
        analysis.setAnalyzer(analyzerExec) { processImageProxy(it) }
    }

cameraProvider.unbindAll()
boundCamera = cameraProvider.bindToLifecycle(
    lifecycleOwner, boundCameraSelector, preview, imageAnalysis, imageCapture
)
```

Default target resolution: **1280×720**. High enough for small printed license text, low enough that per-frame OCR stays under the throttle interval.

### 6.4 Periodic autofocus

```kotlin
/**
 * How often to re-trigger center autofocus. A single startup
 * startFocusAndMetering() locks focus on whatever was centered at bind time
 * (usually an empty scene) for the metering duration, so a bottle presented
 * afterward stays soft until focus re-converges.
 */
private val autofocusIntervalMs = 1500L

private fun startPeriodicFocus(previewView: PreviewView) {
    focusJob?.cancel()
    focusJob = focusScope.launch {
        while (isActive) {
            delay(autofocusIntervalMs)
            if (isStreaming.get() && isBound.get()) setCenterFocus(previewView)
        }
    }
}

fun setCenterFocus(previewView: PreviewView) {
    try {
        val cam = boundCamera ?: return
        // Skip until the preview has been measured — a 0×0 metering point is
        // meaningless and throws on some devices.
        if (previewView.width == 0 || previewView.height == 0) return
        val center = previewView.meteringPointFactory
            .createPoint(previewView.width / 2f, previewView.height / 2f)
        // Auto-cancel after roughly one refocus cycle so a triggered AF lock
        // never outlives the next re-trigger.
        val action = FocusMeteringAction.Builder(center, FocusMeteringAction.FLAG_AF)
            .setAutoCancelDuration(2, TimeUnit.SECONDS)
            .build()
        cam.cameraControl.startFocusAndMetering(action)
    } catch (e: Exception) {
        logger.e("Autofocus failed", e)
    }
}
```

Note the pairing: 1500 ms re-trigger interval, 2 s auto-cancel. The lock never outlives its successor.

### 6.5 `switchCamera` — used as "rebind" throughout the ID scan

```kotlin
/**
 * `startCamera()` early-returns while isBound is true, so calling it a second
 * time to change lenses is a silent no-op — this unbinds first so the new
 * selector actually takes effect.
 */
fun switchCamera(previewView: PreviewView, cameraSelector: CameraSelector) {
    if (!isBound.get()) {
        startCamera(previewView, cameraSelector = cameraSelector)
        return
    }
    try {
        cameraProviderFuture.get().unbindAll()
    } catch (e: Exception) {
        logger.w("Unbind before camera switch failed: ${e.message}")
    }
    preview = null
    imageAnalysis = null
    boundCamera = null
    isBound.set(false)
    isStreaming.set(false)
    startCamera(previewView, cameraSelector = cameraSelector)
}
```

`ScanPhotoIdStep` calls `switchCamera(view, DEFAULT_BACK_CAMERA)` in four places: initial bind, sheet dismiss, session unlock, stall recovery. It is the universal "(re)bind the back camera" entry point.

### 6.6 `pauseCamera` — full teardown, not a soft pause

```kotlin
fun pauseCamera() {
    focusJob?.cancel()
    focusJob = null
    try {
        cameraProviderFuture.get().unbindAll()
    } catch (_: Exception) {
        logger.i("Failed to pause camera")
    }
    preview = null
    imageAnalysis = null
    boundCamera = null
    isBound.set(false)
    isStreaming.set(false)
    analyzerExecutor?.shutdown()
    analyzerExecutor = null
}
```

The analyzer executor is reused across rebinds and shut down here — a fresh executor per bind leaked one thread each time.

---

## 7. Scan UI — `ScanPhotoIdStep`

### 7.1 Composable contract

```kotlin
@Composable
internal fun ScanPhotoIdStep(
    cameraHelper: CameraHelper,
    navController: NavController,
    firstName: String,
    lastName: String,
    isSessionLocked: Boolean,
    isVoiceoverEnabled: Boolean,
    onUserInteraction: () -> Unit,
    onFirstNameChange: (String) -> Unit,
    onLastNameChange: (String) -> Unit,
    onContinue: () -> Unit,
)
```

Stateless with respect to the *name* — the host owns `firstName`/`lastName`. The step owns only scan-session UI state.

### 7.2 Local state

```kotlin
private enum class NameField { FIRST, LAST }
private enum class ScanStatus { SCANNING, PAUSED, RESTARTING }

private const val FRAME_WATCHDOG_INTERVAL_MS = 2_000L
private const val FRAME_STALL_TIMEOUT_MS = 4_000L
```

```kotlin
val analyzer = remember { IdCardAnalyzer(context.applicationContext) }
val lastNameFocus = remember { FocusRequester() }
var previewView by remember { mutableStateOf<PreviewView?>(null) }
var showNameSheet by remember { mutableStateOf(false) }
var suggestions by remember { mutableStateOf(emptyList<String>()) }
// Which field a tapped suggestion chip fills. Two writers that can't
// conflict: focusing a field claims the target (onFocusChanged), and a chip
// tap advances it while CLEARING focus.
var activeField by remember { mutableStateOf(NameField.FIRST) }
// TextFieldValue (not plain String) so programmatic fills — scan results and
// chip taps — can place the cursor at the END of the text instead of the start.
var firstNameValue by remember { mutableStateOf(firstName.withCursorAtEnd()) }
var lastNameValue by remember { mutableStateOf(lastName.withCursorAtEnd()) }
var scanStatus by remember { mutableStateOf(ScanStatus.SCANNING) }
// Fed by every camera frame; the watchdog below rebinds the camera when it goes stale.
var lastFrameAtMs by remember { mutableLongStateOf(0L) }

DisposableEffect(Unit) { onDispose { analyzer.close() } }
```

```kotlin
/** A [TextFieldValue] whose cursor sits after the last character. */
private fun String.withCursorAtEnd() = TextFieldValue(this, TextRange(length))
```

Programmatic text fills must place the caret at the end. A plain string binding puts it at position 0, so the operator's first keystroke prepends instead of appends. Any port with a text-field abstraction must handle this explicitly.

### 7.3 Frame collection loop

```kotlin
LaunchedEffect(previewView) {
    previewView?.let { view ->
        cameraHelper.switchCamera(view, cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA)
        lastFrameAtMs = System.currentTimeMillis()
        // Off the main thread — analyze() copies the frame to a bitmap
        // synchronously (~30-80ms), which would jank the preview.
        // The analyzer posts its callback back to Main.
        withContext(Dispatchers.Default) {
            cameraHelper.frameFlow.collect { proxy ->
                lastFrameAtMs = System.currentTimeMillis()
                if (scanStatus == ScanStatus.RESTARTING) scanStatus = ScanStatus.SCANNING
                // try/finally: an analyzer throw must neither kill this
                // collector (scanning would silently die) nor leak the proxy.
                try {
                    // analyze() snapshots the frame synchronously, so the
                    // proxy can be closed as soon as it returns.
                    analyzer.analyze(proxy) { result ->
                        result.name?.let {
                            firstNameValue = it.firstName.withCursorAtEnd()
                            lastNameValue = it.lastName.withCursorAtEnd()
                            onFirstNameChange(it.firstName)
                            onLastNameChange(it.lastName)
                        }
                        suggestions = result.suggestions
                        activeField = NameField.FIRST
                        // Fully stop the camera while the sheet is up —
                        // streaming frames under a sheet just drains battery.
                        cameraHelper.pauseCamera()
                        scanStatus = ScanStatus.PAUSED
                        showNameSheet = true
                    }
                } finally {
                    proxy.close()
                }
            }
        }
    }
}
```

Three invariants: collect off the UI thread, `finally { proxy.close() }`, and the analyzer marshals its callback back to the UI thread itself.

### 7.4 Frame stall watchdog

```kotlin
// Frame watchdog: covers every "camera stuck" mode in one place — bind
// failure, a dead ImageAnalysis stream after a lens race, or a stalled
// pipeline. No frames for FRAME_STALL_TIMEOUT_MS while we should be
// scanning → rebind the camera, and keep retrying each interval.
// rememberUpdatedState: this effect is keyed on previewView, so its loop
// would otherwise capture the isSessionLocked value from launch time forever.
val sessionLockedNow by rememberUpdatedState(isSessionLocked)
LaunchedEffect(previewView) {
    val view = previewView ?: return@LaunchedEffect
    while (isActive) {
        delay(FRAME_WATCHDOG_INTERVAL_MS)
        val stalled = System.currentTimeMillis() - lastFrameAtMs > FRAME_STALL_TIMEOUT_MS
        if (stalled && !showNameSheet && !sessionLockedNow) {
            scanStatus = ScanStatus.RESTARTING
            cameraHelper.switchCamera(view, cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA)
            // Full stall window before judging the rebind, so we don't
            // thrash while the camera is still coming up.
            lastFrameAtMs = System.currentTimeMillis()
        }
    }
}
```

**Two watchdogs exist and they guard different things — keep both:**

| Watchdog | Location | Guards | Timeout |
|---|---|---|---|
| Frame stall | UI (`ScanPhotoIdStep`) | Camera stopped delivering frames | 4 s, checked every 2 s |
| ML Kit timeout | Analyzer | A frame entered the recogniser and never came back | 2.5 s |

Without the frame watchdog, a bind failure or a lens race leaves a black preview with no recovery. Without the analyzer watchdog, one dropped SDK callback latches the single-flight gate forever. Neither covers the other.

### 7.5 Session lock interplay

```kotlin
// The session-lock overlay lives in the ACTIVITY window; the sheet lives in
// its own dialog window ABOVE it. When the lock engages, close the sheet so
// the overlay is actually in front, and stop the camera work behind it.
// On unlock, bring scanning back.
var wasLocked by remember { mutableStateOf(false) }
LaunchedEffect(isSessionLocked) {
    if (isSessionLocked) {
        wasLocked = true
        showNameSheet = false
        analyzer.pause()
        cameraHelper.pauseCamera()
        scanStatus = ScanStatus.PAUSED
    } else if (wasLocked) {
        wasLocked = false
        previewView?.let {
            cameraHelper.switchCamera(it, cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA)
        }
        lastFrameAtMs = System.currentTimeMillis()
        analyzer.resume()
        scanStatus = ScanStatus.SCANNING
    }
}
```

App-specific (this app has an idle session lock), but the pattern generalises to any modal system overlay: a dialog-window sheet renders **above** an activity-window overlay, so the sheet must be dismissed for the overlay to be effective. Also note the lock overlay's own camera bind calls `unbindAll()`, killing this screen's use cases — hence the explicit rebind on unlock.

### 7.6 Camera layer UI

```kotlin
Box(modifier = Modifier.fillMaxSize()) {
    AndroidView(
        factory = { ctx -> PreviewView(ctx).also { previewView = it } },
        modifier = Modifier.fillMaxSize()
    )
    // ID-card-shaped scan guide.
    Box(
        modifier = Modifier
            .align(Alignment.Center)
            .size(width = 320.dp, height = 200.dp)
            .border(
                width = 3.dp,
                color = MaterialTheme.colorScheme.secondary,
                shape = RoundedCornerShape(16.dp)
            )
    )
    BackButton(navController = navController, modifier = Modifier.align(Alignment.TopStart).padding(16.dp))
    Box(modifier = Modifier.align(Alignment.TopCenter).padding(top = 16.dp)) {
        StepTitleWithSpeech(
            isSoundOverride = isVoiceoverEnabled,
            titleResOverride = R.string.face_scan_id_title
        )
    }
    // ... bottom card: status pill + hint + "Enter Manually" (below)
}
```

Guide rectangle is 320×200 dp — roughly the ISO/IEC 7810 ID-1 aspect ratio (85.6×54 mm ≈ 1.586:1). **It is visual guidance only; there is no crop.** The full frame goes to the recogniser. This matters: if you decide to crop to the guide, you change recognition behaviour for cards the user framed loosely, and the prominence heuristic's height comparisons shift.

### 7.7 Status pill

```kotlin
val statusColor = when (scanStatus) {
    ScanStatus.SCANNING   -> MaterialTheme.colorScheme.secondary
    ScanStatus.PAUSED     -> AppTheme.extendedColors.textColor
    ScanStatus.RESTARTING -> MaterialTheme.colorScheme.error
}
Row(verticalAlignment = Alignment.CenterVertically) {
    Box(modifier = Modifier.size(8.dp).background(color = statusColor, shape = CircleShape))
    Spacer(modifier = Modifier.width(8.dp))
    Text(
        text = stringResource(
            when (scanStatus) {
                ScanStatus.SCANNING   -> R.string.face_scan_id_status_scanning
                ScanStatus.PAUSED     -> R.string.face_scan_id_status_paused
                ScanStatus.RESTARTING -> R.string.face_scan_id_status_restarting
            }
        ),
        color = statusColor,
        style = MaterialTheme.typography.labelMedium
    )
}
```

A silently dead camera is indistinguishable from "no ID detected yet". The pill makes the difference visible, and turns the automatic stall recovery into something the operator can understand rather than a mystery freeze.

### 7.8 Manual entry fallback

```kotlin
HollowButton(
    text = stringResource(R.string.face_scan_id_enter_manually).uppercase(),
    onClick = {
        analyzer.pause()
        cameraHelper.pauseCamera()
        // Manual entry starts from a clean slate — no leftover
        // names or chips from an earlier scan.
        firstNameValue = "".withCursorAtEnd()
        lastNameValue = "".withCursorAtEnd()
        onFirstNameChange("")
        onLastNameChange("")
        suggestions = emptyList()
        activeField = NameField.FIRST
        scanStatus = ScanStatus.PAUSED
        showNameSheet = true
    },
    color = MaterialTheme.colorScheme.primary,
    fixedWidth = false
)
```

Same sheet, cleared state. One sheet implementation serves both entry paths.

### 7.9 Result bottom sheet

```kotlin
if (showNameSheet) {
    ModalBottomSheet(
        onDismissRequest = {
            showNameSheet = false
            // Bring the camera back up (it was fully stopped for battery
            // while the sheet was open), then rescan.
            previewView?.let {
                cameraHelper.switchCamera(it, cameraSelector = CameraSelector.DEFAULT_BACK_CAMERA)
            }
            lastFrameAtMs = System.currentTimeMillis()
            analyzer.resume()
            scanStatus = ScanStatus.SCANNING
        },
        sheetState = rememberModalBottomSheetState()
    ) {
        // The sheet gets its own window, which would pull the system nav
        // buttons back over the full-screen app.
        HideSystemBarsInCurrentWindow()
        // Focus + IME live per-window. These MUST be read inside the sheet's
        // dialog window — the step-level composition would hand back the
        // ACTIVITY's focus manager / keyboard controller, whose moveFocus/
        // clearFocus/hide are no-ops for fields hosted in this window.
        val sheetFocusManager = LocalFocusManager.current
        val sheetKeyboard = LocalSoftwareKeyboardController.current
        // ... content
    }
}
```

**Two window-scoping traps, both Compose-specific but conceptually portable to any dialog-window UI:**

1. A modal sheet opens its own window, which restores system bars over a full-screen app. Re-hide inside the sheet.
2. Focus manager and keyboard controller are per-window. Reading them outside the sheet gives you the activity's instances, whose `clearFocus()` / `hide()` are silent no-ops on fields inside the sheet.

### 7.10 Suggestion chips + `activeField`

```kotlin
if (suggestions.isNotEmpty()) {
    // Says exactly which field the next chip tap fills.
    Text(
        text = stringResource(
            R.string.face_scan_id_suggestions_label,
            stringResource(
                when (activeField) {
                    NameField.FIRST -> R.string.face_registration_first_name
                    NameField.LAST  -> R.string.face_registration_last_name
                }
            )
        ),
        color = MaterialTheme.colorScheme.primary,
        style = MaterialTheme.typography.bodySmall,
        modifier = Modifier.fillMaxWidth()
    )
    Spacer(modifier = Modifier.height(4.dp))
    FlowRow(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        suggestions.forEach { word ->
            SuggestionChip(
                onClick = {
                    onUserInteraction()
                    when (activeField) {
                        NameField.FIRST -> {
                            firstNameValue = word.withCursorAtEnd()
                            onFirstNameChange(word)
                            activeField = NameField.LAST
                        }
                        NameField.LAST -> {
                            lastNameValue = word.withCursorAtEnd()
                            onLastNameChange(word)
                        }
                    }
                    // Chip taps are pick-not-type: clear focus so NO field owns
                    // the cursor and the IME has nothing to attach to — focusing
                    // a field would summon the keyboard, and hiding it after the
                    // fact is racy. The highlight is driven by activeField alone;
                    // tapping a field directly re-focuses (and opens the
                    // keyboard) as usual.
                    sheetFocusManager.clearFocus()
                    sheetKeyboard?.hide()
                },
                label = { Text(word) }
            )
        }
    }
    Spacer(modifier = Modifier.height(12.dp))
}
```

`activeField` behaviour rules:

| Event | Effect on `activeField` | Focus/keyboard |
|---|---|---|
| Scan result arrives | Reset to `FIRST` | unchanged |
| Chip tapped while `FIRST` | Advance to `LAST` | **cleared**, keyboard hidden |
| Chip tapped while `LAST` | Stays `LAST` (repeated taps overwrite last name) | **cleared**, keyboard hidden |
| Field gains focus | Set to that field | normal focus |

The invariant: **whenever a cursor exists, it is in the highlighted field.** Two writers (`onFocusChanged` and chip tap) can never disagree, because a chip tap clears focus.

The auto-advance FIRST→LAST makes the common repair — OCR paired the wrong two words — exactly two taps.

### 7.11 Target-field highlight

```kotlin
/** Primary-colored border/label marking the field the next chip tap fills. */
@Composable
private fun chipTargetFieldColors(isTarget: Boolean): TextFieldColors =
    if (isTarget) {
        OutlinedTextFieldDefaults.colors(
            unfocusedBorderColor = MaterialTheme.colorScheme.primary,
            unfocusedLabelColor = MaterialTheme.colorScheme.primary,
        )
    } else {
        OutlinedTextFieldDefaults.colors()
    }
```

Only `unfocused*` colours are overridden, so the highlight is visible precisely when no cursor is present — which is exactly the chip-tap mode.

### 7.12 Text fields

```kotlin
OutlinedTextField(
    value = firstNameValue,
    onValueChange = {
        onUserInteraction()
        firstNameValue = it
        onFirstNameChange(it.text)
    },
    label = { Text(stringResource(R.string.face_registration_first_name)) },
    singleLine = true,
    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Next),
    keyboardActions = KeyboardActions(
        // Direct requester, not moveFocus: it targets the node itself so it
        // works regardless of window focus scope.
        onNext = { lastNameFocus.requestFocus() }
    ),
    colors = chipTargetFieldColors(
        isTarget = suggestions.isNotEmpty() && activeField == NameField.FIRST
    ),
    modifier = Modifier
        .fillMaxWidth()
        .onFocusChanged { if (it.isFocused) activeField = NameField.FIRST }
)
Spacer(modifier = Modifier.height(12.dp))
OutlinedTextField(
    value = lastNameValue,
    onValueChange = {
        onUserInteraction()
        lastNameValue = it
        onLastNameChange(it.text)
    },
    label = { Text(stringResource(R.string.face_registration_last_name)) },
    singleLine = true,
    keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
    keyboardActions = KeyboardActions(
        onDone = {
            sheetFocusManager.clearFocus()
            sheetKeyboard?.hide()
            // Done submits, same as the CONTINUE button — but only
            // under the same both-names-filled gate it enforces.
            if (firstName.isNotBlank() && lastName.isNotBlank()) {
                onContinue()
            }
        }
    ),
    colors = chipTargetFieldColors(
        isTarget = suggestions.isNotEmpty() && activeField == NameField.LAST
    ),
    modifier = Modifier
        .fillMaxWidth()
        .focusRequester(lastNameFocus)
        .onFocusChanged { if (it.isFocused) activeField = NameField.LAST }
)
Spacer(modifier = Modifier.height(24.dp))
ActionButtonPrimary(
    text = stringResource(R.string.face_registration_continue).uppercase(),
    onClick = onContinue,
    enabled = firstName.isNotBlank() && lastName.isNotBlank(),
    color = MaterialTheme.colorScheme.primary
)
```

The IME `Done` action and the CONTINUE button enforce the **same** gate: both names non-blank. Duplicating the gate rather than sharing a flag is deliberate — but if you port this, extracting `canContinue = firstName.isNotBlank() && lastName.isNotBlank()` is a safe improvement.

### 7.13 String resources

```xml
<string name="face_registration_title">Setup Quick Access</string>
<string name="face_scan_id_title">Scan Photo ID</string>
<string name="face_scan_id_hint">Hold your photo ID or driver\'s license inside the frame</string>
<string name="face_scan_id_enter_manually">Enter Manually</string>
<string name="face_scan_id_suggestions_label">%1$s Suggestions</string>
<string name="face_scan_id_status_scanning">Scanning for ID…</string>
<string name="face_scan_id_status_paused">Scanning paused</string>
<string name="face_scan_id_status_restarting">Restarting camera…</string>
<string name="face_registration_first_name">First Name</string>
<string name="face_registration_last_name">Last Name</string>
<string name="face_registration_continue">Continue</string>
```

`face_scan_id_suggestions_label` is parameterised with the target field's own localised label, so the chip header reads "First Name Suggestions" / "Last Name Suggestions" and follows `activeField` live. Translations exist in `values-es` and `values-fr`.

---

## 8. Flow host — `FaceRegistrationScreen`

### 8.1 Name state ownership

```kotlin
// rememberSaveable: a scanned/typed name survives activity recreation and
// process death while the user is still mid-enrollment.
var firstName by rememberSaveable { mutableStateOf("") }
var lastName by rememberSaveable { mutableStateOf("") }
var nameEntered by rememberSaveable { mutableStateOf(false) }

// After process death these flags are restored but the ViewModel's pending
// names are not — re-seed it, or the face scan would enroll a blank name.
// No-op on config changes: the surviving ViewModel is past Idle by then.
LaunchedEffect(Unit) {
    if (nameEntered && state is RegistrationState.Idle) {
        viewModel.startRegistration(firstName, lastName)
    }
}
```

**This is the subtlest bug in the whole feature.** The name lives in two places with different lifetimes:

| Holder | Survives config change | Survives process death |
|---|---|---|
| `rememberSaveable` (UI) | yes | yes (saved-instance bundle) |
| ViewModel `pendingFirstName/LastName` | yes | **no** |

After process death, the UI restores `nameEntered = true` and skips straight to face capture — with an empty ViewModel. Enrollment would then persist a blank name. The `LaunchedEffect` re-seeds the ViewModel, guarded on `state is RegistrationState.Idle` so it is a no-op on a mere config change (where the surviving ViewModel is already past `Idle`).

**Any port with a comparable two-tier state model needs this re-seed.** If your framework has a single state holder that survives both, the problem disappears — prefer that.

### 8.2 Step routing

```kotlin
Column(modifier = Modifier.fillMaxSize()) {
    when {
        !nameEntered -> {
            ScanPhotoIdStep(
                cameraHelper = cameraHelper,
                navController = navController,
                firstName = firstName,
                lastName = lastName,
                isSessionLocked = isSessionLocked,
                isVoiceoverEnabled = viewModel.isVoiceoverEnabled,
                onUserInteraction = viewModel::onSessionActivity,
                onFirstNameChange = { firstName = it },
                onLastNameChange = { lastName = it },
                onContinue = {
                    nameEntered = true
                    viewModel.startRegistration(firstName, lastName)
                }
            )
        }

        state is RegistrationState.Enrolled -> {
            EnrolledStep(
                onAddUser = {
                    nameEntered = false
                    firstName = ""
                    lastName = ""
                },
                onDone = { navController.popBackStack() }
            )
        }

        else -> ScanFaceStep(/* ... */)
    }
}
```

`onAddUser` resets all three flags — the next enrollment starts from a clean ID scan.

### 8.3 Shared `CameraHelper`

```kotlin
val cameraHelper = remember { CameraHelper(context, lifecycleOwner, ContextCompat.getMainExecutor(context)) }
```

One instance for both steps. The ID step binds the **back** camera; the face step binds the **front** camera by default. Because both go through `switchCamera` (which unbinds first), the handoff works without extra coordination.

### 8.4 Orientation lock

```kotlin
// Camera-based face/ID capture requires portrait framing on phones. Tablets keep
// free rotation because their landscape layout is intentionally supported.
val activity = context as? Activity
val isPhone = LocalConfiguration.current.smallestScreenWidthDp < TABLET_BREAKPOINT_DP
DisposableEffect(Unit) {
    if (isPhone) activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_PORTRAIT
    onDispose {
        if (isPhone) activity?.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
    }
}
```

---

## 9. Persistence — from name to Quick Access user

### 9.1 Entity

```kotlin
/**
 * Room entity representing one enrolled "Quick Access" face profile.
 *
 * A local-only record created when an operator registers their face via the
 * Settings > Face Recognition flow. Distinct from UserEntity (the backend
 * account record) — email here is a snapshot copied from the logged-in
 * session at registration time, not an ongoing link to that account.
 */
@Entity(tableName = "face_profiles")
data class FaceProfileEntity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0L,
    val firstName: String,   // ← from the ID scan
    val lastName: String,    // ← from the ID scan
    val email: String?,
    val isEnabled: Boolean = true,
    val createdAt: Long,
    val lastUsedAt: Long? = null,
    val faceImagePath: String? = null
)
```

Equivalent DDL:

```sql
CREATE TABLE face_profiles (
    id            INTEGER PRIMARY KEY AUTOINCREMENT,
    firstName     TEXT    NOT NULL,
    lastName      TEXT    NOT NULL,
    email         TEXT,
    isEnabled     INTEGER NOT NULL DEFAULT 1,
    createdAt     INTEGER NOT NULL,
    lastUsedAt    INTEGER,
    faceImagePath TEXT
);
```

`firstName` / `lastName` are exactly and only what the ID scan contributes. Note what is **not** in the schema: no DOB column, no license-number column, no ID-image path. The schema itself enforces the privacy scope.

### 9.2 ViewModel binding path

```kotlin
private var pendingFirstName: String = ""
private var pendingLastName: String = ""

/**
 * Begins a new registration: resets any prior capture progress.
 */
fun startRegistration(firstName: String, lastName: String) {
    pendingFirstName = firstName
    pendingLastName = lastName
    capturedEmbeddings.clear()
    pendingFrontBitmap = null
    autoCaptureJob?.cancel()
    autoCaptureFrames = null
    _registrationState.value = RegistrationState.Capturing(FaceCaptureAngle.FRONT, 0)
}
```

```kotlin
/** Guards finishRegistration against double-taps while the async insert is still running. */
private var finishInFlight = false

fun finishRegistration() {
    if (finishInFlight || _registrationState.value is RegistrationState.Enrolled) return
    finishInFlight = true
    viewModelScope.launch {
        try {
            if (capturedEmbeddings.size < FaceCaptureAngle.entries.size) {
                _registrationState.value = RegistrationState.Failed
                return@launch
            }
            val email = sessionEmailProvider()
            val faceImagePath = pendingFrontBitmap?.let { saveFaceImage(it) }
            faceProfileRepository.registerProfile(
                firstName = pendingFirstName,   // ← ID-scan name lands here
                lastName = pendingLastName,     // ←
                email = email,
                embeddingsByAngle = capturedEmbeddings.toMap(),
                now = System.currentTimeMillis(),
                faceImagePath = faceImagePath
            )
            _registrationState.value = RegistrationState.Enrolled
        } finally {
            finishInFlight = false
        }
    }
}
```

The ID-scan name is carried, unmodified, from `startRegistration` through all three face-capture angles to `registerProfile`. No re-validation, no re-normalisation — the operator already confirmed it in the sheet.

`finishInFlight` plus the `Enrolled` state check makes the persist idempotent against double-taps.

### 9.3 Repository — atomic insert

```kotlin
suspend fun registerProfile(
    firstName: String,
    lastName: String,
    email: String?,
    embeddingsByAngle: Map<FaceCaptureAngle, FloatArray>,
    now: Long,
    faceImagePath: String? = null
): Long = profileDao.insertWithEmbeddings(
    FaceProfileEntity(
        firstName = firstName,
        lastName = lastName,
        email = email,
        createdAt = now,
        faceImagePath = faceImagePath
    )
) { id ->
    embeddingsByAngle.map { (angle, vec) ->
        FaceEmbeddingEntity(faceProfileId = id, angle = angle.name, vec = floatArrayToBytes(vec))
    }
}
```

### 9.4 DAO — the transaction that matters

```kotlin
/**
 * Inserts a profile and its per-angle embeddings atomically, so a failure
 * between the two writes can't leave an enabled profile with nothing to
 * match against (which would arm the session lock with no way to unlock).
 */
@Transaction
suspend fun insertWithEmbeddings(
    profile: FaceProfileEntity,
    embeddings: (faceProfileId: Long) -> List<FaceEmbeddingEntity>
): Long {
    val id = insert(profile)
    insertEmbeddings(embeddings(id))
    return id
}
```

**This transaction is a safety requirement, not an optimisation.** A profile row inserted with `isEnabled = 1` but no embedding rows is a user who can never authenticate — and in this app that arms a session lock with no way to unlock it. Any port must keep profile + credential writes in one transaction.

```kotlin
@Query("SELECT * FROM face_profiles ORDER BY createdAt DESC")
fun observeAll(): Flow<List<FaceProfileEntity>>
```

Feeds the Quick Access Users list, where the scanned name is finally displayed as `"${profile.firstName} ${profile.lastName}"`.

---

## 10. Permissions

Manifest:

```xml
<uses-permission android:name="android.permission.CAMERA" />
```

Runtime request happens in `MainActivity` at app startup. **`ScanPhotoIdStep` and `FaceRegistrationScreen` have no per-screen permission gate** — they rely on that startup request. Other camera screens in the repo (dispense flow, inventory scan) gate explicitly via `PermissionUtils`.

**Recommendation for the port:** add the per-screen gate. Relying on a startup grant means that if the user revokes camera permission from system settings while the app is in the background, the ID-scan screen shows a permanently black preview with a "Restarting camera…" pill — the frame watchdog will spin forever, because a missing permission is not a recoverable stall. An explicit gate turns that into a clear message and a settings deep-link.

---

## 11. Port checklist

Ordered so that each step is verifiable before the next.

### Phase 1 — Pure logic (no device needed)
- [ ] Port `IdTextLine`, `IdCardName`, `IdScanResult`.
- [ ] Port `displayCase` (apostrophes and hyphens re-capitalise).
- [ ] Port `STRIPPED_TOKENS` and `EXCLUDED_WORDS`, keeping the strip-vs-disqualify distinction.
- [ ] Port `NAME_WORD` — widen to `\p{L}` if you need accented names.
- [ ] Port all four tiers and the fallthrough order.
- [ ] Port `candidateWords` including label-first ranking and the 8-cap.
- [ ] Reproduce the full test matrix (§5.7). **All green before continuing.**

### Phase 2 — Recognition engine
- [ ] Define a recogniser interface (`decodePdf417`, `recognizeText`) so the analyzer is testable.
- [ ] Implement the throttle (`MIN_INTERVAL_MS`).
- [ ] Implement the single-flight gate; enumerate every release path and cover each.
- [ ] Implement the frame token; verify a stale late callback cannot free a newer frame's gate.
- [ ] Implement the watchdog (`MLKIT_TIMEOUT_MS`).
- [ ] Synchronous frame snapshot; release the camera buffer immediately.
- [ ] PDF417 first; on hit fire immediately. Wire AAMVA `DCS`/`DAC` if your SDK gives raw payloads — read **only** those two.
- [ ] OCR fallback with two-frame confirmation for both the parsed-name and suggestions-only cases.
- [ ] Marshal the callback to the UI thread.
- [ ] `pause()` / `resume()` (resume clears both candidate buffers) / idempotent `close()`.
- [ ] Free frame buffers on every exit path.

### Phase 3 — Camera layer
- [ ] Back camera, ~1280×720, latest-frame-only backpressure.
- [ ] Correctly-oriented output for the recogniser.
- [ ] Conflated frame channel that closes dropped frames.
- [ ] Periodic centre autofocus (~1.5 s), auto-cancel ~2 s, skip on unmeasured preview.
- [ ] `pause` that fully unbinds and shuts down the analysis executor.
- [ ] A single "rebind back camera" entry point that unbinds first.

### Phase 4 — Scan UI
- [ ] Full-screen preview + ID-shaped guide (~1.586:1). No crop.
- [ ] Frame collection off the UI thread, `finally`-close every frame.
- [ ] Status indicator with SCANNING / PAUSED / RESTARTING.
- [ ] Frame stall watchdog (4 s stale, 2 s poll) that rebinds; suppress while a sheet is open.
- [ ] Result sheet: editable first/last fields, cursor placed at end on programmatic fill.
- [ ] Suggestion chips with `activeField` targeting, auto-advance FIRST→LAST, clear focus on tap.
- [ ] Target-field highlight visible only when no cursor is present.
- [ ] Chip header naming the target field, parameterised for translation.
- [ ] "Enter Manually" opens the same sheet with cleared state.
- [ ] Sheet dismiss rebinds the camera and resumes the analyzer.
- [ ] CONTINUE and IME-Done share the both-names-non-blank gate.
- [ ] Dispose the analyzer when the screen leaves.
- [ ] Hide system bars inside the sheet's own window if the app is full-screen.
- [ ] Read focus/keyboard controllers **inside** the sheet's window.

### Phase 5 — Flow + persistence
- [ ] Host owns `firstName` / `lastName` / `nameEntered` in state that survives process death.
- [ ] Re-seed downstream state after process death (§8.1) if you have a two-tier state model.
- [ ] Continue advances to face capture and seeds the pending name.
- [ ] Persist profile + credentials in **one transaction**.
- [ ] Guard the persist against double-submit.
- [ ] Reset all name flags on "Add another user".
- [ ] Display the name in the Quick Access users list.

### Phase 6 — Platform concerns
- [ ] Camera permission declared and requested; **add a per-screen gate** (§10).
- [ ] Obfuscation/minification keep rules for the OCR/barcode SDK.
- [ ] Lock orientation on phones if your layout assumes portrait.
- [ ] Localise all scan strings; keep the parameterised suggestions label.
- [ ] Confirm no ID frame is written to disk anywhere.
- [ ] Confirm no non-name AAMVA field is read, logged, or stored.

---

## 12. Failure-mode reference

| Symptom | Cause | Mitigation in this design |
|---|---|---|
| Scanning silently stops working, preview still live | Single-flight gate latched by an unreleased path | Analyzer watchdog (`MLKIT_TIMEOUT_MS`) + gate release on all six paths |
| Preview black, status shows RESTARTING forever | Camera never bound (often a revoked permission) | Frame watchdog retries; **add a permission gate** — a watchdog cannot fix a missing grant |
| Frame stream stalls after a few seconds | Dropped `ImageProxy` never closed; buffer pool exhausted | `onUndeliveredElement = { it.close() }` + `finally { proxy.close() }` |
| OOM within seconds of opening the screen | Per-frame bitmaps not recycled | Explicit `bitmap.recycle()` in `finishFrame` |
| Wrong name appears then corrects itself | Single-frame OCR misread surfaced | Two-frame confirmation requirement |
| Blank name persisted after process death | ViewModel pending names lost while UI flags restored | Re-seed `LaunchedEffect` (§8.1) |
| User can never authenticate after enrolling | Profile row written without credential rows | `@Transaction insertWithEmbeddings` |
| Typing prepends instead of appends | Programmatic fill left the caret at position 0 | `withCursorAtEnd()` |
| Keyboard pops up on every chip tap | Chip tap focused a field | Chip tap clears focus; highlight driven by `activeField` |
| System nav bars reappear when the sheet opens | Sheet is a separate window | `HideSystemBarsInCurrentWindow()` inside the sheet |
| `clearFocus()` / `hide()` do nothing | Controllers read from the wrong window | Read them inside the sheet's composition |
| Address line parsed as a name | `1 MAIN ST` matched a numbered label | Tier 1 requires **both** `1`/`LN` and `2`/`FN`; `NAME_WORD` requires a leading letter |
| Badge org name parsed as a person | Org vocabulary not filtered | `EXCLUDED_WORDS` disqualifies the whole line |
| Card in focus but blurry text | One-shot AF locked on the empty startup scene | Periodic centre autofocus |
| Battery drain while the sheet is open | Camera still streaming behind the sheet | `pauseCamera()` on hit; rebind on dismiss |
| Session-lock overlay hidden behind the sheet | Sheet is in a higher window than the activity overlay | Dismiss the sheet when the lock engages |
| Preview dead after session unlock | Overlay's own bind called `unbindAll()` | Explicit rebind on unlock |
