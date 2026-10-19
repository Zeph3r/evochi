# Evochi

*Every step brings your Evochi to life.* Evochi is a cozy voxel pet, built from the
*Evochi Complete Game Design, UI/UX & Style Guide v1.2*.

| Folder | What it is |
|---|---|
| `web/` | The playable build: every screen, all the game rules, 65 engine, QA, story, home and trail tests (`npm test`) and an inline build (`node build.mjs`). |
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

**Rooms and dialogue:** each place is a storybook scene. The room fills the top of the screen, the
villagers stand on its floor, and a speech box with a name tab overlaps the floor. Its tail points at
the speaker, the line types in, and tapping the box finishes it (or carries on, shown by ▼).

The villagers are layered puppets: shadow, body, head per expression, a blink overlay, and the arm
with their prop. Each one has idle, talk and listen loops:

- Bram lifts and resettles his wrench.
- Mira raises her seedling to look at it.
- Pip waves his letter and hops.
- Alder nods over his map.

In the Trail Guild, whoever isn't talking reacts to the other. Interactables stay readable over the
busy rooms: the room sits back (softer, a vignette), the villager you can switch to has a pulsing ring
at their feet, shared rooms put name chips over heads, and quest markers bob above the villager they
belong to.

**Settings > Classic villagers** swaps the room-lit villagers for the original flat-shaded ones.

**Code:**

- Rules: `web/src/game/story.js`, mirrored in `flutter/lib/game/story/`.
- Screens: `web/src/screens/village.js` and `web/src/ui/puppet.js`, mirrored in
  `flutter/lib/features/village/` (`npc_puppet.dart`).
