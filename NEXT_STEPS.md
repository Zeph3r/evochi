# Next steps (handoff)

## Beta launch: logs, crashes, backend (the plan, 11 Nov)

There was never a written plan for this, only seams left in the code. This is the plan, what is built,
and what only the owner can do. The site's promises set the rules (site/README.md): usage events are
opt-in, step data is never sold or used for ads, sign-in with Apple, Google or email, accounts sync to the
cloud. And the standing rule: health data never reaches a backend as raw samples, only derived progress.

**Built (11 Nov):**

- `core/services/diagnostics.dart`: a ring-buffer log (`Log.i/w/e`, the last 600 lines; every product event
  goes in too, whatever the sharing toggle says, since the log only leaves the phone when the player sends it);
  `FlutterError.onError`, `PlatformDispatcher.onError` and a guarded zone round `main` writing every error down
  (`LocalCrashReporter`: the last five, with the screen and the log's tail, kept on disk); a frame watch
  (`JankWatch`: frames over 32 ms counted per screen, a log line every 10 s while it goes on); the last
  session's log tail saved with a clean/live mark, so a start after a crash knows it. `Diagnostics.cloud` is the
  seam for Crashlytics. The Wilds names its screen (`wilds` / `mine`); other screens can (`Diagnostics.screen`).
- Settings > Privacy & data > **Report a problem** (`features/settings/report_problem.dart`): what happened in
  the player's words plus the build, phone OS, screen, the last crash, the jank summary and the log, copied to
  the clipboard or handed to the mail app (`SUPPORT_EMAIL` dart-define, default support@evochigame.com).
- `android-release.yml`: uploads the Dart symbols to Crashlytics when `FIREBASE_APP_ID_ANDROID` and
  `FIREBASE_SERVICE_ACCOUNT_JSON` are set (no-op until then; the symbols are always attached to the run).

**Step 1, to finish once the Firebase project exists (one session):**

- `flutterfire configure` in `flutter/` (writes `lib/firebase_options.dart`; the Android `google-services.json`
  goes in `android/app/`, the iOS plist in `ios/Runner/` when iOS exists), add `firebase_core` and
  `firebase_crashlytics`, `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` in
  `main._main` right after `Diagnostics.install`, and a `FirebaseCrashReporter implements CrashReporter`
  (record -> `FirebaseCrashlytics.instance.recordError`, keys -> `setCustomKey`, and `Log.listen` ->
  `log()` for breadcrumbs) set as `Diagnostics.cloud`. Crashlytics collection follows the usage-events
  consent toggle (`setCrashlyticsCollectionEnabled`), and the privacy page's "crash reporter" blank gets
  filled in.
- Optional: ship `Analytics.buffer` to a Cloud Function endpoint (consented events only) rather than GA4, so
  the data stays ours and the privacy wording stays simple.

**Step 2, the backend (the biggest chunk; needs the project):**

- Firebase Auth: Apple, Google and email-link providers. Wire `_provider` / `_email` in
  `onboarding_screens.dart` (they show a "once Firebase is configured" sheet today) and a "Link account" in
  Settings; `startGuest(accountType:, email:)` already takes the account; `GameRepository` already pushes to
  `remote` for non-guest accounts once `remote.enabled` is true.
- `data/remote/remote_sync.dart`: a `FirestoreSync implements RemoteSync`. The design is in its header: a
  save snapshot per uid (`saves/{uid}`), a ledger (`ledger/{uid}/txns/{id}`) keyed by the client's own
  transaction ids (`quest:<questId>@<period>`, `purchase:<requestId>`), a Cloud Function `confirmTransaction`
  that appends once per id, and conflicts resolved from the ledger, never last-write-wins. The snapshot must be
  a whitelist of fields: derived progress and daily totals, never step samples.
- Account deletion: a Function behind `site/delete-account.html` and `deleteAccountData`; the app's
  "Delete all data" already calls the hook.
- Founders: the app can't tell a founder (the waitlist knows). At sign-in, a Function asks the site's API
  (Cloudflare D1, `site/functions/api/`, a shared secret) whether the email is a founder and sets a flag on
  the account; the app then shows `pip_gold` in the cinematic and whatever else founders get.
- Nice to have: a `config` document for a kill switch / minimum build, read at start.

**Step 3, the beta itself (mostly console work):**

- Android: Play Console app, the upload keystore and the service account as the four `ANDROID_*` and the
  `PLAY_SERVICE_ACCOUNT_JSON` secrets (never in chat), internal testing first, then closed testing with the
  waitlist's emails (a new Play account needs 12 testers for 14 days before production anyway). The Data
  safety form and the Health Connect declaration (`READ_STEPS`, gameplay) in the console; the privacy policy
  URL live (site deployed per `site/DEPLOY.md`, `config.json` filled, `legalDraft` off after review).
- iOS: an Apple Developer account, the `ios/` folder (never generated yet), Sign in with Apple (required once
  Google sign-in is offered), the HealthKit entitlement, TestFlight; builds need a Mac or a macOS runner.
- Invites: `site/emails/` has the beta invite; a small admin script exports the waitlist to the tester list.
- Feedback: Report a problem (above) plus wherever testers talk (a form, a channel).

**Owner's checklist (nothing here can be done from the repo):** create the Firebase project and commit (or
add as secrets) its config files; enable the auth providers; the Play Console app and its secrets; the Apple
account; deploy the site and fill `site/config.json`; a legal review of the privacy and terms pages.

