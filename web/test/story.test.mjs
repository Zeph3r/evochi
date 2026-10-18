// Village Tales, Chapter 1: the ten acceptance tests from the Quest Bible (§9) plus step-rule checks.
import test from 'node:test';
import assert from 'node:assert/strict';

import * as G from '../src/game/state.js';
import * as Q from '../src/game/story.js';
import { ITEMS, isShopItem } from '../src/game/catalog.js';
import { CONFIG } from '../src/game/config.js';
import { dayStart, addDays, HOUR, DAY } from '../src/game/time.js';

const TZ = 'America/New_York';
const T0 = Date.UTC(2026, 9, 5, 14, 0, 0); // Mon 5 Oct 2026, 10:00 New York
const K0 = '2026-10-05';

function freshPet(now = T0) {
  let s = G.newState(now, TZ);
  s = G.startGuest(s, now, TZ).state;
  s = G.setConnection(s, 'demo', now).state;
  s = G.createPet(s, { name: 'Ember', paletteId: 'amber', requestId: 'req-1' }, now).state;
  s = G.finishOnboarding(s).state;
  return s;
}

/** A walk of `steps` inside [from, from + 1h]. */
function walkAt(from, steps, tag) {
  return [{ id: `w_${tag}`, source: 'phone', start: from, end: from + HOUR, count: steps }];
}
function sync(s, samples, now) {
  const r = G.syncSteps(s, samples, now);
  assert.equal(r.error, null);
  return r;
}
function must(r) {
  assert.equal(r.error, null, r.error);
  return r.state;
}
/** Give the pet enough XP for `level` by backfilling past days (before any quest is accepted). */
function levelUp(s, level, now) {
  let i = 1;
  while (Q.accountLevel(s) < level) {
    const k = addDays(K0, -i);
    // backdate the pet so earlier days count
    s.pet.createdDay = k < s.pet.createdDay ? k : s.pet.createdDay;
    s = sync(s, [{ id: `lv_${k}`, source: 'phone', start: dayStart(k, TZ) + 9 * HOUR, end: dayStart(k, TZ) + 10 * HOUR, count: 9000 }], now).state;
    i++;
    assert.ok(i < 400, 'levelling runaway');
  }
  return s;
}
function finishVq01(s, now) {
  s = must(Q.acceptStoryQuest(s, 'vq01', now));
  s = sync(s, walkAt(now + 60000, 2500, `vq01_${now}`), now + 2 * HOUR).state;
  s = must(Q.storyHandIn(s, 'vq01', 'mira_dew', now + 2 * HOUR));
  s = must(Q.storyHandIn(s, 'vq01', 'bram_sprig', now + 2 * HOUR));
  return s;
}

test('VQ01 full flow: walk after accepting, Mira, Bram, Firefly Hearth + 75 coins once', () => {
  let s = freshPet();
  assert.equal(Q.questPhase(s, 'vq01'), 'available');
  s = must(Q.acceptStoryQuest(s, 'vq01', T0));
  assert.equal(s.story.questStates.vq01.resolvedSteps, 2000);
  let r = sync(s, walkAt(T0 + 60000, 1200, 'a'), T0 + 2 * HOUR);
  s = r.state;
  assert.equal(Q.questPhase(s, 'vq01'), 'accepted_walk');
  assert.equal(Q.questView(s, 'vq01', T0 + 2 * HOUR).walk.progress, 1200);
  r = sync(s, walkAt(T0 + 3 * HOUR, 900, 'b'), T0 + 4 * HOUR);
  s = r.state;
  assert.equal(Q.questPhase(s, 'vq01'), 'dew_ready');
  assert.equal(Q.pouchQty(s, 'q_dawn_dew_vial'), 1);
  assert.ok(r.events.some((e) => e.type === 'story_item' && e.itemId === 'q_dawn_dew_vial'));
  // Bram can't be skipped to
  assert.equal(Q.storyHandIn(s, 'vq01', 'bram_sprig', T0 + 4 * HOUR).error, 'story_not_ready');
  s = must(Q.storyHandIn(s, 'vq01', 'mira_dew', T0 + 4 * HOUR));
  assert.equal(Q.pouchQty(s, 'q_dawn_dew_vial'), 0);
  assert.equal(Q.pouchQty(s, 'q_lumenbud_sprig'), 1);
  const before = G.balance(s);
  r = Q.storyHandIn(s, 'vq01', 'bram_sprig', T0 + 4 * HOUR);
  s = must(r);
  assert.equal(Q.questPhase(s, 'vq01'), 'completed');
  assert.equal(G.balance(s), before + 75);
  assert.equal(G.ownedQty(s, 'reward_firefly_hearth'), 1);
  assert.equal(s.story.flags.lamp_lit, true);
  assert.ok(r.events.some((e) => e.type === 'story_completed'));
});

