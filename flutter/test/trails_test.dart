// Lumen Trails: daily discoveries, the Trail Guild, encounter quests (their beats are the Deep Wilds'
// story floors: game/wilds/story_floors.dart), companions, and old saves' open encounters settled.

import 'dart:convert';

import 'package:evochi/core/models/catalog.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/models/story_state.dart';
import 'package:evochi/core/models/trails_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/home/home.dart' as h;
import 'package:evochi/game/story/story.dart' as q;
import 'package:evochi/game/trails/trails.dart' as tr;
import 'package:evochi/game/wilds/story_floors.dart' as sf;
import 'package:evochi/game/wilds/wilds.dart' as w;
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
  expect(r.error, isNull, reason: '${r.error}${r.info['message'] != null ? ': ${r.info['message']}' : ''}');
  return r.state;
}

/// A walk of [steps] inside [from, from + 1h].
List<StepSample> walkAt(int from, int steps, String tag) => [StepSample(id: 'w_$tag', source: 'phone', start: from, end: from + hourMs, count: steps)];

g.ActionResult sync(GameState s, List<StepSample> samples, int now) {
  final r = g.syncSteps(s, samples, now);
  expect(r.error, isNull);
  return r;
}

GameState give(GameState s, String id, int n) {
  final c = s.copy();
  g.grantItem(c, id, n, 'test', t0);
  return c;
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
  s = sync(s, walkAt(now + minMs, 2500, 'vq01'), now + 2 * hourMs).state;
  s = must(q.storyHandIn(s, 'vq01', 'mira_dew', now + 2 * hourMs));
  return must(q.storyHandIn(s, 'vq01', 'bram_sprig', now + 2 * hourMs));
}

/// A quest marked completed in place (like the web test's `questStates[id] = { phase: 'completed', ... }`).
QuestState doneState(int now, {int resolved = 1000, bool seen = false}) => QuestState.fromJson({
      'phase': 'completed',
      'acceptedAt': now - hourMs,
      'acceptedDay': dayKey(now, tzName),
      'resolvedSteps': resolved,
      'completedAt': now,
      'seenCompletion': seen,
    });

/// Complete [n] discoveries one after another (each: begin, walk, inspect). Returns the state and the time.
(GameState, int) doDiscoveries(GameState s, int n, int from) {
  var now = from;
  for (var i = 0; i < n; i++) {
    final d = tr.trailsStatus(s, now).discoveries.where((x) => x.phase == 'offered').firstOrNull;
    expect(d, isNotNull, reason: 'a discovery is posted');
    s = must(tr.beginDiscovery(s, d!.id, now));
    s = sync(s, walkAt(now + minMs, d.target + 200, 'disc$i'), now + 2 * hourMs).state;
    s = must(tr.inspectDiscovery(s, d.id, now + 2 * hourMs));
    now += 3 * hourMs;
  }
  return (s, now);
}

int balance(GameState s) => g.balanceOf(s);

