// Lumen Trails: the Trail Guild's daily discoveries, encounter quests, the encounter engine (calm,
// befriend, restore) and companions. Mirrors web/src/game/trails.js.
//
// Lore: ancient Lumen Trails once joined every corner of the Evochi world. Lumen is made by movement,
// exploration and bonds, so your real steps restore the trails. Encounters are never fights to the
// finish: wild Evochi are calmed and befriended, Hollow-tangled guardians are restored. Your Evochi
// never faints; you can always retreat and try again.
//
// Rules of thumb:
//  - three authored discoveries a day, picked deterministically per account and day, never random
//  - discovery walks count steps after you begin them (same fresh-sample counting as the story)
//  - encounter quests live in the story engine (line 'trail'); the encounter itself is the hand-in
//  - the encounter is a pure turn-based state machine seeded per attempt, so it replays the same way
//
// Every action is `(state, ..., now) -> ActionResult` and never mutates its input.

import 'dart:math' as math;

import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';
import '../../core/models/trails_state.dart';
import '../engine.dart';
import '../story/story.dart' as story;

ActionResult _ok(GameState s, [List<GameEvent> events = const []]) => ActionResult(s, events: events);
ActionResult _fail(GameState s, String error, [Map<String, Object?> info = const {}]) => ActionResult(s, error: error, info: info);

// ---------------------------------------------------------------------- lore ----
class TrailLore {
  const TrailLore._();
  static const title = 'The Fading Paths';
  static const intro =
      'Long ago, luminous paths called Lumen Trails connected every corner of the Evochi world. Lumen is made by movement, exploration and the bonds between living things. Now many paths have faded, dimmed by time and the mysterious Hollow.';
  static const trails =
      'As you explore, befriend Evochi and take more steps together, the Lumen Trails begin to shine again. Every encounter, however small, helps restore light to the world.';
  static const guild =
      'The Trail Guild was formed to restore the pathways. Every day it posts small discoveries, and now and then a trail leads somewhere no one has walked in a very long time.';
}

// --------------------------------------------------------------------- guild ----
class GuildRank {
  const GuildRank(this.id, this.name, this.xp);
  final String id;
  final String name;
  final int xp; // guild XP the rank starts at
}

const guildRanks = [
  GuildRank('wanderer', 'Wanderer', 0),
  GuildRank('trail_friend', 'Trail Friend', 40),
  GuildRank('pathfinder', 'Pathfinder', 120),
  GuildRank('lightkeeper', 'Lightkeeper', 260),
  GuildRank('trailwarden', 'Trailwarden', 480),
];

/// The rank for [xp], the next one (null at the top) and progress toward it.
class GuildRankView {
  const GuildRankView({required this.rank, required this.xp, required this.next, required this.into, required this.need});
  final GuildRank rank;
  final int xp;
  final GuildRank? next;
  final int into; // XP into the current rank
  final int need; // XP the current rank spans (0 at the top)
  String get id => rank.id;
  String get name => rank.name;
  double get pct => next == null || need == 0 ? 1.0 : into / need;
}

GuildRankView guildRank(int xp) {
  var cur = guildRanks.first;
  GuildRank? next;
  for (final r in guildRanks) {
    if (xp >= r.xp) {
      cur = r;
    } else {
      next = r;
      break;
    }
  }
  return GuildRankView(rank: cur, xp: xp, next: next, into: xp - cur.xp, need: next == null ? 0 : next.xp - cur.xp);
}

// ---------------------------------------------------------------- affinities ----
class Affinity {
  const Affinity(this.id, this.name, this.icon, this.color, this.explore, this.ability);
  final String id;
  final String name;
  final String icon;
  final int color; // ARGB
  final String explore;
  final String ability;
}

const affinityDefs = <String, Affinity>{
  'nature': Affinity('nature', 'Nature', 'aff_nature', 0xFF5FA046, 'Grows blocked pathways', 'Root Snare'),
  'ember': Affinity('ember', 'Ember', 'aff_ember', 0xFFEC7A4A, 'Lights ancient torches', 'Spark Burst'),
  'water': Affinity('water', 'Water', 'aff_water', 0xFF4C9BCC, 'Crosses aquatic obstacles', 'Healing Mist'),
  'stone': Affinity('stone', 'Stone', 'aff_stone', 0xFF8E887E, 'Opens cave passages', 'Stone Guard'),
  'celestial': Affinity('celestial', 'Celestial', 'aff_celestial', 0xFF9975C9, 'Reveals hidden ruins', 'Starlight Beam'),
  'lumen': Affinity('lumen', 'Lumen', 'trail', 0xFFF4B84E, 'Walks the old trails', 'Lumen Glow'),
};

// ----------------------------------------------------------------- creatures ----
class CreatureStates {
  const CreatureStates(this.start, this.mid, this.done);
  final String start;
  final String mid;
  final String done;
}

class CompanionAbility {
  const CompanionAbility(this.ability, this.name, this.text);
  final String ability; // the encounter action id
  final String name;
  final String text;
}

class Creature {
  const Creature({
    required this.id,
    required this.name,
    required this.affinity,
    required this.kind,
    required this.rarity,
    required this.size,
    required this.traits,
    required this.home,
    required this.blurb,
    required this.likes,
    required this.states,
    this.companion,
    this.boss = false,
  });
  final String id;
  final String name;
  final String affinity;
  final String kind; // wild | hollow
  final String rarity;
  final String size; // small | large
  final List<String> traits;
  final String home;
  final String blurb;
  final List<String> likes; // items it loves (x1.5 in an encounter)
  final CreatureStates states; // sprite state at the start, past half way, and when done
  final CompanionAbility? companion; // what it does for you once befriended
  final bool boss;
}