test('AT1 replaying the same step batch five times adds no progress, materials or coins', () => {
  let s = freshPet();
  s = must(Q.acceptStoryQuest(s, 'vq01', T0));
  const batch = walkAt(T0 + 60000, 900, 'replay');
  for (let i = 0; i < 5; i++) s = sync(s, batch, T0 + 2 * HOUR + i).state;
  assert.equal(Q.questView(s, 'vq01', T0 + 3 * HOUR).walk.progress, 900);
  assert.equal(Q.questPhase(s, 'vq01'), 'accepted_walk');
  const big = walkAt(T0 + 2 * HOUR, 3000, 'big');
  for (let i = 0; i < 5; i++) s = sync(s, big, T0 + 4 * HOUR + i).state;
  assert.equal(Q.pouchQty(s, 'q_dawn_dew_vial'), 1, 'one vial, however many replays');
  s = must(Q.storyHandIn(s, 'vq01', 'mira_dew', T0 + 5 * HOUR));
  s = must(Q.storyHandIn(s, 'vq01', 'bram_sprig', T0 + 5 * HOUR));
  const bal = G.balance(s);
  for (let i = 0; i < 5; i++) {
    s = sync(s, big, T0 + 6 * HOUR + i).state;
    s = must(Q.storyHandIn(s, 'vq01', 'bram_sprig', T0 + 6 * HOUR + i));
  }
  assert.equal(G.balance(s), bal);
  assert.equal(G.ownedQty(s, 'reward_firefly_hearth'), 1);
  assert.equal(s.wallet.txns.filter((t) => t.id === 'story:vq01').length, 1);
});

test('no retroactive credit: steps before acceptance never count', () => {
  let s = freshPet();
  s = sync(s, walkAt(T0 - 2 * HOUR, 5000, 'before'), T0 - HOUR).state;
  s = must(Q.acceptStoryQuest(s, 'vq01', T0));
  s = sync(s, [], T0 + HOUR).state;
  assert.equal(Q.questView(s, 'vq01', T0 + HOUR).walk.progress, 0);
  // a late-delivered sample from before acceptance changes nothing either
  s = sync(s, walkAt(T0 - 3 * HOUR, 4000, 'late'), T0 + HOUR).state;
  assert.equal(Q.questPhase(s, 'vq01'), 'accepted_walk');
  // a sample straddling acceptance counts only its share after acceptance
  s = sync(s, [{ id: 'straddle', source: 'phone', start: T0 - 30 * 60000, end: T0 + 30 * 60000, count: 1000 }], T0 + 2 * HOUR).state;
  assert.equal(Q.questView(s, 'vq01', T0 + 2 * HOUR).walk.progress, 500);
});

test('target is min(nominal, personal goal) and frozen at acceptance', () => {
  let s = freshPet();
  s = must(G.setGoal(s, 1500, T0));
  s = must(Q.acceptStoryQuest(s, 'vq01', T0));
  assert.equal(s.story.questStates.vq01.resolvedSteps, 1500);
  s = must(G.setGoal(s, 1000, T0 + 1000));
  assert.equal(Q.questView(s, 'vq01', T0 + 2000).resolved, 1500, 'a lower goal later cannot lower the quest');
  s = sync(s, walkAt(T0 + 60000, 1200, 'x'), T0 + 2 * HOUR).state;
  assert.equal(Q.questPhase(s, 'vq01'), 'accepted_walk');
});

