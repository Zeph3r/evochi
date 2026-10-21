// Home Tales rules: the Garden, the Cottage Kitchen and Apothecary, and the three Cozy Skills.
// Mirrors web/src/game/home.js.
//
// Everything here belongs to the player account (like the story), not to one Evochi: beds, skill XP
// and recipes survive memorials and new pets. Rules:
//  - crops grow on real time; walking adds a bonus (steps taken after planting, from the same
//    de-duplicated samples as the story), and an optional watering adds a little more
//  - harvests, brews and meals go into the ordinary inventory and reuse the item catalog
//  - crafting never wastes ingredients: the minigame only ever adds a quality bonus
//  - the Kitchen opens with "A Place to Call Home", the Apothecary with "Mira's Mortar" (story flags)
//
// Every action is `(state, ..., now) -> ActionResult` and never mutates its input.

import 'dart:math' as math;

import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../core/models/home_state.dart';
import '../economy/economy.dart' as econ;
import '../engine.dart' as g;
import '../story/story.dart' as story;

g.ActionResult _ok(GameState s, [List<g.GameEvent> events = const []]) => g.ActionResult(s, events: events);
g.ActionResult _fail(GameState s, String error, [Map<String, Object?> info = const {}]) => g.ActionResult(s, error: error, info: info);

// ------------------------------------------------------------------- skills ----
class SkillDef {
  const SkillDef(this.id, this.name, this.icon, this.color, this.verb);
  final String id;
  final String name;
  final String icon;
  final int color; // ARGB, e.g. Color(def.color) in widgets
  final String verb;
}

const skillDefs = <String, SkillDef>{
  'farming': SkillDef('farming', 'Farming', 'skill_farming', 0xFF5FA046, 'harvest'),
  'cooking': SkillDef('cooking', 'Cooking', 'skill_cooking', 0xFFE8792E, 'cook'),
  'alchemy': SkillDef('alchemy', 'Alchemy', 'skill_alchemy', 0xFF9975C9, 'brew'),
};
const skillOrder = ['farming', 'cooking', 'alchemy'];

/// XP from level L to L+1 = base + step * (L - 1), up to [skillCurveMax].
const skillCurveBase = 40;
const skillCurveStep = 20;
const skillCurveMax = 20;

class SkillLevel {
  const SkillLevel(this.level, this.into, this.need, this.maxed);
  final int level;
  final int into; // XP into the current level
  final int need; // XP the current level needs (0 when maxed)
  final bool maxed;
}

SkillLevel skillLevel(int xp) {
  var level = 1;
  var left = math.max(0, xp);
  for (;;) {
    if (level >= skillCurveMax) return SkillLevel(level, 0, 0, true);
    final need = skillCurveBase + skillCurveStep * (level - 1);
    if (left < need) return SkillLevel(level, left, need, false);
    left -= need;
    level++;
  }
}

// -------------------------------------------------------------------- crops ----
class CropDef {
  const CropDef(this.id, this.name, this.seed, this.yieldItems, this.growMin, this.xp, this.level);
  final String id;
  final String name;
  final String seed;
  final Map<String, int> yieldItems;
  final int growMin; // minutes of real time with no walking
  final int xp; // Farming XP per harvest
  final int level; // Farming level that unlocks it
}

const cropDefs = <String, CropDef>{
  'sunberry': CropDef('sunberry', 'Sunberry', 'seed_sunberry', {'sunberry': 3}, 20, 12, 1),
  'meadow_carrot': CropDef('meadow_carrot', 'Meadow Carrot', 'seed_meadow_carrot', {'meadow_carrot': 2}, 45, 14, 1),
  'golden_wheat': CropDef('golden_wheat', 'Golden Wheat', 'seed_golden_wheat', {'golden_wheat': 3}, 90, 18, 2),
  'glowleaf': CropDef('glowleaf', 'Glowleaf', 'seed_glowleaf', {'glowleaf': 2}, 180, 24, 3),
  'moonshroom': CropDef('moonshroom', 'Moonshroom', 'seed_moonshroom', {'moonshroom': 2}, 360, 36, 5),
};
const cropOrder = ['sunberry', 'meadow_carrot', 'golden_wheat', 'glowleaf', 'moonshroom'];

class PlotDef {
  const PlotDef(this.id, this.level);
  final String id;
  final int level; // Farming level that opens the bed
}

