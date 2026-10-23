# The Old Trail, the mines and smithing: the plan

Source: the "Evochi Mining & Smithing Experience Design Bible" (October 2026, 27 pages, shared in chat).
This file keeps what we build from it. The bible's own rule applies: settled game rules are input; floor
numbers, item names, prices, step thresholds and enemy ecology are proposals to playtest.

## Settled (build as written)

- The Old Trail runs east of the village to the Crossing: Flint's dwelling, the mine entrance, the Sunlit
  Thicket gate. Beats: leave village -> forest edge -> rocky climb -> cliff crossing (waterfall) -> Flint.
  These are one walkable map, not separate scenes.
- Mine floors reuse the Wilds floor generator, with cave art and ore placement.
- The Pounce is the existing walk sheet posed in code (crouch -> lunge -> impact -> land). No new sprite sheet.
- Four tiers: copper, iron, lumen crystal, obsidian. They are a gear and difficulty ladder, not real
  geology. Obsidian is volcanic glass: knapped and fitted, never smelted.
- Flint sells mining gear. Bram forges Evochi gear from ore. Obsidian Evochi get a mining edge.

## Money rule (our constraint wins over the mockups)

Mockups price some gear in Glimmer. Glimmer is the premium currency, and paid things are looks-only. So:
gear with stats costs EvoCoins and ore only; Glimmer can buy looks (a finish, an engraving, a lantern
color), never light radius, mining power or carry. Steps are never sold; health data never reaches ads.

## Decisions since (in chat)

- Mining gear is its own loadout (helmet, harness, paw guards, satchel, lantern, tool), worn and shown
  only on the Old Trail and in the mines. It never takes off a wearable; a helmet only covers a hat
  while you're out mining.
- Flint sells the tools of the trade (headlamps, picks, satchels, lanterns) for EvoCoins, plus ore from
  the iron tier up; Bram forges the armour (harnesses, paw guards) from your ore. Gear sets the ore you
  can break and your mining power.
- No diamonds, and nothing that reads as a block game's ore: no grey stone with coloured specks. Each
  ore is a rounded boulder with its ore growing out of it in its own shapes (copper nodules on
  sandstone, iron ribs across rust rock, lumen buds from slate, obsidian glass shards on basalt).
- Lumen is the game's mint-green light (the Lumenbud, Lumen Shards, the Lantern Tonic); the purple is the
  Hollow that tangles the Thicket's creatures. Lumen crystal is soft glowing buds, breathing light and
  brightening as your Evochi comes near. A Hollow-tainted crystal could live in the sealed shafts.
- Ores have ambient life: lumen glows and sheds motes, obsidian has a sliding violet sheen, copper and
  iron catch small glints.

## The Pounce (one hit, ~480 ms)

| phase | ms | what happens |
|---|---|---|
| wind-up | 0-110 | crouch, squash |
| lunge | 110-195 | head drives forward |
| impact | 195-250 | the contact marker: damage, particles, sound, haptic, all fired here once |
| recovery | 250-400 | settle; queue the next hit if one is waiting |
| ready | 400-480 | visible ready state |

- Hitstop 40-55 ms, visual only; input and the rest of the scene keep running.
- Rock: 2-4 px shove, growing cracks, 3-6 chips, light dust; damage persists (whole, chipped, cracked, burst).
- Final hit: bigger crack, short burst, ore arcs in a stagger into the satchel, a small collect tick.
- Stage personality: Hatchling overcommits and tumbles happily; Juvenile brisk recoil with a crystal
  wiggle; Elder grounded, quick reset.
- Too hard: short clink, bounce, puzzled head tilt, "Needs better gear" note. Never silent, nothing lost.
- A rare find gets one memorable reaction, not a popup per hit.

Per ore (sound / haptic):
- Copper: dry stone crack + small metallic note / light, medium, heavy.
- Iron: deep thunk + faint ring / medium; heavier final.
- Lumen: rising bell, crystal chimes / short crisp, subtle trail.
- Obsidian: glassy fracture, falling bits / short precise tap + final snap.

Haptics setting: Off / Gentle / Normal. Obey mute and reduced motion. Everything must read with sound
and vibration off. Low-end devices: fewer particles, no blur; timing unchanged.

Code shape: node states Idle -> Approach -> Crouch -> Lunge -> Impact -> Recover -> Break/Collect;
`enum MiningEvent { chip, crack, shatter, collect }`; one contact handler feeds render, audio, haptics and
loot; loot is awarded atomically once on break, guarded against repeat contacts.

## Controls (no tap-spam)

- Tap ore: walk to it and face it; show the Pounce button. Don't auto-pounce.
- Tap Pounce: one committed strike; at most one queued follow-up.
- Hold Pounce: repeat, stopping on release, interruption, out of range or break.
- Bag full: ore stays collectible or an overflow flow appears. Moving away: finish or cancel before
  contact, no ghost loot. Offline: mining works; step bonuses wait for a verified sync.

## Geology (discovery, phase 3)

Generator pass before ore: pick cave geology (biome, depth, rock family, fossil / hydrothermal / volcanic
flags) -> 1-3 branching veins -> clues at walls and junctions (green malachite stain near copper, crystal
growths) -> ore nodes on the veins, rarer pockets behind discovery routes -> per-node hit tier, 4 crack
states, audio family, loot, journal entry. First find of each ore: a short Field Journal card (streak,
luster, hardness, crystal habit).

## Steps (prospecting only)

Daily milestones to test: 1,000 a scout clue, 3,000 a rare-pocket hint, 5,000 a small bonus cache.
Capped, deduplicated, from the verified step source. Never per Pounce, never needed for crafting or the
story; a player who doesn't walk that day can still mine and forge.

## Smithing at Bram's

Three short steps: Prepare (refine, pick the piece; can be automatic) -> Shape (3-4 rhythmic hammer taps,
sparks, haptics) -> Finish (finish, engraving, fit; preview on the Evochi at once). No long failure states.
Materials: copper for trim, lamps, fittings; iron for frames and protection; lumen as a crystal socket;
obsidian as knapped glass inlays.

Heirlooms: every piece keeps a memory card (name, where the ore was found, crafted by, first journey,
finish, refit for evolution, shown in the Nest when retired). Personality and provenance over stat
inflation. Gear never hides the face, spines or gait.

Gear slots in the art: helmet (light), harness (body), paw guards, satchel (carry), lantern (utility),
attachment (special).

## The Wilds link

Working mines: no forced battles. Wildlife has personality, not combat (Burrowlings uncover pockets;
Shardbacks block routes and are passed by patience, another path or an object). Sealed shafts are opt-in
fights like Guild Raids, with temporary Raid HP and NPC allies; they give distinct finds, never basic tiers,
and never hurt Vitality, growth or bond. Lore: lumen crystals have begun answering footsteps, echoing the
Heartroot; old shafts are opening toward forgotten parts of the Wilds.

## Order of work

1. Feel: one copper node, walk-sheet Pounce, the contact marker, cracks, sound, haptics, loot arc.
   Done when the hit reads with sound off.
2. World: Old Trail walkable, Flint's talk and shop, one mine floor, Bram's craft, gear checks.
   Done when one trip from the village ends in a worn item.
3. Discovery: veins, journal, clues, step milestones, item memory.
4. Expansion: iron, lumen, obsidian feel; wildlife, fossils, sealed shafts.
