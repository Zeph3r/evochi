// Lumen Trails: daily discoveries, the Trail Guild, encounter quests, the encounter engine and companions.
import test from 'node:test';
import assert from 'node:assert/strict';

import * as G from '../src/game/state.js';
import * as Q from '../src/game/story.js';
import * as H from '../src/game/home.js';
import * as TR from '../src/game/trails.js';
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
  assert.equal(r.error, null, r.error + (r.message ? ': ' + r.message : ''));
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
function finishVq01(s, now) {
  s = must(Q.acceptStoryQuest(s, 'vq01', now));
  s = G.syncSteps(s, walkAt(now + MIN, 2500, 'vq01'), now + 2 * HOUR).state;
  s = must(Q.storyHandIn(s, 'vq01', 'mira_dew', now + 2 * HOUR));
  return must(Q.storyHandIn(s, 'vq01', 'bram_sprig', now + 2 * HOUR));
}
/** Complete `n` discoveries on consecutive days (each: begin, walk, inspect). */
function doDiscoveries(s, n, from) {
  let now = from;
  for (let i = 0; i < n; i++) {
    const d = TR.trailsStatus(s, now).discoveries.find((x) => x.phase === 'offered');
    assert.ok(d, 'a discovery is posted');
    s = must(TR.beginDiscovery(s, d.id, now));
    s = G.syncSteps(s, walkAt(now + MIN, d.target + 200, `disc${i}`), now + 2 * HOUR).state;
    s = must(TR.inspectDiscovery(s, d.id, now + 2 * HOUR));
    now += 3 * HOUR;
  }
  return [s, now];
}
/** Play an encounter to the end with Lumen Glow, resting when out of Energy. */
function playOut(s, now, { item = null } = {}) {
  let turns = 0;
  while (!TR.encounterView(s, now).done) {
    const v = TR.encounterView(s, now);
    const comp = v.actions.find((a) => a.id === 'petal_hush' && a.can);
    if (item && G.ownedQty(s, item) > 0 && turns === 0) s = must(TR.encounterAct(s, 'item', item, now));
    else if (comp) s = must(TR.encounterAct(s, 'petal_hush', null, now));
    else if (v.energy >= 24) s = must(TR.encounterAct(s, 'lumen_glow', null, now));
    else s = must(TR.encounterAct(s, 'soothe', null, now));
    turns++;
    assert.ok(turns < 80, 'encounter runaway');
  }
  return [s, turns];
}

test('catalog: shards and tonics are never sold; the relic is a story decoration', () => {
  assert.equal(isShopItem('lumen_shard'), false);
  assert.equal(isShopItem('lantern_tonic'), false);
  assert.equal(ITEMS.ancient_relic.acquisition, 'story');
  assert.equal(ITEMS.ancient_relic.decor, 'side');
});

test('old saves get a trails object; the day board is three authored discoveries, stable per day', () => {
  const s = freshPet();
  const old = JSON.parse(G.serialize(s));
  delete old.trails;
  const back = G.migrate(old);
  assert.ok(back.trails && back.trails.stats);
  const a = TR.pickDiscoveries(s, K0);
  const b = TR.pickDiscoveries(s, K0);
  assert.deepEqual(a, b);
  assert.equal(a.length, 3);
  assert.equal(new Set(a.map((id) => TR.DISCOVERIES[id].place)).size, 3, 'three different places');
  // nothing gated behind the cottage or the ruins before they exist
  for (const id of a) assert.equal(TR.DISCOVERIES[id].needs, undefined);
  // a different day, a different set (usually), never the same place twice
  const c = TR.pickDiscoveries(s, addDays(K0, 1));
  assert.equal(c.length, 3);
});

