# Evochi: Flutter client

Evochi is a cozy pet that grows from your steps. This folder is the iOS/Android client, built to the
*Evochi Complete Game Design, UI/UX & Style Guide v1.2*.

> **Status: written without a Flutter SDK, so it has never been compiled.** I wrote it in an
> environment that couldn't download Flutter. Every Dart file passes a syntax check and every
> project-internal import resolves, but `flutter analyze` and `flutter test` have **not** been run.
> Run them first and expect to fix a few small type or API details. The likeliest spot is
> `lib/data/health_adapters/health_step_source.dart` if your `health` package major differs from the
> one pinned. The game rules match the web build, and those rules *are* tested: 23 passing tests in
> `../web/test`, mirrored in `test/engine_test.dart`.

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
  game/           pure rules: xp/ (XP, levels, step aggregation), vitality/, evolution/, bond/, engine.dart
  data/           local store, repository, remote sync boundary, health adapters
  features/       onboarding, nest (+ memorial), journey, pet (details + evolution), bag, shop, evodex, settings
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

1. `build_characters.py`, `build_items.py`, `build_scenes.py`, `build_decor.py`, `wordmark.py` and
   `sfx.py` write the masters to `../assets`.
2. `build_web_assets.py` packs them into the atlases and `manifest.json`.
3. Copy that output into `assets/art`.
