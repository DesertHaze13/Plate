# Interactive nutrition pie explorer

Available on Today and Progress in build 11.

- Switch between Macros and Food categories.
- Tap/click or drag over a slice to highlight it. Category rows provide the same selection for keyboard and accessibility users.
- Inspect percentage, energy contribution and (for macros) grams and target status.
- See the foods contributing to a slice, ordered by energy contribution. Open a food row to inspect its original meal.
- Reset to all slices or reveal the full contributor list.
- Progress uses the selected week/month, with explicit period totals and daily averages over logged days. Today uses today's meals and effective training/rest targets.
- Empty datasets do not fabricate slices. Zero-energy macros remain inspectable through their category rows.

Macro slice sizes use protein × 4, carbohydrate × 4 and fat × 9 kcal. Food categories use each item's logged calories and portion quantity. These are separate views; categories and macros are not added together. Label energy can differ from 4/4/9-derived energy, which is stated in the interface.

Verification: 34 tests passed, including macro energy, cumulative sector selection boundaries, zero/invalid data and portion-aware food-category aggregation. Native Mac and universal iOS Release builds passed. Mac category selection, macro detail, food-category switching, contributor-to-meal drill-down, empty-day state and period labels were exercised without modifying meal data.