test('a discovery: begin, walk (steps after beginning only), inspect at its place, rewards once', () => {
  let s = freshPet();
  const now = T0 + HOUR;
  // steps before beginning never count
  s = G.syncSteps(s, walkAt(T0, 4000, 'early'), now).state;
  const d0 = TR.trailsStatus(s, now).discoveries[0];
  assert.equal(d0.phase, 'offered');
  s = must(TR.beginDiscovery(s, d0.id, now));
  assert.equal(TR.discoveryView(s, d0.id, now).phase, 'walking');
  assert.equal(TR.discoveryView(s, d0.id, now).walked, 0);
  assert.equal(TR.inspectDiscovery(s, d0.id, now).error, 'discovery_not_ready');
  const r = G.syncSteps(s, walkAt(now + MIN, d0.target + 100, 'd0'), now + 2 * HOUR);
  s = r.state;
  assert.ok(r.events.some((e) => e.type === 'discovery_ready' && e.id === d0.id));
  const v = TR.discoveryView(s, d0.id, now + 2 * HOUR);
  assert.equal(v.phase, 'ready');
  assert.deepEqual(TR.cluesAt(s, d0.place, now + 2 * HOUR).map((x) => x.id), [d0.id]);
  const coins = G.balance(s);
  const r2 = TR.inspectDiscovery(s, d0.id, now + 2 * HOUR);
  s = must(r2);
  assert.ok(r2.events.some((e) => e.type === 'discovery_found'));
  assert.equal(G.balance(s), coins + d0.reward.coins);
  for (const [id, n] of Object.entries(d0.reward.items)) assert.equal(G.ownedQty(s, id), n);
  assert.equal(s.trails.guildXp, d0.reward.guildXp);
  assert.equal(TR.trailsStatus(s, now + 2 * HOUR).foundToday, 1);
  // again: nothing more
  const r3 = TR.inspectDiscovery(s, d0.id, now + 3 * HOUR);
  assert.equal(r3.state, s);
  assert.equal(G.balance(r3.state), coins + d0.reward.coins);
  // the board resets tomorrow
  const tomorrow = now + DAY;
  assert.equal(TR.trailsStatus(s, tomorrow).foundToday, 0);
  assert.equal(TR.trailsStatus(s, tomorrow).discoveries.length, 3);
});

test('guild ranks climb with discovery XP', () => {
  assert.equal(TR.guildRank(0).name, 'Wanderer');
  assert.equal(TR.guildRank(45).name, 'Trail Friend');
  assert.equal(TR.guildRank(45).next.name, 'Pathfinder');
  assert.equal(TR.guildRank(9999).next, null);
});

test('The Forest Guardian: needs two discoveries, a walk, then an encounter that befriends Petalune', () => {
  let s = freshPet();
  s = levelUp(s, 3, T0);
  let now = T0 + HOUR;
  s = finishVq01(s, now);
  now += 3 * HOUR;
  assert.equal(Q.questPhase(s, 'eq01'), 'locked');
  assert.equal(Q.lockReason(s, 'eq01').needDiscoveries, 2);
  // Pip offers Chapter 1's second quest first; once that's underway he mentions the Guild's rule
  assert.equal(Q.npcConversation(s, 'npc_pip', now).start, 'VQ02_PIP00');
  const onWalk = must(Q.acceptStoryQuest(s, 'vq02', now));
  assert.equal(Q.npcConversation(onWalk, 'npc_pip', now).start, 'EQ01_LOCK');
  [s, now] = doDiscoveries(s, 2, now);
  assert.equal(Q.questPhase(s, 'eq01'), 'available');
  assert.equal(Q.npcConversation(s, 'npc_pip', now).start, 'VQ02_PIP00'); // the greeting, then straight into the Guild job
  assert.equal(Q.npcConversation(s, 'npc_pip', now).nodes.VQ02_PIP00.choices[0].next, 'EQ01_P00');
  s = must(Q.acceptStoryQuest(s, 'eq01', now));
  assert.equal(TR.startEncounter(s, 'eq01', now).error, 'story_not_ready');
  s = G.syncSteps(s, walkAt(now + MIN, 1600, 'eq01'), now + 2 * HOUR).state;
  now += 2 * HOUR;
  assert.equal(Q.questPhase(s, 'eq01'), 'ruins_ready');
  assert.equal(Q.pouchQty(s, 'q_mossy_clue'), 1);
  const n = Q.nextStep(s, 'eq01');
  assert.equal(n.kind, 'encounter');
  assert.equal(n.place, 'ruins');
  assert.equal(n.encounter, 'petalune');
  assert.ok(Q.storyStatus(s, now).encounters.some((v) => v.id === 'eq01'));
  // the optional tart is never required
  assert.equal(Q.questView(s, 'eq01', now).objectives.find((o) => o.id === 'tart').optional, true);
  s = must(TR.startEncounter(s, 'eq01', now));
  let v = TR.encounterView(s, now);
  assert.equal(v.goal, 'befriend');
  assert.equal(v.meter, 0);
  assert.equal(v.stateKey, 'wary');
  assert.equal(v.energy, 100);
  // the same attempt always plays the same way
  const a1 = TR.encounterAct(s, 'lumen_glow', null, now).state.trails.encounter;
  const a2 = TR.encounterAct(s, 'lumen_glow', null, now).state.trails.encounter;
  assert.deepEqual(a1.log, a2.log);
  assert.equal(a1.energy, 76);
  // an item you don't have is refused; no energy means no glow
  assert.equal(TR.encounterAct(s, 'item', 'sunberry_tart', now).error, 'not_owned');
  let turns;
  [s, turns] = playOut(s, now);
  v = TR.encounterView(s, now);
  assert.equal(v.done, 'success');
  assert.equal(v.stateKey, 'happy');
  assert.ok(turns > 3 && turns < 40, `took ${turns} turns`);
  assert.equal(s.trails.companions.petalune.since, now);
  const coins = G.balance(s);
  const r = TR.completeEncounter(s, now);
  s = must(r);
  assert.equal(s.trails.encounter, null);
  assert.equal(Q.questPhase(s, 'eq01'), 'completed');
  assert.equal(Q.pouchQty(s, 'q_mossy_clue'), 0);
  assert.equal(G.balance(s), coins + 150);
  assert.ok(G.ownedQty(s, 'lumen_shard') >= 1);
  assert.ok(s.story.titleUnlocks.includes('friend_of_petalune'));
  assert.equal(s.story.flags.petalune_befriended, true);
  assert.ok(r.events.some((e) => e.type === 'companion_joined'));
  assert.equal(TR.trailsStatus(s, now).companions[0].name, 'Petalune');
  // Pip thanks you once, then has a normal line
  assert.equal(Q.npcConversation(s, 'npc_pip', now).start, 'EQ01_P05');
  s = must(Q.markNpcMet(s, 'eq01_thanks'));
  assert.notEqual(Q.npcConversation(s, 'npc_pip', now).start, 'EQ01_P05');
  // the ruins now post discoveries
  assert.ok(TR.DISCOVERY_ORDER.some((id) => TR.DISCOVERIES[id].place === 'ruins'));
});

