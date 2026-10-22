// Village Tales, Chapter 1: The Light of Sunlit Village (Quest Bible v1.0, October 2026).
// The cast, places, quest materials and the quests: the three chapter quests, the Home Tales (the
// Cottage and its rooms), the optional side stories and the Lumen Trails encounter quests.
// Mirrors web/src/game/story.js.

/// Manual (unverified) entries count toward story walks. Chapter 1 rewards are cosmetic and can't be
/// traded or sold, and manual entry is how players without a step sensor take part. Turn this off
/// before any story reward becomes tradable.
class StoryConfig {
  static bool countManualSteps = true;
}

class Npc {
  const Npc(this.id, this.name, this.title, this.location, this.species);
  final String id;
  final String name;
  final String title;
  final String location;
  final String species;
}

const npcs = <String, Npc>{
  'npc_mira': Npc('npc_mira', 'Mira', 'the Gardener', 'glasshouse', 'tanuki'),
  'npc_bram': Npc('npc_bram', 'Bram', 'the Lanternkeeper', 'workshop', 'badger-bear'),
  'npc_pip': Npc('npc_pip', 'Pip', 'the Courier', 'lodge', 'sparrow'),
  'npc_alder': Npc('npc_alder', 'Alder', 'the Mapmaker', 'lodge', 'tortoise'),
};

class Place {
  const Place(this.id, this.locId, this.name, this.short, this.npcs, this.blurb);
  final String id;
  final String locId;
  final String name;
  final String short;
  final List<String> npcs;
  final String blurb;
}

const places = <String, Place>{
  'glasshouse': Place('glasshouse', 'loc_mira_glasshouse', "Mira's Glasshouse", 'Glasshouse', ['npc_mira'], 'A glass-roofed garden cottage full of seedlings.'),
  'workshop': Place('workshop', 'loc_bram_workshop', "Bram's Workshop", 'Workshop', ['npc_bram'], 'Copper, glass lenses and a warm furnace glow.'),
  'lodge': Place('lodge', 'loc_trail_guild', 'Trail Guild Lodge', 'Trail Guild', ['npc_pip', 'npc_alder'], "Pip's courier counter and Alder's map table."),
  'waystone': Place('waystone', 'loc_village_square', 'The Waystone', 'Waystone', [], 'An old standing stone in the middle of the Square.'),
};

/// Quest materials: key items for the Quest Pouch. Deliberately NOT catalog items, so the Market,
/// chests, purchases, equipping and any future trading cannot see them.
class QuestMaterial {
  const QuestMaterial(this.id, this.name, this.quest, this.usedBy, this.max, this.desc);
  final String id;
  final String name;
  final String quest;
  final String usedBy; // an npc id, 'waystone', 'cottage', 'ruins' or 'gate'
  final int max;
  final String desc;
}

