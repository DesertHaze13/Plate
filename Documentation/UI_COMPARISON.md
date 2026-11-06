# UI comparison: Current and Plate

The earlier Plate interface copied Current’s palette and broad column layout, but did not share enough of its interaction language. Rounded cards alone did not produce the same experience.

| Area | Current reference | Earlier Plate | Updated Plate, build 8 |
| --- | --- | --- | --- |
| Surfaces | Reflective regular glass, visible pastel fields and layered shadows | Flat ultra-thin material and low-contrast blurred background | Regular glass surfaces, distinct pastel fields and stronger layered shadows |
| Navigation | Draggable floating glass bar; sliding selection and spring feedback | Standard tabs with a second capture bar | Draggable floating glass navigation with a sliding selection, symbol response, haptics and adjacent capture action |
| Sidebar | Gradient icon tiles, hover tilt and sliding active row | Flat icons and abruptly changing active row | Dimensional gradient tiles, hover feedback and matched selection motion |
| Main hero | Compact value, tactile illustration and expandable details | Oversized ring with static surrounding content | Compact energy hero, layered food illustration, animated eaten/remaining switch and expandable macro drawer |
| Data exploration | Switchable stories and expandable data | Mostly read-only cards | Energy/Protein/Balance stories, macro detail expansion, meal filters and chart selection |
| Controls | Tactile buttons and animated selection | Standard segmented pickers mixed with custom controls | Consistent spring selection across nutrition stories, progress period, goals and units |

Motion supports Reduce Motion. Glass cards fall back to solid surfaces when Reduce Transparency is enabled. Decorative artwork never changes logged nutrition.

The update also removes a Google-login crash path: Firestore’s default persistent cache is used without changing shared settings after the database starts. Google configuration is validated before entering the SDK, and overlapping sign-in attempts are ignored.
