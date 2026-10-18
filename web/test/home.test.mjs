// Home: garden beds, walking-boosted growth, crafting, skills, the Cottage and Apothecary quests and
// the side stories (special requirements stay optional).
import test from 'node:test';
import assert from 'node:assert/strict';

import * as G from '../src/game/state.js';
import * as Q from '../src/game/story.js';
import * as H from '../src/game/home.js';
import { ITEMS, isShopItem } from '../src/game/catalog.js';
import { dayStart, addDays, HOUR, DAY } from '../src/game/time.js';

const TZ = 'America/New_York';
const T0 = Date.UTC(2026, 9, 5, 14, 0, 0); // Mon 5 Oct 2026, 10:00 New York
const K0 = '2026-10-05';
const MIN = 60000;

function freshPet(now = T0) {
  let s = G.newState(now, TZ);
  s = G.startGuest(s, now, TZ).state;
  s = G.setConnection(s, 'demo', now).state;
  s = G.createPet(s, { name: 'Ember', paletteId: 'amber', requestId: 'req-1' }, now).state;
  s = G.finishOnboarding(s).state;
  return s;
}
function must(r) {
  assert.equal(r.error, null, r.error);
  return r.state;
}
function walkAt(from, steps, tag) {
  return [{ id: `w_${tag}`, source: 'phone', start: from, end: from + HOUR, count: steps }];
}
function give(s, id, n) {
  s = structuredClone(s);
  G.grantItem(s, id, n, 'test', T0);
  return s;
}
function levelUp(s, level, now) {
  let i = 1;
  while (Q.accountLevel(s) < level) {
    const k = addDays(K0, -i);
    s.pet.createdDay = k < s.pet.createdDay ? k : s.pet.createdDay;
    s = G.syncSteps(s, [{ id: `lv_${k}`, source: 'phone', start: dayStart(k, TZ) + 9 * HOUR, end: dayStart(k, TZ) + 10 * HOUR, count: 9000 }], now).state;
    i++;
    assert.ok(i < 400, 'levelling runaway');
  }
  return s;
}
function setSkill(s, skill, level) {
  s = structuredClone(s);
  let xp = 0;
  for (let l = 1; l < level; l++) xp += H.SKILL_CURVE.base + H.SKILL_CURVE.step * (l - 1);
  H.ensureHome(s).skills[skill] = xp;
  return s;
}

test('catalog: seeds are Market items, harvests and homemade food never are', () => {
  for (const c of Object.values(H.CROPS)) {
    assert.ok(isShopItem(c.seed), c.seed);
    for (const id of Object.keys(c.yield)) assert.ok(!isShopItem(id) && ITEMS[id].category === 'ingredient', id);
  }
  for (const r of Object.values(H.RECIPES)) {
    assert.ok(ITEMS[r.makes] && !isShopItem(r.makes), r.makes);
    for (const id of Object.keys(r.needs)) assert.ok(ITEMS[id], id);
  }
});

test('skill curve: levels, carry-over and the cap', () => {
  assert.deepEqual(H.skillLevel(0), { level: 1, into: 0, need: 40, maxed: false });
  assert.equal(H.skillLevel(40).level, 2);
  assert.equal(H.skillLevel(99).level, 2);
  assert.equal(H.skillLevel(100).level, 3);
  assert.equal(H.skillLevel(1e9).level, H.SKILL_CURVE.max);
});

test('old saves get a home in place, and starter seeds come once', () => {
  const s0 = freshPet();
  delete s0.home;
  const s = G.migrate(JSON.parse(JSON.stringify(s0)));
  assert.ok(s.home && s.home.plots.p1 === null && s.home.skills.farming === 0);
  assert.equal(s.story.flags.cottage_restored, false);
  const r1 = H.claimStarterSeeds(s, T0);
  assert.equal(G.ownedQty(r1.state, 'seed_sunberry'), 3);
  const r2 = H.claimStarterSeeds(r1.state, T0 + 1);
  assert.equal(G.ownedQty(r2.state, 'seed_sunberry'), 3, 'starter seeds are granted once');
});

test('planting: seeds, unlocked beds and crops only', () => {
  let s = must(H.claimStarterSeeds(freshPet(), T0));
  assert.equal(H.plant(s, 'p4', 'sunberry', T0).error, 'plot_locked');
  assert.equal(H.plant(s, 'p1', 'glowleaf', T0).error, 'crop_locked');
  assert.equal(H.plant(s, 'p1', 'golden_wheat', T0).error, 'crop_locked');
  s = must(H.plant(s, 'p1', 'sunberry', T0));
  assert.equal(G.ownedQty(s, 'seed_sunberry'), 2);
  assert.equal(H.plant(s, 'p1', 'sunberry', T0).error, 'plot_busy');
  const s2 = setSkill(s, 'farming', 4);
  assert.ok(H.plotUnlocked(s2, 'p4'));
});