test('AT2 5,000 steps on one day grant only one Windprint Paper; a second day grants the second', () => {
  let s = freshPet();
  s = levelUp(s, 3, T0);
  s = finishVq01(s, T0);
  const t1 = T0 + 3 * HOUR;
  s = must(Q.acceptStoryQuest(s, 'vq02', t1));
  assert.equal(s.story.questStates.vq02.resolvedSteps, 2500);
  s = sync(s, walkAt(t1 + 60000, 5000, 'd1a'), t1 + 2 * HOUR).state;
  s = sync(s, walkAt(t1 + 3 * HOUR, 5000, 'd1b'), t1 + 5 * HOUR).state;
  assert.equal(Q.pouchQty(s, 'q_windprint_paper'), 1);
  assert.equal(Q.questView(s, 'vq02', t1 + 5 * HOUR).walk.qualified, 1);
  // next local day
  const k1 = addDays(K0, 1);
  const d2 = dayStart(k1, TZ) + 9 * HOUR;
  s = sync(s, walkAt(d2, 2600, 'd2'), d2 + 2 * HOUR).state;
  assert.equal(Q.pouchQty(s, 'q_windprint_paper'), 2);
  assert.equal(Q.questPhase(s, 'vq02'), 'paper_2_ready');
  // a third day can't mint a third paper
  const k2 = addDays(K0, 2);
  s = sync(s, walkAt(dayStart(k2, TZ) + 9 * HOUR, 9000, 'd3'), dayStart(k2, TZ) + 12 * HOUR).state;
  assert.equal(Q.pouchQty(s, 'q_windprint_paper'), 2);
  s = must(Q.storyHandIn(s, 'vq02', 'pip_papers', dayStart(k2, TZ) + 13 * HOUR));
  s = must(Q.storyHandIn(s, 'vq02', 'alder_letter', dayStart(k2, TZ) + 13 * HOUR));
  assert.equal(G.ownedQty(s, 'reward_windtrail_mantle'), 1);
  assert.equal(s.story.flags.waystone_revealed, true);
});

test('rest days never fail a multi-day quest', () => {
  let s = freshPet();
  s = levelUp(s, 3, T0);
  s = finishVq01(s, T0);
  s = must(Q.acceptStoryQuest(s, 'vq02', T0 + 3 * HOUR));
  s = sync(s, walkAt(T0 + 4 * HOUR, 3000, 'r1'), T0 + 6 * HOUR).state;
  // five quiet days, then one more walk
  const k = addDays(K0, 6);
  s = sync(s, walkAt(dayStart(k, TZ) + 9 * HOUR, 3000, 'r2'), dayStart(k, TZ) + 11 * HOUR).state;
  assert.equal(Q.questPhase(s, 'vq02'), 'paper_2_ready');
});

test('AT3 Quest 2 stays locked at level 2 and before Quest 1, even with plenty of steps', () => {
  let s = freshPet();
  s = levelUp(s, 2, T0);
  assert.equal(Q.accountLevel(s), 2);
  s = sync(s, walkAt(T0 + HOUR, 20000, 'lots'), T0 + 3 * HOUR).state;
  assert.equal(Q.questPhase(s, 'vq02'), 'locked');
  assert.equal(Q.acceptStoryQuest(s, 'vq02', T0 + 3 * HOUR).error, 'story_locked');
  let s3 = levelUp(s, 3, T0 + 3 * HOUR);
  assert.equal(Q.questPhase(s3, 'vq02'), 'locked', 'level alone is not enough');
  assert.ok(Q.lockReason(s3, 'vq02').needQuest === 'vq01');
  s3 = finishVq01(s3, T0 + 4 * HOUR);
  assert.equal(Q.questPhase(s3, 'vq02'), 'available');
  assert.equal(Q.questPhase(s3, 'vq03'), 'locked');
});

