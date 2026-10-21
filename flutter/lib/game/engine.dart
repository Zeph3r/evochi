// Evochi game engine: derived view + pure actions.
//
// Every action is `(state, ..., now) -> ActionResult` and never mutates its input.
// Invariants (style guide §22): XP, balances and claims never go negative; one pet per
// creation request; one item per equipment slot; evolution only moves forward; every
// grant/spend has a unique transaction id.

import 'dart:math' as math;

import '../app/constants.dart';
import '../core/models/catalog.dart';
import '../core/models/game_state.dart';
import '../core/utils/day_keys.dart';
import '../core/utils/ids.dart';
import 'bond/bond.dart';
import 'economy/economy.dart' as econ;
import 'evolution/evolution.dart';
import 'story/story.dart' as story;
import 'trails/trails.dart' as trails;
import 'vitality/vitality.dart';
import 'xp/step_aggregation.dart';
import 'xp/xp.dart';

class GameEvent {
  const GameEvent(this.type, [this.data = const {}]);
  final String type;
  final Map<String, Object?> data;
  @override
  String toString() => 'GameEvent($type, $data)';
}

class ActionResult {
  ActionResult(this.state, {this.events = const [], this.error, this.info = const {}});
  final GameState state;
  final List<GameEvent> events;
  final String? error;
  final Map<String, Object?> info;
  bool get ok => error == null;
}

ActionResult _ok(GameState s, [List<GameEvent> events = const []]) => ActionResult(s, events: events);
ActionResult _fail(GameState s, String error, [Map<String, Object?> info = const {}]) => ActionResult(s, error: error, info: info);

// ------------------------------------------------------------------ derived ----
class QuestView {
  QuestView({
    required this.def,
    required this.periodKey,
    required this.claimId,
    required this.progress,
    required this.target,
    required this.label,
    required this.eligible,
    required this.claimed,
  });
  final QuestDef def;
  final String periodKey;
  final String claimId;
  final int progress;
  final int target;
  final String label;
  final bool eligible;
  final bool claimed;
}

class PetView {
  PetView({
    required this.totalXp,
    required this.level,
    required this.activeDays,
    required this.lifetimeSteps,
    required this.vitality,
    required this.bond,
    required this.hearts,
    required this.evolution,
    required this.xpToday,
    required this.recoveryReadyAt,
    required this.petToday,
    required this.playToday,
    required this.daysTogether,
  });
  final int totalXp;
  final LevelInfo level;
  final int activeDays;
  final int lifetimeSteps;
  final VitalityResult vitality;
  final int bond;
  final int hearts;
  final EvolutionStatus evolution;
  final int xpToday;
  final int recoveryReadyAt;
  final bool petToday;
  final bool playToday;
  final int daysTogether;
  PetStatus get status => vitality.status;
  bool get dead => vitality.dead;
}

class GameView {
  GameView({
    required this.zone,
    required this.today,
    required this.days,
    required this.goal,
    required this.todaySteps,
    required this.todayUnverified,
    required this.todayXp,
    required this.balance,
    required this.pet,
    required this.quests,
  });
  final String zone;
  final String today;
  final Map<String, DayTotal> days;
  final int goal;
  final int todaySteps;
  final bool todayUnverified;
  final ActivityXp todayXp;
  final int balance;
  final PetView? pet;
  final List<QuestView> quests;
  int get claimable => quests.where((q) => q.eligible && !q.claimed).length;
}

String zoneOf(GameState s) => s.player?.timezone ?? s.tzHint;

int goalFor(GameState s, String key) {
  var g = s.player?.goal ?? GameConfig.current.defaultGoal;
  GoalChange? best;
  for (final h in s.player?.goalHistory ?? const <GoalChange>[]) {
    if (h.from.compareTo(key) <= 0 && (best == null || h.from.compareTo(best.from) >= 0)) best = h;
  }
  if (best != null) g = best.goal;
  return g;
}

/// A wallet balance: EvoCoins unless [currency] says otherwise ('glimmer').
int balanceOf(GameState s, [String currency = 'evocoin']) => s.txns.fold(0, (a, t) => t.currency == currency ? a + t.amount : a);
int ownedQty(GameState s, String id) => s.inventory[id]?.quantity ?? 0;

