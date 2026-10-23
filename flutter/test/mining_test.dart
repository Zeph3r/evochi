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
}
