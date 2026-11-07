# Today day browsing — build 14

Tap the Today/date title to choose any past date. The seven-day strip has meal-presence dots, previous/next seven-day navigation and a Return to Today button. Future dates are unavailable.

All dashboard values derive from the selected date: meal filters, totals, macro pie, contributors, warnings, summaries and sticky glance. Training-day targets are resolved from that date’s persisted training flag. Historical targets are not snapshotted in the existing schema, so past comparisons are labelled as using the current configured targets. Historical browsing does not alter today’s training setting, capture date, widget totals, or records.

Returning to Today clears the pinned historical date, allowing the existing clock refresh to follow midnight. Empty historical days show a factual no-records state rather than a prompt to log today’s food. The chart resets its selected macro when the day changes. Reduced Motion is respected.

Regression checks cover Jakarta midnight boundaries, portion totals, and date-specific rest/training target resolution. Mac UI checks exercise the calendar and returning to Today; device build/version checks are recorded separately in the delivery outputs.