test('AT4 the same reward / hand-in twice is a no-op, never a second payout or a deduction', () => {
  let s = freshPet();
  s = finishVq01(s, T0);
  const inv = JSON.stringify(s.inventory);
  const pouch = JSON.stringify(s.story.questPouch);
  const bal = G.balance(s);
  const r = Q.storyHandIn(s, 'vq01', 'bram_sprig', T0 + 9 * HOUR);
  assert.equal(r.error, null);
  assert.ok(r.events.some((e) => e.type === 'story_already'));
  assert.equal(JSON.stringify(r.state.inventory), inv);
  assert.equal(JSON.stringify(r.state.story.questPouch), pouch);
  assert.equal(G.balance(r.state), bal);
  // a direct second grant is rejected too
  const s2 = structuredClone(s);
  assert.equal(Q.grantStoryRewardOnce(s2, 'vq01', T0), null);
  assert.equal(G.balance(s2), bal);
  // re-accepting a finished quest changes nothing
  assert.equal(Q.acceptStoryQuest(s, 'vq01', T0 + 10 * HOUR).state, s);
});

test('AT5 quest materials cannot be bought, equipped, placed, or dropped by chests', () => {
  let s = freshPet();
  s = G.grantCoins(s, 10000, T0).state;
  for (const id of Object.keys(Q.QUEST_MATERIALS)) {
    assert.equal(ITEMS[id], undefined, `${id} must not be a catalog item`);
    assert.ok(G.purchase(s, id, 'p-' + id, T0).error);
    assert.ok(G.equip(s, id, T0).error);
    assert.ok(G.placeDecoration(s, id, 'nest').error);
    assert.ok(!CONFIG.chest.items.includes(id));
  }
  // story cosmetics can't be bought either, and never come out of the weekly cosmetic roll
  for (const id of ['reward_firefly_hearth', 'reward_windtrail_mantle', 'reward_waystone_bloom']) {
    assert.equal(G.purchase(s, id, 'p-' + id, T0).error, 'not_for_sale');
    assert.equal(ITEMS[id].shop, null);
    assert.equal(ITEMS[id].price, null);
    assert.equal(ITEMS[id].tradable, false);
    assert.equal(ITEMS[id].sellable, false);
    assert.ok(!CONFIG.chest.items.includes(id));
  }
  // the weekly cosmetic roll: with every shop wearable owned, a story wearable is still never picked
  for (const id of Object.keys(ITEMS)) if (ITEMS[id].category === 'wearable' && isShopItem(id)) s = G.purchase(s, id, 'own-' + id, T0).state;
  const week = ['2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08'];
  for (const k of week) s = sync(s, [{ id: 'wk' + k, source: 'phone', start: dayStart(k, TZ) + 9 * HOUR, end: dayStart(k, TZ) + 10 * HOUR, count: 8000 }], dayStart('2026-10-08', TZ) + 12 * HOUR).state;
  const r = G.claimQuest(s, 'weekly_explorer', dayStart('2026-10-08', TZ) + 12 * HOUR);
  assert.equal(r.error, null);
  assert.equal(G.ownedQty(r.state, 'reward_windtrail_mantle'), 0);
});

test('AT6 the Market lists only shop items: no q_* or reward_* ids', () => {
  const shopIds = Object.keys(ITEMS).filter(isShopItem);
  assert.ok(shopIds.length >= 14);
  for (const id of shopIds) {
    assert.ok(!id.startsWith('q_') && !id.startsWith('reward_'), id);
  }
  for (const cat of ['wearables', 'habitats', 'care']) {
    const listed = Object.keys(ITEMS).filter((id) => ITEMS[id].shop === cat);
    assert.ok(listed.every((id) => !id.startsWith('reward_')));
  }
  assert.ok(Object.keys(ITEMS).filter((id) => ITEMS[id].featured).every(isShopItem));
});

test('AT7 the Windtrail Mantle equips on all three forms; the decor fits its Nest slots', () => {
  let s = freshPet();
  s.inventory.reward_windtrail_mantle = { quantity: 1, acquisitions: [] };
  s.inventory.reward_firefly_hearth = { quantity: 1, acquisitions: [] };
  s.inventory.reward_waystone_bloom = { quantity: 1, acquisitions: [] };
  for (const stage of [1, 2, 3]) {
    s.pet.stage = stage;
    const r = G.equip(s, 'reward_windtrail_mantle', T0);
    assert.equal(r.error, null, `stage ${stage}`);
    assert.equal(r.state.pet.equipped.back, 'reward_windtrail_mantle');
  }
  assert.equal(G.placeDecoration(s, 'reward_firefly_hearth', 'nest').error, null);
  assert.equal(G.placeDecoration(s, 'reward_firefly_hearth', 'left').error, 'no_anchor');
  for (const slot of ['left', 'right', 'back']) assert.equal(G.placeDecoration(s, 'reward_waystone_bloom', slot).error, null);
  assert.equal(G.placeDecoration(s, 'reward_waystone_bloom', 'nest').error, 'no_anchor');
});

