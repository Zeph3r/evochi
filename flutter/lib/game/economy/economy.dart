// The economy (docs: Evochi Economy & Monetization Plan): Glimmer, the premium currency; the rare finds
// that drop in play and sell at the Starlight Caravan; the tiered daily chest; Season 1: First Light;
// Evochi Plus; and the Google Play products that top it all up.
//
// Rules that hold everywhere:
//  - Glimmer is a second currency on the wallet ledger (WalletTxn currency 'glimmer'), never a stored
//    balance, so each grant and spend has a unique id and a retry adds nothing.
//  - Every roll uses the game's seeded random (player id + a source id): retrying a claim gives the same
//    result and can't be farmed.
//  - Steps are never sold. A Sunstone ripens a bed; it never adds steps, and the story still needs walking.
//  - Rest days are never punished: chest tiers climb with the goal days reached this week and never fall.

import 'dart:math' as math;

import '../../core/models/catalog.dart';
import '../../core/models/economy_state.dart';
import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';
import '../../core/utils/ids.dart';
import '../engine.dart' as g;
import '../home/home.dart' as h;
import '../story/story_data.dart' show titles;
import '../wilds/charms.dart' as charms;

const glimmer = 'glimmer';

int glimmerOf(GameState s) => g.balanceOf(s, glimmer);

g.ActionResult _ok(GameState s, [List<g.GameEvent> events = const []]) => g.ActionResult(s, events: events);
g.ActionResult _fail(GameState s, String error, [Map<String, Object?> info = const {}]) => g.ActionResult(s, error: error, info: info);

String _zone(GameState s) => g.zoneOf(s);
String _today(GameState s, int now) => dayKey(now, _zone(s));
String _pid(GameState s) => s.player?.id ?? 'guest';

bool _addGlimmer(GameState s, String id, int amount, String cause, int now) =>
    g.addTxn(s, WalletTxn(id: id, amount: amount, cause: cause, at: now, currency: glimmer));

// ================================================================ rare finds ====
/// The rare items that work today. Starseed (needs the Starfruit crop) and Prism Scale (needs the shimmer
/// render) are in the catalog but neither drops nor sells until their art lands.
const activeRares = ['sunstone', 'moonwell_dew', 'heartbloom', 'wayfinder_compass', 'golden_acorn', 'hollow_ward'];

/// Items that are armed from the Bag and wait for their moment (one at a time).
const armable = {'golden_acorn': 'Your next daily chest opens one tier better.', 'wayfinder_compass': 'Your next trail discovery pays double.', 'hollow_ward': 'Your next Wilds run starts with a three-hit shield.'};

class Drop {
  const Drop(this.id, this.chance, {this.min = 1, this.max = 1});
  final String id; // an item id, or 'glimmer'
  final double chance;
  final int min;
  final int max;
}

/// Where rare finds come from (each line rolls on its own). Tuned in the plan's Rare items table.
const dropTables = <String, List<Drop>>{
  'wilds_foe': [
    Drop('sunstone', 0.005), Drop('golden_acorn', 0.003), Drop('hollow_ward', 0.01), Drop(glimmer, 0.01, min: 1, max: 3),
    // charms (game/wilds/charms.dart): 0.6% between them
    Drop('emberfang_charm', 0.0012), Drop('frostbell_charm', 0.0012), Drop('static_acorn', 0.0012), Drop('sap_locket', 0.0012),
    Drop('dazzle_pebble', 0.0012),
  ],
  'wilds_boss': [
    Drop('sunstone', 0.08), Drop('heartbloom', 0.03),
    // a guardian is the likeliest place to find a charm: 10% between them
    Drop('emberfang_charm', 0.02), Drop('frostbell_charm', 0.02), Drop('static_acorn', 0.02), Drop('sap_locket', 0.02),
    Drop('dazzle_pebble', 0.02),
  ],
  'discovery': [Drop('moonwell_dew', 0.05), Drop('wayfinder_compass', 0.04)],
  'weekly': [Drop('golden_acorn', 0.10)],
};

/// Roll a drop table: what came out, id -> quantity ('glimmer' for Glimmer).
Map<String, int> rollDrops(String table, math.Random r) {
  final out = <String, int>{};
  for (final d in dropTables[table] ?? const <Drop>[]) {
    if (r.nextDouble() < d.chance) {
      final n = d.min + (d.max > d.min ? r.nextInt(d.max - d.min + 1) : 0);
      out[d.id] = (out[d.id] ?? 0) + n;
    }
  }
  return out;
}

/// Grant a roll into the save (items to the Bag, Glimmer to the wallet). Mutates [s].
List<Map<String, Object?>> grantDrops(GameState s, Map<String, int> drops, String source, String txn, int now) {
  final rewards = <Map<String, Object?>>[];
  drops.forEach((id, n) {
    if (n <= 0) return;
    if (id == glimmer) {
      if (_addGlimmer(s, '$txn:glimmer', n, source, now)) rewards.add({'kind': 'glimmer', 'amount': n});
    } else if (catalog.containsKey(id)) {
      g.grantItem(s, id, n, source, now, txn);
      for (var i = 0; i < n; i++) {
        rewards.add({'kind': 'item', 'itemId': id});
      }
    }
  });
  return rewards;
}

