# Plate

A native SwiftUI food and nutrition tracker for iPhone, iPad, and Mac.

Plate combines photo capture, nutrition-label OCR, editable meal reviews, and daily calorie and macro tracking. Its interface includes native Liquid Glass tab navigation, dimensional illustrations, a circular interactive energy hero with macro details, switchable nutrition stories, a custom calendar, charts, and adaptive layouts for each platform.

## Features

- Food photos, nutrition labels, barcode matching, image imports, and manual entry.
- On-device Vision OCR, English and Indonesian label parsing, serving-size calculations, and optional AI recognition.
- Review and edit every food item before logging it.
- Daily calorie, protein, carbohydrate, and fat targets, with optional training-day targets. Independent almost-full/met/over warnings show what remains, including projected totals before saving a meal.
- Meal history, saved foods, repeat meals, weight tracking, and progress charts.
- Google sign-in and private Firestore synchronization, with offline caches and a photo-upload outbox.
- Optional Apple Health integration, widgets, capture control, Siri shortcuts, and a Mac menu-bar glance.
- Light/dark appearance, reduced-motion support, and accessible control descriptions.

## Requirements

- Xcode 27 beta, Swift 6.
- iOS/iPadOS 26 or later; macOS 26 or later.
- Firebase Apple SDK 12.0.0 and Google Sign-In 8.0.0, resolved through Swift Package Manager.

Xcode 27 is needed for the guarded Foundation Models image APIs. Their runtime use depends on OS and model capabilities; Vision and manual entry provide other capture paths.

## Build

1. Clone the repository and open `Plate.xcodeproj`.
2. Copy `Resources/Common/Info.example.plist` to `Resources/Common/Info.plist`.
3. Configure your own Firebase Apple app(s). Add their `GoogleService-Info.plist` files to `Resources/iOS/` and `Resources/macOS/`. These files are deliberately excluded from Git.
4. Replace the example Google callback scheme in `Resources/Common/Info.plist` with `REVERSED_CLIENT_ID` from your Firebase configuration. Enable Google sign-in in Firebase Authentication.
5. Select your own Apple signing team for the app and widget targets. Configure compatible bundle identifiers and entitlements if changing the defaults.
6. Select `Plate` for iPhone/iPad or `PlateMac` for native Mac, then build and run.

The default bundle identifier is `com.dony.plate`; widgets use `com.dony.plate.widgets`. Personal signing configuration and service setup must be adapted for your own installation.

## Backend setup

Create a Firestore database and deploy `Firebase/firestore.rules` to your own Firebase project. The rules restrict user documents and photos to their owner. The default photo path stores compressed JPEG bytes in Firestore documents, while displayed totals are calculated from meal snapshots.

For optional cloud recognition, configure Firebase AI Logic and a supported Gemini model. Development builds use App Check debug registration; register each development key privately. Debug keys must never be committed. Production attestation and enforcement require separate configuration and verification.

`Firebase/storage.rules` and `Firebase/functions/` provide an optional Cloud Storage and daily-total function path. Check your Firebase plan and billing requirements before deploying those services. The default Firestore photo and total paths do not require that optional deployment.

Firebase configuration, credentials, signing files, local user data, device backups, and built application archives are not included in this repository.

## Project layout

- `Sources/Shared/Domain`: nutrition models, label parsing, and calculations (`PlateCore`).
- `Sources/Shared/Features`: SwiftUI screens and design system.
- `Sources/Shared/Services`: recognition, persistence, sync, and platform services.
- `Sources/iOS/App`: universal iPhone/iPad entry point.
- `Sources/macOS/App`: native Mac entry point and menu-bar UI.
- `Sources/Widgets`: widgets and capture control.
- `Resources/Plate.icon`: editable layered Icon Composer asset.
- `Firebase`: rules and optional aggregation function.
- `Tests`: domain and capture checks.

See `Documentation/PROJECT_STRUCTURE.md` and `Documentation/DATA_MODEL.md` for implementation details.

## Checks

```sh
swift test --filter PlateCoreTests
node --test Firebase/functions/totals.test.js
```

The app targets can be built with the `Plate` and `PlateMac` Xcode schemes after configuring Firebase and signing. The latest interface update is version 1.0.0, build 10.

See [the UI comparison](Documentation/UI_COMPARISON.md) for the Current-inspired interaction update and the Google sign-in crash fix.

On iPhone, native system tabs provide the selection lens and touch tracking. On iOS 27, the camera uses the prominent tab role; Settings is accessible from the top toolbar. The custom simulated tab selector has been removed.

See [target warnings](Documentation/TARGET_WARNINGS.md) for thresholds, calorie tolerance, macro states, and meal-preview behavior.
