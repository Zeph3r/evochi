// Evochi game state, derived view and actions.
// Every action is a pure function (state, args..., now) -> { state, events, error }.
// Invariants (style guide §22): XP, balances and claims never go negative; one pet per
// creation request; one item per equipment slot; evolution only moves forward.

import { CONFIG, PALETTES, STAGES } from './config.js';
import { ITEMS, item, isStackable, itemCompatible, DECOR_SLOTS, isShopItem } from './catalog.js';
import { dayKey, dayStart, addDays, weekKey, weekDays, deviceZone, HOUR } from './time.js';
import { mergeSamples, aggregateDays } from './steps.js';
import {
  activityXp, levelInfo, isActiveDay, evolutionStatus, replayVitality, bondValue, bondHearts,
} from './progression.js';
import { newStory, ensureStory, applyStoryProgress, storyStatus } from './story.js';
import { newHome, ensureHome, homeStatus } from './home.js';
import { newTrails, ensureTrails, trailsStatus, applyTrailProgress } from './trails.js';

export const SCHEMA_VERSION = 1;

// ------------------------------------------------------------- helpers ----
function clone(s) {
  return typeof structuredClone === 'function' ? structuredClone(s) : JSON.parse(JSON.stringify(s));
}

let idCounter = 0;
export function uid(prefix = 'id') {
  idCounter = (idCounter + 1) % 1e6;
  const r = Math.random().toString(36).slice(2, 8);
  return `${prefix}_${Date.now().toString(36)}${r}${idCounter.toString(36)}`;
}

function ok(state, events = []) {
  return { state, events, error: null };
}
function fail(state, error, extra = {}) {
  return { state, events: [], error, ...extra };
}

// deterministic PRNG for chest/cosmetic rolls (idempotent: same inputs, same result)
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

// --------------------------------------------------------- initial state ----
export function newState(now = Date.now(), tz = deviceZone()) {
  return {
    schema: SCHEMA_VERSION,
    configVersion: CONFIG.version,
    player: null,
    onboarding: { step: 'welcome', draft: { name: '', paletteId: 'amber', habitatId: 'sunlit_meadow' }, requestId: null },
    pet: null,
    pastPets: [],
    steps: { samples: [], connection: 'none', syncedUntil: 0, lastSync: null, lastSource: null },
    wallet: { txns: [] },
    inventory: {},
    claims: {},
    nest: { habitatId: 'sunlit_meadow', placements: {} },
    unlocks: {},
    audit: [],
    flags: { coachDone: false, guestNoticeSeen: false },
    analytics: [],
    debug: { clockOffset: 0 },
    story: newStory(),
    home: newHome(),
    trails: newTrails(),
    tzHint: tz,
    createdAt: now,
  };
}

// ---------------------------------------------------------- derivation ----
export function goalFor(state, key) {
  const hist = state.player?.goalHistory || [];
  let g = state.player?.goal ?? CONFIG.goal.default;
  let best = null;
  for (const h of hist) if (h.from <= key && (!best || h.from >= best.from)) best = h;
  if (best) g = best.goal;
  return g;
}

export function balance(state) {
  return state.wallet.txns.reduce((a, t) => a + t.amount, 0);
}

export function ownedQty(state, id) {
  return state.inventory[id]?.quantity || 0;
}

