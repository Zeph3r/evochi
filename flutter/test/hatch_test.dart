// The Hatching Nook (game/hatch/hatch.dart): eggs found and bought, cradles, steps counted once a day,
// care, the hatch into one new companion, and switching the active Evochi.

import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/hatch/hatch.dart' as hatch;
import 'package:flutter_test/flutter_test.dart';

const tzName = 'America/New_York';
final t0 = DateTime.utc(2026, 10, 19, 14).millisecondsSinceEpoch;
const k0 = '2026-10-19';

GameState must(g.ActionResult r) {
  expect(r.error, isNull, reason: r.error);
  return r.state;
}

GameState freshPet() {
  var s = GameState.fresh(t0, tzName);
  s = g.startGuest(s, t0, tzName).state;
  s = g.setConnection(s, 'demo', t0).state;
  return must(g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: t0));
}

GameState walkDay(GameState s, String key, int steps, [String tag = '']) {
  final start = dayStart(key, tzName) + 9 * hourMs;
  return must(g.syncSteps(s, [StepSample(id: 'w_${key}_${steps}_$tag', source: 'phone', start: start, end: start + hourMs, count: steps)], start + 2 * hourMs));
}

GameState glimmer(GameState s, int n) {
  final c = s.copy();
  g.addTxn(c, WalletTxn(id: 'test:glimmer', amount: n, cause: 'test', at: t0, currency: 'glimmer'));
  return c;
}

