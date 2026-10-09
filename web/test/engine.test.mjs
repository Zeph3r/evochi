// Engine tests, including the release QA matrix cases that are pure game logic (§24).
import test from 'node:test';
import assert from 'node:assert/strict';

import * as G from '../src/game/state.js';
import { activityXp, xpToNext, levelInfo, replayVitality, bondValue } from '../src/game/progression.js';
import { aggregateDays } from '../src/game/steps.js';
import { dayKey, dayStart, addDays, weekKey, HOUR, DAY } from '../src/game/time.js';
import { simulateDay } from '../src/game/health.js';

const TZ = 'America/New_York';
const T0 = Date.UTC(2026, 9, 5, 14, 0, 0); // Mon 5 Oct 2026, 10:00 New York

function freshPet(now = T0, extra = {}) {
  let s = G.newState(now, TZ);
  s = G.startGuest(s, now, TZ).state;
  s = G.setConnection(s, 'demo', now).state;
  const r = G.createPet(s, { name: 'Ember', paletteId: 'amber', requestId: 'req-1', ...extra }, now);
  assert.equal(r.error, null);
  return r.state;
}

function walk(key, steps, idTag = '') {
  const start = dayStart(key, TZ) + 9 * HOUR;
  return [{ id: `w_${key}_${steps}_${idTag}`, source: 'phone', start, end: start + HOUR, count: steps }];
}

test('activity XP worked example (§15)', () => {
  const rows = [[0, 0], [1750, 35], [3500, 75], [4850, 94], [7000, 150], [10500, 170], [20000, 170]];
  for (const [s, xp] of rows) assert.equal(activityXp(s, 7000).total, xp, `steps ${s}`);
  const r = activityXp(4850, 7000);
  assert.equal(r.base, 69);
  assert.equal(r.milestones, 25);
});

test('level curve: ~600 XP needed at level 8', () => {
  assert.equal(xpToNext(1), 120);
  assert.equal(xpToNext(8), 600);
  const total = Array.from({ length: 7 }, (_, i) => xpToNext(i + 1)).reduce((a, b) => a + b, 0);
  const li = levelInfo(total + 320);
  assert.equal(li.level, 8);
  assert.equal(li.into, 320);
  assert.equal(li.need, 600);
});

test('Q01 fresh install -> guest -> create pet exactly once', () => {
  let s = freshPet();
  const again = G.createPet(s, { name: 'Ember', paletteId: 'amber', requestId: 'req-1' }, T0 + 1000);
  assert.equal(again.error, null);
  assert.equal(again.state.pet.id, s.pet.id, 'retry with same request id is idempotent');
  const other = G.createPet(s, { name: 'Other', paletteId: 'ocean', requestId: 'req-2' }, T0 + 2000);
  assert.equal(other.error, 'pet_exists');
  assert.equal(s.pet.paletteId, 'amber');
  assert.equal(s.pet.name, 'Ember');
});

test('name validation', () => {
  assert.equal(G.validateName('  Ember  ').name, 'Ember');
  assert.equal(G.validateName('').ok, false);
  assert.equal(G.validateName('x'.repeat(13)).ok, false);
  assert.equal(G.validateName('<script>').ok, false);
});

test('Q03 sync 4,850 / 7,000 steps -> 94 XP once', () => {
  let s = freshPet();
  const key = dayKey(T0, TZ);
  const r = G.syncSteps(s, walk(key, 4850), T0 + HOUR);
  s = r.state;
  const d = G.derive(s, T0 + HOUR);
  assert.equal(d.todaySteps, 4850);
  assert.equal(d.pet.totalXp, 94);
  assert.ok(r.events.some((e) => e.type === 'xp' && e.amount === 94));
});

test('Q04 re-delivered sample gives no extra XP or coins', () => {
  let s = freshPet();
  const key = dayKey(T0, TZ);
  s = G.syncSteps(s, walk(key, 7000), T0 + HOUR).state;
  s = G.claimQuest(s, 'daily_goal', T0 + HOUR).state;
  const bal = G.balance(s);
  const xp = G.derive(s, T0 + HOUR).pet.totalXp;
  const r = G.syncSteps(s, walk(key, 7000), T0 + 2 * HOUR);
  s = r.state;
  assert.equal(G.derive(s, T0 + 2 * HOUR).pet.totalXp, xp);
  assert.equal(G.balance(s), bal);
  assert.ok(!r.events.some((e) => e.type === 'xp'));
});

