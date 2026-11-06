import test from 'node:test';
import assert from 'node:assert/strict';
import { summarize } from './totals.js';
const meal = { items: [{ quantity: 2, nutrients: { calories: 130, protein: 3 } }] };
test('servings scale all nutrients', () => { assert.equal(summarize([meal]).calories, 260); assert.equal(summarize([meal]).protein, 6); });
test('recomputation is idempotent and deletion clears totals', () => { assert.deepEqual(summarize([meal]), summarize([meal])); assert.equal(summarize([]).calories, 0); });
test('invalid quantities are rejected', () => { assert.throws(() => summarize([{ items: [{ quantity: -1 }] }])); });