test('a liked treat calms faster; retreating returns the items used', () => {
  let s = freshPet();
  s = levelUp(s, 3, T0);
  let now = T0 + HOUR;
  s = finishVq01(s, now);
  now += 3 * HOUR;
  [s, now] = doDiscoveries(s, 2, now);
  s = must(Q.acceptStoryQuest(s, 'eq01', now));
  s = G.syncSteps(s, walkAt(now + MIN, 1600, 'eq01'), now + 2 * HOUR).state;
  now += 2 * HOUR;
  s = give(s, 'sunberry_tart', 1);
  s = must(TR.startEncounter(s, 'eq01', now));
  assert.equal(TR.itemEffect('sunberry_tart', 'befriend', 'petalune').amount, 39);
  assert.equal(TR.itemEffect('sunberry_tart', 'befriend', 'petalune').liked, true);
  const r = TR.encounterAct(s, 'item', 'sunberry_tart', now);
  const after = must(r);
  assert.equal(G.ownedQty(after, 'sunberry_tart'), 0);
  assert.ok(after.trails.encounter.meter >= 39, 'tart counted');
  // retreat: the tart comes back, the quest stays ready
  const back = must(TR.encounterAct(after, 'retreat', null, now));
  assert.equal(back.trails.encounter, null);
  assert.equal(G.ownedQty(back, 'sunberry_tart'), 1);
  assert.equal(Q.questPhase(back, 'eq01'), 'ruins_ready');
  assert.equal(back.trails.stats.retreats, 1);
  // a second attempt reseeds
  const again = must(TR.startEncounter(back, 'eq01', now + HOUR));
  assert.notEqual(again.trails.encounter.seed, after.trails.encounter.seed);
});

