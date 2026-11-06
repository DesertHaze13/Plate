# Food photo recognition — build 13

The old path returned a sufficiently confident on-device answer before consulting Gemini. Food photos now go to the configured full Flash model first when the existing cloud preference allows it. Printed single nutrition panels remain deterministic and authoritative. When cloud fails, the user sees a clearly identified on-device estimate and must confirm food names. Cloud opt-out never sends an image.

Default: `gemini-3.5-flash`, temperature 0.2, thinking budget 2048, max output 8192 tokens, request timeout 120 seconds. Empty and legacy Lite settings resolve to full Flash; custom settings remain supported. This is a stronger model configuration, not a measured accuracy guarantee. A synthetic label benchmark returned its exact printed nutrients; this does not establish real Indonesian food accuracy.

The prompt covers Indonesian rice varieties, Padang/warteg dishes, soups, satay-side dishes, tofu/tempeh, snacks, sauces and drinks. It requires inspection of visible components, avoids invented customary sides, forbids double-counting composite dishes and components, and requests literal descriptions for ambiguous identities. Confidence of 0.55 or lower requires explicit name confirmation. Nutrition from appearance remains an editable estimate, including oil, coconut milk and portions.

No user food photo dataset was collected or uploaded for these tests. Model migration, warning amounts, existing domain behavior, printed-label OCR and invalid-image handling are covered by tests. Signed app builds exercise the actual Firebase AI SDK.