test('AT8 memorial, a new pet and a new colourway keep the story and its rewards', () => {
  let s = freshPet();
  s = levelUp(s, 3, T0);
  s = finishVq01(s, T0);
  s = must(Q.acceptStoryQuest(s, 'vq02', T0 + 3 * HOUR));
  s = sync(s, walkAt(T0 + 4 * HOUR, 3000, 'm1'), T0 + 6 * HOUR).state;
  s = must(G.memorialize(s, T0 + 7 * HOUR));
  s = must(G.createPet(s, { name: 'Pebble', paletteId: 'ocean', requestId: 'req-2' }, T0 + 8 * HOUR));
  assert.equal(s.pet.paletteId, 'ocean');
  assert.equal(Q.questPhase(s, 'vq01'), 'completed');
  assert.equal(Q.questPhase(s, 'vq02'), 'accepted_two_days');
  assert.equal(Q.pouchQty(s, 'q_windprint_paper'), 1);
  assert.equal(G.ownedQty(s, 'reward_firefly_hearth'), 1);
  assert.equal(s.story.flags.lamp_lit, true);
  assert.ok(Q.accountLevel(s) >= 3, 'story gates never go backwards with a new pet');
  // the new pet keeps progressing the same quest
  const k = addDays(K0, 1);
  s = sync(s, walkAt(dayStart(k, TZ) + 9 * HOUR, 3000, 'm2'), dayStart(k, TZ) + 11 * HOUR).state;
  assert.equal(Q.questPhase(s, 'vq02'), 'paper_2_ready');
});

test('AT9 no step permission: the quest waits, nothing fails, progress resumes later', () => {
  let s = freshPet();
  s = must(Q.acceptStoryQuest(s, 'vq01', T0));
  s = sync(s, walkAt(T0 + 60000, 800, 'p1'), T0 + 2 * HOUR).state;
  s = must(G.setConnection(s, 'none', T0 + 2 * HOUR));
  const v = Q.questView(s, 'vq01', T0 + 30 * DAY);
  assert.equal(v.paused, true);
  assert.equal(v.phase, 'accepted_walk');
  assert.equal(v.walk.progress, 800);
  s = must(G.setConnection(s, 'demo', T0 + 31 * DAY));
  s = sync(s, walkAt(T0 + 31 * DAY, 1500, 'p2'), T0 + 31 * DAY + 2 * HOUR).state;
  assert.equal(Q.questPhase(s, 'vq01'), 'dew_ready');
});

