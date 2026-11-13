# Creatures, genetics and the world clock: the plan

Source: "Evochi: Core Creature & World Design Plan", the owner's planning, shared in chat on 12 Nov 2026,
and the owner's decisions on it the same night. This file keeps what we build from it. Like the mines plan,
settled rules are input; numbers are proposals to playtest.

## The six colours

All Evochi share one body; colour sets element, specialization and Elder Ultimate.

| Colour   | Element           | Specialization                | Elder Ultimate |
|----------|-------------------|-------------------------------|----------------|
| Amber    | Lumen / Light     | Light-based combat            | Lumen Glow     |
| Forest   | Nature            | Farming and plant abilities   | Root Snare     |
| Coral    | Ember / Fire      | Offensive fire combat         | Spark Burst    |
| Ocean    | Water             | Healing and support           | Healing Mist   |
| Amethyst | Celestial         | Celestial energy attacks      | Starlight Beam |
| Obsidian | Stone / Earth     | Mining and earth-based combat | Stone Guard    |

Already in the game: the six affinities with exactly these abilities (`game/trails/trails.dart`,
`affinityDefs`), tied today to the trails' creatures, not to your Evochi's colour. Joining colour to affinity
is the first step whenever this starts.

## Stages

Eggling (movement, idle quirks, the first personality tells), Juvenile (standard combat moves and its
specialization's utility), Elder (its Elder Ultimate). The stages exist; what each unlocks follows this.

## Personality seed (built: the live pet lab, 12 Nov)

- An egg's seed rolls continuous genes 0-100: curiosity, courage, sociability, energy, appetite, feistiness
  (the plan's "aggression", named for a cozy game; same role: it pounces) and expressiveness
  (`game/personality/genome.dart`). Most land near the middle; about one gene in ten lands past 15 or 85.
- Personality never locks out elemental powers; it shapes how they look and move (an impulsive Coral fires
  quick wild embers, a calm one slow deliberate strikes): the quirks layer (`brain.dart`, `Quirks`: pace, hop,
  glances, posture, blink, idle habit), which combat animation will read too.
- The AI loop: needs drain at rates the genes set and are acted on at thresholds the genes set; a utility AI
  scores actions from needs and surroundings times the genes (`brain.dart`). Developer tools > live pet lab.
- Not yet in the game: the live Eggling (`features/live`) and the brain run only in the lab. The saved
  personality (`personality.dart`, profiles) is unchanged until we choose to move the game onto the genome.

## Settled by the owner (12 Nov)

- **Death stays.** An Evochi can still die if you stop walking (vitality, memorials). The plan's "immortal
  Elders" applies only as far as the vitality rules allow; Star Ascension (below) is an option, not a
  replacement for death.
- **Real clock.** The world runs on the player's real local time: night in the game when it is night outside
  (the nest already reads the local hour, `day_keys.hourIn`). No accelerated Minecraft-style day. Scenes will
  need a night (and dusk/dawn) version: render them alongside each scene's re-render in the new storybook look
  (`tools/art/storybook.py`), with the lights the scene tools already have (`STATE_LIGHT`).
- **Night hatching: smaller bonuses.** Hatching at night may lean an egg's traits (nocturnal colours,
  gender ratio), but the nudge is kept small, so nobody is rewarded for staying up late (it is a health app).

## Waiting (wanted, not yet)

- **Many Evochi.** Several living Evochi at once (breeding, gendered pairs, Elders on town, farm and mining
  duties). The owner wants it, later. It is the biggest change: the save holds one `Pet` today (plus
  `pastPets` and the Hatching Nook's eggs), so it needs a roster, which one walks with you (gets the steps),
  and new screens.
- **Breeding and genetics**, once there are many: genders; the mother's line gives colour and Elder Ultimate,
  the father's the secondary specialization or passive and a pull on the child's personality; mixed colours
  make hybrids (an Amber body with Forest farming), purebreds get stronger elemental potency; personality
  sets how fast two bond before an egg. `Genome.child` already blends two parents with mutation; the roles,
  hybrids and compatibility go on top.
- **Star Ascension**: a max-level Elder becomes a constellation (boosting its element's astrology odds) and
  leaves a Legacy Egg carrying its traits.
- **Calendar astrology**: rotating elemental signs nudging eggs (traits, inheritance odds, rare shell
  markings). Call the calendar's turning something other than "season": the Season Pass has that word.

## Later: hunting, trading and money

- The owner is open to changing the monetization rules (today: paid cosmetics are looks-only, rank II/III
  charms only from play, no paid random outcomes, Hollow Surge never costs Glimmer), to be decided later.
  Until then those rules stand.
- When it comes up: the Wilds today calm creatures rather than defeat them, so "hunting" needs a decision
  on tone; trading needs a server; and paid random outcomes carry store and legal requirements (published
  odds on the App Store and Google Play; some countries restrict paid loot boxes outright).
