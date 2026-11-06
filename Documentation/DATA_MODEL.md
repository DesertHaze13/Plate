# Storage contract — version 1

Singletons use valid alternating Firestore paths: `users/{uid}/profile/current`, `goals/current` and `settings/current`. Meals, saved foods and weights use UUID document IDs. Each document is accessible only to its authenticated owner. The photo collection is private to the same owner.

Nutrients are stored for a base serving; quantity scales the base without mutating it. Meals record the capture timezone and a local day key. Today's screen uses the device calendar. Historical day keys do not change when traveling. Server timestamps support last committed write wins for whole documents. Item arrays are saved as one unit.

On the free Spark plan, meal snapshots are authoritative for visible daily/history totals. The `days` cache is not written by clients and is not required. The optional future Cloud Function recomputes old and new days in transactions to support edits/deletes and duplicate event delivery. Its three aggregation unit tests pass; it is not deployed.

Local-only meals and each account use separate atomic JSON files under Application Support/Plate. Auth changes detach old snapshot listeners and clear the visible account state. Firestore also persists offline writes and cached documents. Snapshot metadata distinguishes local cache, pending uploads and server-acknowledged data. Profile/goals/settings/foods/weights use typed listeners; large account writes are split into batches below Firestore's limit.

Default photo references use `firestore://users/{uid}/photos/{mealID}` and a separate `-thumb` document. JPEG payloads are capped below Firestore's document size limit. The uploader persists pending work locally, checks that the meal still exists, and retries on reconnection/activation. Photos are cached locally and private reads are protected by the same owner rule. Repeat-meal actions create independent photo copies. The optional Storage adapter uses `users/{uid}/meals/{mealID}/photo.jpg` and `thumbnail.jpg`, with no public download-token URL.

Scanned or saved foods retain their serving basis, quantity, optional barcode and source. Label values stay authoritative. Missing required values are explicitly tracked until the user confirms them. Recognition estimates retain confidence and available normalized top-left image bounds.