const questMaterials = <String, QuestMaterial>{
  'q_dawn_dew_vial': QuestMaterial('q_dawn_dew_vial', 'Dawn Dew Vial', 'vq01', 'npc_mira', 1,
      'A stout glass vial of icy-sky dew with a golden glint. A tiny bit of sunrise in a bottle.'),
  'q_lumenbud_sprig': QuestMaterial('q_lumenbud_sprig', 'Lumenbud Sprig', 'vq01', 'npc_bram', 1,
      'A dark-sage stem with three little golden buds. It wants to be a lamp wick.'),
  'q_windprint_paper': QuestMaterial('q_windprint_paper', 'Windprint Paper', 'vq02', 'npc_pip', 2,
      'Folded cream paper with a faint wind spiral. It only appears when someone walks the route with care.'),
  'q_sealed_trail_letter': QuestMaterial('q_sealed_trail_letter', 'Sealed Trail Letter', 'vq02', 'npc_alder', 1,
      "An old trail letter, sealed with the Guild's navy wing."),
  'q_echo_rubbing': QuestMaterial('q_echo_rubbing', 'Echo Rubbing', 'vq03', 'npc_bram', 3,
      "A charcoal rubbing of one of the Waystone's memories. The rune strokes glow faintly."),
  'q_waystone_core': QuestMaterial('q_waystone_core', 'Waystone Core', 'vq03', 'waystone', 1,
      'A cream stone cube with three gold channels and a tiny mint centre. No sparks yet.'),
  'q_glowbloom_essence': QuestMaterial('q_glowbloom_essence', 'Glowbloom Essence', 'vq03', 'waystone', 1,
      'A droplet jar holding one luminous petal. Care, gathered a little every day.'),
  'q_sturdy_timber': QuestMaterial('q_sturdy_timber', 'Sturdy Timber', 'hq01', 'npc_bram', 1,
      'Straight oak planks, tied with twine. Exactly what an old roof needs.'),
  'q_mossy_clue': QuestMaterial('q_mossy_clue', 'Mossy Clue', 'eq01', 'ruins', 1,
      'A pressed flower and a tuft of green fur, found on the path to the Mossy Ruins. Something small went this way.'),
  'q_lumen_trace': QuestMaterial('q_lumen_trace', 'Lumen Trace', 'eq02', 'ruins', 1,
      'A jar of faintly glowing dust swept from the ruin stones. It hums when you walk.'),
  'q_old_trail_map': QuestMaterial('q_old_trail_map', "Alder's Old Map", 'eq03', 'gate', 1,
      'A brittle map of the north road. Alder has marked the bridge, and a gate beyond it that no one has opened in living memory.'),
};

/// Story titles by id (display names).
const titles = {
  'first_lightkeeper': 'First Lightkeeper',
  'friend_of_small_things': 'Friend of Small Things',
  'grove_friend': 'Grove Friend',
  'friend_of_petalune': 'Friend of Petalune',
  'trailwarden': 'Trailwarden',
  'lightbearer': 'Lightbearer', // Season 1: First Light, premium track
};

const chapterName = 'Village Tales, Chapter 1';
const chapterTitle = 'The Light of Sunlit Village';

class StoryRewards {
  const StoryRewards({this.items = const [], this.coins = 0, this.titles = const [], this.gifts = const {}, this.unlocks = const [], this.companion});
  final List<String> items; // story cosmetics (acquisition 'story'), granted once
  final int coins;
  final List<String> titles;
  final Map<String, int> gifts; // ordinary inventory items (seeds, harvests)
  final List<String> unlocks; // display only: what the quest opens (Cottage, Kitchen, Apothecary)
  final String? companion; // display only: the creature the encounter befriends (granted by the encounter engine)
}

class StoryWalk {
  const StoryWalk({required this.type, required this.nominal, required this.days, required this.phase, required this.ready, this.grant = const {}, this.perDay = const {}});
  final String type; // incremental | days
  final int nominal;
  final int days;
  final String phase; // the phase during which steps count
  final String ready; // the phase reached when the walk is done
  final Map<String, int> grant; // incremental: granted once when done
  final Map<String, int> perDay; // days: granted for each qualifying day
}

class TurnIn {
  const TurnIn({
    required this.id,
    required this.npc,
    required this.from,
    required this.to,
    required this.label,
    this.consume = const {},
    this.grant = const {},
    this.rewards,
    this.flags = const [],
    this.consumeItems = const {},
    this.requireStage = 0,
    this.encounter,
    this.optionalItems = const {},
  });
  final String id;
  final String npc; // an npc id, 'waystone', 'cottage', 'ruins' or 'gate'
  final String from;
  final String to;
  final String label;
  final Map<String, int> consume; // Quest Pouch materials
  final Map<String, int> grant;
  final StoryRewards? rewards;
  final List<String> flags;
  final Map<String, int> consumeItems; // ordinary inventory items (harvests, homemade food)
  final int requireStage; // 0 = any; 2 = a Juvenile (or Elder) Evochi
  final String? encounter; // Lumen Trails: the creature this hand-in is played against (the encounter is the hand-in)
  final Map<String, int> optionalItems; // recommended for the encounter, never required
}