test('Tangled Lumen: a Hollow is restored (Instability to 0); Glowleaf is required and Light hits harder', () => {
  let s = freshPet();
  s = levelUp(s, 4, T0);
  let now = T0 + HOUR;
  s = finishVq01(s, now);
  now += 3 * HOUR;
  [s, now] = doDiscoveries(s, 2, now);
  s = must(Q.acceptStoryQuest(s, 'eq01', now));
  s = G.syncSteps(s, walkAt(now + MIN, 1600, 'eq01'), now + 2 * HOUR).state;
  now += 2 * HOUR;
  s = must(TR.startEncounter(s, 'eq01', now));
  [s] = playOut(s, now);
  s = must(TR.completeEncounter(s, now));
  // hq01 (the cottage) is also a prerequisite
  assert.equal(Q.questPhase(s, 'eq02'), 'locked');
  s = structuredClone(s);
  s.story.questStates.hq01 = { phase: 'completed', acceptedAt: now, completedAt: now, resolvedSteps: 3000 };
  s.story.flags.cottage_restored = true;
  assert.equal(Q.questPhase(s, 'eq02'), 'available');
  assert.equal(Q.npcConversation(s, 'npc_mira', now).start, 'EQ02_M00');
  s = must(Q.acceptStoryQuest(s, 'eq02', now));
  s = G.syncSteps(s, walkAt(now + MIN, 2100, 'eq02'), now + 2 * HOUR).state;
  now += 2 * HOUR;
  assert.equal(Q.nextStep(s, 'eq02').kind, 'gather');
  assert.equal(TR.startEncounter(s, 'eq02', now).error, 'story_missing_items');
  s = give(s, 'glowleaf', 2);
  assert.equal(Q.nextStep(s, 'eq02').kind, 'encounter');
  s = must(TR.startEncounter(s, 'eq02', now));
  let v = TR.encounterView(s, now);
  assert.equal(v.goal, 'restore');
  assert.equal(v.meter, 100);
  assert.equal(v.stateKey, 'hollow');
  assert.equal(v.actions.find((a) => a.id === 'lumen_glow').power, 21, 'Light x1.3 against the Hollow');
  assert.ok(v.actions.some((a) => a.id === 'petal_hush' && a.can), 'Petalune helps');
  const one = TR.encounterAct(s, 'lumen_glow', null, now).state.trails.encounter;
  assert.ok(one.meter <= 100 - 21 + 9, 'instability fell');
  let turns;
  [s, turns] = playOut(s, now);
  v = TR.encounterView(s, now);
  assert.equal(v.done, 'success');
  assert.equal(v.stateKey, 'restored');
  assert.equal(s.trails.encounter.companionUsed, true);
  s = must(TR.completeEncounter(s, now));
  assert.equal(G.ownedQty(s, 'glowleaf'), 0, 'the Glowleaf poultice was used');
  assert.equal(s.story.flags.sprout_restored, true);
  assert.equal(s.trails.restored.hollow_sprout, now);
  assert.ok(G.ownedQty(s, 'lumen_shard') >= 3);
  // the Lantern Tonic recipe only appears once the sprout is restored
  const before = structuredClone(s);
  before.story.flags.sprout_restored = false;
  before.story.flags.apothecary_unlocked = true;
  s.story.flags.apothecary_unlocked = true;
  const setAlch = (st) => {
    st = structuredClone(st);
    H.ensureHome(st).skills.alchemy = 1000;
    return st;
  };
  assert.equal(H.recipeView(setAlch(before), 'lantern_tonic').known, false);
  assert.equal(H.recipeView(setAlch(before), 'lantern_tonic').needsStory, true);
  assert.equal(H.recipeView(setAlch(s), 'lantern_tonic').known, true);
  let s2 = give(give(setAlch(s), 'glowleaf', 1), 'sunberry', 2);
  s2 = must(H.craft(s2, 'lantern_tonic', 'good', now));
  assert.equal(G.ownedQty(s2, 'lantern_tonic'), 1);
  assert.equal(G.ownedQty(s2, 'lumen_shard'), G.ownedQty(s, 'lumen_shard') - 1);
});

test('The Forgotten Sentinel: winning with every Lantern Tonic spent still finishes the quest', () => {
  let s = freshPet();
  s = levelUp(s, 6, T0);
  const now = T0 + HOUR;
  s = structuredClone(s);
  for (const id of ['vq01', 'vq02', 'vq03', 'hq01', 'eq01', 'eq02']) {
    s.story.questStates[id] = { phase: 'completed', acceptedAt: now - HOUR, completedAt: now, resolvedSteps: 1000, seenCompletion: true };
    s.story.claimedRewards.push(id);
  }
  Object.assign(s.story.flags, { lamp_lit: true, waystone_revealed: true, waystone_restored: true, cottage_restored: true, petalune_befriended: true, sprout_restored: true });
  s = must(Q.markNpcMet(s, 'waystone_map'));
  s = must(Q.acceptStoryQuest(s, 'eq03', now));
  s = G.syncSteps(s, walkAt(now + MIN, 3100, 'eq03'), now + 2 * HOUR).state;
  s = give(s, 'lantern_tonic', 1);
  s = must(TR.startEncounter(s, 'eq03', now + 2 * HOUR));
  // offer the only tonic in the fight
  [s] = playOut(s, now + 2 * HOUR, { item: 'lantern_tonic' });
  assert.equal(TR.encounterView(s, now).done, 'success');
  assert.equal(G.ownedQty(s, 'lantern_tonic'), 0);
  // the gate accepts the tonic you already gave the Sentinel: no "you still need 1 more Lantern Tonic"
  s = must(TR.completeEncounter(s, now + 3 * HOUR));
  assert.equal(Q.questPhase(s, 'eq03'), 'completed');
  assert.equal(TR.encounterView(s, now), null);
  assert.equal(G.ownedQty(s, 'lantern_tonic'), 0);
  // and the Bag still pays first when it can: two tonics, one offered, one taken at the gate (the test below)
});