const plotDefs = [PlotDef('p1', 1), PlotDef('p2', 1), PlotDef('p3', 1), PlotDef('p4', 4)];

PlotDef plotDef(String id) => plotDefs.firstWhere((p) => p.id == id);

/// Steps after planting that add one whole growing time...
const growStepsForFull = 10000;

/// ...capped at 60% of it.
const growMaxWalkShare = 0.6;

/// Optional watering, once per planting.
const growWater = 0.15;

/// The Apothecary's Sprout Tonic, once per planting.
const growSproutTonic = 0.5;

/// First visit to the Home Map: a few seeds from Mira, once per account.
const starterSeedGift = {'seed_sunberry': 3, 'seed_meadow_carrot': 2};

// ------------------------------------------------------------------ recipes ----
class StationDef {
  const StationDef(this.id, this.name, this.skill, this.flag, this.verb, this.quest);
  final String id;
  final String name;
  final String skill;
  final String flag; // the story flag that opens it
  final String verb; // Cook | Brew
  final String quest; // the story quest that opens it
}

const stationDefs = <String, StationDef>{
  'kitchen': StationDef('kitchen', 'Kitchen', 'cooking', 'cottage_restored', 'Cook', 'hq01'),
  'apothecary': StationDef('apothecary', 'Apothecary', 'alchemy', 'apothecary_unlocked', 'Brew', 'hq02'),
};

class RecipeDef {
  const RecipeDef(this.id, this.station, this.makes, this.needs, this.level, this.xp, {this.flag});
  final String id;
  final String station;
  final String makes;
  final Map<String, int> needs;
  final int level;
  final int xp;
  final String? flag; // a story flag the recipe also needs (the Lantern Tonic: Tangled Lumen)
}

const recipeDefs = <String, RecipeDef>{
  'sunberry_tart': RecipeDef('sunberry_tart', 'kitchen', 'sunberry_tart', {'sunberry': 3, 'golden_wheat': 1}, 1, 20),
  'carrot_stew': RecipeDef('carrot_stew', 'kitchen', 'carrot_stew', {'meadow_carrot': 2, 'sunberry': 1}, 1, 15),
  'golden_bun': RecipeDef('golden_bun', 'kitchen', 'golden_bun', {'golden_wheat': 2}, 2, 15),
  'moonshroom_pie': RecipeDef('moonshroom_pie', 'kitchen', 'moonshroom_pie', {'moonshroom': 2, 'golden_wheat': 2}, 4, 40),
  'glowleaf_tonic': RecipeDef('glowleaf_tonic', 'apothecary', 'glowleaf_tonic', {'glowleaf': 2, 'sunberry': 1}, 1, 20),
  'meadow_tea': RecipeDef('meadow_tea', 'apothecary', 'meadow_tea', {'glowleaf': 1, 'meadow_carrot': 1}, 1, 15),
  'sprout_tonic': RecipeDef('sprout_tonic', 'apothecary', 'sprout_tonic', {'glowleaf': 1, 'golden_wheat': 1}, 2, 20),
  'moonlight_draught': RecipeDef('moonlight_draught', 'apothecary', 'moonlight_draught', {'moonshroom': 2, 'glowleaf': 1}, 4, 40),
  'lantern_tonic': RecipeDef('lantern_tonic', 'apothecary', 'lantern_tonic', {'lumen_shard': 1, 'glowleaf': 1, 'sunberry': 2}, 3, 30, flag: 'sprout_restored'),
};
const recipeOrder = ['sunberry_tart', 'carrot_stew', 'golden_bun', 'moonshroom_pie', 'glowleaf_tonic', 'meadow_tea', 'sprout_tonic', 'moonlight_draught', 'lantern_tonic'];

/// The story quest that teaches a recipe: its room's quest, or Tangled Lumen for the Lantern Tonic.
String recipeQuest(RecipeDef r) => r.flag == 'sprout_restored' ? 'eq02' : stationDefs[r.station]!.quest;

/// The minigame result: 'perfect' doubles the batch and gives +50% skill XP; anything else is a
/// normal batch.
class CraftQuality {
  const CraftQuality(this.batch, this.xp, this.label);
  final int batch;
  final double xp;
  final String label;
}

const craftQualities = <String, CraftQuality>{
  'perfect': CraftQuality(2, 1.5, 'Perfect!'),
  'good': CraftQuality(1, 1, 'Good'),
};