test('cross-source de-duplication (phone + watch count once)', () => {
  const key = dayKey(T0, TZ);
  const start = dayStart(key, TZ) + 9 * HOUR;
  const samples = [
    { id: 'a', source: 'phone', start, end: start + 15 * 60000, count: 1000, manual: false },
    { id: 'b', source: 'watch', start, end: start + 15 * 60000, count: 980, manual: false },
  ];
  assert.equal(aggregateDays(samples, TZ)[key].steps, 1000);
});

test('Q05 rapid double claim grants once', () => {
  let s = freshPet();
  s = G.syncSteps(s, walk(dayKey(T0, TZ), 2000), T0 + HOUR).state;
  const r1 = G.claimQuest(s, 'first_steps', T0 + HOUR);
  const r2 = G.claimQuest(r1.state, 'first_steps', T0 + HOUR + 5);
  assert.equal(G.balance(r2.state), 15);
  assert.equal(r2.state.wallet.txns.filter((t) => t.cause === 'quest:first_steps').length, 1);
  assert.ok(r2.events.some((e) => e.type === 'already_claimed'));
});

test('quests are not claimable before the threshold', () => {
  let s = freshPet();
  s = G.syncSteps(s, walk(dayKey(T0, TZ), 1000), T0 + HOUR).state;
  assert.equal(G.claimQuest(s, 'first_steps', T0 + HOUR).error, 'not_eligible');
});

test('Q07 purchase affordable crown; Q08 insufficient funds', () => {
  let s = freshPet();
  s = G.grantCoins(s, 200, T0).state;
  const r = G.purchase(s, 'golden_crest_crown', 'buy-1', T0);
  assert.equal(r.error, null);
  assert.equal(G.balance(r.state), 50);
  assert.equal(G.ownedQty(r.state, 'golden_crest_crown'), 1);
  // retry with same request id is a no-op
  const again = G.purchase(r.state, 'golden_crest_crown', 'buy-1', T0 + 1);
  assert.equal(G.balance(again.state), 50);
  // already owned
  assert.equal(G.purchase(r.state, 'golden_crest_crown', 'buy-2', T0).error, 'owned');
  // insufficient
  const poor = G.purchase(r.state, 'explorer_hat', 'buy-3', T0);
  assert.equal(poor.error, 'insufficient');
  assert.equal(G.balance(poor.state), 50);
  assert.equal(G.ownedQty(poor.state, 'explorer_hat'), 0);
});

test('Q06 equip head cosmetic then evolve: anchors kept, no entitlement lost', () => {
  let s = freshPet();
  s = G.grantCoins(s, 500, T0).state;
  s = G.purchase(s, 'explorer_hat', 'p1', T0).state;
  s = G.equip(s, 'explorer_hat', T0).state;
  // stage 2 needs level 10 (3,340 XP at max 170/day) and 7 active days
  let now = T0;
  for (let i = 0; i < 20; i++) {
    const key = addDays(dayKey(T0, TZ), i);
    now = dayStart(key, TZ) + 20 * HOUR;
    s = G.syncSteps(s, walk(key, 10500), now).state;
  }
  const d = G.derive(s, now);
  assert.ok(d.pet.level >= 10, `level ${d.pet.level}`);
  assert.ok(d.pet.evo.eligible);
  const r = G.evolve(s, now);
  assert.equal(r.error, null);
  assert.equal(r.state.pet.stage, 2);
  assert.equal(r.state.pet.equipped.head, 'explorer_hat');
  assert.equal(G.ownedQty(r.state, 'explorer_hat'), 1);
  assert.equal(G.evolve(r.state, now).error, 'not_eligible');
});

test('equip rules: one item per slot, ownership required', () => {
  let s = freshPet();
  assert.equal(G.equip(s, 'leaf_scarf', T0).error, 'not_owned');
  s = G.grantCoins(s, 500, T0).state;
  s = G.purchase(s, 'leaf_scarf', 'a', T0).state;
  s = G.purchase(s, 'blue_scarf', 'b', T0).state;
  s = G.equip(s, 'leaf_scarf', T0).state;
  const r = G.equip(s, 'blue_scarf', T0);
  assert.equal(r.state.pet.equipped.neck, 'blue_scarf');
  assert.equal(r.events[0].replaced, 'leaf_scarf');
});