const creatureDefs = <String, Creature>{
  'petalune': Creature(
    id: 'petalune',
    name: 'Petalune',
    affinity: 'nature',
    kind: 'wild',
    rarity: 'rare',
    size: 'small',
    traits: ['Nature', 'Gentle', 'Flower Crest'],
    home: 'Mossy Ruins',
    blurb: 'A gentle Evochi that spreads seeds wherever it goes. Said to lead others to hidden Lumen Trails.',
    likes: ['sunberry_tart', 'carrot_stew', 'golden_bun'],
    states: CreatureStates('wary', 'neutral', 'happy'),
    companion: CompanionAbility('petal_hush', 'Petal Hush', 'Petalune hums softly: +12 Calm (or -12 Instability), once an encounter.'),
  ),
  'hollow_sprout': Creature(
    id: 'hollow_sprout',
    name: 'Hollow Sprout',
    affinity: 'nature',
    kind: 'hollow',
    rarity: 'uncommon',
    size: 'small',
    traits: ['Hollow', 'Nature (faded)', 'Shy'],
    home: 'Mossy Ruins',
    blurb: 'A once-thriving forest Evochi, now covered in Hollow growth. It reacts to kindness and care.',
    likes: ['glowleaf', 'meadow_tea', 'healing_herb'],
    states: CreatureStates('hollow', 'hollow', 'restored'),
  ),
  'sentinel': Creature(
    id: 'sentinel',
    name: 'Forgotten Sentinel',
    affinity: 'celestial',
    kind: 'hollow',
    rarity: 'legendary',
    size: 'large',
    boss: true,
    traits: ['Hollow', 'Celestial (faded)', 'Ancient'],
    home: 'The old gate past the bridge',
    blurb: 'A guardian of the Lumen Trails. Its light is dim, but it still listens. Help it remember.',
    likes: ['lantern_tonic', 'glowleaf_tonic', 'moonlight_draught'],
    states: CreatureStates('hollow', 'waking', 'restored'),
  ),
};
const creatureOrder = ['petalune', 'hollow_sprout', 'sentinel'];

// --------------------------------------------------------------- discoveries ----
class DiscoveryReward {
  const DiscoveryReward({this.coins = 0, this.items = const {}, this.guildXp = 0});
  final int coins;
  final Map<String, int> items;
  final int guildXp;
}

/// What must be true for a discovery to be posted: a story flag, or a completed quest.
class DiscoveryNeeds {
  const DiscoveryNeeds({this.flag, this.quest});
  final String? flag;
  final String? quest;
}

/// An authored discovery (never a random objective). [place] is where the glinting clue appears once
/// the walk is done.
class Discovery {
  const Discovery({
    required this.id,
    required this.title,
    required this.place,
    required this.steps,
    required this.icon,
    required this.clue,
    required this.found,
    required this.reward,
    this.needs,
  });
  final String id;
  final String title;
  final String place; // glasshouse | workshop | lodge | waystone | homemap | garden | cottage | ruins | gate
  final int steps;
  final String icon; // an item id or an icon name
  final String clue;
  final String found;
  final DiscoveryReward reward;
  final DiscoveryNeeds? needs;
}

const discoveryDefs = <String, Discovery>{
  'd_seed_pouch': Discovery(
      id: 'd_seed_pouch',
      title: 'The Missing Seed Pouch',
      place: 'glasshouse',
      steps: 1500,
      icon: 'seed_sunberry',
      clue: 'Mira has lost a pouch of seeds somewhere between the seedling trays.',
      found: 'Tucked behind a watering can: a pouch of seeds, and a very relieved Mira.',
      reward: DiscoveryReward(coins: 20, items: {'seed_sunberry': 2, 'seed_meadow_carrot': 1}, guildXp: 12)),
  'd_footprint': Discovery(
      id: 'd_footprint',
      title: 'A Strange Footprint',
      place: 'lodge',
      steps: 2500,
      icon: 'discover',
      clue: 'Pip found a small, leafy footprint by the courier counter. Investigate where it leads.',
      found: 'The prints circle the map table and stop at the window. Something small has been watching the village.',
      reward: DiscoveryReward(coins: 30, items: {'lumen_shard': 1}, guildXp: 18)),
  'd_flicker': Discovery(
      id: 'd_flicker',
      title: 'The Flickering Lantern',
      place: 'workshop',
      steps: 1200,
      icon: 'explorer_lantern',
      clue: "Bram's spare lantern keeps flickering. Take a look at the wick.",
      found: 'A Lumenbud seed had rooted in the wick. Bram keeps it in a jar on the sill now.',
      reward: DiscoveryReward(coins: 25, items: {'healing_herb': 1}, guildXp: 12)),
  'd_waystone_hum': Discovery(
      id: 'd_waystone_hum',
      title: 'A Hum in the Stone',
      place: 'waystone',
      steps: 2000,
      icon: 'star',
      clue: 'Alder swears the Waystone hums on quiet evenings. Listen closely.',
      found: 'With your ear to the stone you hear it: a faint, steady note, like a path remembering itself.',
      reward: DiscoveryReward(coins: 30, items: {'lumen_shard': 1}, guildXp: 16)),
  'd_pond_glint': Discovery(
      id: 'd_pond_glint',
      title: 'A Glint in the Pond',
      place: 'homemap',
      steps: 1000,
      icon: 'lumen_shard',
      clue: 'Something glitters in the pond by your nest after a walk.',
      found: 'A sliver of Lumen, cool and bright, washed up among the lily pads.',
      reward: DiscoveryReward(coins: 15, items: {'lumen_shard': 1}, guildXp: 10)),
  'd_night_moth': Discovery(
      id: 'd_night_moth',
      title: 'The Glow Moths',
      place: 'garden',
      steps: 1500,
      icon: 'skill_farming',
      clue: 'Glow moths gather in gardens where Lumen is strong. See if any have come to yours.',
      found: 'Three pale moths rest on the bed posts. Where they sat, the soil feels warm and ready.',
      reward: DiscoveryReward(coins: 20, items: {'seed_glowleaf': 1}, guildXp: 14),
      needs: DiscoveryNeeds(quest: 'hq01')),
  'd_old_letter': Discovery(
      id: 'd_old_letter',
      title: 'The Letter in the Wall',
      place: 'cottage',
      steps: 1800,
      icon: 'q_sealed_trail_letter',
      clue: 'Bram says the old cottage wall had a loose stone with something behind it.',
      found: 'A letter, decades old: a Trail Guild walker writing home about a stone that sings. The last line: "Keep walking. The paths remember us."',
      reward: DiscoveryReward(coins: 35, items: {'lumen_shard': 1}, guildXp: 20),
      needs: DiscoveryNeeds(flag: 'cottage_restored')),
  'd_herb_run': Discovery(
      id: 'd_herb_run',
      title: 'Herbs for the Guild',
      place: 'lodge',
      steps: 1500,
      icon: 'healing_herb',
      clue: 'The Guild keeps a first-aid shelf stocked. Walk a round of the village and check it.',
      found: 'The shelf was bare. You restock it from the basket by the door, and Pip pays you back in coins.',
      reward: DiscoveryReward(coins: 40, guildXp: 12)),
  'd_moss_runes': Discovery(
      id: 'd_moss_runes',
      title: 'Runes under the Moss',
      place: 'ruins',
      steps: 2000,
      icon: 'ancient_relic',
      clue: 'The Mossy Ruins have more carvings than anyone has catalogued. Clear a little moss.',
      found: 'Under the moss, a line of trail runes points away from the village, toward the north road.',
      reward: DiscoveryReward(coins: 35, items: {'lumen_shard': 1}, guildXp: 22),
      needs: DiscoveryNeeds(quest: 'eq01')),
  'd_petal_trail': Discovery(
      id: 'd_petal_trail',
      title: 'A Trail of Petals',
      place: 'ruins',
      steps: 1200,
      icon: 'creature_petalune',
      clue: 'Petals keep appearing on the path to the ruins. Follow them.',
      found: 'The petals end at the arch, where a small flower has grown overnight in a crack of the stone.',
      reward: DiscoveryReward(coins: 20, items: {'seed_glowleaf': 1}, guildXp: 14),
      needs: DiscoveryNeeds(quest: 'eq01')),
};
final discoveryOrder = discoveryDefs.keys.toList();
const discoveriesPerDay = 3;