test('growth: real time, walking after planting (capped), watering', () => {
  let s = must(H.claimStarterSeeds(freshPet(), T0));
  s = must(H.plant(s, 'p1', 'meadow_carrot', T0)); // 45 minutes
  const at = (t) => H.plotView(s, 'p1', t);
  assert.equal(at(T0).stage, 'sprout');
  assert.ok(Math.abs(at(T0 + 22.5 * MIN).progress - 0.5) < 1e-9);
  assert.equal(H.harvest(s, 'p1', T0 + 20 * MIN).error, 'not_ripe');
  // steps taken BEFORE planting never count
  s = G.syncSteps(s, walkAt(T0 - 2 * HOUR, 5000, 'before'), T0).state;
  assert.equal(at(T0).progress, 0);
  // 3,000 steps after planting = 30% of the growing time
  s = G.syncSteps(s, walkAt(T0 + MIN, 3000, 'after'), T0 + 2 * MIN).state;
  assert.ok(Math.abs(at(T0 + 2 * MIN).walk ?? 0) >= 0);
  assert.ok(Math.abs(H.plotGrowth(s, s.home.plots.p1, T0 + 2 * MIN).walk - 0.3) < 1e-9);
  // walking can add at most 60%
  s = G.syncSteps(s, walkAt(T0 + 3 * MIN, 20000, 'long'), T0 + 4 * MIN).state;
  assert.equal(H.plotGrowth(s, s.home.plots.p1, T0 + 4 * MIN).walk, H.GROW.maxWalkShare);
  // watering once adds 15%, a second time changes nothing
  s = must(H.water(s, 'p1', T0 + 4 * MIN));
  const w = H.plotGrowth(s, s.home.plots.p1, T0 + 4 * MIN).progress;
  s = must(H.water(s, 'p1', T0 + 4 * MIN));
  assert.equal(H.plotGrowth(s, s.home.plots.p1, T0 + 4 * MIN).progress, w);
  // 60% walked + 15% watered + 25% of the time = ripe
  const ripeAt = T0 + Math.ceil(0.25 * 45) * MIN;
  assert.equal(at(ripeAt).ripe, true);
});

test('harvest: yield into the Bag, Farming XP, bed cleared, never twice', () => {
  let s = must(H.claimStarterSeeds(freshPet(), T0));
  s = must(H.plant(s, 'p2', 'sunberry', T0));
  const r = H.harvest(s, 'p2', T0 + 21 * MIN);
  s = must(r);
  assert.equal(G.ownedQty(s, 'sunberry'), 3);
  assert.equal(s.home.skills.farming, H.CROPS.sunberry.xp);
  assert.equal(s.home.plots.p2, null);
  assert.equal(H.harvest(s, 'p2', T0 + 22 * MIN).error, 'plot_empty');
  assert.ok(r.events.some((e) => e.type === 'harvested'));
});

test('skill-ups name what they unlock', () => {
  let s = give(must(H.claimStarterSeeds(freshPet(), T0)), 'seed_sunberry', 10);
  let ups = [];
  let t = T0;
  for (let i = 0; i < 4; i++) {
    s = must(H.plant(s, 'p1', 'sunberry', t));
    t += 21 * MIN;
    const r = H.harvest(s, 'p1', t);
    s = must(r);
    ups.push(...r.events.filter((e) => e.type === 'skill_up'));
  }
  assert.equal(ups.length, 1);
  assert.equal(ups[0].level, 2);
  assert.ok(ups[0].unlocks.some((m) => m.kind === 'crop' && m.id === 'golden_wheat'));
});

test('crafting: station must be open, recipe known, ingredients complete; perfect doubles the batch', () => {
  let s = give(give(freshPet(), 'sunberry', 7), 'golden_wheat', 2);
  assert.equal(H.craft(s, 'sunberry_tart', 'good', T0).error, 'station_locked');
  s = structuredClone(s);
  s.story.flags.cottage_restored = true;
  assert.equal(H.craft(s, 'golden_bun', 'good', T0).error, 'recipe_locked');
  const r = H.craft(s, 'sunberry_tart', 'good', T0);
  s = must(r);
  assert.equal(G.ownedQty(s, 'sunberry_tart'), 1);
  assert.equal(G.ownedQty(s, 'sunberry'), 4);
  assert.equal(s.home.skills.cooking, 20);
  const r2 = H.craft(s, 'sunberry_tart', 'perfect', T0);
  s = must(r2);
  assert.equal(G.ownedQty(s, 'sunberry_tart'), 3);
  assert.equal(s.home.skills.cooking, 50);
  assert.equal(H.craft(s, 'sunberry_tart', 'perfect', T0).error, 'missing_ingredients');
  assert.equal(G.ownedQty(s, 'sunberry'), 1, 'a failed craft takes nothing');
});