void main() {
  setUpAll(ensureTimeZones);

  test('catalog: shards and tonics are never sold; the relic is a story decoration', () {
    expect(isShopItem('lumen_shard'), isFalse);
    expect(isShopItem('lantern_tonic'), isFalse);
    expect(catalog['ancient_relic']!.acquisition, 'story');
    expect(catalog['ancient_relic']!.decor, 'side');
  });

  test('old saves get a trails object; the day board is three authored discoveries, stable per day', () {
    final s = freshPet();
    final old = (jsonDecode(s.serialize()) as Map).cast<String, dynamic>();
    old.remove('trails');
    final back = GameState.fromJson(old);
    expect(back.trails.stats, isNotEmpty);
    expect(back.trails.stat('discoveries'), 0);
    // deterministic per player and day
    final a = tr.pickDiscoveries(s, k0);
    final b = tr.pickDiscoveries(s, k0);
    expect(a, equals(b));
    expect(a.length, 3);
    expect({for (final id in a) tr.discoveryDefs[id]!.place}.length, 3, reason: 'three different places');
    // nothing gated behind the cottage or the ruins before they exist
    for (final id in a) {
      expect(tr.discoveryDefs[id]!.needs, isNull);
    }
    // a different day, a different set (usually), never the same place twice
    final c = tr.pickDiscoveries(s, addDays(k0, 1));
    expect(c.length, 3);
    expect({for (final id in c) tr.discoveryDefs[id]!.place}.length, 3);
    // the saved board round-trips
    final again = GameState.fromJson((jsonDecode(must(tr.beginDiscovery(s, a[0], t0)).serialize()) as Map).cast<String, dynamic>());
    expect(again.trails.days[k0]!.ids, equals(a));
    expect(again.trails.days[k0]!.states[a[0]]!.acceptedAt, t0);
  });

  test('a discovery: begin, walk (steps after beginning only), inspect at its place, rewards once', () {
    var s = freshPet();
    final now = t0 + hourMs;
    // steps before beginning never count
    s = sync(s, walkAt(t0, 4000, 'early'), now).state;
    final d0 = tr.trailsStatus(s, now).discoveries[0];
    expect(d0.phase, 'offered');
    s = must(tr.beginDiscovery(s, d0.id, now));
    expect(tr.discoveryView(s, d0.id, now).phase, 'walking');
    expect(tr.discoveryView(s, d0.id, now).walked, 0);
    expect(tr.inspectDiscovery(s, d0.id, now).error, 'discovery_not_ready');
    final r = sync(s, walkAt(now + minMs, d0.target + 100, 'd0'), now + 2 * hourMs);
    s = r.state;
    expect(r.events.any((e) => e.type == 'discovery_ready' && e.data['id'] == d0.id), isTrue);
    final v = tr.discoveryView(s, d0.id, now + 2 * hourMs);
    expect(v.phase, 'ready');
    expect(tr.cluesAt(s, d0.place, now + 2 * hourMs).map((x) => x.id).toList(), [d0.id]);
    final coins = balance(s);
    final r2 = tr.inspectDiscovery(s, d0.id, now + 2 * hourMs);
    s = must(r2);
    expect(r2.events.any((e) => e.type == 'discovery_found'), isTrue);
    expect(balance(s), coins + d0.reward.coins);
    for (final e in d0.reward.items.entries) {
      expect(g.ownedQty(s, e.key), e.value);
    }
    expect(s.trails.guildXp, d0.reward.guildXp);
    expect(tr.trailsStatus(s, now + 2 * hourMs).foundToday, 1);
    // again: nothing more
    final r3 = tr.inspectDiscovery(s, d0.id, now + 3 * hourMs);
    expect(identical(r3.state, s), isTrue);
    expect(balance(r3.state), coins + d0.reward.coins);
    // the board resets tomorrow
    final tomorrow = now + dayMs;
    expect(tr.trailsStatus(s, tomorrow).foundToday, 0);
    expect(tr.trailsStatus(s, tomorrow).discoveries.length, 3);
  });

  test('guild ranks climb with discovery XP', () {
    expect(tr.guildRank(0).name, 'Wanderer');
    expect(tr.guildRank(45).name, 'Trail Friend');
    expect(tr.guildRank(45).next!.name, 'Pathfinder');
    expect(tr.guildRank(45).into, 5);
    expect(tr.guildRank(45).need, 80);
    expect(tr.guildRank(9999).next, isNull);
  });

  test('The Forest Guardian: needs two discoveries, a walk, then an encounter that befriends Petalune', () {
    var s = freshPet();
    s = levelUp(s, 3, t0);
    var now = t0 + hourMs;
    s = finishVq01(s, now);
    now += 3 * hourMs;
    expect(q.questPhase(s, 'eq01'), 'locked');
    expect(q.lockReason(s, 'eq01')!.needDiscoveries, 2);
    // Pip offers Chapter 1's second quest first; once that's underway he mentions the Guild's rule
    expect(q.npcConversation(s, 'npc_pip', now).start, 'VQ02_PIP00');
    final onWalk = must(q.acceptStoryQuest(s, 'vq02', now));
    expect(q.npcConversation(onWalk, 'npc_pip', now).start, 'EQ01_LOCK');
    (s, now) = doDiscoveries(s, 2, now);
    expect(q.questPhase(s, 'eq01'), 'available');
    expect(q.npcConversation(s, 'npc_pip', now).start, 'VQ02_PIP00'); // the greeting, then straight into the Guild job
    expect(q.npcConversation(s, 'npc_pip', now).nodes['VQ02_PIP00']!.choices[0].next, 'EQ01_P00');
    s = must(q.acceptStoryQuest(s, 'eq01', now));
    // its place (the Mossy Ruins, F3) waits for the walk
    expect(sf.storyFloorOpen(s, 'eq01'), isFalse);
    s = sync(s, walkAt(now + minMs, 1600, 'eq01'), now + 2 * hourMs).state;
    now += 2 * hourMs;
    expect(q.questPhase(s, 'eq01'), 'ruins_ready');
    expect(q.pouchQty(s, 'q_mossy_clue'), 1);
    final n = q.nextStep(s, 'eq01');
    expect(n.kind, 'encounter');
    expect(n.place, 'ruins');
    expect(n.encounter, 'petalune');
    expect(q.storyStatus(s, now).encounters.any((v) => v.id == 'eq01'), isTrue);
    // the optional tart is never required
    expect(q.questView(s, 'eq01', now).objectives.firstWhere((o) => o.id == 'tart').optional, isTrue);
    // the job's place: the Mossy Ruins at F3 of Fernwood Trail, while the job is open
    expect(sf.storyFloorAt(s, 3)?.quest, 'eq01');
    expect(tr.encounterDefs['eq01']!.creature, 'petalune');
    // Petalune's trust earned on the floor: the job hands in
    final coins = balance(s);
    final r = sf.wildsStoryDone(s, 'eq01', now);
    s = must(r);
    expect(s.trails.companions['petalune']!.since, now);
    expect(s.trails.stat('befriended'), 1);
    expect(sf.storyFloorAt(s, 3), isNull, reason: 'done: F3 is an ordinary floor again');
    expect(q.questPhase(s, 'eq01'), 'completed');
    expect(q.pouchQty(s, 'q_mossy_clue'), 0);
    expect(balance(s), coins + 150);
    expect(g.ownedQty(s, 'lumen_shard') >= 1, isTrue);
    expect(s.story.titleUnlocks, contains('friend_of_petalune'));
    expect(s.story.flags['petalune_befriended'], isTrue);
    expect(r.events.any((e) => e.type == 'companion_joined' && e.data['creature'] == 'petalune'), isTrue);
    expect(tr.trailsStatus(s, now).companions[0].name, 'Petalune');
    // Pip thanks you once, then has a normal line
    expect(q.npcConversation(s, 'npc_pip', now).start, 'EQ01_P05');
    s = must(q.markNpcMet(s, 'eq01_thanks'));
    expect(q.npcConversation(s, 'npc_pip', now).start, isNot('EQ01_P05'));
    // the ruins now post discoveries
    expect(tr.discoveryOrder.any((id) => tr.discoveryDefs[id]!.place == 'ruins'), isTrue);
    expect(tr.pickDiscoveries(s, addDays(k0, 2)).length, 3);
  });

  test('old saves: an encounter left open on the turn-based stage gives back what was offered', () {
    var s = freshPet();
    s = levelUp(s, 3, t0);
    var now = t0 + hourMs;
    s = finishVq01(s, now);
    now += 3 * hourMs;
    (s, now) = doDiscoveries(s, 2, now);
    s = must(q.acceptStoryQuest(s, 'eq01', now));
    s = sync(s, walkAt(now + minMs, 1600, 'eq01'), now + 2 * hourMs).state;
    now += 2 * hourMs;
    // a save from before: the tart already offered, the encounter unfinished
    final j = s.toJson();
    (j['trails'] as Map)['encounter'] = {
      'quest': 'eq01', 'creature': 'petalune', 'goal': 'befriend', 'meter': 39, 'max': 100, 'energy': 76, 'energyMax': 100,
      'turn': 1, 'seed': 'old:eq01:1', 'mood': 'curious', 'used': {'sunberry_tart': 1}, 'log': [], 'startedAt': now,
    };
    final old = GameState.fromJson((jsonDecode(jsonEncode(j)) as Map).cast<String, dynamic>());
    expect(old.trails.oldEncounter?.used['sunberry_tart'], 1);
    final r = tr.settleOldEncounter(old, now);
    final back = must(r);
    expect(back.trails.oldEncounter, isNull);
    expect(back.toJson()['trails'], isNot(contains('encounter')));
    expect(g.ownedQty(back, 'sunberry_tart'), 1);
    expect(q.questPhase(back, 'eq01'), 'ruins_ready', reason: 'the job still waits, now on its story floor');
    expect(r.events.single.data['handedIn'], isFalse);
    // settled once: nothing more
    expect(identical(tr.settleOldEncounter(back, now).state, back), isTrue);
  });

  test('old saves: an encounter already won but not yet handed in finishes its job', () {
    var s = freshPet();
    s = levelUp(s, 3, t0);
    var now = t0 + hourMs;
    s = finishVq01(s, now);
    now += 3 * hourMs;
    (s, now) = doDiscoveries(s, 2, now);
    s = must(q.acceptStoryQuest(s, 'eq01', now));
    s = sync(s, walkAt(now + minMs, 1600, 'eq01'), now + 2 * hourMs).state;
    now += 2 * hourMs;
    final j = s.toJson();
    (j['trails'] as Map)['encounter'] = {
      'quest': 'eq01', 'creature': 'petalune', 'goal': 'befriend', 'seed': 'old:eq01:1', 'used': <String, int>{}, 'done': 'success',
    };
    (j['trails'] as Map)['companions'] = {'petalune': {'since': now, 'encounters': 0}};
    final old = GameState.fromJson((jsonDecode(jsonEncode(j)) as Map).cast<String, dynamic>());
    final coins = balance(old);
    final r = tr.settleOldEncounter(old, now);
    final done = must(r);
    expect(q.questPhase(done, 'eq01'), 'completed');
    expect(balance(done), coins + 150);
    expect(r.events.any((e) => e.type == 'old_encounter_settled' && e.data['handedIn'] == true), isTrue);
    expect(done.trails.oldEncounter, isNull);
  });

  test('Tangled Lumen: a Hollow is restored (Instability to 0); Glowleaf is required and Light hits harder', () {
    var s = freshPet();
    s = levelUp(s, 4, t0);
    var now = t0 + hourMs;
    s = finishVq01(s, now);
    now += 3 * hourMs;
    (s, now) = doDiscoveries(s, 2, now);
    s = must(q.acceptStoryQuest(s, 'eq01', now));
    s = sync(s, walkAt(now + minMs, 1600, 'eq01'), now + 2 * hourMs).state;
    now += 2 * hourMs;
    s = must(sf.wildsStoryDone(s, 'eq01', now));
    // hq01 (the cottage) is also a prerequisite
    expect(q.questPhase(s, 'eq02'), 'locked');
    s = s.copy();
    s.story.questStates['hq01'] = doneState(now, resolved: 3000);
    s.story.flags['cottage_restored'] = true;
    expect(q.questPhase(s, 'eq02'), 'available');
    expect(q.npcConversation(s, 'npc_mira', now).start, 'EQ02_M00');
    s = must(q.acceptStoryQuest(s, 'eq02', now));
    s = sync(s, walkAt(now + minMs, 2100, 'eq02'), now + 2 * hourMs).state;
    now += 2 * hourMs;
    expect(q.nextStep(s, 'eq02').kind, 'gather');
    expect(sf.storyFloorAt(s, 3), isNull, reason: 'the Glowleaf first');
    s = give(s, 'glowleaf', 2);
    expect(q.nextStep(s, 'eq02').kind, 'encounter');
    expect(sf.storyFloorAt(s, 3)?.beat, 'sprout');
    // the Hollow Sprout calmed on the floor: restored, and the job hands in
    s = must(sf.wildsStoryDone(s, 'eq02', now));
    expect(g.ownedQty(s, 'glowleaf'), 0, reason: 'the Glowleaf poultice was used');
    expect(s.story.flags['sprout_restored'], isTrue);
    expect(s.trails.restored['hollow_sprout'], now);
    expect(s.trails.stat('restored'), 1);
    expect(g.ownedQty(s, 'lumen_shard') >= 3, isTrue);
    // the Lantern Tonic recipe only appears once the sprout is restored
    final before = s.copy();
    before.story.flags['sprout_restored'] = false;
    before.story.flags['apothecary_unlocked'] = true;
    s = s.copy();
    s.story.flags['apothecary_unlocked'] = true;
    GameState setAlch(GameState st) {
      st = st.copy();
      st.home.skills['alchemy'] = 1000;
      return st;
    }

    expect(h.recipeView(setAlch(before), 'lantern_tonic').known, isFalse);
    expect(h.recipeView(setAlch(before), 'lantern_tonic').needsStory, isTrue);
    expect(h.recipeView(setAlch(s), 'lantern_tonic').known, isTrue);
    var s2 = give(give(setAlch(s), 'glowleaf', 1), 'sunberry', 2);
    s2 = must(h.craft(s2, 'lantern_tonic', 'good', now));
    expect(g.ownedQty(s2, 'lantern_tonic'), 1);
    expect(g.ownedQty(s2, 'lumen_shard'), g.ownedQty(s, 'lumen_shard') - 1);
  });

  test('The Forgotten Sentinel: winning with every Lantern Tonic spent still finishes the quest', () {
    var s = freshPet();
    s = levelUp(s, 6, t0);
    final now = t0 + hourMs;
    s = s.copy();
    for (final id in ['vq01', 'vq02', 'vq03', 'hq01', 'eq01', 'eq02']) {
      s.story.questStates[id] = doneState(now, seen: true);
      s.story.claimedRewards.add(id);
    }
    for (final f in ['lamp_lit', 'waystone_revealed', 'waystone_restored', 'cottage_restored', 'petalune_befriended', 'sprout_restored']) {
      s.story.flags[f] = true;
    }
    s = must(q.markNpcMet(s, 'waystone_map'));
    s = must(q.acceptStoryQuest(s, 'eq03', now));
    s = sync(s, walkAt(now + minMs, 3100, 'eq03'), now + 2 * hourMs).state;
    s = give(s, 'lantern_tonic', 1);
    expect(sf.storyFloorAt(s, 5)?.beat, 'sentinel');
    // the only tonic drunk in the fight (its light breaks the Sentinel's shield)
    s = must(w.wildsDrink(s, 'lantern_tonic', now + 2 * hourMs));
    expect(g.ownedQty(s, 'lantern_tonic'), 0);
    // the gate accepts the tonic already spent on it: no "you still need 1 more Lantern Tonic"
    s = must(sf.wildsStoryDone(s, 'eq03', now + 3 * hourMs, spent: const {'lantern_tonic': 1}));
    expect(q.questPhase(s, 'eq03'), 'completed');
    expect(g.ownedQty(s, 'lantern_tonic'), 0);
  });

  test('The Forgotten Sentinel: after the Waystone, a long restore with a second phase; the relic and title', () {
    var s = freshPet();
    s = levelUp(s, 6, t0);
    final now = t0 + hourMs;
    s = s.copy();
    // shortcut the prerequisites
    for (final id in ['vq01', 'vq02', 'vq03', 'hq01', 'eq01', 'eq02']) {
      s.story.questStates[id] = doneState(now, seen: true);
      s.story.claimedRewards.add(id);
    }
    for (final f in ['lamp_lit', 'waystone_revealed', 'waystone_restored', 'cottage_restored', 'petalune_befriended', 'sprout_restored']) {
      s.story.flags[f] = true;
    }
    s.trails.companions['petalune'] = CompanionState(since: now - dayMs);
    // Alder shows the map first, then offers the quest
    expect(q.npcConversation(s, 'npc_alder', now).start, 'ALD_MAP00');
    s = must(q.markNpcMet(s, 'waystone_map'));
    expect(q.questPhase(s, 'eq03'), 'available');
    expect(q.npcConversation(s, 'npc_alder', now).start, 'EQ03_A00');
    s = must(q.acceptStoryQuest(s, 'eq03', now));
    s = sync(s, walkAt(now + minMs, 3100, 'eq03'), now + 2 * hourMs).state;
    expect(q.questPhase(s, 'eq03'), 'gate_ready');
    expect(q.nextStep(s, 'eq03').kind, 'gather'); // the Lantern Tonic
    s = give(s, 'lantern_tonic', 2);
    expect(q.nextStep(s, 'eq03').place, 'gate');
    expect(tr.encounterDefs['eq03']!.scene, 'sentinel_gate');
    expect(sf.storyFloorAt(s, 5)?.quest, 'eq03');
    // one tonic drunk in the fight, the other taken at the gate
    s = must(w.wildsDrink(s, 'lantern_tonic', now + 2 * hourMs));
    final coins = balance(s);
    s = must(sf.wildsStoryDone(s, 'eq03', now + 3 * hourMs));
    expect(q.questPhase(s, 'eq03'), 'completed');
    expect(g.ownedQty(s, 'lantern_tonic'), 0, reason: 'one tonic used in the encounter, one at the gate');
    expect(g.ownedQty(s, 'ancient_relic'), 1);
    expect(balance(s), coins + 300);
    expect(s.story.titleUnlocks, contains('trailwarden'));
    expect(s.story.flags['sentinel_restored'], isTrue);
    expect(q.npcConversation(s, 'npc_alder', now + 3 * hourMs).start, 'EQ03_A04');
    // the relic can be placed in the nest like any side decoration
    s = must(g.placeDecoration(s, 'ancient_relic', 'left'));
    expect(s.placements['left'], 'ancient_relic');
  });

  test('story lines stay well-formed with the new quests', () {
    final s = freshPet();
    for (final id in q.lines.keys) {
      expect(q.lineText(s, id, t0, petName: 'Ember'), isA<String>(), reason: id);
    }
    for (final npc in ['npc_pip', 'npc_mira', 'npc_alder', 'npc_bram']) {
      final c = q.npcConversation(s, npc, t0);
      expect(q.lines.containsKey(c.start), isTrue, reason: '$npc opens with a real line (${c.start})');
    }
  });
}