The latest work is the fight rework: every move in four beats (wind-up, action, impact with a
hit-stop, recovery) and a canvas particle engine (`web/src/ui/fx.js`, ported to Flutter as
`stage_fx.dart`); the four encounter Shorts were re-recorded with it. Before that, the encounter rework: the battle shot (your Evochi from behind, the wild one
facing it, low Blender cameras), camera moves and ability effects, the Sentinel's awakening, encounter
music, and the encounter UI after the Encounter UI Redesign board. Before that: Lumen Trails (daily
discoveries, the Trail Guild, encounters and companions). README.md covers the project, the art
pipeline and how to build.

## The start screen (built 11 Nov, not yet the app's first screen)

`features/title/title_screen.dart` is the environment production sheet's start screen: sky, stars and moon,
drifting clouds, far hills with flickering village lights, the lake with the moon's shimmer, the Village itself
across the water (its own voxels, rendered from afar), the floating island with the sleeping Elder (a 20-frame
breathing loop, petal mane) and the props in front of her, fireflies, a shooting star, the logo and "Tap to
begin". Everything animated is one CustomPainter on one clock, gradients for every glow (no blur). The art is
`assets/art/title/` from `tools/art/title_layers.py` (its `--only=preview` draws the composed screen as a PNG,
and `LAYOUT` there is the layout the app reads from `title.json`, so composition is tuned asset-side). The logo
is `assets/brand/evochi_logo.svg` (Pixelify Sans Bold lettering, `tools/art/logo_font.py`).

- Settings > Developer tools > "Preview the start screen" shows it. It is not in the onboarding flow: the
  onboarding chat owns `RootGate` / `IntroGate` / Welcome; mounting it is `TitleScreen(onBegin: ...)` ahead of
  Welcome (and the old voxel `wordmark_evochi.webp` can give way to `titles/logo.webp` there).
- The island and the Elder are flat renders. The Blender title loop (PC, `scene/title_scene.py`) can replace
  them with the same contract: `island.webp`, `island_front.webp`, `elder_sleep.webp` strip + `title.json`.

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

- **Look.** All 55 scenes are rendered at full quality on the PC's GPU and packed in `flutter/assets/art/cine/`
  (265 WebP plates, 22 MB; analyze clean and 227 tests passing on the PC). Checked against the storyboard: the
  map's three states, the village at dusk, the Glasshouse by night, the nest, Mira, the aisle, steps, Pip; the cast
  in close-up at twice the voxel grain with smooth shadow stand-ins; the egg cracks in Lumen gold across the side
  that faces you; the Elder orbit at one distance in a landscape frame (a wide panel on the pick card). Still worth a
  look on a phone: the Hollow creep's density in motion, and whether the top band of the map plate (the dark room
  above the desk) wants a vignette or a tighter crop at zoom 1. To re-render: `cine_pack.py` into
  `blender\cine\packs\`, drop those entries from `packs\render_status.json`, run `render_cine.bat`, then
  `--regrade` from the packs and `cine_assets.py`.
- **Founders.** The app can't tell a founder yet (the waitlist knows, the app doesn't), so `pip_gold` isn't shown.
  A claim code in the beta invite, or the sign-in email matched against the waitlist, would decide it.
- **The push-in as a real camera move** (storyboard frame 6) and the Glasshouse tracking shot (frame 11): the
  app zooms the plates for now; `cine_blender.py` can render a camera path as frames (`vs.cameras`, as the
  Elder orbit does) for a pre-rendered version on the PC's GPU.

## Not verified yet

- **Flutter compiles and runs on Windows** (Flutter 3.27.1, VS 2022, 19 Oct 2026), and `.github/workflows/
  flutter-ci.yml` runs `flutter analyze` and `flutter test` on every push (11 Nov: 255 tests). The Windows
  debug build at the time: `flutter analyze` had 0 errors, `flutter test` passed 67, and the Windows debug build runs onboarding, Home, Journey,
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
