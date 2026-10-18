// Home: the Garden, the Cottage Kitchen and Apothecary, and the three Cozy Skills.
//
// Everything here belongs to the player account (like the story), not to one Evochi: beds, skill XP
// and recipes survive memorials and new pets. Rules:
//  - crops grow on real time; walking adds a bonus (steps taken after planting, from the same
//    de-duplicated samples as the story), and an optional watering adds a little more
//  - harvests, brews and meals go into the ordinary inventory and reuse the item catalog
//  - crafting never wastes ingredients: the minigame only ever adds a quality bonus
//  - the Kitchen opens with "A Place to Call Home", the Apothecary with "Mira's Mortar" (story flags)

import { ITEMS } from './catalog.js';
import { dayKey } from './time.js';
// state.js and story.js import each other; these are only used inside functions (never at load time)
import { grantItem, ownedQty } from './state.js';
import { freshDays, ensureStory } from './story.js';

export const HOME_SCHEMA = 1;

// ------------------------------------------------------------------ skills ----
export const SKILLS = {
  farming: { id: 'farming', name: 'Farming', icon: 'skill_farming', color: '#5FA046', verb: 'harvest' },
  cooking: { id: 'cooking', name: 'Cooking', icon: 'skill_cooking', color: '#E8792E', verb: 'cook' },
  alchemy: { id: 'alchemy', name: 'Alchemy', icon: 'skill_alchemy', color: '#9975C9', verb: 'brew' },
};
export const SKILL_ORDER = ['farming', 'cooking', 'alchemy'];
// XP from level L to L+1 = base + step * (L - 1)
export const SKILL_CURVE = { base: 40, step: 20, max: 20 };

export function skillLevel(xp) {
  let level = 1;
  let left = Math.max(0, Math.floor(xp || 0));
  for (;;) {
    if (level >= SKILL_CURVE.max) return { level, into: 0, need: 0, maxed: true };
    const need = SKILL_CURVE.base + SKILL_CURVE.step * (level - 1);
    if (left < need) return { level, into: left, need, maxed: false };
    left -= need;
    level++;
  }
}

// ------------------------------------------------------------------- crops ----
export const CROPS = {
  sunberry: { id: 'sunberry', name: 'Sunberry', seed: 'seed_sunberry', yield: { sunberry: 3 }, growMin: 20, xp: 12, level: 1 },
  meadow_carrot: { id: 'meadow_carrot', name: 'Meadow Carrot', seed: 'seed_meadow_carrot', yield: { meadow_carrot: 2 }, growMin: 45, xp: 14, level: 1 },
  golden_wheat: { id: 'golden_wheat', name: 'Golden Wheat', seed: 'seed_golden_wheat', yield: { golden_wheat: 3 }, growMin: 90, xp: 18, level: 2 },
  glowleaf: { id: 'glowleaf', name: 'Glowleaf', seed: 'seed_glowleaf', yield: { glowleaf: 2 }, growMin: 180, xp: 24, level: 3 },
  moonshroom: { id: 'moonshroom', name: 'Moonshroom', seed: 'seed_moonshroom', yield: { moonshroom: 2 }, growMin: 360, xp: 36, level: 5 },
};
export const CROP_ORDER = ['sunberry', 'meadow_carrot', 'golden_wheat', 'glowleaf', 'moonshroom'];

export const PLOTS = [
  { id: 'p1', level: 1 }, { id: 'p2', level: 1 }, { id: 'p3', level: 1 }, { id: 'p4', level: 4 },
];

export const GROW = {
  stepsForFull: 10000, // steps after planting that add one whole growing time...
  maxWalkShare: 0.6, // ...capped at 60% of it
  water: 0.15, // optional watering, once per planting
  sproutTonic: 0.5, // the Apothecary's Sprout Tonic, once per planting
};

export const STARTER_SEEDS = { seed_sunberry: 3, seed_meadow_carrot: 2 };

