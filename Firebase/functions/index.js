import { initializeApp } from 'firebase-admin/app';
import { getFirestore, FieldValue } from 'firebase-admin/firestore';
import { onDocumentWritten } from 'firebase-functions/v2/firestore';
import { summarize } from './totals.js';
initializeApp();
const db = getFirestore();
// Recompute inside a transaction: retries, duplicate delivery and concurrent devices
// cannot double-count. A date edit recomputes BOTH affected days.
export const recalculateDay = onDocumentWritten({ document: 'users/{uid}/meals/{mealID}', retry: true }, async event => {
  const keys = new Set([event.data?.before.data()?.dayKey, event.data?.after.data()?.dayKey].filter(Boolean));
  const root = db.collection('users').doc(event.params.uid);
  for (const key of keys) {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) throw new Error('Invalid day key');
    await db.runTransaction(async transaction => {
      const meals = await transaction.get(root.collection('meals').where('dayKey', '==', key));
      transaction.set(root.collection('days').doc(key), {
        dayKey: key, totals: summarize(meals.docs.map(doc => doc.data())),
        mealCount: meals.size, updatedAt: FieldValue.serverTimestamp()
      });
    });
  }
});