// ================================================================ daily chest ====
const chestTiers = ['wood', 'silver', 'gold', 'lumen'];
const chestNames = {'wood': 'Wooden chest', 'silver': 'Silver chest', 'gold': 'Gold chest', 'lumen': 'Lumen chest'};

class ChestDef {
  const ChestDef({required this.coins, required this.items, required this.commonChance, required this.rare, this.glimmerChance = 0, this.glimmer = const [0, 0]});
  final List<int> coins; // [min, max]
  final int items; // guaranteed items from the uncommon pool
  final double commonChance; // a chance at one common item (wood)
  final double rare; // chance of a rare find (1.0 = guaranteed)
  final double glimmerChance;
  final List<int> glimmer; // [min, max]
}

const chestDefs = <String, ChestDef>{
  'wood': ChestDef(coins: [10, 30], items: 0, commonChance: 0.4, rare: 0.02),
  'silver': ChestDef(coins: [25, 50], items: 1, commonChance: 0, rare: 0.06),
  'gold': ChestDef(coins: [50, 90], items: 2, commonChance: 0, rare: 0.15, glimmerChance: 0.03, glimmer: [10, 20]),
  'lumen': ChestDef(coins: [100, 100], items: 0, commonChance: 0, rare: 1.0, glimmerChance: 0.25, glimmer: [20, 40]),
};

const chestCommon = ['berry_snack', 'berry_snack', 'healing_herb', 'sunlit_flower'];
const chestUncommon = ['healing_herb', 'meadow_tea', 'glowleaf_tonic', 'sprout_tonic', 'seed_glowleaf', 'seed_moonshroom'];

/// A chest's rare roll, by weight (Starseed's share waits for the Starfruit crop).
const chestRareWeights = {'sunstone': 45, 'moonwell_dew': 35, 'heartbloom': 13, 'golden_acorn': 7};

/// Lumen chests: 3% of any chest. Walking 150% of the goal lifts a chest one tier (to Gold at most).
const lumenChance = 0.03;
const overachieve = 1.5;

String _pickWeighted(math.Random r, Map<String, int> w) {
  final total = w.values.fold(0, (a, b) => a + b);
  var x = r.nextInt(total);
  for (final e in w.entries) {
    if (x < e.value) return e.key;
    x -= e.value;
  }
  return w.keys.first;
}

int _goalDaysThisWeek(GameState s, g.GameView d) {
  final pet = s.pet;
  return weekDays(d.today).where((k) {
    final day = d.days[k];
    return day != null && !day.unverified && day.steps >= g.goalFor(s, k) && (pet == null || k.compareTo(pet.createdDay) >= 0);
  }).length;
}

int _tierIndex(String t) => chestTiers.indexOf(t);

/// The chest's tier before the 3% Lumen roll: goal days this week (1-3 Wooden, 4-5 Silver, 6-7 Gold),
/// one better for 150% of the goal (Gold at most), then a Golden Acorn or Plus's weekly lift.
({String tier, bool overachieved, bool acorn, bool plusLift}) _chestBase(GameState s, g.GameView d, int now) {
  final days = math.max(1, _goalDaysThisWeek(s, d));
  var i = days >= 6 ? 2 : (days >= 4 ? 1 : 0);
  final over = d.todaySteps >= (overachieve * d.goal).ceil();
  if (over) i = math.min(2, i + 1);
  final acorn = (s.economy.armed['golden_acorn'] ?? 0) > 0;
  if (acorn) i = math.min(3, i + 1);
  final plusLift = plusActive(s, now) && s.flags['plus_lift:${weekKey(d.today)}'] != true && i < 3;
  if (plusLift) i = math.min(3, i + 1);
  return (tier: chestTiers[i], overachieved: over, acorn: acorn, plusLift: plusLift);
}

/// The tier today's Daily Goal chest would open as (for the quest row), before the Lumen chance.
String chestTierPreview(GameState s, int now) => _chestBase(s, g.derive(s, now), now).tier;