// --------------------------------------------------------------- milestones ----
/// What a skill level opens: a crop, a bed, a recipe or a story quest (the Skills chart reads this).
class SkillMilestone {
  const SkillMilestone({required this.skill, required this.level, required this.kind, required this.id, required this.label, this.quest, this.story = false});
  final String skill;
  final int level;
  final String kind; // crop | plot | recipe | quest
  final String id;
  final String label;
  final String? quest; // recipes: the quest that opens their room
  final bool story;
}

List<SkillMilestone> skillMilestones(String skill) {
  final out = <SkillMilestone>[];
  void add(int level, String kind, String id, String label, {String? quest, bool story = false}) =>
      out.add(SkillMilestone(skill: skill, level: level, kind: kind, id: id, label: label, quest: quest, story: story));
  if (skill == 'farming') {
    for (final c in cropOrder) {
      add(cropDefs[c]!.level, 'crop', c, cropDefs[c]!.name);
    }
    for (final p in plotDefs) {
      if (p.level > 1) add(p.level, 'plot', p.id, 'A fourth garden bed');
    }
    add(3, 'quest', 'hq02', "Mira's Mortar needs Glowleaf", story: true);
  } else {
    final station = skill == 'cooking' ? 'kitchen' : 'apothecary';
    for (final r in recipeOrder) {
      final def = recipeDefs[r]!;
      if (def.station == station) add(def.level, 'recipe', r, item(def.makes).name, quest: recipeQuest(def));
    }
    if (skill == 'cooking') add(2, 'quest', 'hq02', "Mira's Mortar (opens the Apothecary)", story: true);
  }
  // stable: by level, then kind, then the order they were added
  final idx = {for (var i = 0; i < out.length; i++) out[i]: i};
  out.sort((a, b) {
    if (a.level != b.level) return a.level - b.level;
    final k = a.kind.compareTo(b.kind);
    return k != 0 ? k : idx[a]! - idx[b]!;
  });
  return out;
}

// ------------------------------------------------------------------ helpers ----
int skillXp(GameState s, String id) => s.home.skills[id] ?? 0;

/// A skill with its level progress (for strips, tabs and the chart).
class SkillView {
  SkillView(this.def, this.xp, this.lv);
  final SkillDef def;
  final int xp;
  final SkillLevel lv;
  String get id => def.id;
  String get name => def.name;
  String get icon => def.icon;
  int get color => def.color;
  int get level => lv.level;
  int get into => lv.into;
  int get need => lv.need;
  bool get maxed => lv.maxed;
  double get pct => maxed || need == 0 ? 1.0 : into / need;
}

SkillView skillView(GameState s, String id) => SkillView(skillDefs[id]!, skillXp(s, id), skillLevel(skillXp(s, id)));

bool storyFlag(GameState s, String f) => s.story.flags[f] == true;

bool stationOpen(GameState s, String station) => storyFlag(s, stationDefs[station]!.flag);

bool plotUnlocked(GameState s, String plotId) {
  final p = plotDefs.where((x) => x.id == plotId).firstOrNull;
  return p != null && skillLevel(skillXp(s, 'farming')).level >= p.level;
}

bool cropUnlocked(GameState s, String cropId) => skillLevel(skillXp(s, 'farming')).level >= cropDefs[cropId]!.level;

/// Steps walked since [since] (same counting as story walks: fresh, de-duplicated samples).
int stepsSince(GameState s, int since) {
  if (s.player == null) return 0;
  return story.freshDays(s, since, g.zoneOf(s)).values.fold(0, (a, d) => a + d.steps);
}

class PlotGrowth {
  const PlotGrowth({required this.progress, required this.time, required this.walk, required this.steps, required this.growMs});
  final double progress; // 0..1
  final double time; // share from real time (uncapped)
  final double walk; // share from walking (capped at growMaxWalkShare)
  final int steps; // steps walked since planting
  final int growMs;
}

/// How far a planted bed has grown: time + walking + watering + tonic, 0..1.
PlotGrowth plotGrowth(GameState s, PlotState plot, int now) {
  final c = cropDefs[plot.crop]!;
  final growMs = c.growMin * 60000;
  final time = math.max(0, now - plot.plantedAt) / growMs;
  final steps = stepsSince(s, plot.plantedAt);
  final walk = math.min(growMaxWalkShare, steps / growStepsForFull);
  final p = time + walk + (plot.watered ? growWater : 0.0) + (plot.tonic ? growSproutTonic : 0.0) + plot.boost;
  return PlotGrowth(progress: math.min(1.0, p), time: time, walk: walk, steps: steps, growMs: growMs);
}

