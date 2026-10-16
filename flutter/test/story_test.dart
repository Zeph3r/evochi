// Village Tales, Chapter 1: the ten acceptance tests from the Quest Bible (§9) plus step-rule checks.
// Mirrors web/test/story.test.mjs so both clients are held to the same story rules.

import 'dart:convert';

import 'package:evochi/app/constants.dart';
import 'package:evochi/core/models/catalog.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/story/story.dart' as q;
import 'package:flutter_test/flutter_test.dart';

const tzName = 'America/New_York';
final t0 = DateTime.utc(2026, 10, 5, 14).millisecondsSinceEpoch; // Mon 5 Oct 2026, 10:00 New York
const k0 = '2026-10-05';

GameState freshPet([int? now]) {
  final n = now ?? t0;
  var s = GameState.fresh(n, tzName);
  s = g.startGuest(s, n, tzName).state;
  s = g.setConnection(s, 'demo', n).state;
  s = must(g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: n));
  return s;
}

/// A walk of [steps] inside [from, from + 1h].
List<StepSample> walkAt(int from, int steps, String tag) => [StepSample(id: 'w_$tag', source: 'phone', start: from, end: from + hourMs, count: steps)];

g.ActionResult sync(GameState s, List<StepSample> samples, int now) {
  final r = g.syncSteps(s, samples, now);
  expect(r.error, isNull);
  return r;
}

GameState must(g.ActionResult r) {
  expect(r.error, isNull, reason: r.error);
  return r.state;
}

GameState backdatePet(GameState s, String k) {
  final j = (jsonDecode(s.serialize()) as Map).cast<String, dynamic>();
  final pet = (j['pet'] as Map).cast<String, dynamic>();
  if (k.compareTo(pet['createdDay'] as String) < 0) pet['createdDay'] = k;
  j['pet'] = pet;
  return GameState.fromJson(j);
}

/// Give the pet enough XP for [level] by backfilling past days (before any quest is accepted).
GameState levelUp(GameState s, int level, int now) {
  var i = 1;
  while (q.accountLevel(s) < level) {
    final k = addDays(k0, -i);
    s = backdatePet(s, k);
    final st = dayStart(k, tzName) + 9 * hourMs;
    s = sync(s, [StepSample(id: 'lv_$k', source: 'phone', start: st, end: st + hourMs, count: 9000)], now).state;
    i++;
    expect(i < 400, isTrue, reason: 'levelling runaway');
  }
  return s;
}

GameState finishVq01(GameState s, int now) {
  s = must(q.acceptStoryQuest(s, 'vq01', now));
  s = sync(s, walkAt(now + 60000, 2500, 'vq01_$now'), now + 2 * hourMs).state;
  s = must(q.storyHandIn(s, 'vq01', 'mira_dew', now + 2 * hourMs));
  s = must(q.storyHandIn(s, 'vq01', 'bram_sprig', now + 2 * hourMs));
  return s;
}

int balance(GameState s) => g.balanceOf(s);

