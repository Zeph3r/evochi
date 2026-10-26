// The Hatching Nook and the companions (docs: Evochi Hatching Nook & Companion Collection design bible).
//
// An egg is found out in the world (a nest hollow on a Deep Wilds floor, a quiet corner of the mine) or
// chosen at the Caravan for Glimmer, with what it can hatch into shown first. It waits in the collection
// until you set it in one of the nook's cradles; from then your verified steps grow it (each day's steps
// counted once, whatever the syncing), gentle care adds a little, and nothing ever sets it back. Ready,
// it waits for you: hatching is your tap, one short celebration, one new Evochi that joins the
// companions resting at home. The Nest keeps one active Evochi; switching is a tap, and the one resting
// keeps everything it had.
//
// Settled rules from the bible: eggs that can be found are always free to find; a bought egg says
// exactly what it may become; no egg spoils, no hatch expires, no care is ever demanded; cradles are a
// progression, never a cap on the eggs you keep; a hatch resolves once, atomically.

import 'dart:math' as math;

import '../../app/constants.dart';
import '../../core/models/game_state.dart';
import '../../core/utils/day_keys.dart';
import '../../core/utils/ids.dart';
import '../engine.dart' as g;
import '../xp/step_aggregation.dart';

class EggTemplate {
  const EggTemplate({
    required this.id,
    required this.name,
    required this.need,
    required this.palettes,
    required this.shell,
    required this.spots,
    required this.blurb,
    this.glimmer,
    this.weeklyLimit = 2,
  });
  final String id;
  final String name;
  final int need; // steps to hatch
  final List<String> palettes; // what it can hatch into (one of these, decided at the hatch)
  final int shell, spots; // its colours (ARGB)
  final String blurb;
  final int? glimmer; // its price at the Caravan (null: never sold)
  final int weeklyLimit;
}

const eggTemplates = <String, EggTemplate>{
  'forest_egg': EggTemplate(
    id: 'forest_egg',
    name: 'Forest Egg',
    need: 2000,
    palettes: ['forest', 'amber'],
    shell: 0xFFBFD98A,
    spots: 0xFF6E9A4A,
    blurb: 'Mossy green, warm to the touch. Left in nest hollows along the forest ways.',
  ),
  'stone_egg': EggTemplate(
    id: 'stone_egg',
    name: 'Stone Egg',
    need: 3500,
    palettes: ['obsidian', 'amethyst'],
    shell: 0xFF8E8AA6,
    spots: 0xFF4E4A66,
    blurb: 'Heavy as rock, veined with a faint violet light. Found deep in the galleries.',
  ),
  'tide_egg': EggTemplate(
    id: 'tide_egg',
    name: 'Tide Egg',
    need: 2500,
    palettes: ['ocean', 'coral'],
    shell: 0xFF8FD3E8,
    spots: 0xFFF2A6A0,
    blurb: 'Sea-glass blue with a coral blush. The Caravan carries them up from the coast.',
    glimmer: 240,
  ),
  'ember_egg': EggTemplate(
    id: 'ember_egg',
    name: 'Ember Egg',
    need: 2500,
    palettes: ['amber', 'obsidian'],
    shell: 0xFFF2B35A,
    spots: 0xFF9C4A2A,
    blurb: 'Warm all through, speckled dark. The Caravan trades for them in the far hills.',
    glimmer: 240,
  ),
};

/// The eggs the Caravan sells, in its order.
List<EggTemplate> get caravanEggs => [for (final t in eggTemplates.values) if (t.glimmer != null) t];

/// The four readable stages of an incubating egg, by how far along it is.
String hatchStage(double frac) => frac >= 0.9 ? 'ready' : (frac >= 0.5 ? 'cracking' : (frac >= 0.25 ? 'stirring' : 'resting'));

const stageWords = {'resting': 'Resting', 'stirring': 'Stirring', 'cracking': 'Cracking', 'ready': 'Ready to hatch'};

