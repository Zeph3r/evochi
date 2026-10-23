// Mining's rules (MINES_PLAN.md): what a burst ore node puts in your Bag. The loot is awarded once, at
// the break, under a key for that break, so a repeated contact or a replayed event never pays twice.
// Steps play no part here: mining works on a day you haven't walked.

import '../../core/models/game_state.dart';
import '../engine.dart' as g;

/// Each ore node's kind -> the item it gives.
const oreItem = {'copper': 'copper_ore', 'iron': 'iron_ore', 'lumen': 'lumen_crystal', 'obsidian': 'obsidian_shard'};

/// A node of [kind] burst: [n] of its ore into the Bag, once for [key] (the map, the node and when it
/// broke). Events: 'ore' {item, n}, and 'ore_first' {item} the first time you ever find that ore.
g.ActionResult breakOre(GameState state, String kind, int n, String key, int now) {
  final item = oreItem[kind];
  if (item == null || n <= 0) return g.ActionResult(state, error: 'unknown_ore');
  final txn = 'mine:$key';
  final had = state.inventory[item];
  if (had != null && had.acquisitions.any((a) => a.txnId == txn)) return g.ActionResult(state); // already paid
  final first = had == null;
  final s = state.copy();
  g.grantItem(s, item, n, 'mine', now, txn);
  return g.ActionResult(s, events: [
    g.GameEvent('ore', {'item': item, 'n': n}),
    if (first) g.GameEvent('ore_first', {'item': item}),
  ]);
}