/// Open the Daily Goal chest into [s] (a copy the caller owns). Returns the tier and the rewards, each
/// marked `'chest': true`. Ids hang off [txnId] (the quest claim), so a retry adds nothing.
({String tier, List<Map<String, Object?>> rewards}) openDailyChest(GameState s, g.GameView d, String txnId, int now) {
  final r = g.seededRandom('${_pid(s)}:$txnId:chest');
  final base = _chestBase(s, d, now);
  var tier = base.tier;
  if (tier != 'lumen' && r.nextDouble() < lumenChance) tier = 'lumen';
  if (base.acorn) s.economy.armed['golden_acorn'] = math.max(0, (s.economy.armed['golden_acorn'] ?? 0) - 1);
  if (base.plusLift) s.flags['plus_lift:${weekKey(d.today)}'] = true;
  final def = chestDefs[tier]!;
  final rewards = <Map<String, Object?>>[];
  final coins = def.coins[0] + (def.coins[1] > def.coins[0] ? r.nextInt(def.coins[1] - def.coins[0] + 1) : 0);
  g.addTxn(s, WalletTxn(id: '$txnId:chest', amount: coins, cause: 'chest', at: now));
  rewards.add({'kind': 'coins', 'amount': coins, 'chest': true});
  void give(String id) {
    g.grantItem(s, id, 1, 'chest', now, '$txnId:chest');
    rewards.add({'kind': 'item', 'itemId': id, 'chest': true});
  }

  if (def.commonChance > 0 && r.nextDouble() < def.commonChance) give(chestCommon[r.nextInt(chestCommon.length)]);
  for (var k = 0; k < def.items; k++) {
    give(chestUncommon[r.nextInt(chestUncommon.length)]);
  }
  final rareW = tier == 'lumen' ? (Map.of(chestRareWeights)..remove('golden_acorn')) : chestRareWeights;
  if (r.nextDouble() < def.rare) give(_pickWeighted(r, rareW));
  // Evochi Plus: one more roll at a rare find
  if (plusActive(s, now) && r.nextDouble() < def.rare) give(_pickWeighted(r, rareW));
  if (def.glimmerChance > 0 && r.nextDouble() < def.glimmerChance) {
    final n = def.glimmer[0] + r.nextInt(def.glimmer[1] - def.glimmer[0] + 1);
    if (_addGlimmer(s, '$txnId:chest:glimmer', n, 'chest', now)) rewards.add({'kind': 'glimmer', 'amount': n, 'chest': true});
  }
  return (tier: tier, rewards: rewards);
}

/// The published odds for one chest tier (the odds button: Play asks for them because a bought Golden
/// Acorn changes what a chest can hold).
List<({String label, String odds})> chestOdds(String tier) {
  final d = chestDefs[tier]!;
  String pct(double x) => x >= 1 ? '100%' : '${(x * 100).toStringAsFixed(x < 0.1 ? 1 : 0)}%';
  final w = tier == 'lumen' ? (Map.of(chestRareWeights)..remove('golden_acorn')) : chestRareWeights;
  final total = w.values.fold(0, (a, b) => a + b);
  return [
    (label: 'EvoCoins', odds: d.coins[0] == d.coins[1] ? '${d.coins[0]}' : '${d.coins[0]}-${d.coins[1]}'),
    if (d.commonChance > 0) (label: 'A common item (Berry Snack, Healing Herb, Sunlit Flower)', odds: pct(d.commonChance)),
    if (d.items > 0) (label: '${d.items} uncommon item${d.items > 1 ? 's' : ''} (herbs, teas, tonics, rare seeds)', odds: '100%'),
    (label: 'A rare find', odds: pct(d.rare)),
    for (final e in w.entries) (label: '   ${catalog[e.key]!.name} (of a rare find)', odds: '${(e.value * 100 / total).toStringAsFixed(0)}%'),
    if (d.glimmerChance > 0) (label: 'Glimmer ${d.glimmer[0]}-${d.glimmer[1]}', odds: pct(d.glimmerChance)),
    if (tier != 'lumen') (label: 'Becomes a Lumen chest', odds: pct(lumenChance)),
  ];
}

/// Weekly Explorer: 10 Glimmer and a 10% chance of a Golden Acorn on top of its coins. Mutates [s].
List<Map<String, Object?>> weeklyBonus(GameState s, String txnId, int now) {
  final rewards = <Map<String, Object?>>[];
  if (_addGlimmer(s, '$txnId:glimmer', 10, 'weekly', now)) rewards.add({'kind': 'glimmer', 'amount': 10});
  rewards.addAll(grantDrops(s, rollDrops('weekly', g.seededRandom('${_pid(s)}:$txnId:weekly')), 'weekly', '$txnId:drop', now));
  return rewards;
}

/// One-time Glimmer for a milestone (first evolution to each stage, first guardian calmed). Mutates [s].
Map<String, Object?>? milestoneGlimmer(GameState s, String key, int amount, int now) =>
    _addGlimmer(s, 'milestone:$key', amount, 'milestone:$key', now) ? {'kind': 'glimmer', 'amount': amount} : null;

// ================================================================ using rare finds ====
g.ActionResult _take(GameState state, String id) =>
    g.ownedQty(state, id) < 1 ? _fail(state, 'not_owned', {'itemId': id}) : _ok(state);

/// Sunstone: the bed's crop ripens at once.
g.ActionResult useSunstone(GameState state, String plotId, int now) {
  final p = state.home.plots[plotId];
  if (p == null) return _fail(state, 'plot_empty');
  if (h.plotGrowth(state, p, now).progress >= 1) return _fail(state, 'already_ripe');
  final t = _take(state, 'sunstone');
  if (!t.ok) return t;
  final s = state.copy();
  s.inventory['sunstone']!.quantity -= 1;
  s.home.plots[plotId]!.boost += 1.0;
  return _ok(s, [g.GameEvent('rare_used', {'itemId': 'sunstone', 'plot': plotId})]);
}