GameView derive(GameState s, int now) {
  final zone = zoneOf(s);
  final today = dayKey(now, zone);
  final days = aggregateDays(s.steps.samples, zone);
  final td = days[today] ?? const DayTotal(verified: 0, manual: 0);
  final goal = goalFor(s, today);
  PetView? pv;
  final p = s.pet;
  if (p != null) {
    final totalXp = p.xpAwarded.values.fold(0, (a, b) => a + b);
    final lv = levelInfo(totalXp);
    var active = 0;
    var lifetime = 0;
    days.forEach((k, d) {
      if (k.compareTo(p.createdDay) < 0) return;
      if (isActiveDay(d.steps, goalFor(s, k))) active++;
      lifetime += d.verified;
    });
    final vit = replayVitality(
      createdDay: p.createdDay,
      todayKey: today,
      days: days,
      goalFor: (k) => goalFor(s, k),
      events: p.events,
      syncedUntil: s.steps.syncedUntil,
      now: now,
      zone: zone,
    );
    final bond = bondValue(p.bondEvents);
    final lastRecovery = p.events.where((e) => e.type == 'care' && e.recovery).fold(0, (a, e) => math.max(a, e.t));
    pv = PetView(
      totalXp: totalXp,
      level: lv,
      activeDays: active,
      lifetimeSteps: lifetime,
      vitality: vit,
      bond: bond,
      hearts: bondHearts(bond),
      evolution: canEvolve(p.stage, lv.level, active),
      xpToday: p.xpAwarded[today] ?? 0,
      recoveryReadyAt: lastRecovery > 0 ? lastRecovery + GameConfig.current.recoveryCooldownHours * hourMs : 0,
      petToday: p.bondEvents.any((e) => e.key == today && e.type == 'pet'),
      playToday: p.bondEvents.any((e) => e.key == today && e.type == 'play'),
      daysTogether: math.max(1, ((now - p.createdAt) / dayMs).round() + 1),
    );
  }
  final view = GameView(
    zone: zone,
    today: today,
    days: days,
    goal: goal,
    todaySteps: td.steps,
    todayUnverified: td.unverified,
    todayXp: calculateDailyXp(td.steps, goal),
    balance: balanceOf(s),
    pet: pv,
    quests: const [],
  );
  return GameView(
    zone: zone,
    today: today,
    days: days,
    goal: goal,
    todaySteps: td.steps,
    todayUnverified: td.unverified,
    todayXp: view.todayXp,
    balance: view.balance,
    pet: pv,
    quests: questStatus(s, view),
  );
}

String _fmt(int n) {
  final str = n.toString();
  final b = StringBuffer();
  for (var i = 0; i < str.length; i++) {
    if (i > 0 && (str.length - i) % 3 == 0) b.write(',');
    b.write(str[i]);
  }
  return b.toString();
}

List<QuestView> questStatus(GameState s, GameView d) {
  final pet = s.pet;
  final week = weekKey(d.today);
  final out = <QuestView>[];
  for (final q in GameConfig.current.quests) {
    final period = q.period == 'week' ? week : d.today;
    final claimId = '${q.id}@$period';
    var progress = 0;
    var target = 1;
    var label = '';
    if (q.ratio != null) {
      target = (q.ratio! * d.goal).ceil();
      progress = math.min(d.todaySteps, target);
      label = '${_fmt(d.todaySteps)} / ${_fmt(target)} steps';
    } else if (q.interaction) {
      progress = (d.pet != null && (d.pet!.petToday || d.pet!.playToday)) ? 1 : 0;
      label = progress == 1 ? 'Done' : 'Not yet';
    } else if (q.goalDays != null) {
      target = q.goalDays!;
      progress = weekDays(d.today).where((k) {
        final day = d.days[k];
        return day != null && day.steps >= goalFor(s, k) && (pet == null || k.compareTo(pet.createdDay) >= 0);
      }).length;
      progress = math.min(progress, target);
      label = '$progress / $target days';
    }
    final eligible = pet != null && progress >= target && !(d.pet != null && d.pet!.dead && q.interaction);
    out.add(QuestView(
      def: q,
      periodKey: period,
      claimId: claimId,
      progress: progress,
      target: target,
      label: label,
      eligible: eligible,
      claimed: s.claims.containsKey(claimId),
    ));
  }
  return out;
}