const trailPlaceNames = <String, String>{
  'glasshouse': "Mira's Glasshouse",
  'workshop': "Bram's Workshop",
  'lodge': 'Trail Guild Lodge',
  'waystone': 'the Waystone',
  'homemap': 'your Home Map',
  'garden': 'your Garden',
  'cottage': 'your Cottage',
  'ruins': 'the Mossy Ruins',
  'gate': 'the Old Gate',
};

/// "the Mossy Ruins" with a capital for titles: "The Mossy Ruins".
String placeTitle(String place) {
  final n = trailPlaceNames[place] ?? place;
  return n.startsWith('the ') ? 'The ${n.substring(4)}' : n;
}

// ------------------------------------------------------------------- helpers ----
const _mask = 0xFFFFFFFF;

/// FNV-1a over the UTF-16 code units, 32-bit (the same hash as the web build).
int _hashStr(String str) {
  var h = 2166136261;
  for (final c in str.codeUnits) {
    h ^= c;
    h = (h * 16777619) & _mask;
  }
  return h;
}

/// mulberry32 seeded from a string: the same stream as the web build for the same seed, so an
/// attempt replays the same way on both clients.
class _Rng {
  _Rng(String seed) : _a = _hashStr(seed);
  int _a;
  double call() {
    _a = (_a + 0x6d2b79f5) & _mask;
    var t = ((_a ^ (_a >> 15)) * (1 | _a)) & _mask;
    t = ((t + (((t ^ (t >> 7)) * (61 | t)) & _mask)) ^ t) & _mask;
    return ((t ^ (t >> 14)) & _mask) / 4294967296;
  }
}

String _zone(GameState s) => zoneOf(s);

int discoveriesDone(GameState s) => s.trails.stat('discoveries');

bool _discoveryOpen(GameState s, Discovery d) {
  final n = d.needs;
  if (n == null) return true;
  if (n.flag != null && s.story.flags[n.flag!] != true) return false;
  if (n.quest != null && story.questPhase(s, n.quest!) != 'completed') return false;
  return true;
}

/// Today's three discoveries: deterministic per account and day, avoiding yesterday's picks and
/// (when the pool allows it) never two at the same place.
List<String> pickDiscoveries(GameState s, String key) {
  final pool = discoveryOrder.where((id) => _discoveryOpen(s, discoveryDefs[id]!)).toList();
  final prev = s.trails.days[addDays(key, -1)]?.ids ?? const <String>[];
  final r = _Rng('${s.player?.id ?? 'guest'}:$key:discover');
  final fresh = pool.where((id) => !prev.contains(id)).toList();
  final from = fresh.length >= discoveriesPerDay ? fresh : pool;
  final ids = <String>[];
  final bag = List<String>.of(from);
  while (ids.length < discoveriesPerDay && bag.isNotEmpty) {
    ids.add(bag.removeAt((r() * bag.length).floor()));
  }
  for (var i = 1; i < ids.length; i++) {
    final before = ids.sublist(0, i);
    if (before.any((x) => discoveryDefs[x]!.place == discoveryDefs[ids[i]]!.place)) {
      final alt = bag.where((x) => !before.any((y) => discoveryDefs[y]!.place == discoveryDefs[x]!.place)).firstOrNull;
      if (alt != null) {
        bag[bag.indexOf(alt)] = ids[i];
        ids[i] = alt;
      }
    }
  }
  return ids;
}