- Tests: `web/test/story.test.mjs` (the Bible's 10 acceptance tests plus step-rule checks),
  mirrored in `flutter/test/story_test.dart`.

## Home Tales: the Home Map, Garden, Cottage and Skills

A cozy crafting layer around the nest. The core loop is **walk → grow → craft → use it for your
Evochi or a quest → unlock**. Still no sixth tab: **Explore Home** on Home opens the Home Map, and
everything else is nested.

| Screen | Where | What it does |
|---|---|---|
| Home Map | Home → Explore Home | The Nest (your Evochi), the Garden, the Cottage and the Village Gate. First visit gives starter seeds (3 Sunberry, 2 Carrot). |
| Garden | Home Map → Garden | 3 beds to start (a 4th at Farming 4). Plant, then crops grow on real time; steps walked after planting add up to 60% more, watering adds 15%, a Sprout Tonic 50%. One tap harvests a ripe bed. |
| Cottage | Home Map → Cottage | Ruined until *A Place to Call Home* (Bram) is done, then it holds the Kitchen and the Apothecary. |
| Kitchen / Apothecary | Cottage | One shared UI: recipes with ingredient have/need, then a skippable timing game. A perfect result doubles the batch and gives +50% XP. Ingredients are never wasted. |
| Skills | Journey → Skills, or the Cottage | Farming, Cooking and Alchemy: XP, level and a milestone timeline showing the skill level and any story quest each unlock needs. |

**Quests** (same engine as Chapter 1; hand-ins can ask for real inventory items):

| Quest | Needs | Steps | Reward |
|---|---|---|---|
| HQ01 A Place to Call Home (Bram) | Lv 2, VQ01 | 3,000 new steps for timber, 3 Sunberries | Cottage + Kitchen, 100 coins, wheat seeds and wheat |
| HQ02 Mira's Mortar (Mira) | HQ01, Cooking 2 | 2 Glowleaf (Farming 3) | Apothecary, 80 coins, Glowleaf and Moonshroom seeds |
| SQ01 The Shy Visitor (Pip), *optional* | HQ01 | a homemade Sunberry Tart | 120 coins, Moonshroom spores, title *Friend of Small Things* |
| SQ02 Guardian of the Old Grove (Alder), *optional* | HQ02, a Juvenile Evochi | a Glowleaf Tonic | 200 coins, title *Grove Friend* |

Special requirements (a grown Evochi, crafted food) live only in side stories, so they never block
the main story. Seeds are sold on the Market's **Garden** shelf; harvests, meals and brews are never
sold. Meals and teas are treats: once a day they give Bond +1, even at full vitality. Seeds and
ingredients live in **Bag > Pantry**. Home progress (beds, skills) belongs to the account, like the
story.

**Code:** rules in `web/src/game/home.js` (+ the HQ/SQ quests in `story.js`), screens in
`web/src/screens/homeland.js`, tests in `web/test/home.test.mjs`. Art: `tools/art/home_scenes.py`
(Home Map, Garden, Cottage close-ups, Kitchen, Apothecary; Blender) and `tools/art/home_items.py`
(seeds, crops, dishes, potions, skill icons, crop growth sprites).

## Lumen Trails: discoveries, the Trail Guild and encounters

The lore that ties everything together, and the game's gentle take on battles.

**The Fading Paths.** Long ago, luminous paths called Lumen Trails connected every corner of the
Evochi world. Lumen is made by movement, exploration and the bonds between living things, so your
real steps restore the trails. Evochi were the guardians of those paths. The Trail Guild was formed
to restore them, and the mysterious Hollow is Lumen gone unstable. At the end of Chapter 1 the woken
Waystone projects a map of the old trails; Alder tells you the rest.

**Daily discoveries** (`Journey → Daily`, the Home chip, or the Guild Board): the Guild posts three
small adventures a day from an authored pool, picked deterministically per account and day (never
random objectives). Each one: *Begin → walk (only steps after you begin count) → inspect the place*,
where a glinting clue appears. Rewards are coins, seeds, Lumen Shards and Guild XP. Guild ranks:
Wanderer → Trail Friend → Pathfinder → Lightkeeper → Trailwarden.

**Encounters** are never fights to the finish. Wild Evochi are *calmed and befriended* (fill the Calm
meter); Hollow-tangled guardians are *restored* (bring Instability to zero). Your Evochi has Energy
but never faints, and you can retreat at any time with the items you used returned. Each encounter
runs *prepare → travel → a short animated intro (2–6 s, skippable) → turns → outro → result*. The
encounter is a seeded, pure state machine, so one attempt always replays the same way.

| Turn action | Effect | Energy |
|---|---|---|
| Lumen Glow (Light) | +16 (×1.3 against the Hollow, ×1.25 more once the Sentinel wakes) | 24 |
| Gentle Nudge (Physical) | +9, and a wild Evochi turns curious (+4 next time) | 10 |
| Soothe (Restore) | +5 and restores 30 Energy | 0 |
| Use Item | homemade food calms (×1.5 if the creature loves it); tonics, Glowleaf and herbs steady the Hollow | 0 |
| Petal Hush (companion) | +12, once per encounter, once Petalune is your friend | 0 |

**Trail jobs** (quests in the story engine, line `trail`; the encounter is the hand-in):

| Job | Needs | Walk | Encounter | Reward |
|---|---|---|---|---|
| EQ01 The Forest Guardian (Pip) | Lv 3, VQ01, 2 discoveries | 1,500 steps → Mossy Clue | befriend **Petalune** (Nature) at the Mossy Ruins; a Sunberry Tart helps | companion Petalune, 150 coins, seeds, shard, title *Friend of Petalune* |
| EQ02 Tangled Lumen (Mira) | Lv 4, EQ01, HQ01 | 2,000 steps → Lumen Trace | restore the **Hollow Sprout**; 2 Glowleaf required | 180 coins, shards, the Lantern Tonic recipe |
| EQ03 The Forgotten Sentinel (Alder) | Lv 6, VQ03, EQ02 | 3,000 steps → Alder's Old Map | restore the **Sentinel** (story boss, two phases) at the old gate; a Lantern Tonic required | Ancient Relic (nest decor), 300 coins, shards, title *Trailwarden* |

Befriended Evochi are **companions**: an EvoDex entry, a visit to your Home Map, and a helping
ability in later encounters. Restored guardians stay at their place. Affinities (Nature, Ember,
Water, Stone, Celestial, and the lizard line's general-purpose Lumen) come from the species, never
from a colourway.

**Code:** rules in `web/src/game/trails.js` (+ the EQ quests and dialogue in `story.js`), screens in
`web/src/screens/trails.js` (Guild Board, discoveries, travel, trail places) and
`web/src/screens/encounter.js` (encounter prep and the encounter itself), tests in
`web/test/trails.test.mjs`. Art: `tools/art/trail_scenes.py` (Mossy Ruins, its Hollow twin and the
Sentinel's gate, plus their battle shots; Blender) and `tools/art/trail_art.py` (the three creatures
with their encounter states, items, affinity and UI icons).

### The encounter shot

Encounters are shot like a battle scene: a low Blender camera just behind your Evochi, which stands
in the foreground on the left **seen from behind** and turned toward the wild one (the `battle` view of
every stage, colourway, wearable and 7 expressions, from `build_characters.py --battle`). The wild one
stands in the middle distance and faces it (`trail_art.py battle`: creature sprites rendered turned
toward you). Each place has a 2:3 backdrop (`<place>_battle`) and a soft foreground layer
(`<place>_battle_fg`, blurred by the packer), with anchors for both feet and both heights, so the
sprites are sized by the scene's perspective.

- **Camera:** the stage is one live element kept across re-renders (`data-keep`, `App.patchKept`) so
  its moves never restart. Shots: `wide`, `pet` (wind-up), `wild` (push-in with parallax on your
  Evochi and the foreground), `close` and `face` (intros). Hits shake it; the Sentinel's arrival is a
  big shake.
- **Turns are choreographed** in four beats, like a fighting game: a wind-up (your Evochi crouches),
  the action, the impact and the recovery. The impact is a *hit-stop* (everything on the shot holds
  still for 3 frames: CSS animations, the camera and the particles), a white flash on the one that was
  hit, a knock-back with squash, a camera punch toward the point of contact, a shockwave ring and
  shards from it; the number pops first and the meter drains after it. The moves: Lumen Glow (motes
  gather into your Evochi as it brightens, a comet of light with a trail flies, light bursts), Gentle
  Nudge (crouch, hop into it, dust and stars), Soothe (teal rings and motes, +Energy counts up),
  items (the item itself turns over in an arc with sparkles, then three chew bounces), Petal Hush
  (Petalune swoops in; a stream of petals winds across and swirls around the wild one). The reply:
  skitter, head tilt, a Hollow surge (ring, embers, a dark vignette pulse), a flicker, or the Hollow
  comes at you (crouch, lunge toward the camera, a violet lash lands on your Evochi: hit-stop, recoil,
  shards, −Energy). The finish: the Hollow one flashes white and *dissolves into motes of light* while
  rays turn behind it, and the restored creature pops back in with a ring, shards and confetti.
- **Effects engine:** `web/src/ui/fx.js` draws all of that on two canvases inside the shot (one behind
  the creatures, one in front): soft pre-rendered sprites (glow, star, shard, petal, heart, puff,
  smoke) with additive light, trails, rings, rays, a vignette pulse, a dissolve emitter and ambient
  motes (gold over the grove, violet embers around a Hollow one). Positions are percent of the shot
  and sizes are 1% of its width, so it looks the same on any phone. Reduced motion turns it off.
- **Idle life:** both creatures breathe, your Evochi blinks (the `blink` battle expression) and the
  wild one glances about between turns, so the shot is never dead still.
- **Intros on the same shot:** close on the wild one, then the camera pulls back as your Evochi steps
  in. The Sentinel's awakening is a story beat: the meadow music stops, a rumble, dust falls, its eyes
  light one after the other, the gate shakes, your Evochi flinches, and the boss music begins before
  the title. Everything is skippable, and reduced motion swaps it for a short fade.
- **Music:** `enc_wild_loop` (encounters), `enc_boss_loop` (the Hollow and the Sentinel), the
  awakening cues `enc_rumble` and `enc_awaken`, and ability cues (`sfx.py`). `audio.setMusic` crossfades.
- **The flow** (after the Encounter UX Flow board): the Journey's Story tab opens with a highlighted
  *Main Quests* card for any trail job whose encounter is waiting ("The Mossy Ruins: disturbance
  detected", the creature as a silhouette, motes rising); the prep screen (*Encounter Preparation*: the
  place, the creature's nameplate, Objective with the checklist, *Recommended* as two tiles, a Suggested
  Item and a Suggested Approach, *Your Team*, a gold *Begin Encounter*); the travel screen with entry
  motes; the intro on the battle shot; the encounter; the result.
- **UI** (after the Encounter UI Redesign board): the intro ends on a hero shot of the wild one with a
  big stacked title ("A Wild / Petalune / Appeared!", "The Forgotten / Sentinel / Awakens!"), the goal
  ("Earn its trust" / "Restore its light"), a line about it and *Begin Encounter*; your Evochi steps in
  when you begin. Nameplates have a portrait, the meter's label and value and a thin bar; under the wild
  one's sits the goal with the turn count (always visible) and status chips read from the real state
  (Hollowed, Waking, Unsteady, Flickering, Wary, Curious, Soothed; on your Evochi: Lumen Charged, Tired,
  Petalune is with you; tap one for what it means). Short announcements ("It's very effective!",
  "Hollow energy surged!", "Petalune seems wary.") pop under the goal; the log card has a headline and a
  line under it in the board's feedback language; the four actions show their cost; Petal Hush sits next
  to Retreat. The result card: "Petalune / Is Calmed!" or "… / Is Restored!", the rewards as tiles, a
  green *Continue*, reward toasts ("Friend of Petalune title earned!") and a speech bubble over the
  creature.
- **Effect library** (the board's names, in `web/src/ui/fx.js`): Lumen Wisps (leaves winding along a
  Gentle Nudge or Petal Hush), Flower Petals (ambient in wild encounters, and Petal Hush), Healing
  Sparkles (Soothe: twinkles, plus signs, leaves), Golden Pulse (where Lumen Glow lands), Hollow Shards
  (crystals breaking off a Hollow one), Violet Crackle (the Hollow's surges and its lash), Dust Burst
  (stone chunks and dust on heavy hits and the Sentinel's awakening). Gold light and green leaves are
  you; violet crystals and crackle are the Hollow. A hit tints light creatures gold and brightens dark
  ones, never a white silhouette.

## The Evochi Game UI Kit (the visual foundation)

The interface is built from crafted materials instead of flat web panels (`web/src/kit.css`, loaded
after `styles.css`; the Flutter app mirrors it in `lib/features/shared/kit.dart`). This is the locked
visual language: new systems (the Lumen Wilds, dungeons, crafting) use these pieces rather than new
directions.

**Palette** (named for the kit, reconciled with the canonical style-guide tokens; where the two were
within a shade, the canonical value is kept):

| Token | Value | Use |
| --- | --- | --- |
| Wood frame | `#8B5939` (frames paint `#B8783F` → `#8E5428`, ink `#4A2A14`) | primary windows, plaques, tabs, nav |
| Parchment | `#F8EBD5` (cards `#FFF8E8` → `#F6E6C8`) | content surfaces |
| Warm gold | `#F4B84E` (`--gold-500`) | primary buttons, the chosen tab and slot |
| Meadow green | `#82B75E` (`--meadow-500`) | positive actions (Give, Plant, Cook) |
| Alchemist violet | `#AA8BCF` (`--violet-400`), plum `#6E4A78` | magical actions (Brew), the Apothecary, the Hollow |
| Deep cocoa | `#3B2923` text, `#473025` / `#4A2A14` outlines | text and outlines |

**Three levels of framing**, so not every rectangle wears a thick border:
1. **Window**: a carved 9-slice frame with brass rivets and leaf sprigs (modals and sheets, the Bag,
   the Market, the encounter's action panel). A few per screen at most.
2. **Card**: printed card stock (paper grain, a thin double rule, a thick bottom edge): the content you
   act on. **Slots** (item tiles, equipment boxes) are inset pockets with a gold ring when chosen.
3. **Inset**: a pressed-in parchment panel holding plain rows split by stitched rules
   (`.card.inset`, `.mini-list`): secondary information, finished quests, what's coming next.

**Four window variants** share the type, buttons, spacing and icons, and each gets an accent:
- **Standard wood and parchment**: Home, Bag (satchel canvas and stitched pockets), Market (awning,
  shelf cards, prices on wooden tags), Village and Trail Guild (a notice board with pinned papers).
- **Journal**: story quests, discoveries, EvoDex, Skills (ruled pages, leather bookmark tabs).
- **Crafting / workbench**: Kitchen (warm, recipe cards), Apothecary (plum wood, lavender paper),
  Farming. Cooking and brewing happen at the station: choosing a recipe pushes the camera in on the
  oven or cauldron, the ingredients drop in, the timing gauge plays over the fire, and the dish pops out
  before the reward card (`u.cook` in `screens/homeland.js`; a fuller minigame can replace the gauge).
- **Encounter / adventure**: battle, encounter preparation, rewards, and next the Wilderness HUD.

**Signs and controls**: page titles are nailed wooden plaques; back and square buttons are light wood;
the coin purse is dark wood; tabs are wooden plaques whose chosen one lifts and lights; the bottom nav
is a carved wooden bar. Buttons have a dark outline, a gloss strip and a thick edge, and sink when
pressed. Section heads get a leaf bullet and a stitched rule; progress bars are carved grooves;
switches are brass knobs in a groove.

**Readability**: nothing below 12 px; secondary text is 13 px. Profile > Larger text raises labels,
descriptions and item text across the game. Profile > Developer tools hides the web preview's step
simulator and playtest shortcuts, so you can see Evochi as players will.

The materials are painted procedurally: `python3 tools/ui_textures.py web/public/assets/ui` writes the
wood planks, paper grain, canvas weave and the four frames (wood, plum, leather, canvas).
`tools/ui_tour.mjs` screenshots every screen with a seeded mid-game save for reviews.

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
python3 build_village.py ../../assets                    # quest items, mantle, decor
# village scenes and villagers are lit in Blender: a Python with the bpy module (pip install bpy, Python 3.13)
<bpy-python> village_blender.py ../../assets/village all --meta scenes.json --raw /tmp/village_raw   # ~70 min on 2 cores
BPY_PYTHON=<bpy-python> python3 build_village.py ../../assets npcs                                 # ~25 min on 2 cores
python3 build_web_assets.py ../../assets ../../web/public/assets <fontsource-dir>
python3 build_web_assets.py ../../assets ../../web/public/assets --village-only   # just the Village Tales art
python3 home_items.py ../../assets                                                   # home items, skill icons, crop sprites
<bpy-python> village_blender.py ../../assets/home home_map_ruined home_map_restored garden kitchen apothecary cottage_ruined cottage_restored --meta scenes.json --raw /tmp/home_raw   # ~40 min on 2 cores
python3 build_web_assets.py ../../assets ../../web/public/assets --home-only      # just the Home Tales art
python3 trail_art.py ../../assets                                                    # creatures, trail items and icons
<bpy-python> village_blender.py ../../assets/trails mossy_ruins mossy_ruins_hollow sentinel_gate --meta scenes.json --raw /tmp/trail_raw   # ~15 min on 2 cores
python3 build_web_assets.py ../../assets ../../web/public/assets --trails-only    # just the Lumen Trails art
# the encounter shots: your Evochi from behind, the creatures turned toward it, backdrops + foreground layers
python3 build_characters.py ../../assets/characters --battle                         # ~6 min
python3 trail_art.py ../../assets battle icons sun purify nudge moon swirl
<bpy-python> village_blender.py ../../assets/trails mossy_ruins_battle mossy_ruins_battle_fg mossy_ruins_hollow_battle mossy_ruins_hollow_battle_fg sentinel_gate_battle sentinel_gate_battle_fg --meta scenes.json --raw /tmp/trail_raw   # ~25 min on 2 cores
python3 build_web_assets.py ../../assets ../../web/public/assets --battle-only    # battle views, backdrops, creatures, icons, encounter music
```

The models live in `characters.py` and `accessories.py`, and the palettes in `palettes.py`. The
villagers are in `village_npcs.py`, the quest items and rewards in `village_items.py`, and the
Square, the interiors and the Waystone in `village_scenes.py`.

Everything is rendered by the small voxel renderer in `voxel.py` (flat-shaded faces with outlines),
except the village scenes and villagers. Those are built from the same voxel models but rendered in
Blender (Cycles): `village_blender.py` lights the rooms with their own lanterns, forge and sun, and
`village_npc_render.py` + `npc_blender.py` stand each villager inside their room (hidden from the
camera, so it only lights them) at the spot and size the game draws them.

- The villagers are rendered part by part (body, head per expression + blink, arm). The parts are
  tagged in `village_npcs.py`, which also holds their pivots and the idle/talk/listen keyframes
  (`NPC_ANIM`).
- Their shading uses smoothed normals, and a smooth stand-in casts their shadows, so voxel steps never
  shade themselves.
- The painted faces become a projected texture.
- The outline and inner lines still come from the flat renderer and are shared out to the parts.
- A "classic" flat-shaded set of the same layers is written alongside for the setting.

Blender jobs need only bpy + numpy (rooms travel as packs from `scene_pack.py`), so they also run in a
stock Blender: `blender -b --python npc_blender.py -- NAME.npz WORK --gpu`. `--gpu` uses OptiX, CUDA,
HIP (AMD), Metal or oneAPI when present.
Change a model or palette there and every sprite, overlay and turnaround regenerates consistently.