class PlotView {
  const PlotView({
    required this.id,
    required this.unlocked,
    required this.need,
    required this.empty,
    this.crop,
    this.plantedAt = 0,
    this.watered = false,
    this.tonic = false,
    this.progress = 0,
    this.ripe = false,
    this.stage,
    this.msLeft = 0,
    this.stepsToRipe,
    this.walkedSteps = 0,
  });
  final String id;
  final bool unlocked;
  final int need; // Farming level that opens the bed
  final bool empty;
  final String? crop;
  final int plantedAt;
  final bool watered;
  final bool tonic;
  final double progress;
  final bool ripe;
  final String? stage; // sprout | growing | ripe
  final int msLeft; // time left if nobody walks
  final int? stepsToRipe; // steps that would finish it now (null when walking alone can't)
  final int walkedSteps;
}

PlotView plotView(GameState s, String plotId, int now) {
  final unlocked = plotUnlocked(s, plotId);
  final plot = s.home.plots[plotId];
  final need = plotDef(plotId).level;
  if (plot == null) return PlotView(id: plotId, unlocked: unlocked, need: need, empty: true);
  final gr = plotGrowth(s, plot, now);
  final ripe = gr.progress >= 1;
  final stage = ripe ? 'ripe' : (gr.progress < 0.34 ? 'sprout' : 'growing');
  final left = ripe ? 0 : math.max(0, ((1 - gr.progress) * gr.growMs).round());
  final walkRoom = math.max(0.0, growMaxWalkShare - gr.walk);
  final stepsToRipe = ripe || (1 - gr.progress) > walkRoom ? null : ((1 - gr.progress) * growStepsForFull).ceil();
  return PlotView(
    id: plotId,
    unlocked: unlocked,
    need: need,
    empty: false,
    crop: plot.crop,
    plantedAt: plot.plantedAt,
    watered: plot.watered,
    tonic: plot.tonic,
    progress: gr.progress,
    ripe: ripe,
    stage: stage,
    msLeft: left,
    stepsToRipe: stepsToRipe,
    walkedSteps: gr.steps,
  );
}

/// Summary for the Home Map, badges and the Skills chart.
class HomeStatus {
  HomeStatus({
    required this.plots,
    required this.skills,
    required this.kitchen,
    required this.apothecary,
    required this.starterSeeds,
    required this.counts,
  });
  final List<PlotView> plots;
  final Map<String, SkillView> skills;
  final bool kitchen;
  final bool apothecary;
  final bool starterSeeds;
  final Map<String, int> counts;

  int get ripe => plots.where((p) => p.ripe).length;
  int get growing => plots.where((p) => !p.empty && !p.ripe).length;
  int get emptyOpen => plots.where((p) => p.empty && p.unlocked).length;
  int count(String k) => counts[k] ?? 0;
}

HomeStatus homeStatus(GameState s, int now) => HomeStatus(
      plots: [for (final p in plotDefs) plotView(s, p.id, now)],
      skills: {for (final k in skillOrder) k: skillView(s, k)},
      kitchen: stationOpen(s, 'kitchen'),
      apothecary: stationOpen(s, 'apothecary'),
      starterSeeds: s.home.starterSeeds,
      counts: Map.of(s.home.counts),
    );

bool hasIngredients(GameState s, Map<String, int> needs, [int times = 1]) => needs.entries.every((e) => g.ownedQty(s, e.key) >= e.value * times);

class NeedHave {
  const NeedHave(this.need, this.have);
  final int need;
  final int have;
  bool get ok => have >= need;
}

class RecipeView {
  RecipeView({required this.def, required this.open, required this.known, required this.have, required this.ready, this.needsStory = false});
  final RecipeDef def;
  final bool open; // its room is open
  final bool known; // the skill level is high enough (and its story flag, if any, is set)
  final Map<String, NeedHave> have;
  final bool ready; // open, known and every ingredient in the Bag
  final bool needsStory; // the recipe waits on a story flag (the Lantern Tonic until the sprout is restored)
  String get id => def.id;
  String get station => def.station;
  String get makes => def.makes;
  int get level => def.level;
  int get xp => def.xp;
  String get name => item(def.makes).name;
  String get skill => stationDefs[def.station]!.skill;
}