// -------------------------------------------------------------- deterministic RNG ----
int _hash(String str) {
  var h = 2166136261;
  for (final c in str.codeUnits) {
    h ^= c;
    h = (h * 16777619) & 0xFFFFFFFF;
  }
  return h;
}

/// Seeded RNG so chest and cosmetic rolls are idempotent per claim.
math.Random seededRandom(String seed) => math.Random(_hash(seed));

// ------------------------------------------------------------- player setup ----
ActionResult startGuest(GameState state, int now, String zone, {String accountType = 'guest', String? email}) {
  if (state.player != null) return _ok(state);
  final s = state.copy();
  s.player = Player(
    id: newId('player'),
    accountType: accountType,
    email: email,
    timezone: zone,
    createdAt: now,
    goal: GameConfig.current.defaultGoal,
  );
  s.onboarding.step = 'create';
  return _ok(s, const [GameEvent('player_created')]);
}

class NameCheck {
  const NameCheck(this.ok, this.name, this.error);
  final bool ok;
  final String name;
  final String? error;
}

NameCheck validateName(String raw) {
  final n = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  final c = GameConfig.current;
  if (n.length < c.nameMin) return const NameCheck(false, '', 'Give your Evochi a name.');
  if (n.length > c.nameMax) return NameCheck(false, '', 'Names can be up to ${c.nameMax} characters.');
  if (!RegExp(r"^[\p{L}\p{N}][\p{L}\p{N} '\-]*$", unicode: true).hasMatch(n)) {
    return const NameCheck(false, '', "Use letters, numbers, spaces, - or '.");
  }
  return NameCheck(true, n, null);
}

/// Creates the Evochi exactly once per request id (retries never duplicate).
ActionResult createPet(GameState state, {required String name, required String paletteId, required String requestId, required int now}) {
  if (state.player == null) return _fail(state, 'no_player');
  if (state.pet != null) {
    if (state.pet!.requestId == requestId) return _ok(state);
    return _fail(state, 'pet_exists');
  }
  final v = validateName(name);
  if (!v.ok) return _fail(state, 'invalid_name', {'message': v.error});
  if (!palettes.any((p) => p.id == paletteId)) return _fail(state, 'invalid_palette');
  final s = state.copy();
  final today = dayKey(now, s.player!.timezone);
  s.pet = Pet(
    id: newId('pet'),
    requestId: requestId,
    name: v.name,
    paletteId: paletteId,
    stage: 1,
    habitatId: 'sunlit_meadow',
    createdAt: now,
    createdDay: today,
    evolutions: [
      {'stage': 1, 'at': now}
    ],
  );
  if (s.flags['starterGranted'] != true) {
    GameConfig.current.starterItems.forEach((id, q) => _grant(s, id, q, 'starter', now));
    s.placements.addAll(GameConfig.current.starterPlacements);
    s.flags['starterGranted'] = true;
  }
  s.unlocks.putIfAbsent('stage:lizard:1', () => now);
  s.unlocks.putIfAbsent('palette:$paletteId', () => now);
  s.onboarding.step = s.pastPets.isNotEmpty ? 'awakening' : (s.steps.connection == 'none' ? 'connect' : 'goal');
  return _ok(s, [GameEvent('pet_created', {'petId': s.pet!.id})]);
}

ActionResult setConnection(GameState state, String connection, int now) {
  final s = state.copy();
  s.steps.connection = connection;
  if ((connection == 'demo' || connection == 'health') && s.steps.syncedUntil == 0) s.steps.syncedUntil = now;
  return _ok(s);
}

ActionResult setGoal(GameState state, int goal, int now) {
  final c = GameConfig.current;
  if (goal < c.goalMin || goal > c.goalMax) return _fail(state, 'invalid_goal');
  final s = state.copy();
  final today = dayKey(now, s.player!.timezone);
  s.player!.goal = goal;
  s.player!.goalHistory.removeWhere((h) => h.from == today);
  s.player!.goalHistory.add(GoalChange(today, goal));
  return _ok(s);
}