void main() {
  setUpAll(ensureTimeZones);

  test('an egg found in the world is one durable thing: the same hollow never pays twice, one find a day', () {
    var s = freshPet();
    final r = hatch.findEgg(s, 'forest_egg', 'Found in the Deep Wilds', 'deep:2:77', t0);
    expect(r.error, isNull);
    expect(r.events.first.type, 'egg_found');
    s = r.state;
    expect(s.hatch.eggs.length, 1);
    expect(s.hatch.eggs.single.state, 'owned');
    expect(hatch.findEgg(s, 'forest_egg', 'Found in the Deep Wilds', 'deep:2:77', t0 + 1000).state.hatch.eggs.length, 1);
    expect(hatch.findEgg(s, 'forest_egg', 'Found in the Deep Wilds', 'deep:3:78', t0 + 2000).error, 'found_today');
    final round = GameState.fromJson(s.toJson());
    expect(round.hatch.eggs.single.templateId, 'forest_egg');
  });

  test("a Caravan egg says what it may become, costs Glimmer, and a week's limit holds", () {
    var s = glimmer(freshPet(), 1000);
    final t = hatch.eggTemplates['tide_egg']!;
    expect(t.palettes, ['ocean', 'coral']);
    expect(hatch.buyEgg(freshPet(), 'tide_egg', 'b1', t0).error, 'need_glimmer');
    s = must(hatch.buyEgg(s, 'tide_egg', 'b1', t0));
    expect(g.balanceOf(s, 'glimmer'), 1000 - 240);
    expect(hatch.buyEgg(s, 'tide_egg', 'b1', t0).state.hatch.eggs.length, 1, reason: 'a repeated request grants nothing');
    s = must(hatch.buyEgg(s, 'tide_egg', 'b2', t0));
    expect(hatch.buyEgg(s, 'tide_egg', 'b3', t0).error, 'weekly_limit');
    expect(hatch.buyEgg(s, 'forest_egg', 'b4', t0).error, 'not_for_sale', reason: 'the free egg is never sold');
    expect(s.hatch.eggs.every((e) => e.origin == 'Chosen at the Caravan'), isTrue);
  });

  test('a stored egg does not grow; set in a cradle, each day\'s steps count once however often they sync', () {
    var s = must(hatch.findEgg(freshPet(), 'forest_egg', 'Found', 'a', t0));
    s = walkDay(s, k0, 3000);
    expect(s.hatch.eggs.single.progress, 0, reason: 'in the collection it waits');
    s = must(hatch.assignEgg(s, s.hatch.eggs.single.id, t0));
    expect(s.hatch.eggs.single.state, 'incubating');
    expect(s.hatch.eggs.single.slot, 0);
    final k1 = addDays(k0, 1);
    s = walkDay(s, k1, 800);
    expect(s.hatch.eggs.single.progress, 800);
    s = walkDay(s, k1, 800, 'again'); // more samples the same day: the total grows, nothing counts twice
    expect(s.hatch.eggs.single.progress, 1600);
    expect(s.hatch.eggs.single.stepsAwarded[k1], 1600);
    // only one cradle to start: a second egg waits
    s = must(hatch.findEgg(s, 'forest_egg', 'Found', 'b', dayStart(k1, tzName) + 12 * hourMs));
    expect(hatch.assignEgg(s, s.hatch.eggs.last.id, t0).error, 'no_free_cradle');
    // back to the collection keeps what it has
    final id = s.hatch.eggs.first.id;
    s = must(hatch.unassignEgg(s, id));
    expect(hatch.eggById(s, id)!.state, 'owned');
    expect(hatch.eggById(s, id)!.progress, greaterThan(0));
  });

  test('care is a little warmth once a day; ready at the full count; the hatch makes one companion and frees the cradle', () {
    var s = must(hatch.findEgg(freshPet(), 'forest_egg', 'Found in the Deep Wilds', 'a', t0));
    final id = s.hatch.eggs.single.id;
    s = must(hatch.assignEgg(s, id, t0));
    s = must(hatch.careEgg(s, id, t0));
    expect(hatch.careEgg(s, id, t0 + 60000).error, 'cared_today');
    expect(hatch.eggById(s, id)!.progress, 40);
    expect(hatch.hatchEgg(s, id, name: 'Moss', requestId: 'h1', now: t0).error, 'not_ready');
    s = walkDay(s, addDays(k0, 1), 2500);
    final egg = hatch.eggById(s, id)!;
    expect(egg.state, 'ready');
    expect(hatch.hatchStage(hatch.fractionOf(egg)), 'ready');
    final palette = hatch.hatchPalette(egg);
    expect(['forest', 'amber'], contains(palette));
    expect(hatch.hatchPalette(egg), palette, reason: 'decided by the egg, the same every time');
    final r = hatch.hatchEgg(s, id, name: 'Moss', requestId: 'h1', now: t0 + 90000000);
    expect(r.error, isNull);
    s = r.state;
    expect(s.pet!.name, 'Ember', reason: 'the active Evochi is never switched for you');
    expect(s.companions.single.name, 'Moss');
    expect(s.companions.single.paletteId, palette);
    expect(s.companions.single.origin, 'Found in the Deep Wilds');
    expect(hatch.eggById(s, id)!.state, 'hatched');
    expect(hatch.eggById(s, id)!.hatchedPetId, s.companions.single.id);
    expect(hatch.freeSlot(s), 0);
    expect(s.hatch.slots, 2, reason: 'the first hatch earns a second cradle');
    expect(hatch.hatchEgg(s, id, name: 'Moss', requestId: 'h1', now: t0).error, isNull, reason: 'the same request again does nothing');
    expect(hatch.hatchEgg(s, id, name: 'Moss', requestId: 'h2', now: t0).error, 'already_hatched');
    final round = GameState.fromJson(s.toJson());
    expect(round.companions.single.origin, 'Found in the Deep Wilds');
  });

  test('switching the active Evochi keeps both whole; favourites and names are per companion', () {
    var s = must(hatch.findEgg(freshPet(), 'forest_egg', 'Found', 'a', t0));
    final id = s.hatch.eggs.single.id;
    s = must(hatch.assignEgg(s, id, t0));
    s = walkDay(s, addDays(k0, 1), 2500);
    s = must(hatch.hatchEgg(s, id, name: 'Moss', requestId: 'h1', now: t0));
    final emberXp = Map.of(s.pet!.xpAwarded);
    final moss = s.companions.single.id;
    s = must(hatch.setActive(s, moss));
    expect(s.pet!.id, moss);
    expect(s.companions.single.name, 'Ember');
    expect(s.companions.single.xpAwarded, emberXp);
    expect(hatch.setActive(s, 'nobody').error, 'not_owned');
    s = must(hatch.toggleFavorite(s, moss));
    expect(hatch.isFavorite(s, moss), isTrue);
    s = must(hatch.renameCompanion(s, s.companions.single.id, 'Pebble'));
    expect(s.companions.single.name, 'Pebble');
    expect(hatch.allPets(s).length, 2);
  });
}