test('Q10 two protected rest days per rolling week; penalties wait 48h grace', () => {
  let s = freshPet();
  const k0 = dayKey(T0, TZ);
  // day 0 healthy walk; days 1..4 zero steps; synced through day 5
  s = G.syncSteps(s, walk(k0, 7000), T0 + HOUR).state;
  const day6 = addDays(k0, 6);
  const now = dayStart(day6, TZ) + 12 * HOUR;
  s = G.syncSteps(s, [], now).state;
  const d = G.derive(s, now);
  const kinds = Object.fromEntries(d.pet.vitalityLog.filter((x) => x.key).map((x) => [x.key, x.kind]));
  assert.equal(kinds[k0], 'goal');
  assert.equal(kinds[addDays(k0, 1)], 'rest');
  assert.equal(kinds[addDays(k0, 2)], 'rest');
  assert.equal(kinds[addDays(k0, 3)], 'low');
  // days 4 and 5 ended 36h / 12h ago: still inside the 48h grace window
  assert.equal(kinds[addDays(k0, 4)], 'grace');
  assert.equal(kinds[addDays(k0, 5)], 'grace');
  assert.equal(d.pet.vitality, 100 - 8);
});

test('late data reverses an incorrect penalty (idempotent replay)', () => {
  let s = freshPet();
  const k0 = dayKey(T0, TZ);
  const now = dayStart(addDays(k0, 6), TZ) + 12 * HOUR;
  s = G.syncSteps(s, [], now).state;
  const before = G.derive(s, now).pet.vitality;
  // a delayed sync shows day 3 was actually active
  s = G.syncSteps(s, simulateDay(addDays(k0, 3), 6000, TZ), now + 1000).state;
  const after = G.derive(s, now + 1000).pet.vitality;
  assert.ok(after > before, `${after} > ${before}`);
});

test('missing sensor data is pending, not inactive', () => {
  let s = freshPet();
  const k0 = dayKey(T0, TZ);
  s.steps.syncedUntil = T0; // no sync after creation
  const now = dayStart(addDays(k0, 6), TZ);
  const d = G.derive(s, now);
  assert.equal(d.pet.vitality, 100);
  assert.ok(d.pet.vitalityLog.every((x) => !x.key || x.kind === 'pending'));
});

test('Q11 time zone travel keeps day attribution deterministic', () => {
  let s = freshPet();
  const key = dayKey(T0, TZ);
  s = G.syncSteps(s, walk(key, 7000), T0 + HOUR).state;
  s = G.claimQuest(s, 'daily_goal', T0 + HOUR).state;
  const bal = G.balance(s);
  // the device moves to Tokyo; account time zone is unchanged, so the same samples land on the same day
  const d = G.derive(s, T0 + 2 * HOUR);
  assert.equal(d.today, key);
  const again = G.claimQuest(s, 'daily_goal', T0 + 2 * HOUR);
  assert.equal(G.balance(again.state), bal);
});

test('Q14 vitality zero -> memorial keeps possessions; revive paths', () => {
  let s = freshPet();
  s = G.grantCoins(s, 300, T0).state;
  s = G.purchase(s, 'leaf_scarf', 'x', T0).state;
  const k0 = dayKey(T0, TZ);
  const now = dayStart(addDays(k0, 40), TZ) + 12 * HOUR;
  s = G.syncSteps(s, [], now).state;
  const d = G.derive(s, now);
  assert.equal(d.pet.dead, true);
  assert.equal(d.pet.status, 'dead');
  assert.equal(G.useConsumable(s, 'berry_snack', now).error, 'pet_dead');
  // walk-based revival is free
  assert.equal(G.reviveWithWalk(s, now).error, 'walk_needed');
  const today = dayKey(now, TZ);
  const s2 = G.syncSteps(s, walk(today, 7200, 'rv'), now + 1000).state;
  const rv = G.reviveWithWalk(s2, now + 2000);
  assert.equal(rv.error, null);
  assert.equal(G.derive(rv.state, now + 2000).pet.dead, false);
  // or start a new egg: cosmetics and coins persist
  const m = G.memorialize(s, now);
  assert.equal(m.state.pet, null);
  assert.equal(m.state.pastPets.length, 1);
  assert.equal(G.ownedQty(m.state, 'leaf_scarf'), 1);
  assert.equal(G.balance(m.state), G.balance(s));
});