RecipeView recipeView(GameState s, String rid) {
  final r = recipeDefs[rid]!;
  final st = stationDefs[r.station]!;
  final lv = skillLevel(skillXp(s, st.skill)).level;
  final open = stationOpen(s, r.station);
  final flagOk = r.flag == null || storyFlag(s, r.flag!);
  final known = lv >= r.level && flagOk;
  return RecipeView(
    def: r,
    open: open,
    known: known,
    have: {for (final e in r.needs.entries) e.key: NeedHave(e.value, g.ownedQty(s, e.key))},
    ready: open && known && hasIngredients(s, r.needs),
    needsStory: !flagOk,
  );
}

void _addSkillXp(GameState s, String skill, double amount, List<g.GameEvent> events) {
  final before = skillLevel(skillXp(s, skill));
  final add = amount.round();
  s.home.skills[skill] = skillXp(s, skill) + add;
  final after = skillLevel(skillXp(s, skill));
  events.add(g.GameEvent('skill_xp', {'skill': skill, 'amount': add}));
  if (after.level > before.level) {
    final unlocks = skillMilestones(skill).where((m) => m.level > before.level && m.level <= after.level).toList();
    events.add(g.GameEvent('skill_up', {'skill': skill, 'level': after.level, 'unlocks': unlocks}));
  }
}

void _take(GameState s, String id, int n) => s.inventory[id]!.quantity -= n;

// ------------------------------------------------------------------ actions ----
/// First visit to the Home Map: a few starter seeds, once per account.
g.ActionResult claimStarterSeeds(GameState state, int now) {
  if (state.home.starterSeeds) return _ok(state);
  final s = state.copy();
  starterSeedGift.forEach((id, n) => g.grantItem(s, id, n, 'home:starter', now, 'home:starter'));
  s.home.starterSeeds = true;
  return _ok(s, [g.GameEvent('home_gift', {'items': Map.of(starterSeedGift)})]);
}

g.ActionResult plant(GameState state, String plotId, String cropId, int now) {
  final c = cropDefs[cropId];
  if (c == null) return _fail(state, 'unknown_crop');
  if (!plotDefs.any((p) => p.id == plotId)) return _fail(state, 'unknown_plot');
  if (!plotUnlocked(state, plotId)) return _fail(state, 'plot_locked', {'need': plotDef(plotId).level});
  if (state.home.plots[plotId] != null) return _fail(state, 'plot_busy');
  if (!cropUnlocked(state, cropId)) return _fail(state, 'crop_locked', {'need': c.level});
  if (g.ownedQty(state, c.seed) < 1) return _fail(state, 'no_seed', {'seed': c.seed});
  final s = state.copy();
  _take(s, c.seed, 1);
  // Evochi Plus: beds water themselves when planted
  s.home.plots[plotId] = PlotState(crop: cropId, plantedAt: now, watered: econ.plusActive(state, now));
  return _ok(s, [g.GameEvent('planted', {'plot': plotId, 'crop': cropId})]);
}

g.ActionResult water(GameState state, String plotId, int now) {
  final p = state.home.plots[plotId];
  if (p == null) return _fail(state, 'plot_empty');
  if (p.watered) return _ok(state, [g.GameEvent('already_watered', {'plot': plotId})]);
  final s = state.copy();
  s.home.plots[plotId]!.watered = true;
  return _ok(s, [g.GameEvent('watered', {'plot': plotId})]);
}

g.ActionResult useSproutTonic(GameState state, String plotId, int now) {
  final p = state.home.plots[plotId];
  if (p == null) return _fail(state, 'plot_empty');
  if (p.tonic) return _fail(state, 'tonic_used');
  if (g.ownedQty(state, 'sprout_tonic') < 1) return _fail(state, 'not_owned');
  if (plotGrowth(state, p, now).progress >= 1) return _fail(state, 'already_ripe');
  final s = state.copy();
  _take(s, 'sprout_tonic', 1);
  s.home.plots[plotId]!.tonic = true;
  return _ok(s, [g.GameEvent('tonic_used', {'plot': plotId})]);
}

