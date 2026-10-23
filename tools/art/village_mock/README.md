# The walkable Sunlit Village: concept

The village re-laid out to walk through with the Wilds camera, before it is built. These are pictures of the
plan, not the game.

- `../village_walk.py` builds and renders the 3D village: the buildings spaced out round the plaza, the Old
  Trail east to the Crossing, and the waterfall pouring off a rock cliff into the pool and creek.
  `python3 village_walk.py OUT --view falls|plaza|workshop|road|all|zoom_hd|zoom_talk`
- `fx_village_walk.py` holds the living-scene zones (water, trees, grass, smoke, glows, cloth, leaves, motes),
  worked out from the layout. Bake them into a copy of the json with
  `scene_fx.py --zones tools/art/village_mock/fx_village_walk.py --json OUT.json village/walk_falls.webp`.
  The PC records a living scene with `flutter/tool/shorts/live_test.dart` (the `_transfer/run_live.flag` helper).
- `village_concept.py` makes the boards (views, map, Flint). `zoom_concept.py` makes the camera study.

## Decided

- **Camera:** walk at 2x, so the view is 18 world units wide. Ease in a little more for a conversation.
- **Evochi:** drawn 1.2x its true size in the village only. The Wilds keep their size.
- **Villagers:** the classic set (flat, even light, dark outline), which matches the Evochi. It is the game's
  default now; room-lit is an opt-in setting.
- **Shadows:** every character casts the day sun's shadow, up and to the right like the trees and buildings,
  drawn 2x long so it reads. The Evochi also gets a soft pool of shade under its body.
- **No labels on buildings.** Names show when you tap or walk up. The places row becomes a quick-travel row.
