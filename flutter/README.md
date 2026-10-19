# Evochi: Flutter client

Evochi is a cozy pet that grows from your steps. This folder is the iOS/Android client, built to the
*Evochi Complete Game Design, UI/UX & Style Guide v1.2*.

> **Status: written without a Flutter SDK, so it has never been compiled.** I wrote it in an
> environment that couldn't download Flutter. Every Dart file passes a syntax check and every
> project-internal import resolves, but `flutter analyze` and `flutter test` have **not** been run.
> Run them first and expect to fix a few small type or API details. The likeliest spot is
> `lib/data/health_adapters/health_step_source.dart` if your `health` package major differs from the
> one pinned. The game rules match the web build, and those rules *are* tested in `../web/test`, mirrored in
> `test/engine_test.dart`, `test/story_test.dart` and `test/home_test.dart`.

## Getting it running

```bash
cd flutter
flutter create --platforms=ios,android --project-name evochi --org com.example .   # generates ios/ and android/
flutter pub get
flutter test            # engine + QA-matrix tests (test/engine_test.dart)
flutter run
```

Then apply the platform snippets:

- **iOS:** paste `platform/ios/Info.plist.snippet.xml` into `ios/Runner/Info.plist` and enable the
  **HealthKit** capability in Xcode.
- **Android:** merge `platform/android/AndroidManifest.snippet.xml`. Set `minSdkVersion 26`, and make
  `MainActivity` extend `FlutterFragmentActivity`.

## Structure (style guide §21)

```
lib/
  app/            constants (versioned balancing config), theme tokens, router, app shell
  controllers/    GameController: state owner, action runner, step sync, event fan-out
  core/models/    GameState contracts (§22) + starter catalog (§18)
  core/utils/     account-time-zone day keys (§15, Q11), ids
  core/services/  art manifest + atlas cache, audio, privacy-conscious analytics
  game/           pure rules: xp/ (XP, levels, step aggregation), vitality/, evolution/, bond/, story/,
                  home/ (Home Tales), engine.dart
  data/           local store, repository, remote sync boundary, health adapters
  features/       onboarding, nest (+ memorial), journey, pet (details + evolution), bag, shop, evodex, settings,
                  village (Village Tales), home (Home Tales)
assets/
  art/            voxel atlases, habitats (parallax layers), items, icons, titles, manifest.json
  audio/          sfx/ and ambient/
  config/         balance_v1.json (all §15-18 numbers), catalog_v1.json
  fonts/          Nunito + Lato (OFL)
```

## Rules engine

The rules all live in `lib/game/engine.dart` and its modules. They are pure functions,
`(state, ..., now) -> ActionResult`, that never mutate their input:

- **Activity XP** = `floor(100·min(S,G)/G)` + milestones (25/50/100% → 10/15/25) + stretch XP (max 20).
  So 4,850 of 7,000 steps gives 94 XP.
- **Level curve:** `roundToNearest10(120 + 40(L-1) + 4(L-1)²)`, computed from lifetime XP.
- **Evolution:** Juvenile needs level 10 and 7 active days; Elder needs level 25 and 21 active days.
  The player starts it, and it can be skipped at any point without losing anything.
- **Vitality** is replayed from history, so it's idempotent:
  - Reaching half your goal gives +8; reaching your full goal gives +14 instead.
  - A day under 25% of goal costs −8, but only after a 48 h grace period and once that week's two
    protected rest days are used up.
  - Missing sensor data counts as "pending", not as inactivity.
  - Late data reverses an incorrect penalty.
- **Bond:** +2 for the first pet of the day, +3 for the first play, +1 for meeting the goal. Direct
  interactions are capped at +5 a day.
- **Economy:**
  - One earnable currency (EvoCoins). Gems stay hidden at MVP.
  - The wallet is an append-only ledger with unique transaction ids, so claims and purchases are
    idempotent.
  - Chest rolls are seeded per claim.
  - Manual steps never unlock chests or cosmetic chances.
- **Step sync** de-duplicates samples by id and by 15-minute buckets across sources. Old samples are
  compacted into daily totals so saves stay small.

## Village Tales, Chapter 1

The story chapter from the *Village Tales Quest Bible v1.0*, ported from the web build (where it is
played and tested end to end).

- **Rules** live in `lib/game/story/`:
  - `story_data.dart` holds the cast, the places, the quest materials and the three quests.
  - `story.dart` holds step crediting, acceptance, hand-ins, the once-only payout and the views.
  - `dialogue.dart` holds the Bible's lines by ID and the conversation graph for each state.