ActionResult setOnboardingStep(GameState state, String step) {
  final s = state.copy();
  s.onboarding.step = step;
  return _ok(s);
}

ActionResult setTimezone(GameState state, String zone) {
  final s = state.copy();
  s.player!.timezone = zone;
  return _ok(s);
}

ActionResult renamePet(GameState state, String name) {
  final v = validateName(name);
  if (!v.ok) return _fail(state, 'invalid_name', {'message': v.error});
  final s = state.copy();
  s.pet!.name = v.name;
  return _ok(s);
}

// --------------------------------------------------------------- step sync ----
/// Merges verified observations and awards newly-earned XP exactly once.
/// Re-delivered samples change nothing; downward corrections are audited, never clawed back.
ActionResult syncSteps(GameState state, List<StepSample> samples, int now, {String source = 'health', bool success = true}) {
  if (!success) {
    final s = state.copy();
    s.steps.lastError = now;
    return _ok(s, const [GameEvent('sync_failed')]);
  }
  final s = state.copy();
  final zone = zoneOf(s);
  final today = dayKey(now, zone);
  // days older than the retention window are sealed (compacted totals are final)
  final sealed = addDays(today, -14);
  final fresh = samples.where((x) => dayKey(x.start, zone).compareTo(sealed) >= 0).toList();
  final merged = mergeSamples(s.steps.samples, fresh);
  s.steps.samples = compactSamples(merged.list, zone, today);
  s.steps.syncedUntil = math.max(s.steps.syncedUntil, now);
  s.steps.lastSync = now;
  s.steps.lastSource = source;
  if (s.audit.length > 200) s.audit = s.audit.sublist(s.audit.length - 200);
  // story walks and Trail Guild discoveries advance from the same de-duplicated samples
  // (account-level, so even without a pet)
  final storyEvents = [...story.applyStoryProgress(s, now), ...trails.applyTrailProgress(s, now)];
  final events = <GameEvent>[];
  final pet = s.pet;
  if (pet == null) return _ok(s, [...storyEvents, GameEvent('synced', {'added': merged.added})]);
  final before = derive(state, now);
  final days = aggregateDays(s.steps.samples, zone);
  var gained = 0;
  days.forEach((k, d) {
    if (k.compareTo(pet.createdDay) < 0 || k.compareTo(today) > 0) return;
    final goal = goalFor(s, k);
    final elig = calculateDailyXp(d.steps, goal).total;
    final awarded = pet.xpAwarded[k] ?? 0;
    if (elig > awarded) {
      pet.xpAwarded[k] = elig;
      gained += elig - awarded;
    } else if (elig < awarded) {
      s.audit.add({'t': now, 'type': 'step_correction', 'day': k, 'eligible': elig, 'awarded': awarded});
    }
    if (d.steps >= goal && !pet.bondEvents.any((e) => e.key == k && e.type == 'goal')) {
      pet.bondEvents.add(BondEvent(key: k, type: 'goal', t: now));
      if (k == today) events.add(const GameEvent('goal_met'));
    }
  });
  final after = derive(s, now);
  if (gained > 0) events.add(GameEvent('xp', {'amount': gained}));
  if (after.pet!.level.level > before.pet!.level.level) events.add(GameEvent('level_up', {'level': after.pet!.level.level}));
  if (after.pet!.evolution.eligible && !before.pet!.evolution.eligible) {
    events.add(GameEvent('evolution_ready', {'stage': after.pet!.evolution.next}));
  }
  for (final q in after.quests) {
    final was = before.quests.firstWhere((b) => b.def.id == q.def.id);
    if (q.eligible && !q.claimed && !was.eligible) events.add(GameEvent('quest_ready', {'questId': q.def.id, 'title': q.def.title}));
  }
  if (before.pet!.dead && !after.pet!.dead) events.add(const GameEvent('recovered'));
  events.addAll(storyEvents); // last, so the story toasts are the ones left showing
  events.add(GameEvent('synced', {'added': merged.added}));
  return _ok(s, events);
}

