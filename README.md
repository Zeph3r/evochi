# Evochi

*Every step brings your Evochi to life.* Evochi is a cozy voxel pet, built from the
*Evochi Complete Game Design, UI/UX & Style Guide v1.2*.

| Folder | What it is |
|---|---|
| `web/` | The playable build: every screen, all the game rules, the 23 engine/QA tests (`npm test`) and an inline build (`node build.mjs`). |
| `flutter/` | The iOS/Android client, organised per §21. It has not been compiled yet; see its README. |
| `assets/` | Master art (PNG) and audio (WAV), named per the §21 convention. |
| `tools/art/` | The Python voxel pipeline that generated every asset. |

## Asset pack contents

- **Characters:**
  - 3 forms (Eggling, Juvenile, Elder) × 6 colourways × 12 expressions, as left-3/4 hero sprites:
    `evochi_lizard_s01_amber_happy_left3q_f000.png`.
  - Turnarounds (front, left, back, right, top) for every form and colourway.
  - Expressions: default, blink, happy, curious, surprised, determined, sad, sleepy, excited,
    neutral, sick, memorial.
- **Wearables:**
  - 8 items, each with an overlay pre-fitted to every form: `item_leaf_scarf_neck_s02_left3q.png`.
  - The overlays share the hero frame, so equipping one is a single extra draw.
- **Item icons:** 14 inventory/shop items plus the preview platform.
- **UI icons:** 32 voxel icons: nav, HUD, categories, status, quests.
- **Habitats:**
  - Sunlit Meadow, Evochi Market and the Welcome vista, as separate sky/far/mid/near parallax
    layers plus a composite.
  - Decoration sprites rendered in the meadow's perspective for each anchor slot, with slot
    coordinates in JSON.
  - Forest and Cliffs thumbnails.
- **Titles:** voxel wordmark plus the screen titles (BAG, MARKET, JOURNEY, EVODEX, PROFILE,
  CREATE YOUR, MEMORIAL).
- **Audio:** UI tap, pet chirp, play, reward chime, coin, purchase, error, level up, evolution
  fanfare, memorial tone, and a seamless meadow ambience loop.

## Rebuilding the art

```bash
cd tools/art
python3 build_characters.py ../../assets/characters      # ~3 min per stage
python3 build_items.py ../../assets
python3 build_scenes.py ../../assets/habitats
python3 build_decor.py ../../assets/habitats
python3 wordmark.py ../../assets/ui_titles
python3 sfx.py ../../assets/audio
python3 build_web_assets.py ../../assets ../../web/public/assets <fontsource-dir>
```

The models live in `characters.py` and `accessories.py`, and the palettes in `palettes.py`.
Change a model or palette there and every sprite, overlay and turnaround regenerates consistently.
