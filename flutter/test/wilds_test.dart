// The Lumen Wilds: the fight (features/wilds/wilds_combat.dart) and what it saves (game/wilds/wilds.dart).

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/features/wilds/wilds_combat.dart';
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/wilds/wilds.dart' as w;
import 'package:flutter_test/flutter_test.dart';

const tzName = 'America/New_York';
final t0 = DateTime.utc(2026, 10, 5, 14).millisecondsSinceEpoch;

GameState freshPet() {
  var s = GameState.fresh(t0, tzName);
  s = g.startGuest(s, t0, tzName).state;
  s = g.setConnection(s, 'demo', t0).state;
  final r = g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: t0);
  expect(r.error, isNull);
  return r.state;
}

/// An open meadow: no water, the given round blocks.
RaidGround meadow([List<(double, double, double)> blocks = const []]) =>
    RaidGround(wet: (x, z) => false, blocks: blocks, bounds: const Rect.fromLTRB(-400, -800, 400, 800));

Actor petAt(double x, double z, {double hp = 120}) =>
    Actor(id: 'pet', kind: 'pet', team: Team.party, x: x, z: z, radius: 9, health: hp)..face(0, -1);

const dt = 1 / 60;

void run(Raid r, double secs, [RaidInput Function(Raid)? input]) {
  final n = (secs / dt).round();
  for (var i = 0; i < n; i++) {
    r.tick(dt, input?.call(r) ?? RaidInput());
  }
}