/// An item an objective counts (e.g. "Grow and harvest 3 Sunberries").
class ObjectiveCount {
  const ObjectiveCount(this.itemId, this.n);
  final String itemId;
  final int n;
}

class Objective {
  const Objective(this.id, this.text, this.doneAt, {this.count, this.optional = false});
  final String id;
  final String text;
  final String doneAt;
  final ObjectiveCount? count;
  final bool optional; // never blocks the quest (an encounter's recommended item)
}

class StoryQuest {
  const StoryQuest({
    required this.id,
    required this.n,
    required this.title,
    required this.level,
    required this.dependsOn,
    required this.giver,
    required this.summary,
    required this.phases,
    this.walk,
    required this.turnIns,
    required this.objectives,
    required this.rewards,
    this.line = 'chapter',
    this.skills = const {},
    this.stage = 0,
    this.acceptPhase,
    this.discoveries = 0,
  });
  final String id;
  final int n;
  final String title;
  final int level;
  final List<String> dependsOn;
  final String giver;
  final String summary;
  final List<String> phases;
  final StoryWalk? walk; // null: no walking objective (the quest starts at [acceptPhase])
  final List<TurnIn> turnIns;
  final List<Objective> objectives;
  final StoryRewards rewards;
  final String line; // chapter | home | side | trail
  final Map<String, int> skills; // Cozy Skill levels needed to accept (e.g. cooking: 2)
  final int stage; // 0 = any; 2 = needs a Juvenile Evochi to accept
  final String? acceptPhase; // the phase a walk-less quest starts in
  final int discoveries; // Trail Guild discoveries completed before the quest is offered
}

