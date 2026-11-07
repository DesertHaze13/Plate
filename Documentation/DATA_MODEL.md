# Storage contract — version 1

Singletons use valid alternating Firestore paths: `users/{uid}/profile/current`, `goals/current` and `settings/current`. Meals, saved foods and weights use UUID document IDs. Each document is accessible only to its authenticated owner. The photo collection is private to the same owner.

Nutrients are stored for a base serving; quantity scales the base without mutating it. Meals record the capture timezone and a local day key. Today's screen uses the device calendar. Historical day keys do not change when traveling. Server timestamps support last committed write wins for whole documents. Item arrays are saved as one unit.

On the free Spark plan, meal snapshots are authoritative for visible daily/history totals. The `days` cache is not written by clients and is not required. The optional future Cloud Function recomputes old and new days in transactions to support edits/deletes and duplicate event delivery. Its three aggregation unit tests pass; it is not deployed.

Local-only meals and each account use separate atomic JSON files under Application Support/Plate. Auth changes detach old snapshot listeners and clear the visible account state. Firestore also persists offline writes and cached documents. Snapshot metadata distinguishes local cache, pending uploads and server-acknowledged data. Profile/goals/settings/foods/weights use typed listeners; large account writes are split into batches below Firestore's limit.

Default photo references use `firestore://users/{uid}/photos/{mealID}` and a separate `-thumb` document. JPEG payloads are capped below Firestore's document size limit. The uploader persists pending work locally, checks that the meal still exists, and retries on reconnection/activation. Remote photo display uses a bounded memory cache; private reads are protected by the same owner rule. Repeat-meal actions create independent photo copies. The optional Storage adapter uses `users/{uid}/meals/{mealID}/photo.jpg` and `thumbnail.jpg`, with no public download-token URL.

Scanned or saved foods retain their serving basis, quantity, optional barcode and source. Label values stay authoritative. Missing required values are explicitly tracked until the user confirms them. Recognition estimates retain confidence and available normalized top-left image bounds.


## Cloud photos and storage policy

New meal photos are saved only for signed-in Firebase accounts. Signed-out meals retain nutrition, not a permanent local image. The camera capture path does not write to Apple Photos, and imported library originals are untouched.

Compressed full/thumbnail pairs use a durable upload outbox with a 20 MiB admission limit. They survive offline sessions and are deleted only after the server acknowledges both uploads. Queue failures leave the meal usable without a photo and surface a notice. Remote history images use a 12 MiB cost-limited memory cache, not permanent downloaded files. Firestore's separate persistent document cache uses a 100 MiB default garbage-collection target (a soft target, not a hard storage cap).

Existing remote-cache duplicates are reclaimed. Existing originals associated with cloud meals are deleted only after both remote images can be read; offline and local-only originals are retained. Firebase configuration and sign-in are required for actual cloud storage. No Google Drive credentials or new cloud project is created automatically.

## Excluding food from a photo

Detected-food overlays toggle item inclusion, and excluded rows are crossed out and omitted from saved nutrition. The photo editor supports 1–4× zoom, pan mode, normalized top-left rectangular exclusion areas, undo, and reset. Excluded pixels are filled opaquely before OCR or image AI sees the image. Reanalysis cannot use full-plate printed values, infer hidden foods, or scale nutrients by pixel area; the user reviews the new estimates. Image-capable AI or configured cloud recognition is required for spatial reanalysis; item exclusion and manual serving adjustments remain available without it.

## Calorie target and Apple Health

- `Profile.calorieCap` is an optional stored value with a 2,200 kcal default ceiling for missing or invalid values. `NutritionCalculator` never returns more, and `MealStore.effectiveTargets` also trims training-day targets to it (carbs first, then fat; protein is kept).
- Goal adjustments are relative to maintenance: lean bulk +10%, recomp −10%, cut −20%. `NutritionCalculator.breakdown(for:)` exposes each step for the Settings card.
- `Profile.measuredActiveKcal` (optional) replaces the activity multiplier with the 14-day average active energy from Apple Health: maintenance = resting burn + measured activity.
- `Nutrients.caffeine` is in milligrams. Older documents without it decode as 0. A typical estimate can be explicitly accepted in the food editor. Zero or unconfirmed caffeine is not automatically guessed for Health exports.
- Each logged food is written to Apple Health as an `HKCorrelation` of type `.food` named after the item, holding energy, macros, fiber, sugar and caffeine samples tagged with `PlateMealID`. Edits replace the meal's entries; deleting a meal removes them.
- Plate reads age, sex, height, weight, blood pressure, resting heart rate, workouts, and resting and active energy. Age, sex, height and weight fill the profile; targets follow unless they were edited by hand.


## Reviewed edits and appearance (build 19)

AI corrections produce an editable proposal before application. Replacing a logged food preserves unrelated foods and saves through the existing meal update and Health synchronization path. Reference images from Photos or Files are compressed in memory; image requests require a vision-capable model and do not silently become text-only estimates. Reference attachments do not replace the saved meal photo.

System/Light/Dark appearance is persisted per device. Daily overages are evaluated independently for calories, protein, carbohydrates, and fat against effective targets. Above-target panels show actual excess and percentage, without representing a medical diagnosis. Warning haptics trigger when a new metric exceeds its target; celebration effects are suppressed while over target.
