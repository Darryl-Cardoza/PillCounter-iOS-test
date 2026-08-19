# Photo ID OCR Scan — Process & Flow Reference

**Companion to:** [ID_SCAN_OCR_IMPLEMENTATION.md](ID_SCAN_OCR_IMPLEMENTATION.md) — code, contracts, port checklist.

This document describes **what happens, in what order, and why** — from the operator tapping "Setup Quick Access" to a Quick Access user row existing in the database. Read this first to understand the feature; read the implementation doc to build it.

---

## 1. Feature in one paragraph

An operator enrolling for Quick Access (face-based unlock) first proves who they are by holding a photo ID up to the back camera. The app runs each camera frame through a PDF417 barcode decoder and, failing that, an OCR text recogniser, extracting **only the person's first and last name**. The extracted name pre-fills two editable fields in a bottom sheet, alongside tap-to-fill chips of every name-like word the camera saw. The operator confirms or corrects, taps Continue, and the name travels through three face-capture steps to be persisted as the display identity of a new Quick Access user record.

---

## 2. Actors and components

| Actor / component | Role in the flow |
|---|---|
| **Operator** | Holds the ID, confirms or corrects the name |
| **Flow host** (`FaceRegistrationScreen`) | Owns the name state; routes between ID scan → face capture → enrolled |
| **Scan screen** (`ScanPhotoIdStep`) | Camera preview, guide overlay, status pill, result sheet |
| **Camera layer** (`CameraHelper`) | Binds CameraX, emits frames on a conflated channel, autofocus, pause/rebind |
| **Analyzer** (`IdCardAnalyzer`) | Per-frame orchestration: throttle → PDF417 → OCR → confirmation → fire |
| **Parser** (`IdNameParser`) | Pure heuristics: OCR lines → name + suggestion words |
| **ViewModel** (`FaceAuthViewModel`) | Carries the confirmed name across face capture; triggers the persist |
| **Repository + DAO** | Atomic write of profile + face embeddings |

---

## 3. End-to-end journey

```
  Settings
     │  tap "Face Recognition"
     ▼
  Face Intro  ── "Setup Quick Access"
     │  tap "Get Started"
     ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 1 — SCAN PHOTO ID                     (this feature)  │
│                                                             │
│  back camera live · ID-shaped guide · status pill           │
│         │                                                   │
│         ├── ID detected  ──► result sheet (prefilled)       │
│         └── "Enter Manually" ──► result sheet (empty)       │
│                        │                                    │
│         sheet: editable First/Last + suggestion chips       │
│                        │  CONTINUE (both names non-blank)   │
└────────────────────────┼────────────────────────────────────┘
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  STEP 2 — SCAN FACE  ×3 angles (FRONT, TILT_LEFT, TILT_RIGHT)│
│  front camera · auto-capture with quality + pose gates      │
└────────────────────────┬────────────────────────────────────┘
                         ▼
              finishRegistration()
                         │
        ┌────────────────┴─────────────────┐
        │  ONE TRANSACTION                 │
        │  face_profiles   ← name here     │
        │  face_embeddings ← 3 vectors     │
        └────────────────┬─────────────────┘
                         ▼
              STEP 3 — ENROLLED
                  │            │
             "Add User"      "Done"
             (reset all)   (back to Settings)
                         ▼
              Quick Access Users list
              shows "First Last"
```

The name captured in Step 1 is the only thing Step 1 contributes — but it is what makes every later screen human-readable.

---

## 4. Scan loop — the core cycle

### 4.1 Narrative

1. The screen composes; a `PreviewView` is created and the back camera binds.
2. `CameraHelper` starts emitting frames on a conflated channel — only the newest frame is ever waiting.
3. A coroutine collects frames **off the UI thread** and hands each one to the analyzer, then closes it in a `finally`.
4. The analyzer drops frames that arrive within 400 ms of the last attempt, and drops frames that arrive while a previous frame is still in flight.
5. An accepted frame is copied to a bitmap **synchronously**, so the camera buffer can be released immediately.
6. A watchdog is armed for that frame (2.5 s).
7. The frame goes to the PDF417 decoder first.
   - **Driver-license barcode found with both names** → fire immediately. Authoritative.
   - **No barcode, or barcode without both names, or decoder failed** → fall through to OCR.