// ----------------------------------------------------------------- recipes ----
export const STATIONS = {
  kitchen: { id: 'kitchen', name: 'Kitchen', skill: 'cooking', flag: 'cottage_restored', verb: 'Cook', quest: 'hq01' },
  apothecary: { id: 'apothecary', name: 'Apothecary', skill: 'alchemy', flag: 'apothecary_unlocked', verb: 'Brew', quest: 'hq02' },
};

export const RECIPES = {
  sunberry_tart: { id: 'sunberry_tart', station: 'kitchen', makes: 'sunberry_tart', needs: { sunberry: 3, golden_wheat: 1 }, level: 1, xp: 20 },
  carrot_stew: { id: 'carrot_stew', station: 'kitchen', makes: 'carrot_stew', needs: { meadow_carrot: 2, sunberry: 1 }, level: 1, xp: 15 },
  golden_bun: { id: 'golden_bun', station: 'kitchen', makes: 'golden_bun', needs: { golden_wheat: 2 }, level: 2, xp: 15 },
  moonshroom_pie: { id: 'moonshroom_pie', station: 'kitchen', makes: 'moonshroom_pie', needs: { moonshroom: 2, golden_wheat: 2 }, level: 4, xp: 40 },
  glowleaf_tonic: { id: 'glowleaf_tonic', station: 'apothecary', makes: 'glowleaf_tonic', needs: { glowleaf: 2, sunberry: 1 }, level: 1, xp: 20 },
  meadow_tea: { id: 'meadow_tea', station: 'apothecary', makes: 'meadow_tea', needs: { glowleaf: 1, meadow_carrot: 1 }, level: 1, xp: 15 },
  sprout_tonic: { id: 'sprout_tonic', station: 'apothecary', makes: 'sprout_tonic', needs: { glowleaf: 1, golden_wheat: 1 }, level: 2, xp: 20 },
  moonlight_draught: { id: 'moonlight_draught', station: 'apothecary', makes: 'moonlight_draught', needs: { moonshroom: 2, glowleaf: 1 }, level: 4, xp: 40 },
  lantern_tonic: { id: 'lantern_tonic', station: 'apothecary', makes: 'lantern_tonic', needs: { lumen_shard: 1, glowleaf: 1, sunberry: 2 }, level: 3, xp: 30, flag: 'sprout_restored' },
};
export const RECIPE_ORDER = Object.keys(RECIPES);

// the minigame result: 'perfect' doubles the batch and gives +50% skill XP; anything else is a normal batch
export const QUALITY = { perfect: { batch: 2, xp: 1.5, label: 'Perfect!' }, good: { batch: 1, xp: 1, label: 'Good' } };

// ------------------------------------------------------------- milestones ----
// What each skill level opens: crops, beds, recipes and quests (the Skills chart reads this).
export function milestones(skill) {
  const out = [];
  const add = (level, kind, id, label, extra = {}) => out.push({ skill, level, kind, id, label, ...extra });
  if (skill === 'farming') {
    for (const c of CROP_ORDER) add(CROPS[c].level, 'crop', c, CROPS[c].name);
    for (const p of PLOTS) if (p.level > 1) add(p.level, 'plot', p.id, 'A fourth garden bed');
    add(3, 'quest', 'hq02', "Mira's Mortar needs Glowleaf", { story: true });
  } else {
    const station = skill === 'cooking' ? 'kitchen' : 'apothecary';
    for (const r of RECIPE_ORDER) {
      const R = RECIPES[r];
      if (R.station === station) add(R.level, 'recipe', r, ITEMS[R.makes].name, { quest: R.flag === 'sprout_restored' ? 'eq02' : STATIONS[station].quest });
    }
    if (skill === 'cooking') add(2, 'quest', 'hq02', "Mira's Mortar (opens the Apothecary)", { story: true });
  }
  out.sort((a, b) => a.level - b.level || a.kind.localeCompare(b.kind));
  return out;
}

