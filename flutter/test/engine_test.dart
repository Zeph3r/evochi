// Engine tests, including the release QA matrix cases that are pure game logic (style guide §24).
// Mirrors web/test/engine.test.mjs so both clients are held to the same rules.

import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/game/bond/bond.dart';
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/vitality/vitality.dart';
import 'package:evochi/game/xp/step_aggregation.dart';
import 'package:evochi/game/xp/xp.dart';
import 'package:flutter_test/flutter_test.dart';

const tzName = 'America/New_York';
final t0 = DateTime.utc(2026, 10, 5, 14).millisecondsSinceEpoch; // Mon 5 Oct 2026, 10:00 New York

GameState freshPet([int? now]) {
  final n = now ?? t0;
  var s = GameState.fresh(n, tzName);
  s = g.startGuest(s, n, tzName).state;
  s = g.setConnection(s, 'demo', n).state;
  final r = g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: n);
  expect(r.error, isNull);
  return r.state;
}

List<StepSample> walk(String key, int steps, [String tag = '']) {
  final start = dayStart(key, tzName) + 9 * hourMs;
  return [StepSample(id: 'w_${key}_${steps}_$tag', source: 'phone', start: start, end: start + hourMs, count: steps)];
}

List<StepSample> dayOf(String key, int steps) {
  final start = dayStart(key, tzName) + 9 * hourMs;
  return List.generate(8, (i) {
    final st = start + i * hourMs;
    return StepSample(id: 'bf_${key}_${i}_$steps', source: 'phone', start: st, end: st + 30 * 60000, count: (steps / 8).round());
  });
}

