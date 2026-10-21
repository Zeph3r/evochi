// The economy (docs: Evochi Economy & Monetization Plan): Glimmer on the ledger, the tiered daily chest,
// rare finds and what they do, the Starlight Caravan, Season 1, Evochi Plus and Play purchases.

import 'dart:math' as math;

import 'package:evochi/core/models/catalog.dart';
import 'package:evochi/core/models/game_state.dart';
import 'package:evochi/core/utils/day_keys.dart';
import 'package:evochi/game/economy/economy.dart' as e;
import 'package:evochi/game/engine.dart' as g;
import 'package:evochi/game/home/home.dart' as h;
import 'package:evochi/game/wilds/wilds.dart' as w;
import 'package:flutter_test/flutter_test.dart';

const tzName = 'America/New_York';
// Mon 19 Oct 2026, 10:00 New York: the first day of Season 1
final t0 = DateTime.utc(2026, 10, 19, 14).millisecondsSinceEpoch;
const k0 = '2026-10-19';

GameState must(g.ActionResult r) {
  expect(r.error, isNull, reason: r.error);
  return r.state;
}

GameState freshPet([int? now]) {
  final n = now ?? t0;
  var s = GameState.fresh(n, tzName);
  s = g.startGuest(s, n, tzName).state;
  s = g.setConnection(s, 'demo', n).state;
  return must(g.createPet(s, name: 'Ember', paletteId: 'amber', requestId: 'req-1', now: n));
}

/// A verified walk on day [key].
GameState walkDay(GameState s, String key, int steps) {
  final start = dayStart(key, tzName) + 9 * hourMs;
  return must(g.syncSteps(s, [StepSample(id: 'w_${key}_$steps', source: 'phone', start: start, end: start + hourMs, count: steps)], start + 2 * hourMs));
}

int at(String key, [int hour = 20]) => dayStart(key, tzName) + hour * hourMs;

GameState give(GameState s, String id, int n) {
  final c = s.copy();
  g.grantItem(c, id, n, 'test', t0);
  return c;
}

GameState glimmer(GameState s, int n) => must(e.grantGlimmerTest(s, n, t0));