/// Moonwell Dew: every planted, unripe bed is watered and gets a quarter of a growing time (once per planting).
g.ActionResult useMoonwellDew(GameState state, int now) {
  final beds = state.home.plots.entries.where((e) => e.value != null && !e.value!.dew && h.plotGrowth(state, e.value!, now).progress < 1).map((e) => e.key).toList();
  if (beds.isEmpty) return _fail(state, 'no_beds');
  final t = _take(state, 'moonwell_dew');
  if (!t.ok) return t;
  final s = state.copy();
  s.inventory['moonwell_dew']!.quantity -= 1;
  for (final id in beds) {
    final p = s.home.plots[id]!;
    p.watered = true;
    p.dew = true;
    p.boost += 0.25;
  }
  return _ok(s, [g.GameEvent('rare_used', {'itemId': 'moonwell_dew', 'beds': beds})]);
}

/// Heartbloom: a fainted Evochi wakes at full Vitality, no herbs and no waiting.
g.ActionResult reviveWithHeartbloom(GameState state, int now) {
  final d = g.derive(state, now);
  if (d.pet == null || !d.pet!.dead) return _fail(state, 'not_dead');
  final t = _take(state, 'heartbloom');
  if (!t.ok) return t;
  final s = state.copy();
  s.inventory['heartbloom']!.quantity -= 1;
  s.pet!.events.add(PetEvent(t: now, type: 'revive', amount: 100, via: 'heartbloom'));
  return _ok(s, [const g.GameEvent('revived', {'via': 'heartbloom'})]);
}

/// Arm a Golden Acorn, Wayfinder Compass or Hollow Ward from the Bag (one of each can wait at a time).
g.ActionResult armRare(GameState state, String itemId) {
  if (!armable.containsKey(itemId)) return _fail(state, 'not_armable');
  if ((state.economy.armed[itemId] ?? 0) > 0) return _fail(state, 'already_armed');
  final t = _take(state, itemId);
  if (!t.ok) return t;
  final s = state.copy();
  s.inventory[itemId]!.quantity -= 1;
  s.economy.armed[itemId] = 1;
  return _ok(s, [g.GameEvent('rare_armed', {'itemId': itemId})]);
}

bool isArmed(GameState s, String itemId) => (s.economy.armed[itemId] ?? 0) > 0;

/// A Wilds run starts: an armed Hollow Ward is spent on it. Returns the shield's hits (0 = none).
g.ActionResult wildsTakeWard(GameState state) {
  if (!isArmed(state, 'hollow_ward')) return _ok(state);
  final s = state.copy();
  s.economy.armed['hollow_ward'] = 0;
  return _ok(s, [const g.GameEvent('ward_up', {'hits': 3})]);
}

/// Knocked out in the Wilds: a Heartbloom gets you back up (the screen restores Raid HP).
g.ActionResult wildsSecondWind(GameState state, int now) {
  final t = _take(state, 'heartbloom');
  if (!t.ok) return t;
  final s = state.copy();
  s.inventory['heartbloom']!.quantity -= 1;
  return _ok(s, [const g.GameEvent('second_wind', {'itemId': 'heartbloom'})]);
}

/// A discovery's reward, doubled by an armed Wayfinder Compass (which it spends), plus its rare roll.
/// Mutates [s]; returns the extra rewards for the toast.
List<Map<String, Object?>> discoveryExtras(GameState s, int coins, Map<String, int> items, String txn, int now) {
  final out = <Map<String, Object?>>[];
  if (isArmed(s, 'wayfinder_compass')) {
    s.economy.armed['wayfinder_compass'] = 0;
    if (coins > 0) g.addTxn(s, WalletTxn(id: '$txn:compass', amount: coins, cause: 'compass', at: now));
    items.forEach((id, n) => g.grantItem(s, id, n, 'compass', now, '$txn:compass'));
    out.add({'kind': 'compass', 'coins': coins, 'items': items});
  }
  out.addAll(grantDrops(s, rollDrops('discovery', g.seededRandom('${_pid(s)}:$txn:drop')), 'discovery', '$txn:drop', now));
  return out;
}

// ================================================================ Evochi Plus ====
bool plusActive(GameState s, int now) => s.economy.plus.until > now;

const plusWelcomeGlimmer = 100;
const plusDailyGlimmer = 10;
const plusDailySeasonXp = 75; // about +10% Season XP for a 6,000-step walker

/// Plus's daily claim: 10 Glimmer and 75 Season XP, once a day while a member.
g.ActionResult claimPlusDaily(GameState state, int now) {
  if (!plusActive(state, now)) return _fail(state, 'not_member');
  final day = _today(state, now);
  if (state.economy.plus.lastDaily == day) return _ok(state, [g.GameEvent('already_claimed', {'id': 'plus:$day'})]);
  final s = state.copy();
  s.economy.plus.lastDaily = day;
  _addGlimmer(s, 'plus:daily:$day', plusDailyGlimmer, 'plus', now);
  final se = currentSeason;
  if (se.activeOn(day)) s.economy.season(se.id).awards['plus:$day'] = plusDailySeasonXp;
  return _ok(s, [g.GameEvent('plus_daily', {'glimmer': plusDailyGlimmer, 'xp': plusDailySeasonXp})]);
}

bool plusDailyReady(GameState s, int now) => plusActive(s, now) && s.economy.plus.lastDaily != _today(s, now);

