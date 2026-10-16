# Next steps (handoff)

The latest work is commit "Village: storybook dialogue, animated villagers with new poses, room-lit in
Blender". README.md covers the project, the art pipeline and how to build.

## Not verified yet

- **Flutter build.** The Flutter side of that commit was only syntax-checked, never compiled. Run
  `flutter pub get`, `flutter analyze` and `flutter test` in `flutter/`, then open a place (Village →
  any building) and compare it with the web build. Files touched:
  - `lib/features/village/village_screen.dart`: the place screen, `_StageNpc`, `_SpeechBox`, typing
  - `lib/features/village/npc_puppet.dart`: the layered, animated villager
  - `lib/core/services/asset_manifest.dart`: `NpcPuppetArt`, `PuppetLayer`, `PuppetAnim`
  - `lib/core/models/game_state.dart`: the `classicVillagers` setting
  - `lib/features/settings/settings_screen.dart`, `lib/features/village/story_widgets.dart`
- The web build is the reference. Run `cd web && node build.mjs`, serve `web/dist`, and play. Web
  tests: `npm test` (40 pass).

## Open decisions and ideas

- Room-lit vs classic villagers: switch with Settings → Classic villagers. Bram has the weakest
  contrast when room-lit (brown on a brown workshop).
- The villager sprites are a little soft on high-DPI phones. Re-render at 1.5× by raising `NPC_SCALE`
  in `tools/art/build_village.py` from 12 to 18. Sizes on screen don't change, because the layout uses
  fractions. Then rebuild:
  `BPY_PYTHON=<python with bpy> python3 build_village.py ../../assets npcs` and the village-only pack.
  On a GPU, pass `--gpu` to `npc_blender.py` / `village_blender.py`. A stock Blender works:
  `blender -b --python npc_blender.py -- NAME.npz WORK --gpu`.
- Poses, pivots and idle/talk/listen keyframes live in `tools/art/village_npcs.py` (`NPC_ANIM`).
  Keyframe-only changes need just the web pack rebuilt, not a re-render.