void main() {
  group('foes', () {
    test('a Thornling notices your Evochi, and its pack hears it', () {
      final r = Raid(ground: meadow(), pet: petAt(0, 34), spawns: const [
        FoeSpawn('a', 'thornling', 'fern', 0, 0),
        FoeSpawn('b', 'thornling', 'fern', 60, -20),
      ]);
      // facing it, near: seen within a moment
      r.foes[0].face(0, 1);
      run(r, 0.6);
      expect(r.foes.every((f) => f.target == r.pet), isTrue);
      expect(r.events.any((e) => e.type == 'alert'), isTrue);
    });

    test('a pack takes turns: never more than two swing at your Evochi at once', () {
      final r = Raid(ground: meadow(), pet: petAt(0, 0, hp: 100000), spawns: [
        for (var i = 0; i < 4; i++) FoeSpawn('t$i', 'thornling', 'fern', i * 30.0 - 45, -50),
      ]);
      for (final f in r.foes) {
        f.face(0, 1);
      }
      var most = 0;
      var attacked = 0;
      for (var i = 0; i < 60 * 14; i++) {
        r.tick(dt, RaidInput());
        final n = r.foes.where((f) => f.target == r.pet && (f.st == FoeState.windup || f.st == FoeState.strike)).length;
        if (n > most) most = n;
        if (n > 0) attacked++;
      }
      expect(most, lessThanOrEqualTo(2));
      expect(attacked, greaterThan(60)); // they do attack
      expect(r.pet.hp, lessThan(r.pet.maxHp));
    });

    test('a rolling Thornling that hits a tree is knocked silly', () {
      final r = Raid(ground: meadow([(0.0, -40.0, 8.0)]), pet: petAt(200, 200), spawns: const [FoeSpawn('a', 'thornling', 'fern', 0, 0)]);
      final f = r.foes.first
        ..target = r.pet
        ..st = FoeState.strike
        ..move = 'roll'
        ..ax = 0
        ..az = -1
        ..travelMax = 74
        ..t = 0;
      run(r, 0.5);
      expect(f.st, FoeState.stagger);
      expect(r.events.any((e) => e.type == 'bonk'), isTrue);
    });

    test('a dodge roll slips through a Thornling\'s roll', () {
      final r = Raid(ground: meadow(), pet: petAt(0, -40), spawns: const [FoeSpawn('a', 'thornling', 'fern', 0, 0)]);
      final f = r.foes.first
        ..target = r.pet
        ..st = FoeState.strike
        ..move = 'roll'
        ..ax = 0
        ..az = -1
        ..travelMax = 74
        ..t = 0;
      final before = r.pet.hp;
      final dodge = RaidInput()..dodge = true;
      r.tick(dt, dodge);
      run(r, 0.4);
      expect(r.pet.hp, before);
      expect(f.st == FoeState.strike || f.st == FoeState.recover, isTrue);
      // and standing still, it lands
      final r2 = Raid(ground: meadow(), pet: petAt(0, -40), spawns: const [FoeSpawn('a', 'thornling', 'fern', 0, 0)]);
      r2.foes.first
        ..target = r2.pet
        ..st = FoeState.strike
        ..move = 'roll'
        ..ax = 0
        ..az = -1
        ..travelMax = 74
        ..t = 0;
      run(r2, 0.4);
      expect(r2.pet.hp, lessThan(before));
    });

    test('a Sporecap keeps its distance when you close in', () {
      final r = Raid(ground: meadow(), pet: petAt(0, 40, hp: 10000), spawns: const [FoeSpawn('s', 'sporecap', 'ring', 0, 0)]);
      final f = r.foes.first
        ..target = r.pet
        ..st = FoeState.engage
        ..cd = 99
        ..cd2 = 99;
      final d0 = f.dist(r.pet);
      run(r, 1.5);
      expect(f.dist(r.pet), greaterThan(d0 + 10));
    });

    test('a Sporecap lobs where you are heading, and the landing slows you', () {
      final r = Raid(ground: meadow(), pet: petAt(0, 90, hp: 10000), spawns: const [FoeSpawn('s', 'sporecap', 'ring', 0, 0)]);
      r.foes.first
        ..target = r.pet
        ..st = FoeState.engage
        ..cd = 0;
      var spored = false;
      for (var i = 0; i < 60 * 6; i++) {
        r.tick(dt, RaidInput());
        if (r.pet.slowT > 0) spored = true;
      }
      expect(r.events.any((e) => e.type == 'spore_lob'), isTrue);
      expect(spored, isTrue);
    });

    test('pulled too far from its clearing, a foe gives up and goes home to heal', () {
      final r = Raid(ground: meadow(), pet: petAt(0, 60, hp: 10000), spawns: const [FoeSpawn('a', 'thornling', 'fern', 0, 0)]);
      final f = r.foes.first
        ..target = r.pet
        ..st = FoeState.engage
        ..hp = 20;
      r.pet.z = 400; // you ran off
      run(r, 0.2);
      expect(f.st, FoeState.home);
      run(r, 6);
      expect(f.st, FoeState.idle);
      expect(f.hp, f.maxHp);
    });

    test('a defeated foe is calmed, not killed: it drops into the satchel and trots off', () {
      final r = Raid(ground: meadow(), pet: petAt(0, 20), spawns: const [FoeSpawn('a', 'thornling', 'fern', 0, 0)], zones: const [ZoneDef('fern', 'Fern Clearing', 0, 0, 40)]);
      final f = r.foes.first..hp = 1;
      final atk = RaidInput()..attack = true;
      r.pet.face(0, -1);
      r.tick(dt, atk);
      run(r, 0.3);
      expect(f.calm, isTrue);
      expect(r.coins, greaterThan(0));
      expect(r.cleared, contains('fern'));
      expect(r.events.any((e) => e.type == 'zone'), isTrue);
      run(r, 4);
      expect(r.foes, isEmpty); // gone into the wood
    });
  });

  group('the guardian', () {
    Raid arena({double petHp = 100000, bool sher = false}) {
      final r = Raid(
        ground: meadow([(-50.0, -420.0, 6.5), (40.0, -430.0, 6.5)]),
        pet: petAt(-14, -330, hp: petHp),
        sher: sher ? (Actor(id: 'sher', kind: 'sher', team: Team.party, x: 0, z: -320, radius: 7, health: 150)) : null,
        bossDef: const BossDef(x: -10, z: -432, ax: -14, az: -398, ar: 74, wall: [(-24.0, -320.0), (-6.0, -330.0)], summon: [(-74.0, -408.0), (46.0, -408.0)]),
      );
      if (sher) r.join();
      return r;
    }

    test('wakes when you step into its arena; the brambles close behind you', () {
      final r = arena();
      run(r, 0.5);
      expect(r.bossState, BossState.dormant);
      r.pet.z = -380;
      run(r, 0.2);
      expect(r.bossState, BossState.intro);
      expect(r.wallActive, isTrue);
      run(r, 2.5);
      expect(r.bossState, BossState.fight);
    });

    test('roars at 60% and 30%, calling two Thornlings each time', () {
      final r = arena();
      r.pet.z = -380;
      run(r, 3);
      final b = r.boss!;
      b.hp = b.maxHp * 0.61;
      final atk = RaidInput()..attack = true;
      // hit it until the roar
      for (var i = 0; i < 400 && b.stage < 2; i++) {
        r.pet
          ..x = b.x
          ..z = b.z + 28;
        r.pet.face(b.x - r.pet.x, b.z - r.pet.z);
        r.tick(dt, i % 20 == 0 ? (RaidInput()..attack = true) : RaidInput());
      }
      expect(b.stage, 2);
      run(r, 1.0);
      expect(r.foes.where((f) => f.summoned).length, 2);
      b.hp = b.maxHp * 0.25;
      r.pet.face(b.x - r.pet.x, b.z - r.pet.z);
      r.tick(dt, atk);
      run(r, 0.2);
      // a hit below 30% enrages it (when one lands)
      if (b.stage < 3) {
        b.hp = b.maxHp * 0.31;
        b.st = FoeState.engage;
        for (var i = 0; i < 400 && b.stage < 3; i++) {
          r.pet
            ..x = b.x
            ..z = b.z + 26;
          b.hp = math.min(b.hp, b.maxHp * 0.31);
          r.pet.face(b.x - r.pet.x, b.z - r.pet.z);
          r.tick(dt, i % 20 == 0 ? (RaidInput()..attack = true) : RaidInput());
        }
      }
      expect(b.stage, 3);
      run(r, 1.6);
      expect(r.foes.where((f) => f.summoned).length, 4);
    });

    test('picks different moves, telegraphs each, and reads a kiting player', () {
      final r = arena();
      r.pet.z = -380;
      run(r, 2.5);
      final b = r.boss!;
      final moves = <String>{};
      // you keep your distance, circling far
      for (var i = 0; i < 60 * 30; i++) {
        final a = i * dt * 0.6;
        r.pet
          ..x = -14 + 62 * math.cos(a)
          ..z = -398 + 62 * math.sin(a);
        r.tick(dt, RaidInput());
        if (b.st == FoeState.windup) moves.add(b.move);
      }
      expect(moves, containsAll(<String>['charge', 'roots']));
      expect(b.kite, greaterThan(0.1));
    });

    test('a charge into a pillar leaves it dazed', () {
      final r = arena();
      r.pet.z = -380;
      run(r, 2.5);
      final b = r.boss!
        ..x = -50
        ..z = -360
        ..st = FoeState.strike
        ..move = 'charge'
        ..ax = 0
        ..az = -1
        ..travelMax = 200
        ..t = 0;
      run(r, 0.6);
      expect(b.st, FoeState.stagger);
      expect(r.events.any((e) => e.type == 'crash'), isTrue);
    });

    test('a knockout is an evacuation: back at the trailhead, half the satchel lost, the guardian reset', () {
      final r = arena(petHp: 50);
      r.coins = 9;
      r.items['lumen_shard'] = 1;
      r.pet.z = -380;
      run(r, 2.5);
      r.boss!.hp = 400;
      for (var i = 0; i < 60 * 40 && r.phase == RaidPhase.explore; i++) {
        r.pet
          ..x = r.boss!.x
          ..z = r.boss!.z + 30;
        r.tick(dt, RaidInput());
      }
      expect(r.phase, RaidPhase.knocked);
      expect(r.events.any((e) => e.type == 'knockout'), isTrue);
      final lost = r.evacuate();
      expect(lost.coinsLost, 5);
      expect(r.coins, 4);
      expect(r.items['lumen_shard'], isNull);
      expect(r.pet.hp, r.pet.maxHp);
      expect((r.pet.x, r.pet.z), (-14.0, -330.0));
      expect(r.boss!.hp, r.boss!.maxHp);
      expect(r.bossState, BossState.dormant);
      expect(r.wallActive, isFalse);
    });

    test('calmed: victory, the brambles part, its summons calm too', () {
      final r = arena();
      r.pet.z = -380;
      run(r, 3);
      final b = r.boss!;
      b.hp = b.maxHp * 0.5;
      for (var i = 0; i < 400 && b.stage < 2; i++) {
        r.pet
          ..x = b.x
          ..z = b.z + 28;
        r.pet.face(b.x - r.pet.x, b.z - r.pet.z);
        r.tick(dt, i % 20 == 0 ? (RaidInput()..attack = true) : RaidInput());
      }
      run(r, 1.2);
      b.hp = 1;
      b.st = FoeState.engage;
      for (var i = 0; i < 300 && !b.calm; i++) {
        r.pet
          ..x = b.x
          ..z = b.z + 26;
        r.pet.face(b.x - r.pet.x, b.z - r.pet.z);
        r.tick(dt, i % 15 == 0 ? (RaidInput()..attack = true) : RaidInput());
      }
      expect(b.calm, isTrue);
      expect(r.bossState, BossState.calm);
      expect(r.events.any((e) => e.type == 'victory'), isTrue);
      expect(r.wallActive, isFalse);
      expect(r.foes.where((f) => f.summoned && !f.calm), isEmpty);
    });

    test('Sher fights beside you and steps out of what is about to land', () {
      final r = arena(sher: true);
      r.pet.z = -380;
      run(r, 3);
      final s = r.sher!;
      final b = r.boss!;
      // a sweep cone right over him
      s
        ..x = b.x
        ..z = b.z + 20;
      r.marks.add(Mark(MarkShape.cone, b.x, b.z, 1.0, r: 54, dx: 0, dz: 1, half: 1.1, owner: b)..t = 0.5);
      final d0 = s.distTo(b.x, b.z);
      run(r, 0.3);
      expect(s.distTo(b.x, b.z), greaterThan(d0 + 6));
    });
  });

  group('the save', () {
    test('Raid HP never touches Vitality, and a run banks once', () {
      final s0 = freshPet();
      final v0 = g.derive(s0, t0).pet!.vitality.vitality;
      final r1 = w.wildsBank(s0, 'run-1', 12, {'lumen_shard': 1}, t0);
      expect(r1.error, isNull);
      expect(g.balanceOf(r1.state) - g.balanceOf(s0), 12);
      expect(g.ownedQty(r1.state, 'lumen_shard'), 1);
      final again = w.wildsBank(r1.state, 'run-1', 12, {'lumen_shard': 1}, t0 + 1000);
      expect(g.balanceOf(again.state), g.balanceOf(r1.state));
      expect(g.ownedQty(again.state, 'lumen_shard'), 1);
      expect(g.derive(again.state, t0).pet!.vitality.vitality, v0);
    });

    test('the first clear rewards once and saves the flag; then a spar rewards once a day', () {
      final s0 = freshPet();
      expect(w.floorCleared(s0, 'thicket'), isFalse);
      final c1 = w.wildsClear(s0, 'thicket', t0);
      expect(w.floorCleared(c1.state, 'thicket'), isTrue);
      expect(g.ownedQty(c1.state, 'briar_heartwood'), 1);
      expect(g.balanceOf(c1.state) - g.balanceOf(s0), 150);
      final retry = w.wildsClear(c1.state, 'thicket', t0 + 500);
      expect(g.balanceOf(retry.state) - g.balanceOf(s0), 150 + 40); // the spar (same day, once)
      final retry2 = w.wildsClear(retry.state, 'thicket', t0 + 900);
      expect(g.balanceOf(retry2.state), g.balanceOf(retry.state));
      expect(g.ownedQty(retry2.state, 'briar_heartwood'), 2);
      final tomorrow = w.wildsClear(retry2.state, 'thicket', t0 + 24 * 3600000);
      expect(g.ownedQty(tomorrow.state, 'briar_heartwood'), 3);
    });

    test('a healing item leaves the Bag when eaten in a fight', () {
      var s = freshPet();
      expect(w.wildsUseHeal(s, 'meadow_tea', t0).error, 'not_owned');
      expect(w.wildsUseHeal(s, 'leaf_scarf', t0).error, 'not_consumable');
      final n0 = g.ownedQty(s, 'berry_snack');
      s = w.wildsSherGift(s, t0).state;
      expect(g.ownedQty(s, 'berry_snack'), n0 + 3);
      expect(g.ownedQty(w.wildsSherGift(s, t0).state, 'berry_snack'), n0 + 3); // once
      expect(w.nextHealItem(s), 'berry_snack');
      expect(w.healItemCount(s), n0 + 3);
      final r = w.wildsUseHeal(s, 'berry_snack', t0);
      expect(g.ownedQty(r.state, 'berry_snack'), n0 + 2);
      expect(w.wildsHealAmount('berry_snack'), greaterThan(20));
    });
  });
}