double fractionOf(Egg e) => (e.progress / (eggTemplates[e.templateId]?.need ?? 2000)).clamp(0.0, 1.0);

const _dayCap = 12000; // steps a day that count toward an egg
const _careSteps = 0.02; // care: a fiftieth of the way, once a day
const _foundPerDay = 1; // eggs found out in the world, a day

Egg? eggById(GameState s, String id) => s.hatch.eggs.where((e) => e.id == id).firstOrNull;
List<Egg> cradled(GameState s) => [for (final e in s.hatch.eggs) if (e.inCradle) e]..sort((a, b) => (a.slot ?? 0).compareTo(b.slot ?? 0));
List<Egg> stored(GameState s) => [for (final e in s.hatch.eggs) if (e.state == 'owned') e];
int? freeSlot(GameState s) {
  final taken = {for (final e in cradled(s)) e.slot};
  for (var i = 0; i < s.hatch.slots; i++) {
    if (!taken.contains(i)) return i;
  }
  return null;
}

/// How many of a sold egg were bought this week (its limit is per week).
int boughtThisWeek(GameState s, String templateId, int now) {
  final week = weekKey(dayKey(now, g.zoneOf(s)));
  return s.txns.where((t) => t.id.startsWith('egg:$templateId:$week:')).length;
}

g.ActionResult _ok(GameState s, [List<g.GameEvent> events = const []]) => g.ActionResult(s, events: events);
g.ActionResult _fail(GameState s, String error, [Map<String, Object?> info = const {}]) => g.ActionResult(s, error: error, info: info);

/// An egg found out in the world, under [key] (a floor's nest hollow pays once), at most one a day.
g.ActionResult findEgg(GameState state, String templateId, String origin, String key, int now) {
  final t = eggTemplates[templateId];
  if (t == null) return _fail(state, 'unknown_egg');
  if (state.hatch.eggs.any((e) => e.id == 'egg:$key')) return _ok(state);
  final day = dayKey(now, g.zoneOf(state));
  if ((state.hatch.found[day] ?? 0) >= _foundPerDay) return _fail(state, 'found_today');
  final s = state.copy();
  s.hatch.eggs.add(Egg(id: 'egg:$key', templateId: templateId, origin: origin, acquiredAt: now));
  s.hatch.found[day] = (s.hatch.found[day] ?? 0) + 1;
  s.hatch.found.removeWhere((k, _) => k.compareTo(addDays(day, -7)) < 0);
  return _ok(s, [g.GameEvent('egg_found', {'egg': 'egg:$key', 'template': templateId, 'first': s.hatch.eggs.length == 1})]);
}

/// An egg chosen at the Caravan: its price in Glimmer, within its weekly limit, once per [requestId].
g.ActionResult buyEgg(GameState state, String templateId, String requestId, int now) {
  final t = eggTemplates[templateId];
  if (t == null || t.glimmer == null) return _fail(state, 'not_for_sale');
  final week = weekKey(dayKey(now, g.zoneOf(state)));
  final txn = 'egg:$templateId:$week:$requestId';
  if (state.txns.any((x) => x.id == txn)) return _ok(state, [g.GameEvent('already_purchased', {'offer': templateId})]);
  if (boughtThisWeek(state, templateId, now) >= t.weeklyLimit) return _fail(state, 'weekly_limit', {'limit': t.weeklyLimit});
  final bal = g.balanceOf(state, 'glimmer');
  if (bal < t.glimmer!) return _fail(state, 'need_glimmer', {'short': t.glimmer! - bal, 'price': t.glimmer});
  final s = state.copy();
  g.addTxn(s, WalletTxn(id: txn, amount: -t.glimmer!, cause: 'egg:$templateId', at: now, currency: 'glimmer'));
  s.hatch.eggs.add(Egg(id: 'egg:$txn', templateId: templateId, origin: 'Chosen at the Caravan', acquiredAt: now));
  return _ok(s, [g.GameEvent('egg_bought', {'egg': 'egg:$txn', 'template': templateId, 'price': t.glimmer})]);
}