/// Make sure today's board exists on [s] (mutates). Returns the day record.
TrailDay _ensureDay(GameState s, int now) {
  final tr = s.trails;
  final key = dayKey(now, _zone(s));
  final day = tr.days.putIfAbsent(key, () => TrailDay(ids: pickDiscoveries(s, key)));
  // keep only a few days of history
  final cutoff = addDays(key, -3);
  tr.days.removeWhere((k, _) => k.compareTo(cutoff) < 0);
  return day;
}

class DiscoveryView {
  const DiscoveryView({
    required this.def,
    required this.placeName,
    required this.target,
    required this.walked,
    required this.pct,
    required this.phase,
    required this.acceptedAt,
    required this.foundAt,
    required this.rewardText,
  });
  final Discovery def;
  final String placeName;
  final int target; // steps asked for (nominal, or half the goal if that's less; at least 500)
  final int walked;
  final double pct;
  final String phase; // offered | walking | ready | found
  final int? acceptedAt;
  final int? foundAt;
  final String rewardText;

  String get id => def.id;
  String get title => def.title;
  String get place => def.place;
  String get icon => def.icon;
  String get clue => def.clue;
  String get found => def.found;
  DiscoveryReward get reward => def.reward;
}

DiscoveryView discoveryView(GameState s, String id, int now) {
  final d = discoveryDefs[id]!;
  final key = dayKey(now, _zone(s));
  final st = s.trails.days[key]?.states[id];
  final goal = s.player?.goal ?? 7000;
  final target = math.min(d.steps, math.max(500, (goal * 0.5).round()));
  var steps = 0;
  if (st != null) steps = story.freshDays(s, st.acceptedAt, _zone(s)).values.fold(0, (a, x) => a + x.steps);
  final walked = math.min(target, math.max(steps, st?.walked ?? 0));
  final phase = st?.foundAt != null
      ? 'found'
      : st == null
          ? 'offered'
          : walked >= target
              ? 'ready'
              : 'walking';
  return DiscoveryView(
    def: d,
    placeName: trailPlaceNames[d.place] ?? d.place,
    target: target,
    walked: walked,
    pct: math.min(1.0, walked / target),
    phase: phase,
    acceptedAt: st?.acceptedAt,
    foundAt: st?.foundAt,
    rewardText: [
      if (d.reward.coins > 0) '${d.reward.coins} EvoCoins',
      for (final e in d.reward.items.entries) '${e.value} × ${catalog[e.key]?.name ?? e.key}',
    ].join(' · '),
  );
}

class CompanionView {
  const CompanionView(this.creature, this.state);
  final Creature creature;
  final CompanionState state;
  String get id => creature.id;
  String get name => creature.name;
  int get since => state.since;
}

/// Summary for the Guild Board, badges and the Home chip.
class TrailsStatus {
  TrailsStatus({
    required this.discoveries,
    required this.rank,
    required this.companions,
    required this.restored,
    required this.encounter,
    required this.stats,
    required this.seen,
    required this.dayKey,
    required this.msToReset,
  });
  final List<DiscoveryView> discoveries;
  final GuildRankView rank;
  final List<CompanionView> companions;
  final Map<String, int> restored;
  final EncounterView? encounter;
  final Map<String, int> stats;
  final Map<String, bool> seen;
  final String dayKey;
  final int msToReset;

  List<DiscoveryView> get ready => discoveries.where((d) => d.phase == 'ready').toList();
  List<DiscoveryView> get walking => discoveries.where((d) => d.phase == 'walking').toList();
  List<DiscoveryView> get offered => discoveries.where((d) => d.phase == 'offered').toList();
  int get foundToday => discoveries.where((d) => d.phase == 'found').length;
  bool hasCompanion(String id) => companions.any((c) => c.id == id);
  bool isRestored(String id) => restored.containsKey(id);
  bool known(String id) => hasCompanion(id) || isRestored(id);
  int stat(String k) => stats[k] ?? 0;
}

TrailsStatus trailsStatus(GameState s, int now) {
  final tr = s.trails;
  final key = dayKey(now, _zone(s));
  final day = tr.days[key];
  final ids = day != null ? day.ids : (s.player != null ? pickDiscoveries(s, key) : const <String>[]);
  return TrailsStatus(
    discoveries: [for (final id in ids) discoveryView(s, id, now)],
    rank: guildRank(tr.guildXp),
    companions: [for (final e in tr.companions.entries) if (creatureDefs.containsKey(e.key)) CompanionView(creatureDefs[e.key]!, e.value)],
    restored: Map.of(tr.restored),
    encounter: tr.encounter == null ? null : encounterView(s, now),
    stats: Map.of(tr.stats),
    seen: Map.of(tr.seen),
    dayKey: key,
    msToReset: math.max(0, dayEnd(key, _zone(s)) - now),
  );
}

/// Which discoveries are ready to inspect at a place (for the glint).
List<DiscoveryView> cluesAt(GameState s, String place, int now) {
  if (s.player == null) return const [];
  return trailsStatus(s, now).discoveries.where((d) => d.place == place && d.phase == 'ready').toList();
}

// --------------------------------------------------------- discovery actions ----
ActionResult beginDiscovery(GameState state, String id, int now) {
  final d = discoveryDefs[id];
  if (d == null) return _fail(state, 'unknown_discovery');
  if (state.player == null) return _fail(state, 'no_player');
  final s = state.copy();
  final day = _ensureDay(s, now);
  if (!day.ids.contains(id)) return _fail(state, 'not_posted');
  if (day.states[id] != null) return _ok(state);
  day.states[id] = DiscoveryProgress(acceptedAt: now);
  return _ok(s, [GameEvent('discovery_begun', {'id': id, 'title': d.title})]);
}