void _startPlus(GameState s, String product, int days, int now, {bool test = false}) {
  final p = s.economy.plus;
  final from = math.max(now, p.until);
  if (p.since == 0 || from == now) p.since = now;
  p.until = from + days * dayMs;
  p.product = product;
  p.test = test;
  if (!p.welcomed) {
    p.welcomed = true;
    _addGlimmer(s, 'plus:welcome', plusWelcomeGlimmer, 'plus', now);
  }
}

/// Developer tools: a 30-day playtest membership (never billed), or end it.
g.ActionResult setPlusTest(GameState state, bool on, int now) {
  final s = state.copy();
  if (on) {
    _startPlus(s, 'test', 30, now, test: true);
  } else {
    s.economy.plus.until = 0;
  }
  return _ok(s, [g.GameEvent('plus_changed', {'on': on})]);
}

// ================================================================ Season 1 ====
class SeasonReward {
  const SeasonReward({this.coins = 0, this.glimmer = 0, this.items = const {}, this.title});
  final int coins;
  final int glimmer;
  final Map<String, int> items;
  final String? title;
  bool get isEmpty => coins == 0 && glimmer == 0 && items.isEmpty && title == null;
}

class SeasonDef {
  const SeasonDef({
    required this.id,
    required this.name,
    required this.start,
    required this.weeks,
    this.tiers = 40,
    this.tierXp = 1000,
    this.passGlimmer = 500,
    this.tierGlimmer = 100,
    this.tierSaleWeek = 3,
    this.stepsPerXp = 10,
    this.goalDayXp = 150,
    this.weeklyXp = 500,
    this.bossXp = 200,
  });
  final String id;
  final String name;
  final String start; // a Monday (day key)
  final int weeks;
  final int tiers;
  final int tierXp;
  final int passGlimmer;
  final int tierGlimmer;
  final int tierSaleWeek; // extra tiers go on sale from this week
  final int stepsPerXp;
  final int goalDayXp;
  final int weeklyXp;
  final int bossXp;

  String get end => addDays(start, weeks * 7); // first day after the season
  bool activeOn(String day) => day.compareTo(start) >= 0 && day.compareTo(end) < 0;
}

/// Season 1: First Light. Fireflies come back to the Thicket as the Hollow stirs. Dates are config: the
/// closed beta runs it from October 19 so the pass can be tested; launch moves the start.
const currentSeason = SeasonDef(id: 's1', name: 'First Light', start: '2026-10-19', weeks: 8);

const _seedCycle = ['seed_sunberry', 'seed_golden_wheat', 'seed_glowleaf', 'seed_moonshroom'];

const _freeListed = <int, SeasonReward>{
  1: SeasonReward(coins: 50),
  5: SeasonReward(items: {'sunstone': 1}),
  10: SeasonReward(glimmer: 50),
  15: SeasonReward(items: {'lumen_shard': 2}),
  20: SeasonReward(items: {'sunstone': 1}),
  25: SeasonReward(glimmer: 50),
  30: SeasonReward(items: {'sunstone': 1}),
  35: SeasonReward(glimmer: 50),
  40: SeasonReward(items: {'season_first_light_scarf': 1}),
};

const _paidListed = <int, SeasonReward>{
  1: SeasonReward(title: 'lightbearer', items: {'sunstone': 3}),
  5: SeasonReward(items: {'season_dawn_circlet': 1}),
  8: SeasonReward(coins: 60, items: {'sunstone': 1}),
  10: SeasonReward(glimmer: 50, items: {'heartbloom': 1}),
  15: SeasonReward(items: {'season_firefly_scarf': 1}),
  16: SeasonReward(coins: 60, items: {'sunstone': 1}),
  20: SeasonReward(glimmer: 50, items: {'heartbloom': 1}),
  24: SeasonReward(coins: 60, items: {'sunstone': 1}),
  25: SeasonReward(items: {'season_lantern_wings': 1}),
  30: SeasonReward(items: {'season_first_light_banner': 1, 'wayfinder_compass': 1}),
  32: SeasonReward(coins: 60, items: {'sunstone': 1}),
  35: SeasonReward(glimmer: 50, items: {'season_glow_ribbon': 1}),
  40: SeasonReward(items: {'season_dawn_shimmer': 1, 'sunstone': 3}),
};

/// What a tier pays on a track ('free' | 'premium').
SeasonReward seasonReward(String track, int tier) {
  if (track == 'free') {
    final l = _freeListed[tier];
    if (l != null) return l;
    return tier.isOdd ? const SeasonReward(coins: 40) : SeasonReward(items: {_seedCycle[(tier ~/ 2) % _seedCycle.length]: 2});
  }
  return _paidListed[tier] ?? const SeasonReward(coins: 60);
}

class SeasonView {
  SeasonView({
    required this.def,
    required this.active,
    required this.xp,
    required this.tier,
    required this.intoTier,
    required this.premium,
    required this.claimedFree,
    required this.claimedPaid,
    required this.daysLeft,
    required this.week,
    required this.stepXp,
    required this.eventXp,
  });
  final SeasonDef def;
  final bool active;
  final int xp;
  final int tier; // tiers reached (0..tiers)
  final int intoTier; // XP into the next tier
  final bool premium;
  final List<int> claimedFree;
  final List<int> claimedPaid;
  final int daysLeft;
  final int week; // 1-based week of the season
  final int stepXp;
  final int eventXp;

