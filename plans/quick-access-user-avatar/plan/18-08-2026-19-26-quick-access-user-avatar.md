# Quick Access User Avatar

Capture the enrolling user's frontal face frame, store it as a JPEG in the app
container, persist its filename (encrypted) on `FaceUserEntity`, and render it as
a 64x64 thumbnail in the Quick Access Users row.

## Decisions (from grilling)

| Question | Decision |
|---|---|
| Which frame becomes the avatar | The frontal/center pose step's captured candidate |
| Where stored | JPEG in `Application Support/FaceAvatars/{userId}.jpg` (container -> dies on uninstall) |
| What Core Data holds | New optional `photo_path` String = **relative filename only** |
| Encryption | `photo_path` joins `encryptedFieldRegistry`, same as `PillCountTransactionDetailsEntity.image_path` |
| Existing users | Lightweight automatic migration, nil path, placeholder fallback in row. No backfill |
| Delete | Row delete also deletes the JPEG; `deleteAll` clears the directory |
| Enrollment rollback | JPEG written only after embeddings persist successfully |
| Row visual | 64x64, cornerRadius 8, `scaledToFill().clipped()`; row height (84pt) and toggle unchanged |

## Steps

### 1. Core Data model

`PillCounter/PillCounter/PillCounter.xcdatamodeld/PillCounter.xcdatamodel/contents`

Add to `FaceUserEntity`:

```xml
<attribute name="photo_path" optional="YES" attributeType="String"/>
```

Optional attribute -> lightweight migration is automatic; existing rows get nil.

### 2. Encryption registry

`Core/Utils/Helpers/NsManagedObject+Encryption.swift`

Add to `encryptedFieldRegistry`:

```swift
"FaceUserEntity": ["photo_path"],
```

### 3. FaceUserStore

`Core/LocalDataSource/FaceUserStore.swift`

- `getUser` / `getAllUsers` must call `decryptEncryptedFieldsInPlace()` on fetch
  results (mirrors `UserStore`) — otherwise `photo_path` surfaces as ciphertext,
  since a refaulted object can return the `willSave` ciphertext snapshot.
- New `setPhotoPath(id:filename:)`, stamping `updated_at`.
- `deleteUser` returns/exposes the photo filename so the caller can delete the
  file, or performs the file delete itself via `FaceAvatarStore`.
- `deleteAll` also calls `FaceAvatarStore.shared.deleteAll()`.

### 4. FaceAvatarStore (new)

`Core/LocalDataSource/FaceAvatarStore.swift` — singleton, matching sibling DAO style.

- Directory: `Application Support/FaceAvatars/`, created lazily.
- `isExcludedFromBackup = true`; file protection
  `.completeUntilFirstUserAuthentication` so rows can render without unlock races.
- `save(userId:image:) -> String?` — JPEG quality 0.8, returns the filename.
- `loadImage(filename:) -> UIImage?`
- `delete(filename:)`
- `deleteAll()`

### 5. Enrollment capture

`Features/FaceAuth/Presentation/ViewModel/FaceEnrollmentViewModel.swift`

- New `private nonisolated(unsafe) var frontalAvatar: UIImage?`.
- In `captureStep`, when the current step is the frontal/center pose: convert the
  candidate `pixelBuffer` to a `UIImage`, crop to the detection box plus 40%
  padding, downscale to 256x256, retain.
- In `finishEnrollment`, **after** `saveEnrollmentEmbeddings` returns true:
  `FaceAvatarStore.save` then `FaceUserStore.setPhotoPath`. On embeddings
  failure, nothing is written. A photo-save failure does NOT fail enrollment —
  the row falls back to the placeholder.
- `cancelEnrollment()`, `retry()`, `prepareForNextUser()` clear `frontalAvatar`.

### 6. Delete cleanup

`Features/FaceAuth/Data/FaceRecognitionRepository.swift`

- `deleteUser` reads the user's `photo_path` before deleting the row, then deletes
  the file.
- `QuickAccessUsersView.deleteSelected` currently calls the two stores directly,
  bypassing the repository — route it through `FaceRecognitionRepository.deleteUser`
  so avatar cleanup cannot be forgotten.

### 7. Row UI

`Features/FaceAuth/Presentation/View/QuickAccessUsersView.swift`

- `Row` gains `image: UIImage?`, loaded in `reload()` from `photo_path`.
- Leading thumbnail: 64x64, `.scaledToFill().frame(64,64).clipped().cornerRadius(8)`.
- Fallback: `Image(systemName: "person.crop.circle.fill")` at
  `appColors.text.opacity(0.3)`, same 64x64 frame.
- Existing HStack spacing (16), row `minHeight` 84, and toggle placement unchanged.

### 8. Tests

`PillCounterTests/` — Swift Testing, protocol mocks, run with
`-parallel-testing-enabled NO`.

- `FaceAvatarStore`: save/load/delete round-trip; `deleteAll`; loading a missing
  file returns nil.
- `FaceUserStore.setPhotoPath`: encrypted round-trip returns plaintext after fetch.
- Existing enrollment tests stay green.

## Files touched

New: `Core/LocalDataSource/FaceAvatarStore.swift` and its test file.

Edited:
- `PillCounter.xcdatamodeld/PillCounter.xcdatamodel/contents`
- `Core/Utils/Helpers/NsManagedObject+Encryption.swift`
- `Core/LocalDataSource/FaceUserStore.swift`
- `Features/FaceAuth/Presentation/ViewModel/FaceEnrollmentViewModel.swift`
- `Features/FaceAuth/Data/FaceRecognitionRepository.swift`
- `Features/FaceAuth/Presentation/View/QuickAccessUsersView.swift`
