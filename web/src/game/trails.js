// Lumen Trails: the Trail Guild's daily discoveries, encounter quests, the encounter engine (calm,
// befriend, restore) and companions.
//
// Lore: ancient Lumen Trails once joined every corner of the Evochi world. Lumen is made by movement,
// exploration and bonds, so your real steps restore the trails. Encounters are never fights to the
// finish: wild Evochi are calmed and befriended, Hollow-tangled guardians are restored. Your Evochi
// never faints; you can always retreat and try again.
//
// Rules of thumb:
//  - three authored discoveries a day, picked deterministically per account and day, never random
//  - discovery walks count steps after you begin them (same fresh-sample counting as the story)
//  - encounter quests live in the story engine (line 'trail'); the encounter itself is the hand-in
//  - the encounter is a pure turn-based state machine seeded per attempt, so it replays the same way

import { ITEMS } from './catalog.js';
import { dayKey, addDays, dayEnd } from './time.js';
import { grantItem, ownedQty, addTxn } from './state.js';
import { freshDays, ensureStory, questPhase, nextStep, storyHandIn, QUESTS } from './story.js';

export const TRAILS_SCHEMA = 1;

// ------------------------------------------------------------------ lore ----
export const LORE = {
  title: 'The Fading Paths',
  intro: 'Long ago, luminous paths called Lumen Trails connected every corner of the Evochi world. Lumen is made by movement, exploration and the bonds between living things. Now many paths have faded, dimmed by time and the mysterious Hollow.',
  trails: 'As you explore, befriend Evochi and take more steps together, the Lumen Trails begin to shine again. Every encounter, however small, helps restore light to the world.',
  guild: 'The Trail Guild was formed to restore the pathways. Every day it posts small discoveries, and now and then a trail leads somewhere no one has walked in a very long time.',
};

// --------------------------------------------------------------- guild ----
export const GUILD_RANKS = [
  { id: 'wanderer', name: 'Wanderer', xp: 0 },
  { id: 'trail_friend', name: 'Trail Friend', xp: 40 },
  { id: 'pathfinder', name: 'Pathfinder', xp: 120 },
  { id: 'lightkeeper', name: 'Lightkeeper', xp: 260 },
  { id: 'trailwarden', name: 'Trailwarden', xp: 480 },
];

export function guildRank(xp) {
  let cur = GUILD_RANKS[0];
  let next = null;
  for (let i = 0; i < GUILD_RANKS.length; i++) {
    if (xp >= GUILD_RANKS[i].xp) cur = GUILD_RANKS[i];
    else {
      next = GUILD_RANKS[i];
      break;
    }
  }
  return { ...cur, xp, next, into: xp - cur.xp, need: next ? next.xp - cur.xp : 0 };
}

// --------------------------------------------------------- affinities ----
export const AFFINITIES = {
  nature: { id: 'nature', name: 'Nature', icon: 'aff_nature', color: '#5FA046', explore: 'Grows blocked pathways', ability: 'Root Snare' },
  ember: { id: 'ember', name: 'Ember', icon: 'aff_ember', color: '#EC7A4A', explore: 'Lights ancient torches', ability: 'Spark Burst' },
  water: { id: 'water', name: 'Water', icon: 'aff_water', color: '#4C9BCC', explore: 'Crosses aquatic obstacles', ability: 'Healing Mist' },
  stone: { id: 'stone', name: 'Stone', icon: 'aff_stone', color: '#8E887E', explore: 'Opens cave passages', ability: 'Stone Guard' },
  celestial: { id: 'celestial', name: 'Celestial', icon: 'aff_celestial', color: '#9975C9', explore: 'Reveals hidden ruins', ability: 'Starlight Beam' },
  lumen: { id: 'lumen', name: 'Lumen', icon: 'trail', color: '#F4B84E', explore: 'Walks the old trails', ability: 'Lumen Glow' },
};