/// Freeze walking progress (called from syncSteps so late samples never lose a finished walk).
/// Mutates [s] (a working copy) and returns events.
List<GameEvent> applyTrailProgress(GameState s, int now) {
  final events = <GameEvent>[];
  if (s.player == null) return events;
  final key = dayKey(now, _zone(s));
  final day = s.trails.days[key];
  if (day == null) return events;
  for (final id in day.ids) {
    final st = day.states[id];
    if (st == null || st.foundAt != null) continue;
    final before = discoveryView(s, id, now);
    final steps = story.freshDays(s, st.acceptedAt, _zone(s)).values.fold(0, (a, x) => a + x.steps);
    final wasReady = st.walked >= before.target;
    st.walked = math.max(st.walked, steps);
    if (!wasReady && st.walked >= before.target) {
      final d = discoveryDefs[id]!;
      events.add(GameEvent('discovery_ready', {'id': id, 'title': d.title, 'place': d.place}));
    }
  }
  return events;
}

ActionResult inspectDiscovery(GameState state, String id, int now) {
  final d = discoveryDefs[id];
  if (d == null) return _fail(state, 'unknown_discovery');
  final v = discoveryView(state, id, now);
  if (v.phase == 'found') return _ok(state, [GameEvent('discovery_already', {'id': id})]);
  if (v.phase != 'ready') return _fail(state, 'discovery_not_ready', {'need': v.target - v.walked});
  final s = state.copy();
  final tr = s.trails;
  final day = _ensureDay(s, now);
  final prev = day.states[id];
  day.states[id] = DiscoveryProgress(acceptedAt: prev?.acceptedAt ?? now, foundAt: now, walked: prev?.walked ?? 0);
  final txn = 'discovery:${dayKey(now, _zone(s))}:$id';
  if (d.reward.coins > 0) addTxn(s, WalletTxn(id: txn, amount: d.reward.coins, cause: 'discovery:$id', at: now));
  d.reward.items.forEach((iid, n) => grantItem(s, iid, n, 'discovery', now, txn));
  final rankBefore = guildRank(tr.guildXp).id;
  tr.guildXp += d.reward.guildXp;
  tr.stats['discoveries'] = tr.stat('discoveries') + 1;
  final events = <GameEvent>[
    GameEvent('discovery_found', {'id': id, 'title': d.title, 'reward': d.reward}),
  ];
  final rankAfter = guildRank(tr.guildXp);
  if (rankAfter.id != rankBefore) events.add(GameEvent('guild_rank', {'rank': rankAfter, 'name': rankAfter.name}));
  return _ok(s, events);
}

ActionResult markTrailSeen(GameState state, String key) {
  if (state.trails.seen[key] == true) return _ok(state);
  final s = state.copy();
  s.trails.seen[key] = true;
  return _ok(s);
}

// ---------------------------------------------------------------- encounters ----
// Each encounter quest's hand-in names a creature; the encounter is played out here and the story
// hand-in runs on success. Befriend: fill Calm to 100. Restore: bring Instability to 0.
class Recommended {
  const Recommended({required this.items, required this.stage, required this.affinity});
  final List<String> items;
  final int stage;
  final String affinity;
}

class EncounterDef {
  const EncounterDef({
    required this.quest,
    required this.creature,
    required this.goal,
    required this.meter,
    required this.place,
    required this.scene,
    required this.intro,
    required this.recommended,
    this.companionOn,
  });
  final String quest;
  final String creature;
  final String goal; // befriend | restore
  final int meter;
  final String place; // ruins | gate
  final String scene; // a trails scene id in the art manifest
  final String intro; // rare | hollow | boss
  final Recommended recommended;
  final String? companionOn; // befriending grants this companion
}

const encounterDefs = <String, EncounterDef>{
  'eq01': EncounterDef(
      quest: 'eq01',
      creature: 'petalune',
      goal: 'befriend',
      meter: 100,
      place: 'ruins',
      scene: 'mossy_ruins',
      intro: 'rare',
      recommended: Recommended(items: ['sunberry_tart'], stage: 1, affinity: 'nature'),
      companionOn: 'petalune'),
  'eq02': EncounterDef(
      quest: 'eq02',
      creature: 'hollow_sprout',
      goal: 'restore',
      meter: 100,
      place: 'ruins',
      scene: 'mossy_ruins_hollow',
      intro: 'hollow',
      recommended: Recommended(items: ['glowleaf', 'meadow_tea'], stage: 1, affinity: 'nature')),
  'eq03': EncounterDef(
      quest: 'eq03',
      creature: 'sentinel',
      goal: 'restore',
      meter: 200,
      place: 'gate',
      scene: 'sentinel_gate',
      intro: 'boss',
      recommended: Recommended(items: ['lantern_tonic'], stage: 2, affinity: 'celestial')),
};

class EncounterActionDef {
  const EncounterActionDef(this.id, this.name, this.kind, this.icon, this.energy, this.power, this.text);
  final String id;
  final String name;
  final String kind; // light | physical | restore | item | companion | retreat
  final String icon;
  final int energy; // cost (negative: restores)
  final int power;
  final String text;
}

const encounterActions = <String, EncounterActionDef>{
  'lumen_glow': EncounterActionDef('lumen_glow', 'Lumen Glow', 'light', 'star', 24, 16, 'A warm pulse of Lumen. Strong against the Hollow.'),
  'gentle_nudge': EncounterActionDef('gentle_nudge', 'Gentle Nudge', 'physical', 'play', 10, 9, 'A playful bump. Cheap, and it makes a wild Evochi curious.'),
  'soothe': EncounterActionDef('soothe', 'Soothe', 'restore', 'calm', -30, 5, 'Sit quietly together. Restores 30 Energy and adds a little Calm.'),
  'item': EncounterActionDef('item', 'Use Item', 'item', 'bag', 0, 0, 'Offer food or a tonic from your Bag.'),
  'petal_hush': EncounterActionDef('petal_hush', 'Petal Hush', 'companion', 'creature_petalune', 0, 12, 'Petalune hums. Once an encounter, no Energy.'),
  'retreat': EncounterActionDef('retreat', 'Retreat', 'retreat', 'back', 0, 0, 'Leave quietly. Items used are returned.'),
};