test('The Forgotten Sentinel: after the Waystone, a long restore with a second phase; the relic and title', () => {
  let s = freshPet();
  s = levelUp(s, 6, T0);
  const now = T0 + HOUR;
  s = structuredClone(s);
  // shortcut the prerequisites
  for (const id of ['vq01', 'vq02', 'vq03', 'hq01', 'eq01', 'eq02']) {
    s.story.questStates[id] = { phase: 'completed', acceptedAt: now - HOUR, completedAt: now, resolvedSteps: 1000, seenCompletion: true };
    s.story.claimedRewards.push(id);
  }
  Object.assign(s.story.flags, { lamp_lit: true, waystone_revealed: true, waystone_restored: true, cottage_restored: true, petalune_befriended: true, sprout_restored: true });
  s.trails.companions.petalune = { since: now - DAY, encounters: 0 };
  // Alder shows the map first, then offers the quest
  assert.equal(Q.npcConversation(s, 'npc_alder', now).start, 'ALD_MAP00');
  s = must(Q.markNpcMet(s, 'waystone_map'));
  assert.equal(Q.questPhase(s, 'eq03'), 'available');
  assert.equal(Q.npcConversation(s, 'npc_alder', now).start, 'EQ03_A00');
  s = must(Q.acceptStoryQuest(s, 'eq03', now));
  s = G.syncSteps(s, walkAt(now + MIN, 3100, 'eq03'), now + 2 * HOUR).state;
  assert.equal(Q.questPhase(s, 'eq03'), 'gate_ready');
  assert.equal(Q.nextStep(s, 'eq03').kind, 'gather'); // the Lantern Tonic
  s = give(s, 'lantern_tonic', 2);
  assert.equal(Q.nextStep(s, 'eq03').place, 'gate');
  s = must(TR.startEncounter(s, 'eq03', now + 2 * HOUR));
  let v = TR.encounterView(s, now);
  assert.equal(v.boss, true);
  assert.equal(v.max, 200);
  assert.equal(v.phase2, false);
  assert.equal(TR.itemEffect('lantern_tonic', 'restore', 'sentinel').amount, 66);
  let turns;
  [s, turns] = playOut(s, now + 2 * HOUR, { item: 'lantern_tonic' });
  v = TR.encounterView(s, now);
  assert.equal(v.done, 'success');
  assert.equal(v.stateKey, 'restored');
  assert.ok(turns >= 4, `a boss takes a while (${turns})`);
  const coins = G.balance(s);
  s = must(TR.completeEncounter(s, now + 3 * HOUR));
  assert.equal(Q.questPhase(s, 'eq03'), 'completed');
  assert.equal(G.ownedQty(s, 'lantern_tonic'), 0, 'one tonic used in the encounter, one at the gate');
  assert.equal(G.ownedQty(s, 'ancient_relic'), 1);
  assert.equal(G.balance(s), coins + 300);
  assert.ok(s.story.titleUnlocks.includes('trailwarden'));
  assert.equal(s.story.flags.sentinel_restored, true);
  assert.equal(Q.npcConversation(s, 'npc_alder', now + 3 * HOUR).start, 'EQ03_A04');
  // the relic can be placed in the nest like any side decoration
  s = must(G.placeDecoration(s, 'ancient_relic', 'left'));
  assert.equal(s.nest.placements.left, 'ancient_relic');
});

test('story lines stay well-formed with the new quests', () => {
  const s = freshPet();
  for (const id of Object.keys(Q.LINES)) assert.equal(typeof Q.lineText(s, id, T0, 'Ember'), 'string', id);
  for (const npc of ['npc_pip', 'npc_mira', 'npc_alder', 'npc_bram']) {
    const c = Q.npcConversation(s, npc, T0);
    assert.ok(Q.LINES[c.start], `${npc} opens with a real line (${c.start})`);
  }
});