// ------------------------------------------------------------------ helpers ----
function ok(state, events = []) {
  return { state, events, error: null };
}
function fail(state, error, extra = {}) {
  return { state, events: [], error, ...extra };
}
function clone(s) {
  return typeof structuredClone === 'function' ? structuredClone(s) : JSON.parse(JSON.stringify(s));
}

export function newHome() {
  return {
    schemaVersion: HOME_SCHEMA,
    plots: { p1: null, p2: null, p3: null, p4: null },
    skills: { farming: 0, cooking: 0, alchemy: 0 },
    starterSeeds: false,
    counts: { harvests: 0, cooked: 0, brewed: 0, perfect: 0 },
    seen: {},
  };
}

/** Add (or upgrade) the home object in place. Safe to call on every load. */
export function ensureHome(s) {
  if (!s.home || typeof s.home !== 'object') s.home = newHome();
  const base = newHome();
  for (const k of Object.keys(base)) if (s.home[k] === undefined) s.home[k] = base[k];
  s.home.plots = { ...base.plots, ...s.home.plots };
  s.home.skills = { ...base.skills, ...s.home.skills };
  s.home.counts = { ...base.counts, ...s.home.counts };
  return s.home;
}

function home(state) {
  return state.home || newHome();
}

export function skillXp(state, id) {
  return home(state).skills[id] || 0;
}

export function skillView(state, id) {
  return { ...SKILLS[id], xp: skillXp(state, id), ...skillLevel(skillXp(state, id)) };
}

function storyFlag(state, f) {
  return !!state.story?.flags?.[f];
}

export function stationOpen(state, station) {
  return storyFlag(state, STATIONS[station].flag);
}

export function plotUnlocked(state, plotId) {
  const p = PLOTS.find((x) => x.id === plotId);
  return !!p && skillLevel(skillXp(state, 'farming')).level >= p.level;
}

export function cropUnlocked(state, cropId) {
  return skillLevel(skillXp(state, 'farming')).level >= CROPS[cropId].level;
}

/** Steps walked since `since` (same counting as story walks: fresh, de-duplicated samples). */
export function stepsSince(state, since) {
  if (!state.player) return 0;
  const tz = state.player.timezone || state.tzHint || 'UTC';
  const days = freshDays(state, since, tz);
  return Object.values(days).reduce((a, d) => a + d.steps, 0);
}

/** How far a planted bed has grown: time + walking + watering + tonic, 0..1. */
export function plotGrowth(state, plot, now) {
  const c = CROPS[plot.crop];
  const growMs = c.growMin * 60000;
  const time = Math.max(0, now - plot.plantedAt) / growMs;
  const steps = stepsSince(state, plot.plantedAt);
  const walk = Math.min(GROW.maxWalkShare, steps / GROW.stepsForFull);
  const p = time + walk + (plot.watered ? GROW.water : 0) + (plot.tonic ? GROW.sproutTonic : 0);
  return { progress: Math.min(1, p), time, walk, steps, growMs };
}

export function plotView(state, plotId, now) {
  const unlocked = plotUnlocked(state, plotId);
  const plot = home(state).plots[plotId] || null;
  const need = PLOTS.find((x) => x.id === plotId).level;
  if (!plot) return { id: plotId, unlocked, need, empty: true };
  const g = plotGrowth(state, plot, now);
  const ripe = g.progress >= 1;
  const stage = ripe ? 'ripe' : g.progress < 0.34 ? 'sprout' : 'growing';
  // time left if nobody walks; and the steps that would finish it now (capped by the walking share)
  const left = ripe ? 0 : Math.max(0, (1 - g.progress) * g.growMs);
  const walkRoom = Math.max(0, GROW.maxWalkShare - g.walk);
  const stepsToRipe = ripe || (1 - g.progress) > walkRoom ? null : Math.ceil((1 - g.progress) * GROW.stepsForFull);
  return {
    id: plotId, unlocked, need, empty: false, crop: plot.crop, plantedAt: plot.plantedAt, watered: !!plot.watered,
    tonic: !!plot.tonic, progress: g.progress, ripe, stage, msLeft: left, stepsToRipe, walkedSteps: g.steps,
  };
}

