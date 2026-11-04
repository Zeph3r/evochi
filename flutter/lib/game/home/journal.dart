// The Garden's crop journal and the village's orders.
//
// The journal: a page per crop, filled in as it's grown (the harvests are counted in home.counts as
// 'grown:<crop>' and 'golden:<crop>', and the first one's day as 'first:<crop>'). Each page has four stamps (the
// first harvest, ten, fifty, a Golden one); a stamp earned is collected for Farming XP, and a page full of them
// pays a little EvoCoin bonus. Nothing here can be bought: it only fills by growing.
//
// The orders: three a day, from the village (Mira, Bram, Pip, Alder), for crops the player can grow. Now and then
// one is special, for a Gilded crop, and pays far more: the reason to keep a Gilded one. Each order can be
// delivered once; tomorrow brings new ones. Every roll is the game's seeded random (the player and the day), so a
// day's orders are the same however often the board is looked at.

import 'dart:math' as math;

import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';
import '../engine.dart' as g;
import 'home.dart' as h;

g.ActionResult _ok(GameState s, [List<g.GameEvent> events = const []]) => g.ActionResult(s, events: events);
g.ActionResult _fail(GameState s, String error, [Map<String, Object?> info = const {}]) => g.ActionResult(s, error: error, info: info);

int _count(GameState s, String k) => s.home.counts[k] ?? 0;

/// Count a harvest in the journal (called by home.harvest).
void noteHarvest(GameState s, String crop, bool golden, int now) {
  s.home.counts['grown:$crop'] = _count(s, 'grown:$crop') + 1;
  if (golden) s.home.counts['golden:$crop'] = _count(s, 'golden:$crop') + 1;
  s.home.counts.putIfAbsent('first:$crop', () => now);
}

// ------------------------------------------------------------------ the journal ----
class Stamp {
  const Stamp(this.id, this.label, this.xp, this.test);
  final String id;
  final String label;
  final int xp; // Farming XP when it's collected
  final bool Function(GameState s, String crop) test;
}

final stamps = <Stamp>[
  Stamp('first', 'First harvest', 10, (s, c) => _count(s, 'grown:$c') >= 1),
  Stamp('ten', 'Ten harvests', 25, (s, c) => _count(s, 'grown:$c') >= 10),
  Stamp('fifty', 'Fifty harvests', 60, (s, c) => _count(s, 'grown:$c') >= 50),
  Stamp('golden', 'A Golden harvest', 40, (s, c) => _count(s, 'golden:$c') >= 1),
];

/// A full page's bonus (EvoCoins), by crop: the slower the crop, the more.
const pageBonus = {'sunberry': 60, 'meadow_carrot': 80, 'golden_wheat': 100, 'glowleaf': 150, 'moonshroom': 200, 'glowcap': 220};

class JournalPage {
  JournalPage(this.crop, this.grown, this.golden, this.firstAt, this.earned, this.collected, this.pageCollected);
  final String crop;
  final int grown, golden;
  final int? firstAt;
  final Set<String> earned, collected;
  final bool pageCollected;
  bool get complete => earned.length == stamps.length;
  bool get toCollect => earned.difference(collected).isNotEmpty || (complete && collected.length == stamps.length && !pageCollected);
  bool get seen => grown > 0;
}

JournalPage journalPage(GameState s, String crop) => JournalPage(
      crop,
      _count(s, 'grown:$crop'),
      _count(s, 'golden:$crop'),
      s.home.counts['first:$crop'],
      {for (final st in stamps) if (st.test(s, crop)) st.id},
      {for (final st in stamps) if (_count(s, 'stamp:$crop:${st.id}') > 0) st.id},
      _count(s, 'page:$crop') > 0,
    );

List<JournalPage> journal(GameState s) => [for (final c in h.cropOrder) journalPage(s, c)];

/// Anything waiting to be collected in the journal (the Garden's badge).
bool journalWaiting(GameState s) => journal(s).any((p) => p.toCollect);

/// Collect what a page has earned: each stamp's XP, then (all four collected) the page's bonus.
g.ActionResult collectJournal(GameState state, String crop, int now) {
  if (!h.cropDefs.containsKey(crop)) return _fail(state, 'unknown_crop');
  final p = journalPage(state, crop);
  if (!p.toCollect) return _fail(state, 'nothing_to_collect');
  final s = state.copy();
  final events = <g.GameEvent>[];
  var xp = 0;
  final got = <String>[];
  for (final st in stamps) {
    if (p.earned.contains(st.id) && !p.collected.contains(st.id)) {
      s.home.counts['stamp:$crop:${st.id}'] = 1;
      xp += st.xp;
      got.add(st.id);
    }
  }
  var coins = 0;
  if (p.complete && !p.pageCollected) {
    s.home.counts['page:$crop'] = 1;
    coins = pageBonus[crop] ?? 60;
    g.addTxn(s, WalletTxn(id: 'journal:$crop', amount: coins, cause: 'journal', at: now));
  }
  if (xp > 0) h.addSkillXp(s, 'farming', xp.toDouble(), events);
  events.insert(0, g.GameEvent('journal_collected', {'crop': crop, 'stamps': got, 'xp': xp, 'coins': coins}));
  return _ok(s, events);
}

// ------------------------------------------------------------------ the orders ----
class Villager {
  const Villager(this.id, this.name, this.ask, this.special);
  final String id; // the village art's name (village/npc_<id>_<expr>.webp)
  final String name;
  final String ask; // what they say, {items} for the order
  final String special; // for a Gilded crop, {crop}
}

