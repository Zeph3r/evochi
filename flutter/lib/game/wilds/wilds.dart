// The Lumen Wilds in the save: what a run brings home, the guardian's first-clear reward and the clear
// flag, the healing items a fight eats from the Bag, and Sher's welcome gift.
//
// The fight itself (Raid HP, Stamina, the foes) lives only on the Wilds screen (features/wilds): Raid HP
// is not Vitality, and a knockout there is an evacuation, never harm to the pet. Only these actions touch
// the save, and each grants once: a retried bank or clear (a double tap, a reconnect) finds its
// transaction already there and adds nothing.

import 'dart:math' as math;

import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';
import '../economy/economy.dart' as econ;
import '../engine.dart';
import 'charms.dart' as charms;

/// The Bag's healing items a fight can use, cheapest first (the button eats these in order). The
/// Apothecary's brews are not here: drunk in the Wilds they give a buff instead ([wildsBrews]).
const wildsHealItems = ['berry_snack', 'carrot_stew', 'golden_bun', 'sunberry_tart', 'healing_herb', 'moonshroom_pie'];

/// Apothecary brews and the buff each gives in the Wilds (the buffs: features/wilds/wilds_combat.dart).
const wildsBrews = {
  'glowleaf_tonic': 'regen',
  'meadow_tea': 'swift',
  'moonlight_draught': 'moonlit',
  'lantern_tonic': 'lantern',
  'ember_draught': 'ember',
  'thornskin_tonic': 'thornskin',
  // coatings (one at a time)
  'frostmint_tonic': 'frost',
  'fizzleberry_soda': 'static',
  'sapling_syrup': 'sap',
  'dazzle_dew': 'dazzle',
  'hushwater': 'hush',
};

/// The brews in the Bag, in [wildsBrews] order.
List<String> ownedBrews(GameState s) => [for (final id in wildsBrews.keys) if (ownedQty(s, id) > 0) id];

/// Drink a brew in a fight: one leaves the Bag (the screen starts its buff).
ActionResult wildsDrink(GameState state, String itemId, int now) {
  final buff = wildsBrews[itemId];
  if (buff == null) return _fail(state, 'not_a_brew');
  if (ownedQty(state, itemId) < 1) return _fail(state, 'not_owned');
  final s = state.copy();
  s.inventory[itemId]!.quantity -= 1;
  return ActionResult(s, events: [GameEvent('wilds_drink', {'itemId': itemId, 'buff': buff})]);
}

/// Raid HP an item restores in the Wilds (scaled from its Vitality value; it never touches Vitality).
int wildsHealAmount(String itemId) => 14 + (catalog[itemId]?.vitality ?? 0) * 3;

String? nextHealItem(GameState s) {
  for (final id in wildsHealItems) {
    if (ownedQty(s, id) > 0) return id;
  }
  return null;
}

int healItemCount(GameState s) => wildsHealItems.fold(0, (a, id) => a + ownedQty(s, id));

String clearFlag(String floor) => 'wilds_${floor}_cleared';

bool floorCleared(GameState s, String floor) => s.flags[clearFlag(floor)] == true;

ActionResult _fail(GameState s, String error) => ActionResult(s, error: error);

/// Eat a healing item in a fight: one leaves the Bag (the screen heals Raid HP by [wildsHealAmount]).
ActionResult wildsUseHeal(GameState state, String itemId, int now) {
  if (!wildsHealItems.contains(itemId)) return _fail(state, 'not_consumable');
  if (ownedQty(state, itemId) < 1) return _fail(state, 'not_owned');
  final s = state.copy();
  s.inventory[itemId]!.quantity -= 1;
  return ActionResult(s, events: [GameEvent('wilds_heal', {'itemId': itemId, 'amount': wildsHealAmount(itemId)})]);
}

List<Map<String, Object?>> _rewards(int coins, Map<String, int> items) => [
      if (coins > 0) {'kind': 'coins', 'amount': coins},
      for (final e in items.entries)
        for (var i = 0; i < e.value; i++) {'kind': 'item', 'itemId': e.key},
    ];