void main() {
  setUpAll(ensureTimeZones);

  test('activity XP worked example (§15)', () {
    const rows = [
      [0, 0],
      [1750, 35],
      [3500, 75],
      [4850, 94],
      [7000, 150],
      [10500, 170],
      [20000, 170],
    ];
    for (final r in rows) {
      expect(calculateDailyXp(r[0], 7000).total, r[1], reason: 'steps ${r[0]}');
    }
    final x = calculateDailyXp(4850, 7000);
    expect(x.base, 69);
    expect(x.milestones, 25);
  });

  test('level curve: ~600 XP needed at level 8', () {
    expect(xpToNext(1), 120);
    expect(xpToNext(8), 600);
    final total = List.generate(7, (i) => xpToNext(i + 1)).reduce((a, b) => a + b);
    final li = levelInfo(total + 320);
    expect(li.level, 8);
    expect(li.into, 320);
    expect(li.need, 600);
  });

  test('Q01 fresh install -> guest -> create pet exactly once', () {
    final s = freshPet();
    final again = g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: t0 + 1000);
    expect(again.error, isNull);
    expect(again.state.pet!.id, s.pet!.id);
    expect(g.createPet(s, name: 'Other', paletteId: 'ocean', requestId: 'req-2', now: t0).error, 'pet_exists');
    expect(s.pet!.paletteId, 'amber');
    expect(s.pet!.name, 'Ember');
  });

  test('name validation', () {
    expect(g.validateName('  Ember  ').name, 'Ember');
    expect(g.validateName('').ok, isFalse);
    expect(g.validateName('x' * 13).ok, isFalse);
    expect(g.validateName('<script>').ok, isFalse);
  });

  test('Q03 sync 4,850 / 7,000 steps -> 94 XP once', () {
    var s = freshPet();
    final r = g.syncSteps(s, walk(dayKey(t0, tzName), 4850), t0 + hourMs);
    s = r.state;
    final d = g.derive(s, t0 + hourMs);
    expect(d.todaySteps, 4850);
    expect(d.pet!.totalXp, 94);
    expect(r.events.any((e) => e.type == 'xp' && e.data['amount'] == 94), isTrue);
  });

  test('Q04 re-delivered sample gives no extra XP or coins', () {
    var s = freshPet();
    final key = dayKey(t0, tzName);
    s = g.syncSteps(s, walk(key, 7000), t0 + hourMs).state;
    s = g.claimQuest(s, 'daily_goal', t0 + hourMs).state;
    final bal = g.balanceOf(s);
    final xp = g.derive(s, t0 + hourMs).pet!.totalXp;
    final r = g.syncSteps(s, walk(key, 7000), t0 + 2 * hourMs);
    expect(g.derive(r.state, t0 + 2 * hourMs).pet!.totalXp, xp);
    expect(g.balanceOf(r.state), bal);
    expect(r.events.any((e) => e.type == 'xp'), isFalse);
  });

  test('cross-source de-duplication (phone + watch count once)', () {
    final key = dayKey(t0, tzName);
    final start = dayStart(key, tzName) + 9 * hourMs;
    final samples = [
      StepSample(id: 'a', source: 'phone', start: start, end: start + 15 * 60000, count: 1000),
      StepSample(id: 'b', source: 'watch', start: start, end: start + 15 * 60000, count: 980),
    ];
    expect(aggregateDays(samples, tzName)[key]!.steps, 1000);
  });

  test('Q05 rapid double claim grants once', () {
    var s = freshPet();
    s = g.syncSteps(s, walk(dayKey(t0, tzName), 2000), t0 + hourMs).state;
    final r1 = g.claimQuest(s, 'first_steps', t0 + hourMs);
    final r2 = g.claimQuest(r1.state, 'first_steps', t0 + hourMs + 5);
    expect(g.balanceOf(r2.state), 15);
    expect(r2.state.txns.where((t) => t.cause == 'quest:first_steps').length, 1);
    expect(r2.events.any((e) => e.type == 'already_claimed'), isTrue);
  });

  test('quests are not claimable before the threshold', () {
    var s = freshPet();
    s = g.syncSteps(s, walk(dayKey(t0, tzName), 1000), t0 + hourMs).state;
    expect(g.claimQuest(s, 'first_steps', t0 + hourMs).error, 'not_eligible');
  });

  test('Q07 purchase affordable crown; Q08 insufficient funds', () {
    var s = freshPet();
    s = g.grantCoins(s, 200, t0).state;
    final r = g.purchase(s, 'golden_crest_crown', 'buy-1', t0);
    expect(r.error, isNull);
    expect(g.balanceOf(r.state), 50);
    expect(g.ownedQty(r.state, 'golden_crest_crown'), 1);
    expect(g.balanceOf(g.purchase(r.state, 'golden_crest_crown', 'buy-1', t0 + 1).state), 50);
    expect(g.purchase(r.state, 'golden_crest_crown', 'buy-2', t0).error, 'owned');
    final poor = g.purchase(r.state, 'explorer_hat', 'buy-3', t0);
    expect(poor.error, 'insufficient');
    expect(g.balanceOf(poor.state), 50);
    expect(g.ownedQty(poor.state, 'explorer_hat'), 0);
  });

  test('Q06 equip head cosmetic then evolve: anchors kept, no entitlement lost', () {
    var s = freshPet();
    s = g.grantCoins(s, 500, t0).state;
    s = g.purchase(s, 'explorer_hat', 'p1', t0).state;
    s = g.equip(s, 'explorer_hat', t0).state;
    var now = t0;
    for (var i = 0; i < 20; i++) {
      final key = addDays(dayKey(t0, tzName), i);
      now = dayStart(key, tzName) + 20 * hourMs;
      s = g.syncSteps(s, walk(key, 10500), now).state;
    }
    final d = g.derive(s, now);
    expect(d.pet!.level.level, greaterThanOrEqualTo(10));
    expect(d.pet!.evolution.eligible, isTrue);
    final r = g.evolve(s, now);
    expect(r.error, isNull);
    expect(r.state.pet!.stage, 2);
    expect(r.state.pet!.equipped['head'], 'explorer_hat');
    expect(g.ownedQty(r.state, 'explorer_hat'), 1);
    expect(g.evolve(r.state, now).error, 'not_eligible');
  });

  test('Q10 two protected rest days per rolling week; penalties wait 48h grace', () {
    var s = freshPet();
    final k0 = dayKey(t0, tzName);
    s = g.syncSteps(s, walk(k0, 7000), t0 + hourMs).state;
    final now = dayStart(addDays(k0, 6), tzName) + 12 * hourMs;
    s = g.syncSteps(s, [], now).state;
    final d = g.derive(s, now);
    final kinds = {for (final x in d.pet!.vitality.log) x.key: x.kind};
    expect(kinds[k0], DayKind.goal);
    expect(kinds[addDays(k0, 1)], DayKind.rest);
    expect(kinds[addDays(k0, 2)], DayKind.rest);
    expect(kinds[addDays(k0, 3)], DayKind.low);
    expect(kinds[addDays(k0, 4)], DayKind.grace);
    expect(kinds[addDays(k0, 5)], DayKind.grace);
    expect(d.pet!.vitality.vitality, 92);
  });

  test('late data reverses an incorrect penalty (idempotent replay)', () {
    var s = freshPet();
    final k0 = dayKey(t0, tzName);
    final now = dayStart(addDays(k0, 6), tzName) + 12 * hourMs;
    s = g.syncSteps(s, [], now).state;
    final before = g.derive(s, now).pet!.vitality.vitality;
    s = g.syncSteps(s, dayOf(addDays(k0, 3), 6000), now + 1000).state;
    expect(g.derive(s, now + 1000).pet!.vitality.vitality, greaterThan(before));
  });

  test('missing sensor data is pending, not inactive', () {
    final s = freshPet();
    s.steps.syncedUntil = t0;
    final d = g.derive(s, dayStart(addDays(dayKey(t0, tzName), 6), tzName));
    expect(d.pet!.vitality.vitality, 100);
    expect(d.pet!.vitality.log.every((x) => x.kind == DayKind.pending), isTrue);
  });

  test('Q11 time zone travel keeps day attribution deterministic', () {
    var s = freshPet();
    final key = dayKey(t0, tzName);
    s = g.syncSteps(s, walk(key, 7000), t0 + hourMs).state;
    s = g.claimQuest(s, 'daily_goal', t0 + hourMs).state;
    final bal = g.balanceOf(s);
    expect(g.derive(s, t0 + 2 * hourMs).today, key);
    expect(g.balanceOf(g.claimQuest(s, 'daily_goal', t0 + 2 * hourMs).state), bal);
  });

  test('Q14 vitality zero -> memorial keeps possessions; revive paths', () {
    var s = freshPet();
    s = g.grantCoins(s, 300, t0).state;
    s = g.purchase(s, 'leaf_scarf', 'x', t0).state;
    final k0 = dayKey(t0, tzName);
    final now = dayStart(addDays(k0, 40), tzName) + 12 * hourMs;
    s = g.syncSteps(s, [], now).state;
    final d = g.derive(s, now);
    expect(d.pet!.dead, isTrue);
    expect(g.useConsumable(s, 'berry_snack', now).error, 'pet_dead');
    expect(g.reviveWithWalk(s, now).error, 'walk_needed');
    final s2 = g.syncSteps(s, walk(dayKey(now, tzName), 7200, 'rv'), now + 1000).state;
    final rv = g.reviveWithWalk(s2, now + 2000);
    expect(rv.error, isNull);
    expect(g.derive(rv.state, now + 2000).pet!.dead, isFalse);
    final m = g.memorialize(s, now);
    expect(m.state.pet, isNull);
    expect(m.state.pastPets.length, 1);
    expect(g.ownedQty(m.state, 'leaf_scarf'), 1);
    expect(g.balanceOf(m.state), g.balanceOf(s));
  });

  test('bond: daily direct cap and celebration', () {
    final ev = [
      BondEvent(key: 'd1', type: 'pet', t: 0),
      BondEvent(key: 'd1', type: 'pet', t: 1),
      BondEvent(key: 'd1', type: 'play', t: 2),
      BondEvent(key: 'd1', type: 'goal', t: 3),
    ];
    expect(bondValue(ev), 6);
  });

  test('consumables decrement on accepted use; herb cooldown', () {
    var s = freshPet();
    final now = dayStart(addDays(dayKey(t0, tzName), 9), tzName) + 12 * hourMs;
    s = g.syncSteps(s, [], now).state;
    final v0 = g.derive(s, now).pet!.vitality.vitality;
    expect(v0, lessThan(100));
    final r = g.useConsumable(s, 'berry_snack', now);
    expect(r.error, isNull);
    expect(g.ownedQty(r.state, 'berry_snack'), 1);
    s = g.grantCoins(r.state, 200, now).state;
    s = g.purchase(s, 'healing_herb', 'h1', now).state;
    s = g.purchase(s, 'healing_herb', 'h2', now).state;
    s = g.useConsumable(s, 'healing_herb', now).state;
    expect(g.useConsumable(s, 'healing_herb', now + hourMs).error, 'cooldown');
  });

  test('decorations need a compatible anchor and ownership', () {
    var s = freshPet();
    expect(s.placements['nest'], 'nest_bed');
    expect(g.placeDecoration(s, 'nest_bed', 'left').error, 'no_anchor');
    expect(g.placeDecoration(s, 'sunlit_flower', 'left').error, 'all_placed');
    s = g.grantCoins(s, 100, t0).state;
    s = g.purchase(s, 'sunlit_flower', 'f', t0).state;
    s = g.placeDecoration(s, 'sunlit_flower', 'left').state;
    expect(g.placeDecoration(s, 'sunlit_flower', 'right').error, 'all_placed');
  });

  test('save round-trips through JSON', () {
    final s = freshPet();
    final back = GameState.tryParse(s.serialize());
    expect(back, isNotNull);
    expect(back!.pet!.name, 'Ember');
    expect(GameState.tryParse('{"schema": 99}'), isNull);
  });

  test('week keys and DST-safe day starts', () {
    expect(weekKey('2026-10-05'), '2026-W41');
    expect(weekKey('2026-10-11'), '2026-W41');
    expect(weekKey('2026-10-12'), '2026-W42');
    expect(weekKey('2027-01-01'), '2026-W53');
    final st = dayStart('2026-11-01', tzName);
    expect(dayKey(st, tzName), '2026-11-01');
    expect(dayKey(st - 1, tzName), '2026-10-31');
  });
}
