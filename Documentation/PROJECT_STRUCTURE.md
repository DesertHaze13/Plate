# Project structure

One Xcode project contains a universal iPhone/iPad application, a separate native Mac application, and an embedded widget extension for each platform. There is no Catalyst target or watch target, matching the requested platform scope.

- `Sources/iOS/App` and `Sources/macOS/App`: platform entry points; Mac adds menu-bar presentation.
- `Sources/Shared/Domain`: the independent PlateCore package, persisted value models, nutrition/goal math, label/serving parsing, guidance states and widget snapshots.
- `Sources/Shared/Services`: observable state and view models, Vision input detection, on-device/cloud recognition protocol, image encoding/cache/outbox, Firebase authentication/sync, Health and notifications.
- `Sources/Shared/Features`: adaptive root navigation, Today, capture/review/item editing, history/charts/foods and onboarding/settings.
- `Sources/Shared/Features/DesignSystem.swift`: shared glass cards, rings, mesh background, scan and image components.
- `Sources/Widgets`: timeline widgets and the iOS capture control.
- `Resources`: platform entitlements/configurations, URL schemes, extension Info.plist and layered Icon Composer asset.
- `Firebase`: owner-only rules, optional Storage rules and optional daily-total function.
- `Tests/PlateCoreTests`: domain and parsing/warning tests.
- `Tests/PlateCaptureTests`: real OCR pipeline and invalid-image integration tests.
- `Tools/generate_project.py`: deterministic target and navigator generation.

The on-device Foundation Models and Firebase AI paths share DetectedMeal/DetectedFood typed generated/Codable output, converted into the same shared MealAnalysis domain structure. The local package executable deliberately excludes Firebase so the interface and Vision flow can be tested offline.