// ----------------------------------------------------------- creatures ----
export const CREATURES = {
  petalune: {
    id: 'petalune', name: 'Petalune', affinity: 'nature', kind: 'wild', rarity: 'rare', size: 'small',
    traits: ['Nature', 'Gentle', 'Flower Crest'], home: 'Mossy Ruins',
    blurb: 'A gentle Evochi that spreads seeds wherever it goes. Said to lead others to hidden Lumen Trails.',
    likes: ['sunberry_tart', 'carrot_stew', 'golden_bun'], states: { start: 'wary', mid: 'neutral', done: 'happy' },
    companion: { ability: 'petal_hush', name: 'Petal Hush', text: 'Petalune hums softly: +12 Calm (or -12 Instability), once an encounter.' },
  },
  hollow_sprout: {
    id: 'hollow_sprout', name: 'Hollow Sprout', affinity: 'nature', kind: 'hollow', rarity: 'uncommon', size: 'small',
    traits: ['Hollow', 'Nature (faded)', 'Shy'], home: 'Mossy Ruins',
    blurb: 'A once-thriving forest Evochi, now covered in Hollow growth. It reacts to kindness and care.',
    likes: ['glowleaf', 'meadow_tea', 'healing_herb'], states: { start: 'hollow', mid: 'hollow', done: 'restored' },
  },
  sentinel: {
    id: 'sentinel', name: 'Forgotten Sentinel', affinity: 'celestial', kind: 'hollow', rarity: 'legendary', size: 'large', boss: true,
    traits: ['Hollow', 'Celestial (faded)', 'Ancient'], home: 'The old gate past the bridge',
    blurb: 'A guardian of the Lumen Trails. Its light is dim, but it still listens. Help it remember.',
    likes: ['lantern_tonic', 'glowleaf_tonic', 'moonlight_draught'], states: { start: 'hollow', mid: 'waking', done: 'restored' },
  },
};

// ---------------------------------------------------------- discoveries ----
// An authored pool (never random objectives). `place` is where the glinting clue appears once the walk
// is done. `needs` are story flags / quests that must be true for the entry to be posted.
export const DISCOVERIES = {
  d_seed_pouch: { title: 'The Missing Seed Pouch', place: 'glasshouse', steps: 1500, icon: 'seed_sunberry',
    clue: 'Mira has lost a pouch of seeds somewhere between the seedling trays.',
    found: 'Tucked behind a watering can: a pouch of seeds, and a very relieved Mira.',
    reward: { coins: 20, items: { seed_sunberry: 2, seed_meadow_carrot: 1 }, guildXp: 12 } },
  d_footprint: { title: 'A Strange Footprint', place: 'lodge', steps: 2500, icon: 'discover',
    clue: 'Pip found a small, leafy footprint by the courier counter. Investigate where it leads.',
    found: 'The prints circle the map table and stop at the window. Something small has been watching the village.',
    reward: { coins: 30, items: { lumen_shard: 1 }, guildXp: 18 } },
  d_flicker: { title: 'The Flickering Lantern', place: 'workshop', steps: 1200, icon: 'explorer_lantern',
    clue: "Bram's spare lantern keeps flickering. Take a look at the wick.",
    found: 'A Lumenbud seed had rooted in the wick. Bram keeps it in a jar on the sill now.',
    reward: { coins: 25, items: { healing_herb: 1 }, guildXp: 12 } },
  d_waystone_hum: { title: 'A Hum in the Stone', place: 'waystone', steps: 2000, icon: 'star',
    clue: 'Alder swears the Waystone hums on quiet evenings. Listen closely.',
    found: 'With your ear to the stone you hear it: a faint, steady note, like a path remembering itself.',
    reward: { coins: 30, items: { lumen_shard: 1 }, guildXp: 16 } },
  d_pond_glint: { title: 'A Glint in the Pond', place: 'homemap', steps: 1000, icon: 'lumen_shard',
    clue: 'Something glitters in the pond by your nest after a walk.',
    found: 'A sliver of Lumen, cool and bright, washed up among the lily pads.',
    reward: { coins: 15, items: { lumen_shard: 1 }, guildXp: 10 } },
  d_night_moth: { title: 'The Glow Moths', place: 'garden', steps: 1500, icon: 'skill_farming',
    clue: 'Glow moths gather in gardens where Lumen is strong. See if any have come to yours.',
    found: 'Three pale moths rest on the bed posts. Where they sat, the soil feels warm and ready.',
    reward: { coins: 20, items: { seed_glowleaf: 1 }, guildXp: 14 }, needs: { quest: 'hq01' } },
  d_old_letter: { title: 'The Letter in the Wall', place: 'cottage', steps: 1800, icon: 'q_sealed_trail_letter',
    clue: 'Bram says the old cottage wall had a loose stone with something behind it.',
    found: 'A letter, decades old: a Trail Guild walker writing home about a stone that sings. The last line: "Keep walking. The paths remember us."',
    reward: { coins: 35, items: { lumen_shard: 1 }, guildXp: 20 }, needs: { flag: 'cottage_restored' } },
  d_herb_run: { title: 'Herbs for the Guild', place: 'lodge', steps: 1500, icon: 'healing_herb',
    clue: 'The Guild keeps a first-aid shelf stocked. Walk a round of the village and check it.',
    found: 'The shelf was bare. You restock it from the basket by the door, and Pip pays you back in coins.',
    reward: { coins: 40, items: {}, guildXp: 12 } },
  d_moss_runes: { title: 'Runes under the Moss', place: 'ruins', steps: 2000, icon: 'ancient_relic',
    clue: 'The Mossy Ruins have more carvings than anyone has catalogued. Clear a little moss.',
    found: 'Under the moss, a line of trail runes points away from the village, toward the north road.',
    reward: { coins: 35, items: { lumen_shard: 1 }, guildXp: 22 }, needs: { quest: 'eq01' } },
  d_petal_trail: { title: 'A Trail of Petals', place: 'ruins', steps: 1200, icon: 'creature_petalune',
    clue: 'Petals keep appearing on the path to the ruins. Follow them.',
    found: 'The petals end at the arch, where a small flower has grown overnight in a crack of the stone.',
    reward: { coins: 20, items: { seed_glowleaf: 1 }, guildXp: 14 }, needs: { quest: 'eq01' } },
};
export const DISCOVERY_ORDER = Object.keys(DISCOVERIES);
export const DISCOVERIES_PER_DAY = 3;