// ------------------------------------------------------------ interactions ----
ActionResult interact(GameState state, String kind, int now) {
  if (state.pet == null) return _fail(state, 'no_pet');
  final d = derive(state, now);
  if (d.pet!.dead) return _fail(state, 'pet_dead');
  final s = state.copy();
  final events = <GameEvent>[GameEvent('interact', {'kind': kind})];
  if (!s.pet!.bondEvents.any((e) => e.key == d.today && e.type == kind)) {
    s.pet!.bondEvents.add(BondEvent(key: d.today, type: kind, t: now));
    final gain = derive(s, now).pet!.bond - d.pet!.bond;
    if (gain > 0) events.add(GameEvent('bond', {'amount': gain}));
  }
  return _ok(s, events);
}

// ------------------------------------------------------------------ wallet ----
bool _addTxn(GameState s, WalletTxn t) {
  if (s.txns.any((x) => x.id == t.id)) return false;
  s.txns.add(t);
  return true;
}

/// Append a wallet transaction once (ids are unique; a repeat is ignored). Mutates [s].
bool addTxn(GameState s, WalletTxn t) => _addTxn(s, t);

/// Add an item to the shared inventory. Mutates [s].
void grantItem(GameState s, String itemId, int qty, String source, int now, [String? txnId]) => _grant(s, itemId, qty, source, now, txnId);

void _grant(GameState s, String itemId, int qty, String source, int now, [String? txnId]) {
  final cur = s.inventory.putIfAbsent(itemId, () => Ownership());
  cur.quantity += qty;
  cur.acquisitions.add(Acquisition(at: now, source: source, qty: qty, txnId: txnId));
}

ActionResult claimQuest(GameState state, String questId, int now) {
  final d = derive(state, now);
  final matches = d.quests.where((x) => x.def.id == questId).toList();
  if (matches.isEmpty) return _fail(state, 'unknown_quest');
  final q = matches.first;
  if (q.claimed) return _ok(state, [GameEvent('already_claimed', {'questId': questId})]);
  if (!q.eligible) return _fail(state, 'not_eligible');
  final s = state.copy();
  final txnId = 'quest:${q.claimId}';
  _addTxn(s, WalletTxn(id: txnId, amount: q.def.coins, cause: 'quest:${q.def.id}', at: now));
  final rewards = <Map<String, Object?>>[
    {'kind': 'coins', 'amount': q.def.coins}
  ];
  final verifiedDay = !d.todayUnverified || GameConfig.current.manualAllowsChests;
  String? tier;
  if (q.def.chest && verifiedDay) {
    // the tiered daily chest (economy plan): Wooden, Silver, Gold or Lumen
    final c = econ.openDailyChest(s, d, txnId, now);
    tier = c.tier;
    rewards.addAll(c.rewards);
  }
  if (q.def.period == 'week' && q.def.goalDays != null) rewards.addAll(econ.weeklyBonus(s, txnId, now));
  if (q.def.cosmeticChance > 0 && verifiedDay) {
    final r = seededRandom('${s.player!.id}:${q.claimId}:cosmetic');
    if (r.nextDouble() < q.def.cosmeticChance) {
      // only Market wearables: story rewards are earned, never rolled
      final pool = catalog.values.where((it) => it.category == ItemCategory.wearable && isShopItem(it.id) && ownedQty(s, it.id) == 0).toList();
      if (pool.isNotEmpty) {
        final pick = pool[r.nextInt(pool.length)];
        _grant(s, pick.id, 1, 'quest', now, txnId);
        rewards.add({'kind': 'item', 'itemId': pick.id});
      }
    }
  }
  s.claims[q.claimId] = {'claimedAt': now, 'txnId': txnId};
  return _ok(s, [GameEvent('claimed', {'questId': questId, 'rewards': rewards, if (tier != null) 'tier': tier})]);
}