test('homemade treats: vitality, plus Bond once a day even at full vitality', () => {
  let s = give(freshPet(), 'carrot_stew', 3);
  const d0 = G.derive(s, T0);
  assert.equal(d0.pet.vitality, 100);
  s = must(G.useConsumable(s, 'carrot_stew', T0));
  const d1 = G.derive(s, T0);
  assert.equal(d1.pet.bond, d0.pet.bond + 1);
  assert.equal(G.useConsumable(s, 'carrot_stew', T0 + 1).error, 'full', 'second treat on a full day: nothing to do');
  assert.equal(G.useConsumable(give(s, 'sprout_tonic', 1), 'sprout_tonic', T0).error, 'use_in_garden');
});

test('Sprout Tonic adds half a growing time once', () => {
  let s = give(must(H.claimStarterSeeds(freshPet(), T0)), 'sprout_tonic', 2);
  s = must(H.plant(s, 'p1', 'sunberry', T0));
  s = must(H.useSproutTonic(s, 'p1', T0));
  assert.equal(H.plotView(s, 'p1', T0).progress, 0.5);
  assert.equal(H.useSproutTonic(s, 'p1', T0).error, 'tonic_used');
  assert.equal(G.ownedQty(s, 'sprout_tonic'), 1);
});

test('A Place to Call Home: walk for timber, harvest berries, Bram, then restore -> Kitchen opens', () => {
  let s = freshPet();
  assert.equal(Q.questPhase(s, 'hq01'), 'locked');
  s = levelUp(s, 2, T0);
  let now = T0 + HOUR;
  // finish VQ01 first
  s = must(Q.acceptStoryQuest(s, 'vq01', now));
  s = G.syncSteps(s, walkAt(now + MIN, 2500, 'vq01'), now + 2 * HOUR).state;
  s = must(Q.storyHandIn(s, 'vq01', 'mira_dew', now + 2 * HOUR));
  s = must(Q.storyHandIn(s, 'vq01', 'bram_sprig', now + 2 * HOUR));
  now += 3 * HOUR;
  assert.equal(Q.questPhase(s, 'hq01'), 'available');
  s = must(Q.acceptStoryQuest(s, 'hq01', now));
  assert.equal(Q.questPhase(s, 'hq01'), 'accepted_walk');
  s = G.syncSteps(s, walkAt(now + MIN, 3200, 'hq01'), now + 2 * HOUR).state;
  assert.equal(Q.questPhase(s, 'hq01'), 'timber_ready');
  assert.equal(Q.pouchQty(s, 'q_sturdy_timber'), 1);
  // no Sunberries yet: gather first, and the hand-in is refused without taking anything
  assert.equal(Q.nextStep(s, 'hq01').kind, 'gather');
  assert.equal(Q.storyHandIn(s, 'hq01', 'bram_timber', now).error, 'story_missing_items');
  assert.equal(Q.pouchQty(s, 'q_sturdy_timber'), 1);
  const v = Q.questView(s, 'hq01', now);
  assert.deepEqual([v.objectives.find((o) => o.id === 'berries').have, v.objectives.find((o) => o.id === 'berries').need], [0, 3]);
  // grow them
  s = must(H.claimStarterSeeds(s, now));
  s = must(H.plant(s, 'p1', 'sunberry', now + 2 * HOUR));
  s = must(H.harvest(s, 'p1', now + 3 * HOUR));
  assert.equal(Q.nextStep(s, 'hq01').kind, 'handin');
  s = must(Q.storyHandIn(s, 'hq01', 'bram_timber', now + 3 * HOUR));
  assert.equal(G.ownedQty(s, 'sunberry'), 0);
  assert.equal(Q.questPhase(s, 'hq01'), 'restoration_ready');
  assert.equal(Q.nextStep(s, 'hq01').place, 'cottage');
  assert.equal(H.stationOpen(s, 'kitchen'), false);
  const coins = G.balance(s);
  const r = Q.storyHandIn(s, 'hq01', 'restore_cottage', now + 3 * HOUR);
  s = must(r);
  assert.equal(Q.questPhase(s, 'hq01'), 'completed');
  assert.equal(H.stationOpen(s, 'kitchen'), true);
  assert.equal(G.balance(s), coins + 100);
  assert.equal(G.ownedQty(s, 'seed_golden_wheat'), 3);
  // paid once
  const again = Q.storyHandIn(s, 'hq01', 'restore_cottage', now + 4 * HOUR);
  assert.equal(G.balance(again.state), coins + 100);
});