- **State** is `GameState.story` (`lib/core/models/story_state.dart`). It uses the same JSON as
  the web save, belongs to the account and survives a memorial or a new pet.
- **Screens** live in `lib/features/village/`:
  - `village_screen.dart` holds the Square, the three interiors, the Waystone and dialogue.
  - `story_widgets.dart` holds quest details, the reward card, the Journey Story tab, the Bag Quest
    Pouch and the Home story chip.
- **Entry points:**
  - **Visit Village** on Home.
  - **Journey > Story**.
  - **Bag > Pouch**.
  - Pushed Village screens switch tabs through `GameController.goTab`.
- **Story rewards** (`reward_*` in `catalog.dart`) have `acquisition: 'story'`, no shop and no
  price. `purchase` refuses them with `not_for_sale`, and the weekly cosmetic roll skips them.
- **Manual steps:** `StoryConfig.countManualSteps` (default `true`) lets manual entries count
  toward story walks.
- **Tests:** `test/story_test.dart` mirrors `../web/test/story.test.mjs`, including the Bible's 10
  acceptance tests.

## Home Tales

The home loop from the web build (where it is played and tested end to end): walk, grow, cook and
brew, then share with your Evochi or a villager. Like the story, it is **uncompiled here**: every file
passes the syntax check and its imports resolve, but `flutter analyze` / `flutter test` have not run.

- **What it is:**
  - **Home Map** (Explore Home on the Nest): the nest, the Garden, the Cottage and the Village Gate,
    plus a one-time starter-seed gift.
  - **Garden:** four beds (the fourth at Farming Lv 4). Crops grow on real time; steps walked after
    planting add up to 60% more, watering adds 15%, and a Sprout Tonic adds 50%. Ripe beds harvest
    with one tap.
  - **Cottage:** restored by the Home Tales quest "A Place to Call Home" (Bram), which opens the
    **Kitchen**. "Mira's Mortar" opens the **Apothecary**. Both rooms share one screen: recipe cards
    and a skippable timing game, where a perfect stop makes a double batch and +50% skill XP.
    Ingredients are never wasted.
  - **Cozy Skills:** Farming, Cooking and Alchemy, with a milestone chart (the Skills screen and
    Journey > Skills).
  - **Side stories:** "The Shy Visitor" (Pip) and "Guardian of the Old Grove" (Alder, needs a
    Juvenile). They are always optional.
  - **Homemade treats:** they add Bond +1 once a day, even at full vitality.
- **Rules** live in `lib/game/home/home.dart` (crops, beds, growth, recipes, skills, milestones,
  actions). Quest changes live in `lib/game/story/`:
  - quests `hq01`, `hq02`, `sq01` and `sq02`, with `consumeItems`, `requireStage`, skill gates and
    walk-less quests
  - next-step kinds `gather` and `grow`
  - gifts and unlocks in rewards
  - the new dialogue
- **State** is `GameState.home` (`lib/core/models/home_state.dart`). It uses the same JSON as the web
  save (`state.home`). Old saves get a fresh one on load.
- **Screens** live in `lib/features/home/`:
  - `home_map_screen.dart`
  - `garden_screen.dart`
  - `cottage_screen.dart`
  - `station_screen.dart`
  - `skills_screen.dart`
  - `home_widgets.dart`: navigation (`goHome`), strips, the quick seed shop and the Skill-up card.
    The Skill-up card is shown by `SkillUpListener` through `rootNavigatorKey`.
- **Elsewhere:**
  - **Bag > Pantry:** seeds and ingredients.
  - **Shop > Garden:** seeds, x1/x3/x5, with Plant now.
  - **Village dialogue:** routes to the Garden, Cottage, Kitchen and Apothecary.
  - **Journey > Story:** lists Home Tales and Side stories.
  - **Settings > Playtest tools > Home Tales:** skip time, skip to Home Tales, seeds, and skill levels.
- **Art:** the manifest's `home` block (`HomeArt` in `asset_manifest.dart`), served from
  `assets/art/home/`. That folder must exist, or the build reports a missing asset directory (the art sync fills it). Until the Cottage close-up
  lands, the Home Map, framed on the cottage, stands in.
- **Tests:** `test/home_test.dart` mirrors `../web/test/home.test.mjs`. It adds a save round-trip
  check and a check for the playtest shortcut.

## Lumen Trails

The Trail Guild's daily discoveries, the trail jobs (encounter quests) and the encounters themselves,
ported from the web build (where they are played and tested end to end). Like the rest of the game
logic it is **uncompiled here**: every file passes the syntax check and its imports resolve, but
`flutter analyze` / `flutter test` have not run.

