// Mining's rules (MINES_PLAN.md): what a burst ore node puts in your Bag, and the mining gear: buying from
// Flint, forging at Bram's, the loadout worn on the trail and in the mines, and what it does (the ore you
// can break, how hard you strike). The loot is awarded once, at the break, under a key for that break, so
// a repeated contact or a replayed event never pays twice; gear likewise once per request. Steps play no
// part here: mining works on a day you haven't walked.

import '../../core/models/game_state.dart';
import '../engine.dart' as g;
import 'gear.dart';

export 'gear.dart';

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

// ------------------------------------------------------------------------------------------- gear
/// The gear you own of [def] (null: none).
GearPiece? ownedGear(GameState s, String def) {
  for (final p in s.mining.gear) {
    if (p.def == def) return p;
  }
  return null;
}

/// The pieces worn, by slot.
Map<String, GearDef> wornGear(GameState s) => {
      for (final e in s.mining.loadout.entries)
        if (s.mining.piece(e.value) != null && gearDefs[s.mining.piece(e.value)!.def] != null) e.key: gearDefs[s.mining.piece(e.value)!.def]!
    };

/// The hardest ore your loadout can break: copper with none, iron with a piece that opens iron, and so on.
int oreTierOf(GameState s) => wornGear(s).values.where((d) => d.opens).fold(1, (a, d) => d.tier > a ? d.tier : a);

/// How much a strike is worth: 1, plus your loadout's power, and an Obsidian Evochi's edge.
double miningPowerOf(GameState s) {
  final edge = s.pet?.paletteId == 'obsidian' ? 1.34 : 1.0;
  return edge * (1 + wornGear(s).values.fold(0.0, (a, d) => a + d.power));
}

/// Where the ore you're about to spend was mined (the latest find of it): a map id like 'trail'.
String? _oreFrom(GameState s, Map<String, int> ore) {
  String? from;
  var at = -1;
  for (final id in ore.keys) {
    for (final a in s.inventory[id]?.acquisitions ?? const <Acquisition>[]) {
      final t = a.txnId;
      if (a.source == 'mine' && t != null && a.at > at) {
        at = a.at;
        from = t.split(':').length > 1 ? t.split(':')[1] : null;
      }
    }
  }
  return from;
}

g.ActionResult _make(GameState state, String def, String maker, String requestId, int now, {String? finish}) {
  final d = gearDefs[def];
  if (d == null) return g.ActionResult(state, error: 'unknown_gear');
  if (d.maker != maker) return g.ActionResult(state, error: 'wrong_maker');
  final txn = 'gear:$requestId';
  if (state.mining.piece(txn) != null) return g.ActionResult(state); // already made: a repeat does nothing
  if (ownedGear(state, def) != null) return g.ActionResult(state, error: 'owned');
  final bal = g.balanceOf(state);
  if (bal < d.coins) return g.ActionResult(state, error: 'insufficient', info: {'short': d.coins - bal});
  final missing = {
    for (final e in d.ore.entries)
      if (g.ownedQty(state, e.key) < e.value) e.key: e.value - g.ownedQty(state, e.key)
  };
  if (missing.isNotEmpty) return g.ActionResult(state, error: 'missing_ore', info: {'missing': missing});
  final s = state.copy();
  if (d.coins > 0) g.addTxn(s, WalletTxn(id: txn, amount: -d.coins, cause: 'gear:$def', at: now));
  for (final e in d.ore.entries) {
    s.inventory[e.key]!.quantity -= e.value;
  }
  final piece = GearPiece(id: txn, def: def, at: now, from: maker, oreFrom: maker == 'bram' ? _oreFrom(state, d.ore) : null, finish: finish);
  s.mining.gear.add(piece);
  s.mining.loadout.putIfAbsent(d.slot, () => piece.id); // an empty slot takes it at once
  return g.ActionResult(s, events: [
    g.GameEvent(maker == 'bram' ? 'gear_forged' : 'gear_bought', {'def': def, 'piece': piece.id, 'worn': s.mining.loadout[d.slot] == piece.id})
  ]);
}

/// Buy a piece from Flint (EvoCoins, and ore from the iron tier up). Once per [requestId].
g.ActionResult buyGear(GameState state, String def, String requestId, int now) => _make(state, def, 'flint', requestId, now);

/// Bram forges a piece from your ore, in the [finish] you picked. Once per [requestId].
g.ActionResult forgeGear(GameState state, String def, String requestId, int now, {String finish = 'polished'}) =>
    _make(state, def, 'bram', requestId, now, finish: gearFinishes.containsKey(finish) ? finish : 'polished');

/// Wear a piece you own in its slot (the one there before goes back to your gear).
g.ActionResult wearGear(GameState state, String pieceId) {
  final p = state.mining.piece(pieceId);
  final d = p == null ? null : gearDefs[p.def];
  if (p == null || d == null) return g.ActionResult(state, error: 'not_owned');
  if (state.mining.loadout[d.slot] == pieceId) return g.ActionResult(state);
  final s = state.copy();
  s.mining.loadout[d.slot] = pieceId;
  return g.ActionResult(s, events: [g.GameEvent('gear_worn', {'slot': d.slot, 'piece': pieceId})]);
}

/// Take off what's in [slot].
g.ActionResult takeOffGear(GameState state, String slot) {
  if (!state.mining.loadout.containsKey(slot)) return g.ActionResult(state);
  final s = state.copy();
  s.mining.loadout.remove(slot);
  return g.ActionResult(s, events: [g.GameEvent('gear_off', {'slot': slot})]);
}

/// The first strike with a piece on: it remembers its first trip (its memory card).
g.ActionResult markFirstTrip(GameState state, int now) {
  final worn = state.mining.loadout.values.toSet();
  if (!state.mining.gear.any((p) => worn.contains(p.id) && p.firstTrip == null)) return g.ActionResult(state);
  final s = state.copy();
  for (final p in s.mining.gear) {
    if (worn.contains(p.id) && p.firstTrip == null) p.firstTrip = now;
  }
  return g.ActionResult(s);
}