void main() {
  setUpAll(ensureTimeZones);

  test('VQ01 full flow: walk after accepting, Mira, Bram, Firefly Hearth + 75 coins once', () {
    var s = freshPet();
    expect(q.questPhase(s, 'vq01'), 'available');
    s = must(q.acceptStoryQuest(s, 'vq01', t0));
    expect(s.story.questStates['vq01']!.resolvedSteps, 2000);
    var r = sync(s, walkAt(t0 + 60000, 1200, 'a'), t0 + 2 * hourMs);
    s = r.state;
    expect(q.questPhase(s, 'vq01'), 'accepted_walk');
    expect(q.questView(s, 'vq01', t0 + 2 * hourMs).walk.progress, 1200);
    r = sync(s, walkAt(t0 + 3 * hourMs, 900, 'b'), t0 + 4 * hourMs);
    s = r.state;
    expect(q.questPhase(s, 'vq01'), 'dew_ready');
    expect(q.pouchQty(s, 'q_dawn_dew_vial'), 1);
    expect(r.events.any((e) => e.type == 'story_item' && e.data['itemId'] == 'q_dawn_dew_vial'), isTrue);
    // Bram can't be skipped to
    expect(q.storyHandIn(s, 'vq01', 'bram_sprig', t0 + 4 * hourMs).error, 'story_not_ready');
    s = must(q.storyHandIn(s, 'vq01', 'mira_dew', t0 + 4 * hourMs));
    expect(q.pouchQty(s, 'q_dawn_dew_vial'), 0);
    expect(q.pouchQty(s, 'q_lumenbud_sprig'), 1);
    final before = balance(s);
    r = q.storyHandIn(s, 'vq01', 'bram_sprig', t0 + 4 * hourMs);
    s = must(r);
    expect(q.questPhase(s, 'vq01'), 'completed');
    expect(balance(s), before + 75);
    expect(g.ownedQty(s, 'reward_firefly_hearth'), 1);
    expect(s.story.flags['lamp_lit'], isTrue);
    expect(r.events.any((e) => e.type == 'story_completed'), isTrue);
  });

  test('AT1 replaying the same step batch five times adds no progress, materials or coins', () {
    var s = freshPet();
    s = must(q.acceptStoryQuest(s, 'vq01', t0));
    final batch = walkAt(t0 + 60000, 900, 'replay');
    for (var i = 0; i < 5; i++) {
      s = sync(s, batch, t0 + 2 * hourMs + i).state;
    }
    expect(q.questView(s, 'vq01', t0 + 3 * hourMs).walk.progress, 900);
    expect(q.questPhase(s, 'vq01'), 'accepted_walk');
    final big = walkAt(t0 + 2 * hourMs, 3000, 'big');
    for (var i = 0; i < 5; i++) {
      s = sync(s, big, t0 + 4 * hourMs + i).state;
    }
    expect(q.pouchQty(s, 'q_dawn_dew_vial'), 1, reason: 'one vial, however many replays');
    s = must(q.storyHandIn(s, 'vq01', 'mira_dew', t0 + 5 * hourMs));
    s = must(q.storyHandIn(s, 'vq01', 'bram_sprig', t0 + 5 * hourMs));
    final bal = balance(s);
    for (var i = 0; i < 5; i++) {
      s = sync(s, big, t0 + 6 * hourMs + i).state;
      s = must(q.storyHandIn(s, 'vq01', 'bram_sprig', t0 + 6 * hourMs + i));
    }
    expect(balance(s), bal);
    expect(g.ownedQty(s, 'reward_firefly_hearth'), 1);
    expect(s.txns.where((t) => t.id == 'story:vq01').length, 1);
  });

  test('no retroactive credit: steps before acceptance never count', () {
    var s = freshPet();
    s = sync(s, walkAt(t0 - 2 * hourMs, 5000, 'before'), t0 - hourMs).state;
    s = must(q.acceptStoryQuest(s, 'vq01', t0));
    s = sync(s, const [], t0 + hourMs).state;
    expect(q.questView(s, 'vq01', t0 + hourMs).walk.progress, 0);
    // a late-delivered sample from before acceptance changes nothing either
    s = sync(s, walkAt(t0 - 3 * hourMs, 4000, 'late'), t0 + hourMs).state;
    expect(q.questPhase(s, 'vq01'), 'accepted_walk');
    // a sample straddling acceptance counts only its share after acceptance
    s = sync(s, [StepSample(id: 'straddle', source: 'phone', start: t0 - 30 * 60000, end: t0 + 30 * 60000, count: 1000)], t0 + 2 * hourMs).state;
    expect(q.questView(s, 'vq01', t0 + 2 * hourMs).walk.progress, 500);
  });

  test('target is min(nominal, personal goal) and frozen at acceptance', () {
    var s = freshPet();
    s = must(g.setGoal(s, 1500, t0));
    s = must(q.acceptStoryQuest(s, 'vq01', t0));
    expect(s.story.questStates['vq01']!.resolvedSteps, 1500);
    s = must(g.setGoal(s, 1000, t0 + 1000));
    expect(q.questView(s, 'vq01', t0 + 2000).resolved, 1500, reason: 'a lower goal later cannot lower the quest');
    s = sync(s, walkAt(t0 + 60000, 1200, 'x'), t0 + 2 * hourMs).state;
    expect(q.questPhase(s, 'vq01'), 'accepted_walk');
  });

  test('AT2 5,000 steps on one day grant only one Windprint Paper; a second day grants the second', () {
    var s = freshPet();
    s = levelUp(s, 3, t0);
    s = finishVq01(s, t0);
    final t1 = t0 + 3 * hourMs;
    s = must(q.acceptStoryQuest(s, 'vq02', t1));
    expect(s.story.questStates['vq02']!.resolvedSteps, 2500);
    s = sync(s, walkAt(t1 + 60000, 5000, 'd1a'), t1 + 2 * hourMs).state;
    s = sync(s, walkAt(t1 + 3 * hourMs, 5000, 'd1b'), t1 + 5 * hourMs).state;
    expect(q.pouchQty(s, 'q_windprint_paper'), 1);
    expect(q.questView(s, 'vq02', t1 + 5 * hourMs).walk.qualified, 1);
    // next local day
    final d2 = dayStart(addDays(k0, 1), tzName) + 9 * hourMs;
    s = sync(s, walkAt(d2, 2600, 'd2'), d2 + 2 * hourMs).state;
    expect(q.pouchQty(s, 'q_windprint_paper'), 2);
    expect(q.questPhase(s, 'vq02'), 'paper_2_ready');
    // a third day can't mint a third paper
    final k2 = addDays(k0, 2);
    s = sync(s, walkAt(dayStart(k2, tzName) + 9 * hourMs, 9000, 'd3'), dayStart(k2, tzName) + 12 * hourMs).state;
    expect(q.pouchQty(s, 'q_windprint_paper'), 2);
    s = must(q.storyHandIn(s, 'vq02', 'pip_papers', dayStart(k2, tzName) + 13 * hourMs));
    s = must(q.storyHandIn(s, 'vq02', 'alder_letter', dayStart(k2, tzName) + 13 * hourMs));
    expect(g.ownedQty(s, 'reward_windtrail_mantle'), 1);
    expect(s.story.flags['waystone_revealed'], isTrue);
  });

  test('rest days never fail a multi-day quest', () {
    var s = freshPet();
    s = levelUp(s, 3, t0);
    s = finishVq01(s, t0);
    s = must(q.acceptStoryQuest(s, 'vq02', t0 + 3 * hourMs));
    s = sync(s, walkAt(t0 + 4 * hourMs, 3000, 'r1'), t0 + 6 * hourMs).state;
    // five quiet days, then one more walk
    final k = addDays(k0, 6);
    s = sync(s, walkAt(dayStart(k, tzName) + 9 * hourMs, 3000, 'r2'), dayStart(k, tzName) + 11 * hourMs).state;
    expect(q.questPhase(s, 'vq02'), 'paper_2_ready');
  });

  test('AT3 Quest 2 stays locked at level 2 and before Quest 1, even with plenty of steps', () {
    var s = freshPet();
    s = levelUp(s, 2, t0);
    expect(q.accountLevel(s), 2);
    s = sync(s, walkAt(t0 + hourMs, 20000, 'lots'), t0 + 3 * hourMs).state;
    expect(q.questPhase(s, 'vq02'), 'locked');
    expect(q.acceptStoryQuest(s, 'vq02', t0 + 3 * hourMs).error, 'story_locked');
    var s3 = levelUp(s, 3, t0 + 3 * hourMs);
    expect(q.questPhase(s3, 'vq02'), 'locked', reason: 'level alone is not enough');
    expect(q.lockReason(s3, 'vq02')!.needQuest, 'vq01');
    s3 = finishVq01(s3, t0 + 4 * hourMs);
    expect(q.questPhase(s3, 'vq02'), 'available');
    expect(q.questPhase(s3, 'vq03'), 'locked');
  });

  test('AT4 the same reward / hand-in twice is a no-op, never a second payout or a deduction', () {
    var s = freshPet();
    s = finishVq01(s, t0);
    final inv = jsonEncode(s.inventory.map((k, v) => MapEntry(k, v.toJson())));
    final pouch = jsonEncode(s.story.questPouch);
    final bal = balance(s);
    final r = q.storyHandIn(s, 'vq01', 'bram_sprig', t0 + 9 * hourMs);
    expect(r.error, isNull);
    expect(r.events.any((e) => e.type == 'story_already'), isTrue);
    expect(jsonEncode(r.state.inventory.map((k, v) => MapEntry(k, v.toJson()))), inv);
    expect(jsonEncode(r.state.story.questPouch), pouch);
    expect(balance(r.state), bal);
    // a direct second grant is rejected too
    final s2 = s.copy();
    expect(q.grantStoryRewardOnce(s2, 'vq01', t0), isNull);
    expect(balance(s2), bal);
    // re-accepting a finished quest changes nothing
    expect(identical(q.acceptStoryQuest(s, 'vq01', t0 + 10 * hourMs).state, s), isTrue);
  });

  test('AT5 quest materials cannot be bought, equipped, placed, or dropped by chests', () {
    var s = freshPet();
    s = g.grantCoins(s, 10000, t0).state;
    for (final id in q.questMaterials.keys) {
      expect(catalog[id], isNull, reason: '$id must not be a catalog item');
      expect(g.purchase(s, id, 'p-$id', t0).error, isNotNull);
      expect(g.equip(s, id, t0).error, isNotNull);
      expect(g.placeDecoration(s, id, 'nest').error, isNotNull);
      expect(GameConfig.current.chestItems.contains(id), isFalse);
    }
    // story cosmetics can't be bought either, and never come out of the weekly cosmetic roll
    for (final id in ['reward_firefly_hearth', 'reward_windtrail_mantle', 'reward_waystone_bloom']) {
      expect(g.purchase(s, id, 'p-$id', t0).error, 'not_for_sale');
      expect(catalog[id]!.shop, isNull);
      expect(catalog[id]!.listPrice, isNull);
      expect(catalog[id]!.tradable, isFalse);
      expect(catalog[id]!.sellable, isFalse);
      expect(GameConfig.current.chestItems.contains(id), isFalse);
    }
    // the weekly cosmetic roll: with every shop wearable owned, a story wearable is still never picked
    for (final it in catalog.values) {
      if (it.category == ItemCategory.wearable && isShopItem(it.id)) s = g.purchase(s, it.id, 'own-${it.id}', t0).state;
    }
    const week = ['2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08'];
    final end = dayStart('2026-10-08', tzName) + 12 * hourMs;
    for (final k in week) {
      s = sync(s, [StepSample(id: 'wk$k', source: 'phone', start: dayStart(k, tzName) + 9 * hourMs, end: dayStart(k, tzName) + 10 * hourMs, count: 8000)], end).state;
    }
    final r = g.claimQuest(s, 'weekly_explorer', end);
    expect(r.error, isNull);
    expect(g.ownedQty(r.state, 'reward_windtrail_mantle'), 0);
  });

  test('AT6 the Market lists only shop items: no q_* or reward_* ids', () {
    final shopIds = catalog.keys.where(isShopItem).toList();
    expect(shopIds.length >= 14, isTrue);
    for (final id in shopIds) {
      expect(id.startsWith('q_') || id.startsWith('reward_'), isFalse, reason: id);
    }
    for (final cat in ['wearables', 'habitats', 'care']) {
      expect(catalog.values.where((it) => it.shop == cat).every((it) => !it.id.startsWith('reward_')), isTrue);
    }
    expect(catalog.values.where((it) => it.featured).every((it) => isShopItem(it.id)), isTrue);
  });

  test('AT7 the Windtrail Mantle equips on all three forms; the decor fits its Nest slots', () {
    final s = freshPet();
    for (final id in ['reward_windtrail_mantle', 'reward_firefly_hearth', 'reward_waystone_bloom']) {
      s.inventory[id] = Ownership(quantity: 1);
    }
    for (final stage in [1, 2, 3]) {
      s.pet!.stage = stage;
      final r = g.equip(s, 'reward_windtrail_mantle', t0);
      expect(r.error, isNull, reason: 'stage $stage');
      expect(r.state.pet!.equipped['back'], 'reward_windtrail_mantle');
    }
    expect(g.placeDecoration(s, 'reward_firefly_hearth', 'nest').error, isNull);
    expect(g.placeDecoration(s, 'reward_firefly_hearth', 'left').error, 'no_anchor');
    for (final slot in ['left', 'right', 'back']) {
      expect(g.placeDecoration(s, 'reward_waystone_bloom', slot).error, isNull);
    }
    expect(g.placeDecoration(s, 'reward_waystone_bloom', 'nest').error, 'no_anchor');
  });

  test('AT8 memorial, a new pet and a new colourway keep the story and its rewards', () {
    var s = freshPet();
    s = levelUp(s, 3, t0);
    s = finishVq01(s, t0);
    s = must(q.acceptStoryQuest(s, 'vq02', t0 + 3 * hourMs));
    s = sync(s, walkAt(t0 + 4 * hourMs, 3000, 'm1'), t0 + 6 * hourMs).state;
    s = must(g.memorialize(s, t0 + 7 * hourMs));
    s = must(g.createPet(s, name: 'Pebble', paletteId: 'ocean', requestId: 'req-2', now: t0 + 8 * hourMs));
    expect(s.pet!.paletteId, 'ocean');
    expect(q.questPhase(s, 'vq01'), 'completed');
    expect(q.questPhase(s, 'vq02'), 'accepted_two_days');
    expect(q.pouchQty(s, 'q_windprint_paper'), 1);
    expect(g.ownedQty(s, 'reward_firefly_hearth'), 1);
    expect(s.story.flags['lamp_lit'], isTrue);
    expect(q.accountLevel(s) >= 3, isTrue, reason: 'story gates never go backwards with a new pet');
    // the new pet keeps progressing the same quest
    final k = addDays(k0, 1);
    s = sync(s, walkAt(dayStart(k, tzName) + 9 * hourMs, 3000, 'm2'), dayStart(k, tzName) + 11 * hourMs).state;
    expect(q.questPhase(s, 'vq02'), 'paper_2_ready');
  });

  test('AT9 no step permission: the quest waits, nothing fails, progress resumes later', () {
    var s = freshPet();
    s = must(q.acceptStoryQuest(s, 'vq01', t0));
    s = sync(s, walkAt(t0 + 60000, 800, 'p1'), t0 + 2 * hourMs).state;
    s = must(g.setConnection(s, 'none', t0 + 2 * hourMs));
    final v = q.questView(s, 'vq01', t0 + 30 * dayMs);
    expect(v.paused, isTrue);
    expect(v.phase, 'accepted_walk');
    expect(v.walk.progress, 800);
    s = must(g.setConnection(s, 'demo', t0 + 31 * dayMs));
    s = sync(s, walkAt(t0 + 31 * dayMs, 1500, 'p2'), t0 + 31 * dayMs + 2 * hourMs).state;
    expect(q.questPhase(s, 'vq01'), 'dew_ready');
  });

  test('AT10 relaunch: the save round-trips with phases, pouch, flags, title and after-dialogue', () {
    var s = freshPet();
    s = levelUp(s, 6, t0);
    s = finishVq01(s, t0);
    s = must(q.acceptStoryQuest(s, 'vq02', t0 + 3 * hourMs));
    for (var i = 0; i < 2; i++) {
      final k = addDays(k0, i);
      final from = dayStart(k, tzName) + 15 * hourMs > t0 + 4 * hourMs ? dayStart(k, tzName) + 15 * hourMs : t0 + 4 * hourMs;
      s = sync(s, walkAt(from, 3000, 'two$i'), dayStart(k, tzName) + 20 * hourMs).state;
    }
    s = must(q.storyHandIn(s, 'vq02', 'pip_papers', t0 + 2 * dayMs));
    s = must(q.storyHandIn(s, 'vq02', 'alder_letter', t0 + 2 * dayMs));
    final tA = t0 + 2 * dayMs + hourMs;
    s = must(q.acceptStoryQuest(s, 'vq03', tA));
    for (var i = 2; i < 5; i++) {
      final k = addDays(k0, i);
      s = sync(s, walkAt(dayStart(k, tzName) + 15 * hourMs, 4000, 'three$i'), dayStart(k, tzName) + 20 * hourMs).state;
    }
    expect(q.pouchQty(s, 'q_echo_rubbing'), 3);
    expect(q.questPhase(s, 'vq03'), 'rubbings_ready');
    expect(q.storyHandIn(s, 'vq03', 'restore', t0 + 6 * dayMs).error, 'story_not_ready');
    s = must(q.storyHandIn(s, 'vq03', 'bram_rubbings', t0 + 6 * dayMs));
    s = must(q.storyHandIn(s, 'vq03', 'mira_essence', t0 + 6 * dayMs));
    final bal = balance(s);
    s = must(q.storyHandIn(s, 'vq03', 'restore', t0 + 6 * dayMs));
    expect(balance(s), bal + 250);
    expect(s.story.titleUnlocks, ['first_lightkeeper']);
    expect(s.story.flags['waystone_restored'], isTrue);
    expect(s.story.questPouch, isEmpty);
    final back = GameState.tryParse(s.serialize())!;
    expect(jsonEncode(back.story.toJson()), jsonEncode(s.story.toJson()));
    for (final id in ['vq01', 'vq02', 'vq03']) {
      expect(q.questPhase(back, id), 'completed');
    }
    expect(q.npcConversation(back, 'npc_mira', t0 + 7 * dayMs).start, 'VQ03_MIR02');
    expect(q.npcConversation(back, 'npc_alder', t0 + 7 * dayMs).start, 'VQ03_ALD06');
    expect(q.npcConversation(back, 'waystone', t0 + 7 * dayMs).start, 'WAY_DONE');
    expect(q.storyStatus(back, t0 + 7 * dayMs).chapterDone, isTrue);
  });

  test('old saves without a story object migrate cleanly', () {
    final j = freshPet().toJson();
    j.remove('story');
    final back = GameState.tryParse(jsonEncode(j))!;
    expect(back.story.schemaVersion, 1);
    expect(back.story.flags['lamp_lit'], isFalse);
    expect(q.questPhase(back, 'vq01'), 'available');
  });

  test('a web save with story state loads into the Flutter model unchanged', () {
    var s = freshPet();
    s = must(q.acceptStoryQuest(s, 'vq01', t0));
    s = sync(s, walkAt(t0 + 60000, 700, 'web'), t0 + hourMs).state;
    final text = s.serialize();
    final back = GameState.tryParse(text)!;
    expect(back.serialize(), text);
  });

  test('dialogue opens on the right line for each state', () {
    var s = freshPet();
    expect(q.npcConversation(s, 'npc_mira', t0).start, 'VQ01_M00');
    s = must(q.markNpcMet(s, 'npc_mira'));
    expect(q.npcConversation(s, 'npc_mira', t0).start, 'VQ01_M01');
    expect(q.npcConversation(s, 'npc_bram', t0).start, 'VQ01_B00');
    expect(q.npcConversation(s, 'npc_pip', t0).start, 'VQ02_PIP00');
    expect(q.npcConversation(s, 'waystone', t0).start, 'WAY_LORE');
    s = must(q.acceptStoryQuest(s, 'vq01', t0));
    s = sync(s, walkAt(t0 + 60000, 700, 'dl'), t0 + hourMs).state;
    expect(q.npcConversation(s, 'npc_mira', t0 + hourMs).start, 'VQ01_M04');
    expect(q.lineText(s, 'VQ01_M04', t0 + hourMs), contains('700/2,000'));
    // every line referenced by a conversation exists
    for (final npc in ['npc_mira', 'npc_bram', 'npc_pip', 'npc_alder', 'waystone']) {
      final c = q.npcConversation(s, npc, t0 + hourMs);
      for (final n in c.nodes.values) {
        expect(q.lines.containsKey(n.id), isTrue, reason: n.id);
        for (final ch in n.choices) {
          final to = ch.next ?? ch.then;
          if (to != null) expect(c.nodes.containsKey(to), isTrue, reason: '${n.id} -> $to');
        }
      }
    }
  });

  test('manual entries count for story walks (configurable)', () {
    var s = freshPet();
    s = must(g.setConnection(s, 'manual', t0));
    s = must(q.acceptStoryQuest(s, 'vq01', t0));
    s = sync(s, [StepSample(id: 'man1', source: 'manual', start: t0 + 60000, end: t0 + 120000, count: 2100, manual: true)], t0 + hourMs).state;
    expect(q.questPhase(s, 'vq01'), 'dew_ready');
  });
}
