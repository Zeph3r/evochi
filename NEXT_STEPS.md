# Next steps (handoff)

The latest work is the Lumen Trails commit (daily discoveries, the Trail Guild, encounters and
companions). README.md covers the project, the art pipeline and how to build.

## Not verified yet

- **Flutter build.** Home Tales and the Lumen Trails were ported to Flutter but, like the rest of
  the Flutter client, only syntax-checked, never compiled. Run `flutter pub get`, `flutter analyze`
  and `flutter test` in `flutter/`, then play Explore Home → Garden, the Cottage restoration, a daily
  discovery and the first encounter, and compare with the web build. See the "Home Tales" and
  "Lumen Trails" sections of `flutter/README.md` for the files.
- The web build is the reference. Run `cd web && node build.mjs`, serve `web/dist`, and play. Web
  tests: `npm test` (65 pass). Phone-size playthroughs (Home Tales: walk → plant → harvest → Bram →
  cottage → cook → Mira → Apothecary; Lumen Trails: discovery → Guild → Pip → prep → travel →
  encounter → reward → companion, then the Hollow Sprout and the Sentinel) run clean with no page
  errors at 390 and 360 px.

## Balancing to playtest (all starting values)

- Crop times (20 min to 6 h), yields and XP: `CROPS` in `web/src/game/home.js`.
- Walking bonus: 10,000 steps after planting add one full growing time, capped at 60%; watering
  adds 15%; Sprout Tonic 50% (`GROW`).
- Skill curve: 40 XP for Lv 2, +20 per level, max 20 (`SKILL_CURVE`). Recipes and the 4th bed unlock
  from the skill levels in `RECIPES` / `PLOTS`; the Skills chart reads them, so it stays in sync.
- Minigame: the golden zone is 62-80% of the meter (with a small grace), one sweep is 1.7 s (2.6 s
  with reduced motion). Perfect = double batch and +50% skill XP; skipping = a normal batch.
- Seed prices on the Market's Garden shelf (8-35 EvoCoins).
- Treats: a meal or tea gives Bond +1 once a day, even at full vitality (`CONFIG.bond.treat`).
- Encounters: Lumen Glow 16 (×1.3 vs Hollow), Nudge 9, Soothe +30 Energy; item effects and the
  creatures' favourites in `itemEffect` / `CREATURES.likes`; Petalune's Calm meter 100, the Hollow
  Sprout 100, the Sentinel 200 with a second phase from 50%. The wild creature's replies (skitter,
  surge, lash) and their odds are in `wildTurn` (`web/src/game/trails.js`).
- Discoveries: three a day from the authored pool in `DISCOVERIES`; walk targets are
  `min(nominal, half your goal)`; Guild ranks at 0 / 40 / 120 / 260 / 480 XP.

## Open decisions and ideas

- More discoveries in the pool (the same places support dozens), and seasonal ones.
- Flamara (Ember) and Aquarel (Water) as daily-discovery encounters, with their exploration
  abilities (light torches, cross water) gating small side areas.
- Whispering Woods and Coastal Cove as the next two trails on the Waystone's map.
- More recipes per skill level, and a use for Moonshroom Pie / Moonlight Draught beyond vitality
  (e.g. a later side story).
- A "species-specific" quest beyond the stage-gated Grove story, once more species exist.
- Room-lit vs classic villagers: switch with Settings → Classic villagers. Bram has the weakest
  contrast when room-lit (brown on a brown workshop).
- The villager sprites are a little soft on high-DPI phones. Re-render at 1.5× by raising `NPC_SCALE`
  in `tools/art/build_village.py` from 12 to 18, then rebuild the village pack.
- Poses, pivots and idle/talk/listen keyframes live in `tools/art/village_npcs.py` (`NPC_ANIM`).