const villagers = [
  Villager('mira', 'Mira', 'My seedlings love company. Could you spare {items}?', 'A Gilded {crop}! Its seeds would sing in the Glasshouse.'),
  Villager('bram', 'Bram', 'The lanterns burn late tonight. {items} would keep me going.', "A Gilded {crop}? I'd set it in the Lodge's window, for luck."),
  Villager('pip', 'Pip', 'Deliveries all day and nothing to eat! {items}, please?', 'Is it true you grew a Gilded {crop}? The whole road would want to see it!'),
  Villager('alder', 'Alder', "I'm mapping the Old Trail. {items} would see me down the road.", 'A Gilded {crop} for my collection of curiosities? Name your price.'),
];

/// A crop's worth in an order (EvoCoins each).
const cropWorth = {'sunberry': 4, 'meadow_carrot': 7, 'golden_wheat': 6, 'glowleaf': 14, 'moonshroom': 25, 'glowcap': 34};
const _orderQty = {'sunberry': (6, 10), 'meadow_carrot': (4, 8), 'golden_wheat': (4, 8), 'glowleaf': (3, 5), 'moonshroom': (2, 4), 'glowcap': (2, 3)};

class VillageOrder {
  VillageOrder({required this.id, required this.villager, required this.wants, required this.coins, required this.xp, required this.special});
  final String id;
  final Villager villager;
  final Map<String, int> wants;
  final int coins, xp;
  final bool special; // a Gilded crop's order

  String get line {
    if (special) {
      final gid = wants.keys.firstWhere((k) => k.startsWith('gilded_'));
      final crop = h.gildedOf.entries.firstWhere((e) => e.value == gid).key;
      return villager.special.replaceAll('{crop}', h.cropDefs[crop]!.name);
    }
    final parts = [for (final e in wants.entries) '${e.value} ${h.itemLabel(e.key, e.value).toLowerCase()}'];
    final items = parts.length == 1 ? parts.first : '${parts.first} and ${parts.last}';
    return villager.ask.replaceAll('{items}', items);
  }
}

const ordersADay = 3;
const specialChance = 0.35;

/// Today's orders (the same all day).
List<VillageOrder> ordersFor(GameState s, int now) {
  final day = dayKey(now, g.zoneOf(s));
  final r = g.seededRandom('${s.player?.id ?? 'guest'}:orders:$day');
  final crops = [for (final c in h.cropOrder) if (h.cropUnlocked(s, c)) c];
  final who = [...villagers]..shuffle(r);
  final out = <VillageOrder>[];
  final special = r.nextDouble() < specialChance ? r.nextInt(ordersADay) : -1;
  for (var i = 0; i < ordersADay; i++) {
    final v = who[i % who.length];
    if (i == special) {
      final crop = crops[r.nextInt(crops.length)];
      out.add(VillageOrder(
        id: '$day:$i',
        villager: v,
        wants: {h.gildedOf[crop]!: 1},
        coins: 200 + cropWorth[crop]! * 15,
        xp: 60,
        special: true,
      ));
      continue;
    }
    final wants = <String, int>{};
    final first = crops[r.nextInt(crops.length)];
    final (lo, hi) = _orderQty[first]!;
    wants[first] = lo + r.nextInt(hi - lo + 1);
    if (crops.length > 1 && r.nextDouble() < 0.4) {
      final second = crops.where((c) => c != first).toList()[r.nextInt(crops.length - 1)];
      final (lo2, hi2) = _orderQty[second]!;
      wants[second] = math.max(1, (lo2 + r.nextInt(hi2 - lo2 + 1)) ~/ 2);
    }
    final worth = wants.entries.fold<int>(0, (a, e) => a + cropWorth[e.key]! * e.value);
    out.add(VillageOrder(
      id: '$day:$i',
      villager: v,
      wants: wants,
      coins: (worth * 1.6 / 5).round() * 5,
      xp: math.max(8, worth ~/ 3),
      special: false,
    ));
  }
  return out;
}

bool orderDone(GameState s, String id) => _count(s, 'order:$id') > 0;

bool canDeliver(GameState s, VillageOrder o) => !orderDone(s, o.id) && o.wants.entries.every((e) => g.ownedQty(s, e.key) >= e.value);

/// Hand an order over: its crops go, its EvoCoins and Farming XP come (once).
g.ActionResult deliverOrder(GameState state, String orderId, int now) {
  final o = ordersFor(state, now).where((x) => x.id == orderId).firstOrNull;
  if (o == null) return _fail(state, 'no_such_order');
  if (orderDone(state, o.id)) return _fail(state, 'already_delivered');
  if (!canDeliver(state, o)) return _fail(state, 'missing_items', {'wants': o.wants});
  final s = state.copy();
  o.wants.forEach((id, n) => s.inventory[id]!.quantity -= n);
  // yesterday's ticks go (only today's are kept)
  final day = orderId.split(':').first;
  s.home.counts.removeWhere((k, _) => k.startsWith('order:') && !k.startsWith('order:$day:'));
  s.home.counts['order:${o.id}'] = 1;
  s.home.counts['orders'] = _count(s, 'orders') + 1;
  g.addTxn(s, WalletTxn(id: 'order:${o.id}', amount: o.coins, cause: 'village_order', at: now));
  final events = <g.GameEvent>[
    g.GameEvent('order_delivered', {'order': o.id, 'villager': o.villager.name, 'coins': o.coins, 'xp': o.xp, 'special': o.special}),
  ];
  h.addSkillXp(s, 'farming', o.xp.toDouble(), events);
  return _ok(s, events);
}