- **What it is:**
  - **Discoveries:** three authored, deterministic picks a day (per account and day; never two at the
    same place). Begin one, walk, then inspect the glinting clue at its place for coins, items and
    Guild XP. Guild ranks: Wanderer, Trail Friend, Pathfinder, Lightkeeper, Trailwarden.
  - **Trail jobs:** `eq01` The Forest Guardian (befriend Petalune at the Mossy Ruins), `eq02` Tangled
    Lumen (restore the Hollow Sprout; Glowleaf required) and `eq03` The Forgotten Sentinel (a boss
    with a second phase at the Old Gate; Lantern Tonic required). They live in the story engine
    (line `trail`); the encounter is the hand-in.
  - **Encounters:** a seeded, turn-based state machine. Befriend fills Calm to 100; Restore brings
    Instability to 0. Lumen Glow (x1.3 on the Hollow, x1.25 more once the Sentinel wakes), Gentle Nudge
    (makes a wild one curious), Soothe (+30 Energy), items (liked ones x1.5) and a befriended
    Petalune's Petal Hush once per encounter. Your Evochi never faints; Retreat returns every item used.
- **Rules** live in `lib/game/trails/trails.dart` and mirror `../web/src/game/trails.js` exactly: the
  FNV-1a + mulberry32 RNG (the same stream for the same seed, so an attempt replays the same way on
  both clients), the `encounter_turn` events (`you`, `wild`, `mood`, `drain`, `kind`, `item`, and a
  final one with `final: true` on the winning move before `encounter_won`), and `completeEncounter`,
  which runs the quest's hand-in and emits `companion_joined`.
- **State** is `GameState.trails` (`lib/core/models/trails_state.dart`), the same JSON as the web save
  (`state.trails`). Old saves get a fresh one on load.