export function derive(state, now) {
  const tz = state.player?.timezone || state.tzHint || 'UTC';
  const today = dayKey(now, tz);
  const days = aggregateDays(state.steps.samples, tz);
  const todayDay = days[today] || { steps: 0, verified: 0, manual: 0, unverified: false };
  const goal = goalFor(state, today);
  const out = {
    tz, today, days, goal,
    todaySteps: todayDay.steps,
    todayUnverified: todayDay.unverified,
    todayXp: activityXp(todayDay.steps, goal),
    balance: balance(state),
    pet: null,
  };
  const pet = state.pet;
  if (pet) {
    const totalXp = Object.values(pet.xpAwarded || {}).reduce((a, b) => a + b, 0);
    const lv = levelInfo(totalXp);
    const gf = (k) => goalFor(state, k);
    let activeDays = 0;
    let lifetimeSteps = 0;
    for (const [k, d] of Object.entries(days)) {
      if (k < pet.createdDay) continue;
      if (isActiveDay(d.steps, gf(k))) activeDays++;
      lifetimeSteps += d.verified;
    }
    const vit = replayVitality({
      createdDay: pet.createdDay, todayKey: today, days, goalFor: gf, events: pet.events || [],
      syncedUntil: state.steps.syncedUntil, now, tz,
    });
    const bond = bondValue(pet.bondEvents || []);
    const evo = evolutionStatus(pet.stage, lv.level, activeDays);
    const lastRecovery = (pet.events || []).filter((e) => e.type === 'care' && e.recovery).reduce((a, e) => Math.max(a, e.t), 0);
    out.pet = {
      totalXp, ...lv, activeDays, lifetimeSteps, vitality: vit.vitality, status: vit.state, dead: vit.dead,
      diedAt: vit.diedAt, vitalityLog: vit.log, restDays: vit.restDays, bond, hearts: bondHearts(bond), evo,
      xpToday: pet.xpAwarded?.[today] || 0,
      recoveryReadyAt: lastRecovery ? lastRecovery + CONFIG.care.recoveryCooldownHours * HOUR : 0,
      petToday: (pet.bondEvents || []).some((e) => e.key === today && e.type === 'pet'),
      playToday: (pet.bondEvents || []).some((e) => e.key === today && e.type === 'play'),
      daysTogether: Math.max(1, Math.round((now - pet.createdAt) / 86400000) + 1),
    };
  }
  out.quests = questStatus(state, out, now);
  out.claimable = out.quests.filter((q) => q.eligible && !q.claimed).length;
  out.story = state.player ? storyStatus(state, now) : null;
  out.home = state.player ? homeStatus(state, now) : null;
  out.trails = state.player ? trailsStatus(state, now) : null;
  return out;
}

// --------------------------------------------------------------- quests ----
export function questStatus(state, d, now) {
  const res = [];
  const pet = state.pet;
  const week = weekKey(d.today);
  for (const q of CONFIG.quests) {
    const period = q.period === 'week' ? week : d.today;
    const claimId = `${q.id}@${period}`;
    let progress = 0;
    let target = 1;
    let label = '';
    if (q.ratio) {
      target = Math.ceil(q.ratio * d.goal);
      progress = Math.min(d.todaySteps, target);
      label = `${d.todaySteps.toLocaleString('en-US')} / ${target.toLocaleString('en-US')} steps`;
    } else if (q.interaction) {
      target = 1;
      progress = pet && d.pet && (d.pet.petToday || d.pet.playToday) ? 1 : 0;
      label = progress ? 'Done' : 'Not yet';
    } else if (q.goalDays) {
      target = q.goalDays;
      progress = weekDays(d.today).filter((k) => {
        const day = d.days[k];
        return day && day.steps >= goalFor(state, k) && (!pet || k >= pet.createdDay);
      }).length;
      progress = Math.min(progress, target);
      label = `${progress} / ${target} days`;
    }
    const eligible = !!pet && progress >= target && !(d.pet && d.pet.dead && q.interaction);
    res.push({ ...q, periodKey: period, claimId, progress, target, label, eligible, claimed: !!state.claims[claimId] });
  }
  return res;
}

// --------------------------------------------------------- player setup ----
export function startGuest(state, now, tz) {
  if (state.player) return ok(state);
  const s = clone(state);
  s.player = {
    id: uid('player'), accountType: 'guest', email: null, timezone: tz || s.tzHint || 'UTC', createdAt: now,
    goal: CONFIG.goal.default, goalHistory: [],
    settings: { sound: true, music: true, haptics: true, reducedMotion: false, notifications: false, quietStart: 21, quietEnd: 8, analytics: false, largeText: false, devTools: true },
  };
  s.onboarding.step = 'create';
  return ok(s, [{ type: 'player_created' }]);
}

export function startAccount(state, email, now, tz) {
  const r = startGuest(state, now, tz);
  const s = r.state;
  s.player.accountType = 'email';
  s.player.email = email;
  return ok(s, r.events);
}

