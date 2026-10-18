# Next steps (handoff)

The latest work is commit "Home Tales: Home Map, Garden, Cottage, Kitchen and Apothecary, Skills".
README.md covers the project, the art pipeline and how to build.

## Not verified yet

- **Flutter build.** Home Tales was ported to Flutter but, like the rest of the Flutter client, only
  syntax-checked, never compiled. Run `flutter pub get`, `flutter analyze` and `flutter test` in
  `flutter/`, then play Explore Home → Garden → plant → harvest, and the Cottage restoration, and
  compare with the web build. See the "Home Tales" section of `flutter/README.md` for the files.
- The web build is the reference. Run `cd web && node build.mjs`, serve `web/dist`, and play. Web
  tests: `npm test` (56 pass). A phone-size playthrough of the whole loop (walk → plant → harvest →
  Bram → restore the cottage → cook with the minigame → give it to the pet → Mira → Apothecary) runs
  clean with no page errors at 390 and 360 px.

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

## Open decisions and ideas

- More recipes per skill level, and a use for Moonshroom Pie / Moonlight Draught beyond vitality
  (e.g. a later side story).
- A "species-specific" quest beyond the stage-gated Grove story, once more species exist.
- Room-lit vs classic villagers: switch with Settings → Classic villagers. Bram has the weakest
  contrast when room-lit (brown on a brown workshop).
- The villager sprites are a little soft on high-DPI phones. Re-render at 1.5× by raising `NPC_SCALE`
  in `tools/art/build_village.py` from 12 to 18, then rebuild the village pack.
- Poses, pivots and idle/talk/listen keyframes live in `tools/art/village_npcs.py` (`NPC_ANIM`).
