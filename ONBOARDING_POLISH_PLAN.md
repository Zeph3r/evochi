# Onboarding polish and character emotion: audit and plan

Two briefs, one plan: the onboarding animation / cinematic / UI polish pass, and a personality-aware emotion and
expression system for Pip, Mira and the player's Evochi. Audited 31 Oct 2026 against `flutter/` (the app) and
`tools/art/` (the art pipeline). Paths below are real; nothing here changes gameplay, step tracking, persistence
or the six affinities.

## What makes it feel flat

1. **Hard cuts everywhere.** `RootGate` (`lib/app/router.dart`) swaps every onboarding screen with a cut; the
   cold open's shot crossfade (`xfade`) never runs because `_prevFrame` is never set; panels (`SpeechCard`, the
   hatch card phases) appear and swap instantly.
2. **Still characters.** Pip and Mira are single Cycles plates (`pip`, `nest_empty`) with a slow camera drift;
   nobody blinks, turns, gestures or reacts while they speak.
3. **A hatch with no build-up.** From the tap to a creature is 0.65 s: a 0.25 s flash, 14 rectangle "shards", 22
   motes (`_EggPainter`, `onboarding_beats.dart`); the shell-piece plates (`egg_shards_*`) are rendered but unused.
4. **Dialogue is text, not a performance.** `SpeechCard` has no entrance, no reveal, no link to a face.
5. Fixed already (31 Oct): reveals never masked (the whole lit map showed at once), raised footprints, the egg
   drawn off-screen on the hatch screen, Welcome stalling after the cold open.

## Architecture map

| System | Files | Today | Planned |
|---|---|---|---|
| Opening cinematic | `features/onboarding/cinematic_player.dart` (`_CinePainter`, `CineTimeline`, `CineCamera`, `FootTrail`), `cinematic_screen.dart`, `assets/art/cine/onboarding_cine.json` from `tools/art/onboarding_cine.py`, plates from `tools/art/cine_scenes.py` | 7 shots over Cycles plates, eased pans and zooms clamped to the plate, reveals, footsteps, captions, 3 sound cues; cuts between shots; repaints every frame with blurred masks | working shot crossfades; captions laid out once; ambient Lumen motes; parallax only where a plate is rendered in depth layers (the village push); reduced-motion path |
| Pip / Welcome | `onboarding_screens.dart` `WelcomeScreen._pipLetter`, plate `pip` | still plate, 9 s drift, text card | **needs a decision (A):** Pip rendered as layered poses (entrance, breathing, blink, head tilt, presenting the letter) over a Pip-less Lodge plate |
| Egg pick | `onboarding_beats.dart` `EggPickScreen` | lift 520 ms easeOutBack with a glow, Elder glimpse panel, card swap | egg wobble on pick, a selection ring and label (not colour alone), guard against rapid re-picks, selection haptic |
| Hatch | `onboarding_beats.dart` `HatchScreen`, `_EggPainter`, `_MapBeat`; `shared/scene_view.dart` `react('hatch')` | ring fills with steps, crack stages 0-3, 0.65 s burst, `excited/hop`, naming card, map beat | a data-driven 4 s timeline (below) built from the existing egg crack sprites, shell plates, sounds and haptics; the ticker moved off whole-screen `setState` |
| Buttons | `shared/widgets.dart` `EvochiButton`, `shared/kit.dart` `Kit.button` | default, pressed (60 ms, 3 px sink, gradient swap), disabled; no loading, focus or success; press ignores reduced motion | loading and success states, focus ring, a 150 ms eased release, reduced motion respected |
| Panels and sheets | `GameCard`/`Kit.card`, `showEvochiSheet`, `SpeechCard`, `KitDialog` | rich materials (grain, bevels, inset shadows, 9-slice frames); no entrance or exit motion | a shared `Entrance` (fade and rise, 280 ms ease-out) on cards and speech; fade-through between onboarding steps in `RootGate` |
| Particles | `shared/live_scene.dart` (`SceneFx`, stateless atlas particles), `scene_view.dart` `_burst`, onboarding painters, `FootTrail` | cheap and stateless; no global cap or quality tier | a quality tier (auto, with a developer override) read by the particle code; caps |
| Camera | `CineCamera.fit`, `village_walk.dart` `_follow`, Wilds camera | all clamp to their maps already | a small impulse helper for the hatch burst (off under reduced motion) |
| Audio and haptics | `core/services/audio_service.dart`, `core/services/haptics.dart` (29 named feels) | rich; hatch uses 2 cues | hatch phases cued from existing sounds (`enc_glow`, `enc_rumble`, `enc_awaken`, `pet_chirp`, `evolve_fanfare`) and feels |
| Accessibility | `app/app.dart` folds the in-game toggle into `MediaQuery.disableAnimations` | 4 places read only the OS flag (`onboarding_beats.dart` hatch timer, `onboarding_screens.dart` Awakening, `shared/acting.dart`, `home/nook_sheet.dart`) | read `MediaQuery` everywhere; reduced-motion versions of every new motion |

## Emotion system: extend, don't duplicate

What exists already, and what it becomes:

- **One face resolver**: `HabitatScene._expression()` (`scene_view.dart`) with a priority stack (forced face,
  health, sleep, reaction, idle glance, blink), and `SceneController.react(kind)` with a `[expr, motion, ms,
  particles]` table and `_Reaction(expr, motion, start, dur, exprEnd)`.
