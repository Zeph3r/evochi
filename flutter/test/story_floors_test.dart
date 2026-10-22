// Story floors (game/wilds/story_floors.dart and the beats in features/wilds/wilds_combat.dart): a Trail
// Guild job's place waits at its floor only while the job is open; a treat for Petalune; the hand-in once
// the beat is done (and only once); Petalune's trust; the Hollow Sprout; Petalune at your side afterwards.

import 'dart:ui' show Rect;

import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/features/wilds/wilds_combat.dart';
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/story/story.dart' as q;
import 'package:evochi/game/wilds/story_floors.dart' as sf;
import 'package:flutter_test/flutter_test.dart';

const tzName = 'America/New_York';
final t0 = DateTime.utc(2026, 10, 19, 14).millisecondsSinceEpoch;
const dt = 1 / 60;

GameState must(g.ActionResult r) {
  expect(r.error, isNull, reason: r.error);
  return r.state;
}

GameState freshPet() {
  var s = GameState.fresh(t0, tzName);
  s = g.startGuest(s, t0, tzName).state;
  s = g.setConnection(s, 'demo', t0).state;
  return must(g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: t0));
}

GameState give(GameState s, String id, int n) {
  final c = s.copy();
  g.grantItem(c, id, n, 'test', t0);
  return c;
}

QuestState _state(String phase) => QuestState.fromJson({
      'phase': phase,
      'acceptedAt': t0 - hourMs,
      'acceptedDay': dayKey(t0, tzName),
      'resolvedSteps': 1500,
    });

/// The job taken and walked: its hand-in waits at the place.
GameState ready(GameState s, String qid) {
  final c = s.copy();
  final (phase, clue) = switch (qid) { 'eq01' => ('ruins_ready', 'q_mossy_clue'), 'eq02' => ('ruins_ready', 'q_lumen_trace'), _ => ('gate_ready', 'q_old_trail_map') };
  for (final dep in q.storyQuests[qid]!.dependsOn) {
    c.story.questStates[dep] = QuestState.fromJson({'phase': 'completed', 'acceptedAt': t0 - 2 * hourMs, 'acceptedDay': dayKey(t0, tzName), 'resolvedSteps': 1000, 'completedAt': t0 - hourMs});
  }
  c.story.questStates[qid] = _state(phase);
  c.story.questPouch[clue] = 1;
  return c;
}

RaidGround meadow() => RaidGround(wet: (x, z) => false, blocks: const [], bounds: const Rect.fromLTRB(-400, -400, 400, 400));
Actor petAt(double x, double z) => Actor(id: 'pet', kind: 'pet', team: Team.party, x: x, z: z, radius: 9, health: 100000)..face(0, -1);

void run(Raid r, double secs, [RaidInput Function()? inp]) {
  for (var i = 0; i < secs / dt; i++) {
    r.tick(dt, inp?.call() ?? RaidInput());
  }
}