8. OCR returns text lines with glyph heights. The parser produces a best-guess name and a ranked list of suggestion words.
9. The analyzer compares against the previous frame's result:
   - **Same name as last frame** → fire, with suggestions attached.
   - **No name, but the same ≥2 suggestions as last frame** → fire with suggestions only.
   - **Anything else** → store as the new candidate and wait for the next frame.
10. On fire: play a scan sound, self-pause, post the result to the UI thread.
11. The UI fills the fields, stops the camera entirely, and opens the result sheet.

### 4.2 Sequence diagram — successful OCR path

```
Operator   PreviewView   CameraHelper   Analyzer        Parser       Screen
   │            │             │            │               │            │
   │ holds ID   │             │            │               │            │
   │───────────►│             │            │               │            │
   │            │  frame N    │            │               │            │
   │            │────────────►│            │               │            │
   │            │             │  analyze() │               │            │
   │            │             │───────────►│               │            │
   │            │             │  (throttle passes,         │            │
   │            │             │   gate acquired,           │            │
   │            │             │   bitmap snapshot)         │            │
   │            │             │◄───returns─┤               │            │
   │            │  close()    │            │               │            │
   │            │             │            │ PDF417 decode │            │
   │            │             │            │  → no barcode │            │
   │            │             │            │ OCR           │            │
   │            │             │            │──lines───────►│            │
   │            │             │            │◄─name+sugg────┤            │
   │            │             │            │ store candidate            │
   │            │             │            │ (frame 1 of 2)             │
   │            │  frame N+1  │            │               │            │
   │            │────────────►│            │               │            │
   │            │             │───────────►│               │            │
   │            │             │            │ OCR           │            │
   │            │             │            │──lines───────►│            │
   │            │             │            │◄─same name────┤            │
   │            │             │            │ CONFIRMED     │            │
   │            │             │            │ sound + pause │            │
   │            │             │            │───result (UI thread)──────►│
   │            │             │            │               │  fill fields
   │            │             │◄────pauseCamera()──────────────────────┤
   │            │             │            │               │  open sheet
   │◄───────────────────── sheet with prefilled name ──────────────────┤
```

### 4.3 Sequence diagram — PDF417 fast path

```
Operator   CameraHelper   Analyzer                        Screen
   │            │             │                              │
   │ shows back │             │                              │
   │ of license │             │                              │
   │───────────►│  frame      │                              │
   │            │────────────►│ PDF417 decode                │
   │            │             │  → TYPE_DRIVER_LICENSE       │
   │            │             │  → firstName + lastName      │
   │            │             │ FIRE (no second frame needed)│
   │            │             │───────result────────────────►│
   │            │◄────pauseCamera()──────────────────────────┤
   │◄──────── sheet, fields filled, NO chips ────────────────┤
```

No two-frame confirmation, and no suggestion chips — the barcode payload is structured data, not a visual guess, so there is nothing to second-guess and nothing to offer as an alternative.

### 4.4 Why the two paths differ

| | PDF417 / AAMVA | OCR |
|---|---|---|
| Source | Structured, error-corrected barcode payload | Visual glyph recognition |
| Confidence | Authoritative | Heuristic |
| Frames needed | 1 | 2 consecutive, agreeing |
| Suggestions offered | none | yes |
| Typical trigger | Back of a US driver's license | Front of a license, or any staff badge |

The confirmation requirement is the accuracy lever for OCR. A single frame at a bad angle, mid-focus, or with glare produces plausible garbage; requiring the identical result twice in a row at 400 ms spacing filters nearly all of it, at the cost of ~400 ms extra latency.

---

## 5. State machines

### 5.1 Scan status (what the operator sees)

```
                    ┌──────────────┐
      screen opens  │              │
      ─────────────►│   SCANNING   │◄──────────────┐
                    │  (green dot) │               │
                    └───┬──────┬───┘               │
          detection /   │      │  no frames 4 s    │ frame arrives
          manual entry /│      │  (and no sheet,   │
          session lock  │      │   not locked)     │
                        ▼      ▼                   │
                 ┌────────┐  ┌────────────┐        │
                 │ PAUSED │  │ RESTARTING │────────┘
                 │(neutral│  │   (red)    │
                 │  dot)  │  │  rebinding │
                 └───┬────┘  └─────┬──────┘
                     │             │ still no frames
       sheet dismissed│            │ next interval
       / session      │            └──► retry rebind
       unlocked       │
                      └──► SCANNING
```

