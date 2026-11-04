// Home Tales: garden beds, walking-boosted growth, crafting, skills, the Cottage and Apothecary quests
// and the side stories (special requirements stay optional). Mirrors web/test/home.test.mjs so both
// clients are held to the same home rules.

import 'dart:convert';

import 'package:evochi/core/models/catalog.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/game/economy/economy.dart' as econ;
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/home/home.dart' as h;
import 'package:evochi/game/story/story.dart' as q;
import 'package:flutter_test/flutter_test.dart';

const tzName = 'America/New_York';
final t0 = DateTime.utc(2026, 10, 5, 14).millisecondsSinceEpoch; // Mon 5 Oct 2026, 10:00 New York
const k0 = '2026-10-05';
const minMs = 60000;

GameState freshPet([int? now]) {
  final n = now ?? t0;
  var s = GameState.fresh(n, tzName);
  s = g.startGuest(s, n, tzName).state;
  s = g.setConnection(s, 'demo', n).state;
  s = must(g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: n));
  return s;
}

GameState must(g.ActionResult r) {
  expect(r.error, isNull, reason: r.error);
  return r.state;
}

/// A walk of [steps] inside [from, from + 1h].
List<StepSample> walkAt(int from, int steps, String tag) => [StepSample(id: 'w_$tag', source: 'phone', start: from, end: from + hourMs, count: steps)];

GameState sync(GameState s, List<StepSample> samples, int now) {
  final r = g.syncSteps(s, samples, now);
  expect(r.error, isNull);
  return r.state;
}

GameState give(GameState s, String id, int n) {
  final c = s.copy();
  g.grantItem(c, id, n, 'test', t0);
  return c;
}

/// The same save with these quests marked completed (like `questStates[id] = { phase: 'completed' }`).
GameState questsDone(GameState s, List<String> ids) {
  final j = (jsonDecode(s.serialize()) as Map).cast<String, dynamic>();
  final story = (j['story'] as Map).cast<String, dynamic>();
  final qs = (story['questStates'] as Map).cast<String, dynamic>();
  for (final id in ids) {
    qs[id] = {'phase': 'completed'};
  }
  story['questStates'] = qs;
  j['story'] = story;
  return GameState.fromJson(j);
}

GameState backdatePet(GameState s, String k) {
  final j = (jsonDecode(s.serialize()) as Map).cast<String, dynamic>();
  final pet = (j['pet'] as Map).cast<String, dynamic>();
  if (k.compareTo(pet['createdDay'] as String) < 0) pet['createdDay'] = k;
  j['pet'] = pet;
  return GameState.fromJson(j);
}

/// Give the pet enough XP for [level] by backfilling past days.
GameState levelUp(GameState s, int level, int now) {
  var i = 1;
  while (q.accountLevel(s) < level) {
    final k = addDays(k0, -i);
    s = backdatePet(s, k);
    final st = dayStart(k, tzName) + 9 * hourMs;
    s = sync(s, [StepSample(id: 'lv_$k', source: 'phone', start: st, end: st + hourMs, count: 9000)], now);
    i++;
    expect(i < 400, isTrue, reason: 'levelling runaway');
  }
  return s;
}

GameState setSkill(GameState s, String skill, int level) {
  final c = s.copy();
  var xp = 0;
  for (var l = 1; l < level; l++) {
    xp += h.skillCurveBase + h.skillCurveStep * (l - 1);
  }
  c.home.skills[skill] = xp;
  return c;
}