// -------------------------------------------------------------------- shop ----
ActionResult purchase(GameState state, String itemId, String requestId, int now) {
  final it = catalog[itemId];
  if (it == null) return _fail(state, 'unknown_item');
  if (!isShopItem(itemId)) return _fail(state, 'not_for_sale');
  final txnId = 'purchase:$requestId';
  if (state.txns.any((t) => t.id == txnId)) return _ok(state, [GameEvent('already_purchased', {'itemId': itemId})]);
  if (!it.isStackable && ownedQty(state, itemId) > 0) return _fail(state, 'owned');
  final bal = balanceOf(state);
  if (bal < it.price) return _fail(state, 'insufficient', {'short': it.price - bal});
  final s = state.copy();
  _addTxn(s, WalletTxn(id: txnId, amount: -it.price, cause: 'purchase:$itemId', at: now));
  _grant(s, itemId, 1, 'shop', now, txnId);
  return _ok(s, [GameEvent('purchased', {'itemId': itemId})]);
}

// --------------------------------------------------------------- inventory ----
ActionResult equip(GameState state, String itemId, int now) {
  final it = catalog[itemId];
  if (it == null || it.category != ItemCategory.wearable) return _fail(state, 'not_wearable');
  if (it.pendingArt) return _fail(state, 'art_pending');
  if (ownedQty(state, itemId) < 1) return _fail(state, 'not_owned');
  if (state.pet == null) return _fail(state, 'no_pet');
  if (!itemCompatible(itemId, state.pet!.stage)) return _fail(state, 'incompatible');
  final s = state.copy();
  final prev = s.pet!.equipped[it.slot!];
  s.pet!.equipped[it.slot!] = itemId;
  return _ok(s, [GameEvent('equipped', {'itemId': itemId, 'slot': it.slot, 'replaced': prev})]);
}

ActionResult unequip(GameState state, String slot) {
  if (state.pet?.equipped[slot] == null) return _ok(state);
  final s = state.copy();
  final prev = s.pet!.equipped.remove(slot);
  return _ok(s, [GameEvent('unequipped', {'itemId': prev, 'slot': slot})]);
}

/// Has the pet had its homemade treat today? (A treat adds Bond once a day.)
bool treatGivenToday(GameState s, String today) => s.pet?.bondEvents.any((e) => e.key == today && e.type == 'treat') ?? false;

ActionResult useConsumable(GameState state, String itemId, int now) {
  final it = catalog[itemId];
  if (it == null || it.category != ItemCategory.consumable) return _fail(state, 'not_consumable');
  if (ownedQty(state, itemId) < 1) return _fail(state, 'not_owned');
  if (it.growth > 0) return _fail(state, 'use_in_garden'); // Sprout Tonic: poured on a garden bed
  if (it.isRare) return _fail(state, 'use_rare'); // rare finds have their own uses (economy.dart)
  final d = derive(state, now);
  if (d.pet == null) return _fail(state, 'no_pet');
  if (d.pet!.dead) return _fail(state, 'pet_dead');
  // a homemade treat still counts for Bond once a day, even when vitality is already full
  final treat = it.treat && !treatGivenToday(state, d.today);
  final vit = d.pet!.vitality.vitality;
  if (vit >= 100 && !treat) return _fail(state, 'full');
  if (it.recovery && d.pet!.recoveryReadyAt > now) return _fail(state, 'cooldown', {'readyAt': d.pet!.recoveryReadyAt});
  final s = state.copy();
  s.inventory[itemId]!.quantity -= 1; // decrement only after the action is accepted
  final gain = math.min(it.vitality, math.max(0, 100 - vit));
  s.pet!.events.add(PetEvent(t: now, type: 'care', amount: it.vitality, itemId: itemId, recovery: it.recovery));
  final events = <GameEvent>[GameEvent('used', {'itemId': itemId, 'vitality': gain})];
  if (treat) {
    s.pet!.bondEvents.add(BondEvent(key: d.today, type: 'treat', t: now));
    final b = derive(s, now).pet!.bond - d.pet!.bond;
    events.add(GameEvent('treat', {'itemId': itemId, 'bond': b}));
    if (b > 0) events.add(GameEvent('bond', {'amount': b}));
  }
  return _ok(s, events);
}