const storyQuests = <String, StoryQuest>{
  'vq01': StoryQuest(
    id: 'vq01',
    n: 1,
    title: 'A Light for the Village',
    level: 1,
    dependsOn: [],
    giver: 'npc_mira',
    summary: 'The nursery lamp by the gate has gone dark. Help Mira wake a Lumenbud, then bring it to Bram.',
    phases: ['available', 'accepted_walk', 'dew_ready', 'sprig_ready', 'completed'],
    walk: StoryWalk(type: 'incremental', nominal: 2000, days: 1, phase: 'accepted_walk', ready: 'dew_ready', grant: {'q_dawn_dew_vial': 1}),
    turnIns: [
      TurnIn(id: 'mira_dew', npc: 'npc_mira', from: 'dew_ready', to: 'sprig_ready', consume: {'q_dawn_dew_vial': 1}, grant: {'q_lumenbud_sprig': 1}, label: 'Give Dawn Dew Vial'),
      TurnIn(
          id: 'bram_sprig',
          npc: 'npc_bram',
          from: 'sprig_ready',
          to: 'completed',
          consume: {'q_lumenbud_sprig': 1},
          rewards: StoryRewards(items: ['reward_firefly_hearth'], coins: 75),
          flags: ['lamp_lit'],
          label: 'Give Lumenbud Sprig'),
    ],
    objectives: [
      Objective('talk', 'Talk to Mira', 'accepted_walk'),
      Objective('walk', 'Walk {resolved_steps} new steps', 'dew_ready'),
      Objective('dew', 'Give the Dawn Dew Vial to Mira', 'sprig_ready'),
      Objective('sprig', 'Deliver the Lumenbud Sprig to Bram', 'completed'),
      Objective('claim', 'Claim your reward', 'completed'),
    ],
    rewards: StoryRewards(items: ['reward_firefly_hearth'], coins: 75),
  ),
  'vq02': StoryQuest(
    id: 'vq02',
    n: 2,
    title: 'The Letter Beyond the Bridge',
    level: 3,
    dependsOn: ['vq01'],
    giver: 'npc_pip',
    summary: 'Pip promised Alder a letter from beyond the bridge, but the wind scattered the route paper.',
    phases: ['locked', 'available', 'accepted_two_days', 'paper_2_ready', 'letter_ready', 'completed'],
    walk: StoryWalk(type: 'days', nominal: 2500, days: 2, phase: 'accepted_two_days', ready: 'paper_2_ready', perDay: {'q_windprint_paper': 1}),
    turnIns: [
      TurnIn(id: 'pip_papers', npc: 'npc_pip', from: 'paper_2_ready', to: 'letter_ready', consume: {'q_windprint_paper': 2}, grant: {'q_sealed_trail_letter': 1}, label: 'Give 2 Windprint Papers'),
      TurnIn(
          id: 'alder_letter',
          npc: 'npc_alder',
          from: 'letter_ready',
          to: 'completed',
          consume: {'q_sealed_trail_letter': 1},
          rewards: StoryRewards(items: ['reward_windtrail_mantle'], coins: 125),
          flags: ['waystone_revealed'],
          label: 'Hand over the Sealed Trail Letter'),
    ],
    objectives: [
      Objective('talk', 'Talk to Pip', 'accepted_two_days'),
      Objective('walk', 'Walk {resolved_steps} steps on 2 different days', 'paper_2_ready'),
      Objective('papers', 'Give 2 Windprint Papers to Pip', 'letter_ready'),
      Objective('letter', 'Give the Sealed Trail Letter to Alder', 'completed'),
      Objective('claim', 'Claim your reward', 'completed'),
    ],
    rewards: StoryRewards(items: ['reward_windtrail_mantle'], coins: 125),
  ),
  'vq03': StoryQuest(
    id: 'vq03',
    n: 3,
    title: 'The Sleeping Waystone',
    level: 6,
    dependsOn: ['vq02'],
    giver: 'npc_alder',
    summary: "Alder's old map matches the sleeping Waystone in the Square. Trace its three memories and wake it.",
    phases: ['locked', 'available', 'accepted_three_days', 'rubbings_ready', 'core_ready', 'restoration_ready', 'completed'],
    walk: StoryWalk(type: 'days', nominal: 3500, days: 3, phase: 'accepted_three_days', ready: 'rubbings_ready', perDay: {'q_echo_rubbing': 1}),
    turnIns: [
      TurnIn(id: 'bram_rubbings', npc: 'npc_bram', from: 'rubbings_ready', to: 'core_ready', consume: {'q_echo_rubbing': 3}, grant: {'q_waystone_core': 1}, label: 'Give 3 Echo Rubbings'),
      TurnIn(id: 'mira_essence', npc: 'npc_mira', from: 'core_ready', to: 'restoration_ready', grant: {'q_glowbloom_essence': 1}, label: 'Ask Mira for Glowbloom Essence'),
      TurnIn(
          id: 'restore',
          npc: 'waystone',
          from: 'restoration_ready',
          to: 'completed',
          consume: {'q_waystone_core': 1, 'q_glowbloom_essence': 1},
          rewards: StoryRewards(items: ['reward_waystone_bloom'], coins: 250, titles: ['first_lightkeeper']),
          flags: ['waystone_restored'],
          label: 'Restore the Waystone'),
    ],
    objectives: [
      Objective('talk', 'Talk to Alder', 'accepted_three_days'),
      Objective('walk', 'Walk {resolved_steps} steps on 3 different days', 'rubbings_ready'),
      Objective('rubbings', 'Give 3 Echo Rubbings to Bram', 'core_ready'),
      Objective('essence', 'Collect Glowbloom Essence from Mira', 'restoration_ready'),
      Objective('restore', 'Restore the Waystone in the Square', 'completed'),
      Objective('claim', 'Claim your rewards', 'completed'),
    ],
    rewards: StoryRewards(items: ['reward_waystone_bloom'], coins: 250, titles: ['first_lightkeeper']),
  ),

  // ---- Home Tales: the Cottage and its rooms. Same engine; hand-ins can ask for real inventory
  // items (`consumeItems`, e.g. harvests and homemade food) as well as Quest Pouch materials.
  'hq01': StoryQuest(
    id: 'hq01',
    n: 1,
    line: 'home',
    title: 'A Place to Call Home',
    level: 2,
    dependsOn: ['vq01'],
    giver: 'npc_bram',
    summary: 'The old cottage past your nest has lost its roof. Gather timber on your walks, grow lunch for the builders and help Bram restore it.',
    phases: ['locked', 'available', 'accepted_walk', 'timber_ready', 'restoration_ready', 'completed'],
    walk: StoryWalk(type: 'incremental', nominal: 3000, days: 1, phase: 'accepted_walk', ready: 'timber_ready', grant: {'q_sturdy_timber': 1}),
    turnIns: [
      TurnIn(
          id: 'bram_timber',
          npc: 'npc_bram',
          from: 'timber_ready',
          to: 'restoration_ready',
          consume: {'q_sturdy_timber': 1},
          consumeItems: {'sunberry': 3},
          label: 'Give the timber and 3 Sunberries'),
      TurnIn(id: 'restore_cottage', npc: 'cottage', from: 'restoration_ready', to: 'completed', flags: ['cottage_restored'], label: 'Restore the Cottage'),
    ],
    objectives: [
      Objective('talk', 'Talk to Bram', 'accepted_walk'),
      Objective('walk', 'Walk {resolved_steps} new steps to gather timber', 'timber_ready'),
      Objective('berries', 'Grow and harvest 3 Sunberries', 'restoration_ready', count: ObjectiveCount('sunberry', 3)),
      Objective('give', 'Bring the timber and Sunberries to Bram', 'restoration_ready'),
      Objective('restore', 'Restore the Cottage on your Home Map', 'completed'),
    ],
    rewards: StoryRewards(coins: 100, gifts: {'seed_golden_wheat': 3, 'golden_wheat': 2}, unlocks: ['Cottage', 'Kitchen']),
  ),
  'hq02': StoryQuest(
    id: 'hq02',
    n: 2,
    line: 'home',
    title: "Mira's Mortar",
    level: 2,
    dependsOn: ['hq01'],
    skills: {'cooking': 2},
    giver: 'npc_mira',
    summary: "Mira's grandmother's mortar is gathering dust. Bring her two Glowleaf from your garden and she'll help you set up an Apothecary.",
    phases: ['locked', 'available', 'need_glowleaf', 'completed'],
    acceptPhase: 'need_glowleaf',
    turnIns: [
      TurnIn(
          id: 'mira_glowleaf',
          npc: 'npc_mira',
          from: 'need_glowleaf',
          to: 'completed',
          consumeItems: {'glowleaf': 2},
          flags: ['apothecary_unlocked'],
          label: 'Give 2 Glowleaf'),
    ],
    objectives: [
      Objective('talk', 'Talk to Mira', 'need_glowleaf'),
      Objective('grow', 'Grow and harvest 2 Glowleaf (Farming Lv 3)', 'completed', count: ObjectiveCount('glowleaf', 2)),
      Objective('give', 'Bring the Glowleaf to Mira', 'completed'),
    ],
    rewards: StoryRewards(coins: 80, gifts: {'seed_glowleaf': 2, 'seed_moonshroom': 2}, unlocks: ['Apothecary']),
  ),

  // ---- Side stories: optional, never on the main path. Special requirements (a grown Evochi, a
  // homemade dish) live only here.
  'sq01': StoryQuest(
    id: 'sq01',
    n: 1,
    line: 'side',
    title: 'The Shy Visitor',
    level: 3,
    dependsOn: ['hq01'],
    giver: 'npc_pip',
    summary: "Something small and fluffy keeps peeking at Pip's mail sacks. Shy visitors can't resist a fresh Sunberry Tart.",
    phases: ['locked', 'available', 'need_tart', 'completed'],
    acceptPhase: 'need_tart',
    turnIns: [
      TurnIn(id: 'pip_tart', npc: 'npc_pip', from: 'need_tart', to: 'completed', consumeItems: {'sunberry_tart': 1}, label: 'Give a Sunberry Tart'),
    ],
    objectives: [
      Objective('talk', 'Talk to Pip', 'need_tart'),
      Objective('bake', 'Bake a Sunberry Tart in your Kitchen', 'completed', count: ObjectiveCount('sunberry_tart', 1)),
      Objective('give', 'Bring the tart to Pip', 'completed'),
    ],
    rewards: StoryRewards(coins: 120, gifts: {'seed_moonshroom': 3}, titles: ['friend_of_small_things']),
  ),
  'sq02': StoryQuest(
    id: 'sq02',
    n: 2,
    line: 'side',
    title: 'Guardian of the Old Grove',
    level: 4,
    dependsOn: ['hq02'],
    stage: 2,
    giver: 'npc_alder',
    summary: 'An old guardian sleeps in the grove past the north road. It only wakes for a grown Evochi carrying a Glowleaf Tonic.',
    phases: ['locked', 'available', 'need_tonic', 'completed'],
    acceptPhase: 'need_tonic',
    turnIns: [
      TurnIn(
          id: 'alder_tonic',
          npc: 'npc_alder',
          from: 'need_tonic',
          to: 'completed',
          consumeItems: {'glowleaf_tonic': 1},
          requireStage: 2,
          label: 'Bring the Glowleaf Tonic to the grove'),
    ],
    objectives: [
      Objective('talk', 'Talk to Alder', 'need_tonic'),
      Objective('brew', 'Brew a Glowleaf Tonic in your Apothecary', 'completed', count: ObjectiveCount('glowleaf_tonic', 1)),
      Objective('give', 'Visit the grove with your Juvenile (or Elder) Evochi', 'completed'),
    ],
    rewards: StoryRewards(coins: 200, titles: ['grove_friend']),
  ),

  // ---- Lumen Trails: encounter quests from the Trail Guild. The hand-in is the encounter itself,
  // played at the place (`encounter` names the creature; `optionalItems` are recommended, never required).
  'eq01': StoryQuest(
    id: 'eq01',
    n: 1,
    line: 'trail',
    title: 'The Forest Guardian',
    level: 3,
    dependsOn: ['vq01'],
    discoveries: 2,
    giver: 'npc_pip',
    summary: 'The Guild has spotted an unusual Evochi in the Mossy Ruins, down Fernwood Trail. Follow the clue, bring something tasty, and see if it will trust you.',
    phases: ['locked', 'available', 'accepted_walk', 'ruins_ready', 'completed'],
    walk: StoryWalk(type: 'incremental', nominal: 1500, days: 1, phase: 'accepted_walk', ready: 'ruins_ready', grant: {'q_mossy_clue': 1}),
    turnIns: [
      TurnIn(
          id: 'calm_petalune',
          npc: 'ruins',
          from: 'ruins_ready',
          to: 'completed',
          consume: {'q_mossy_clue': 1},
          encounter: 'petalune',
          optionalItems: {'sunberry_tart': 1},
          flags: ['petalune_befriended'],
          label: 'Befriend the Forest Guardian'),
    ],
    objectives: [
      Objective('talk', 'Talk to Pip at the Trail Guild', 'accepted_walk'),
      Objective('walk', 'Walk {resolved_steps} new steps to follow the clue', 'ruins_ready'),
      Objective('tart', 'Optional: bring a Sunberry Tart (better results)', 'completed', optional: true, count: ObjectiveCount('sunberry_tart', 1)),
      Objective('calm', 'Go down Fernwood Trail to the Mossy Ruins (F3) and earn its trust', 'completed'),
    ],
    rewards: StoryRewards(coins: 150, gifts: {'seed_glowleaf': 2, 'lumen_shard': 1}, companion: 'petalune', titles: ['friend_of_petalune']),
  ),
  'eq02': StoryQuest(
    id: 'eq02',
    n: 2,
    line: 'trail',
    title: 'Tangled Lumen',
    level: 4,
    dependsOn: ['eq01', 'hq01'],
    giver: 'npc_mira',
    summary: 'A plant spirit in the ruins is tangled in unstable Lumen. Mira thinks fresh Glowleaf and a steady heart can restore it.',
    phases: ['locked', 'available', 'accepted_walk', 'ruins_ready', 'completed'],
    walk: StoryWalk(type: 'incremental', nominal: 2000, days: 1, phase: 'accepted_walk', ready: 'ruins_ready', grant: {'q_lumen_trace': 1}),
    turnIns: [
      TurnIn(
          id: 'restore_sprout',
          npc: 'ruins',
          from: 'ruins_ready',
          to: 'completed',
          consume: {'q_lumen_trace': 1},
          consumeItems: {'glowleaf': 2},
          encounter: 'hollow_sprout',
          optionalItems: {'meadow_tea': 1},
          flags: ['sprout_restored'],
          label: 'Restore the Hollow Sprout'),
    ],
    objectives: [
      Objective('talk', 'Talk to Mira', 'accepted_walk'),
      Objective('walk', 'Walk {resolved_steps} new steps to gather a Lumen Trace', 'ruins_ready'),
      Objective('glow', 'Grow and harvest 2 Glowleaf (Farming Lv 3)', 'completed', count: ObjectiveCount('glowleaf', 2)),
      Objective('restore', 'Go down Fernwood Trail to the Mossy Ruins (F3) and restore the sprout', 'completed'),
    ],
    rewards: StoryRewards(coins: 180, gifts: {'lumen_shard': 2, 'seed_moonshroom': 1}, unlocks: ['Lantern Tonic recipe']),
  ),
  'eq03': StoryQuest(
    id: 'eq03',
    n: 3,
    line: 'trail',
    title: 'The Forgotten Sentinel',
    level: 6,
    dependsOn: ['vq03', 'eq02'],
    giver: 'npc_alder',
    summary: "The Waystone's map shows a gate beyond the old bridge. A guardian sleeps there, tangled in Hollow. Bring a Lantern Tonic and a steady Evochi.",
    phases: ['locked', 'available', 'accepted_walk', 'gate_ready', 'completed'],
    walk: StoryWalk(type: 'incremental', nominal: 3000, days: 1, phase: 'accepted_walk', ready: 'gate_ready', grant: {'q_old_trail_map': 1}),
    turnIns: [
      TurnIn(
          id: 'restore_sentinel',
          npc: 'gate',
          from: 'gate_ready',
          to: 'completed',
          consume: {'q_old_trail_map': 1},
          consumeItems: {'lantern_tonic': 1},
          encounter: 'sentinel',
          optionalItems: {'glowleaf_tonic': 1},
          flags: ['sentinel_restored'],
          label: 'Restore the Forgotten Sentinel'),
    ],
    objectives: [
      Objective('talk', 'Talk to Alder', 'accepted_walk'),
      Objective('walk', 'Walk {resolved_steps} new steps along the north road', 'gate_ready'),
      Objective('tonic', 'Brew a Lantern Tonic in your Apothecary (Alchemy Lv 3)', 'completed', count: ObjectiveCount('lantern_tonic', 1)),
      Objective('restore', 'Cross the old bridge and restore the Sentinel', 'completed'),
    ],
    rewards: StoryRewards(coins: 300, items: ['ancient_relic'], gifts: {'lumen_shard': 3}, titles: ['trailwarden'], unlocks: ['The Fading Paths']),
  ),
};

/// Village Tales, Chapter 1.
const questOrder = ['vq01', 'vq02', 'vq03'];

/// Home Tales: the Cottage, then the Apothecary.
const homeOrder = ['hq01', 'hq02'];

/// Side stories: optional, never on the main path.
const sideOrder = ['sq01', 'sq02'];

/// Lumen Trails: the Trail Guild's encounter quests.
const trailOrder = ['eq01', 'eq02', 'eq03'];

/// Every quest, in the order progress is applied and markers are computed.
const allQuests = [...questOrder, ...homeOrder, ...sideOrder, ...trailOrder];