/// The satchel brought home (through the exit, a retreat, or with the guardian calmed). One run banks
/// once: its transaction id is the run's.
ActionResult wildsBank(GameState state, String runId, int coins, Map<String, int> items, int now, {int calmed = 0}) {
  final bag = {for (final e in items.entries) if (e.value > 0 && catalog.containsKey(e.key)) e.key: e.value};
  final glimmer = items[econ.glimmer] ?? 0; // a rare foe drop rides in the satchel too
  if (coins <= 0 && bag.isEmpty && glimmer <= 0 && calmed <= 0) return ActionResult(state);
  final s = state.copy();
  final txn = 'wilds:run:$runId';
  if (!addTxn(s, WalletTxn(id: txn, amount: coins, cause: 'wilds', at: now))) {
    return ActionResult(state, events: [GameEvent('already_claimed', {'id': txn})]);
  }
  // charms: the worn one grows; one already owned that dropped again becomes progress, not a second copy
  final dupes = {for (final e in bag.entries) if (charms.charmDefs.containsKey(e.key) && charms.ownsCharm(s, e.key)) e.key: e.value};
  final charmEvents = charms.charmsAfterRun(s, calmed, dupes);
  dupes.keys.forEach(bag.remove);
  bag.forEach((id, n) => grantItem(s, id, n, 'wilds', now, txn));
  final rewards = _rewards(coins, bag);
  if (glimmer > 0) rewards.addAll(econ.grantDrops(s, {econ.glimmer: glimmer}, 'wilds', txn, now));
  return ActionResult(s, events: [
    GameEvent('wilds_banked', {'coins': coins, 'items': bag, 'glimmer': glimmer, 'rewards': rewards}),
    ...charmEvents,
  ]);
}

/// What calming a floor's guardian is worth: the first time, and a spar after that (once a day).
({int coins, Map<String, int> items}) clearReward(bool first) =>
    first ? (coins: 150, items: {'briar_heartwood': 1, 'lumen_shard': 2}) : (coins: 40, items: {'briar_heartwood': 1});

/// The guardian calmed: the first time, the floor's reward and its clear flag (saved); after that a
/// smaller sparring reward, once a day. Retries add nothing.
ActionResult wildsClear(GameState state, String floor, int now) {
  final first = !floorCleared(state, floor);
  final day = dayKey(now, state.player?.timezone ?? 'UTC');
  final txn = first ? 'wilds:$floor:first' : 'wilds:$floor:spar:$day';
  final s = state.copy();
  s.flags[clearFlag(floor)] = true;
  final r = clearReward(first);
  if (!addTxn(s, WalletTxn(id: txn, amount: r.coins, cause: 'wilds_clear', at: now))) {
    // already rewarded (a retry, or a second spar today): the flag stays, nothing more
    return ActionResult(s, events: [GameEvent('already_claimed', {'id': txn})]);
  }
  r.items.forEach((id, n) => grantItem(s, id, n, 'wilds', now, txn));
  final rewards = _rewards(r.coins, r.items);
  // the economy: the guardian's rare roll, 200 Season XP (once a day) and, the first time, 50 Glimmer
  final rare = econ.rollDrops('wilds_boss', seededRandom('${s.player?.id ?? 'guest'}:$txn:rare'));
  // a charm already owned turns into progress toward its next rank
  final dupes = {for (final e in rare.entries) if (charms.charmDefs.containsKey(e.key) && charms.ownsCharm(s, e.key)) e.key: e.value};
  final charmEvents = charms.charmsAfterRun(s, 0, dupes);
  dupes.keys.forEach(rare.remove);
  rewards.addAll(econ.grantDrops(s, rare, 'wilds', '$txn:rare', now));
  econ.seasonBossAward(s, now);
  if (first) {
    final m = econ.milestoneGlimmer(s, 'first_boss:$floor', 50, now);
    if (m != null) rewards.add(m);
  }
  return ActionResult(s, events: [
    GameEvent('wilds_cleared', {'floor': floor, 'first': first, 'coins': r.coins, 'items': r.items, 'rewards': rewards}),
    ...charmEvents,
  ]);
}

// ---- the Deep Wilds (F2 and down: features/wilds/deep_floor.dart)
String reachFlag(int floor) => 'wilds_f${floor}_reached';