test('AT10 relaunch: the save round-trips with phases, pouch, flags, title and after-dialogue', () => {
  let s = freshPet();
  s = levelUp(s, 6, T0);
  s = finishVq01(s, T0);
  s = must(Q.acceptStoryQuest(s, 'vq02', T0 + 3 * HOUR));
  for (let i = 0; i < 2; i++) {
    const k = addDays(K0, i);
    s = sync(s, walkAt(Math.max(dayStart(k, TZ) + 15 * HOUR, T0 + 4 * HOUR), 3000, 'two' + i), dayStart(k, TZ) + 20 * HOUR).state;
  }
  s = must(Q.storyHandIn(s, 'vq02', 'pip_papers', T0 + 2 * DAY));
  s = must(Q.storyHandIn(s, 'vq02', 'alder_letter', T0 + 2 * DAY));
  const tA = T0 + 2 * DAY + HOUR;
  s = must(Q.acceptStoryQuest(s, 'vq03', tA));
  for (let i = 2; i < 5; i++) {
    const k = addDays(K0, i);
    s = sync(s, walkAt(dayStart(k, TZ) + 15 * HOUR, 4000, 'three' + i), dayStart(k, TZ) + 20 * HOUR).state;
  }
  assert.equal(Q.pouchQty(s, 'q_echo_rubbing'), 3);
  assert.equal(Q.questPhase(s, 'vq03'), 'rubbings_ready');
  assert.equal(Q.storyHandIn(s, 'vq03', 'restore', T0 + 6 * DAY).error, 'story_not_ready');
  s = must(Q.storyHandIn(s, 'vq03', 'bram_rubbings', T0 + 6 * DAY));
  s = must(Q.storyHandIn(s, 'vq03', 'mira_essence', T0 + 6 * DAY));
  const bal = G.balance(s);
  s = must(Q.storyHandIn(s, 'vq03', 'restore', T0 + 6 * DAY));
  assert.equal(G.balance(s), bal + 250);
  assert.deepEqual(s.story.titleUnlocks, ['first_lightkeeper']);
  assert.equal(s.story.flags.waystone_restored, true);
  assert.deepEqual(s.story.questPouch, {});
  const back = G.migrate(JSON.parse(G.serialize(s)));
  assert.deepEqual(back.story, s.story);
  for (const id of ['vq01', 'vq02', 'vq03']) assert.equal(Q.questPhase(back, id), 'completed');
  assert.equal(Q.npcConversation(back, 'npc_mira', T0 + 7 * DAY).start, 'VQ03_MIR02');
  // after the Waystone wakes, Alder shows the map once (the Lumen Trails lead-in), then his usual goodbye
  assert.equal(Q.npcConversation(back, 'npc_alder', T0 + 7 * DAY).start, 'ALD_MAP00');
  const seen = must(Q.markNpcMet(back, 'waystone_map'));
  assert.equal(Q.npcConversation(seen, 'npc_alder', T0 + 7 * DAY).start, 'VQ03_ALD06');
  assert.equal(Q.npcConversation(back, 'waystone', T0 + 7 * DAY).start, 'WAY_DONE');
  assert.equal(Q.storyStatus(back, T0 + 7 * DAY).chapterDone, true);
});

test('old saves without a story object migrate cleanly', () => {
  const s = freshPet();
  delete s.story;
  const back = G.migrate(JSON.parse(JSON.stringify(s)));
  assert.equal(back.story.schemaVersion, 1);
  assert.equal(Q.questPhase(back, 'vq01'), 'available');
});

test('dialogue opens on the right line for each state', () => {
  let s = freshPet();
  assert.equal(Q.npcConversation(s, 'npc_mira', T0).start, 'VQ01_M00');
  s = must(Q.markNpcMet(s, 'npc_mira'));
  assert.equal(Q.npcConversation(s, 'npc_mira', T0).start, 'VQ01_M01');
  assert.equal(Q.npcConversation(s, 'npc_bram', T0).start, 'VQ01_B00');
  assert.equal(Q.npcConversation(s, 'npc_pip', T0).start, 'VQ02_PIP00');
  assert.equal(Q.npcConversation(s, 'waystone', T0).start, 'WAY_LORE');
  s = must(Q.acceptStoryQuest(s, 'vq01', T0));
  s = sync(s, walkAt(T0 + 60000, 700, 'dl'), T0 + HOUR).state;
  assert.equal(Q.npcConversation(s, 'npc_mira', T0 + HOUR).start, 'VQ01_M04');
  assert.match(Q.lineText(s, 'VQ01_M04', T0 + HOUR), /700\/2,000/);
  // every line referenced by a conversation exists
  for (const npc of ['npc_mira', 'npc_bram', 'npc_pip', 'npc_alder', 'waystone']) {
    const c = Q.npcConversation(s, npc, T0 + HOUR);
    for (const n of Object.values(c.nodes)) {
      assert.ok(Q.LINES[n.id], n.id);
      for (const ch of n.choices) if (ch.next || ch.then) assert.ok(c.nodes[ch.next || ch.then], `${n.id} -> ${ch.next || ch.then}`);
    }
  }
});

test('manual entries count for story walks (configurable)', () => {
  let s = freshPet();
  s = must(G.setConnection(s, 'manual', T0));
  s = must(Q.acceptStoryQuest(s, 'vq01', T0));
  s = sync(s, [{ id: 'man1', source: 'manual', start: T0 + 60000, end: T0 + 120000, count: 2100, manual: true }], T0 + HOUR).state;
  assert.equal(Q.questPhase(s, 'vq01'), 'dew_ready');
});
