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