| Status | Colour | Camera | Analyzer | Meaning to the operator |
|---|---|---|---|---|
| SCANNING | secondary/green | bound, streaming | active | Hold the ID in the frame |
| PAUSED | neutral text | unbound | paused | Sheet is open, or session locked |
| RESTARTING | error/red | rebinding | active | Camera hiccup, recovering automatically |

The pill exists because a dead camera and "no ID detected yet" look identical otherwise. It turns automatic recovery from a mystery freeze into visible feedback.

### 5.2 Analyzer internal state

```
        ┌────────────────────────────────────────────┐
        │                  IDLE                      │
        │  isProcessing=false, isPaused=false        │
        └──────────────────┬─────────────────────────┘
                           │ frame arrives
                    ┌──────▼───────┐
                    │ throttle?    │ <400ms since last → DROP
                    └──────┬───────┘
                    ┌──────▼───────┐
                    │ gate free?   │ no → DROP
                    └──────┬───────┘
                           │ acquire gate, snapshot bitmap,
                           │ increment token, arm watchdog
        ┌──────────────────▼─────────────────────────┐
        │              PROCESSING                    │
        │  isProcessing=true, token=N                │
        └──────┬───────────────────────┬─────────────┘
               │ PDF417 hit            │ PDF417 miss/fail
               ▼                       ▼
          ┌────────┐            ┌─────────────┐
          │  FIRE  │            │  OCR + parse│
          └───┬────┘            └──────┬──────┘
              │                        │
              │        ┌───────────────┼───────────────┐
              │        │ matches       │ no match      │
              │        │ last frame    │               │
              │        ▼               ▼               │
              │   ┌────────┐    ┌──────────────┐       │
              │   │  FIRE  │    │ store as     │       │
              │   └───┬────┘    │ candidate    │       │
              │       │         └──────┬───────┘       │
              └───────┴────────────────┘               │
                      │                               │
                      ▼                               ▼
        ┌─────────────────────────────┐   ┌──────────────────────┐
        │  PAUSED (self-paused)       │   │ finishFrame: recycle │
        │  awaiting resume()          │   │ bitmap, release gate │
        └─────────────────────────────┘   │ (only if token still │
                                          │  current)            │
                                          └──────────┬───────────┘
                                                     ▼
                                                   IDLE
```

**Escape hatches from PROCESSING** (all six must exist — this is where ports break):

1. PDF417 success → fire + finishFrame
2. OCR success → maybe fire, then finishFrame via the completion listener
3. OCR failure listener → completion listener still runs finishFrame
4. Synchronous throw during dispatch → catch + finishFrame
5. Synchronous throw entering OCR → catch + finishFrame
6. Watchdog at 2.5 s → force-release the gate

Miss any one and the gate latches: the camera keeps streaming, the preview looks perfectly alive, and no frame is ever analysed again.

### 5.3 Registration state (flow host)

```
   Idle
     │  startRegistration(firstName, lastName)   ← ID scan result lands here
     ▼
   Capturing(FRONT, 0)
     │  angle committed
     ▼
   Capturing(TILT_LEFT, 1)
     │
     ▼
   Capturing(TILT_RIGHT, 2)
     │  all 3 captured → finishRegistration()
     ▼
   Enrolled ──► "Add User" resets host flags ──► back to ID scan
            └─► "Done" ──► pop back to Settings

   (Rejected(angle, reason) and Failed are transient/terminal side states)
```

### 5.4 Name state ownership across the flow

```
┌─── Flow host (rememberSaveable) ─────────────────────────────┐
│  firstName, lastName, nameEntered                            │
│  survives: config change ✓   process death ✓                 │
└───────────────────┬──────────────────────────────────────────┘
                    │ onContinue → startRegistration(first, last)
┌───────────────────▼──────────────────────────────────────────┐
│  ViewModel: pendingFirstName, pendingLastName                │
│  survives: config change ✓   process death ✗                 │
└───────────────────┬──────────────────────────────────────────┘
                    │ finishRegistration → registerProfile(...)
┌───────────────────▼──────────────────────────────────────────┐
│  Room: face_profiles.firstName / .lastName                    │
│  survives: everything                                         │
└──────────────────────────────────────────────────────────────┘
```