  bool canClaim(String track, int t) =>
      t >= 1 && t <= tier && !(track == 'free' ? claimedFree : claimedPaid).contains(t) && (track == 'free' || premium) && !seasonReward(track, t).isEmpty;
  int get claimable => [for (var t = 1; t <= tier; t++) ...[if (canClaim('free', t)) 1, if (canClaim('premium', t)) 1]].length;
  bool get tiersOnSale => active && week >= def.tierSaleWeek && tier < def.tiers;
}

/// Season XP: 1 per 10 verified steps since the season began, 150 per goal day, 500 per week with 4+
/// goal days, plus awards (a guardian calmed, Plus's daily claim) and tiers bought.
SeasonView seasonView(GameState s, int now, [SeasonDef se = currentSeason]) {
  final d = g.derive(s, now);
  final prog = s.economy.seasons[se.id] ?? SeasonProgress();
  final last = d.today.compareTo(se.end) < 0 ? d.today : addDays(se.end, -1);
  var steps = 0;
  var goalDays = 0;
  final weeks = <String, int>{};
  d.days.forEach((k, day) {
    if (k.compareTo(se.start) < 0 || k.compareTo(last) > 0) return;
    steps += day.verified;
    if (!day.unverified && day.steps >= g.goalFor(s, k)) {
      goalDays++;
      weeks[weekKey(k)] = (weeks[weekKey(k)] ?? 0) + 1;
    }
  });
  final stepXp = steps ~/ se.stepsPerXp;
  final eventXp = goalDays * se.goalDayXp + weeks.values.where((n) => n >= 4).length * se.weeklyXp + prog.awards.values.fold<int>(0, (a, b) => a + b);
  final xp = stepXp + eventXp + prog.boughtTiers * se.tierXp;
  final tier = math.min(se.tiers, xp ~/ se.tierXp);
  final active = se.activeOn(d.today);
  return SeasonView(
    def: se,
    active: active,
    xp: xp,
    tier: tier,
    intoTier: tier >= se.tiers ? se.tierXp : xp % se.tierXp,
    premium: prog.premium,
    claimedFree: List.of(prog.free),
    claimedPaid: List.of(prog.paid),
    daysLeft: active ? diffDays(d.today, se.end) : 0,
    week: active ? diffDays(se.start, d.today) ~/ 7 + 1 : 0,
    stepXp: stepXp,
    eventXp: eventXp,
  );
}

List<Map<String, Object?>> _grantSeason(GameState s, SeasonReward r, String txn, int now) {
  final out = <Map<String, Object?>>[];
  if (r.coins > 0 && g.addTxn(s, WalletTxn(id: txn, amount: r.coins, cause: 'season', at: now))) out.add({'kind': 'coins', 'amount': r.coins});
  if (r.glimmer > 0 && _addGlimmer(s, '$txn:glimmer', r.glimmer, 'season', now)) out.add({'kind': 'glimmer', 'amount': r.glimmer});
  r.items.forEach((id, n) {
    g.grantItem(s, id, n, 'season', now, txn);
    for (var i = 0; i < n; i++) {
      out.add({'kind': 'item', 'itemId': id});
    }
  });
  final t = r.title;
  if (t != null && !s.story.titleUnlocks.contains(t)) {
    s.story.titleUnlocks.add(t);
    out.add({'kind': 'title', 'title': titles[t] ?? t});
  }
  return out;
}

/// Claim every reached, unclaimed tier on both tracks (premium only with the pass).
g.ActionResult claimSeason(GameState state, int now, [SeasonDef se = currentSeason]) {
  final v = seasonView(state, now, se);
  if (v.claimable == 0) return _ok(state, [const g.GameEvent('season_nothing')]);
  final s = state.copy();
  final prog = s.economy.season(se.id);
  final rewards = <Map<String, Object?>>[];
  for (var t = 1; t <= v.tier; t++) {
    if (v.canClaim('free', t)) {
      prog.free.add(t);
      rewards.addAll(_grantSeason(s, seasonReward('free', t), 'season:${se.id}:free:$t', now));
    }
    if (v.canClaim('premium', t)) {
      prog.paid.add(t);
      rewards.addAll(_grantSeason(s, seasonReward('premium', t), 'season:${se.id}:premium:$t', now));
    }
  }
  return _ok(s, [g.GameEvent('season_claimed', {'rewards': rewards})]);
}

/// The premium track, for 500 Glimmer.
g.ActionResult buySeasonPass(GameState state, int now, [SeasonDef se = currentSeason]) {
  final v = seasonView(state, now, se);
  if (!v.active) return _fail(state, 'season_over');
  if (v.premium) return _ok(state, [const g.GameEvent('already_owned')]);
  if (glimmerOf(state) < se.passGlimmer) return _fail(state, 'need_glimmer', {'short': se.passGlimmer - glimmerOf(state)});
  final s = state.copy();
  _addGlimmer(s, 'season:${se.id}:pass', -se.passGlimmer, 'season_pass', now);
  s.economy.season(se.id).premium = true;
  return _ok(s, [g.GameEvent('season_pass', {'season': se.id})]);
}