test("Mira's Mortar needs Cooking 2 and 2 Glowleaf; it opens the Apothecary", () => {
  let s = freshPet();
  s = structuredClone(s);
  s.story.questStates.vq01 = { phase: 'completed' };
  s.story.questStates.hq01 = { phase: 'completed' };
  s.story.flags.cottage_restored = true;
  s = levelUp(s, 2, T0);
  assert.match(Q.lockReason(s, 'hq02').text, /Cooking Lv 2/);
  s = setSkill(s, 'cooking', 2);
  assert.equal(Q.lockReason(s, 'hq02'), null);
  s = must(Q.acceptStoryQuest(s, 'hq02', T0));
  assert.equal(Q.questPhase(s, 'hq02'), 'need_glowleaf');
  assert.equal(Q.nextStep(s, 'hq02').kind, 'gather');
  s = give(s, 'glowleaf', 2);
  s = must(Q.storyHandIn(s, 'hq02', 'mira_glowleaf', T0));
  assert.equal(H.stationOpen(s, 'apothecary'), true);
  assert.equal(G.ownedQty(s, 'glowleaf'), 0);
});

test('side story: the Grove asks for a grown Evochi, and it stays optional', () => {
  let s = freshPet();
  s = structuredClone(s);
  for (const q of ['vq01', 'hq01', 'hq02']) s.story.questStates[q] = { phase: 'completed' };
  s = levelUp(s, 4, T0);
  const lock = Q.lockReason(s, 'sq02');
  assert.equal(lock.needStage, 2);
  assert.match(lock.text, /Juvenile/);
  // nothing on the main path depends on a side story
  for (const q of Object.values(Q.QUESTS)) if (q.line !== 'side') assert.ok(!q.dependsOn.some((d) => Q.QUESTS[d].line === 'side'), q.id);
  s.pet.stage = 2;
  assert.equal(Q.lockReason(s, 'sq02'), null);
  s = must(Q.acceptStoryQuest(s, 'sq02', T0));
  s = give(s, 'glowleaf_tonic', 1);
  s = must(Q.storyHandIn(s, 'sq02', 'alder_tonic', T0));
  assert.ok(s.story.titleUnlocks.includes('grove_friend'));
});

test('npc markers and conversations reach the new quests without breaking Chapter 1', () => {
  let s = freshPet();
  s = structuredClone(s);
  s.story.questStates.vq01 = { phase: 'completed' };
  s = levelUp(s, 2, T0);
  assert.equal(Q.npcMarkers(s, T0).npc_bram, 'quest');
  const c = Q.npcConversation(s, 'npc_bram', T0);
  assert.equal(c.start, 'HQ01_B00');
  const mira = Q.npcConversation(s, 'npc_mira', T0);
  assert.equal(mira.start, 'VQ01_M07');
  assert.ok(Q.lineText(s, 'HQ01_B02', T0).includes('3,000'));
});

test('labels and sources: plural names and where each home item comes from', () => {
  assert.equal(H.itemLabel('sunberry', 3), 'Sunberries');
  assert.equal(H.itemLabel('sunberry', 1), 'Sunberry');
  assert.equal(H.itemLabel('golden_wheat', 2), 'Golden Wheat');
  assert.equal(H.itemLabel('glowleaf', 2), 'Glowleaf');
  assert.equal(H.itemLabel('seed_moonshroom', 3), 'Moonshroom Spores');
  assert.equal(H.itemLabel('sunberry_tart', 2), 'Sunberry Tarts');
  assert.deepEqual(H.homeSource('sunberry'), { route: 'garden', verb: 'Grow', place: 'Garden' });
  assert.equal(H.homeSource('sunberry_tart').station, 'kitchen');
  assert.equal(H.homeSource('glowleaf_tonic').station, 'apothecary');
  assert.equal(H.homeSource('berry_snack'), null);
  // every quest text that can ask for an item resolves to a place to get it
  for (const q of Object.values(Q.QUESTS)) {
    for (const t of q.turnIns) for (const id of Object.keys(t.consumeItems || {})) assert.ok(H.homeSource(id), id);
  }
});

test('the story still reads well for walk-less quests (no crash in line text)', () => {
  let s = freshPet();
  for (const id of Object.keys(Q.LINES)) assert.equal(typeof Q.lineText(s, id, T0, 'Ember'), 'string', id);
});
