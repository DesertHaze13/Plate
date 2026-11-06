# Calorie and macro target warnings

Build 10 adds independent checks for calories, protein, carbohydrates and fat.

- A short alert near the top of Today identifies targets that are almost full, met, or over.
- Each macro tile displays its own status.
- The target check-in shows eaten/target values and the amount remaining or exceeded for all four targets.
- Meal review shows projected totals before saving, using the selected day’s existing meals and training/rest targets. Unconfirmed food values are excluded from the projection until the review is valid.
- Warning feedback occurs when a target changes into a warning state; completed targets receive success feedback when no warning takes priority. No repeated modal alerts are shown.

The warning threshold uses the existing editable fraction (85% by default). Macros are met at exactly 100% and are over when above their target. Calories retain the configured on-target tolerance. Zero or invalid targets are marked unset rather than falsely completed.

These are comparisons with the user's configured goals. They do not alter food data or targets, and historical dates use the current goal configuration for the selected training/rest day.

Verification: 30 tests passed, including independent macro states, threshold edges, calorie tolerance, unset values, and projected totals. Signed native Mac and universal iOS Release builds passed. The Mac dashboard and unsaved meal-review projections were exercised without saving test food.
