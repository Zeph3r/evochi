# Evochi — Logo Asset Pack

This ZIP contains the **actual transparent PNG images** generated for the Evochi logo, plus crops, common UI sizes, individual decorative PNG assets, a visual overview, and a Claude-ready implementation prompt.

**Important:** These are **raster PNGs, not true SVG vectors**. They scale down well within reasonable UI sizes but they cannot scale infinitely without rasterization. The project does not contain editable letter/extrusion paths. Do **not** rename PNG files to `.svg` or embed them in SVG and claim they are vector art. If true SVG is needed, manually rebuild clean pixel-aligned paths from the approved style reference, keeping the PNGs as reference/fallback.

## Where to start

1. Open `previews/asset_overview.jpg` to see the variants on example backgrounds.
2. Open `instructions/CLAUDE_PROMPT.md` and paste its contents into Claude alongside the ZIP (or extracted directory).
3. Use the chosen assets in your game's existing logo/title/header components. **Preserve the current UI layout and navigation.**

## Files

- `assets/originals/logo_primary_with_sparkles.png` — primary generated full-color wordmark (sparklier, detailed).
- `assets/originals/logo_clean_header_variant.png` — cleaner full-color variant (better for headers).
- `assets/originals/brand_crystal_icon.png` — crystal + sprout brand symbol (not yet an Android/iOS icon package).
- `assets/originals/ornaments_source_strip.png` — all the decorative sprites laid out on one transparent strip.
- `assets/game-ready/logo_primary_trimmed.png` — tightly cropped primary wordmark, unscaled.
- `assets/game-ready/logo_compact_trimmed.png` — tightly cropped cleaner wordmark, unscaled.
- `assets/game-ready/logo_primary_1024w.png`, `768w.png`, `512w.png` — title/load-screen PNG options.
- `assets/game-ready/logo_compact_512w.png`, `384w.png`, `256w.png` — in-game header PNG options. Small sizes may need further optical simplification.
- `assets/game-ready/icon_trimmed.png`, `icon_512w.png`, `icon_256w.png`, `icon_128w.png` — branding symbol sizes.
- `assets/game-ready/logo_one_ink_dark.png`, `logo_one_ink_light.png` — **automatically extracted**, simplified one-ink text/ornament masks. **Review before shipping**, as they are convenience derivatives and not final hand-designed monochrome marks.
- `assets/ornaments/` — individually cropped sprouts, amber crystal, and sparkle PNGs, to place or animate independently.
- `reference/evochi_approved_style_reference.png` — the approved style/concept sheet, **reference only**. Do not use this sheet as an in-game texture.
- `previews/asset_overview.jpg` — preview on sample backgrounds, **not** a game texture.

## Integration notes

- Preserve transparent alpha. Do not add a rectangular plaque or opaque background behind the logo.
- Keep the aspect ratio; never stretch to fill the screen width and height simultaneously.
- Center within a responsive safe area. On mobile leave space for a notch/status bar and controls.
- Keep logo decorations optional: use `assets/ornaments/` as **separate UI layers** when adding sparkle animation.
- Use `contain`/aspect-ratio-preserving scaling in the actual UI renderer.
- For a high-resolution PNG, downscale carefully using one of the supplied exports and inspect at the final device size. `image-rendering: pixelated` is optional; it may look worse when the source is already antialiased.
- Do not build a new logo out of a generic font when these approved visual references are available.
- Test the wordmark on both dark night and bright grass scenes.
- The output is a generated visual asset. Before release, inspect minor pixel/artifact fringes, kerning, and letter geometry.

## Suggested asset paths in the project

```text
assets/ui/branding/
  evochi-logo-primary.png
  evochi-logo-header.png
  evochi-mark.png
  ornaments/
    amber-crystal.png
    sprout-left.png
    sprout-right.png
    sparkle-*.png
```

Store the source archive outside the runtime assets directory if your engine bundles all source files by default.