- **Screens** live in `lib/features/trails/`:
  - `guild_screen.dart`: the Guild Board (rank, lore, today's discoveries, trail jobs, friends).
  - `trail_place_screen.dart`: the Mossy Ruins and the Old Gate (scene, residents, the clue glint).
  - `prep_screen.dart`: the place header with a look-around button, the scene banner, the quest card
    with its checklist, your team, the recommended item (Change / Make), rewards, and Prepare & Enter
    (or Talk to / Go for a walk / Make X / Continue the encounter for a live one after a relaunch).
  - `travel_screen.dart`: the trip (three lines over the panning scene), then the encounter with its
    intro.
  - `encounter_stage.dart`: the battle shot. `shotGeometry` is a verbatim port of the web's (fractions
    of the 2:3 backdrop; your Evochi's width per stage, its face kept left of the wild one). The
    stage is a widget tree driven imperatively through `EncounterStage` (a `ChangeNotifier` holding
    the camera shot, the sprite states and expressions, one-shot reactions, shakes, punches, flashes,
    the letterbox/aura/eye flags and the few widget effects), so camera moves and effects never
    restart when the state re-renders. Everything that moves inside the world reads one `StageClock`
    (a `Ticker` the view hands the stage), and `hitstop(ms)` holds that clock and the effects still,
    like the web pausing every running animation; a reaction fired right after a hit-stop plays
    through it. Layers, bottom to top: backdrop, aura, back effects, the wild one, your Evochi (the
    untrimmed battle frame plus equipped wearables, `BattleSprite` in `shared/sprite.dart`), the
    foreground layer (parallax), front effects, widget effects (numbers, the "?" bubble, Petalune),
    grade, flash, dust, plates, ribbon and caption; the title and the skip pill sit over the
    letterbox. Camera shots: wide, pet (1.16), wild (1.13, with the foreground at 1.09 and your Evochi
    nudged), close (1.55) and face (2.3) as a transform on the clock (1 s eased; 0.34 s for the
    'fast' beats of a turn; a cut when instant), plus the camera punch toward the wild one or your
    Evochi. The sprite reactions mirror the web's keyframes with their timing function eased per
    segment (hit with its two hard white-silhouette frames, perk, munch, the wild lunge, pop with the
    born fade-in, dissolve to white, look, skitter, tilt, surge, flicker, joy; cast, lunge, rest,
    toss, hurt, flinch, hop).
  - `stage_fx.dart`: `StageFx`, the port of the web's canvas effects engine: particles drawn from
    pre-rendered soft sprites (glow, dot, puff, star, shard, petal, heart, smoke) with additive light
    on two `CustomPaint` layers (`StageFxPainter`, back and front), movers (comets with an optional
    spinning item head and `onArrive`, shockwave rings, turning rays, the vignette pulse, the
    dissolve emitter, petal streams that orbit their target), the ambient motes (gold over the grove,
    violet Hollow embers around the wild one, brighter gold once won) and `freeze(ms)` for the
    hit-stop. Positions are fractions of the world box; sizes and speeds are in 1% of its width.
  - `encounter_screen.dart`: the phases (intro, card, play, outro, result), the intros on the same shot
    (rare, hollow and the Sentinel's awakening, 8.2 s, with the eye flashes, embers, rings, shards,
    smoke and pulses), `_runTurn` (the web's four beats and timings: wind-up, action, impact fired by
    the projectile's arrival with a timer fallback, recovery; hit-stops of 100/80/60 ms, punches,
    shakes; the number pops before the meter tweens over 380 ms; x0.35 and no canvas effects with
    reduced motion), the finish choreography (the Hollow dissolves into motes under turning rays and
    the restored creature pops back in; a befriended one bounces under hearts and confetti), the
    idle life between turns (a blink every 2.4-5 s, the wild one glancing about), the panel (log
    card with history, the action grid with cost chips, retreat), the goal card, the result (rewards
    row, EvoDex card, Continue) and the item picker. The panel is measured after each frame and the
    view ends 20px above it, like the web.
  - `trails_widgets.dart`: navigation, tags, the rank card, discovery rows and cards, the clue glint,
    the creature card, the friends panel, the trail quest rows, `EncCta` and the reward tiles.
- **Audio:** `AudioService.setMusic(name)` crossfades the loop (null = the meadow ambience,
  `enc_wild_loop` / `enc_boss_loop` for encounters, `'none'` for silence) and `play` has the new
  cues (`enc_rumble`, `enc_awaken`, `enc_glow`, `enc_whoosh`, `enc_soothe`, `enc_surge`).
- **Art:** the manifest's `trails` block (`TrailsArt`: scenes, creatures, `battle`, `battleCreatures`)
  and each form's `chars.sNN.battle` entry (`BattleEntry`), served from `assets/art/trails/` and
  `assets/art/chars/`. Art packs without the battle shots fall back to a plain stage.
- **Simplified relative to the web:** CSS filter effects (brightness, saturate) are colour
  matrices and the white-silhouette flash is a `srcIn` colour filter; the eye glow's `screen` blend is
  a canvas blend; the Hollow silhouette's rim is a radial glow rather than an alpha-shaped shadow; the
  implicit fades inside the world (the aura's opacity, the eye glows, the sprite-state crossfade) are
  not held by a hit-stop; the canvas sprites are 96 px `ui.Image`s rather than 64 px canvases; there is
  no slow-motion capture hook. Everything else (timings, shots, numbers, texts, effects) follows the
  web.
- **Tests:** `test/trails_test.dart` mirrors `../web/test/trails.test.mjs` (the catalog guard, the
  deterministic day board and old-save migration, a discovery's begin/walk/inspect, Guild ranks, the
  three trail jobs end to end including startEncounter gating, the liked-treat/retreat refund case,
  and the dialogue sanity check).
- **Asset sync:** `python3 <scratchpad>/sync_flutter_assets.py` copies the art (icons, items, `home/`,
  `trails/`, the battle atlases and overlays under `chars/`) and the audio from
  `../web/public/assets`, and merges the manifest keys (`home`, `trails`, `chars.sNN.battle`, new
  `icons`, `items` and `audio` entries). Flutter keeps loops under `assets/audio/ambient/` and
  one-shots under `assets/audio/sfx/`.

## Accounts and cloud

`data/remote/remote_sync.dart` defines the server boundary: pull/push snapshot, server-confirmed
ledger appends, and account deletion. The app ships with `NoopRemoteSync` (guest and local email
profiles). To add Apple/Google sign-in and cloud saves:

1. Add Firebase Auth and Firestore.
2. Implement `RemoteSync`.
3. Pass it to `GameRepository(remote: ...)` in `main.dart`.

The welcome screen's Apple/Google buttons explain this and fall back to guest play until then.

## Regenerating art

All art comes from the Python voxel pipeline in `../tools/art`:

1. `build_characters.py`, `build_items.py`, `build_scenes.py`, `build_decor.py`, `build_village.py`,
   `wordmark.py` and `sfx.py` write the masters to `../assets`.
2. `build_web_assets.py` packs them into the atlases and `manifest.json`.
3. Copy that output into `assets/art`.