- **A personality-aware selector**: `game/personality/` (`Personality` with five continuous traits, `catalog.dart`
  `BehaviorDef` with `expr`/`exprEnd`/`motion`/`clip`, `director.dart` `BehaviorDirector` with repeat penalty and
  a barely used `Mood`).
- **Authored dialogue faces**: `game/story/dialogue.dart` `Line.expression`, shown by `Chathead`/`NpcPuppet`.
- **Faces in the atlases**: Evochi have default, blink, happy, curious, surprised, determined, sad, sleepy,
  excited, neutral (plus sick, memorial); villagers neutral, happy, worried, thinking, proud; Flint his own five.

The plan adds one layer on top, not a second system:

1. `assets/config/emotions.json` + `game/emotion/emotion.dart`: the eleven emotions as data (face per character
   kind with fallbacks, posture/motion, priority, default duration, transition speed, optional sound, particles,
   and a `next` chain such as surprised to afraid to relieved to neutral). Adding one is a JSON entry.
2. `SceneController.feel(emotion, intensity, source)`: resolves to the existing `_Reaction`, scaled by the pet's
   traits (expressiveness and energy set amplitude and tempo, curiosity the glance rate) through the
   `BehaviorDirector` (seeded variation, cooldowns). Priority lets hatch and story beats override idle reactions
   and expire cleanly when a screen goes.
3. Gameplay hooks from events the controller already raises (`treat`/`used`, `discovery_found`,
   `story_completed`, `recovered`, `evolved`, nest pet/play, sleep and wake); no new mechanics.
4. Dialogue: an optional `gesture` and `intensity` on `Line` (absent means today's behaviour); `SpeechCard` gains
   a speaker face for onboarding.
5. A developer emotion preview inside the existing `settings/personality_lab.dart`: character, emotion, intensity,
   personality profile, variation seed, transition time.

Personality: the runtime model is five continuous traits with three catalog profiles (cautious, lively, calm);
the face kit's six (brave, timid, stubborn, playful, curious, calm) are art variants mapped by
`UltArt.variantFor`. Animation tendencies are driven by the traits, so no category is invented or renamed.

## Hatch timeline (data-driven, about 4 s)

One `HatchTimeline` with per-affinity parameters (glow colour from `AFFINITY_GLOW`, burst pattern, sound, the
Eggling's personality reaction), shared by all six eggs:

| Phase | Time | What happens |
|---|---|---|
| A, quiet | 0.0-0.6 s | ambient motion eases down, a faint inner glow, `enc_glow` |
| B, shaking | 0.6-1.3 s | irregular seeded shakes with pauses and small turns, building; light haptic ticks |
| C, cracks | 1.3-2.0 s | the existing crack sprites step up, affinity light leaks, a few rising motes, `enc_rumble` |
| D, burst | 2.0-2.3 s | flash, the rendered shell pieces (`egg_shards_*`) thrown out, a small camera impulse, `enc_awaken`, a stronger haptic |
| E, reveal | 2.3-3.1 s | the Eggling rises with anticipation, overshoot and a soft landing (squash on the sprite, no mesh distortion) |
| F, payoff | 3.1-4.0 s | blink, a curious look around, notices you, its personality reaction; a moment of quiet before the name card |

It plays once (guarded), cleans up on leaving, survives backgrounding, and grants nothing itself (the hatch state
is already saved by the engine).

## Phases

1. **Foundation**: `lib/app/motion.dart` (duration and easing tokens, reduced-motion helpers), the 4 OS-flag
   reads fixed, `Entrance` widget, fade-through in `RootGate` for the onboarding steps, the cold open's shot
   crossfade.
2. **UI polish**: button loading, success and focus states and an eased release; speech cards that enter and
   reveal (tap to complete); egg-pick selection ring, label and wobble.
3. **Hatch**: the timeline above, all six eggs, verified by recording.
4. **Characters**: the emotion layer, gameplay hooks, the preview; Pip and Mira per decision A.
5. **Cinematic environment**: ambient motes, depth layers where rendered, light that travels.
6. **Final pass**: transitions, particle tiers, performance numbers from the recorder and a real phone, reduced
   motion, before/after recordings.

Every batch is checked by recording the real app (`tool/shorts/onboarding_record_test.dart`, `ONB_UNTIL` for a
quick part) and by `flutter analyze` and the test suite on the PC.

## Decisions to make

- **A. Pip and Mira in motion.** Recommended: render them as layered pose sequences in Blender on the PC's GPU
  (entrance, breathing, blink, head tilt, presenting the letter or the egg), composited over plates rendered
  without them, so they keep their exact Cycles look. The alternative is a gentle 2D breathing warp on the
  current plates: cheaper, much less alive.
- **B. Three more faces.** The brief's emotions afraid, frustrated and affectionate have no face in the Evochi
  atlases. Recommended: paint them in the existing face pipeline (`tools/art/characters.py`) and rebuild the
  atlases (designs unchanged, three faces added); until then they fall back to surprised, determined and happy.
- **C. A visual quality setting.** Recommended: automatic, with a developer override, no new player-facing toggle.

## Product proposals (not to be built without approval)

Worth testing for retention: delaying account creation until after the hatch (guest start already exists),
moving the daily goal after the first hatch, letting the first hatch happen before step access (the "Hold the
egg" path already allows it), and a short first quest straight after naming.