**The gap in the middle is a real bug source.** After process death the host restores `nameEntered = true` and routes straight to face capture — with an empty ViewModel. Enrollment would persist a blank name. The host therefore re-seeds the ViewModel on first composition, guarded on the registration state still being `Idle` so it is a no-op after a mere rotation.

---

## 6. Decision trees

### 6.1 Which recognition path fires

```
frame accepted
   │
   ├─ PDF417 barcode present?
   │     │
   │     ├─ yes → is it TYPE_DRIVER_LICENSE?
   │     │          │
   │     │          ├─ yes → both firstName and lastName non-empty?
   │     │          │          ├─ yes → FIRE (authoritative, no chips)
   │     │          │          └─ no  → fall through to OCR
   │     │          └─ no  → fall through to OCR
   │     └─ no / decode failed → fall through to OCR
   │
   └─ OCR
        │
        ├─ parser returned a name?
        │     ├─ yes → identical to last frame's name?
        │     │          ├─ yes → FIRE (name + chips)
        │     │          └─ no  → store candidate, wait
        │     └─ no  → ≥2 suggestions AND identical to last frame's?
        │                ├─ yes → FIRE (chips only, fields stay empty)
        │                └─ no  → store candidate, wait
```

### 6.2 Which parser tier wins

Tried in order; first non-null result wins.

```
OCR lines (text + glyph height)
   │
   ├─ TIER 1 — AAMVA printed labels
   │   Requires BOTH:  "LN <value>" or "1 <value>"
   │              and  "FN <value>" or "2 <value>"
   │   Guard: both-required, so "1 MAIN ST" alone cannot misfire
   │   Middle name dropped from the FN value
   │   ✓ → done
   │
   ├─ TIER 2 — explicit printed name label
   │   "Name: Cole Paulson"          (inline value)
   │   "Name" / next line is value   (stacked value)
   │   "First Name" + "Last Name"    (stacked labels)
   │   Guard: \b so "Namesake…" does not match
   │   Full-name value → try comma split, then lenient 2–4 word split
   │   ✓ → done
   │
   ├─ TIER 3 — comma form
   │   "PAULSON, COLE"  → exactly two comma parts, both name-like
   │   Middle name/initial dropped from the first-name side
   │   ✓ → done
   │
   └─ TIER 4 — prominence (the badge case)
       Every line of 2–3 name-like words, titles/credentials stripped,
       role/org/license vocabulary disqualified
       → tallest glyph height wins
       ✓ → done   ✗ → null (fields stay empty, chips carry the load)
```

### 6.3 Confidence vs autonomy

The stricter the rule, the more autonomy the result gets:

| Consumer | Rule strictness | What the result does |
|---|---|---|
| Tier 4 auto-guess | strict: 2–3 words, both ends ≥2 chars | Fills both fields on its own |
| Tier 2 label-vouched value | lenient: 2–4 words | Fills both fields, but a label already vouched for it |
| Suggestion chips | loosest: ≤4 words per line, each word ≥2 chars | User picks — a false positive costs one extra chip |

### 6.4 Word filtering — two different mechanisms

```
line: "DR COLE PAULSON RPH"
        │
        ├─ STRIPPED_TOKENS  ("DR", "RPH") → REMOVED from the line
        │
        └─ remaining ["COLE", "PAULSON"] → evaluated → valid name ✓


line: "MEDICAL CENTER"
        │
        └─ EXCLUDED_WORDS ("MEDICAL", "CENTER") → whole LINE disqualified ✗
```

Confusing these two is the most common porting mistake in the parser. Strip = drop the word, keep the line. Exclude = drop the line.

---

## 7. Recovery and resilience

### 7.1 Two independent watchdogs

