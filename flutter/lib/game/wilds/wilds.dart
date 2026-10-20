// The Lumen Wilds in the save: what a run brings home, the guardian's first-clear reward and the clear
// flag, the healing items a fight eats from the Bag, and Sher's welcome gift.
//
// The fight itself (Raid HP, Stamina, the foes) lives only on the Wilds screen (features/wilds): Raid HP
// is not Vitality, and a knockout there is an evacuation, never harm to the pet. Only these actions touch
// the save, and each grants once: a retried bank or clear (a double tap, a reconnect) finds its
// transaction already there and adds nothing.

import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';
import '../engine.dart';

/// The Bag's healing items a fight can use, cheapest first (the button eats these in order).
const wildsHealItems = [
  'berry_snack', 'meadow_tea', 'carrot_stew', 'golden_bun', 'sunberry_tart', 'glowleaf_tonic', 'healing_herb',
  'moonshroom_pie', 'lantern_tonic', 'moonlight_draught',
];

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
ActionResult wildsBank(GameState state, String runId, int coins, Map<String, int> items, int now) {
  final bag = {for (final e in items.entries) if (e.value > 0 && catalog.containsKey(e.key)) e.key: e.value};
  if (coins <= 0 && bag.isEmpty) return ActionResult(state);
  final s = state.copy();
  final txn = 'wilds:run:$runId';
  if (!addTxn(s, WalletTxn(id: txn, amount: coins, cause: 'wilds', at: now))) {
    return ActionResult(state, events: [GameEvent('already_claimed', {'id': txn})]);
  }
  bag.forEach((id, n) => grantItem(s, id, n, 'wilds', now, txn));
  return ActionResult(s, events: [
    GameEvent('wilds_banked', {'coins': coins, 'items': bag, 'rewards': _rewards(coins, bag)}),
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
  return ActionResult(s, events: [
    GameEvent('wilds_cleared', {'floor': floor, 'first': first, 'coins': r.coins, 'items': r.items, 'rewards': _rewards(r.coins, r.items)}),
  ]);
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