ActionResult placeDecoration(GameState state, String itemId, String slotId) {
  final it = catalog[itemId];
  if (it == null || it.category != ItemCategory.decoration) return _fail(state, 'not_decoration');
  if (it.pendingArt) return _fail(state, 'art_pending');
  final slot = decorSlots[slotId];
  if (slot == null || slot.accepts != it.decor) return _fail(state, 'no_anchor');
  final placedElsewhere = state.placements.entries.where((e) => e.value == itemId && e.key != slotId).length;
  if (placedElsewhere >= ownedQty(state, itemId)) return _fail(state, 'all_placed');
  final s = state.copy();
  s.placements[slotId] = itemId;
  return _ok(s, [GameEvent('placed', {'itemId': itemId, 'slotId': slotId})]);
}

ActionResult removeDecoration(GameState state, String slotId) {
  final s = state.copy();
  s.placements.remove(slotId);
  return _ok(s, [GameEvent('removed', {'slotId': slotId})]);
}

// --------------------------------------------------------------- evolution ----
ActionResult evolve(GameState state, int now) {
  final d = derive(state, now);
  if (d.pet == null) return _fail(state, 'no_pet');
  if (d.pet!.dead) return _fail(state, 'pet_dead');
  if (!d.pet!.evolution.eligible) return _fail(state, 'not_eligible');
  final s = state.copy();
  final next = s.pet!.stage + 1;
  if (next > 3) return _fail(state, 'invalid_stage');
  s.pet!.stage = next;
  s.pet!.evolutions.add({'stage': next, 'at': now});
  final removed = <String>[];
  for (final e in s.pet!.equipped.entries.toList()) {
    if (!itemCompatible(e.value, next)) {
      s.pet!.equipped.remove(e.key); // returned to inventory: ownership is untouched
      removed.add(e.value);
    }
  }
  s.unlocks.putIfAbsent('stage:lizard:$next', () => now);
  final bonus = econ.milestoneGlimmer(s, 'evolve:$next', 30, now);
  return _ok(s, [GameEvent('evolved', {'stage': next, 'removed': removed, if (bonus != null) 'glimmer': bonus['amount']})]);
}

// ------------------------------------------------------ recovery / memorial ----
ActionResult reviveWithHerbs(GameState state, int now) {
  final d = derive(state, now);
  if (d.pet == null || !d.pet!.dead) return _fail(state, 'not_dead');
  final cost = GameConfig.current.reviveHerbCost;
  if (ownedQty(state, 'healing_herb') < cost) return _fail(state, 'need_herbs', {'need': cost});
  final s = state.copy();
  s.inventory['healing_herb']!.quantity -= cost;
  s.pet!.events.add(PetEvent(t: now, type: 'revive', amount: GameConfig.current.reviveVitality, via: 'herbs'));
  return _ok(s, [const GameEvent('revived', {'via': 'herbs'})]);
}

/// Free, activity-based revival: reach today's full goal.
ActionResult reviveWithWalk(GameState state, int now) {
  final d = derive(state, now);
  if (d.pet == null || !d.pet!.dead) return _fail(state, 'not_dead');
  if (d.todaySteps < d.goal) return _fail(state, 'walk_needed', {'remaining': d.goal - d.todaySteps});
  final s = state.copy();
  s.pet!.events.add(PetEvent(t: now, type: 'revive', amount: GameConfig.current.reviveVitality, via: 'walk'));
  return _ok(s, [const GameEvent('revived', {'via': 'walk'})]);
}

ActionResult memorialize(GameState state, int now) {
  final d = derive(state, now);
  if (d.pet == null) return _fail(state, 'no_pet');
  final s = state.copy();
  final p = s.pet!;
  s.pastPets.add(PastPet(
    id: p.id,
    name: p.name,
    paletteId: p.paletteId,
    stage: p.stage,
    peakLevel: d.pet!.level.level,
    createdAt: p.createdAt,
    endedAt: now,
    daysTogether: d.pet!.daysTogether,
    lifetimeSteps: d.pet!.lifetimeSteps,
  ));
  s.pet = null;
  s.onboarding = Onboarding(step: 'create', draftPalette: p.paletteId);
  return _ok(s, [const GameEvent('memorialized')]);
}

// ------------------------------------------------------------------- debug ----
ActionResult grantCoins(GameState state, int amount, int now, {String cause = 'playtest'}) {
  final s = state.copy();
  _addTxn(s, WalletTxn(id: newId('txn'), amount: amount, cause: cause, at: now));
  return _ok(s);
}