/// The deepest Deep Wilds floor ever reached (1: none yet, only the Thicket).
int deepestFloor(GameState s) {
  var d = 1;
  while (s.flags[reachFlag(d + 1)] == true) {
    d++;
  }
  return d;
}

/// You went down the steps to [floor]: remembered (the deepest you have been), and the first time you
/// reach a new depth, a little Glimmer for the explorer.
ActionResult wildsReach(GameState state, int floor, int now) {
  if (state.flags[reachFlag(floor)] == true) return ActionResult(state);
  final s = state.copy();
  s.flags[reachFlag(floor)] = true;
  // every fifth floor, the first time: a little Glimmer for the explorer
  final m = floor % 5 == 0 ? econ.milestoneGlimmer(s, 'deep_f$floor', 25, now) : null;
  return ActionResult(s, events: [GameEvent('wilds_reached', {'floor': floor, 'glimmer': m == null ? 0 : 25})]);
}

// ---- Flint's mine keeps its own depth (its galleries are not the Deep Wilds' floors)
String mineReachFlag(int floor) => 'mine_f${floor}_reached';

/// The deepest gallery of the mine ever reached (1: only the first).
int deepestMineFloor(GameState s) {
  var d = 1;
  while (s.flags[mineReachFlag(d + 1)] == true) {
    d++;
  }
  return d;
}

/// You went down the mine's shaft to [floor]: remembered, so the mouth can take you straight back down.
ActionResult mineReach(GameState state, int floor, int now) {
  if (state.flags[mineReachFlag(floor)] == true) return ActionResult(state);
  final s = state.copy();
  s.flags[mineReachFlag(floor)] = true;
  return ActionResult(s, events: [GameEvent('mine_reached', {'floor': floor})]);
}

// ---- the Hollow Surge: now and then, from F5, a floor you go down to is churning with the Hollow. Its
// creatures are tougher; calming it breaks the Surge and spills a Lumen cache (the Wilds screen). It is
// only ever found by going down the steps: never bought, never sold, no Glimmer anywhere near it.
const surgeFrom = 5;

/// A Surge at least once in this many floors gone down (from F5): the pity.
const surgePity = 25;

/// The chance of a Surge on a floor: 3% at F5, half a point more a floor, at most 8%.
double surgeChance(int depth) => depth < surgeFrom ? 0 : math.min(0.08, 0.03 + 0.005 * (depth - surgeFrom));

/// Down the steps to [depth] (the floor made from [seed]): reached (see [wildsReach]) and, from F5, the
/// Surge's roll. The same floor asked twice (a retry) rolls once and answers the same.
ActionResult wildsDescend(GameState state, int depth, int seed, int now) {
  final reach = wildsReach(state, depth, now);
  final s = reach.state == state ? state.copy() : reach.state;
  final st = s.trails.stats;
  final events = [...reach.events];
  if (depth >= surgeFrom) {
    final bool hit;
    if (st['surge_seed'] == seed) {
      hit = st['surge_hit'] == 1;
    } else {
      final pity = st['surge_pity'] ?? 0;
      hit = pity >= surgePity - 1 || seededRandom('${s.player?.id ?? 'guest'}:surge:$depth:$seed').nextDouble() < surgeChance(depth);
      st['surge_seed'] = seed;
      st['surge_hit'] = hit ? 1 : 0;
      st['surge_pity'] = hit ? 0 : pity + 1;
      if (hit) st['surges'] = (st['surges'] ?? 0) + 1;
    }
    if (hit) events.add(GameEvent('hollow_surge', {'floor': depth}));
  }
  return ActionResult(s, events: events);
}

/// Sher's welcome: the first time he joins, a few Berry Snacks for the road.
ActionResult wildsSherGift(GameState state, int now) {
  if (state.flags['wilds_sher_gift'] == true) return ActionResult(state);
  final s = state.copy();
  s.flags['wilds_sher_gift'] = true;
  grantItem(s, 'berry_snack', 3, 'wilds', now);
  return ActionResult(s, events: [
    const GameEvent('wilds_gift', {'itemId': 'berry_snack', 'qty': 3}),
  ]);
}