export function homeStatus(state, now) {
  const H = home(state);
  const plots = PLOTS.map((p) => plotView(state, p.id, now));
  const skills = Object.fromEntries(SKILL_ORDER.map((k) => [k, skillView(state, k)]));
  return {
    plots, skills,
    ripe: plots.filter((p) => p.ripe).length,
    growing: plots.filter((p) => !p.empty && !p.ripe).length,
    emptyOpen: plots.filter((p) => p.empty && p.unlocked).length,
    kitchen: stationOpen(state, 'kitchen'),
    apothecary: stationOpen(state, 'apothecary'),
    starterSeeds: H.starterSeeds,
    counts: { ...H.counts },
  };
}

export function hasIngredients(state, needs, times = 1) {
  return Object.entries(needs).every(([id, n]) => ownedQty(state, id) >= n * times);
}

export function recipeView(state, rid) {
  const R = RECIPES[rid];
  const st = STATIONS[R.station];
  const lv = skillLevel(skillXp(state, st.skill)).level;
  const open = stationOpen(state, R.station);
  const known = lv >= R.level && (!R.flag || storyFlag(state, R.flag));
  const have = Object.fromEntries(Object.entries(R.needs).map(([id, n]) => [id, { need: n, have: ownedQty(state, id) }]));
  const ready = open && known && hasIngredients(state, R.needs);
  return { ...R, name: ITEMS[R.makes].name, open, known, have, ready, skill: st.skill, needsStory: !!R.flag && !storyFlag(state, R.flag) };
}

function addSkillXp(s, skill, amount, events) {
  const H = ensureHome(s);
  const before = skillLevel(H.skills[skill]);
  H.skills[skill] = (H.skills[skill] || 0) + Math.round(amount);
  const after = skillLevel(H.skills[skill]);
  events.push({ type: 'skill_xp', skill, amount: Math.round(amount) });
  if (after.level > before.level) {
    const unlocks = milestones(skill).filter((m) => m.level > before.level && m.level <= after.level);
    events.push({ type: 'skill_up', skill, level: after.level, unlocks });
  }
}

function take(s, id, n) {
  s.inventory[id].quantity -= n;
}

// ------------------------------------------------------------------ actions ----
/** First visit to the Home Map: a few starter seeds, once per account. */
export function claimStarterSeeds(state, now) {
  if (home(state).starterSeeds) return ok(state);
  const s = clone(state);
  const H = ensureHome(s);
  for (const [id, n] of Object.entries(STARTER_SEEDS)) grantItem(s, id, n, 'home:starter', now, 'home:starter');
  H.starterSeeds = true;
  return ok(s, [{ type: 'home_gift', items: { ...STARTER_SEEDS } }]);
}

export function plant(state, plotId, cropId, now) {
  const c = CROPS[cropId];
  if (!c) return fail(state, 'unknown_crop');
  if (!PLOTS.some((p) => p.id === plotId)) return fail(state, 'unknown_plot');
  if (!plotUnlocked(state, plotId)) return fail(state, 'plot_locked', { need: PLOTS.find((p) => p.id === plotId).level });
  if (home(state).plots[plotId]) return fail(state, 'plot_busy');
  if (!cropUnlocked(state, cropId)) return fail(state, 'crop_locked', { need: c.level });
  if (ownedQty(state, c.seed) < 1) return fail(state, 'no_seed', { seed: c.seed });
  const s = clone(state);
  const H = ensureHome(s);
  take(s, c.seed, 1);
  H.plots[plotId] = { crop: cropId, plantedAt: now, watered: false, tonic: false };
  return ok(s, [{ type: 'planted', plot: plotId, crop: cropId }]);
}

export function water(state, plotId, now) {
  const p = home(state).plots[plotId];
  if (!p) return fail(state, 'plot_empty');
  if (p.watered) return ok(state, [{ type: 'already_watered', plot: plotId }]);
  const s = clone(state);
  ensureHome(s).plots[plotId].watered = true;
  return ok(s, [{ type: 'watered', plot: plotId }]);
}