```
┌────────────────── UI: frame stall watchdog ─────────────────┐
│  every 2 s: is (now − lastFrameAt) > 4 s ?                   │
│    and no sheet open, and session not locked                 │
│      → status = RESTARTING, rebind back camera               │
│      → reset lastFrameAt (full window before re-judging)     │
│  keeps retrying every interval until frames flow             │
│                                                              │
│  covers: bind failure, dead ImageAnalysis after a lens race, │
│          stalled pipeline                                    │
└──────────────────────────────────────────────────────────────┘

┌───────────── Analyzer: ML Kit timeout watchdog ─────────────┐
│  armed per frame, fires at 2.5 s                             │
│    if this frame's token is still current AND gate held      │
│      → force-release the gate                                │
│                                                              │
│  covers: a recogniser callback that never arrives            │
└──────────────────────────────────────────────────────────────┘
```

Neither substitutes for the other. Frames can flow while the gate is latched (analyzer watchdog needed). The gate can be free while no frames arrive at all (frame watchdog needed).

### 7.2 The frame token

Prevents a stale, slow frame from sabotaging a newer one:

```
frame A: token=5, gate acquired, watchdog armed
frame A stalls in the recogniser
watchdog fires → gate released
frame B: token=6, gate acquired, watchdog armed
frame A's callback FINALLY arrives → finishFrame(token=5)
        │
        └─ frameToken.get() == 6 ≠ 5
              → recycle A's bitmap ONLY
              → do NOT release the gate (B holds it)
              → do NOT cancel the watchdog (it is B's)
```

Without the token check, frame A's late completion frees frame B's gate and cancels frame B's watchdog — and if B's own callback is then dropped, the gate is unrecoverable.

### 7.3 Frame buffer lifecycle

Every frame must be closed exactly once, on every path:

```
CameraHelper.processImageProxy
   ├─ not streaming            → close
   ├─ channel closed for send  → close
   ├─ trySend failed           → close
   ├─ throwable               → close
   └─ conflated buffer overwrote it before the collector read it
                               → close (onUndeliveredElement)

Screen frame collector
   └─ try { analyzer.analyze(proxy) { … } } finally { proxy.close() }

Analyzer
   └─ bitmap.recycle() in finishFrame, on every exit path
```

Skipping any of these exhausts the small `KEEP_ONLY_LATEST` buffer pool and the stream stalls permanently — or, for bitmaps, OOMs within seconds at 2.5 analysed frames/sec.

### 7.4 Camera pause/resume triggers

| Trigger | Camera | Analyzer | Sheet | Status |
|---|---|---|---|---|
| Detection fires | `pauseCamera()` (full unbind) | self-paused | opens | PAUSED |
| "Enter Manually" tapped | `pauseCamera()` | `pause()` | opens (cleared) | PAUSED |
| Sheet dismissed | rebind back camera | `resume()` | closes | SCANNING |
| Session locks | `pauseCamera()` | `pause()` | force-closed | PAUSED |
| Session unlocks | rebind back camera | `resume()` | stays closed | SCANNING |
| Frames stale 4 s | rebind back camera | untouched | — | RESTARTING |
| Screen leaves | (lifecycle unbind) | `close()` | — | — |

`resume()` clears both candidate buffers, so a stale candidate from before the pause cannot pair with the first frame after it and fire a false confirmation.

### 7.5 Session lock interplay (app-specific pattern)

This app has an idle session lock that draws an overlay in the **activity** window. A modal bottom sheet lives in its **own dialog window, above** the activity window.

```
   normal:      [ activity: preview + card ]
                [ sheet window: name sheet ]   ← on top

   lock engages while sheet is open:
                [ activity: lock overlay ]
                [ sheet window: name sheet ]   ← STILL on top — lock defeated
```

So the lock handler must dismiss the sheet, not merely draw over it. It also pauses the camera and analyzer (no point burning battery behind a lock screen).

On unlock, an explicit rebind is required: the lock overlay runs its own face-verify camera bind, and `bindToLifecycle` internally calls `unbindAll()` — which killed this screen's use cases. Without the rebind the preview stays dead forever.

**Generalisation for ports:** any modal system overlay that renders in a lower window than your result sheet needs the same dismiss-then-rebind handling.

---

## 8. Operator interaction detail — the result sheet

### 8.1 What the sheet shows, by result kind