export function setOnboardingStep(state, step) {
  const s = clone(state);
  s.onboarding.step = step;
  return ok(s);
}

export function updateDraft(state, patch) {
  const s = clone(state);
  s.onboarding.draft = { ...s.onboarding.draft, ...patch };
  return ok(s);
}

export function validateName(name) {
  const n = (name || '').trim().replace(/\s+/g, ' ');
  if (n.length < CONFIG.name.min) return { ok: false, error: 'Give your Evochi a name.' };
  if (n.length > CONFIG.name.max) return { ok: false, error: `Names can be up to ${CONFIG.name.max} characters.` };
  if (!/^[\p{L}\p{N}][\p{L}\p{N} '\-]*$/u.test(n)) return { ok: false, error: 'Use letters, numbers, spaces, - or \'.' };
  return { ok: true, name: n };
}

/** Create the Evochi exactly once per request id (retries do not duplicate). */
export function createPet(state, { name, paletteId, habitatId = 'sunlit_meadow', requestId }, now) {
  if (!state.player) return fail(state, 'no_player');
  if (state.pet && !state.pet.memorialized) {
    if (state.pet.requestId === requestId) return ok(state); // idempotent retry
    return fail(state, 'pet_exists');
  }
  const v = validateName(name);
  if (!v.ok) return fail(state, 'invalid_name', { message: v.error });
  if (!PALETTES.some((p) => p.id === paletteId)) return fail(state, 'invalid_palette');
  const s = clone(state);
  const tz = s.player.timezone;
  const today = dayKey(now, tz);
  s.pet = {
    id: uid('pet'), requestId, speciesId: 'lizard', name: v.name, paletteId, stage: 1,
    habitatId, createdAt: now, createdDay: today, xpAwarded: {}, events: [], bondEvents: [],
    evolutions: [{ stage: 1, at: now }], equipped: {}, status: 'healthy',
  };
  s.nest.habitatId = habitatId;
  // starter kit on the very first pet only
  if (!s.flags.starterGranted) {
    for (const it of CONFIG.starter.items) grant(s, it.itemId, it.quantity, 'starter', now);
    for (const p of CONFIG.starter.placements) s.nest.placements[p.slotId] = p.itemId;
    s.flags.starterGranted = true;
  }
  unlock(s, `stage:lizard:1`, now);
  unlock(s, `palette:${paletteId}`, now);
  s.onboarding.step = s.steps.connection === 'none' ? 'connect' : 'goal';
  if (s.pastPets.length) s.onboarding.step = 'awakening';
  return ok(s, [{ type: 'pet_created', petId: s.pet.id }]);
}

function unlock(s, id, now) {
  if (!s.unlocks[id]) s.unlocks[id] = now;
}

export function setConnection(state, connection, now) {
  const s = clone(state);
  s.steps.connection = connection; // 'demo' | 'manual' | 'none'
  if (connection === 'demo' && !s.steps.syncedUntil) s.steps.syncedUntil = now;
  return ok(s);
}

export function setGoal(state, goal, now) {
  const g = Math.round(Number(goal));
  if (!Number.isFinite(g) || g < CONFIG.goal.min || g > CONFIG.goal.max) return fail(state, 'invalid_goal');
  const s = clone(state);
  const today = dayKey(now, s.player.timezone);
  s.player.goal = g;
  s.player.goalHistory = (s.player.goalHistory || []).filter((h) => h.from !== today);
  s.player.goalHistory.push({ from: today, goal: g });
  return ok(s);
}

export function finishOnboarding(state) {
  const s = clone(state);
  s.onboarding.step = 'done';
  return ok(s);
}

export function setTimezone(state, tz) {
  const s = clone(state);
  s.player.timezone = tz;
  return ok(s);
}

export function updateSettings(state, patch) {
  const s = clone(state);
  s.player.settings = { ...s.player.settings, ...patch };
  return ok(s);
}

export function renamePet(state, name) {
  const v = validateName(name);
  if (!v.ok) return fail(state, 'invalid_name', { message: v.error });
  const s = clone(state);
  s.pet.name = v.name;
  return ok(s);
}

// ----------------------------------------------------------- step sync ----
/**
 * Keep saves small: samples older than `keepDays` are folded into one record per
 * day and kind (verified/manual). Day totals - and therefore XP, quests and the
 * vitality replay - are unchanged, so compaction is invisible to the rules.
 */
export function compactSamples(samples, tz, today, keepDays = 14) {
  const cutoff = addDays(today, -keepDays);
  const old = samples.filter((s) => dayKey(s.start, tz) < cutoff && s.source !== 'compacted' && s.source !== 'compacted-manual');
  if (!old.length) return samples;
  const keep = samples.filter((s) => !old.includes(s));
  const days = aggregateDays(old, tz);
  for (const [k, d] of Object.entries(days)) {
    const mid = dayStart(k, tz) + 12 * HOUR;
    // merge with an existing compacted record for that day, if any
    const ex = keep.find((s) => s.source === 'compacted' && dayKey(s.start, tz) === k);
    if (d.verified) {
      if (ex) ex.count += d.verified;
      else keep.push({ id: `cmp_${k}`, source: 'compacted', start: mid, end: mid, count: d.verified, manual: false });
    }
    const exm = keep.find((s) => s.source === 'compacted-manual' && dayKey(s.start, tz) === k);
    if (d.manual) {
      if (exm) exm.count += d.manual;
      else keep.push({ id: `cmpm_${k}`, source: 'compacted-manual', start: mid, end: mid, count: d.manual, manual: true });
    }
  }
  return keep;
}

/**
 * Merge verified observations and award newly-earned XP exactly once.
 * Re-delivered samples change nothing; corrections downward are audited, never clawed back.
 */
export function syncSteps(state, samples, now, { source = 'demo', success = true } = {}) {
  if (!success) {
    const s = clone(state);
    s.steps.lastError = now;
    return ok(s, [{ type: 'sync_failed' }]);
  }
  const s = clone(state);
  const tz0 = s.player?.timezone || s.tzHint || 'UTC';
  // days older than the retention window are sealed: their compacted totals are final,
  // so re-delivered or very late samples for them are ignored (no double counting)
  const sealed = addDays(dayKey(now, tz0), -14);
  const fresh = samples.filter((x) => dayKey(Number(x.start), tz0) >= sealed);
  const { list: merged, added } = mergeSamples(s.steps.samples, fresh);
  const list = compactSamples(merged, tz0, dayKey(now, tz0));
  s.steps.samples = list;
  if (s.audit.length > 200) s.audit = s.audit.slice(-200);
  s.steps.syncedUntil = Math.max(s.steps.syncedUntil || 0, now);
  s.steps.lastSync = now;
  s.steps.lastSource = source;
  const events = [];
  const storyEvents = [...applyStoryProgress(s, now), ...applyTrailProgress(s, now)];
  if (!s.pet) return ok(s, [...storyEvents, { type: 'synced', added }]);
  const before = derive(state, now);
  const tz = s.player.timezone;
  const days = aggregateDays(list, tz);
  const today = dayKey(now, tz);
  let gained = 0;
  for (const [k, d] of Object.entries(days)) {
    if (k < s.pet.createdDay || k > today) continue;
    const goal = goalFor(s, k);
    const elig = activityXp(d.steps, goal).total;
    const awarded = s.pet.xpAwarded[k] || 0;
    if (elig > awarded) {
      s.pet.xpAwarded[k] = elig;
      gained += elig - awarded;
    } else if (elig < awarded) {
      s.audit.push({ t: now, type: 'step_correction', day: k, eligible: elig, awarded });
    }
    if (d.steps >= goal && !(s.pet.bondEvents || []).some((e) => e.key === k && e.type === 'goal')) {
      s.pet.bondEvents.push({ key: k, type: 'goal', t: now });
      if (k === today) events.push({ type: 'goal_met' });
    }
  }
  const after = derive(s, now);
  if (gained > 0) events.push({ type: 'xp', amount: gained });
  if (after.pet.level > before.pet.level) events.push({ type: 'level_up', level: after.pet.level });
  if (after.pet.evo.eligible && !before.pet.evo.eligible) events.push({ type: 'evolution_ready', stage: after.pet.evo.next });
  const newly = after.quests.filter((q) => q.eligible && !q.claimed && !before.quests.find((b) => b.id === q.id && b.eligible));
  for (const q of newly) events.push({ type: 'quest_ready', questId: q.id, title: q.title });
  if (before.pet.dead && !after.pet.dead) events.push({ type: 'recovered' });
  events.push(...storyEvents);
  events.push({ type: 'synced', added });
  return ok(s, events);
}

// --------------------------------------------------------- interactions ----
export function interact(state, kind, now) {
  if (!state.pet) return fail(state, 'no_pet');
  const d = derive(state, now);
  if (d.pet.dead) return fail(state, 'pet_dead');
  const s = clone(state);
  const today = d.today;
  const exists = s.pet.bondEvents.some((e) => e.key === today && e.type === kind);
  const events = [{ type: 'interact', kind }];
  if (!exists) {
    s.pet.bondEvents.push({ key: today, type: kind, t: now });
    const after = derive(s, now);
    const gain = after.pet.bond - d.pet.bond;
    if (gain > 0) events.push({ type: 'bond', amount: gain });
  }
  return ok(s, events);
}

// --------------------------------------------------------------- wallet ----
export function addTxn(s, txn) {
  if (s.wallet.txns.some((t) => t.id === txn.id)) return false;
  s.wallet.txns.push(txn);
  return true;
}

export function grantItem(s, itemId, qty, source, now, txnId = null) {
  return grant(s, itemId, qty, source, now, txnId);
}

function grant(s, itemId, qty, source, now, txnId = null) {
  const cur = s.inventory[itemId] || { quantity: 0, acquisitions: [] };
  cur.quantity += qty;
  cur.acquisitions.push({ at: now, source, txnId, qty });
  s.inventory[itemId] = cur;
}

export function claimQuest(state, questId, now) {
  const d = derive(state, now);
  const q = d.quests.find((x) => x.id === questId);
  if (!q) return fail(state, 'unknown_quest');
  if (q.claimed) return ok(state, [{ type: 'already_claimed', questId }]); // idempotent
  if (!q.eligible) return fail(state, 'not_eligible');
  const s = clone(state);
  const txnId = `quest:${q.claimId}`;
  addTxn(s, { id: txnId, amount: q.coins, currency: 'evocoin', cause: `quest:${q.id}`, at: now });
  const rewards = [{ kind: 'coins', amount: q.coins }];
  const verifiedDay = !d.todayUnverified || CONFIG.manualSteps.allowChests;
  if (q.chest && verifiedDay) {
    const r = rng(`${s.player.id}:${q.claimId}:chest`);
    const coins = CONFIG.chest.coins[Math.floor(r() * CONFIG.chest.coins.length)];
    addTxn(s, { id: `${txnId}:chest`, amount: coins, currency: 'evocoin', cause: 'chest', at: now });
    rewards.push({ kind: 'coins', amount: coins, chest: true });
    if (r() < CONFIG.chest.itemChance) {
      const it = CONFIG.chest.items[Math.floor(r() * CONFIG.chest.items.length)];
      grant(s, it, 1, 'chest', now, `${txnId}:chest`);
      rewards.push({ kind: 'item', itemId: it });
    }
  }
  if (q.cosmeticChance && verifiedDay) {
    const r = rng(`${s.player.id}:${q.claimId}:cosmetic`);
    if (r() < q.cosmeticChance) {
      const pool = Object.keys(ITEMS).filter((id) => ITEMS[id].category === 'wearable' && isShopItem(id) && !ownedQty(s, id));
      if (pool.length) {
        const pick = pool[Math.floor(r() * pool.length)];
        grant(s, pick, 1, 'quest', now, txnId);
        rewards.push({ kind: 'item', itemId: pick });
      }
    }
  }
  s.claims[q.claimId] = { claimedAt: now, txnId };
  return ok(s, [{ type: 'claimed', questId, rewards }]);
}

// ----------------------------------------------------------------- shop ----
export function purchase(state, itemId, requestId, now) {
  const it = ITEMS[itemId];
  if (!it) return fail(state, 'unknown_item');
  if (!isShopItem(itemId)) return fail(state, 'not_for_sale');
  const txnId = `purchase:${requestId}`;
  if (state.wallet.txns.some((t) => t.id === txnId)) return ok(state, [{ type: 'already_purchased', itemId }]);
  if (!isStackable(itemId) && ownedQty(state, itemId) > 0) return fail(state, 'owned');
  if (balance(state) < it.price) return fail(state, 'insufficient', { short: it.price - balance(state) });
  const s = clone(state);
  addTxn(s, { id: txnId, amount: -it.price, currency: 'evocoin', cause: `purchase:${itemId}`, at: now });
  grant(s, itemId, 1, 'shop', now, txnId);
  return ok(s, [{ type: 'purchased', itemId }]);
}

// ------------------------------------------------------------ inventory ----
export function equip(state, itemId, now) {
  const it = ITEMS[itemId];
  if (!it || it.category !== 'wearable') return fail(state, 'not_wearable');
  if (ownedQty(state, itemId) < 1) return fail(state, 'not_owned');
  if (!state.pet) return fail(state, 'no_pet');
  if (!itemCompatible(itemId, state.pet.stage)) return fail(state, 'incompatible');
  const s = clone(state);
  const prev = s.pet.equipped[it.slot];
  s.pet.equipped[it.slot] = itemId;
  return ok(s, [{ type: 'equipped', itemId, slot: it.slot, replaced: prev || null }]);
}

export function unequip(state, slot) {
  if (!state.pet?.equipped?.[slot]) return ok(state);
  const s = clone(state);
  const prev = s.pet.equipped[slot];
  delete s.pet.equipped[slot];
  return ok(s, [{ type: 'unequipped', itemId: prev, slot }]);
}

export function useConsumable(state, itemId, now) {
  const it = ITEMS[itemId];
  if (!it || it.category !== 'consumable') return fail(state, 'not_consumable');
  if (ownedQty(state, itemId) < 1) return fail(state, 'not_owned');
  if (it.effect.growth) return fail(state, 'use_in_garden');
  const d = derive(state, now);
  if (!d.pet) return fail(state, 'no_pet');
  if (d.pet.dead) return fail(state, 'pet_dead');
  // a homemade treat still counts for Bond once a day, even when vitality is already full
  const treat = !!it.effect.treat && !(state.pet.bondEvents || []).some((e) => e.key === d.today && e.type === 'treat');
  if (d.pet.vitality >= 100 && !treat) return fail(state, 'full');
  if (it.effect.recovery && d.pet.recoveryReadyAt > now) return fail(state, 'cooldown', { readyAt: d.pet.recoveryReadyAt });
  const s = clone(state);
  s.inventory[itemId].quantity -= 1;
  const gain = Math.min(it.effect.vitality || 0, Math.max(0, 100 - d.pet.vitality));
  s.pet.events.push({ t: now, type: 'care', amount: it.effect.vitality, itemId, recovery: !!it.effect.recovery });
  const events = [{ type: 'used', itemId, vitality: gain }];
  if (treat) {
    s.pet.bondEvents.push({ key: d.today, type: 'treat', t: now });
    const b = derive(s, now).pet.bond - d.pet.bond;
    events.push({ type: 'treat', itemId, bond: b });
    if (b > 0) events.push({ type: 'bond', amount: b });
  }
  return ok(s, events);
}

export function placeDecoration(state, itemId, slotId) {
  const it = ITEMS[itemId];
  if (!it || it.category !== 'decoration') return fail(state, 'not_decoration');
  const slot = DECOR_SLOTS[slotId];
  if (!slot || !slot.accepts.includes(it.decor)) return fail(state, 'no_anchor');
  const placed = Object.entries(state.nest.placements).filter(([sid, id]) => id === itemId && sid !== slotId).length;
  if (placed >= ownedQty(state, itemId)) return fail(state, 'all_placed');
  const s = clone(state);
  s.nest.placements[slotId] = itemId;
  return ok(s, [{ type: 'placed', itemId, slotId }]);
}

export function removeDecoration(state, slotId) {
  const s = clone(state);
  delete s.nest.placements[slotId];
  return ok(s, [{ type: 'removed', slotId }]);
}

// ------------------------------------------------------------ evolution ----
export function evolve(state, now) {
  const d = derive(state, now);
  if (!d.pet) return fail(state, 'no_pet');
  if (d.pet.dead) return fail(state, 'pet_dead');
  if (!d.pet.evo.eligible) return fail(state, 'not_eligible');
  const s = clone(state);
  const next = s.pet.stage + 1;
  if (next <= s.pet.stage || next > 3) return fail(state, 'invalid_stage');
  s.pet.stage = next;
  s.pet.evolutions.push({ stage: next, at: now });
  const removed = [];
  for (const [slot, id] of Object.entries(s.pet.equipped)) {
    if (!itemCompatible(id, next)) {
      delete s.pet.equipped[slot];
      removed.push(id);
    }
  }
  unlock(s, `stage:lizard:${next}`, now);
  return ok(s, [{ type: 'evolved', stage: next, removed }]);
}

// ---------------------------------------------------- recovery / memorial ----
export function reviveWithHerbs(state, now) {
  const d = derive(state, now);
  if (!d.pet?.dead) return fail(state, 'not_dead');
  const cost = CONFIG.care.revive.herbCost;
  if (ownedQty(state, 'healing_herb') < cost) return fail(state, 'need_herbs', { need: cost });
  const s = clone(state);
  s.inventory.healing_herb.quantity -= cost;
  s.pet.events.push({ t: now, type: 'revive', amount: CONFIG.care.revive.vitality, via: 'herbs' });
  return ok(s, [{ type: 'revived', via: 'herbs' }]);
}

/** Free, activity-based revival: reach today's full goal after the pet passed. */
export function reviveWithWalk(state, now) {
  const d = derive(state, now);
  if (!d.pet?.dead) return fail(state, 'not_dead');
  const diedDay = dayKey(d.pet.diedAt, d.tz);
  if (d.today <= diedDay && d.todaySteps < d.goal) return fail(state, 'walk_needed');
  if (d.todaySteps < d.goal) return fail(state, 'walk_needed', { remaining: d.goal - d.todaySteps });
  const s = clone(state);
  s.pet.events.push({ t: now, type: 'revive', amount: CONFIG.care.revive.vitality, via: 'walk' });
  return ok(s, [{ type: 'revived', via: 'walk' }]);
}

export function memorialize(state, now) {
  const d = derive(state, now);
  if (!d.pet) return fail(state, 'no_pet');
  const s = clone(state);
  const p = s.pet;
  s.pastPets.push({
    id: p.id, name: p.name, paletteId: p.paletteId, stage: p.stage, peakLevel: d.pet.level,
    createdAt: p.createdAt, endedAt: now, daysTogether: d.pet.daysTogether, lifetimeSteps: d.pet.lifetimeSteps,
  });
  s.pet = null;
  s.onboarding = { step: 'create', draft: { name: '', paletteId: p.paletteId, habitatId: p.habitatId }, requestId: null };
  return ok(s, [{ type: 'memorialized' }]);
}

// --------------------------------------------------------------- debug ----
export function grantCoins(state, amount, now, cause = 'playtest') {
  const s = clone(state);
  addTxn(s, { id: uid('txn'), amount, currency: 'evocoin', cause, at: now });
  return ok(s);
}

// ------------------------------------------------------------- persist ----
export function serialize(state) {
  return JSON.stringify({ ...state, savedAt: Date.now() });
}

export function migrate(obj) {
  if (!obj || typeof obj !== 'object') return null;
  if (!obj.schema) return null;
  // future: schema upgrades go here
  if (obj.schema > SCHEMA_VERSION) return null;
  // Village Tales (story schema 1) arrived after save schema 1: add it to older saves in place
  ensureStory(obj);
  // Home (garden, cottage, skills) arrived after story schema 1: same in-place upgrade
  ensureHome(obj);
  ensureTrails(obj);
  return obj;
}

export { STAGES, PALETTES, ITEMS, dayKey, dayStart, addDays };