export function useSproutTonic(state, plotId, now) {
  const p = home(state).plots[plotId];
  if (!p) return fail(state, 'plot_empty');
  if (p.tonic) return fail(state, 'tonic_used');
  if (ownedQty(state, 'sprout_tonic') < 1) return fail(state, 'not_owned');
  if (plotGrowth(state, p, now).progress >= 1) return fail(state, 'already_ripe');
  const s = clone(state);
  take(s, 'sprout_tonic', 1);
  ensureHome(s).plots[plotId].tonic = true;
  return ok(s, [{ type: 'tonic_used', plot: plotId }]);
}

export function harvest(state, plotId, now) {
  const p = home(state).plots[plotId];
  if (!p) return fail(state, 'plot_empty');
  if (plotGrowth(state, p, now).progress < 1) return fail(state, 'not_ripe');
  const c = CROPS[p.crop];
  const s = clone(state);
  const H = ensureHome(s);
  const txn = `harvest:${plotId}:${p.plantedAt}`;
  for (const [id, n] of Object.entries(c.yield)) grantItem(s, id, n, 'harvest', now, txn);
  H.plots[plotId] = null;
  H.counts.harvests++;
  const events = [{ type: 'harvested', plot: plotId, crop: p.crop, items: { ...c.yield } }];
  addSkillXp(s, 'farming', c.xp, events);
  return ok(s, events);
}

/** Cook or brew one recipe. `quality` comes from the (skippable) minigame and only ever adds. */
export function craft(state, recipeId, quality, now) {
  const R = RECIPES[recipeId];
  if (!R) return fail(state, 'unknown_recipe');
  const v = recipeView(state, recipeId);
  if (!v.open) return fail(state, 'station_locked', { station: R.station });
  if (!v.known) return fail(state, 'recipe_locked', { need: R.level, skill: v.skill, flag: R.flag && !storyFlag(state, R.flag) ? R.flag : null });
  if (!hasIngredients(state, R.needs)) return fail(state, 'missing_ingredients');
  const q = QUALITY[quality] || QUALITY.good;
  const s = clone(state);
  const H = ensureHome(s);
  for (const [id, n] of Object.entries(R.needs)) take(s, id, n);
  grantItem(s, R.makes, q.batch, R.station, now, `${R.station}:${recipeId}:${now}`);
  H.counts[R.station === 'kitchen' ? 'cooked' : 'brewed']++;
  if (quality === 'perfect') H.counts.perfect++;
  const events = [{ type: 'crafted', recipe: recipeId, station: R.station, item: R.makes, qty: q.batch, quality: QUALITY[quality] ? quality : 'good' }];
  addSkillXp(s, v.skill, R.xp * q.xp, events);
  return ok(s, events);
}

/** Display name with a simple plural ("3 Sunberries", "2 Golden Wheat"). */
export function itemLabel(id, n = 1) {
  const nm = ITEMS[id]?.name || id;
  if (n === 1 || /(Wheat|Glowleaf|Tea|s)$/.test(nm)) return nm;
  if (/[^aeiou]y$/.test(nm)) return nm.slice(0, -1) + 'ies';
  return nm + 's';
}

/** Where an item comes from at home: the Garden for crops, the Kitchen or Apothecary for recipes. */
export function homeSource(id) {
  const it = ITEMS[id];
  if (!it) return null;
  if (it.category === 'ingredient' || it.category === 'seed') return { route: 'garden', verb: 'Grow', place: 'Garden' };
  const R = RECIPES[id];
  if (R) return { route: 'station', station: R.station, verb: STATIONS[R.station].verb, place: STATIONS[R.station].name };
  return null;
}

export function markHomeSeen(state, key) {
  if (home(state).seen?.[key]) return ok(state);
  const s = clone(state);
  ensureHome(s).seen[key] = true;
  return ok(s);
}

// ensureStory is re-exported for callers that build a fresh home + story in one go
export { ensureStory, dayKey };