| Result | First/Last fields | Chips | Header |
|---|---|---|---|
| PDF417 hit | prefilled | none | — |
| OCR name parsed | prefilled | shown | "First Name Suggestions" |
| OCR suggestions only | empty | shown | "First Name Suggestions" |
| Manual entry | empty | none | — |

### 8.2 The chip repair loop

The common OCR failure is not "unreadable" — it is **wrong pairing**: the parser picked two words that are both on the card but belong to different fields, or picked the org name. Chips make that a two-tap fix.

```
   chips: [ Cole ] [ Paulson ] [ Alan ]
   header: "First Name Suggestions"      activeField = FIRST
   First Name  [                    ]  ← highlighted border
   Last Name   [                    ]

   ── tap "Cole" ──────────────────────────────────────────

   header: "Last Name Suggestions"       activeField = LAST
   First Name  [ Cole               ]
   Last Name   [                    ]  ← highlighted border

   ── tap "Paulson" ───────────────────────────────────────

   header: "Last Name Suggestions"       activeField = LAST (stays)
   First Name  [ Cole               ]
   Last Name   [ Paulson            ]  ← still highlighted
                                          (further taps overwrite it)

   CONTINUE now enabled
```

Rules that make this work without confusion:

- **Auto-advance FIRST → LAST on the first tap.** Two taps is the whole repair.
- **`activeField` stays on LAST after the second tap**, so a mis-tap is fixed by tapping the right chip again rather than by clearing a field.
- **A chip tap clears focus and hides the keyboard.** Chips are "pick", not "type" — focusing a field to receive the word would summon the keyboard, and hiding it afterwards is racy.
- **The highlight uses only the unfocused colours**, so it is visible exactly when no cursor exists — precisely the chip-tap mode.
- **Tapping a field directly** claims `activeField` and opens the keyboard, as normal.

Invariant: *whenever a cursor exists, it is in the highlighted field.* The two writers of `activeField` (focus change, chip tap) can never disagree, because a chip tap removes the cursor entirely.

### 8.3 Submission gate

Both the CONTINUE button and the keyboard's Done action require **both** names non-blank. Nothing advances on a half-filled name.

### 8.4 Dismissing the sheet

Swiping the sheet away is a deliberate "let me rescan": the camera rebinds, the analyzer resumes with cleared candidates, and the status returns to SCANNING. Anything the operator typed stays in the host's state, so a rescan that fires again simply overwrites it.

---

## 9. Privacy flow

```
   PDF417 payload actually contains:
     DCS  family name      ──────► READ  → lastName
     DAC  first name       ──────► READ  → firstName
     DAD  middle name      ──┐
     DBB  date of birth      │
     DAG/DAI/DAJ  address    ├────► NEVER READ, discarded with the frame
     DAQ  license number     │
     DBA  expiry, DBC sex, …─┘

   OCR text:
     every recognised line ──► parser ──► name + name-like words only
     everything else discarded with the frame

   Frames:
     bitmap snapshot ──► recogniser ──► recycle()
     NEVER written to disk

   Persisted:
     face_profiles.firstName    ← from the scan
     face_profiles.lastName     ← from the scan
     face_profiles.email        ← session snapshot, not from the ID
     face_embeddings            ← from the FACE step, not the ID step
     faceImagePath              ← FRONT-angle FACE image, not the ID image
```

The schema has no DOB column, no ID-number column, and no ID-image path. **The narrow scope is enforced by the data model, not just by discipline in the code.** Preserve that property when porting: if a column does not exist, a future change cannot quietly start filling it.

---

## 10. Timing budget

| Stage | Typical | Notes |
|---|---|---|
| Frame arrival interval | 33–66 ms | camera at 15–30 fps |
| Analysis throttle | 400 ms | ~2.5 analysed frames/sec |
| Frame → bitmap snapshot | 30–80 ms | synchronous, off the UI thread |
| PDF417 decode | 20–60 ms | fast, runs first |
| OCR (full frame) | 150–400 ms | mid-range device |
| Frame watchdog poll | 2 s | — |
| Frame stall threshold | 4 s | — |
| Analyzer timeout | 2.5 s | ≥3× p99 of decode+OCR chained |
| Autofocus re-trigger | 1.5 s | AF lock auto-cancels at 2 s |
| **PDF417 hit, end to end** | **~0.3–0.5 s** | single frame |
| **OCR hit, end to end** | **~1.0–1.5 s** | two agreeing frames + throttle |

