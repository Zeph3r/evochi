# Evochi facial expression art kit

This pack is intended for Claude / your game-dev workflow. It preserves all **previously generated reference sheets unchanged** in `references/`. The sprites are **transparent, newly reconstructed prototypes** inspired by the earlier concept art; they are **not exact extracted character textures** or a substitute for the existing 3D model / UV mappings.

## What is inside

- `references/`: exact original art images, the original in-game stage model sheet, personality sheets, and Claude's current version for comparison.
- `assets/svg/`: 54 editable vector facial poses (6 personalities × 3 evolutions × 3 combat reactions).
- `assets/png_512/`: 54 transparent RGBA decals, 512×320.
- `assets/png_256/`: the same 54 in native 256×160 resolution.
- `assets/layers_png_512/`: 270 independent transparent layers (`brows`, `eyes`, `cheeks`, `mouth`, `accents` for each pose). Use these for facial interpolation, blink, strain morph, character-specific reactions.
- `previews/`: contact sheets of the assets.
- `manifest.json`: mappings for names, stage, personality, expression and file locations.
- `CLAUDE_CORRECTION_BRIEF.md`: exact prompt / instructions to provide Claude.

## Integration principles

1. **Keep the actual character mesh, voxels, ears, horns, tail, feet, gold patches and material exactly unchanged.** The art assets here are ONLY eyes, eyebrows, mouth, cheeks and optional tiny accents.
2. Put the expression decal on the **existing face material or face region** using current UV mapping, or implement small transparent texture layers if the existing rig supports it. Avoid having face art hover above a curved head. You will need the actual model UV coordinates and render code to place layers exactly.
3. Apply personality and evolution, then state (e.g. `timid_elder_strain`), leaving the body mesh untouched.
4. For production, match decal UV placement to the true 3D face. Test from front, 3/4 angle and boss cinematic camera.
5. Color palette is in `manifest.json`; avoid stark outlines, bright blue anime sweat icons or massive black eyebrows not justified by the expression.
6. Treat the source reference sheets as *style direction*, NOT automatically as game-ready source assets. These generated art sources were flattened with their backgrounds.

## Precision caveat

A raster concept sheet does not contain its original editable eyes / mouth layers, actual voxel geometry, UV mapping or render settings. Therefore, a literal pixel-exact implementation is impossible without source model / face atlas. The `references/` files are the **exact original images**. The alpha PNG / SVG sprite assets are hand-built approximations designed to make iteration faster.
