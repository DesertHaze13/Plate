export const fields = ['calories', 'protein', 'carbs', 'fat', 'fiber', 'sugar'];
export function summarize(meals) {
  const totals = Object.fromEntries(fields.map(key => [key, 0]));
  for (const meal of meals) {
    for (const item of meal.items ?? []) {
      const quantity = item.quantity;
      if (!Number.isFinite(quantity) || quantity <= 0) throw new Error('Invalid serving quantity');
      for (const key of fields) {
        const value = item.nutrients?.[key] ?? 0;
        if (!Number.isFinite(value) || value < 0) throw new Error('Invalid nutrient');
        totals[key] += value * quantity;
      }
    }
  }
  return totals;
}