The OCR path's extra ~500 ms is the price of the two-frame confirmation. It is worth it: a wrong name shown once and then silently corrected erodes trust in the whole scan far more than half a second of waiting.

---

## 11. Integration order for a port

Build in this order — each phase is verifiable before the next begins.

```
   1. PARSER  (pure, no device)
      unit tests only · badge case, license case, address guard,
      label variants, comma form, titles, chips
      ── must be fully green before anything else ──
                    │
   2. ANALYZER  (fake recogniser interface)
      throttle · single-flight gate · frame token · watchdog ·
      two-frame confirmation · all six gate-release paths
                    │
   3. CAMERA
      back lens · latest-frame-only · correct orientation ·
      conflated channel that closes dropped frames ·
      periodic autofocus · full-unbind pause · single rebind entry point
                    │
   4. SCAN UI
      preview + guide + status pill · off-UI-thread collection ·
      frame stall watchdog · result sheet · chips + activeField ·
      manual entry · dismiss-resume · dispose analyzer
                    │
   5. FLOW + PERSISTENCE
      host owns the name in death-surviving state · re-seed after
      process death · advance to face capture · ONE transaction for
      profile + credentials · double-submit guard · reset on "add user"
                    │
   6. PLATFORM
      camera permission (add a per-screen gate) · obfuscation keep
      rules · orientation lock · localisation · privacy audit
```

Phase 1 is where the accuracy lives and it needs no hardware. Phase 2 is where the reliability lives — every "scanning silently stopped working" bug traces back to a gate-release path missed here. Phases 3–4 are platform plumbing. Phase 5 is where a missed transaction produces an unauthenticatable user.

---

## 12. Verification scenarios

Run these on-device before calling a port complete.

### Happy paths
1. Back of a US driver's license → name fills in under ~0.5 s, no chips.
2. Front of a driver's license → name fills after ~1–1.5 s, chips present.
3. Staff badge with org + role text → person's name wins, org/role ignored.
4. "Enter Manually" → empty sheet, no chips, typing works, CONTINUE gates on both fields.

### Correction paths
5. OCR pairs the wrong words → two chip taps fix it; keyboard never appears.
6. Tap a field directly → keyboard appears, `activeField` follows the focus.
7. Chip header text tracks `activeField` and is localised.

### Resilience
8. Swipe the sheet away → status returns to SCANNING, a new scan fires.
9. Cover the camera / force a bind failure → status shows RESTARTING, recovers when unblocked.
10. Leave the screen mid-scan and return → no crash, no leaked thread, scanning works.
11. Rotate the device on a tablet → preview stays correctly oriented.
12. Enable "Don't keep activities", enrol a name, background the app during face capture, return → the persisted name is **not** blank.
13. Double-tap the final Continue in face capture → exactly one profile row.

### Privacy
14. Scan a license, then inspect the database → no DOB, no license number, no address anywhere.
15. Inspect app storage after several scans → no ID images written.
16. Inspect logs → no name-adjacent PII beyond what the app already logs deliberately.

---

## 13. Quick cross-reference

| Question | Where to look |
|---|---|
| Data shapes to port first | Implementation §3 |
| Analyzer full source | Implementation §4.3 |
| Tuning constants and rationale | Implementation §4.2 |
| AAMVA element codes | Implementation §4.4(g) |
| Parser full source | Implementation §5.4 |
| Vocabulary tables | Implementation §5.2 |
| Test matrix | Implementation §5.7 |
| Camera configuration | Implementation §6.3 |
| Chip/`activeField` rules | Implementation §7.10, this doc §8.2 |
| Process-death re-seed | Implementation §8.1, this doc §5.4 |
| Schema and transaction | Implementation §9 |
| Port checklist | Implementation §11 |
| Failure-mode table | Implementation §12 |
| Runtime flow, diagrams | this doc §3–§7 |
| Timing budget | this doc §10 |
| On-device verification | this doc §12 |