/// One extra tier for 100 Glimmer (from week 3; it buys pass rewards, never story progress).
g.ActionResult buySeasonTier(GameState state, String requestId, int now, [SeasonDef se = currentSeason]) {
  final v = seasonView(state, now, se);
  if (!v.tiersOnSale) return _fail(state, 'not_on_sale');
  if (glimmerOf(state) < se.tierGlimmer) return _fail(state, 'need_glimmer', {'short': se.tierGlimmer - glimmerOf(state)});
  final s = state.copy();
  if (!_addGlimmer(s, 'season:${se.id}:tier:$requestId', -se.tierGlimmer, 'season_tier', now)) return _ok(state, [const g.GameEvent('already_purchased')]);
  s.economy.season(se.id).boughtTiers += 1;
  return _ok(s, [g.GameEvent('season_tier', {'tier': v.tier + 1})]);
}

/// A guardian calmed: 200 Season XP, once a day. Mutates [s].
void seasonBossAward(GameState s, int now, [SeasonDef se = currentSeason]) {
  final day = _today(s, now);
  if (se.activeOn(day)) s.economy.season(se.id).awards.putIfAbsent('boss:$day', () => se.bossXp);
}

// ================================================================ Starlight Caravan ====
class CaravanOffer {
  const CaravanOffer({required this.id, required this.itemId, required this.qty, required this.price, this.full = 0, this.section = 'rare', this.deal = false});
  final String id;
  final String itemId;
  final int qty;
  final int price; // Glimmer
  final int full; // the undiscounted price (0 = no discount)
  final String section; // rare | deals | charms
  final bool deal; // one per day
  int get off => full > price && full > 0 ? ((1 - price / full) * 100).round() : 0;
}

int _pack(int unit, int qty, double off) => (unit * qty * (1 - off)).round();

/// Today's Caravan stock: every working rare find singly and in five-packs (10% off), and three daily
/// deals picked for this player and day (two at 10% off, one at 20%).
List<CaravanOffer> caravanStock(GameState s, int now) {
  final out = <CaravanOffer>[];
  final day = _today(s, now);
  final r = g.seededRandom('${_pid(s)}:caravan:$day');
  final pool = List.of(activeRares)..shuffle(r);
  for (var i = 0; i < 3; i++) {
    final id = pool[i];
    final unit = catalog[id]!.glimmer!;
    final off = i == 0 ? 0.2 : 0.1;
    out.add(CaravanOffer(id: 'deal:$day:$i', itemId: id, qty: 2, price: _pack(unit, 2, off), full: unit * 2, section: 'deals', deal: true));
  }
  for (final id in activeRares) {
    final unit = catalog[id]!.glimmer!;
    out.add(CaravanOffer(id: 'one:$id', itemId: id, qty: 1, price: unit));
    out.add(CaravanOffer(id: 'five:$id', itemId: id, qty: 5, price: _pack(unit, 5, 0.1), full: unit * 5));
  }
  out.addAll(weekCharms(s, now));
  return out;
}

/// This week's charms at the Caravan: two of the five it can stock, chosen per player and week (rank I;
/// playing with a charm is what ranks it up). One of each, once.
List<CaravanOffer> weekCharms(GameState s, int now) {
  final week = weekKey(_today(s, now));
  final r = g.seededRandom('${_pid(s)}:charms:$week');
  final pool = [for (final d in charms.charmDefs.values) if (d.sold) d.id]..shuffle(r);
  return [
    for (final id in pool.take(2)) CaravanOffer(id: 'charm:$week:$id', itemId: id, qty: 1, price: catalog[id]!.glimmer!, section: 'charms'),
  ];
}

bool dealBought(GameState s, String offerId) => s.txns.any((t) => t.id == 'caravan:$offerId');

/// Buy a Caravan offer with Glimmer. A deal sells once a day; other offers take a fresh [requestId].
g.ActionResult buyCaravan(GameState state, String offerId, String requestId, int now) {
  final o = caravanStock(state, now).where((x) => x.id == offerId).firstOrNull;
  if (o == null) return _fail(state, 'not_in_stock');
  if (o.section == 'charms' && charms.ownsCharm(state, o.itemId)) return _fail(state, 'owned');
  final txn = o.deal || o.section == 'charms' ? 'caravan:${o.id}' : 'caravan:${o.id}:$requestId';
  if (state.txns.any((t) => t.id == txn)) return _ok(state, [g.GameEvent('already_purchased', {'offer': offerId})]);
  final bal = glimmerOf(state);
  if (bal < o.price) return _fail(state, 'need_glimmer', {'short': o.price - bal, 'price': o.price});
  final s = state.copy();
  _addGlimmer(s, txn, -o.price, 'caravan:${o.itemId}', now);
  g.grantItem(s, o.itemId, o.qty, 'caravan', now, txn);
  return _ok(s, [g.GameEvent('caravan_bought', {'itemId': o.itemId, 'qty': o.qty, 'price': o.price})]);
}

g.ActionResult markCaravanMet(GameState state) {
  if (state.economy.caravanMet) return _ok(state);
  final s = state.copy();
  s.economy.caravanMet = true;
  return _ok(s);
}

