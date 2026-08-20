# Face Auth Debug Menu Rows

Approved 18-08-2026 18:42.

## Goal

Two DEBUG-only rows in the hamburger menu so face recognition can be exercised
on demand, without waiting for the inactivity timer:

- **Verify Face (Debug)** — opens `FaceAuthenticationView` as its own camera
  screen, identifies which enrolled user is in frame, shows the welcome name,
  and calls `FaceSessionManager.unlock(userId:userName:)` so the real unlock
  plumbing (session owner switch, `last_authenticated_at` write, idle timer
  arming) is exercised too. Repeatable — back out and tap again.
- **Lock Now (Debug)** — locks instantly and shows the session-locked screen.

No production code path changes. Both rows compile out of release builds.

## Decisions (from grilling)

| Question | Decision |
|---|---|
| Ship or debug-only? | `#if DEBUG` only. No L10n strings, no design sign-off, no PMS gating. |
| Verify row destination? | Own camera screen (`FaceAuthenticationView`), **and** calls real `unlock(...)` on success. Not the lock overlay. |
| No enrolled users? | Toast `"No enrolled users"` via `ToastManager.shared.show`, DEBUG-only literal. Both rows. |
| Lock Now + nav stack? | Leave nav stack alone. Overlay lives at app root and covers the menu; on unlock you land back in the menu, which proves resume-in-place. |
| "Idle for 0 sec" subtitle on instant lock | Accepted. Cosmetic, DEBUG-only. |

### Why a `fullScreenCover`, not a new route

`HamburgerMenuFLow` is `Hashable, Codable` and feeds a persisted navigation
path. Adding a `#if DEBUG` case to a `Codable` enum means a release build could
in principle fail to decode a path a debug build wrote. Presenting
`FaceAuthenticationView` as a `#if DEBUG` `.fullScreenCover` from
`HamburgerMenuView` avoids touching `AppNavigation` and the `Codable` surface
entirely.

`FaceAuthenticationView` dismisses via `@Environment(\.dismiss)` and locks
orientation in `onAppear` / unlocks in `onDisappear` — both behave correctly
inside a `fullScreenCover`.

## Changes

### 1. `Core/Constants/Enums/Enums.swift` — `HamburgerMenuItem`

- Add, under `#if DEBUG`, cases `DebugVerifyFace` and `DebugLockNow`, placed
  after `.QuickAccessUsers` and before `.Logout`.
- `title`: hardcoded `"⚙︎ Verify Face (Debug)"` / `"⚙︎ Lock Now (Debug)"`.
  No `L10n` entries — debug scaffolding is not localized.
- `iconName`: reuse existing assets `"profile_icon"` / `"logout_icon"`. No new
  assets.
- Both the `title` and `iconName` switches get the new cases wrapped in
  `#if DEBUG` so the release build's switches stay exhaustive.
- `allCases` picks the rows up automatically through `CaseIterable` synthesis
  under the flag — the menu needs no separate list change.

### 2. `Features/Settings/View/HamburgerMenuView.swift`

- New `#if DEBUG` state: `@State private var showDebugFaceVerify = false`.
- `#if DEBUG` `.fullScreenCover(isPresented: $showDebugFaceVerify)` presenting:

  ```swift
  FaceAuthenticationView { userId, userName in
      Log("DEBUG VerifyFace: matched \(userName) (\(userId))")
      FaceSessionManager.shared.unlock(userId: userId, userName: userName)
  }
  .environmentObject(appColors)
  ```

  The welcome name comes from the view's own `.authenticated` state; the user
  taps Continue to dismiss.

- `handleMenuSelection` gains, under `#if DEBUG`:
  - `.DebugVerifyFace` — guard `FaceSessionManager.shared.hasEnrolledUsers`,
    else toast `"No enrolled users"`; then `showDebugFaceVerify = true`.
  - `.DebugLockNow` — same guard/toast; then
    `FaceSessionManager.shared.lockDueToInactivity()`. Nav stack untouched.
- `isItemDisabled` is untouched — debug rows are never PMS-gated.

### 3. Nothing else

No `AppNavigation` change. No `HamburgerMenuFLow` change. No `L10n` strings.
No new assets. No tests — this is DEBUG-only scaffolding with no logic to
cover.

## Files touched

- `PillCounter/PillCounter/Core/Constants/Enums/Enums.swift`
- `PillCounter/PillCounter/Features/Settings/View/HamburgerMenuView.swift`

## How to use it

**Verify Face (Debug)** — camera opens, scan runs the same per-frame pipeline
as the lock screen. Xcode console shows, per attempt:

```
Authentication: loaded N registered user(s), M total embeddings
Repository: user <id> (<name>) has K stored embedding row(s)
DEBUG allScores (sorted): [you=0.612, other=0.221]
DEBUG gate: threshold=0.38 thresholdPass=true marginRequired=0.03 marginActual=0.391 marginPass=true
Authentication: SUCCESS for user <id>
DEBUG VerifyFace: matched <name> (<id>)
```

Reading the output:

- `loaded 0` — not enrolled, or user row is inactive (identify uses
  `activeOnly: true`).
- `0/K embeddings unpacked` / `nil-empty payload` — decrypt failure (KEK/DEK);
  enrollment stored rows but they are unreadable.
- own score below `0.38` — threshold, quality, or lighting problem.
- own score high but `marginPass=false` — two enrolled faces too similar.
- wrong name at the top of `allScores` — genuine misidentification.

**Lock Now (Debug)** — session-locked screen appears immediately, subtitle
reads "Idle for 0 sec". Scan to unlock; you land back in the hamburger menu.