class ItemEffect {
  const ItemEffect(this.amount, this.liked);
  final int amount;
  final bool liked;
}

const _itemBase = <String, (int, int)>{
  // (befriend, restore)
  'sunberry_tart': (26, 6),
  'carrot_stew': (22, 6),
  'golden_bun': (18, 4),
  'moonshroom_pie': (30, 10),
  'berry_snack': (12, 2),
  'glowleaf': (10, 18),
  'healing_herb': (6, 16),
  'meadow_tea': (16, 16),
  'glowleaf_tonic': (14, 24),
  'moonlight_draught': (12, 30),
  'lantern_tonic': (20, 44),
};

/// What an item does in an encounter (Calm for befriending, Instability for restoring), or null.
ItemEffect? itemEffect(String itemId, String goal, String creature) {
  if (!catalog.containsKey(itemId)) return null;
  final base = _itemBase[itemId];
  if (base == null) return null;
  final liked = creatureDefs[creature]?.likes.contains(itemId) ?? false;
  final raw = goal == 'befriend' ? base.$1 : base.$2;
  return ItemEffect((raw * (liked ? 1.5 : 1)).round(), liked);
}

class EncounterItem {
  const EncounterItem(this.id, this.qty, this.effect);
  final String id;
  final int qty;
  final ItemEffect effect;
  String get name => catalog[id]?.name ?? id;
  int get amount => effect.amount;
  bool get liked => effect.liked;
}

/// Bag items that help in this encounter, with what they would do.
List<EncounterItem> encounterItems(GameState s, String goal, String creature) {
  final out = <EncounterItem>[];
  for (final id in s.inventory.keys) {
    if (ownedQty(s, id) <= 0) continue;
    final fx = itemEffect(id, goal, creature);
    if (fx != null) out.add(EncounterItem(id, ownedQty(s, id), fx));
  }
  return out;
}

int _petStage(GameState s) => s.pet?.stage ?? 1;

int maxEnergy(GameState s) => const {1: 100, 2: 120, 3: 140}[_petStage(s)] ?? 100;

/// Start the encounter for a quest whose hand-in is ready.
ActionResult startEncounter(GameState state, String qid, int now) {
  final e = encounterDefs[qid];
  if (e == null) return _fail(state, 'unknown_encounter');
  if (state.pet == null || state.player == null) return _fail(state, 'no_pet');
  final q = story.storyQuests[qid]!;
  final t = q.turnIns.firstWhere((x) => x.encounter != null);
  if (story.questPhase(state, qid) != t.from) return _fail(state, 'story_not_ready');
  final n = story.nextStep(state, qid);
  if (n.kind == 'gather') return _fail(state, 'story_missing_items', {'missing': n.needs.where((x) => !x.ok).toList()});
  final cur = state.trails.encounter;
  if (cur != null && cur.quest != qid) return _fail(state, 'encounter_busy');
  final s = state.copy();
  final tr = s.trails;
  tr.attempts[qid] = (tr.attempts[qid] ?? 0) + 1;
  final c = creatureDefs[e.creature]!;
  tr.encounter = EncounterState(
    quest: qid,
    creature: e.creature,
    goal: e.goal,
    meter: e.goal == 'befriend' ? 0 : e.meter,
    max: e.meter,
    energy: maxEnergy(s),
    energyMax: maxEnergy(s),
    seed: '${s.player!.id}:$qid:${tr.attempts[qid]}',
    mood: e.goal == 'befriend' ? 'wary' : 'surging',
    startedAt: now,
    log: [LogLine('wild', e.goal == 'befriend' ? '${c.name} watches you from a distance.' : '${c.name} shudders with Hollow energy.')],
  );
  tr.stats['encounters'] = tr.stat('encounters') + 1;
  return _ok(s, [GameEvent('encounter_started', {'quest': qid, 'creature': e.creature})]);
}

double _pct(EncounterState e) => e.goal == 'befriend' ? e.meter / e.max : 1 - e.meter / e.max;

/// One action as the encounter screen shows it: whether it can be used now and its effective power.
class ActionView {
  const ActionView(this.def, {required this.can, required this.power});
  final EncounterActionDef def;
  final bool can;
  final int power;
  String get id => def.id;
  String get name => def.name;
  String get kind => def.kind;
  String get icon => def.icon;
  int get energy => def.energy;
  String get text => def.text;
}

/// Everything the encounter screen needs.
class EncounterView {
  EncounterView({
    required this.e,
    required this.creature,
    required this.def,
    required this.pct,
    required this.stateKey,
    required this.actions,
    required this.items,
  });
  final EncounterState e;
  final Creature creature;
  final EncounterDef def;
  final double pct;
  final String stateKey; // the creature sprite state to draw
  final List<ActionView> actions;
  final List<EncounterItem> items;

  String get quest => e.quest;
  String get goal => e.goal;
  int get meter => e.meter;
  int get max => e.max;
  int get energy => e.energy;
  int get energyMax => e.energyMax;
  int get turn => e.turn;
  String get seed => e.seed;
  String get mood => e.mood;
  bool get companionUsed => e.companionUsed;
  Map<String, int> get used => e.used;
  String? get done => e.done;
  List<LogLine> get log => e.log;
  String get scene => def.scene;
  String get intro => def.intro;
  Recommended get recommended => def.recommended;
  int get pctLabel => (pct * 100).round();
  String get meterLabel => goal == 'befriend' ? 'Calm' : 'Instability';
  int get meterShown => meter;
  bool get boss => creature.boss;
  bool get phase2 => creature.boss && pct >= 0.5;
  bool get success => done == 'success';
}