/// A stored egg set in a free cradle: from now its steps count.
g.ActionResult assignEgg(GameState state, String eggId, int now) {
  final e = eggById(state, eggId);
  if (e == null) return _fail(state, 'no_egg');
  if (e.state != 'owned') return _fail(state, 'not_stored');
  final slot = freeSlot(state);
  if (slot == null) return _fail(state, 'no_free_cradle');
  final s = state.copy();
  final egg = eggById(s, eggId)!;
  final zone = g.zoneOf(s);
  final today = dayKey(now, zone);
  egg.state = 'incubating';
  egg.slot = slot;
  egg.assignedDay = today;
  // what was walked today before this moment stays the day's, not the egg's
  final sofar = aggregateDays(s.steps.samples, zone)[today]?.steps ?? 0;
  egg.stepsAwarded[today] = math.max(egg.stepsAwarded[today] ?? 0, math.min(sofar, _dayCap));
  if (fractionOf(egg) >= 1) egg.state = 'ready';
  return _ok(s, [g.GameEvent('egg_assigned', {'egg': eggId, 'slot': slot})]);
}

/// Back to the collection (its progress kept, no more steps until it is set again).
g.ActionResult unassignEgg(GameState state, String eggId) {
  final e = eggById(state, eggId);
  if (e == null || !e.inCradle) return _fail(state, 'not_in_cradle');
  final s = state.copy();
  final egg = eggById(s, eggId)!;
  egg.state = 'owned';
  egg.slot = null;
  egg.assignedDay = null;
  return _ok(s, [g.GameEvent('egg_unassigned', {'egg': eggId})]);
}

/// A little care, once a day: a touch of warmth toward the hatch (never asked for, never missed).
g.ActionResult careEgg(GameState state, String eggId, int now) {
  final e = eggById(state, eggId);
  if (e == null || !e.inCradle) return _fail(state, 'not_in_cradle');
  final day = dayKey(now, g.zoneOf(state));
  if (e.careDays.contains(day)) return _fail(state, 'cared_today');
  final s = state.copy();
  final egg = eggById(s, eggId)!;
  egg.careDays.add(day);
  final need = eggTemplates[egg.templateId]?.need ?? 2000;
  egg.progress += (need * _careSteps).round();
  final events = [g.GameEvent('egg_cared', {'egg': eggId})];
  if (egg.state == 'incubating' && fractionOf(egg) >= 1) {
    egg.state = 'ready';
    events.add(g.GameEvent('egg_ready', {'egg': eggId}));
  }
  return _ok(s, events);
}

/// Walking, counted into every cradled egg once a day (called from the step sync on the copied state).
List<g.GameEvent> applyHatchProgress(GameState s, int now) {
  final events = <g.GameEvent>[];
  final eggs = cradled(s).where((e) => e.state == 'incubating').toList();
  if (eggs.isEmpty) return events;
  final zone = g.zoneOf(s);
  final today = dayKey(now, zone);
  final days = aggregateDays(s.steps.samples, zone);
  for (final e in eggs) {
    final from = e.assignedDay ?? today;
    days.forEach((k, d) {
      if (k.compareTo(from) < 0 || k.compareTo(today) > 0) return;
      final elig = math.min(d.steps, _dayCap);
      final awarded = e.stepsAwarded[k] ?? 0;
      if (elig > awarded) {
        e.stepsAwarded[k] = elig;
        e.progress += elig - awarded;
      }
    });
    if (fractionOf(e) >= 1) {
      e.state = 'ready';
      events.add(g.GameEvent('egg_ready', {'egg': e.id}));
    }
  }
  return events;
}

/// What a ready egg will hatch into: decided by the egg itself, the same every time it is asked.
String hatchPalette(Egg e) {
  final t = eggTemplates[e.templateId];
  final list = t?.palettes ?? const ['amber'];
  return list[g.seededRandom('hatch:${e.id}').nextInt(list.length)];
}