g.ActionResult harvest(GameState state, String plotId, int now) {
  final p = state.home.plots[plotId];
  if (p == null) return _fail(state, 'plot_empty');
  if (plotGrowth(state, p, now).progress < 1) return _fail(state, 'not_ripe');
  final c = cropDefs[p.crop]!;
  final s = state.copy();
  final txn = 'harvest:$plotId:${p.plantedAt}';
  c.yieldItems.forEach((id, n) => g.grantItem(s, id, n, 'harvest', now, txn));
  s.home.plots[plotId] = null;
  s.home.counts['harvests'] = (s.home.counts['harvests'] ?? 0) + 1;
  final events = <g.GameEvent>[
    g.GameEvent('harvested', {'plot': plotId, 'crop': p.crop, 'items': Map.of(c.yieldItems)}),
  ];
  _addSkillXp(s, 'farming', c.xp.toDouble(), events);
  return _ok(s, events);
}

/// Cook or brew one recipe. [quality] comes from the (skippable) minigame and only ever adds.
g.ActionResult craft(GameState state, String recipeId, String quality, int now) {
  final r = recipeDefs[recipeId];
  if (r == null) return _fail(state, 'unknown_recipe');
  final v = recipeView(state, recipeId);
  if (!v.open) return _fail(state, 'station_locked', {'station': r.station});
  if (!v.known) return _fail(state, 'recipe_locked', {'need': r.level, 'skill': v.skill, 'flag': v.needsStory ? r.flag : null});
  if (!hasIngredients(state, r.needs)) return _fail(state, 'missing_ingredients');
  final q = craftQualities[quality] ?? craftQualities['good']!;
  final s = state.copy();
  r.needs.forEach((id, n) => _take(s, id, n));
  g.grantItem(s, r.makes, q.batch, r.station, now, '${r.station}:$recipeId:$now');
  final countKey = r.station == 'kitchen' ? 'cooked' : 'brewed';
  s.home.counts[countKey] = (s.home.counts[countKey] ?? 0) + 1;
  if (quality == 'perfect') s.home.counts['perfect'] = (s.home.counts['perfect'] ?? 0) + 1;
  final events = <g.GameEvent>[
    g.GameEvent('crafted', {
      'recipe': recipeId,
      'station': r.station,
      'item': r.makes,
      'qty': q.batch,
      'quality': craftQualities.containsKey(quality) ? quality : 'good',
    }),
  ];
  _addSkillXp(s, v.skill, r.xp * q.xp, events);
  return _ok(s, events);
}

g.ActionResult markHomeSeen(GameState state, String key) {
  if (state.home.seen[key] == true) return _ok(state);
  final s = state.copy();
  s.home.seen[key] = true;
  return _ok(s);
}

// -------------------------------------------------------------------- labels ----
/// Display name with a simple plural ("3 Sunberries", "2 Golden Wheat").
String itemLabel(String id, [int n = 1]) {
  final nm = catalog[id]?.name ?? id;
  if (n == 1 || RegExp(r'(Wheat|Glowleaf|Tea|s)$').hasMatch(nm)) return nm;
  if (RegExp(r'[^aeiou]y$').hasMatch(nm)) return '${nm.substring(0, nm.length - 1)}ies';
  return '${nm}s';
}

/// Where an item comes from at home: the Garden for crops, the Kitchen or Apothecary for recipes.
class HomeSource {
  const HomeSource({required this.route, required this.verb, required this.place, this.station});
  final String route; // garden | station
  final String verb; // Grow | Cook | Brew
  final String place; // Garden | Kitchen | Apothecary
  final String? station;
  @override
  String toString() => 'HomeSource($route, $verb, $place, $station)';
}

HomeSource? homeSource(String id) {
  final it = catalog[id];
  if (it == null) return null;
  if (it.category == ItemCategory.ingredient || it.category == ItemCategory.seed) return const HomeSource(route: 'garden', verb: 'Grow', place: 'Garden');
  final r = recipeDefs[id];
  if (r != null) {
    final st = stationDefs[r.station]!;
    return HomeSource(route: 'station', station: r.station, verb: st.verb, place: st.name);
  }
  return null;
}

/// The recipes an ingredient goes into.
List<RecipeDef> recipesUsing(String id) => [for (final r in recipeOrder) if (recipeDefs[r]!.needs.containsKey(id)) recipeDefs[r]!];