EncounterView? encounterView(GameState s, int now) {
  final e = s.trails.encounter;
  if (e == null) return null;
  final c = creatureDefs[e.creature]!;
  final def = encounterDefs[e.quest]!;
  final p = _pct(e);
  final stateKey = e.done == 'success' ? c.states.done : (p >= 0.5 ? c.states.mid : c.states.start);
  final companion = s.trails.companions.containsKey('petalune') && e.creature != 'petalune' ? encounterActions['petal_hush'] : null;
  final actions = <ActionView>[
    for (final id in const ['lumen_glow', 'gentle_nudge', 'soothe', 'item'])
      ActionView(
        encounterActions[id]!,
        can: e.done == null && (encounterActions[id]!.energy <= 0 || e.energy >= encounterActions[id]!.energy),
        power: encounterActions[id]!.kind == 'light' && c.kind == 'hollow' ? (encounterActions[id]!.power * 1.3).round() : encounterActions[id]!.power,
      ),
    if (companion != null) ActionView(companion, can: e.done == null && !e.companionUsed, power: companion.power),
  ];
  return EncounterView(e: e, creature: c, def: def, pct: p, stateKey: stateKey, actions: actions, items: encounterItems(s, e.goal, e.creature));
}

/// More Calm, or less Instability; never past the ends.
void _gain(EncounterState e, int amount) {
  if (e.goal == 'befriend') {
    e.meter = math.max(0, math.min(e.max, e.meter + amount));
  } else {
    e.meter = math.max(0, math.min(e.max, e.meter - amount));
  }
}

class _WildReply {
  const _WildReply(this.text, {this.delta = 0, this.energy = 0, required this.mood});
  final String text;
  final int delta;
  final int energy;
  final String mood;
}

/// The creature's reply, seeded so an attempt always plays the same way.
_WildReply _wildTurn(EncounterState e, _Rng r, Creature c, String lastKind) {
  final roll = r();
  if (e.goal == 'befriend') {
    final p = _pct(e);
    if (lastKind == 'item' && roll < 0.8) return _WildReply('${c.name} nibbles, and edges a little closer.', delta: 4, mood: 'curious');
    if (p < 0.35 && roll < 0.35) return _WildReply('${c.name} skitters back behind the stones.', delta: -6, mood: 'wary');
    if (p < 0.7 && roll < 0.2) return _WildReply('${c.name} hides, peeking out at you.', delta: -3, mood: 'wary');
    if (roll < 0.5) return _WildReply('${c.name} tilts its head and watches ${e.curious ? 'with bright eyes' : 'carefully'}.', mood: 'curious');
    return _WildReply('${c.name} sniffs the air and settles.', delta: 2, mood: p > 0.6 ? 'calm' : 'curious');
  }
  final p = _pct(e);
  final boss = c.boss;
  if (boss && p >= 0.5 && roll < 0.45) return const _WildReply('The Sentinel wakes a little more. Hollow light lashes out!', energy: -18, mood: 'waking');
  if (roll < (boss ? 0.4 : 0.35)) return _WildReply('Hollow energy surges through ${c.name}.', delta: -(boss ? 9 : 7), mood: 'surging');
  if (roll < 0.6) return _WildReply('${c.name} flickers. The vines loosen for a moment.', mood: 'flickering');
  if (roll < 0.75) return const _WildReply('A tendril of Hollow whips past you.', energy: -12, mood: 'surging');
  return _WildReply('${c.name} goes still, listening.', delta: 3, mood: 'settling');
}

/// One turn: your action (plus an item id for 'item'), then the creature's reply.
ActionResult encounterAct(GameState state, String actionId, String? itemId, int now) {
  final e0 = state.trails.encounter;
  if (e0 == null) return _fail(state, 'no_encounter');
  if (e0.done != null) return _fail(state, 'encounter_over');
  final a = encounterActions[actionId];
  if (a == null) return _fail(state, 'unknown_action');
  final s = state.copy();
  final tr = s.trails;
  final e = tr.encounter!;
  final c = creatureDefs[e.creature]!;
  final events = <GameEvent>[];
  void log(String who, String text) => e.log.add(LogLine(who, text));
  if (actionId == 'retreat') {
    // items used come back: nothing is ever wasted on a retreat
    e.used.forEach((id, n) => grantItem(s, id, n, 'retreat', now, 'retreat:${e.seed}:$id'));
    tr.encounter = null;
    tr.stats['retreats'] = tr.stat('retreats') + 1;
    return _ok(s, [GameEvent('encounter_retreat', {'quest': e.quest, 'creature': e.creature})]);
  }
  var amount = 0;
  final kind = a.kind;
  if (actionId == 'item') {
    final fx = itemId == null ? null : itemEffect(itemId, e.goal, e.creature);
    if (fx == null || ownedQty(s, itemId!) < 1) return _fail(state, 'not_owned');
    s.inventory[itemId]!.quantity -= 1;
    e.used[itemId] = (e.used[itemId] ?? 0) + 1;
    amount = fx.amount;
    log('you', 'You offer ${catalog[itemId]!.name}.${fx.liked ? ' ${c.name} loves it!' : ''}');
  } else if (actionId == 'petal_hush') {
    if (!tr.companions.containsKey('petalune') || e.creature == 'petalune') return _fail(state, 'no_companion');
    if (e.companionUsed) return _fail(state, 'companion_used');
    e.companionUsed = true;
    amount = a.power;
    log('you', 'Petalune hums a soft, green note.');
  } else {
    if (a.energy > 0 && e.energy < a.energy) return _fail(state, 'no_energy', {'need': a.energy});
    e.energy = math.max(0, math.min(e.energyMax, e.energy - a.energy));
    amount = a.power;
    if (a.kind == 'light' && c.kind == 'hollow') amount = (amount * 1.3).round();
    if (a.kind == 'light' && c.boss && _pct(e) >= 0.5) amount = (amount * 1.25).round();
    if (a.kind == 'physical' && e.goal == 'befriend') {
      if (e.curious) amount += 4;
      e.curious = true;
    }
    if (a.kind == 'restore') e.curious = false;
    final petName = s.pet?.name ?? 'Your Evochi';
    log('you', switch (a.kind) {
      'light' => '$petName glows with Lumen.',
      'physical' => '$petName gives ${c.name} a gentle nudge.',
      _ => '$petName sits down quietly. Energy returns.',
    });
  }
  _gain(e, amount);
  e.turn++;
  if (_pct(e) >= 1) {
    // the winning move: no reply, but the screen still gets the turn (marked final) before the win
    events.add(GameEvent('encounter_turn', {'turn': e.turn, 'you': amount, 'wild': 0, 'mood': null, 'drain': 0, 'kind': kind, 'item': itemId, 'final': true}));
    return _finishEncounter(s, e, events, now);
  }
  final r = _Rng('${e.seed}:${e.turn}');
  final w = _wildTurn(e, r, c, kind);
  if (w.delta != 0) _gain(e, w.delta);
  if (w.energy != 0) e.energy = math.max(0, e.energy + w.energy);
  e.mood = w.mood;
  log('wild', w.text);
  if (_pct(e) >= 1) return _finishEncounter(s, e, events, now);
  // what the screen choreographs: your gain, the reply's delta and mood, and the Energy it drained
  // (0 when none), plus the kind of move and the item offered
  events.add(GameEvent('encounter_turn', {'turn': e.turn, 'you': amount, 'wild': w.delta, 'mood': w.mood, 'drain': w.energy, 'kind': kind, 'item': itemId}));
  return _ok(s, events);
}