void main() {
  setUpAll(ensureTimeZones);

  group('the save', () {
    test('a job\'s place waits at its floor only while the job is open', () {
      var s = freshPet();
      expect(sf.storyFloorAt(s, 3), isNull);
      s = ready(s, 'eq01');
      expect(sf.storyFloorAt(s, 3)?.quest, 'eq01');
      expect(sf.storyFloorAt(s, 2), isNull);
      expect(sf.storyFloorOpen(s, 'eq01'), isTrue);
      // done: the floor is an ordinary one again
      s = must(sf.wildsStoryDone(s, 'eq01', t0));
      expect(sf.storyFloorAt(s, 3), isNull);
    });

    test('the Sprout\'s floor needs the Glowleaf in the Bag; the Sentinel\'s gate is not a Wilds floor yet', () {
      var s = ready(freshPet(), 'eq02');
      expect(sf.storyFloorAt(s, 3), isNull);
      s = give(s, 'glowleaf', 2);
      expect(sf.storyFloorAt(s, 3)?.quest, 'eq02');
      expect(sf.storyFloorAt(ready(freshPet(), 'eq03'), 5), isNull);
    });

    test('earning Petalune\'s trust finishes the job once: a companion, the quest\'s reward, no second payout', () {
      var s = ready(freshPet(), 'eq01');
      final coins0 = g.balanceOf(s);
      final res = sf.wildsStoryDone(s, 'eq01', t0);
      s = must(res);
      expect(q.questPhase(s, 'eq01'), 'completed');
      expect(s.trails.companions.containsKey('petalune'), isTrue);
      expect(sf.petaluneWithYou(s), isTrue);
      expect(res.events.any((e) => e.type == 'companion_joined'), isTrue);
      expect(res.events.any((e) => e.type == 'story_completed'), isTrue);
      expect(g.balanceOf(s) - coins0, q.storyQuests['eq01']!.rewards.coins);
      final again = sf.wildsStoryDone(s, 'eq01', t0 + 1000);
      expect(again.events.single.type, 'story_already');
      expect(g.balanceOf(again.state), g.balanceOf(s));
    });

    test('restoring the Sprout takes the Glowleaf (or what of it was used on the floor) and remembers it', () {
      var s = give(ready(freshPet(), 'eq02'), 'glowleaf', 2);
      s = must(sf.wildsStoryDone(s, 'eq02', t0));
      expect(q.questPhase(s, 'eq02'), 'completed');
      expect(g.ownedQty(s, 'glowleaf'), 0);
      expect(s.trails.restored.containsKey('hollow_sprout'), isTrue);
      expect(s.trails.companions.containsKey('hollow_sprout'), isFalse);
    });

    test('a treat leaves the Bag; the ones Petalune loves warm it half again as much', () {
      var s = freshPet();
      expect(sf.wildsOffer(s, 'sunberry_tart', t0).error, 'not_owned');
      s = give(give(s, 'sunberry_tart', 1), 'berry_snack', 2);
      expect(sf.treatsFor(s).first, 'sunberry_tart');
      final a = sf.wildsOffer(s, 'sunberry_tart', t0);
      expect(a.events.single.data['trust'], 30);
      expect(g.ownedQty(a.state, 'sunberry_tart'), 0);
      final b = sf.wildsOffer(s, 'berry_snack', t0);
      expect(b.events.single.data['trust'], 20);
      expect(sf.wildsOffer(s, 'leaf_scarf', t0).error, isNotNull);
    });
  });

  group('Petalune\'s trust', () {
    Raid ruins() => Raid(ground: meadow(), pet: petAt(0, 40), storyBeat: 'trust', storyX: 0, storyZ: 0, seed: 3);

    test('being near and gentle grows it, but only so far; a hum and a treat take it the rest', () {
      final r = ruins();
      expect(r.petalune, isNotNull);
      expect(r.foes, isEmpty);
      run(r, 40);
      expect(r.trust, closeTo(Raid.trustDrift, 0.01));
      expect(r.storyDone, isFalse);
      expect(r.hum(), isTrue);
      expect(r.hum(), isFalse); // a breath between hums
      expect(r.trust, greaterThan(Raid.trustDrift));
      r.treat(30);
      expect(r.trust, 100);
      expect(r.storyDone, isTrue);
      expect(r.petalune!.calm, isTrue);
      expect(r.events.any((e) => e.type == 'story_done'), isTrue);
    });

    test('the ruins are a haven: a Hollow creature gives up on your Evochi there while Petalune is wary', () {
      final r = Raid(
          ground: meadow(),
          pet: petAt(0, 30),
          storyBeat: 'trust',
          storyX: 0,
          storyZ: 0,
          spawns: const [FoeSpawn('a', 'thornling', 'z', 0, 100)],
          seed: 3);
      final f = r.foes.first..face(0, -1);
      final hp = r.pet.hp;
      run(r, 8);
      expect(r.pet.hp, hp);
      expect(f.distTo(0, 0), greaterThan(Raid.havenR * 0.8));
    });

    test('an attack near it startles it: trust drops', () {
      final r = ruins()..trust = 25;
      r.press('attack');
      run(r, 0.5, () => RaidInput()..attack = true);
      expect(r.trust, lessThan(25));
    });

    test('once it trusts you it follows, and Petal Hush mends your Evochi in a fight', () {
      final r = Raid(
          ground: meadow(), pet: petAt(0, 40), companion: true, spawns: const [FoeSpawn('a', 'thornling', 'z', 0, 0)], seed: 3);
      final pl = r.petalune!;
      expect(pl.calm, isTrue);
      r.pet.hp = r.pet.maxHp - 500;
      r.foes.first
        ..maxHp = 100000
        ..hp = 100000
        ..face(0, 1);
      // walk off: it keeps up
      run(r, 2, () => RaidInput()..mx = 1);
      expect(pl.dist(r.pet), lessThan(60));
      final before = r.pet.hp;
      run(r, 20);
      expect(r.events.any((e) => e.type == 'hush') || r.pet.hp > before, isTrue);
    });
  });

  group('the Hollow Sprout', () {
    test('it fights from the ruins; calmed, it is restored and stays', () {
      final r = Raid(ground: meadow(), pet: petAt(0, 80), storyBeat: 'sprout', storyX: 0, storyZ: 0, seed: 5);
      final sp = r.foes.singleWhere((f) => f.kind == 'hollow_sprout');
      expect(r.foeTotal, 1);
      run(r, 6);
      expect(r.marks.isNotEmpty || r.events.any((e) => e.type == 'lash' || e.type == 'thorns'), isTrue, reason: 'it attacks');
      r.calmAllForTesting();
      run(r, 3);
      expect(r.storyDone, isTrue);
      expect(r.foes.contains(sp), isTrue, reason: 'restored, it stays among the ruins');
      expect(r.calmed, 1);
    });
  });
}
