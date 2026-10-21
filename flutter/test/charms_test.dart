// Charms (game/wilds/charms.dart and the fight in features/wilds/wilds_combat.dart): wearing one, ranks
// that grow with play, duplicates turning into progress, the two set from rare finds, the Caravan's weekly
// charms for Glimmer, and what a worn charm does in a fight.

import 'dart:ui';

import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/features/wilds/wilds_combat.dart';
import 'package:evochi/game/economy/economy.dart' as e;
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/wilds/charms.dart' as ch;
import 'package:evochi/game/wilds/wilds.dart' as w;
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

RaidGround meadow() => RaidGround(wet: (x, z) => false, blocks: const [], bounds: const Rect.fromLTRB(-400, -400, 400, 400));
Actor petAt(double x, double z, {double hp = 100000}) => Actor(id: 'pet', kind: 'pet', team: Team.party, x: x, z: z, radius: 9, health: hp)..face(0, -1);

void main() {
  setUpAll(ensureTimeZones);

  group('wearing and growing', () {
    test('only an owned charm can be worn; one at a time; it can come off', () {
      var s = freshPet();
      expect(ch.wearCharm(s, 'sap_locket').error, 'not_owned');
      s = give(s, 'sap_locket', 1);
      s = give(s, 'static_acorn', 1);
      s = must(ch.wearCharm(s, 'sap_locket'));
      expect(ch.wornCharm(s), 'sap_locket');
      s = must(ch.wearCharm(s, 'static_acorn'));
      expect(ch.wornCharm(s), 'static_acorn');
      s = must(ch.wearCharm(s, ''));
      expect(ch.wornCharm(s), isNull);
    });

    test('a worn charm grows with the creatures calmed: rank II at 25, rank III at 75', () {
      var s = give(freshPet(), 'emberfang_charm', 1);
      s = must(ch.wearCharm(s, 'emberfang_charm'));
      expect(ch.charmRank(s, 'emberfang_charm'), 1);
      var r = must(w.wildsBank(s, 'run1', 10, const {}, t0, calmed: 24));
      expect(ch.charmRank(r, 'emberfang_charm'), 1);
      final res = w.wildsBank(r, 'run2', 0, const {}, t0, calmed: 1);
      expect(res.events.any((x) => x.type == 'charm_rank' && x.data['rank'] == 2), isTrue);
      r = must(res);
      r = must(w.wildsBank(r, 'run3', 5, const {}, t0, calmed: 60));
      expect(ch.charmRank(r, 'emberfang_charm'), 3);
      expect(ch.charmNext(r, 'emberfang_charm'), isNull);
    });

    test('a charm already owned that drops again becomes progress, not a second copy', () {
      var s = give(freshPet(), 'dazzle_pebble', 1);
      final res = w.wildsBank(s, 'run1', 5, const {'dazzle_pebble': 1, 'lumen_shard': 1}, t0);
      s = must(res);
      expect(g.ownedQty(s, 'dazzle_pebble'), 1);
      expect(ch.charmXp(s, 'dazzle_pebble'), ch.charmDupeXp);
      expect(g.ownedQty(s, 'lumen_shard'), greaterThan(0));
      expect(res.events.any((x) => x.type == 'charm_dupe'), isTrue);
    });

    test('the Prism and Starseed charms are set from their rare finds', () {
      var s = freshPet();
      expect(ch.setCharm(s, 'prism_charm', t0).error, 'charm_needs');
      s = give(give(s, 'prism_scale', 1), 'lumen_shard', 2);
      s = must(ch.setCharm(s, 'prism_charm', t0));
      expect(ch.ownsCharm(s, 'prism_charm'), isTrue);
      expect(g.ownedQty(s, 'prism_scale'), 0);
      expect(ch.wornCharm(s), 'prism_charm'); // the first charm goes straight on
      expect(ch.setCharm(s, 'prism_charm', t0).error, 'owned');
    });
  });

  group('the Caravan', () {
    test('sells two charms a week for Glimmer, one each, never one you own', () {
      var s = freshPet();
      final week = e.weekCharms(s, t0);
      expect(week.length, 2);
      expect(week.every((o) => ch.charmDefs[o.itemId]!.sold), isTrue);
      // the same two all week
      expect(e.weekCharms(s, t0 + 2 * dayMs).map((o) => o.itemId), week.map((o) => o.itemId));
      final o = week.first;
      s = must(e.grantGlimmerTest(s, o.price, t0));
      s = must(e.buyCaravan(s, o.id, 'r1', t0));
      expect(ch.ownsCharm(s, o.itemId), isTrue);
      expect(e.glimmerOf(s), 0);
      s = must(e.grantGlimmerTest(s, o.price, t0));
      expect(e.buyCaravan(s, o.id, 'r2', t0).error, 'owned');
    });
  });

  group('in a fight', () {
    Raid duel(String charm, {int rank = 3, List<FoeSpawn>? foes}) {
      final r = Raid(
          ground: meadow(),
          pet: petAt(0, 34),
          spawns: foes ?? const [FoeSpawn('a', 'thornling', 'z', 0, 16)],
          charm: charm,
          charmRank: rank,
          seed: 4);
      for (final f in r.foes) {
        f
          ..maxHp = 5000
          ..hp = 5000
          ..face(0, 1);
      }
      return r;
    }

    void swing(Raid r, double secs) {
      for (var i = 0; i < secs / dt; i++) {
        r.tick(dt, RaidInput()..attack = true);
      }
    }

    test('the Emberfang sets foes alight, the Frostmint Bell chills them', () {
      final a = duel('emberfang_charm');
      var burnt = false;
      for (var i = 0; i < 60 * 4 && !burnt; i++) {
        a.tick(dt, RaidInput()..attack = true);
        burnt = a.foes.first.burnT > 0;
      }
      expect(burnt, isTrue);
      final b = duel('frostbell_charm');
      var chilled = false;
      for (var i = 0; i < 60 * 4 && !chilled; i++) {
        b.tick(dt, RaidInput()..attack = true);
        chilled = b.foes.first.chillT > 0;
      }
      expect(chilled, isTrue);
    });

    test('the Sap Locket heals as you hit', () {
      final r = duel('sap_locket');
      r.pet.hp = r.pet.maxHp - 50;
      r.foes.first.stun = 4;
      final before = r.pet.hp;
      swing(r, 1.5);
      expect(r.pet.hp, greaterThan(before));
    });

    test('the Prism Charm splits the Bolt into three', () {
      // far off, so the bolts are still in the air when we count them
      final r = duel('prism_charm', foes: const [FoeSpawn('a', 'thornling', 'z', 0, -150)]);
      r.press('bolt');
      for (var i = 0; i < 40 && r.shots.isEmpty; i++) {
        r.tick(dt, RaidInput());
      }
      expect(r.shots.where((s) => s.kind == ShotKind.bolt).length, 3);
      expect(r.shots.where((s) => s.prism).length, 2);
    });

    test('the Starseed Charm leaves a healing bloom where a creature is calmed', () {
      final r = duel('starseed_charm');
      final f = r.foes.first
        ..maxHp = 10
        ..hp = 10;
      for (var i = 0; i < 60 * 3 && !f.calm; i++) {
        r.tick(dt, RaidInput()..attack = true);
      }
      expect(f.calm, isTrue);
      expect(r.pickups.any((p) => p.kind == 'bloom' && p.amount == 24), isTrue);
    });

    test('no charm, no change: the fight is the same as before', () {
      final r = Raid(ground: meadow(), pet: petAt(0, 34), spawns: const [FoeSpawn('a', 'thornling', 'z', 0, 16)], seed: 4);
      expect(r.charm, isNull);
    });
  });
}