ActionResult _finishEncounter(GameState s, EncounterState e, List<GameEvent> events, int now) {
  final tr = s.trails;
  final c = creatureDefs[e.creature]!;
  e.done = 'success';
  final petName = s.pet?.name ?? 'your Evochi';
  e.log.add(LogLine('wild', e.goal == 'befriend' ? '${c.name} nuzzles $petName. It trusts you.' : 'The Hollow dissolves into motes of light. ${c.name} remembers.'));
  if (e.goal == 'befriend') {
    tr.companions.putIfAbsent(e.creature, () => CompanionState(since: now));
    tr.stats['befriended'] = tr.stat('befriended') + 1;
  } else {
    tr.restored[e.creature] = now;
    tr.stats['restored'] = tr.stat('restored') + 1;
  }
  events.add(GameEvent('encounter_won', {'quest': e.quest, 'creature': e.creature, 'goal': e.goal}));
  return _ok(s, events);
}

/// Close a finished encounter (after the result screen): the quest's hand-in runs and pays out.
ActionResult completeEncounter(GameState state, int now) {
  final e = state.trails.encounter;
  if (e == null) return _ok(state);
  if (e.done != 'success') return _fail(state, 'encounter_not_won');
  final q = story.storyQuests[e.quest]!;
  final t = q.turnIns.firstWhere((x) => x.encounter != null);
  var s = state.copy();
  s.trails.encounter = null;
  final r = story.storyHandIn(s, e.quest, t.id, now);
  if (!r.ok) return _fail(state, r.error!, r.info);
  s = r.state;
  return _ok(s, [
    ...r.events,
    if (e.goal == 'befriend') GameEvent('companion_joined', {'creature': e.creature}),
  ]);
}

/// Drop an unfinished encounter without a result (e.g. the app was closed mid-way).
ActionResult abandonEncounter(GameState state) {
  if (state.trails.encounter == null) return _ok(state);
  final s = state.copy();
  s.trails.encounter = null;
  return _ok(s);
}

CompanionView? companionView(GameState s, String id) {
  final c = s.trails.companions[id];
  final def = creatureDefs[id];
  if (c == null || def == null) return null;
  return CompanionView(def, c);
}

// ------------------------------------------------------------------ playtest ----
/// Playtest: begin, walk and inspect up to [max] of today's discoveries (only those not yet found).
/// The walk is a synthetic sample that starts when the discovery began, so it counts in full.
/// Returns the new state and how many were found.
(GameState, int) playtestFinishDiscoveries(GameState state, int now, int max) {
  var s = state;
  var n = 0;
  for (var i = 0; i < max; i++) {
    final t = trailsStatus(s, now);
    final d = t.discoveries.where((x) => x.phase != 'found' && (t.stat('discoveries') + n < 2 || i < max)).firstOrNull;
    if (d == null) break;
    if (d.phase == 'offered') s = beginDiscovery(s, d.id, now).state;
    final v = discoveryView(s, d.id, now);
    if (v.phase != 'ready') {
      // a full target's worth after the discovery began: overlapping buckets take the larger
      // source, so this alone always finishes the walk
      final end = now + 60000;
      final start = math.max(v.acceptedAt ?? now, end - 30 * 60000);
      final sample = StepSample(id: 'disc_${d.id}_$now', source: 'playtest', start: start, end: end, count: v.target + 50);
      s = syncSteps(s, [sample], end, source: 'playtest').state;
    }
    final r = inspectDiscovery(s, d.id, now + 60000);
    if (!r.ok) break;
    s = r.state;
    n++;
  }
  return (s, n);
}

/// Playtest: Chapter 1's first quest done, account level 3 and two discoveries found, so Pip offers
/// the Guild's first trail job. False (state unchanged) when the Trails are already open.
ActionResult playtestTrailsReady(GameState state, int now) {
  var s = story.playtestHomeTalesReady(state, now).state;
  if (story.accountLevel(s) < 3) {
    s = s.copy();
    s.story.peakLevel = math.max(s.story.peakLevel, 3);
  }
  final (after, n) = playtestFinishDiscoveries(s, now, 2);
  final changed = !identical(after, state) || n > 0;
  return changed ? _ok(after, [GameEvent('playtest_trails', {'found': n})]) : _ok(state);
}
