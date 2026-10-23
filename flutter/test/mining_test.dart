// Mining's rules (lib/features/village/mining.dart): a node breaks on exactly its hits, its crack
// stages run whole -> chipped -> cracked -> burst, an Obsidian Evochi's edge, and the strike's pose
// returns to rest by the end of its ~480 ms.

import 'package:evochi/core/models/catalog.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/features/village/mining.dart';
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/home/home.dart' as h;
import 'package:evochi/game/mining/mining.dart' as m;
import 'package:flutter_test/flutter_test.dart';

final t0 = DateTime.utc(2026, 10, 5, 14).millisecondsSinceEpoch;

GameState freshPet() {
  var s = GameState.fresh(t0, 'America/New_York');
  s = g.startGuest(s, t0, 'America/New_York').state;
  s = g.setConnection(s, 'demo', t0).state;
  s = g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: t0).state;
  return s;
}

void main() {
  test('copper breaks on the third hit, chipped then cracked on the way', () {
    final n = OreNode('copper', 0, 0);
    expect(n.strike(1, 3), isFalse);
    expect(n.state, 1);
    expect(n.strike(1, 3), isFalse);
    expect(n.state, 2);
    expect(n.strike(1, 3), isTrue);
    expect(n.state, 3);
    expect(n.broken, isTrue);
    n.regrow();
    expect(n.state, 0);
    expect(n.damage, 0);
  });

  test("an Obsidian Evochi's edge: iron in three hits instead of four", () {
    final plain = OreNode('iron', 0, 0), obsidian = OreNode('iron', 0, 0);
    var a = 0, b = 0;
    while (!plain.strike(1.0, 4)) {
      a++;
    }
    while (!obsidian.strike(1.34, 4)) {
      b++;
    }
    expect(a + 1, 4);
    expect(b + 1, 3);
  });

  test('the strike crouches, reaches the rock at its contact, and is at rest by its end', () {
    for (final stage in [1, 2, 3]) {
      final (back, _, crouch, _, _) = pouncePose(pounceWindup - 0.001, stage);
      expect(back, lessThan(0), reason: 'it draws back first');
      expect(crouch, lessThan(1), reason: 'and crouches');
      final (reach, _, _, _, _) = pouncePose(pounceContact, stage);
      expect(reach, greaterThan(0.7), reason: 'the head reaches the rock at the contact');
      final (end, sx, sy, lean, col) = pouncePose(pounceEnd, stage);
      expect(end, 0);
      expect(sx, 1);
      expect(sy, 1);
      expect(lean, 0);
      expect(col, 0);
    }
  });

  test('a too-hard node stops the lunge short', () {
    final (full, _, _, _, _) = pouncePose(pounceContact, 3);
    final (hard, _, _, _, _) = pouncePose(pounceContact, 3, hard: true);
    expect(hard, lessThan(full));
  });

  test('ore tiers: copper needs no gear, the rest climb', () {
    expect(oreTier['copper'], 1);
    expect(oreTier['iron']! < oreTier['lumen']! && oreTier['lumen']! < oreTier['obsidian']!, isTrue);
  });

  test('a burst node puts its ore in the Bag once, however often the break is reported', () {
    var s = freshPet();
    final r = m.breakOre(s, 'copper', 3, 'trail:0:1000', t0);
    expect(r.error, isNull);
    expect(g.ownedQty(r.state, 'copper_ore'), 3);
    expect(r.events.map((e) => e.type), containsAll(['ore', 'ore_first']));
    s = r.state;
    final again = m.breakOre(s, 'copper', 3, 'trail:0:1000', t0 + 5);
    expect(g.ownedQty(again.state, 'copper_ore'), 3, reason: 'the same break never pays twice');
    expect(again.events, isEmpty);
    final next = m.breakOre(s, 'copper', 2, 'trail:0:2000', t0 + 60000);
    expect(g.ownedQty(next.state, 'copper_ore'), 5);
    expect(next.events.map((e) => e.type), isNot(contains('ore_first')));
  });

  test('ore is mined, never sold or bought, and does not point you to the Garden', () {
    for (final id in m.oreItem.values) {
      final it = catalog[id]!;
      expect(it.acquisition, 'mine', reason: id);
      expect(it.shop, isNull, reason: id);
      expect(it.glimmer, isNull, reason: id);
      expect(it.sellable, isFalse, reason: id);
      expect(h.homeSource(id), isNull, reason: id);
    }
    expect(m.breakOre(freshPet(), 'diamond', 1, 'x', t0).error, isNotNull);
  });

  GameState rich(GameState s, int coins) {
    final c = s.copy();
    g.addTxn(c, WalletTxn(id: 'test:coins', amount: coins, cause: 'test', at: t0));
    return c;
  }

  test("Flint sells gear for coins; it goes on at once and can't be bought twice", () {
    var s = rich(freshPet(), 500);
    final r = m.buyGear(s, 'copper_headlamp', 'req-1', t0);
    expect(r.error, isNull);
    s = r.state;
    expect(g.balanceOf(s), 380);
    expect(m.ownedGear(s, 'copper_headlamp'), isNotNull);
    expect(s.mining.loadout['helmet'], m.ownedGear(s, 'copper_headlamp')!.id, reason: 'an empty slot takes it');
    expect(m.buyGear(s, 'copper_headlamp', 'req-1', t0).state.mining.gear.length, 1, reason: 'a repeated request does nothing');
    expect(m.buyGear(s, 'copper_headlamp', 'req-2', t0).error, 'owned');
    expect(m.buyGear(s, 'copper_harness', 'req-3', t0).error, 'wrong_maker', reason: "Bram forges harnesses, Flint doesn't sell them");
    expect(m.buyGear(freshPet(), 'copper_pick', 'req-4', t0).error, 'insufficient');
  });

  test('Bram forges from your ore, and the piece remembers where the ore was mined', () {
    var s = freshPet();
    expect(m.forgeGear(s, 'copper_harness', 'f-1', t0).error, 'missing_ore');
    s = m.breakOre(s, 'copper', 3, 'trail:0:1', t0).state;
    s = m.breakOre(s, 'copper', 3, 'trail:1:2', t0 + 1000).state;
    final r = m.forgeGear(s, 'copper_harness', 'f-1', t0 + 5000, finish: 'engraved');
    expect(r.error, isNull);
    s = r.state;
    expect(g.ownedQty(s, 'copper_ore'), 0);
    final p = m.ownedGear(s, 'copper_harness')!;
    expect(p.from, 'bram');
    expect(p.oreFrom, 'trail');
    expect(p.finish, 'engraved');
    expect(g.balanceOf(s), 0, reason: 'forging costs ore, not coins');
  });

  test('the loadout sets the ore you can break and how hard you strike', () {
    var s = rich(freshPet(), 1000);
    expect(m.oreTierOf(s), 1);
    expect(m.miningPowerOf(s), 1.0);
    s = m.buyGear(s, 'copper_pick', 'p1', t0).state;
    expect(m.miningPowerOf(s), closeTo(1.15, 1e-9));
    expect(m.oreTierOf(s), 1, reason: 'a copper pick breaks nothing harder than copper');
    for (var i = 0; i < 2; i++) {
      s = m.breakOre(s, 'copper', 3, 'trail:0:$i', t0 + i).state;
    }
    s = m.buyGear(s, 'iron_pick', 'p2', t0).state;
    expect(m.ownedGear(s, 'iron_pick'), isNotNull);
    expect(s.mining.loadout['tool'], m.ownedGear(s, 'copper_pick')!.id, reason: 'the slot was taken: the new one waits');
    s = m.wearGear(s, m.ownedGear(s, 'iron_pick')!.id).state;
    expect(m.oreTierOf(s), 2);
    expect(m.miningPowerOf(s), closeTo(1.35, 1e-9));
    s = m.takeOffGear(s, 'tool').state;
    expect(m.oreTierOf(s), 1);
  });

  test("gear is its own loadout: it never touches the wearables, and it's never for Glimmer", () {
    var s = rich(freshPet(), 500);
    final before = Map.of(s.pet!.equipped);
    s = m.buyGear(s, 'copper_headlamp', 'r', t0).state;
    expect(s.pet!.equipped, before);
    expect(s.txns.where((t) => t.currency == 'glimmer'), isEmpty);
    final round = GameState.fromJson(s.toJson());
    expect(round.mining.loadout, s.mining.loadout);
    expect(round.mining.gear.single.def, 'copper_headlamp');
  });

  test('the first strike with gear on marks its first trip, once', () {
    var s = rich(freshPet(), 500);
    s = m.buyGear(s, 'copper_lantern', 'r', t0).state;
    s = m.markFirstTrip(s, t0 + 10).state;
    s = m.markFirstTrip(s, t0 + 20).state;
    expect(m.ownedGear(s, 'copper_lantern')!.firstTrip, t0 + 10);
  });
}
