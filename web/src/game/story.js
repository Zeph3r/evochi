// Village Tales, Chapter 1: The Light of Sunlit Village (Quest Bible v1.0, October 2026).
//
// Story progression belongs to the player account, not to a pet: it lives in `state.story`, survives
// memorials, new pets, colourway changes and evolution, and its rewards go into the shared inventory.
//
// Rules (Quest Bible §9):
//  - only steps taken AFTER a quest is accepted count; the target is resolved once at acceptance
//    (min(nominal, personal goal)) and frozen, so changing the goal later cannot move it
//  - multi-day quests count distinct local calendar days (account time zone); one material per day
//  - progress is computed from the de-duplicated sample list, so re-delivered or replayed samples
//    never add progress, and every grant / hand-in / payout is idempotent
//  - quest materials live in their own pouch (never ITEMS, the Market, chests or trading);
//    story cosmetics are ordinary inventory items with acquisition 'story', shop null, price null
//  - no timers, no streaks: rest days and paused syncs never fail a quest

import { ITEMS } from './catalog.js';
import { dayKey } from './time.js';
import { aggregateDays } from './steps.js';
import { levelInfo } from './progression.js';
// state.js and home.js import this module too; these are only used inside functions (never at load time)
import { goalFor, grantItem, addTxn, ownedQty } from './state.js';
import { skillLevel, SKILLS } from './home.js';

export const STORY_SCHEMA = 1;

export const STORY_CONFIG = {
  // Manual (unverified) entries count toward story walks. Chapter 1 rewards are cosmetic and can't be
  // traded or sold, and manual entry is how players without a step sensor take part. Turn this off
  // before any story reward becomes tradable.
  countManualSteps: true,
};

// ------------------------------------------------------------------ cast ----
export const NPCS = {
  npc_mira: {
    id: 'npc_mira', name: 'Mira', title: 'the Gardener', location: 'glasshouse', species: 'tanuki',
    voice: 'Patient and hopeful', color: '#7F9871',
  },
  npc_bram: {
    id: 'npc_bram', name: 'Bram', title: 'the Lanternkeeper', location: 'workshop', species: 'badger-bear',
    voice: 'Gruff but soft-hearted', color: '#8D5D3B',
  },
  npc_pip: {
    id: 'npc_pip', name: 'Pip', title: 'the Courier', location: 'lodge', species: 'sparrow',
    voice: 'Fast and enthusiastic', color: '#D9954D',
  },
  npc_alder: {
    id: 'npc_alder', name: 'Alder', title: 'the Mapmaker', location: 'lodge', species: 'tortoise',
    voice: 'Calm and observant', color: '#7F9871',
  },
};

export const PLACES = {
  glasshouse: { id: 'glasshouse', locId: 'loc_mira_glasshouse', name: "Mira's Glasshouse", short: 'Glasshouse', npcs: ['npc_mira'],
    blurb: 'A glass-roofed garden cottage full of seedlings.' },
  workshop: { id: 'workshop', locId: 'loc_bram_workshop', name: "Bram's Workshop", short: 'Workshop', npcs: ['npc_bram'],
    blurb: 'Copper, glass lenses and a warm furnace glow.' },
  lodge: { id: 'lodge', locId: 'loc_trail_guild', name: 'Trail Guild Lodge', short: 'Trail Guild', npcs: ['npc_pip', 'npc_alder'],
    blurb: "Pip's courier counter and Alder's map table." },
  waystone: { id: 'waystone', locId: 'loc_village_square', name: 'The Waystone', short: 'Waystone', npcs: [],
    blurb: 'An old standing stone in the middle of the Square.' },
};

// Quest materials: key items for the Quest Pouch. Deliberately NOT in ITEMS, so the Market, chests,
// purchases, equipping and any future trading cannot see them.
export const QUEST_MATERIALS = {
  q_dawn_dew_vial: { name: 'Dawn Dew Vial', quest: 'vq01', usedBy: 'npc_mira', max: 1,
    desc: 'A stout glass vial of icy-sky dew with a golden glint. A tiny bit of sunrise in a bottle.' },
  q_lumenbud_sprig: { name: 'Lumenbud Sprig', quest: 'vq01', usedBy: 'npc_bram', max: 1,
    desc: 'A dark-sage stem with three little golden buds. It wants to be a lamp wick.' },
  q_windprint_paper: { name: 'Windprint Paper', quest: 'vq02', usedBy: 'npc_pip', max: 2,
    desc: 'Folded cream paper with a faint wind spiral. It only appears when someone walks the route with care.' },
  q_sealed_trail_letter: { name: 'Sealed Trail Letter', quest: 'vq02', usedBy: 'npc_alder', max: 1,
    desc: 'An old trail letter, sealed with the Guild\'s navy wing.' },
  q_echo_rubbing: { name: 'Echo Rubbing', quest: 'vq03', usedBy: 'npc_bram', max: 3,
    desc: 'A charcoal rubbing of one of the Waystone\'s memories. The rune strokes glow faintly.' },
  q_waystone_core: { name: 'Waystone Core', quest: 'vq03', usedBy: 'waystone', max: 1,
    desc: 'A cream stone cube with three gold channels and a tiny mint centre. No sparks yet.' },
  q_glowbloom_essence: { name: 'Glowbloom Essence', quest: 'vq03', usedBy: 'waystone', max: 1,
    desc: 'A droplet jar holding one luminous petal. Care, gathered a little every day.' },
  q_sturdy_timber: { name: 'Sturdy Timber', quest: 'hq01', usedBy: 'npc_bram', max: 1,
    desc: 'Straight oak planks, tied with twine. Exactly what an old roof needs.' },
  q_mossy_clue: { name: 'Mossy Clue', quest: 'eq01', usedBy: 'ruins', max: 1,
    desc: 'A pressed flower and a tuft of green fur, found on the path to the Mossy Ruins. Something small went this way.' },
  q_lumen_trace: { name: 'Lumen Trace', quest: 'eq02', usedBy: 'ruins', max: 1,
    desc: 'A jar of faintly glowing dust swept from the ruin stones. It hums when you walk.' },
  q_old_trail_map: { name: "Alder's Old Map", quest: 'eq03', usedBy: 'gate', max: 1,
    desc: 'A brittle map of the north road. Alder has marked the bridge, and a gate beyond it that no one has opened in living memory.' },
};

export const TITLES = {
  first_lightkeeper: { name: 'First Lightkeeper', quest: 'vq03' },
  friend_of_small_things: { name: 'Friend of Small Things', quest: 'sq01' },
  grove_friend: { name: 'Grove Friend', quest: 'sq02' },
  friend_of_petalune: { name: 'Friend of Petalune', quest: 'eq01' },
  trailwarden: { name: 'Trailwarden', quest: 'eq03' },
};

export const CHAPTER = { id: 'ch1', name: 'Village Tales, Chapter 1', title: 'The Light of Sunlit Village' };