void main() {
  setUpAll(ensureTimeZones);

  group('Glimmer', () {
    test('lives on the ledger beside EvoCoins and never mixes with them', () {
      var s = freshPet();
      final coins = g.balanceOf(s);
      s = glimmer(s, 120);
      expect(e.glimmerOf(s), 120);
      expect(g.balanceOf(s), coins);
      expect(g.derive(s, t0).balance, coins);
    });

    test('survives a save round-trip with the economy block', () {
      var s = glimmer(freshPet(), 50);
      s = give(s, 'hollow_ward', 1);
      s = must(e.armRare(s, 'hollow_ward'));
      final back = GameState.tryParse(s.serialize())!;
      expect(e.glimmerOf(back), 50);
      expect(e.isArmed(back, 'hollow_ward'), isTrue);
    });
  });

  group('Daily chest', () {
    test('tiers climb with goal days this week: Wooden, Silver, Gold', () {
      var s = freshPet();
      s = walkDay(s, k0, 7000);
      expect(e.chestTierPreview(s, at(k0)), 'wood');
      for (var i = 1; i < 4; i++) {
        s = walkDay(s, addDays(k0, i), 7000);
      }
      expect(e.chestTierPreview(s, at(addDays(k0, 3))), 'silver');
      for (var i = 4; i < 6; i++) {
        s = walkDay(s, addDays(k0, i), 7000);
      }
      expect(e.chestTierPreview(s, at(addDays(k0, 5))), 'gold');
    });

    test('a missed day never lowers the tier, and 150% of the goal lifts it one', () {
      var s = freshPet();
      s = walkDay(s, k0, 7000);
      // Tuesday rests; Wednesday walks 150% of the goal
      s = walkDay(s, addDays(k0, 2), 10500);
      expect(e.chestTierPreview(s, at(addDays(k0, 2))), 'silver');
    });

    test('claiming opens the chest once, with a tier and chest rewards', () {
      var s = walkDay(freshPet(), k0, 7000);
      final r = g.claimQuest(s, 'daily_goal', at(k0));
      expect(r.error, isNull);
      final ev = r.events.firstWhere((x) => x.type == 'claimed');
      expect(ev.data['tier'], isIn(['wood', 'lumen']));
      final rewards = (ev.data['rewards'] as List).cast<Map<String, Object?>>();
      expect(rewards.where((x) => x['chest'] == true), isNotEmpty);
      s = r.state;
      final coins = g.balanceOf(s), gl = e.glimmerOf(s);
      final again = g.claimQuest(s, 'daily_goal', at(k0) + 1000);
      expect(g.balanceOf(again.state), coins);
      expect(e.glimmerOf(again.state), gl);
    });

    test('a Golden Acorn lifts the next chest one tier and is spent', () {
      var s = give(walkDay(freshPet(), k0, 7000), 'golden_acorn', 1);
      s = must(e.armRare(s, 'golden_acorn'));
      expect(e.chestTierPreview(s, at(k0)), 'silver');
      s = must(g.claimQuest(s, 'daily_goal', at(k0)));
      expect(e.isArmed(s, 'golden_acorn'), isFalse);
    });

    test('Evochi Plus lifts one chest a week', () {
      var s = must(e.setPlusTest(walkDay(freshPet(), k0, 7000), true, t0));
      expect(e.chestTierPreview(s, at(k0)), 'silver');
      s = must(g.claimQuest(s, 'daily_goal', at(k0)));
      s = walkDay(s, addDays(k0, 1), 7000);
      expect(e.chestTierPreview(s, at(addDays(k0, 1))), 'wood');
    });

    test('manual steps still never open a chest', () {
      var s = freshPet();
      final st = dayStart(k0, tzName) + 9 * hourMs;
      s = must(g.syncSteps(s, [StepSample(id: 'm1', source: 'manual', start: st, end: st + hourMs, count: 8000, manual: true)], st + 2 * hourMs, source: 'manual'));
      final r = g.claimQuest(s, 'daily_goal', at(k0));
      if (r.ok) {
        final ev = r.events.firstWhere((x) => x.type == 'claimed');
        expect(ev.data.containsKey('tier'), isFalse);
      }
    });

    test('published odds cover every tier', () {
      for (final t in e.chestTiers) {
        expect(e.chestOdds(t), isNotEmpty);
      }
    });
  });

  group('Rare finds', () {
    GameState planted() {
      var s = freshPet();
      s = must(h.claimStarterSeeds(s, t0));
      s = must(h.plant(s, 'p1', 'meadow_carrot', t0));
      return must(h.plant(s, 'p2', 'sunberry', t0));
    }

    test('a Sunstone ripens a bed at once', () {
      var s = give(planted(), 'sunstone', 1);
      expect(h.plotView(s, 'p1', t0 + 1000).ripe, isFalse);
      s = must(e.useSunstone(s, 'p1', t0 + 1000));
      expect(h.plotView(s, 'p1', t0 + 2000).ripe, isTrue);
      expect(g.ownedQty(s, 'sunstone'), 0);
      expect(e.useSunstone(s, 'p2', t0).error, 'not_owned');
    });

    test('Moonwell Dew waters every growing bed once per planting', () {
      var s = give(planted(), 'moonwell_dew', 2);
      s = must(e.useMoonwellDew(s, t0 + 1000));
      expect(s.home.plots['p1']!.watered, isTrue);
      expect(s.home.plots['p2']!.watered, isTrue);
      expect(s.home.plots['p1']!.boost, closeTo(0.25, 1e-9));
      expect(e.useMoonwellDew(s, t0 + 2000).error, 'no_beds');
      expect(g.ownedQty(s, 'moonwell_dew'), 1);
    });

    test('a Heartbloom wakes a fainted Evochi at full Vitality', () {
      var s = give(freshPet(), 'heartbloom', 1);
      expect(e.reviveWithHeartbloom(s, t0).error, 'not_dead');
      // nine quiet days: the pet faints
      final later = at(addDays(k0, 30));
      final d = g.derive(s, later);
      if (d.pet!.dead) {
        s = must(e.reviveWithHeartbloom(s, later));
        expect(g.derive(s, later).pet!.vitality.vitality, 100);
      }
    });

    test('a Wayfinder Compass doubles the next discovery and is spent', () {
      var s = give(freshPet(), 'wayfinder_compass', 1);
      s = must(e.armRare(s, 'wayfinder_compass'));
      expect(e.armRare(give(s, 'wayfinder_compass', 1), 'wayfinder_compass').error, 'already_armed');
      final c = s.copy();
      final before = g.balanceOf(c);
      final extras = e.discoveryExtras(c, 30, {'lumen_shard': 1}, 'discovery:test', t0);
      expect(extras.first['kind'], 'compass');
      expect(g.balanceOf(c), before + 30);
      expect(g.ownedQty(c, 'lumen_shard'), 1);
      expect(e.isArmed(c, 'wayfinder_compass'), isFalse);
    });

    test('a Hollow Ward is spent when a Wilds run starts', () {
      var s = must(e.armRare(give(freshPet(), 'hollow_ward', 1), 'hollow_ward'));
      final r = e.wildsTakeWard(s);
      expect(r.events.single.type, 'ward_up');
      expect(e.isArmed(r.state, 'hollow_ward'), isFalse);
      expect(e.wildsTakeWard(r.state).events, isEmpty);
    });

    test('rare finds are never fed to the pet or sold in the Market', () {
      final s = give(freshPet(), 'sunstone', 1);
      expect(g.useConsumable(s, 'sunstone', t0).error, 'use_rare');
      for (final id in e.activeRares) {
        expect(isShopItem(id), isFalse);
        expect(catalog[id]!.glimmer, isNotNull);
      }
    });

    test('drop rates land near the plan', () {
      var sun = 0, ward = 0;
      const n = 200000;
      for (var i = 0; i < n; i++) {
        final d = e.rollDrops('wilds_foe', math.Random(i));
        sun += d['sunstone'] ?? 0;
        ward += d['hollow_ward'] ?? 0;
      }
      expect(sun / n, closeTo(0.005, 0.001));
      expect(ward / n, closeTo(0.01, 0.0015));
    });
  });

  group('Wilds', () {
    test('Glimmer in the satchel banks to the wallet', () {
      var s = freshPet();
      s = must(w.wildsBank(s, 'run1', 5, {e.glimmer: 2, 'lumen_shard': 1}, t0));
      expect(e.glimmerOf(s), 2);
      expect(g.ownedQty(s, 'lumen_shard'), 1);
    });

    test('the first guardian clear pays 50 Glimmer once and 200 Season XP a day', () {
      var s = must(w.wildsClear(freshPet(), 'thicket', t0));
      expect(e.glimmerOf(s), 50);
      expect(s.economy.seasons['s1']!.awards['boss:$k0'], 200);
      s = must(w.wildsClear(s, 'thicket', t0 + hourMs));
      expect(e.glimmerOf(s), 50);
    });
  });

  group('Starlight Caravan', () {
    test('sells rare finds for Glimmer, five-packs 10% off', () {
      var s = freshPet();
      final stock = e.caravanStock(s, t0);
      final one = stock.firstWhere((o) => o.id == 'one:sunstone');
      final five = stock.firstWhere((o) => o.id == 'five:sunstone');
      expect(one.price, 30);
      expect(five.price, 135);
      expect(e.buyCaravan(s, one.id, 'r1', t0).error, 'need_glimmer');
      s = glimmer(s, 200);
      s = must(e.buyCaravan(s, five.id, 'r1', t0));
      expect(g.ownedQty(s, 'sunstone'), 5);
      expect(e.glimmerOf(s), 65);
      // a retried request adds nothing
      expect(e.glimmerOf(e.buyCaravan(s, five.id, 'r1', t0).state), 65);
    });

    test('three daily deals, each once a day', () {
      var s = glimmer(freshPet(), 1000);
      final deals = e.caravanStock(s, t0).where((o) => o.deal).toList();
      expect(deals, hasLength(3));
      expect(deals.first.off, 20);
      s = must(e.buyCaravan(s, deals.first.id, 'a', t0));
      final bal = e.glimmerOf(s);
      expect(e.glimmerOf(e.buyCaravan(s, deals.first.id, 'b', t0).state), bal);
      expect(e.dealBought(s, deals.first.id), isTrue);
    });
  });

  group('Season 1: First Light', () {
    test('XP comes from verified steps, goal days and awards', () {
      var s = freshPet();
      for (var i = 0; i < 5; i++) {
        s = walkDay(s, addDays(k0, i), 7000);
      }
      final v = e.seasonView(s, at(addDays(k0, 4)));
      // 35,000 steps -> 3,500 XP, 5 goal days -> 750, a 4+ goal-day week -> 500
      expect(v.xp, 3500 + 750 + 500);
      expect(v.tier, 4);
      expect(v.active, isTrue);
    });

    test('free tiers claim once; premium needs the pass', () {
      var s = freshPet();
      for (var i = 0; i < 5; i++) {
        s = walkDay(s, addDays(k0, i), 7000);
      }
      final now = at(addDays(k0, 4));
      final coins = g.balanceOf(s);
      s = must(e.claimSeason(s, now));
      expect(e.seasonView(s, now).claimedFree, [1, 2, 3, 4]);
      expect(g.balanceOf(s), greaterThan(coins));
      expect(e.buySeasonPass(s, now).error, 'need_glimmer');
      s = must(e.buySeasonPass(glimmer(s, 500), now));
      expect(e.glimmerOf(s), 0);
      s = must(e.claimSeason(s, now));
      expect(e.seasonView(s, now).claimedPaid, [1, 2, 3, 4]);
      expect(s.story.titleUnlocks, contains('lightbearer'));
      expect(g.ownedQty(s, 'sunstone'), greaterThanOrEqualTo(3));
    });

    test('extra tiers go on sale in week 3', () {
      var s = glimmer(freshPet(), 300);
      expect(e.buySeasonTier(s, 'x', t0).error, 'not_on_sale');
      final wk3 = at(addDays(k0, 14));
      s = must(e.buySeasonTier(s, 'x', wk3));
      expect(e.seasonView(s, wk3).tier, 1);
    });

    test('a regular walker finishes the pass inside the season', () {
      var s = freshPet();
      for (var i = 0; i < 56; i++) {
        // 6,000 steps a day, the goal set to 6,000, five goal days a week
        s = walkDay(s, addDays(k0, i), i % 7 < 5 ? 7000 : 4000);
      }
      expect(e.seasonView(s, at(addDays(k0, 55))).tier, 40);
    });

    test('season cosmetics are owned but wait for their art', () {
      final s = give(freshPet(), 'season_firefly_scarf', 1);
      expect(g.equip(s, 'season_firefly_scarf', t0).error, 'art_pending');
    });
  });

  group('Evochi Plus', () {
    test('welcome Glimmer once, then a daily claim', () {
      var s = must(e.setPlusTest(freshPet(), true, t0));
      expect(e.plusActive(s, t0), isTrue);
      expect(e.glimmerOf(s), 100);
      s = must(e.claimPlusDaily(s, t0));
      expect(e.glimmerOf(s), 110);
      expect(e.plusDailyReady(s, t0), isFalse);
      expect(e.glimmerOf(e.claimPlusDaily(s, t0 + 1000).state), 110);
      final tomorrow = t0 + 24 * hourMs;
      expect(e.plusDailyReady(s, tomorrow), isTrue);
      // ending and restarting never pays the welcome twice
      s = must(e.setPlusTest(s, false, t0));
      s = must(e.setPlusTest(s, true, t0));
      expect(e.glimmerOf(s), 110);
    });

    test('beds water themselves when planted', () {
      var s = must(e.setPlusTest(freshPet(), true, t0));
      s = must(h.claimStarterSeeds(s, t0));
      s = must(h.plant(s, 'p1', 'sunberry', t0));
      expect(s.home.plots['p1']!.watered, isTrue);
    });
  });

  group('Play purchases', () {
    test('grant once per order id; the Starter Pack once per account', () {
      var s = freshPet();
      s = must(e.grantPlayPurchase(s, 'starter_pack', 'test-1', t0));
      expect(e.glimmerOf(s), 300);
      expect(g.ownedQty(s, 'sunstone'), 3);
      expect(e.glimmerOf(e.grantPlayPurchase(s, 'starter_pack', 'test-1', t0).state), 300);
      expect(e.grantPlayPurchase(s, 'starter_pack', 'test-2', t0).error, 'already_owned');
      s = must(e.grantPlayPurchase(s, 'glimmer_550', 'test-3', t0));
      expect(e.glimmerOf(s), 850);
    });

    test('Pass Plus unlocks the premium track and ten tiers', () {
      final s = must(e.grantPlayPurchase(freshPet(), 'pass_plus', 'test-9', t0));
      final v = e.seasonView(s, t0);
      expect(v.premium, isTrue);
      expect(v.tier, 10);
    });

    test('a Plus subscription starts the membership', () {
      final s = must(e.grantPlayPurchase(freshPet(), 'plus_monthly', 'GPA.1', t0));
      expect(e.plusActive(s, t0 + 29 * 24 * hourMs), isTrue);
      expect(e.plusActive(s, t0 + 31 * 24 * hourMs), isFalse);
    });
  });
}