/// The hatch: one new Evochi (named now, or later), the egg resolved, the cradle freed; the newcomer
/// rests with the companions (never made active for you). The first hatch earns a second cradle, the
/// third a third.
g.ActionResult hatchEgg(GameState state, String eggId, {required String name, required String requestId, required int now}) {
  final e = eggById(state, eggId);
  if (e == null) return _fail(state, 'no_egg');
  if (e.state == 'hatched') {
    final pet = [state.pet, ...state.companions].whereType<Pet>().where((p) => p.requestId == requestId).firstOrNull;
    return pet != null ? _ok(state) : _fail(state, 'already_hatched');
  }
  if (e.state != 'ready') return _fail(state, 'not_ready');
  final v = g.validateName(name);
  if (!v.ok) return _fail(state, 'invalid_name', {'message': v.error});
  final s = state.copy();
  final egg = eggById(s, eggId)!;
  final today = dayKey(now, g.zoneOf(s));
  final paletteId = hatchPalette(egg);
  final pet = Pet(
    id: newId('pet'),
    requestId: requestId,
    name: v.name,
    paletteId: paletteId,
    stage: 1,
    habitatId: s.pet?.habitatId ?? 'sunlit_meadow',
    createdAt: now,
    createdDay: today,
    origin: egg.origin,
    evolutions: [
      {'stage': 1, 'at': now}
    ],
  );
  egg.state = 'hatched';
  egg.slot = null;
  egg.hatchedPetId = pet.id;
  egg.hatchedAt = now;
  s.hatch.hatched++;
  if (s.hatch.hatched == 1 && s.hatch.slots < 2) s.hatch.slots = 2;
  if (s.hatch.hatched == 3 && s.hatch.slots < 3) s.hatch.slots = 3;
  if (s.pet == null) {
    s.pet = pet; // no Evochi at all: the newcomer is yours at once
  } else {
    s.companions.add(pet);
  }
  s.unlocks.putIfAbsent('palette:$paletteId', () => now);
  return _ok(s, [g.GameEvent('egg_hatched', {'egg': eggId, 'petId': pet.id, 'palette': paletteId, 'slots': s.hatch.slots})]);
}

/// Every Evochi you have: the active one first, then the companions resting at home.
List<Pet> allPets(GameState s) => [if (s.pet != null) s.pet!, ...s.companions];

/// A resting companion made active; the one that was active rests in its place, keeping everything.
g.ActionResult setActive(GameState state, String petId) {
  if (state.pet?.id == petId) return _ok(state);
  final i = state.companions.indexWhere((p) => p.id == petId);
  if (i < 0) return _fail(state, 'not_owned');
  final s = state.copy();
  final next = s.companions.removeAt(i);
  final was = s.pet;
  s.pet = next;
  if (was != null) s.companions.insert(0, was);
  return _ok(s, [g.GameEvent('companion_active', {'petId': petId})]);
}

bool isFavorite(GameState s, String petId) => s.flags['fav:$petId'] == true;

g.ActionResult toggleFavorite(GameState state, String petId) {
  final s = state.copy();
  s.flags['fav:$petId'] = !(state.flags['fav:$petId'] == true);
  return _ok(s);
}

/// A new name for any Evochi you have, active or resting.
g.ActionResult renameCompanion(GameState state, String petId, String name) {
  final v = g.validateName(name);
  if (!v.ok) return _fail(state, 'invalid_name', {'message': v.error});
  final s = state.copy();
  final p = allPets(s).where((p) => p.id == petId).firstOrNull;
  if (p == null) return _fail(state, 'not_owned');
  p.name = v.name;
  return _ok(s);
}

String paletteLabel(String id) => palettes.where((p) => p.id == id).firstOrNull?.label ?? id;

/// A flag remembered on the save (the hatch celebration seen once: it can be skipped after).
g.ActionResult setFlag(GameState state, String key, bool value) {
  if ((state.flags[key] == true) == value) return _ok(state);
  final s = state.copy();
  s.flags[key] = value;
  return _ok(s);
}