test('bond: daily direct cap and celebration', () => {
  const ev = [
    { key: 'd1', type: 'pet' }, { key: 'd1', type: 'pet' }, { key: 'd1', type: 'play' }, { key: 'd1', type: 'goal' },
  ];
  assert.equal(bondValue(ev), 6);
});

test('consumables: decrement on accepted use, herb cooldown', () => {
  let s = freshPet();
  const k0 = dayKey(T0, TZ);
  const now = dayStart(addDays(k0, 9), TZ) + 12 * HOUR;
  s = G.syncSteps(s, [], now).state; // several penalties so vitality is well below 100
  const v0 = G.derive(s, now).pet.vitality;
  assert.ok(v0 < 100);
  const r = G.useConsumable(s, 'berry_snack', now);
  assert.equal(r.error, null);
  assert.equal(G.ownedQty(r.state, 'berry_snack'), 1);
  assert.equal(G.derive(r.state, now).pet.vitality, Math.min(100, v0 + 4));
  s = G.grantCoins(r.state, 200, now).state;
  s = G.purchase(s, 'healing_herb', 'h1', now).state;
  s = G.purchase(s, 'healing_herb', 'h2', now).state;
  s = G.useConsumable(s, 'healing_herb', now).state;
  assert.equal(G.useConsumable(s, 'healing_herb', now + HOUR).error, 'cooldown');
});

test('decorations need a compatible anchor and ownership', () => {
  let s = freshPet();
  assert.equal(s.nest.placements.nest, 'nest_bed');
  assert.equal(G.placeDecoration(s, 'nest_bed', 'left').error, 'no_anchor');
  assert.equal(G.placeDecoration(s, 'sunlit_flower', 'left').error, 'all_placed');
  s = G.grantCoins(s, 100, T0).state;
  s = G.purchase(s, 'sunlit_flower', 'f', T0).state;
  s = G.placeDecoration(s, 'sunlit_flower', 'left').state;
  assert.equal(G.placeDecoration(s, 'sunlit_flower', 'right').error, 'all_placed');
});

test('week keys', () => {
  assert.equal(weekKey('2026-10-05'), '2026-W41');
  assert.equal(weekKey('2026-10-11'), '2026-W41');
  assert.equal(weekKey('2026-10-12'), '2026-W42');
  assert.equal(weekKey('2027-01-01'), '2026-W53');
});

test('dayStart is local midnight across DST', () => {
  const s = dayStart('2026-11-01', TZ); // DST ends this day
  assert.equal(dayKey(s, TZ), '2026-11-01');
  assert.equal(dayKey(s - 1, TZ), '2026-10-31');
});

test('sample compaction keeps day totals (and XP) unchanged', async () => {
  const { compactSamples } = await import('../src/game/state.js');
  let s = freshPet();
  const k0 = dayKey(T0, TZ);
  const many = [];
  for (let i = 0; i < 40; i++) {
    const st = dayStart(k0, TZ) + 8 * HOUR + i * 600000;
    many.push({ id: 'p' + i, source: 'phone', start: st, end: st + 300000, count: 150 });
    many.push({ id: 'w' + i, source: 'watch', start: st, end: st + 300000, count: 140 });
  }
  s = G.syncSteps(s, many, T0 + 10 * HOUR).state;
  const before = G.derive(s, T0 + 10 * HOUR);
  const later = dayStart(addDays(k0, 20), TZ);
  const s2 = G.syncSteps(s, [], later).state;
  assert.ok(s2.steps.samples.length < 5, `compacted to ${s2.steps.samples.length}`);
  const after = G.derive(s2, later);
  assert.equal(after.days[k0].steps, before.days[k0].steps);
  assert.equal(after.pet.totalXp, before.pet.totalXp);
  // re-delivering an already-compacted day's samples must not double count it
  const s3 = G.syncSteps(s2, many.slice(0, 2), later + 1000).state;
  assert.equal(G.derive(s3, later + 1000).days[k0].steps, before.days[k0].steps);
});
