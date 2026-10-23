// Mining's rules (lib/features/village/mining.dart): a node breaks on exactly its hits, its crack
// stages run whole -> chipped -> cracked -> burst, an Obsidian Evochi's edge, and the strike's pose
// returns to rest by the end of its ~480 ms.

import 'package:evochi/features/village/mining.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