export const PLACE_NAMES = {
  glasshouse: "Mira's Glasshouse", workshop: "Bram's Workshop", lodge: 'Trail Guild Lodge', waystone: 'the Waystone',
  homemap: 'your Home Map', garden: 'your Garden', cottage: 'your Cottage', ruins: 'the Mossy Ruins', gate: 'the Old Gate',
};

// ------------------------------------------------------------- helpers ----
function ok(state, events = []) {
  return { state, events, error: null };
}
function fail(state, error, extra = {}) {
  return { state, events: [], error, ...extra };
}
function clone(s) {
  return typeof structuredClone === 'function' ? structuredClone(s) : JSON.parse(JSON.stringify(s));
}
function hashStr(str) {
  let h = 2166136261;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    h = Math.imul(h, 16777619);
  }
  return h >>> 0;
}
function rng(seed) {
  let a = hashStr(seed);
  return () => {
    a |= 0;
    a = (a + 0x6d2b79f5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

export function newTrails() {
  return {
    schemaVersion: TRAILS_SCHEMA,
    guildXp: 0,
    days: {}, // dayKey -> { ids: [...], states: { id: { acceptedAt, foundAt, dayProgress } } }
    companions: {}, // creatureId -> { since, encounters }
    restored: {}, // creatureId -> at
    encounter: null, // the live encounter, or null
    attempts: {}, // questId -> n
    seen: {}, // one-time scenes: waystone_map, guild_intro
    stats: { discoveries: 0, encounters: 0, befriended: 0, restored: 0, retreats: 0 },
  };
}

export function ensureTrails(s) {
  if (!s.trails || typeof s.trails !== 'object') s.trails = newTrails();
  const base = newTrails();
  for (const k of Object.keys(base)) if (s.trails[k] === undefined) s.trails[k] = base[k];
  s.trails.stats = { ...base.stats, ...s.trails.stats };
  return s.trails;
}

function T(state) {
  return state.trails || newTrails();
}
function tzOf(state) {
  return state.player?.timezone || state.tzHint || 'UTC';
}

export function discoveriesDone(state) {
  return T(state).stats.discoveries || 0;
}

function discoveryOpen(state, d) {
  if (!d.needs) return true;
  if (d.needs.flag && !state.story?.flags?.[d.needs.flag]) return false;
  if (d.needs.quest && questPhase(state, d.needs.quest) !== 'completed') return false;
  return true;
}

/** Today's three discoveries: deterministic per account and day, avoiding yesterday's picks. */
export function pickDiscoveries(state, key) {
  const pool = DISCOVERY_ORDER.filter((id) => discoveryOpen(state, DISCOVERIES[id]));
  const prev = T(state).days[addDays(key, -1)]?.ids || [];
  const r = rng(`${state.player?.id || 'guest'}:${key}:discover`);
  const fresh = pool.filter((id) => !prev.includes(id));
  const from = fresh.length >= DISCOVERIES_PER_DAY ? fresh : pool;
  const ids = [];
  const bag = from.slice();
  while (ids.length < DISCOVERIES_PER_DAY && bag.length) ids.push(bag.splice(Math.floor(r() * bag.length), 1)[0]);
  // a mix of places: never two at the same place when the pool allows it
  for (let i = 1; i < ids.length; i++) {
    if (ids.slice(0, i).some((x) => DISCOVERIES[x].place === DISCOVERIES[ids[i]].place)) {
      const alt = bag.find((x) => !ids.slice(0, i).some((y) => DISCOVERIES[y].place === DISCOVERIES[x].place));
      if (alt) {
        bag.splice(bag.indexOf(alt), 1, ids[i]);
        ids[i] = alt;
      }
    }
  }
  return ids;
}

/** Make sure today's board exists on `s` (mutates). Returns the day record. */
function ensureDay(s, now) {
  const tr = ensureTrails(s);
  const key = dayKey(now, tzOf(s));
  if (!tr.days[key]) tr.days[key] = { ids: pickDiscoveries(s, key), states: {} };
  // keep only a few days of history
  for (const k of Object.keys(tr.days)) if (k < addDays(key, -3)) delete tr.days[k];
  return tr.days[key];
}

export function discoveryView(state, id, now) {
  const d = DISCOVERIES[id];
  const key = dayKey(now, tzOf(state));
  const st = T(state).days[key]?.states?.[id] || null;
  const goal = state.player?.goal || 7000;
  const target = Math.min(d.steps, Math.max(500, Math.round(goal * 0.5)));
  let steps = 0;
  if (st?.acceptedAt) steps = Object.values(freshDays(state, st.acceptedAt, tzOf(state))).reduce((a, x) => a + x.steps, 0);
  const walked = Math.min(target, Math.max(steps, st?.walked || 0));
  const phase = st?.foundAt ? 'found' : !st?.acceptedAt ? 'offered' : walked >= target ? 'ready' : 'walking';
  return {
    id, ...d, placeName: PLACE_NAMES[d.place], target, walked, pct: Math.min(1, walked / target), phase,
    acceptedAt: st?.acceptedAt || null, foundAt: st?.foundAt || null,
    rewardText: [d.reward.coins ? `${d.reward.coins} EvoCoins` : null, ...Object.entries(d.reward.items || {}).map(([i, n]) => `${n} × ${ITEMS[i]?.name || i}`)].filter(Boolean).join(' · '),
  };
}

export function trailsStatus(state, now) {
  const tr = T(state);
  const key = dayKey(now, tzOf(state));
  const day = tr.days[key];
  const ids = day ? day.ids : state.player ? pickDiscoveries(state, key) : [];
  const discoveries = ids.map((id) => discoveryView(state, id, now));
  const rank = guildRank(tr.guildXp || 0);
  const companions = Object.entries(tr.companions).map(([id, c]) => ({ ...CREATURES[id], ...c }));
  return {
    discoveries, ready: discoveries.filter((d) => d.phase === 'ready'), walking: discoveries.filter((d) => d.phase === 'walking'),
    offered: discoveries.filter((d) => d.phase === 'offered'), foundToday: discoveries.filter((d) => d.phase === 'found').length,
    rank, companions, restored: { ...tr.restored }, encounter: tr.encounter ? encounterView(state, now) : null,
    stats: { ...tr.stats }, seen: { ...tr.seen }, dayKey: key,
    msToReset: Math.max(0, dayEnd(key, tzOf(state)) - now),
  };
}

/** Which discoveries are ready to inspect at a place (for the glint). */
export function cluesAt(state, place, now) {
  if (!state.player) return [];
  return trailsStatus(state, now).discoveries.filter((d) => d.place === place && d.phase === 'ready');
}

// ------------------------------------------------------ discovery actions ----
export function beginDiscovery(state, id, now) {
  if (!DISCOVERIES[id]) return fail(state, 'unknown_discovery');
  if (!state.player) return fail(state, 'no_player');
  const s = clone(state);
  const day = ensureDay(s, now);
  if (!day.ids.includes(id)) return fail(state, 'not_posted');
  if (day.states[id]?.acceptedAt) return ok(state);
  day.states[id] = { acceptedAt: now, foundAt: null, walked: 0 };
  return ok(s, [{ type: 'discovery_begun', id, title: DISCOVERIES[id].title }]);
}

/** Freeze walking progress (called from syncSteps so late samples never lose a finished walk). */
export function applyTrailProgress(s, now) {
  const events = [];
  if (!s.player) return events;
  const tr = ensureTrails(s);
  const key = dayKey(now, tzOf(s));
  const day = tr.days[key];
  if (!day) return events;
  for (const id of day.ids) {
    const st = day.states[id];
    if (!st || !st.acceptedAt || st.foundAt) continue;
    const before = discoveryView(s, id, now);
    const steps = Object.values(freshDays(s, st.acceptedAt, tzOf(s))).reduce((a, x) => a + x.steps, 0);
    const wasReady = (st.walked || 0) >= before.target;
    st.walked = Math.max(st.walked || 0, steps);
    if (!wasReady && st.walked >= before.target) events.push({ type: 'discovery_ready', id, title: DISCOVERIES[id].title, place: DISCOVERIES[id].place });
  }
  return events;
}

export function inspectDiscovery(state, id, now) {
  const d = DISCOVERIES[id];
  if (!d) return fail(state, 'unknown_discovery');
  const v = discoveryView(state, id, now);
  if (v.phase === 'found') return ok(state, [{ type: 'discovery_already', id }]);
  if (v.phase !== 'ready') return fail(state, 'discovery_not_ready', { need: v.target - v.walked });
  const s = clone(state);
  const tr = ensureTrails(s);
  const day = ensureDay(s, now);
  day.states[id] = { ...(day.states[id] || {}), foundAt: now };
  const txn = `discovery:${dayKey(now, tzOf(s))}:${id}`;
  if (d.reward.coins) addTxn(s, { id: txn, amount: d.reward.coins, currency: 'evocoin', cause: `discovery:${id}`, at: now });
  for (const [iid, n] of Object.entries(d.reward.items || {})) grantItem(s, iid, n, 'discovery', now, txn);
  const rankBefore = guildRank(tr.guildXp).id;
  tr.guildXp += d.reward.guildXp || 0;
  tr.stats.discoveries++;
  const events = [{ type: 'discovery_found', id, title: d.title, reward: d.reward }];
  const rankAfter = guildRank(tr.guildXp);
  if (rankAfter.id !== rankBefore) events.push({ type: 'guild_rank', rank: rankAfter });
  return ok(s, events);
}

export function markTrailSeen(state, key) {
  if (T(state).seen?.[key]) return ok(state);
  const s = clone(state);
  ensureTrails(s).seen[key] = true;
  return ok(s);
}

// ----------------------------------------------------------- encounters ----
// Each encounter quest's hand-in names a creature; the encounter is played out here and the story
// hand-in runs on success. Befriend: fill Calm to 100. Restore: bring Instability to 0.
export const ENCOUNTERS = {
  eq01: { creature: 'petalune', goal: 'befriend', meter: 100, place: 'ruins', scene: 'mossy_ruins', intro: 'rare',
    recommended: { items: ['sunberry_tart'], stage: 1, affinity: 'nature' }, companionOn: 'petalune' },
  eq02: { creature: 'hollow_sprout', goal: 'restore', meter: 100, place: 'ruins', scene: 'mossy_ruins_hollow', intro: 'hollow',
    recommended: { items: ['glowleaf', 'meadow_tea'], stage: 1, affinity: 'nature' } },
  eq03: { creature: 'sentinel', goal: 'restore', meter: 200, place: 'gate', scene: 'sentinel_gate', intro: 'boss',
    recommended: { items: ['lantern_tonic'], stage: 2, affinity: 'celestial' } },
};

export const ACTIONS = {
  lumen_glow: { id: 'lumen_glow', name: 'Lumen Glow', kind: 'light', icon: 'star', energy: 24, power: 16,
    text: 'A warm pulse of Lumen. Strong against the Hollow.' },
  gentle_nudge: { id: 'gentle_nudge', name: 'Gentle Nudge', kind: 'physical', icon: 'play', energy: 10, power: 9,
    text: 'A playful bump. Cheap, and it makes a wild Evochi curious.' },
  soothe: { id: 'soothe', name: 'Soothe', kind: 'restore', icon: 'calm', energy: -30, power: 5,
    text: 'Sit quietly together. Restores 30 Energy and adds a little Calm.' },
  item: { id: 'item', name: 'Use Item', kind: 'item', icon: 'bag', energy: 0, power: 0, text: 'Offer food or a tonic from your Bag.' },
  petal_hush: { id: 'petal_hush', name: 'Petal Hush', kind: 'companion', icon: 'creature_petalune', energy: 0, power: 12,
    text: 'Petalune hums. Once an encounter, no Energy.' },
  retreat: { id: 'retreat', name: 'Retreat', kind: 'retreat', icon: 'back', energy: 0, power: 0, text: 'Leave quietly. Items used are returned.' },
};

/** What an item does in an encounter (Calm for befriending, Instability for restoring). */
export function itemEffect(itemId, goal, creature) {
  const it = ITEMS[itemId];
  if (!it) return null;
  const likes = CREATURES[creature]?.likes || [];
  const base = {
    sunberry_tart: { befriend: 26, restore: 6 }, carrot_stew: { befriend: 22, restore: 6 }, golden_bun: { befriend: 18, restore: 4 },
    moonshroom_pie: { befriend: 30, restore: 10 }, berry_snack: { befriend: 12, restore: 2 },
    glowleaf: { befriend: 10, restore: 18 }, healing_herb: { befriend: 6, restore: 16 }, meadow_tea: { befriend: 16, restore: 16 },
    glowleaf_tonic: { befriend: 14, restore: 24 }, moonlight_draught: { befriend: 12, restore: 30 }, lantern_tonic: { befriend: 20, restore: 44 },
  }[itemId];
  if (!base) return null;
  const amount = Math.round(base[goal] * (likes.includes(itemId) ? 1.5 : 1));
  return { amount, liked: likes.includes(itemId) };
}

export function encounterItems(state, goal, creature) {
  return Object.keys(state.inventory || {}).filter((id) => ownedQty(state, id) > 0 && itemEffect(id, goal, creature))
    .map((id) => ({ id, name: ITEMS[id].name, qty: ownedQty(state, id), ...itemEffect(id, goal, creature) }));
}

function petStage(state) {
  return state.pet?.stage || 1;
}

export function maxEnergy(state) {
  return { 1: 100, 2: 120, 3: 140 }[petStage(state)] || 100;
}

/** Start the encounter for a quest whose hand-in is ready. */
export function startEncounter(state, qid, now) {
  const E = ENCOUNTERS[qid];
  if (!E) return fail(state, 'unknown_encounter');
  if (!state.pet || !state.player) return fail(state, 'no_pet');
  const q = QUESTS[qid];
  const t = q.turnIns.find((x) => x.encounter);
  if (questPhase(state, qid) !== t.from) return fail(state, 'story_not_ready');
  const n = nextStep(state, qid);
  if (n.kind === 'gather') return fail(state, 'story_missing_items', { missing: n.needs.filter((x) => !x.ok) });
  if (T(state).encounter && T(state).encounter.quest !== qid) return fail(state, 'encounter_busy');
  const s = clone(state);
  const tr = ensureTrails(s);
  tr.attempts[qid] = (tr.attempts[qid] || 0) + 1;
  const C = CREATURES[E.creature];
  tr.encounter = {
    quest: qid, creature: E.creature, goal: E.goal, meter: E.goal === 'befriend' ? 0 : E.meter, max: E.meter,
    energy: maxEnergy(s), energyMax: maxEnergy(s), turn: 0, seed: `${s.player.id}:${qid}:${tr.attempts[qid]}`,
    mood: E.goal === 'befriend' ? 'wary' : 'surging', curious: false, used: {}, companionUsed: false, done: null,
    log: [{ who: 'wild', text: E.goal === 'befriend' ? `${C.name} watches you from a distance.` : `${C.name} shudders with Hollow energy.` }],
    startedAt: now,
  };
  tr.stats.encounters++;
  return ok(s, [{ type: 'encounter_started', quest: qid, creature: E.creature }]);
}

function pct(e) {
  return e.goal === 'befriend' ? e.meter / e.max : 1 - e.meter / e.max;
}

/** Everything the encounter screen needs. */
export function encounterView(state, now) {
  const e = T(state).encounter;
  if (!e) return null;
  const C = CREATURES[e.creature];
  const E = ENCOUNTERS[e.quest];
  const p = pct(e);
  const stateKey = e.done === 'success' ? C.states.done : p >= 0.5 ? C.states.mid : C.states.start;
  const companion = T(state).companions.petalune && e.creature !== 'petalune' ? ACTIONS.petal_hush : null;
  const actions = [ACTIONS.lumen_glow, ACTIONS.gentle_nudge, ACTIONS.soothe, ACTIONS.item].map((a) => ({
    ...a, can: !e.done && (a.energy <= 0 || e.energy >= a.energy),
    power: a.kind === 'light' && C.kind === 'hollow' ? Math.round(a.power * 1.3) : a.power,
  }));
  if (companion) actions.push({ ...companion, can: !e.done && !e.companionUsed });
  return {
    ...e, creature: C, scene: E.scene, intro: E.intro, pct: p, pctLabel: Math.round(p * 100), stateKey,
    meterLabel: e.goal === 'befriend' ? 'Calm' : 'Instability', meterShown: e.goal === 'befriend' ? Math.round(e.meter) : Math.round(e.meter),
    actions, items: encounterItems(state, e.goal, e.creature), recommended: E.recommended, boss: !!C.boss,
    phase2: !!C.boss && p >= 0.5,
  };
}

function gain(e, amount) {
  // more Calm, or less Instability; never past the ends
  if (e.goal === 'befriend') e.meter = Math.max(0, Math.min(e.max, e.meter + amount));
  else e.meter = Math.max(0, Math.min(e.max, e.meter - amount));
}

function wildTurn(e, r, C, lastKind) {
  // the creature's reply, seeded so an attempt always plays the same way
  const roll = r();
  if (e.goal === 'befriend') {
    const p = pct(e);
    if (lastKind === 'item' && roll < 0.8) return { text: `${C.name} nibbles, and edges a little closer.`, delta: 4, mood: 'curious' };
    if (p < 0.35 && roll < 0.35) return { text: `${C.name} skitters back behind the stones.`, delta: -6, mood: 'wary' };
    if (p < 0.7 && roll < 0.2) return { text: `${C.name} hides, peeking out at you.`, delta: -3, mood: 'wary' };
    if (roll < 0.5) return { text: `${C.name} tilts its head and watches ${e.curious ? 'with bright eyes' : 'carefully'}.`, delta: 0, mood: 'curious' };
    return { text: `${C.name} sniffs the air and settles.`, delta: 2, mood: p > 0.6 ? 'calm' : 'curious' };
  }
  const p = pct(e);
  const boss = !!C.boss;
  if (boss && p >= 0.5 && roll < 0.45) return { text: 'The Sentinel wakes a little more. Hollow light lashes out!', delta: 0, energy: -18, mood: 'waking' };
  if (roll < (boss ? 0.4 : 0.35)) return { text: `Hollow energy surges through ${C.name}.`, delta: -(boss ? 9 : 7), mood: 'surging' };
  if (roll < 0.6) return { text: `${C.name} flickers. The vines loosen for a moment.`, delta: 0, mood: 'flickering' };
  if (roll < 0.75) return { text: 'A tendril of Hollow whips past you.', delta: 0, energy: -12, mood: 'surging' };
  return { text: `${C.name} goes still, listening.`, delta: 3, mood: 'settling' };
}

/** One turn: your action (plus an item id for 'item'), then the creature's reply. */
export function encounterAct(state, actionId, itemId, now) {
  const e0 = T(state).encounter;
  if (!e0) return fail(state, 'no_encounter');
  if (e0.done) return fail(state, 'encounter_over');
  const A = ACTIONS[actionId];
  if (!A) return fail(state, 'unknown_action');
  const s = clone(state);
  const tr = ensureTrails(s);
  const e = tr.encounter;
  const C = CREATURES[e.creature];
  const events = [];
  const log = (who, text) => e.log.push({ who, text });
  if (actionId === 'retreat') {
    // items used come back: nothing is ever wasted on a retreat
    for (const [id, n] of Object.entries(e.used)) grantItem(s, id, n, 'retreat', now, `retreat:${e.seed}:${id}`);
    tr.encounter = null;
    tr.stats.retreats++;
    return ok(s, [{ type: 'encounter_retreat', quest: e.quest, creature: e.creature }]);
  }
  let amount = 0;
  let kind = A.kind;
  if (actionId === 'item') {
    const fx = itemEffect(itemId, e.goal, e.creature);
    if (!fx || ownedQty(s, itemId) < 1) return fail(state, 'not_owned');
    s.inventory[itemId].quantity -= 1;
    e.used[itemId] = (e.used[itemId] || 0) + 1;
    amount = fx.amount;
    log('you', `You offer ${ITEMS[itemId].name}.${fx.liked ? ` ${C.name} loves it!` : ''}`);
  } else if (actionId === 'petal_hush') {
    if (!tr.companions.petalune || e.creature === 'petalune') return fail(state, 'no_companion');
    if (e.companionUsed) return fail(state, 'companion_used');
    e.companionUsed = true;
    amount = A.power;
    log('you', 'Petalune hums a soft, green note.');
  } else {
    if (A.energy > 0 && e.energy < A.energy) return fail(state, 'no_energy', { need: A.energy });
    e.energy = Math.max(0, Math.min(e.energyMax, e.energy - A.energy));
    amount = A.power;
    if (A.kind === 'light' && C.kind === 'hollow') amount = Math.round(amount * 1.3);
    if (A.kind === 'light' && C.boss && pct(e) >= 0.5) amount = Math.round(amount * 1.25);
    if (A.kind === 'physical' && e.goal === 'befriend') {
      if (e.curious) amount += 4;
      e.curious = true;
    }
    if (A.kind === 'restore') e.curious = false;
    log('you', { light: `${s.pet.name} glows with Lumen.`, physical: `${s.pet.name} gives ${C.name} a gentle nudge.`, restore: `${s.pet.name} sits down quietly. Energy returns.` }[A.kind]);
  }
  gain(e, amount);
  e.turn++;
  if (pct(e) >= 1) return finishEncounter(s, e, events, now);
  const r = rng(`${e.seed}:${e.turn}`);
  const w = wildTurn(e, r, C, kind);
  if (w.delta) gain(e, w.delta);
  if (w.energy) e.energy = Math.max(0, e.energy + w.energy);
  e.mood = w.mood;
  log('wild', w.text);
  if (pct(e) >= 1) return finishEncounter(s, e, events, now);
  events.push({ type: 'encounter_turn', turn: e.turn, you: amount, wild: w.delta || 0 });
  return ok(s, events);
}

function finishEncounter(s, e, events, now) {
  const tr = ensureTrails(s);
  const C = CREATURES[e.creature];
  e.done = 'success';
  e.log.push({ who: 'wild', text: e.goal === 'befriend' ? `${C.name} nuzzles ${s.pet.name}. It trusts you.` : `The Hollow dissolves into motes of light. ${C.name} remembers.` });
  if (e.goal === 'befriend') {
    tr.companions[e.creature] = tr.companions[e.creature] || { since: now, encounters: 0 };
    tr.stats.befriended++;
  } else {
    tr.restored[e.creature] = now;
    tr.stats.restored++;
  }
  events.push({ type: 'encounter_won', quest: e.quest, creature: e.creature, goal: e.goal });
  return ok(s, events);
}

/** Close a finished encounter (after the result screen): the quest's hand-in runs and pays out. */
export function completeEncounter(state, now) {
  const e = T(state).encounter;
  if (!e) return ok(state);
  if (e.done !== 'success') return fail(state, 'encounter_not_won');
  const q = QUESTS[e.quest];
  const t = q.turnIns.find((x) => x.encounter);
  let s = clone(state);
  ensureTrails(s).encounter = null;
  const r = storyHandIn(s, e.quest, t.id, now);
  if (r.error) return fail(state, r.error, r);
  s = r.state;
  const events = [...r.events];
  if (e.goal === 'befriend') events.push({ type: 'companion_joined', creature: e.creature });
  return ok(s, events);
}

/** Drop an unfinished encounter without a result (e.g. the app was closed mid-way). */
export function abandonEncounter(state) {
  if (!T(state).encounter) return ok(state);
  const s = clone(state);
  ensureTrails(s).encounter = null;
  return ok(s);
}

export function companionView(state, id) {
  const c = T(state).companions[id];
  if (!c) return null;
  return { ...CREATURES[id], ...c };
}

// re-exported for callers that build fresh state in one go
export { ensureStory, dayKey };