void main() {
  setUpAll(ensureTimeZones);

  test('catalog: seeds are Market items, harvests and homemade food never are', () {
    for (final c in h.cropDefs.values) {
      expect(isShopItem(c.seed), isTrue, reason: c.seed);
      for (final id in c.yieldItems.keys) {
        expect(isShopItem(id), isFalse, reason: id);
        expect(catalog[id]!.category, ItemCategory.ingredient, reason: id);
      }
    }
    for (final r in h.recipeDefs.values) {
      expect(catalog[r.makes] != null && !isShopItem(r.makes), isTrue, reason: r.makes);
      for (final id in r.needs.keys) {
        expect(catalog[id], isNotNull, reason: id);
      }
    }
  });

  test('skill curve: levels, carry-over and the cap', () {
    final l0 = h.skillLevel(0);
    expect([l0.level, l0.into, l0.need, l0.maxed], [1, 0, 40, false]);
    expect(h.skillLevel(40).level, 2);
    expect(h.skillLevel(99).level, 2);
    expect(h.skillLevel(100).level, 3);
    expect(h.skillLevel(1000000000).level, h.skillCurveMax);
  });

  test('old saves get a home in place, and starter seeds come once', () {
    final j = (jsonDecode(freshPet().serialize()) as Map).cast<String, dynamic>();
    j.remove('home');
    ((j['story'] as Map)['flags'] as Map).remove('cottage_restored');
    final s = GameState.tryParse(jsonEncode(j))!;
    expect(s.home.plots.containsKey('p1') && s.home.plots['p1'] == null, isTrue);
    expect(s.home.skills['farming'], 0);
    expect(s.story.flags['cottage_restored'], isFalse);
    final r1 = h.claimStarterSeeds(s, t0);
    expect(g.ownedQty(r1.state, 'seed_sunberry'), 3);
    final r2 = h.claimStarterSeeds(r1.state, t0 + 1);
    expect(g.ownedQty(r2.state, 'seed_sunberry'), 3, reason: 'starter seeds are granted once');
  });

  test('planting: seeds, unlocked beds and crops only', () {
    var s = must(h.claimStarterSeeds(freshPet(), t0));
    expect(h.plant(s, 'p4', 'sunberry', t0).error, 'plot_locked');
    expect(h.plant(s, 'p1', 'glowleaf', t0).error, 'crop_locked');
    expect(h.plant(s, 'p1', 'golden_wheat', t0).error, 'crop_locked');
    s = must(h.plant(s, 'p1', 'sunberry', t0));
    expect(g.ownedQty(s, 'seed_sunberry'), 2);
    expect(h.plant(s, 'p1', 'sunberry', t0).error, 'plot_busy');
    final s2 = setSkill(s, 'farming', 4);
    expect(h.plotUnlocked(s2, 'p4'), isTrue);
  });

  test('growth: real time, walking after planting (capped), watering', () {
    var s = must(h.claimStarterSeeds(freshPet(), t0));
    s = must(h.plant(s, 'p1', 'meadow_carrot', t0)); // 45 minutes
    h.PlotView at(int t) => h.plotView(s, 'p1', t);
    expect(at(t0).stage, 'sprout');
    expect((at(t0 + (22.5 * minMs).round()).progress - 0.5).abs() < 1e-9, isTrue);
    expect(h.harvest(s, 'p1', t0 + 20 * minMs).error, 'not_ripe');
    // steps taken BEFORE planting never count
    s = sync(s, walkAt(t0 - 2 * hourMs, 5000, 'before'), t0);
    expect(at(t0).progress, 0);
    // 3,000 steps after planting = 30% of the growing time
    s = sync(s, walkAt(t0 + minMs, 3000, 'after'), t0 + 2 * minMs);
    expect((h.plotGrowth(s, s.home.plots['p1']!, t0 + 2 * minMs).walk - 0.3).abs() < 1e-9, isTrue);
    // walking can add at most 60%
    s = sync(s, walkAt(t0 + 3 * minMs, 20000, 'long'), t0 + 4 * minMs);
    expect(h.plotGrowth(s, s.home.plots['p1']!, t0 + 4 * minMs).walk, h.growMaxWalkShare);
    // watering once adds 15%, a second time changes nothing
    s = must(h.water(s, 'p1', t0 + 4 * minMs));
    final w = h.plotGrowth(s, s.home.plots['p1']!, t0 + 4 * minMs).progress;
    s = must(h.water(s, 'p1', t0 + 4 * minMs));
    expect(h.plotGrowth(s, s.home.plots['p1']!, t0 + 4 * minMs).progress, w);
    // 60% walked + 15% watered + 25% of the time = ripe
    final ripeAt = t0 + (0.25 * 45).ceil() * minMs;
    expect(at(ripeAt).ripe, isTrue);
  });

  test('harvest: yield into the Bag, Farming XP, bed cleared, never twice', () {
    var s = must(h.claimStarterSeeds(freshPet(), t0));
    s = must(h.plant(s, 'p2', 'sunberry', t0));
    final r = h.harvest(s, 'p2', t0 + 21 * minMs);
    s = must(r);
    expect(g.ownedQty(s, 'sunberry'), 3);
    expect(s.home.skills['farming'], h.cropDefs['sunberry']!.xp);
    expect(s.home.plots['p2'], isNull);
    expect(h.harvest(s, 'p2', t0 + 22 * minMs).error, 'plot_empty');
    expect(r.events.any((e) => e.type == 'harvested'), isTrue);
  });

  test('skill-ups name what they unlock', () {
    var s = give(must(h.claimStarterSeeds(freshPet(), t0)), 'seed_sunberry', 10);
    final ups = <g.GameEvent>[];
    var t = t0;
    for (var i = 0; i < 4; i++) {
      s = must(h.plant(s, 'p1', 'sunberry', t));
      t += 21 * minMs;
      final r = h.harvest(s, 'p1', t);
      s = must(r);
      ups.addAll(r.events.where((e) => e.type == 'skill_up'));
    }
    expect(ups.length, 1);
    expect(ups.first.data['level'], 2);
    final unlocks = (ups.first.data['unlocks'] as List).cast<h.SkillMilestone>();
    expect(unlocks.any((m) => m.kind == 'crop' && m.id == 'golden_wheat'), isTrue);
  });

  test('crafting: station must be open, recipe known, ingredients complete; perfect doubles the batch', () {
    var s = give(give(freshPet(), 'sunberry', 7), 'golden_wheat', 2);
    expect(h.craft(s, 'sunberry_tart', 'good', t0).error, 'station_locked');
    s = s.copy();
    s.story.flags['cottage_restored'] = true;
    expect(h.craft(s, 'golden_bun', 'good', t0).error, 'recipe_locked');
    final r = h.craft(s, 'sunberry_tart', 'good', t0);
    s = must(r);
    expect(g.ownedQty(s, 'sunberry_tart'), 1);
    expect(g.ownedQty(s, 'sunberry'), 4);
    expect(s.home.skills['cooking'], 20);
    final r2 = h.craft(s, 'sunberry_tart', 'perfect', t0);
    s = must(r2);
    expect(g.ownedQty(s, 'sunberry_tart'), 3);
    expect(s.home.skills['cooking'], 50);
    expect(h.craft(s, 'sunberry_tart', 'perfect', t0).error, 'missing_ingredients');
    expect(g.ownedQty(s, 'sunberry'), 1, reason: 'a failed craft takes nothing');
  });

  test('homemade treats: vitality, plus Bond once a day even at full vitality', () {
    var s = give(freshPet(), 'carrot_stew', 3);
    final d0 = g.derive(s, t0);
    expect(d0.pet!.vitality.vitality, 100);
    s = must(g.useConsumable(s, 'carrot_stew', t0));
    final d1 = g.derive(s, t0);
    expect(d1.pet!.bond, d0.pet!.bond + 1);
    expect(g.useConsumable(s, 'carrot_stew', t0 + 1).error, 'full', reason: 'second treat on a full day: nothing to do');
    expect(g.useConsumable(give(s, 'sprout_tonic', 1), 'sprout_tonic', t0).error, 'use_in_garden');
  });

  test('Sprout Tonic adds half a growing time once', () {
    var s = give(must(h.claimStarterSeeds(freshPet(), t0)), 'sprout_tonic', 2);
    s = must(h.plant(s, 'p1', 'sunberry', t0));
    s = must(h.useSproutTonic(s, 'p1', t0));
    expect(h.plotView(s, 'p1', t0).progress, 0.5);
    expect(h.useSproutTonic(s, 'p1', t0).error, 'tonic_used');
    expect(g.ownedQty(s, 'sprout_tonic'), 1);
  });

  test('A Place to Call Home: walk for timber, harvest berries, Bram, then restore -> Kitchen opens', () {
    var s = freshPet();
    expect(q.questPhase(s, 'hq01'), 'locked');
    s = levelUp(s, 2, t0);
    var now = t0 + hourMs;
    // finish VQ01 first
    s = must(q.acceptStoryQuest(s, 'vq01', now));
    s = sync(s, walkAt(now + minMs, 2500, 'vq01'), now + 2 * hourMs);
    s = must(q.storyHandIn(s, 'vq01', 'mira_dew', now + 2 * hourMs));
    s = must(q.storyHandIn(s, 'vq01', 'bram_sprig', now + 2 * hourMs));
    now += 3 * hourMs;
    expect(q.questPhase(s, 'hq01'), 'available');
    s = must(q.acceptStoryQuest(s, 'hq01', now));
    expect(q.questPhase(s, 'hq01'), 'accepted_walk');
    s = sync(s, walkAt(now + minMs, 3200, 'hq01'), now + 2 * hourMs);
    expect(q.questPhase(s, 'hq01'), 'timber_ready');
    expect(q.pouchQty(s, 'q_sturdy_timber'), 1);
    // no Sunberries yet: gather first, and the hand-in is refused without taking anything
    expect(q.nextStep(s, 'hq01').kind, 'gather');
    expect(q.storyHandIn(s, 'hq01', 'bram_timber', now).error, 'story_missing_items');
    expect(q.pouchQty(s, 'q_sturdy_timber'), 1);
    final berries = q.questView(s, 'hq01', now).objectives.firstWhere((o) => o.id == 'berries');
    expect([berries.have, berries.need], [0, 3]);
    // grow them
    s = must(h.claimStarterSeeds(s, now));
    s = must(h.plant(s, 'p1', 'sunberry', now + 2 * hourMs));
    s = must(h.harvest(s, 'p1', now + 3 * hourMs));
    expect(q.nextStep(s, 'hq01').kind, 'handin');
    s = must(q.storyHandIn(s, 'hq01', 'bram_timber', now + 3 * hourMs));
    expect(g.ownedQty(s, 'sunberry'), 0);
    expect(q.questPhase(s, 'hq01'), 'restoration_ready');
    expect(q.nextStep(s, 'hq01').place, 'cottage');
    expect(h.stationOpen(s, 'kitchen'), isFalse);
    final coins = g.balanceOf(s);
    s = must(q.storyHandIn(s, 'hq01', 'restore_cottage', now + 3 * hourMs));
    expect(q.questPhase(s, 'hq01'), 'completed');
    expect(h.stationOpen(s, 'kitchen'), isTrue);
    expect(g.balanceOf(s), coins + 100);
    expect(g.ownedQty(s, 'seed_golden_wheat'), 3);
    // paid once
    final again = q.storyHandIn(s, 'hq01', 'restore_cottage', now + 4 * hourMs);
    expect(g.balanceOf(again.state), coins + 100);
  });

  test("Mira's Mortar needs Cooking 2 and 2 Glowleaf; it opens the Apothecary", () {
    var s = questsDone(freshPet(), ['vq01', 'hq01']);
    s.story.flags['cottage_restored'] = true;
    s = levelUp(s, 2, t0);
    expect(q.lockReason(s, 'hq02')!.text, contains('Cooking Lv 2'));
    s = setSkill(s, 'cooking', 2);
    expect(q.lockReason(s, 'hq02'), isNull);
    s = must(q.acceptStoryQuest(s, 'hq02', t0));
    expect(q.questPhase(s, 'hq02'), 'need_glowleaf');
    expect(q.nextStep(s, 'hq02').kind, 'gather');
    s = give(s, 'glowleaf', 2);
    s = must(q.storyHandIn(s, 'hq02', 'mira_glowleaf', t0));
    expect(h.stationOpen(s, 'apothecary'), isTrue);
    expect(g.ownedQty(s, 'glowleaf'), 0);
  });

  test('side story: the Grove asks for a grown Evochi, and it stays optional', () {
    var s = questsDone(freshPet(), ['vq01', 'hq01', 'hq02']);
    s = levelUp(s, 4, t0);
    final lock = q.lockReason(s, 'sq02')!;
    expect(lock.needStage, 2);
    expect(lock.text, contains('Juvenile'));
    // nothing on the main path depends on a side story
    for (final quest in q.storyQuests.values) {
      if (quest.line != 'side') expect(quest.dependsOn.any((d) => q.storyQuests[d]!.line == 'side'), isFalse, reason: quest.id);
    }
    s.pet!.stage = 2;
    expect(q.lockReason(s, 'sq02'), isNull);
    s = must(q.acceptStoryQuest(s, 'sq02', t0));
    s = give(s, 'glowleaf_tonic', 1);
    s = must(q.storyHandIn(s, 'sq02', 'alder_tonic', t0));
    expect(s.story.titleUnlocks, contains('grove_friend'));
  });

  test('npc markers and conversations reach the new quests without breaking Chapter 1', () {
    var s = questsDone(freshPet(), ['vq01']);
    s = levelUp(s, 2, t0);
    expect(q.npcMarkers(s)['npc_bram'], 'quest');
    expect(q.npcConversation(s, 'npc_bram', t0).start, 'HQ01_B00');
    expect(q.npcConversation(s, 'npc_mira', t0).start, 'VQ01_M07');
    expect(q.lineText(s, 'HQ01_B02', t0), contains('3,000'));
    // every line a conversation (the Cottage included) refers to exists
    for (final npc in ['npc_mira', 'npc_bram', 'npc_pip', 'npc_alder', 'cottage', 'waystone']) {
      final c = q.npcConversation(s, npc, t0);
      for (final n in c.nodes.values) {
        expect(q.lines.containsKey(n.id), isTrue, reason: n.id);
        for (final ch in n.choices) {
          final to = ch.next ?? ch.then;
          if (to != null) expect(c.nodes.containsKey(to), isTrue, reason: '${n.id} -> $to');
        }
      }
    }
  });

  test('labels and sources: plural names and where each home item comes from', () {
    expect(h.itemLabel('sunberry', 3), 'Sunberries');
    expect(h.itemLabel('sunberry', 1), 'Sunberry');
    expect(h.itemLabel('golden_wheat', 2), 'Golden Wheat');
    expect(h.itemLabel('glowleaf', 2), 'Glowleaf');
    expect(h.itemLabel('seed_moonshroom', 3), 'Moonshroom Spores');
    expect(h.itemLabel('sunberry_tart', 2), 'Sunberry Tarts');
    final src = h.homeSource('sunberry')!;
    expect([src.route, src.verb, src.place, src.station], ['garden', 'Grow', 'Garden', null]);
    expect(h.homeSource('sunberry_tart')!.station, 'kitchen');
    expect(h.homeSource('glowleaf_tonic')!.station, 'apothecary');
    expect(h.homeSource('berry_snack'), isNull);
    // every quest text that can ask for an item resolves to a place to get it
    for (final quest in q.storyQuests.values) {
      for (final t in quest.turnIns) {
        for (final id in t.consumeItems.keys) {
          expect(h.homeSource(id), isNotNull, reason: id);
        }
      }
    }
  });

  test('the story still reads well for walk-less quests (no crash in line text)', () {
    final s = freshPet();
    for (final id in q.lines.keys) {
      expect(q.lineText(s, id, t0, petName: 'Ember'), isA<String>(), reason: id);
    }
  });

  // ---- Flutter-only checks: the save format and the playtest shortcut
  test('the home state round-trips through a save unchanged', () {
    var s = must(h.claimStarterSeeds(freshPet(), t0));
    s = must(h.plant(s, 'p1', 'sunberry', t0));
    s = must(h.water(s, 'p1', t0));
    final text = s.serialize();
    final back = GameState.tryParse(text)!;
    expect(jsonEncode(back.home.toJson()), jsonEncode(s.home.toJson()));
    expect(back.serialize(), text);
    expect(back.home.plots['p1']!.watered, isTrue);
  });

  test('playtest: Skip to Home Tales finishes VQ01 once and opens A Place to Call Home', () {
    var s = freshPet();
    final r = q.playtestHomeTalesReady(s, t0);
    s = must(r);
    expect(r.events, isNotEmpty);
    expect(q.questPhase(s, 'vq01'), 'completed');
    expect(g.ownedQty(s, 'reward_firefly_hearth'), 1);
    expect(q.questPhase(s, 'hq01'), 'available');
    expect(q.playtestHomeTalesReady(s, t0 + 1).events, isEmpty);
  });

  group('garden helpers', () {
    Pet resting(String id, {String palette = 'forest', int stage = 2}) =>
        Pet(id: id, requestId: 'req-$id', name: 'Fern $id', paletteId: palette, stage: stage, habitatId: 'sunlit_meadow', createdAt: t0, createdDay: k0);

    GameState withHelpers(List<Pet> pets) {
      final c = give(freshPet(), 'seed_sunberry', 6);
      c.companions.addAll(pets);
      return c;
    }

    test('only a resting Forest Juvenile can tend a bed', () {
      final s = withHelpers([resting('a'), resting('b', palette: 'amber'), resting('c', stage: 3), resting('d', stage: 1)]);
      expect(h.helperCandidates(s).map((p) => p.id), ['a']);
      expect(h.assignHelper(s, 'p1', 'b', t0).error, 'cant_help');
      expect(h.assignHelper(s, 'p1', 'c', t0).error, 'cant_help');
      expect(h.assignHelper(s, 'p1', 'd', t0).error, 'cant_help');
      expect(h.assignHelper(s, 'p1', 'zz', t0).error, 'not_resting');
      expect(h.assignHelper(s, 'p8', 'a', t0).error, 'plot_locked');
      expect(must(h.assignHelper(s, 'p1', 'a', t0)).home.helpers, {'p1': 'a'});
    });

    test('a tended bed is watered, and its harvest has one more of the crop, never a speed boost', () {
      var s = withHelpers([resting('a')]);
      s = must(h.assignHelper(s, 'p1', 'a', t0));
      s = must(h.plant(s, 'p1', 'sunberry', t0));
      s = must(h.plant(s, 'p2', 'sunberry', t0));
      expect(s.home.plots['p1']!.watered, isTrue);
      expect(s.home.plots['p1']!.tender, 'a');
      expect(h.tended(s, 'p1'), isTrue);
      expect(h.tended(s, 'p2'), isFalse);
      // watered, it grows like any watered bed: no faster
      final wet = must(h.water(s, 'p2', t0));
      expect(h.plotGrowth(wet, wet.home.plots['p1']!, t0 + 10 * minMs).progress, h.plotGrowth(wet, wet.home.plots['p2']!, t0 + 10 * minMs).progress);
      final done = t0 + 21 * minMs;
      final r1 = h.harvest(s, 'p1', done);
      final r2 = h.harvest(s, 'p2', done);
      final golden = r1.events.first.data['golden'] == true;
      expect(r1.events.first.data['items'], golden ? {'sunberry': 8, 'gilded_sunberry': 1} : {'sunberry': 4});
      expect(r2.events.first.data['items'], {'sunberry': 3});
    });

    test('Golden harvests come about one in ten, seeded (no rerolls), and only on tended beds', () {
      var golden = 0;
      for (var i = 0; i < 200; i++) {
        var s = withHelpers([resting('a')]);
        s = must(h.assignHelper(s, 'p1', 'a', t0));
        s = must(h.plant(s, 'p1', 'sunberry', t0 + i * 1000));
        if (h.goldenHarvest(s, 'p1')) golden++;
        expect(h.goldenHarvest(s, 'p1'), h.goldenHarvest(s.copy(), 'p1'));
      }
      expect(golden, inInclusiveRange(8, 36));
      final plain = must(h.plant(withHelpers([]), 'p1', 'sunberry', t0));
      expect(h.goldenHarvest(plain, 'p1'), isFalse);
    });

    test('a Sunstone on a tended bed always comes up Golden: doubled, a Gilded crop, more XP', () {
      var s = give(give(withHelpers([resting('a')]), 'sunstone', 2), 'seed_meadow_carrot', 2);
      s = must(h.assignHelper(s, 'p1', 'a', t0));
      s = must(h.plant(s, 'p1', 'meadow_carrot', t0));
      s = must(h.plant(s, 'p2', 'meadow_carrot', t0));
      s = must(econ.useSunstone(s, 'p1', t0 + minMs));
      s = must(econ.useSunstone(s, 'p2', t0 + minMs));
      final r = h.harvest(s, 'p1', t0 + 2 * minMs);
      expect(r.events.first.data['golden'], isTrue);
      expect(r.events.first.data['items'], {'meadow_carrot': 6, 'gilded_carrot': 1});
      expect(r.state.home.counts['golden'], 1);
      expect(h.skillXp(r.state, 'farming'), 21);
      // untended, a Sunstone ripens it and that's all
      final plain = h.harvest(s, 'p2', t0 + 2 * minMs);
      expect(plain.events.first.data['golden'], isFalse);
      expect(plain.events.first.data['items'], {'meadow_carrot': 2});
    });

    test('a helper tends one bed: moved, the crop it left is no longer tended; it can join a growing bed, not a ripe one', () {
      var s = withHelpers([resting('a')]);
      s = must(h.plant(s, 'p1', 'sunberry', t0));
      s = must(h.plant(s, 'p2', 'sunberry', t0));
      s = must(h.assignHelper(s, 'p1', 'a', t0 + minMs));
      expect(h.tended(s, 'p1'), isTrue);
      expect(s.home.plots['p1']!.watered, isTrue);
      s = must(h.assignHelper(s, 'p2', 'a', t0 + 2 * minMs));
      expect(h.tended(s, 'p1'), isFalse);
      expect(h.tended(s, 'p2'), isTrue);
      expect(s.home.helpers, {'p2': 'a'});
      // ripe: the helper stays on the bed for the next planting, but this crop isn't tended
      final late = must(h.assignHelper(s, 'p1', 'a', t0 + 30 * minMs));
      expect(h.tended(late, 'p1'), isFalse);
      expect(late.home.helpers, {'p1': 'a'});
      // and it rests again
      expect(must(h.assignHelper(late, 'p1', null, t0)).home.helpers, isEmpty);
    });

    test('grown into an Elder, a helper finishes its crop and then rests; one out walking tends nothing', () {
      var s = withHelpers([resting('a')]);
      s = must(h.assignHelper(s, 'p1', 'a', t0));
      s = must(h.plant(s, 'p1', 'sunberry', t0));
      s.companions.first.stage = 3;
      expect(h.tended(s, 'p1'), isTrue);
      s = must(h.harvest(s, 'p1', t0 + 21 * minMs));
      s = must(h.plant(s, 'p1', 'sunberry', t0 + 22 * minMs));
      expect(s.home.plots['p1']!.tender, isNull);
      expect(s.home.helpers, isEmpty);
      // a helper who became the active Evochi isn't at home
      var w = withHelpers([resting('b')]);
      w = must(h.assignHelper(w, 'p1', 'b', t0));
      w = must(h.plant(w, 'p1', 'sunberry', t0));
      w.companions.clear();
      expect(h.tended(w, 'p1'), isFalse);
    });

    test('one helper to a field: the garden from the start, the lower field once its first bed opens', () {
      var s = withHelpers([resting('a'), resting('b'), resting('c')]);
      expect(h.helperSlots(s), 1);
      expect(h.nextHelperSlot(s), 6);
      s = must(h.assignHelper(s, 'p1', 'a', t0));
      final taken = h.assignHelper(s, 'p2', 'b', t0);
      expect(taken.error, 'field_taken');
      expect(taken.info['pet'], 'a');
      // moving the one at work, within its field, is fine
      expect(must(h.assignHelper(s, 'p2', 'a', t0)).home.helpers, {'p2': 'a'});
      expect(h.assignHelper(s, 'p5', 'b', t0).error, 'plot_locked');
      s = setSkill(s, 'farming', 6);
      expect(h.helperSlots(s), 2);
      expect(h.nextHelperSlot(s), isNull);
      s = must(h.assignHelper(s, 'p5', 'b', t0));
      expect(h.assignHelper(s, 'p3', 'c', t0).error, 'field_taken');
      s = setSkill(s, 'farming', 8);
      expect(h.assignHelper(s, 'p6', 'c', t0).error, 'field_taken');
      expect(h.helpersAtWork(s), 2);
    });

    test('helpers and a tended planting survive a save', () {
      var s = withHelpers([resting('a')]);
      s = must(h.assignHelper(s, 'p1', 'a', t0));
      s = must(h.plant(s, 'p1', 'sunberry', t0));
      final back = GameState.fromJson((jsonDecode(s.serialize()) as Map).cast<String, dynamic>());
      expect(back.home.helpers, {'p1': 'a'});
      expect(back.home.plots['p1']!.tender, 'a');
      expect(h.tended(back, 'p1'), isTrue);
    });
  });
}