// ================================================================ Google Play products ====
class CashProduct {
  const CashProduct({required this.id, required this.name, required this.price, this.glimmer = 0, this.items = const {}, this.oneTime = false, this.plusDays = 0, this.pass = false, this.note = ''});
  final String id; // the Play product id
  final String name;
  final String price; // display price in USD (Play shows the local price once billing is live)
  final int glimmer;
  final Map<String, int> items;
  final bool oneTime;
  final int plusDays; // a subscription period
  final bool pass; // includes the Season Pass
  final String note;
}

const cashProducts = <CashProduct>[
  CashProduct(id: 'starter_pack', name: 'Starter Pack', price: '\$2.99', glimmer: 300, items: {'sunstone': 3, 'heartbloom': 1}, oneTime: true, note: 'Once per account'),
  CashProduct(id: 'glimmer_100', name: 'Glimmer Pouch', price: '\$0.99', glimmer: 100),
  CashProduct(id: 'glimmer_550', name: 'Glimmer Bag', price: '\$4.99', glimmer: 550, note: '+10%'),
  CashProduct(id: 'glimmer_1150', name: 'Glimmer Chest', price: '\$9.99', glimmer: 1150, note: '+15%'),
  CashProduct(id: 'glimmer_2400', name: 'Glimmer Crate', price: '\$19.99', glimmer: 2400, note: '+20%'),
  CashProduct(id: 'glimmer_6250', name: 'Glimmer Vault', price: '\$49.99', glimmer: 6250, note: '+25%'),
  CashProduct(id: 'glimmer_13000', name: 'Glimmer Hoard', price: '\$99.99', glimmer: 13000, note: '+30%'),
  CashProduct(id: 'pass_plus', name: 'Pass Plus', price: '\$14.99', pass: true, note: 'Season Pass + 10 tiers'),
  CashProduct(id: 'plus_monthly', name: 'Evochi Plus (monthly)', price: '\$4.99 / month', plusDays: 30),
  CashProduct(id: 'plus_yearly', name: 'Evochi Plus (yearly)', price: '\$39.99 / year', plusDays: 365),
];

CashProduct? cashProduct(String id) => cashProducts.where((p) => p.id == id).firstOrNull;

bool offerOwned(GameState s, String productId) => s.economy.offers.containsKey(productId);

/// A Google Play purchase arrives: grant it once (the order id is the key). The billing layer calls this
/// after the receipt checks out and completes the purchase only when it succeeds. Playtests pass a
/// 'test-' order id and are marked as such.
g.ActionResult grantPlayPurchase(GameState state, String productId, String orderId, int now, {String token = ''}) {
  final p = cashProduct(productId);
  if (p == null) return _fail(state, 'unknown_product');
  if (state.economy.purchases.any((x) => x.orderId == orderId)) return _ok(state, [g.GameEvent('already_granted', {'orderId': orderId})]);
  if (p.oneTime && offerOwned(state, p.id)) return _fail(state, 'already_owned');
  final s = state.copy();
  s.economy.purchases.add(PlayPurchase(orderId: orderId, product: productId, at: now, token: token));
  final txn = 'play:$orderId';
  final rewards = <Map<String, Object?>>[];
  if (p.glimmer > 0 && _addGlimmer(s, txn, p.glimmer, 'play:$productId', now)) rewards.add({'kind': 'glimmer', 'amount': p.glimmer});
  p.items.forEach((id, n) {
    g.grantItem(s, id, n, 'play', now, txn);
    for (var i = 0; i < n; i++) {
      rewards.add({'kind': 'item', 'itemId': id});
    }
  });
  if (p.oneTime) s.economy.offers[p.id] = now;
  if (p.pass) {
    final prog = s.economy.season(currentSeason.id);
    prog.premium = true;
    prog.boughtTiers += 10;
  }
  if (p.plusDays > 0) _startPlus(s, p.id, p.plusDays, now, test: orderId.startsWith('test-'));
  return _ok(s, [g.GameEvent('play_granted', {'product': productId, 'rewards': rewards})]);
}

/// Developer tools: grant Glimmer without a purchase (playtests only).
g.ActionResult grantGlimmerTest(GameState state, int amount, int now) {
  final s = state.copy();
  _addGlimmer(s, newId('test'), amount, 'playtest', now);
  return _ok(s);
}

/// A short, friendly reason for an economy error code (toasts).
String economyError(String code, [Map<String, Object?> info = const {}]) => switch (code) {
      'need_glimmer' => 'You need ${info['short']} more Glimmer.',
      'already_ripe' => 'That bed is already ripe.',
      'plot_empty' => 'Plant something first.',
      'no_beds' => 'No growing beds to water.',
      'not_dead' => 'Your Evochi is awake.',
      'already_armed' => 'One is already waiting to be used.',
      'not_owned' => "You don't have one.",
      'season_over' => 'This season has ended.',
      'not_on_sale' => 'Extra tiers go on sale in week ${currentSeason.tierSaleWeek}.',
      'already_owned' => 'Already yours.',
      'not_member' => 'That is an Evochi Plus perk.',
      _ => 'That did not work.',
    };
