# Evochi

*Every step brings your Evochi to life.* Evochi is a cozy voxel pet, built from the
*Evochi Complete Game Design, UI/UX & Style Guide v1.2*.

| Folder | What it is |
|---|---|
| `web/` | The playable build: every screen, all the game rules, 40 engine, QA and story tests (`npm test`) and an inline build (`node build.mjs`). |
| `flutter/` | The iOS/Android client, organised per §21. It has not been compiled yet; see its README. |
| `assets/` | Master art (PNG) and audio (WAV), named per the §21 convention. |
| `tools/art/` | The Python voxel pipeline that generated every asset. |

## Village Tales, Chapter 1: The Light of Sunlit Village

A short story chapter built from the *Village Tales Quest Bible v1.0* and its design manifest. It
adds no sixth tab:

- **Visit Village** on Home opens the Square.
- Story quests live in **Journey > Story**.
- Quest items live in **Bag > Pouch**.

**Cast and places:**

- Mira the Gardener (Glasshouse).
- Bram the Lanternkeeper (Workshop).
- Pip the Courier and Alder the Mapmaker (Trail Guild Lodge).
- The Waystone in the Square.

**Quests:**

| Quest | Unlocks | Walk | Reward |
|---|---|---|---|
| VQ01 A Light for the Village | Lv 1 | 2,000 new steps | Firefly Hearth (Nest decor) + 75 EvoCoins |
| VQ02 The Letter Beyond the Bridge | Lv 3 and VQ01 | 2,500 steps on 2 different days | Windtrail Mantle (back slot, all forms) + 125 |
| VQ03 The Sleeping Waystone | Lv 6 and VQ02 | 3,500 steps on 3 different days | Waystone Bloom (side decor) + 250 + title *First Lightkeeper* |

**Rules (Quest Bible §9):**

- Only steps taken after you accept a quest count.
- Each walk target is `min(nominal, your daily goal)`, fixed when you accept.
- Multi-day walks count distinct local days, with one quest item per day.
- Rest days and paused step sync never fail a quest. There are no timers or streaks.
- Hand-ins and payouts are idempotent.
- Story progress belongs to the account, so it survives a memorial, a new pet or a new colourway.

**Items:**

- Quest items are never catalog items, so the Market, chests and trading can't see them.
- Story rewards are ordinary inventory items, but they are never sold: `acquisition: 'story'`,
  `shop: null`, `price: null`, not tradable, not sellable.

**Manual step entries** count toward story walks. This is set by `STORY_CONFIG.countManualSteps`
(web) and `StoryConfig.countManualSteps` (Flutter). Turn it off before any story reward becomes
tradable.

**Code:**

- Rules: `web/src/game/story.js`, mirrored in `flutter/lib/game/story/`.
- Screens: `web/src/screens/village.js`, mirrored in `flutter/lib/features/village/`.
- Tests: `web/test/story.test.mjs` (the Bible's 10 acceptance tests plus step-rule checks),
  mirrored in `flutter/test/story_test.dart`.

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
- **Village Tales:**
  - Mira, Bram, Pip and Alder as voxel sprites with 5 expressions each (neutral, happy, worried,
    thinking, proud): `village/npc_mira_happy.png`.
  - The Square in 3 story states (dim, lamp lit, Waystone restored), the Glasshouse, Workshop and
    Trail Guild interiors, and the Waystone close-up (dormant and restored).
  - 7 quest item icons and 3 story rewards. The Windtrail Mantle has overlays fitted to every
    form, and the Firefly Hearth and Waystone Bloom have decor sprites for their Nest slots.
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
python3 build_village.py ../../assets                    # villagers, quest items, mantle, decor, scenes
python3 build_web_assets.py ../../assets ../../web/public/assets <fontsource-dir>
python3 build_web_assets.py ../../assets ../../web/public/assets --village-only   # just the Village Tales art
```

The models live in `characters.py` and `accessories.py`, and the palettes in `palettes.py`. The
villagers are in `village_npcs.py`, the quest items and rewards in `village_items.py`, and the
Square and the interiors in `village_scenes.py`.
Change a model or palette there and every sprite, overlay and turnaround regenerates consistently.
