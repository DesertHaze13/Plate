# Plate icon: "Bite P"

Open `Resources/Plate.icon` in Apple's Icon Composer. It is a layered Liquid Glass icon for iOS and macOS.

- **Mark:** a bold lowercase **p** whose bowl is Plate's energy ring, with a bite taken out of its top-right. It says food, progress and Plate in one shape. The aurora gradient runs violet → pink → coral → amber, the same colours as the ring inside the app.
- **Spark:** a white four-point spark bursts from the bite (the AI that reads your food), with two crumbs in the carb (amber) and fat (mint) colours.

## Layers

1. **Background fill.** Light: a soft peach-to-lilac aurora. Dark: deep ube to near-black.
2. **Bite P** (glass). Specular highlights, 20% translucency and a coloured shadow, so it reads as a glass object floating over the fill. In the clear and tinted appearances, the system turns this into frosted glass.
3. **AI spark** (on top). A neutral shadow lifts it off the P.

The layer images are `Assets/plate.png` (porcelain plate, bottom), `Assets/ring.png` (the bitten P sitting on the plate, glass) and `Assets/spark.png` (AI spark, top), rendered at 1024 × 1024 from `Resources/Icon Sources/plate.svg`, `ring.svg` and `spark.svg`. Edit the SVGs, re-render them to PNG, and preview Default, Dark, Clear and Tinted in Icon Composer.
