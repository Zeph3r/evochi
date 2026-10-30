# Next steps (handoff)

The latest work is the fight rework: every move in four beats (wind-up, action, impact with a
hit-stop, recovery) and a canvas particle engine (`web/src/ui/fx.js`, ported to Flutter as
`stage_fx.dart`); the four encounter Shorts were re-recorded with it. Before that, the encounter rework: the battle shot (your Evochi from behind, the wild one
facing it, low Blender cameras), camera moves and ability effects, the Sentinel's awakening, encounter
music, and the encounter UI after the Encounter UI Redesign board. Before that: Lumen Trails (daily
discoveries, the Trail Guild, encounters and companions). README.md covers the project, the art
pipeline and how to build.

## The onboarding cinematic (in progress)

The Fading Paths cold open and the beats after it (README: "The onboarding cinematic"). What's there:

- `tools/art/cine_scenes.py`, `cine_blender.py`, `cine_pack.py`, `render_cine_pc.py`, `onboarding_cine.py`,
  `cine_assets.py`: the scenes, the renderer (DoF, depth pass, sky worlds, actors, layered renders, the grade),
  packs for the PC's GPU, the cut and its preview video, the asset packer.
- `flutter/lib/features/onboarding/cinematic_player.dart` (the cold open, from the same shot list),
  `cinematic_screen.dart` (once before Welcome, again from Settings > Watch the intro),
  `onboarding_beats.dart` (EggPickScreen: Mira's nest; HatchScreen: the egg cracked by real steps, the hatch,
  naming after it, the name flying to the map and the grove trail lighting). The router uses the new screens;
  the old CreateScreen and AwakeningScreen stay in `onboarding_screens.dart` unused. A new pet is created as
  "Eggling" and renamed after the hatch (`renamePet`); the web build's onboarding is unchanged.

Still to do:

- **Full-quality plates.** The packs are on the PC (`blender\cine\packs\`, 55 of them, with the current
  `cine_blender.py`, `cine_pack.py` and `render_cine_pc.py`); double-click `blender\cine\render_cine.bat` to render
  them on the GPU (progress in `packs\render_status.json`). Then bring the raw frames and depth passes back,
  `cine_blender.py --regrade`, and `cine_assets.py` into `flutter/assets/art/cine/`. Until then the PC's
  `assets/art/cine/` holds a stand-in pack of the CPU previews (14 plates; the rest fall back in the app).
- **Look.** Done against the storyboard at preview size: the steps scene (remodelled sneakers, Mochi facing the
  camera, the prints visible), the Glasshouse at night (warm inside, Mira at the door at village size), Pip (stands
  in the Lodge, no counter in front of him). Check the rest at full size: the Hollow creep's density, the crack glow.
- **Founders.** The app can't tell a founder yet (the waitlist knows, the app doesn't), so `pip_gold` isn't shown.
  A claim code in the beta invite, or the sign-in email matched against the waitlist, would decide it.
- **The push-in as a real camera move** (storyboard frame 6) and the Glasshouse tracking shot (frame 11): the
  app zooms the plates for now; `cine_blender.py` can render a camera path as frames (`vs.cameras`, as the
  Elder orbit does) for a pre-rendered version on the PC's GPU.

## Not verified yet

- **Flutter now compiles and runs on Windows** (Flutter 3.27.1, VS 2022, 19 Oct 2026): `flutter analyze`
  has 0 errors, `flutter test` passes 67, and the Windows debug build runs onboarding, Home, Journey,
  Bag, EvoDex, the Village and the whole Market (browse, details, Dressing Room, buy → Equip Now,
  nest preview, seeds). On Windows, run `1_check.bat` (doctor, platform folders, pub get, analyze,
  test) and then `2_build_and_run.bat` (it waits for Developer Mode, which plugins need for symlinks,
  then builds and opens a phone-sized window). `NuGet.Config` adds nuget.org for audioplayers_windows.
  Logs go to `logs/`. Android and iOS builds are still untried.

- **Flutter build.** Home Tales and the Lumen Trails were ported to Flutter but, like the rest of
  the Flutter client, only syntax-checked, never compiled. That includes the newest port, the fight
  choreography and the effects engine (`features/trails/stage_fx.dart`, the hit-stop clock in
  `encounter_stage.dart`): play a Lumen Glow turn and the Hollow Sprout's finish and compare the
  timing with `web/` frame by frame. Run `flutter pub get`, `flutter analyze`
  and `flutter test` in `flutter/`, then play Explore Home → Garden, the Cottage restoration, a daily
  discovery and the first encounter, and compare with the web build. See the "Home Tales" and
  "Lumen Trails" sections of `flutter/README.md` for the files.
- **Flutter: the game-native kit** (`lib/features/shared/kit.dart`, the 9-slice frames in `assets/ui/`)
  is also uncompiled. Run `dart format lib` (some `KitPage` wraps are indented 2 spaces off), then
  `flutter analyze`; the spots most likely to need a touch are the typed record pattern in `Tag`,
  `DecoratedSliver` in Journey, and `SnackBar(clipBehavior:)` / `Dialog(surfaceTintColor:)`. Compare
  each screen with `node tools/ui_tour.mjs OUT` on the web build. Settings, Pet, onboarding, Cottage,
  Garden and Home Map only pick up the kit through the shared widgets so far.
  The UX pass on top of it (Journey order, the Bag's dressing room, the cooking station, Larger text,
  Developer tools) is uncompiled too; check `EvochiTextScaler` in `app/theme.dart`, `ListenableBuilder`
  in `shared/scene_scaffold.dart` and `Image.asset(opacity:)` in `home/station_screen.dart` first.
- **Flutter: the Market redesign** (`lib/features/shop/`: `shop_screen.dart`, `market_kit.dart`,
  `market_catalog.dart`, `market_details.dart`, `market_preview.dart`) is uncompiled. Run
  `flutter test test/trails_test.dart` for the new Sentinel hand-in test, then walk the same path as
  `market_check`: browse each tab, search and sort, open a sheet, the Dressing Room (three views, zoom,
  Show original, buy, Equip Now, Take off), Preview in Nest, and View in Bag. Check that the catalog
  keeps its scroll position after a preview and after switching tabs. The hero offer is hard-wired to
  `golden_crest_crown` because the Dart catalog has no `hero` flag.
- The web build is the reference. Run `cd web && node build.mjs`, serve `web/dist`, and play. Web
  tests: `npm test` (66 pass). Phone-size playthroughs (Home Tales: walk → plant → harvest → Bram →
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
- Encounter pacing: a turn plays out in about 2-2.5 s (impact at ~0.9 s, the reply at ~1.6 s), the
  intros run 4.3 s (rare), 4.9 s (Hollow) and 8.2 s (the Sentinel's awakening), all skippable. The
  timings are in `runTurn` / `playIntro` (`web/src/screens/encounter.js`); the shot sizes (your
  Evochi's width per stage, the wild one's cap) are `PET_W` and `shotGeometry`.
- Discoveries: three a day from the authored pool in `DISCOVERIES`; walk targets are
  `min(nominal, half your goal)`; Guild ranks at 0 / 40 / 120 / 260 / 480 XP.

## Open decisions and ideas

- The encounter backdrops could go further toward the board: more flowers and ferns around the
  clearing, a waterfall in view at the ruins. They're in `trail_scenes.py` (`to_battle`, `BATTLE`).
- The intro cinematics and turn effects are CSS + timers; the Flutter port mirrors the layout and the
  state but not every effect yet (see `flutter/README.md`).

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
