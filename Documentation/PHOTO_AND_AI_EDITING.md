# Photo + description and per-food AI — build 16

## Capture

Attach a photo, type a description, or use both. Choosing an image prepares it locally; analysis starts only when the user presses Analyze. Descriptions can clarify Indonesian names, ingredients, cooking method and portion size. Results list foods, base servings, quantities and editable nutrition before logging. Replacing a photo clears the prior draft. Changing the description after a result disables saving until re-analysis.

Printed nutrition values remain authoritative. When context supplies an eaten amount, AI interprets the number of base servings; the parser restores printed nutrients. A synthetic in-app image test read a 400 kcal / 100 g label with “I ate 60 g” as 0.6 servings, totaling 240 kcal. A subsequent single-food AI edit to 30 g returned a clearly labelled Flash Lite fallback proposal of 0.3 servings / 120 kcal. Applying updated only the draft; cancelling capture left the stored daily total and meal count unchanged.

## Single-food correction

Every food in a logged meal has Edit with AI, also available inside its manual editor. New draft foods expose the same action. The sheet accepts a correction, optional new photo, or the existing meal/draft photo when available. It requests exactly one corrected food and shows the before/after totals before Apply.

The selected food ID and bounds are retained. Other foods, meal ID and timestamp are not touched. Applying changes the local review draft; Save in the logged-meal screen commits it. Cancel leaves the stored record intact. Missing nutrition, uncertain identity and unconfirmed label portions must be reviewed before saving. AI model metadata is an optional backwards-compatible food field.

## Latency and provider limits

The tested default remains full `gemini-3.5-flash`, with temperature 0.15 and a 512-token thinking budget, reduced from 2048. Unnecessary image classification and saliency passes were removed from the cloud path. One original OCR/serving pipeline regression completes in under one second on the test Mac after assets are warm; this is not a cloud latency guarantee.

A true 30-second deadline covers App Check, account-token preparation and generation. Cancellation and late callback protection are tested. Cloud failure never silently launches a second lengthy on-device generation. Cloud opt-out remains respected. Metadata-only stage diagnostics contain no photo, prompt, token or account identifier.

During verification, the provider reported an HTTP 429 daily free-tier limit of 20 requests for its full Flash route. This is the observed project/model response, not a universal limit. Newer Flash variants were tested but were unavailable or overloaded, so they are not the default. A synthetic Indonesian correction succeeded through full Flash in 6.741 seconds before quota exhaustion.

An optional free `gemini-3.5-flash-lite` fallback is attempted only after provider quota/capacity responses (429/503). It never bypasses authentication or verification. Fallback results are explicitly labelled, including in the review before Apply; users may disable it in Settings. Both models produce estimates that require review. No billing or project security setting is changed.

## Interaction design

Original avocado, sunny egg and crunchy-food characters float, react to taps, emit brief bursts, and can be dragged with spring return. A shuffle control swaps the characters. A moving type strip, animated figures and selectable macro ring add motion. Decorative motion follows Reduce Motion; the narrow layout scales the character group to fit capture sheets and iPhone widths.

## Verification

Regression coverage includes serving math, selected-day behavior, identity-preserving single-food revisions, legacy data decoding, optional fallback routing, non-bypass of verification errors, timeout, cancellation, printed-label OCR and invalid inputs. Runtime UI tests use synthetic foods/images and cancel without logging test entries. Current installed versions and archive checks are recorded in the private delivery outputs.