// ----------------------------------------------------------------- quests ----
export const QUESTS = {
  vq01: {
    id: 'vq01', n: 1, title: 'A Light for the Village', level: 1, dependsOn: [], giver: 'npc_mira',
    summary: 'The nursery lamp by the gate has gone dark. Help Mira wake a Lumenbud, then bring it to Bram.',
    phases: ['available', 'accepted_walk', 'dew_ready', 'sprig_ready', 'completed'],
    walk: { type: 'incremental', nominal: 2000, days: 1, phase: 'accepted_walk', ready: 'dew_ready', grant: { q_dawn_dew_vial: 1 } },
    turnIns: [
      { id: 'mira_dew', npc: 'npc_mira', from: 'dew_ready', to: 'sprig_ready', consume: { q_dawn_dew_vial: 1 },
        grant: { q_lumenbud_sprig: 1 }, label: 'Give Dawn Dew Vial' },
      { id: 'bram_sprig', npc: 'npc_bram', from: 'sprig_ready', to: 'completed', consume: { q_lumenbud_sprig: 1 },
        rewards: { items: ['reward_firefly_hearth'], coins: 75 }, flags: ['lamp_lit'], label: 'Give Lumenbud Sprig' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Mira', doneAt: 'accepted_walk' },
      { id: 'walk', text: 'Walk {resolved_steps} new steps', doneAt: 'dew_ready' },
      { id: 'dew', text: 'Give the Dawn Dew Vial to Mira', doneAt: 'sprig_ready' },
      { id: 'sprig', text: 'Deliver the Lumenbud Sprig to Bram', doneAt: 'completed' },
      { id: 'claim', text: 'Claim your reward', doneAt: 'completed' },
    ],
    rewards: { items: ['reward_firefly_hearth'], coins: 75 },
  },
  vq02: {
    id: 'vq02', n: 2, title: 'The Letter Beyond the Bridge', level: 3, dependsOn: ['vq01'], giver: 'npc_pip',
    summary: 'Pip promised Alder a letter from beyond the bridge, but the wind scattered the route paper.',
    phases: ['locked', 'available', 'accepted_two_days', 'paper_2_ready', 'letter_ready', 'completed'],
    walk: { type: 'days', nominal: 2500, days: 2, phase: 'accepted_two_days', ready: 'paper_2_ready', perDay: { q_windprint_paper: 1 } },
    turnIns: [
      { id: 'pip_papers', npc: 'npc_pip', from: 'paper_2_ready', to: 'letter_ready', consume: { q_windprint_paper: 2 },
        grant: { q_sealed_trail_letter: 1 }, label: 'Give 2 Windprint Papers' },
      { id: 'alder_letter', npc: 'npc_alder', from: 'letter_ready', to: 'completed', consume: { q_sealed_trail_letter: 1 },
        rewards: { items: ['reward_windtrail_mantle'], coins: 125 }, flags: ['waystone_revealed'], label: 'Hand over the Sealed Trail Letter' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Pip', doneAt: 'accepted_two_days' },
      { id: 'walk', text: 'Walk {resolved_steps} steps on 2 different days', doneAt: 'paper_2_ready' },
      { id: 'papers', text: 'Give 2 Windprint Papers to Pip', doneAt: 'letter_ready' },
      { id: 'letter', text: 'Give the Sealed Trail Letter to Alder', doneAt: 'completed' },
      { id: 'claim', text: 'Claim your reward', doneAt: 'completed' },
    ],
    rewards: { items: ['reward_windtrail_mantle'], coins: 125 },
  },
  vq03: {
    id: 'vq03', n: 3, title: 'The Sleeping Waystone', level: 6, dependsOn: ['vq02'], giver: 'npc_alder',
    summary: 'Alder\'s old map matches the sleeping Waystone in the Square. Trace its three memories and wake it.',
    phases: ['locked', 'available', 'accepted_three_days', 'rubbings_ready', 'core_ready', 'restoration_ready', 'completed'],
    walk: { type: 'days', nominal: 3500, days: 3, phase: 'accepted_three_days', ready: 'rubbings_ready', perDay: { q_echo_rubbing: 1 } },
    turnIns: [
      { id: 'bram_rubbings', npc: 'npc_bram', from: 'rubbings_ready', to: 'core_ready', consume: { q_echo_rubbing: 3 },
        grant: { q_waystone_core: 1 }, label: 'Give 3 Echo Rubbings' },
      { id: 'mira_essence', npc: 'npc_mira', from: 'core_ready', to: 'restoration_ready', consume: {},
        grant: { q_glowbloom_essence: 1 }, label: 'Ask Mira for Glowbloom Essence' },
      { id: 'restore', npc: 'waystone', from: 'restoration_ready', to: 'completed',
        consume: { q_waystone_core: 1, q_glowbloom_essence: 1 },
        rewards: { items: ['reward_waystone_bloom'], coins: 250, titles: ['first_lightkeeper'] },
        flags: ['waystone_restored'], label: 'Restore the Waystone' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Alder', doneAt: 'accepted_three_days' },
      { id: 'walk', text: 'Walk {resolved_steps} steps on 3 different days', doneAt: 'rubbings_ready' },
      { id: 'rubbings', text: 'Give 3 Echo Rubbings to Bram', doneAt: 'core_ready' },
      { id: 'essence', text: 'Collect Glowbloom Essence from Mira', doneAt: 'restoration_ready' },
      { id: 'restore', text: 'Restore the Waystone in the Square', doneAt: 'completed' },
      { id: 'claim', text: 'Claim your rewards', doneAt: 'completed' },
    ],
    rewards: { items: ['reward_waystone_bloom'], coins: 250, titles: ['first_lightkeeper'] },
  },

  // ---- Home Tales: the Cottage and its rooms. Same engine; hand-ins can ask for real inventory
  // items (`consumeItems`, e.g. harvests and homemade food) as well as Quest Pouch materials.
  hq01: {
    id: 'hq01', n: 1, line: 'home', title: 'A Place to Call Home', level: 2, dependsOn: ['vq01'], giver: 'npc_bram',
    summary: 'The old cottage past your nest has lost its roof. Gather timber on your walks, grow lunch for the builders and help Bram restore it.',
    phases: ['locked', 'available', 'accepted_walk', 'timber_ready', 'restoration_ready', 'completed'],
    walk: { type: 'incremental', nominal: 3000, days: 1, phase: 'accepted_walk', ready: 'timber_ready', grant: { q_sturdy_timber: 1 } },
    turnIns: [
      { id: 'bram_timber', npc: 'npc_bram', from: 'timber_ready', to: 'restoration_ready', consume: { q_sturdy_timber: 1 },
        consumeItems: { sunberry: 3 }, label: 'Give the timber and 3 Sunberries' },
      { id: 'restore_cottage', npc: 'cottage', from: 'restoration_ready', to: 'completed', consume: {},
        flags: ['cottage_restored'], label: 'Restore the Cottage' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Bram', doneAt: 'accepted_walk' },
      { id: 'walk', text: 'Walk {resolved_steps} new steps to gather timber', doneAt: 'timber_ready' },
      { id: 'berries', text: 'Grow and harvest 3 Sunberries', doneAt: 'restoration_ready', count: { item: 'sunberry', n: 3 } },
      { id: 'give', text: 'Bring the timber and Sunberries to Bram', doneAt: 'restoration_ready' },
      { id: 'restore', text: 'Restore the Cottage on your Home Map', doneAt: 'completed' },
    ],
    rewards: { coins: 100, gifts: { seed_golden_wheat: 3, golden_wheat: 2 }, unlocks: ['Cottage', 'Kitchen'] },
  },
  hq02: {
    id: 'hq02', n: 2, line: 'home', title: "Mira's Mortar", level: 2, dependsOn: ['hq01'], skills: { cooking: 2 }, giver: 'npc_mira',
    summary: "Mira's grandmother's mortar is gathering dust. Bring her two Glowleaf from your garden and she'll help you set up an Apothecary.",
    phases: ['locked', 'available', 'need_glowleaf', 'completed'],
    acceptPhase: 'need_glowleaf',
    turnIns: [
      { id: 'mira_glowleaf', npc: 'npc_mira', from: 'need_glowleaf', to: 'completed', consume: {}, consumeItems: { glowleaf: 2 },
        flags: ['apothecary_unlocked'], label: 'Give 2 Glowleaf' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Mira', doneAt: 'need_glowleaf' },
      { id: 'grow', text: 'Grow and harvest 2 Glowleaf (Farming Lv 3)', doneAt: 'completed', count: { item: 'glowleaf', n: 2 } },
      { id: 'give', text: 'Bring the Glowleaf to Mira', doneAt: 'completed' },
    ],
    rewards: { coins: 80, gifts: { seed_glowleaf: 2, seed_moonshroom: 2 }, unlocks: ['Apothecary'] },
  },

  // ---- Side stories: optional, never on the main path. Special requirements (a grown Evochi, a
  // homemade dish) live only here.
  sq01: {
    id: 'sq01', n: 1, line: 'side', title: 'The Shy Visitor', level: 3, dependsOn: ['hq01'], giver: 'npc_pip',
    summary: 'Something small and fluffy keeps peeking at Pip\'s mail sacks. Shy visitors can\'t resist a fresh Sunberry Tart.',
    phases: ['locked', 'available', 'need_tart', 'completed'],
    acceptPhase: 'need_tart',
    turnIns: [
      { id: 'pip_tart', npc: 'npc_pip', from: 'need_tart', to: 'completed', consume: {}, consumeItems: { sunberry_tart: 1 },
        label: 'Give a Sunberry Tart' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Pip', doneAt: 'need_tart' },
      { id: 'bake', text: 'Bake a Sunberry Tart in your Kitchen', doneAt: 'completed', count: { item: 'sunberry_tart', n: 1 } },
      { id: 'give', text: 'Bring the tart to Pip', doneAt: 'completed' },
    ],
    rewards: { coins: 120, gifts: { seed_moonshroom: 3 }, titles: ['friend_of_small_things'] },
  },
  sq02: {
    id: 'sq02', n: 2, line: 'side', title: 'Guardian of the Old Grove', level: 4, dependsOn: ['hq02'], stage: 2, giver: 'npc_alder',
    summary: 'An old guardian sleeps in the grove past the north road. It only wakes for a grown Evochi carrying a Glowleaf Tonic.',
    phases: ['locked', 'available', 'need_tonic', 'completed'],
    acceptPhase: 'need_tonic',
    turnIns: [
      { id: 'alder_tonic', npc: 'npc_alder', from: 'need_tonic', to: 'completed', consume: {}, consumeItems: { glowleaf_tonic: 1 },
        requireStage: 2, label: 'Bring the Glowleaf Tonic to the grove' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Alder', doneAt: 'need_tonic' },
      { id: 'brew', text: 'Brew a Glowleaf Tonic in your Apothecary', doneAt: 'completed', count: { item: 'glowleaf_tonic', n: 1 } },
      { id: 'give', text: 'Visit the grove with your Juvenile (or Elder) Evochi', doneAt: 'completed' },
    ],
    rewards: { coins: 200, titles: ['grove_friend'] },
  },

  // ---- Lumen Trails: encounter quests from the Trail Guild. The hand-in is the encounter itself,
  // played at the place (`encounter` names the creature; `optionalItems` are recommended, never required).
  eq01: {
    id: 'eq01', n: 1, line: 'trail', title: 'The Forest Guardian', level: 3, dependsOn: ['vq01'], discoveries: 2, giver: 'npc_pip',
    summary: "The Guild has spotted an unusual Evochi near the Mossy Ruins. Follow the clue, bring something tasty, and see if it will trust you.",
    phases: ['locked', 'available', 'accepted_walk', 'ruins_ready', 'completed'],
    walk: { type: 'incremental', nominal: 1500, days: 1, phase: 'accepted_walk', ready: 'ruins_ready', grant: { q_mossy_clue: 1 } },
    turnIns: [
      { id: 'calm_petalune', npc: 'ruins', from: 'ruins_ready', to: 'completed', consume: { q_mossy_clue: 1 }, encounter: 'petalune',
        optionalItems: { sunberry_tart: 1 }, flags: ['petalune_befriended'], label: 'Befriend the Forest Guardian' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Pip at the Trail Guild', doneAt: 'accepted_walk' },
      { id: 'walk', text: 'Walk {resolved_steps} new steps to follow the clue', doneAt: 'ruins_ready' },
      { id: 'tart', text: 'Optional: bring a Sunberry Tart (better results)', doneAt: 'completed', optional: true, count: { item: 'sunberry_tart', n: 1 } },
      { id: 'calm', text: 'Travel to the Mossy Ruins and calm the Evochi', doneAt: 'completed' },
    ],
    rewards: { coins: 150, gifts: { seed_glowleaf: 2, lumen_shard: 1 }, companion: 'petalune', titles: ['friend_of_petalune'] },
  },
  eq02: {
    id: 'eq02', n: 2, line: 'trail', title: 'Tangled Lumen', level: 4, dependsOn: ['eq01', 'hq01'], giver: 'npc_mira',
    summary: 'A plant spirit in the ruins is tangled in unstable Lumen. Mira thinks fresh Glowleaf and a steady heart can restore it.',
    phases: ['locked', 'available', 'accepted_walk', 'ruins_ready', 'completed'],
    walk: { type: 'incremental', nominal: 2000, days: 1, phase: 'accepted_walk', ready: 'ruins_ready', grant: { q_lumen_trace: 1 } },
    turnIns: [
      { id: 'restore_sprout', npc: 'ruins', from: 'ruins_ready', to: 'completed', consume: { q_lumen_trace: 1 }, consumeItems: { glowleaf: 2 },
        encounter: 'hollow_sprout', optionalItems: { meadow_tea: 1 }, flags: ['sprout_restored'], label: 'Restore the Hollow Sprout' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Mira', doneAt: 'accepted_walk' },
      { id: 'walk', text: 'Walk {resolved_steps} new steps to gather a Lumen Trace', doneAt: 'ruins_ready' },
      { id: 'glow', text: 'Grow and harvest 2 Glowleaf (Farming Lv 3)', doneAt: 'completed', count: { item: 'glowleaf', n: 2 } },
      { id: 'restore', text: 'Travel to the Mossy Ruins and restore the sprout', doneAt: 'completed' },
    ],
    rewards: { coins: 180, gifts: { lumen_shard: 2, seed_moonshroom: 1 }, unlocks: ['Lantern Tonic recipe'] },
  },
  eq03: {
    id: 'eq03', n: 3, title: 'The Forgotten Sentinel', line: 'trail', level: 6, dependsOn: ['vq03', 'eq02'], giver: 'npc_alder',
    summary: "The Waystone's map shows a gate beyond the old bridge. A guardian sleeps there, tangled in Hollow. Bring a Lantern Tonic and a steady Evochi.",
    phases: ['locked', 'available', 'accepted_walk', 'gate_ready', 'completed'],
    walk: { type: 'incremental', nominal: 3000, days: 1, phase: 'accepted_walk', ready: 'gate_ready', grant: { q_old_trail_map: 1 } },
    turnIns: [
      { id: 'restore_sentinel', npc: 'gate', from: 'gate_ready', to: 'completed', consume: { q_old_trail_map: 1 }, consumeItems: { lantern_tonic: 1 },
        encounter: 'sentinel', optionalItems: { glowleaf_tonic: 1 }, flags: ['sentinel_restored'], label: 'Restore the Forgotten Sentinel' },
    ],
    objectives: [
      { id: 'talk', text: 'Talk to Alder', doneAt: 'accepted_walk' },
      { id: 'walk', text: 'Walk {resolved_steps} new steps along the north road', doneAt: 'gate_ready' },
      { id: 'tonic', text: 'Brew a Lantern Tonic in your Apothecary (Alchemy Lv 3)', doneAt: 'completed', count: { item: 'lantern_tonic', n: 1 } },
      { id: 'restore', text: 'Cross the old bridge and restore the Sentinel', doneAt: 'completed' },
    ],
    rewards: { coins: 300, items: ['ancient_relic'], gifts: { lumen_shard: 3 }, titles: ['trailwarden'], unlocks: ['The Fading Paths'] },
  },
};
export const QUEST_ORDER = ['vq01', 'vq02', 'vq03'];
export const HOME_ORDER = ['hq01', 'hq02'];
export const SIDE_ORDER = ['sq01', 'sq02'];
export const TRAIL_ORDER = ['eq01', 'eq02', 'eq03'];
export const ALL_QUESTS = [...QUEST_ORDER, ...HOME_ORDER, ...SIDE_ORDER, ...TRAIL_ORDER];

// --------------------------------------------------------------- helpers ----
function ok(state, events = []) {
  return { state, events, error: null };
}
function fail(state, error, extra = {}) {
  return { state, events: [], error, ...extra };
}
function clone(s) {
  return typeof structuredClone === 'function' ? structuredClone(s) : JSON.parse(JSON.stringify(s));
}

export function newStory() {
  return {
    schemaVersion: STORY_SCHEMA,
    activeQuestId: null,
    questStates: {},
    questPouch: {},
    qualifiedDayKeys: {},
    claimedRewards: [],
    flags: { lamp_lit: false, waystone_revealed: false, waystone_restored: false, cottage_restored: false, apothecary_unlocked: false,
      petalune_befriended: false, sprout_restored: false, sentinel_restored: false },
    titleUnlocks: [],
    npcsMet: {},
    offersSeen: {},
    peakLevel: 1,
  };
}

/** Add (or upgrade) the story object in place. Safe to call on every load. */
export function ensureStory(s) {
  if (!s.story || typeof s.story !== 'object') s.story = newStory();
  const base = newStory();
  for (const k of Object.keys(base)) if (s.story[k] === undefined) s.story[k] = base[k];
  s.story.flags = { ...base.flags, ...s.story.flags };
  return s.story;
}

function story(state) {
  return state.story || newStory();
}

export function pouchQty(state, id) {
  return story(state).questPouch[id] || 0;
}

/** Highest level this account has reached with any Evochi (story gates never go backwards). */
export function accountLevel(state) {
  let lv = story(state).peakLevel || 1;
  if (state.pet) {
    const xp = Object.values(state.pet.xpAwarded || {}).reduce((a, b) => a + b, 0);
    lv = Math.max(lv, levelInfo(xp).level);
  }
  for (const p of state.pastPets || []) lv = Math.max(lv, p.peakLevel || 1);
  return lv;
}

function phaseIndex(q, phase) {
  return q.phases.indexOf(phase);
}

/** The quest's phase, including the derived 'locked' / 'available' states before acceptance. */
export function questPhase(state, qid) {
  const q = QUESTS[qid];
  const st = story(state).questStates[qid];
  if (st) return st.phase;
  return lockReason(state, qid) ? 'locked' : 'available';
}

/** Why a quest can't be accepted yet, or null. */
export function lockReason(state, qid) {
  const q = QUESTS[qid];
  const done = (id) => story(state).questStates[id]?.phase === 'completed';
  const missing = q.dependsOn.filter((id) => !done(id));
  const lv = accountLevel(state);
  const skills = Object.entries(q.skills || {}).filter(([k, n]) => skillLevel(state.home?.skills?.[k] || 0).level < n);
  const stage = q.stage && (state.pet?.stage || 0) < q.stage;
  const disc = q.discoveries ? Math.max(0, q.discoveries - (state.trails?.stats?.discoveries || 0)) : 0;
  if (missing.length || lv < q.level || skills.length || stage || disc) {
    const parts = [];
    if (lv < q.level) parts.push(`reach level ${q.level}`);
    if (missing.length) parts.push(`finish "${QUESTS[missing[0]].title}"`);
    for (const [k, n] of skills) parts.push(`reach ${SKILLS[k].name} Lv ${n}`);
    if (disc) parts.push(`complete ${disc} more Trail Guild discover${disc === 1 ? 'y' : 'ies'}`);
    if (stage) parts.push('your Evochi grows into a Juvenile');
    return {
      level: q.level, needLevel: lv < q.level, needQuest: missing[0] || null, needSkills: Object.fromEntries(skills),
      needStage: stage ? q.stage : null, needDiscoveries: disc, text: 'Unlocks when ' + (parts[0].startsWith('your') ? '' : 'you ') + parts.join(' and '),
    };
  }
  return null;
}

/** Steps a quest asks for, frozen at acceptance (min(nominal, personal goal)). */
export function resolvedSteps(state, qid, now) {
  const st = story(state).questStates[qid];
  if (st) return st.resolvedSteps;
  const tz = state.player?.timezone || state.tzHint || 'UTC';
  const goal = goalFor(state, dayKey(now, tz));
  if (!QUESTS[qid].walk) return 0;
  return Math.min(QUESTS[qid].walk.nominal, goal);
}

// Steps from samples that happened at or after `since` (verified samples are clipped proportionally,
// compacted day records are ignored: progress for those days was frozen while they were still fresh).
export function freshDays(state, since, tz) {
  const clipped = [];
  for (const x of state.steps?.samples || []) {
    if (x.source === 'compacted' || x.source === 'compacted-manual') continue;
    if (x.manual) {
      if (!STORY_CONFIG.countManualSteps) continue;
      if (x.end >= since) clipped.push(x);
      continue;
    }
    if (x.start >= since) clipped.push(x);
    else if (x.end > since) clipped.push({ ...x, start: since, count: Math.round((x.count * (x.end - since)) / (x.end - x.start)) });
  }
  return aggregateDays(clipped, tz);
}

function addPouch(s, grant, events, qid, now) {
  for (const [id, n] of Object.entries(grant || {})) {
    s.story.questPouch[id] = (s.story.questPouch[id] || 0) + n;
    events.push({ type: 'story_item', questId: qid, itemId: id, qty: n, name: QUEST_MATERIALS[id].name });
  }
}

/**
 * Advance walking objectives from the step samples. Mutates `s` (a working copy) and returns events.
 * Called from syncSteps after samples are merged, and after accepting a quest.
 */
export function applyStoryProgress(s, now) {
  const events = [];
  if (!s.player) return events;
  const st0 = ensureStory(s);
  st0.peakLevel = Math.max(st0.peakLevel || 1, accountLevel(s));
  const tz = s.player.timezone || s.tzHint || 'UTC';
  for (const qid of ALL_QUESTS) {
    const q = QUESTS[qid];
    const st = st0.questStates[qid];
    if (!q.walk || !st || st.phase !== q.walk.phase) continue;
    const days = freshDays(s, st.acceptedAt, tz);
    st.dayProgress = st.dayProgress || {};
    for (const [k, d] of Object.entries(days)) st.dayProgress[k] = Math.max(st.dayProgress[k] || 0, d.steps);
    if (q.walk.type === 'incremental') {
      const total = Object.values(st.dayProgress).reduce((a, b) => a + b, 0);
      st.freshTotal = Math.max(st.freshTotal || 0, total);
      if (st.freshTotal >= st.resolvedSteps) {
        addPouch(s, q.walk.grant, events, qid, now);
        st.phase = q.walk.ready;
        st.readyAt = now;
        events.push({ type: 'story_ready', questId: qid, npc: nextStep(s, qid).npc, kind: nextStep(s, qid).kind });
      }
    } else {
      const set = st0.qualifiedDayKeys[qid] || (st0.qualifiedDayKeys[qid] = []);
      for (const k of Object.keys(st.dayProgress).sort()) {
        if (set.length >= q.walk.days) break;
        if (st.dayProgress[k] >= st.resolvedSteps && !set.includes(k)) {
          set.push(k);
          addPouch(s, q.walk.perDay, events, qid, now);
          events.push({ type: 'story_day', questId: qid, day: k, count: set.length, of: q.walk.days });
        }
      }
      if (set.length >= q.walk.days) {
        st.phase = q.walk.ready;
        st.readyAt = now;
        events.push({ type: 'story_ready', questId: qid, npc: nextStep(s, qid).npc, kind: nextStep(s, qid).kind });
      }
    }
  }
  return events;
}

// --------------------------------------------------------------- actions ----
export function acceptStoryQuest(state, qid, now) {
  const q = QUESTS[qid];
  if (!q) return fail(state, 'unknown_quest');
  if (!state.player) return fail(state, 'no_player');
  const cur = story(state).questStates[qid];
  if (cur) return ok(state, [{ type: 'story_already', questId: qid }]); // idempotent
  const lock = lockReason(state, qid);
  if (lock) return fail(state, 'story_locked', { message: lock.text });
  const s = clone(state);
  const st = ensureStory(s);
  const tz = s.player.timezone || s.tzHint || 'UTC';
  st.questStates[qid] = {
    phase: q.walk ? q.walk.phase : q.acceptPhase, acceptedAt: now, acceptedDay: dayKey(now, tz), resolvedSteps: resolvedSteps(s, qid, now),
    dayProgress: {}, freshTotal: 0, tracked: true, completedAt: null, seenCompletion: false,
  };
  st.activeQuestId = qid;
  st.offersSeen[qid] = true;
  const events = [{ type: 'story_accepted', questId: qid, title: q.title }];
  events.push(...applyStoryProgress(s, now));
  return ok(s, events);
}

function hasItems(state, consume) {
  return Object.entries(consume || {}).every(([id, n]) => pouchQty(state, id) >= n);
}

/** Inventory items a hand-in asks for (harvests, homemade food), and what's still missing.
 *  `spent` counts items already given at the place (offered during its encounter): they did the job. */
export function itemNeeds(state, t, spent = {}) {
  const out = [];
  for (const [id, n] of Object.entries(t?.consumeItems || {})) {
    const have = ownedQty(state, id) + (spent[id] || 0);
    out.push({ id, need: n, have: Math.min(have, n), ok: have >= n });
  }
  return out;
}

function stageOk(state, t) {
  return !t?.requireStage || (state.pet?.stage || 0) >= t.requireStage;
}

/** Give quest items to an NPC (or the Waystone). Transactional and idempotent. */
export function storyHandIn(state, qid, turnInId, now, { spent = {} } = {}) {
  const q = QUESTS[qid];
  const t = q?.turnIns.find((x) => x.id === turnInId);
  if (!t) return fail(state, 'unknown_turnin');
  const st = story(state).questStates[qid];
  if (!st) return fail(state, 'story_not_accepted');
  if (phaseIndex(q, st.phase) > phaseIndex(q, t.from)) return ok(state, [{ type: 'story_already', questId: qid, turnIn: turnInId }]);
  if (st.phase !== t.from) return fail(state, 'story_not_ready');
  if (!hasItems(state, t.consume)) return fail(state, 'story_missing_items');
  const short = itemNeeds(state, t, spent).filter((x) => !x.ok);
  if (short.length) return fail(state, 'story_missing_items', { missing: short });
  if (!stageOk(state, t)) return fail(state, 'story_needs_stage', { stage: t.requireStage });
  const s = clone(state);
  const S = ensureStory(s);
  const events = [];
  for (const [id, n] of Object.entries(t.consume || {})) {
    S.questPouch[id] -= n;
    if (S.questPouch[id] <= 0) delete S.questPouch[id];
  }
  for (const [id, n] of Object.entries(t.consumeItems || {})) {
    // from the Bag first (as always); only a shortfall is covered by what was already offered at the place
    const take = Math.min(n, ownedQty(s, id));
    if (take) s.inventory[id].quantity -= take;
  }
  events.push({ type: 'story_handin', questId: qid, turnIn: turnInId, npc: t.npc, consumed: t.consume });
  addPouch(s, t.grant, events, qid, now);
  for (const f of t.flags || []) S.flags[f] = true;
  const qs = S.questStates[qid];
  qs.phase = t.to;
  if (t.to === 'completed') {
    qs.completedAt = now;
    const rewards = grantStoryRewardOnce(s, qid, now);
    if (S.activeQuestId === qid) S.activeQuestId = null;
    events.push({ type: 'story_completed', questId: qid, title: q.title, rewards });
  } else {
    events.push({ type: 'story_ready', questId: qid, npc: nextStep(s, qid).npc, kind: nextStep(s, qid).kind });
  }
  return ok(s, events);
}

/** Pay out a quest's rewards exactly once (inventory items, EvoCoins, titles). Mutates `s`. */
export function grantStoryRewardOnce(s, qid, now) {
  const S = ensureStory(s);
  if (S.claimedRewards.includes(qid)) return null;
  const r = QUESTS[qid].rewards;
  for (const id of r.items || []) {
    if (!ITEMS[id] || ITEMS[id].acquisition !== 'story') throw new Error('story reward must be a story item: ' + id);
    if (!(s.inventory[id]?.quantity > 0)) grantItem(s, id, 1, `story:${qid}`, now, `story:${qid}`);
  }
  if (r.coins) addTxn(s, { id: `story:${qid}`, amount: r.coins, currency: 'evocoin', cause: `story:${qid}`, at: now });
  for (const [id, n] of Object.entries(r.gifts || {})) grantItem(s, id, n, `story:${qid}`, now, `story:${qid}:gift`);
  for (const t of r.titles || []) if (!S.titleUnlocks.includes(t)) S.titleUnlocks.push(t);
  S.claimedRewards.push(qid);
  return r;
}

function patch(state, fn) {
  const s = clone(state);
  ensureStory(s);
  fn(s.story);
  return ok(s);
}
export const markNpcMet = (state, npcId) => (story(state).npcsMet[npcId] ? ok(state) : patch(state, (S) => (S.npcsMet[npcId] = true)));
export const markOfferSeen = (state, qid) => (story(state).offersSeen[qid] ? ok(state) : patch(state, (S) => (S.offersSeen[qid] = true)));
export const markCompletionSeen = (state, qid) => (!story(state).questStates[qid] || story(state).questStates[qid].seenCompletion
  ? ok(state) : patch(state, (S) => (S.questStates[qid].seenCompletion = true)));
export const setTracked = (state, qid, on) => (!story(state).questStates[qid] ? fail(state, 'story_not_accepted')
  : patch(state, (S) => (S.questStates[qid].tracked = !!on)));

/** Re-evaluate walking progress without new samples (app open, entering the Village). */
export function storyTick(state, now) {
  const s = clone(state);
  const events = applyStoryProgress(s, now);
  return ok(events.length ? s : state, events);
}

// ----------------------------------------------------------------- views ----
/** Where to go next for a quest: { kind: 'talk'|'walk'|'handin'|'done', npc, place, turnIn } */
export function nextStep(state, qid) {
  const q = QUESTS[qid];
  const phase = questPhase(state, qid);
  if (phase === 'completed') return { kind: 'done' };
  if (phase === 'locked') return { kind: 'locked', npc: q.giver, place: NPCS[q.giver].location };
  if (phase === 'available') return { kind: 'talk', npc: q.giver, place: NPCS[q.giver].location };
  if (q.walk && phase === q.walk.phase) return { kind: 'walk' };
  const t = q.turnIns.find((x) => x.from === phase);
  if (!t) return { kind: 'done' };
  const place = t.npc === 'waystone' || t.npc === 'cottage' || t.npc === 'ruins' || t.npc === 'gate' ? t.npc : NPCS[t.npc].location;
  const needs = itemNeeds(state, t);
  if (needs.some((x) => !x.ok)) return { kind: 'gather', npc: t.npc, place, turnIn: t.id, label: t.label, needs, encounter: t.encounter || null };
  if (!stageOk(state, t)) return { kind: 'grow', npc: t.npc, place, turnIn: t.id, label: t.label, stage: t.requireStage };
  if (t.encounter) return { kind: 'encounter', npc: t.npc, place, turnIn: t.id, label: t.label, needs, encounter: t.encounter };
  return { kind: 'handin', npc: t.npc, place, turnIn: t.id, label: t.label, needs };
}

export function fill(text, vars) {
  return text.replace(/\{(\w+)\}/g, (m, k) => (vars[k] !== undefined ? vars[k] : m));
}

function fmtN(n) {
  return Math.round(n).toLocaleString('en-US');
}

/** Everything the Journey card, quest details and the Village need about one quest. */
export function questView(state, qid, now) {
  const q = QUESTS[qid];
  const st = story(state).questStates[qid] || null;
  const phase = questPhase(state, qid);
  const lock = phase === 'locked' ? lockReason(state, qid) : null;
  const resolved = resolvedSteps(state, qid, now);
  const tz = state.player?.timezone || state.tzHint || 'UTC';
  const today = dayKey(now, tz);
  const qualified = story(state).qualifiedDayKeys[qid] || [];
  let walk = q.walk ? { target: resolved, days: q.walk.days, type: q.walk.type } : null;
  if (st && q.walk) {
    if (q.walk.type === 'incremental') {
      const total = phaseIndex(q, phase) > phaseIndex(q, q.walk.phase) ? resolved : Math.min(resolved, st.freshTotal || 0);
      walk = { ...walk, progress: total, pct: total / resolved };
    } else {
      const todaySteps = st.dayProgress?.[today] || 0;
      walk = {
        ...walk, qualified: qualified.length, todaySteps: Math.min(resolved, todaySteps),
        todayDone: qualified.includes(today), pct: qualified.length / q.walk.days,
      };
    }
  }
  const pi = phaseIndex(q, phase);
  const objectives = q.objectives.map((o) => {
    const done = pi >= phaseIndex(q, o.doneAt);
    const v = { id: o.id, text: fill(o.text, { resolved_steps: fmtN(resolved) }), done, optional: !!o.optional };
    if (o.count) {
      const have = Math.min(o.count.n, ownedQty(state, o.count.item));
      Object.assign(v, { item: o.count.item, need: o.count.n, have: done ? o.count.n : have, ready: done || have >= o.count.n });
    }
    return v;
  });
  const current = objectives.find((o) => !o.done && !o.optional && !(o.ready && o.item))?.id || objectives.find((o) => !o.done && !o.optional)?.id || null;
  const paused = !!st && !!q.walk && phase === q.walk.phase && (!state.steps || state.steps.connection === 'none');
  return {
    id: qid, n: q.n, title: q.title, level: q.level, summary: q.summary, phase, accepted: !!st, lock,
    completed: phase === 'completed', resolved, walk, objectives, current, next: nextStep(state, qid),
    rewards: q.rewards, tracked: st ? st.tracked !== false : false, paused,
    seenCompletion: st?.seenCompletion || false, completedAt: st?.completedAt || null,
    giver: q.giver, dependsOn: q.dependsOn, line: q.line || 'chapter',
  };
}

/** Summary for badges and the Village: quest views, flags, pouch, what needs attention. */
export function storyStatus(state, now) {
  const S = story(state);
  const quests = QUEST_ORDER.map((id) => questView(state, id, now));
  const home = HOME_ORDER.map((id) => questView(state, id, now));
  const side = SIDE_ORDER.map((id) => questView(state, id, now));
  const trail = TRAIL_ORDER.map((id) => questView(state, id, now));
  const all = [...quests, ...home, ...side, ...trail];
  // the Cottage hand-in happens on the Home Map, so it isn't a Village visit
  const turnIns = all.filter((v) => v.next.kind === 'handin' && v.next.npc !== 'cottage');
  const encounters = all.filter((v) => v.next.kind === 'encounter');
  const offers = all.filter((v) => v.phase === 'available' && !S.offersSeen[v.id]);
  const unseenDone = all.filter((v) => v.completed && !v.seenCompletion);
  const actives = all.filter((v) => v.accepted && !v.completed);
  const active = actives.find((v) => v.id === S.activeQuestId) || actives[0] || null;
  const chapterActive = quests.find((v) => v.accepted && !v.completed) || null;
  const nextUp = chapterActive || quests.find((v) => v.phase === 'available')
    || (quests.every((v) => v.completed) ? home.find((v) => v.accepted && !v.completed) || home.find((v) => v.phase === 'available') : null)
    || quests.find((v) => v.phase === 'locked') || null;
  return {
    quests, home, side, trail, all, flags: { ...newStory().flags, ...S.flags }, pouch: { ...S.questPouch }, titles: S.titleUnlocks.slice(),
    active, actives, nextUp, turnIns, encounters, offers, unseenDone, attention: turnIns.length + offers.length,
    chapterDone: quests.every((v) => v.completed), level: accountLevel(state),
    cottageReady: questPhase(state, 'hq01') === 'restoration_ready',
  };
}

/** Which NPCs have something for the player right now (map markers). */
export function npcMarkers(state, now) {
  const out = {};
  for (const qid of ALL_QUESTS) {
    const n = nextStep(state, qid);
    if (n.kind === 'handin') out[n.npc] = 'handin';
    else if (n.kind === 'talk' && !out[n.npc]) out[n.npc] = 'quest';
  }
  return out;
}

// --------------------------------------------------------------- dialogue ----
// Lines are the Quest Bible's script (IDs kept). A few connective lines the Bible implies but doesn't
// write out (locked hints, "still waiting") are marked EXTRA.
export const LINES = {
  VQ01_M00: { s: 'npc_mira', e: 'happy', t: "Oh! You're new to Sunlit Village. I'm Mira. Your Evochi looks curious." },
  VQ01_M01: { s: 'npc_mira', e: 'worried', t: 'The nursery lamp by the gate used to shine every evening. Lately, even the fireflies have forgotten the way home.' },
  VQ01_M02: { s: 'npc_mira', e: 'thinking', t: "Bram says its wick needs a Lumenbud. Those only wake when the morning dew gets stirred up." },
  VQ01_M03: { s: 'npc_mira', e: 'happy', t: "Wonderful! Take your Evochi on a walk. After {resolved_steps} new steps, I'll collect enough Dawn Dew for one sprig." },
  VQ01_M04: { s: 'npc_mira', e: 'neutral', t: "The seedlings are listening. You've walked {progress}/{resolved_steps} steps since we spoke." },
  VQ01_M05: { s: 'npc_mira', e: 'happy', t: 'There it is. A tiny bit of sunrise in a bottle. May I use it to wake this Lumenbud?' },
  VQ01_M06: { s: 'npc_mira', e: 'proud', t: "Look! Three little lights. Take the sprig to Bram's workshop. He'll know where it belongs." },
  VQ01_M07: { s: 'npc_mira', e: 'happy', t: 'Evening looks warmer now. Your footsteps made that happen.' },
  VQ01_B00: { s: 'npc_bram', e: 'worried', t: "A dark lamp and no replacement wick. That's the sort of problem that keeps me up." },
  VQ01_B01: { s: 'npc_bram', e: 'thinking', t: 'Well now. Mira grew a proper Lumenbud? Let me see those glowing leaves.' },
  VQ01_B02: { s: 'npc_bram', e: 'happy', t: 'One twist here, a little spark there... Ha! The village has its glow back.' },
  VQ01_B03: { s: 'npc_bram', e: 'proud', t: 'Keep this Firefly Hearth for your Nest. Good light is meant to be shared.' },
  VQ01_B04: { s: 'npc_bram', e: 'neutral', t: "If that little Hearth ever flickers, don't worry. Good work lasts." },
  VQ02_PIP00: { s: 'npc_pip', e: 'worried', t: 'Delivery for... oh! Sorry, I thought your Evochi was the postbox. The ears threw me off.' },
  VQ02_PIP01: { s: 'npc_pip', e: 'worried', t: 'I promised Alder a letter from beyond the bridge. Trouble is, the wind scattered its special route paper!' },
  VQ02_PIP02: { s: 'npc_pip', e: 'thinking', t: 'Not for an old trail letter. Windprint Paper only appears when someone walks the route with care.' },
  VQ02_PIP03: { s: 'npc_pip', e: 'happy', t: "Two walks, two days. Reach {resolved_steps} steps on each day and we'll have enough paper to seal it." },
  VQ02_PIP04: { s: 'npc_pip', e: 'neutral', t: "We're at {qualifying_days}/2 Windprints. One good walk at a time. No need to rush!" },
  VQ02_PIP05: { s: 'npc_pip', e: 'happy', t: 'Both sheets! Let me fold the corners... and press the Guild seal. There!' },
  VQ02_PIP06: { s: 'npc_pip', e: 'proud', t: 'Please hand this Sealed Trail Letter to Alder at the map desk. I want him to read it first.' },
  VQ02_PIP07: { s: 'npc_pip', e: 'happy', t: 'Delivered! For once, my mail has a happy ending and all its corners.' },
  PIP_LOCKED: { s: 'npc_pip', e: 'thinking', t: "I've got a long delivery brewing, but it's a big route for a little Evochi. {lock_hint} and come find me!", extra: true },
  VQ02_ALD00: { s: 'npc_alder', e: 'neutral', t: 'Maps tell us where the road goes. Letters remind us why it matters.' },
  VQ02_ALD01: { s: 'npc_alder', e: 'thinking', t: "That Guild seal... I haven't seen one of those in many seasons. May I?" },
  VQ02_ALD02: { s: 'npc_alder', e: 'proud', t: "It's the old path record! There was a waystone on the north road. I thought we'd lost its story." },
  VQ02_ALD03: { s: 'npc_alder', e: 'happy', t: 'Pip asked me to give you this Windtrail Mantle. Travelers should look the part.' },
  VQ02_ALD04: { s: 'npc_alder', e: 'neutral', t: "The north road has another chapter left in it. Come back when you're ready." },
  VQ03_ALD00: { s: 'npc_alder', e: 'thinking', t: 'Your letter unlocked an older map. See these three carved lines? They match the sleeping waystone in the Square.' },
  VQ03_ALD01: { s: 'npc_alder', e: 'neutral', t: 'I believe so. The stone remembers three journeys, each on a different day. We need to trace those memories.' },
  VQ03_ALD02: { s: 'npc_alder', e: 'happy', t: 'Walk {resolved_steps} steps on three separate days. Each day will reveal one Echo Rubbing.' },
  VQ03_ALD03: { s: 'npc_alder', e: 'neutral', t: 'Old stones are patient. {qualifying_days}/3 memories found. Rest when you need to.' },
  VQ03_ALD04: { s: 'npc_alder', e: 'proud', t: 'Three complete markings. Bram has the tools to bind them. Take them to his workshop.' },
  ALD_WAITING: { s: 'npc_alder', e: 'thinking', t: 'The Core will want company before it wakes. Mira knows the last ingredient.', extra: true },
  VQ03_ALD05: { s: 'npc_alder', e: 'happy', t: "The best maps don't tell us to hurry. They remind us there's somewhere worth going." },
  VQ03_ALD06: { s: 'npc_alder', e: 'happy', t: 'The village shines differently with you in it.' },
  VQ03_BRA00: { s: 'npc_bram', e: 'thinking', t: "These grooves aren't random scratches. They're a pattern. Here, let me make them a home." },
  VQ03_BRA01: { s: 'npc_bram', e: 'proud', t: "A new Waystone Core. No sparks yet, mind you. You need Mira's Glowbloom Essence for that." },
  VQ03_BRA02: { s: 'npc_bram', e: 'happy', t: 'Not bad for a few careful steps and a stubborn old lampwright.' },
  VQ03_MIR00: { s: 'npc_mira', e: 'happy', t: "You found the stone's memory! The last ingredient isn't rare. It's care, gathered a little every day." },
  VQ03_MIR01: { s: 'npc_mira', e: 'proud', t: "Take this. Plant the Core and Essence together in the Square. I'll meet you under the old lantern." },
  VQ03_MIR02: { s: 'npc_mira', e: 'happy', t: 'Look at that... every path has a little light again.' },
  VQ03_PIP08: { s: 'npc_pip', e: 'happy', t: "I'm going to need a bigger postbag for all this good news!" },
  WAY_LORE: { s: 'waystone', t: 'An old standing stone in the middle of the Square, cool to the touch. Moss has crept into three faint carved lines.', extra: true },
  VQ03_WAY00: { s: 'waystone', t: 'A cool stone with three dark channels. One of its grooves glimmers when your Evochi approaches.' },
  VQ03_WAY01: { s: 'waystone', t: 'The Core settles into the stone. Mint light runs through the grooves. Fireflies rise over Sunlit Village.' },
  WAY_DONE: { s: 'waystone', t: 'Mint light hums in the grooves. Fireflies drift over the Square, and every path out of the village has a little glow.', extra: true },

  // ---- Home Tales 1: A Place to Call Home (Bram)
  HQ01_B00: { s: 'npc_bram', e: 'thinking', t: "That old cottage past your nest? Roof's half gone and the door's wandered off. Shame. It's a good little house." },
  HQ01_B01: { s: 'npc_bram', e: 'neutral', t: "I'll fix it up if you'll lend a hand. I need sturdy timber, the kind you only spot when you're out walking the hedgerows." },
  HQ01_B02: { s: 'npc_bram', e: 'happy', t: "Good! Walk {resolved_steps} steps and keep your eyes open. And grow a few Sunberries for the builders' lunch, eh?" },
  HQ01_B03: { s: 'npc_bram', e: 'neutral', t: 'Timber turns up for walkers. You\'re {progress}/{resolved_steps} steps along. No hurry.' },
  HQ01_B04: { s: 'npc_bram', e: 'thinking', t: "Fine timber, that! Now, about lunch... three Sunberries, if your garden's grown any. You've got {sunberry}/3." },
  HQ01_B05: { s: 'npc_bram', e: 'happy', t: "Timber AND Sunberries. That's a builder's breakfast. Hand them over and I'll get the roof up." },
  HQ01_B06: { s: 'npc_bram', e: 'proud', t: "Roof's on, shutters are hung. The last bit's yours: go and open the place up. It's on your Home Map." },
  HQ01_B07: { s: 'npc_bram', e: 'neutral', t: "It's waiting for you. Go on, open it up." },
  HQ01_B08: { s: 'npc_bram', e: 'happy', t: 'Good roof, good friends. That\'s all a cottage needs.' },
  HQ01_C00: { s: 'cottage', t: 'The old cottage stands quiet. Bram has stacked the timber by the door, and new roof beams are waiting.' },
  HQ01_C01: { s: 'cottage', t: 'Hammers tap, shutters swing open and a warm glow fills the windows. The chimney gives a happy little puff.' },
  HQ01_C02: { s: 'cottage', t: 'An old cottage with a broken roof and an empty doorway. Someone in the village might know how to fix it.', extra: true },
  HQ01_B09: { s: 'npc_bram', e: 'proud', t: 'There. A hearth, a kitchen, and a place to call home. Welcome in.' },

  // ---- Home Tales 2: Mira's Mortar (Mira)
  HQ02_M00: { s: 'npc_mira', e: 'happy', t: 'Your kitchen smells lovely, all the way from here! Have you ever tried brewing?' },
  HQ02_M01: { s: 'npc_mira', e: 'thinking', t: "My grandmother's mortar is gathering dust. Bring me two Glowleaf from your garden and I'll show you how it's done." },
  HQ02_M02: { s: 'npc_mira', e: 'happy', t: 'Glowleaf grows slowly, so plant it early. You\'ll need Farming level 3 to coax it out of the soil.' },
  HQ02_M03: { s: 'npc_mira', e: 'neutral', t: 'Any Glowleaf yet? You have {glowleaf}/2. The seedlings say hello.' },
  HQ02_M04: { s: 'npc_mira', e: 'happy', t: "Oh, they're glowing beautifully! Here, take the mortar. Your cottage has a little back room that would suit it." },
  HQ02_M05: { s: 'npc_mira', e: 'proud', t: 'The Apothecary is yours. Start with a Glowleaf Tonic. Stir slowly, smile often.' },
  HQ02_M06: { s: 'npc_mira', e: 'happy', t: 'How are the brews going? Your Evochi looks very well looked after.' },

  // ---- Side story: The Shy Visitor (Pip)
  SQ01_P00: { s: 'npc_pip', e: 'thinking', t: "Psst! Something small and fluffy keeps peeking at the mail sacks. I think it's hungry, but it's SO shy." },
  SQ01_P01: { s: 'npc_pip', e: 'happy', t: "They say shy visitors can't resist a fresh Sunberry Tart. Could you bake one?" },
  SQ01_P02: { s: 'npc_pip', e: 'happy', t: 'Bake it in your Cottage kitchen and bring it here. I\'ll leave it on the step!' },
  SQ01_P03: { s: 'npc_pip', e: 'neutral', t: 'No tart yet? Sunberries, wheat and a warm oven. You can do it!' },
  SQ01_P04: { s: 'npc_pip', e: 'happy', t: "It smells amazing! Let me put it on the step... shh... look!" },
  SQ01_P05: { s: 'npc_pip', e: 'proud', t: 'A little fox-sprite! It took the tart and left some Moonshroom spores behind. I think that means thank you.' },
  SQ01_P06: { s: 'npc_pip', e: 'happy', t: 'The fox-sprite waves at me now. Well, it wiggles its tail. Same thing!' },

  // ---- Side story: Guardian of the Old Grove (Alder)
  SQ02_A00: { s: 'npc_alder', e: 'thinking', t: 'There is an old guardian in the grove past the north road. It only wakes for an Evochi that has grown a little.' },
  SQ02_A01: { s: 'npc_alder', e: 'neutral', t: 'Bring a Glowleaf Tonic. The guardian is very old, and very thirsty.' },
  SQ02_A02: { s: 'npc_alder', e: 'happy', t: 'Brew one in your Apothecary, then come and find me. We\'ll walk there together.' },
  SQ02_A03: { s: 'npc_alder', e: 'neutral', t: 'The grove is patient. A Glowleaf Tonic, whenever you have one.' },
  SQ02_A04: { s: 'npc_alder', e: 'proud', t: 'A fine tonic. The guardian opens one mossy eye, drinks, and the whole grove sighs with green light.' },
  SQ02_A05: { s: 'npc_alder', e: 'happy', t: 'It remembered {pet}. Few travellers can say that.' },
  SQ02_A06: { s: 'npc_alder', e: 'happy', t: 'The old grove has been greener since your visit.' },
  SQ02_ALOCK: { s: 'npc_alder', e: 'thinking', t: 'Your Evochi is still very young. When it has grown into a Juvenile, ask me about the old grove.', extra: true },

  // ---- The Waystone's map (after Chapter 1): Alder's lore reveal
  ALD_MAP00: { s: 'npc_alder', e: 'surprised', t: "Something strange happened when the Waystone woke. It doesn't just light the Square. Look: it's projecting a map." },
  ALD_MAP01: { s: 'npc_alder', e: 'thinking', t: 'Ancient paths, reaching into regions nobody has walked in generations. The old books called them the Lumen Trails.' },
  ALD_MAP02: { s: 'npc_alder', e: 'neutral', t: 'One trail leads to the Whispering Woods. Another toward a coastal cove. And a third, far older, has nearly vanished.' },
  ALD_MAP03: { s: 'npc_alder', e: 'proud', t: "Evochi weren't made to fight one another, {pet}. They were guardians of these paths. Every species kept the world connected." },
  ALD_MAP04: { s: 'npc_alder', e: 'thinking', t: "So here is our mystery: why did the trails fade, and why have some guardians forgotten their purpose? The Guild's discoveries will help us find out." },

  // ---- Trail 1: The Forest Guardian (Pip)
  EQ01_P00: { s: 'npc_pip', e: 'happy', t: "Guild business! We've spotted an unusual Evochi near the Mossy Ruins. Leafy ears, a flower on its head, FAST." },
  EQ01_P01: { s: 'npc_pip', e: 'thinking', t: "It's shy, so no chasing. Follow the clues on a walk, bring something it might like to eat, and let it come to you." },
  EQ01_P02: { s: 'npc_pip', e: 'happy', t: 'Walk {resolved_steps} steps and keep your eyes on the path. A Sunberry Tart wouldn\'t hurt either!' },
  EQ01_P03: { s: 'npc_pip', e: 'neutral', t: 'Any sign of it? You\'re {progress}/{resolved_steps} steps along the trail.' },
  EQ01_P04: { s: 'npc_pip', e: 'happy', t: "A clue! Pressed flower, green fur. It's at the ruins, I'd bet my satchel. Go gently." },
  EQ01_P05: { s: 'npc_pip', e: 'proud', t: 'You made friends with it?! A Petalune! The Guild hasn\'t logged one in forty years. Welcome to the Guild proper, Trail Friend.' },
  EQ01_P06: { s: 'npc_pip', e: 'happy', t: 'Petalune keeps leaving petals on my mail sacks. I think it likes you.' },
  EQ01_LOCK: { s: 'npc_pip', e: 'thinking', t: "The Guild only sends members after wild Evochi. Finish a couple of daily discoveries first ({discoveries}/2 so far) and I'll put your name down.", extra: true },

  // ---- Trail 2: Tangled Lumen (Mira)
  EQ02_M00: { s: 'npc_mira', e: 'worried', t: "Petalune led me to something sad at the ruins. A little plant spirit, all tangled up in purple light. It isn't sick. It's... faded." },
  EQ02_M01: { s: 'npc_mira', e: 'thinking', t: 'The old books call it the Hollow: Lumen gone unstable. Kindness steadies it. Fresh Glowleaf helps most of all.' },
  EQ02_M02: { s: 'npc_mira', e: 'happy', t: 'Walk {resolved_steps} steps near the ruins to gather a trace of its Lumen, and bring two Glowleaf from your garden.' },
  EQ02_M03: { s: 'npc_mira', e: 'neutral', t: 'How is the poor thing? You\'ll need 2 Glowleaf ({glowleaf}/2) and a steady heart.' },
  EQ02_M04: { s: 'npc_mira', e: 'proud', t: "You restored it! Look at it bloom. Here, I wrote down a recipe: Lantern Tonic. Lumen Shards and Glowleaf. The Guild will want it." },
  EQ02_M05: { s: 'npc_mira', e: 'happy', t: 'The little sprout waves at everyone now. Whatever the Hollow is, it can be undone.' },

  // ---- Trail 3: The Forgotten Sentinel (Alder)
  EQ03_A00: { s: 'npc_alder', e: 'thinking', t: "The faded third trail on the map. I've matched it to the north road, past the old bridge. There's a gate there, and something very old sleeping at it." },
  EQ03_A01: { s: 'npc_alder', e: 'worried', t: "A guardian of the trails, tangled in Hollow for longer than anyone remembers. It won't be gentle. But it isn't our enemy." },
  EQ03_A02: { s: 'npc_alder', e: 'neutral', t: 'Walk {resolved_steps} steps along the north road while I copy the map. Bring a Lantern Tonic: nothing steadies the Hollow like Lumen in a bottle.' },
  EQ03_A03: { s: 'npc_alder', e: 'neutral', t: 'The bridge will hold. The question is the guardian. Lantern Tonic, a grown Evochi if you have one, and patience.' },
  EQ03_A04: { s: 'npc_alder', e: 'proud', t: "You restored a Sentinel. The map changed the moment it woke: the third trail is bright again, and it goes on past the horizon." },
  EQ03_A05: { s: 'npc_alder', e: 'happy', t: "I'll be honest, {pet}. I don't think the trails faded because the world was dying. I think they faded because people stopped exploring it." },
  EQ03_A06: { s: 'npc_alder', e: 'happy', t: 'The Sentinel hums at dusk now. Pip says it sounds like the Waystone. More Trails are on the way, Trailwarden.' },
};

// Choice helpers: next = another line, act = an engine action run before moving on
const C = (label, o = {}) => ({ label, ...o });
const LEAVE = (label = 'Leave') => C(label, { leave: true });

/**
 * The conversation an NPC opens with in the current state: a small graph of nodes
 * { id, choices[] } where a choice has `next` (line id), `act` ({ kind: 'accept'|'handin', ... }),
 * `goto` (place id or 'journey'), `then` (line after the act) or `leave`.
 */
export function npcConversation(state, npcId, now) {
  const S = story(state);
  const ph = (qid) => questPhase(state, qid);
  const met = !!S.npcsMet[npcId];
  const N = {};
  const node = (id, choices) => (N[id] = { id, choices });
  let start;
  if (npcId === 'npc_mira') {
    const p3 = ph('vq03');
    const p1 = ph('vq01');
    if (p3 === 'core_ready') {
      start = node('VQ03_MIR00', [C('Ask Mira for Glowbloom Essence', { act: { kind: 'handin', quest: 'vq03', turnIn: 'mira_essence' }, then: 'VQ03_MIR01' }), LEAVE('Not yet')]).id;
      node('VQ03_MIR01', [C('Go to the Waystone', { goto: 'waystone' }), LEAVE()]);
    } else if (p3 === 'restoration_ready') {
      start = node('VQ03_MIR01', [C('Go to the Waystone', { goto: 'waystone' }), LEAVE()]).id;
    } else if (p1 === 'available') {
      node('VQ01_M01', [C('What happened to it?', { next: 'VQ01_M02' }), C('I can help.', { act: { kind: 'accept', quest: 'vq01' }, then: 'VQ01_M03' }), LEAVE('Maybe later.')]);
      node('VQ01_M02', [C('I can help.', { act: { kind: 'accept', quest: 'vq01' }, then: 'VQ01_M03' }), LEAVE('Maybe later.')]);
      node('VQ01_M03', [C('Go for a walk', { goto: 'journey' }), LEAVE('See you soon')]);
      start = met ? 'VQ01_M01' : node('VQ01_M00', [C('Nice to meet you!', { next: 'VQ01_M01' })]).id;
    } else if (p1 === 'accepted_walk') {
      start = node('VQ01_M04', [C('Go for a walk', { goto: 'journey' }), LEAVE('See you soon')]).id;
    } else if (p1 === 'dew_ready') {
      start = node('VQ01_M05', [C('Give Dawn Dew Vial', { act: { kind: 'handin', quest: 'vq01', turnIn: 'mira_dew' }, then: 'VQ01_M06' }), LEAVE('Not yet')]).id;
      node('VQ01_M06', [C("Go to Bram's Workshop", { goto: 'workshop' }), LEAVE()]);
    } else if (p1 === 'sprig_ready') {
      start = node('VQ01_M06', [C("Go to Bram's Workshop", { goto: 'workshop' }), LEAVE()]).id;
    } else if (ph('hq02') === 'available') {
      node('HQ02_M00', [C('Brewing?', { next: 'HQ02_M01' })]);
      node('HQ02_M01', [C("I'd love to learn.", { act: { kind: 'accept', quest: 'hq02' }, then: 'HQ02_M02' }), LEAVE('Maybe later.')]);
      node('HQ02_M02', [C('Visit your Garden', { goto: 'garden' }), LEAVE('See you soon')]);
      start = 'HQ02_M00';
    } else if (ph('hq02') === 'need_glowleaf') {
      if (nextStep(state, 'hq02').kind === 'handin') {
        start = node('HQ02_M04', [C('Give 2 Glowleaf', { act: { kind: 'handin', quest: 'hq02', turnIn: 'mira_glowleaf' }, then: 'HQ02_M05' }), LEAVE('Not yet')]).id;
        node('HQ02_M05', [C('Thank you, Mira!', { reward: 'hq02' })]);
      } else start = node('HQ02_M03', [C('Visit your Garden', { goto: 'garden' }), LEAVE('See you soon')]).id;
    } else if (ph('eq02') === 'available') {
      node('EQ02_M00', [C('Faded?', { next: 'EQ02_M01' })]);
      node('EQ02_M01', [C("I'll help it.", { act: { kind: 'accept', quest: 'eq02' }, then: 'EQ02_M02' }), LEAVE('Maybe later.')]);
      node('EQ02_M02', [C('Go for a walk', { goto: 'journey' }), C('Visit your Garden', { goto: 'garden' }), LEAVE('See you soon')]);
      start = 'EQ02_M00';
    } else if (ph('eq02') === 'accepted_walk') {
      start = node('EQ02_M03', [C('Go for a walk', { goto: 'journey' }), C('Visit your Garden', { goto: 'garden' }), LEAVE('See you soon')]).id;
    } else if (ph('eq02') === 'ruins_ready') {
      start = node('EQ02_M03', [C('Go to the Mossy Ruins', { goto: 'prep:eq02' }), C('Visit your Garden', { goto: 'garden' }), LEAVE('See you soon')]).id;
    } else if (ph('eq02') === 'completed' && !S.npcsMet.eq02_thanks) {
      start = node('EQ02_M04', [C('Thank you, Mira!', { act: { kind: 'met', npc: 'eq02_thanks' }, leave: true })]).id;
    } else if (p3 === 'completed' && ph('eq02') !== 'completed') {
      start = node('VQ03_MIR02', [LEAVE('Goodbye, Mira')]).id;
    } else if (ph('eq02') === 'completed') {
      start = node('EQ02_M05', [LEAVE('Goodbye, Mira')]).id;
    } else if (ph('hq02') === 'completed') {
      start = node('HQ02_M06', [LEAVE('Goodbye, Mira')]).id;
    } else {
      start = node('VQ01_M07', [LEAVE('Goodbye, Mira')]).id;
    }
  } else if (npcId === 'npc_bram') {
    const p3 = ph('vq03');
    const p1 = ph('vq01');
    const h1 = ph('hq01');
    if (p3 === 'rubbings_ready') {
      start = node('VQ03_BRA00', [C('Give 3 Echo Rubbings', { act: { kind: 'handin', quest: 'vq03', turnIn: 'bram_rubbings' }, then: 'VQ03_BRA01' }), LEAVE('Not yet')]).id;
      node('VQ03_BRA01', [C("Go to Mira's Glasshouse", { goto: 'glasshouse' }), LEAVE()]);
    } else if (p3 === 'core_ready') {
      start = node('VQ03_BRA01', [C("Go to Mira's Glasshouse", { goto: 'glasshouse' }), LEAVE()]).id;
    } else if (p1 === 'sprig_ready') {
      start = node('VQ01_B01', [C('Give Lumenbud Sprig', { act: { kind: 'handin', quest: 'vq01', turnIn: 'bram_sprig' }, then: 'VQ01_B02' }), LEAVE('Not yet')]).id;
      node('VQ01_B02', [C('Continue', { next: 'VQ01_B03' })]);
      node('VQ01_B03', [C('Thank you, Bram!', { reward: 'vq01' })]);
    } else if (h1 === 'available') {
      node('HQ01_B00', [C('What does it need?', { next: 'HQ01_B01' })]);
      node('HQ01_B01', [C("I'll help!", { act: { kind: 'accept', quest: 'hq01' }, then: 'HQ01_B02' }), LEAVE('Maybe later.')]);
      node('HQ01_B02', [C('Go for a walk', { goto: 'journey' }), C('Visit your Garden', { goto: 'garden' }), LEAVE('See you soon')]);
      start = 'HQ01_B00';
    } else if (h1 === 'accepted_walk') {
      start = node('HQ01_B03', [C('Go for a walk', { goto: 'journey' }), C('Visit your Garden', { goto: 'garden' }), LEAVE('See you soon')]).id;
    } else if (h1 === 'timber_ready') {
      if (nextStep(state, 'hq01').kind === 'handin') {
        start = node('HQ01_B05', [C('Give the timber and 3 Sunberries', { act: { kind: 'handin', quest: 'hq01', turnIn: 'bram_timber' }, then: 'HQ01_B06' }), LEAVE('Not yet')]).id;
        node('HQ01_B06', [C('Go to your Cottage', { goto: 'cottage' }), LEAVE()]);
      } else start = node('HQ01_B04', [C('Visit your Garden', { goto: 'garden' }), LEAVE('See you soon')]).id;
    } else if (h1 === 'restoration_ready') {
      start = node('HQ01_B07', [C('Go to your Cottage', { goto: 'cottage' }), LEAVE()]).id;
    } else if (p3 === 'completed') {
      start = node('VQ03_BRA02', [LEAVE('Goodbye, Bram')]).id;
    } else if (h1 === 'completed') {
      start = node('HQ01_B08', [LEAVE('Goodbye, Bram')]).id;
    } else if (p1 === 'completed') {
      start = node('VQ01_B04', [LEAVE('Goodbye, Bram')]).id;
    } else {
      start = node('VQ01_B00', [LEAVE()]).id;
    }
  } else if (npcId === 'npc_pip') {
    const p2 = ph('vq02');
    const p3 = ph('vq03');
    const s1 = ph('sq01');
    if (p2 === 'paper_2_ready') {
      start = node('VQ02_PIP05', [C('Give 2 Windprint Papers', { act: { kind: 'handin', quest: 'vq02', turnIn: 'pip_papers' }, then: 'VQ02_PIP06' }), LEAVE('Not yet')]).id;
      node('VQ02_PIP06', [C('Talk to Alder', { npc: 'npc_alder' }), LEAVE()]);
    } else if (p2 === 'letter_ready') {
      start = node('VQ02_PIP06', [C('Talk to Alder', { npc: 'npc_alder' }), LEAVE()]).id;
    } else if (ph('eq01') === 'available') {
      // the Guild's first trail job: offered as soon as it unlocks, even mid-chapter
      node('EQ01_P00', [C('Shy how?', { next: 'EQ01_P01' })]);
      node('EQ01_P01', [C("I'll find it.", { act: { kind: 'accept', quest: 'eq01' }, then: 'EQ01_P02' }), LEAVE('Not now.')]);
      node('EQ01_P02', [C('Go for a walk', { goto: 'journey' }), C('Go to your Kitchen', { goto: 'kitchen' }), LEAVE('See you soon')]);
      start = met ? 'EQ01_P00' : node('VQ02_PIP00', [C('Hello, Pip!', { next: 'EQ01_P00' })]).id;
    } else if (ph('eq01') === 'accepted_walk') {
      start = node('EQ01_P03', [C('Go for a walk', { goto: 'journey' }), LEAVE('See you soon')]).id;
    } else if (ph('eq01') === 'ruins_ready') {
      start = node('EQ01_P04', [C('Go to the Mossy Ruins', { goto: 'prep:eq01' }), LEAVE('Not yet')]).id;
    } else if (ph('eq01') === 'completed' && !S.npcsMet.eq01_thanks) {
      start = node('EQ01_P05', [C('Thank you, Pip!', { act: { kind: 'met', npc: 'eq01_thanks' }, leave: true })]).id;
    } else if (p2 === 'locked') {
      node('PIP_LOCKED', [LEAVE('Okay!')]);
      start = met ? 'PIP_LOCKED' : node('VQ02_PIP00', [C('Hello, Pip!', { next: 'PIP_LOCKED' })]).id;
    } else if (p2 === 'available') {
      node('VQ02_PIP01', [C("Can't you use ordinary paper?", { next: 'VQ02_PIP02' }), C("I'll help deliver it.", { act: { kind: 'accept', quest: 'vq02' }, then: 'VQ02_PIP03' }), LEAVE('Not now.')]);
      node('VQ02_PIP02', [C("I'll help deliver it.", { act: { kind: 'accept', quest: 'vq02' }, then: 'VQ02_PIP03' }), LEAVE('Not now.')]);
      node('VQ02_PIP03', [C('Go for a walk', { goto: 'journey' }), LEAVE('See you soon')]);
      start = met ? 'VQ02_PIP01' : node('VQ02_PIP00', [C('Hello, Pip!', { next: 'VQ02_PIP01' })]).id;
    } else if (p2 === 'accepted_two_days') {
      // mid-walk: Pip nudges you on, and mentions the Guild's rule for its first trail job once
      const lockHint = ph('eq01') === 'locked' && lockReason(state, 'eq01')?.needDiscoveries && !lockReason(state, 'eq01').needQuest && !S.npcsMet.eq01_hint;
      if (lockHint) {
        node('EQ01_LOCK', [C("See today's discoveries", { goto: 'discover', act: { kind: 'met', npc: 'eq01_hint' } }), C('Okay!', { act: { kind: 'met', npc: 'eq01_hint' }, leave: true })]);
        start = 'EQ01_LOCK';
      } else start = node('VQ02_PIP04', [C('Go for a walk', { goto: 'journey' }), LEAVE('See you soon')]).id;
    } else if (ph('eq01') === 'locked' && lockReason(state, 'eq01')?.needDiscoveries && p2 !== 'available' && p2 !== 'locked') {
      start = node('EQ01_LOCK', [C("See today's discoveries", { goto: 'discover' }), LEAVE('Okay!')]).id;
    } else if (s1 === 'available') {
      node('SQ01_P00', [C('Hungry?', { next: 'SQ01_P01' })]);
      node('SQ01_P01', [C("I'll bake one!", { act: { kind: 'accept', quest: 'sq01' }, then: 'SQ01_P02' }), LEAVE('Not now.')]);
      node('SQ01_P02', [C('Go to your Kitchen', { goto: 'kitchen' }), LEAVE('See you soon')]);
      start = 'SQ01_P00';
    } else if (s1 === 'need_tart') {
      if (nextStep(state, 'sq01').kind === 'handin') {
        start = node('SQ01_P04', [C('Give a Sunberry Tart', { act: { kind: 'handin', quest: 'sq01', turnIn: 'pip_tart' }, then: 'SQ01_P05' }), LEAVE('Not yet')]).id;
        node('SQ01_P05', [C('Thank you, Pip!', { reward: 'sq01' })]);
      } else start = node('SQ01_P03', [C('Go to your Kitchen', { goto: 'kitchen' }), LEAVE('See you soon')]).id;
    } else if (p3 === 'completed') {
      start = node('VQ03_PIP08', [LEAVE('Goodbye, Pip')]).id;
    } else if (ph('eq01') === 'completed' && (s1 === 'completed' || s1 === 'locked')) {
      start = node('EQ01_P06', [LEAVE('Goodbye, Pip')]).id;
    } else if (s1 === 'completed') {
      start = node('SQ01_P06', [LEAVE('Goodbye, Pip')]).id;
    } else {
      start = node('VQ02_PIP07', [LEAVE('Goodbye, Pip')]).id;
    }
  } else if (npcId === 'npc_alder') {
    const p2 = ph('vq02');
    const p3 = ph('vq03');
    if (p2 === 'letter_ready') {
      start = node('VQ02_ALD01', [C('Hand over the Sealed Trail Letter', { act: { kind: 'handin', quest: 'vq02', turnIn: 'alder_letter' }, then: 'VQ02_ALD02' }), LEAVE('Not yet')]).id;
      node('VQ02_ALD02', [C('Continue', { next: 'VQ02_ALD03' })]);
      node('VQ02_ALD03', [C('Thank you, Alder!', { reward: 'vq02' })]);
    } else if (p3 === 'available') {
      node('VQ03_ALD00', [C('Can it be repaired?', { next: 'VQ03_ALD01' }), C("Let's wake it.", { act: { kind: 'accept', quest: 'vq03' }, then: 'VQ03_ALD02' }), LEAVE('I need more time.')]);
      node('VQ03_ALD01', [C("Let's wake it.", { act: { kind: 'accept', quest: 'vq03' }, then: 'VQ03_ALD02' }), LEAVE('I need more time.')]);
      node('VQ03_ALD02', [C('Go for a walk', { goto: 'journey' }), LEAVE('See you soon')]);
      start = 'VQ03_ALD00';
    } else if (p3 === 'accepted_three_days') {
      start = node('VQ03_ALD03', [C('Go for a walk', { goto: 'journey' }), LEAVE('See you soon')]).id;
    } else if (p3 === 'rubbings_ready') {
      start = node('VQ03_ALD04', [C("Go to Bram's Workshop", { goto: 'workshop' }), LEAVE()]).id;
    } else if (p3 === 'core_ready' || p3 === 'restoration_ready') {
      start = node('ALD_WAITING', [C(p3 === 'core_ready' ? "Go to Mira's Glasshouse" : 'Go to the Waystone', { goto: p3 === 'core_ready' ? 'glasshouse' : 'waystone' }), LEAVE()]).id;
    } else if (p3 === 'completed' && !S.npcsMet.waystone_map) {
      node('ALD_MAP00', [C('A map?', { next: 'ALD_MAP01' })]);
      node('ALD_MAP01', [C('Where do they go?', { next: 'ALD_MAP02' })]);
      node('ALD_MAP02', [C('Continue', { next: 'ALD_MAP03' })]);
      node('ALD_MAP03', [C('Continue', { next: 'ALD_MAP04' })]);
      node('ALD_MAP04', [C("Let's find out", { act: { kind: 'met', npc: 'waystone_map' }, leave: true })]);
      start = 'ALD_MAP00';
    } else if (ph('eq03') === 'available') {
      node('EQ03_A00', [C('Something old?', { next: 'EQ03_A01' })]);
      node('EQ03_A01', [C("Let's wake it.", { act: { kind: 'accept', quest: 'eq03' }, then: 'EQ03_A02' }), LEAVE('I need more time.')]);
      node('EQ03_A02', [C('Go for a walk', { goto: 'journey' }), C('Go to your Apothecary', { goto: 'apothecary' }), LEAVE('See you soon')]);
      start = 'EQ03_A00';
    } else if (ph('eq03') === 'accepted_walk') {
      start = node('EQ03_A03', [C('Go for a walk', { goto: 'journey' }), C('Go to your Apothecary', { goto: 'apothecary' }), LEAVE('See you soon')]).id;
    } else if (ph('eq03') === 'gate_ready') {
      start = node('EQ03_A03', [C('Go to the old gate', { goto: 'prep:eq03' }), C('Go to your Apothecary', { goto: 'apothecary' }), LEAVE('See you soon')]).id;
    } else if (ph('eq03') === 'completed' && !S.npcsMet.eq03_thanks) {
      node('EQ03_A04', [C('Continue', { next: 'EQ03_A05' })]);
      node('EQ03_A05', [C('Thank you, Alder', { act: { kind: 'met', npc: 'eq03_thanks' }, leave: true })]);
      start = 'EQ03_A04';
    } else if (ph('eq03') === 'completed' && ph('sq02') !== 'available' && ph('sq02') !== 'need_tonic') {
      start = node('EQ03_A06', [LEAVE('Goodbye, Alder')]).id;
    } else if (ph('sq02') === 'available') {
      node('SQ02_A00', [C('What does it need?', { next: 'SQ02_A01' })]);
      node('SQ02_A01', [C("Let's wake it.", { act: { kind: 'accept', quest: 'sq02' }, then: 'SQ02_A02' }), LEAVE('Another time.')]);
      node('SQ02_A02', [C('Go to your Apothecary', { goto: 'apothecary' }), LEAVE('See you soon')]);
      start = 'SQ02_A00';
    } else if (ph('sq02') === 'need_tonic') {
      if (nextStep(state, 'sq02').kind === 'handin') {
        start = node('SQ02_A04', [C('Offer the Glowleaf Tonic', { act: { kind: 'handin', quest: 'sq02', turnIn: 'alder_tonic' }, then: 'SQ02_A05' }), LEAVE('Not yet')]).id;
        node('SQ02_A05', [C('Thank you, Alder!', { reward: 'sq02' })]);
      } else if (nextStep(state, 'sq02').kind === 'grow') {
        start = node('SQ02_ALOCK', [LEAVE('Okay!')]).id;
      } else start = node('SQ02_A03', [C('Go to your Apothecary', { goto: 'apothecary' }), LEAVE('See you soon')]).id;
    } else if (ph('sq02') === 'locked' && ph('hq02') === 'completed' && lockReason(state, 'sq02')?.needStage) {
      start = node('SQ02_ALOCK', [LEAVE('Okay!')]).id;
    } else if (p3 === 'completed') {
      start = node('VQ03_ALD06', [LEAVE('Goodbye, Alder')]).id;
    } else if (ph('sq02') === 'completed') {
      start = node('SQ02_A06', [LEAVE('Goodbye, Alder')]).id;
    } else if (p2 === 'completed') {
      start = node('VQ02_ALD04', [LEAVE()]).id;
    } else {
      start = node('VQ02_ALD00', [LEAVE()]).id;
    }
  } else if (npcId === 'cottage') {
    const h1 = ph('hq01');
    if (h1 === 'restoration_ready') {
      start = node('HQ01_C00', [C('Restore the Cottage', { act: { kind: 'handin', quest: 'hq01', turnIn: 'restore_cottage' }, then: 'HQ01_C01' }), LEAVE('Not yet')]).id;
      node('HQ01_C01', [C('Continue', { next: 'HQ01_B09' })]);
      node('HQ01_B09', [C('Step inside', { reward: 'hq01' })]);
    } else {
      start = node('HQ01_C02', [LEAVE('Back to the map')]).id;
    }
  } else if (npcId === 'waystone') {
    const p3 = ph('vq03');
    if (p3 === 'completed') {
      start = node('WAY_DONE', [LEAVE('Back to the Square')]).id;
    } else if (p3 === 'restoration_ready') {
      start = node('VQ03_WAY00', [C('Restore the Waystone', { act: { kind: 'handin', quest: 'vq03', turnIn: 'restore' }, then: 'VQ03_WAY01' }), LEAVE('Not yet')]).id;
      node('VQ03_WAY01', [C('Continue', { next: 'VQ03_MIR02' })]);
      node('VQ03_MIR02', [C('Continue', { next: 'VQ03_BRA02' })]);
      node('VQ03_BRA02', [C('Continue', { next: 'VQ03_PIP08' })]);
      node('VQ03_PIP08', [C('Continue', { next: 'VQ03_ALD05' })]);
      node('VQ03_ALD05', [C('Claim your rewards', { reward: 'vq03' })]);
    } else if (S.flags.waystone_revealed) {
      start = node('VQ03_WAY00', [LEAVE('Back to the Square')]).id;
    } else {
      start = node('WAY_LORE', [LEAVE('Back to the Square')]).id;
    }
  }
  return { npc: npcId, start, nodes: N };
}

/** Line text with live values filled in. */
export function lineText(state, id, now, petName = 'your Evochi') {
  const L = LINES[id];
  if (!L) return '';
  const P = { VQ01: 'vq01', VQ02: 'vq02', PIP_: 'vq02', HQ01: 'hq01', HQ02: 'hq02', SQ01: 'sq01', SQ02: 'sq02', EQ01: 'eq01', EQ02: 'eq02', EQ03: 'eq03', ALD_: 'vq03' };
  const qid = P[id.slice(0, 4)] || 'vq03';
  const v = questView(state, qid, now);
  const lock = lockReason(state, 'vq02');
  const hint = !lock ? 'Come back soon'
    : lock.needLevel && lock.needQuest ? `Help Mira and Bram light the lamp, reach level ${lock.level},`
      : lock.needLevel ? `Reach level ${lock.level}` : 'Help Mira and Bram light the lamp first,';
  return fill(L.t, {
    resolved_steps: fmtN(v.resolved),
    progress: fmtN(v.walk?.progress || 0),
    qualifying_days: String(v.walk?.qualified || 0),
    lock_hint: hint,
    pet: petName,
    sunberry: String(Math.min(3, ownedQty(state, 'sunberry'))),
    glowleaf: String(Math.min(2, ownedQty(state, 'glowleaf'))),
    discoveries: String(state.trails?.stats?.discoveries || 0),
  });
}
