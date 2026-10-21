// A playtest bot for the Lumen Wilds fights: it plays like a decent (not perfect) player — closes in and
// pounces, bolts the Sporecaps, pulses when crowded, dodges what it sees coming (most of the time, a
// little late now and then), eats a berry when low — and reports how each fight goes, so the numbers
// can be tuned. The bounds it checks are loose: winnable, not trivial.

import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'package:evochi/features/wilds/wilds_combat.dart';
import 'package:flutter_test/flutter_test.dart';

const dt = 1 / 60;

RaidGround field([List<(double, double, double)> blocks = const []]) =>
    RaidGround(wet: (x, z) => false, blocks: blocks, bounds: const Rect.fromLTRB(-300, -700, 300, 700));

class Bot {
  Bot(this.r, {this.skill = 0.8, this.heals = 4, int seed = 1}) : rng = math.Random(seed);
  final Raid r;
  final double skill; // chance it reacts to a telegraph in time
  int heals;
  final math.Random rng;
  double _swingT = 0, _healT = 0;
  int healsUsed = 0, dodges = 0;
  final _noticed = <Mark, bool>{}; // per telegraph: did it notice in time?
  double _bestD = double.infinity, _stuckT = 0;

  RaidInput input() {
    final inp = RaidInput();
    final p = r.pet;
    _swingT -= dt;
    _healT -= dt;
    // something about to land on it: dodge out (if it noticed in time)
    for (final m in r.marks) {
      if (m.done || !m.covers(p.x, p.z, p.radius)) continue;
      final saw = _noticed.putIfAbsent(m, () => rng.nextDouble() < skill);
      if (saw && m.p > 0.6 && r.stamina >= 20) {
        var ex = p.x - m.x, ez = p.z - m.z;
        if (m.shape == MarkShape.line) {
          final side = (p.x - m.x) * m.dz - (p.z - m.z) * m.dx >= 0 ? 1.0 : -1.0;
          ex = m.dz * side;
          ez = -m.dx * side;
        }
        inp
          ..mx = ex
          ..mz = ez
          ..dodge = true;
        dodges++;
        return inp;
      }
    }
    for (final w in r.waves) {
      final d = p.distTo(w.x, w.z);
      if (!w.hit.contains(p) && d - w.r < 16 && d - w.r > 0 && r.stamina >= 20 && rng.nextDouble() < skill) {
        inp
          ..mx = w.x - p.x
          ..mz = w.z - p.z
          ..dodge = true;
        dodges++;
        return inp;
      }
    }
    if (p.hpFrac < 0.35 && heals > 0 && _healT <= 0) {
      heals--;
      healsUsed++;
      _healT = 2.5;
      r.useHeal(26);
    }
    Foe? t;
    var bd = double.infinity;
    for (final f in r.hostile) {
      final d = p.dist(f) - (f.kind == 'sporecap' ? 20 : 0);
      if (d < bd) {
        bd = d;
        t = f;
      }
    }
    if (t == null) return inp;
    final d = p.dist(t);
    var crowd = 0;
    for (final f in r.hostile) {
      if (p.dist(f) < 40) crowd++;
    }
    if (crowd >= 2 && r.pulseCd <= 0 && r.stamina > 40) inp.pulse = true;
    if (t.kind == 'sporecap' && d > 45 && d < 150 && r.boltCd <= 0 && r.stamina > 30) {
      p.face(t.x - p.x, t.z - p.z);
      inp.bolt = true;
    }
    // close in (on the guardian, go for its flank unless that has it stuck), then pounce
    var gx = t.x, gz = t.z;
    if (d < _bestD - 1) {
      _bestD = d;
      _stuckT = 0;
    } else {
      _stuckT += dt;
    }
    if (_stuckT > 1.0) {
      _bestD = d;
      _stuckT = -1.5; // straight at it for a while
    }
    if (t is Boss && _stuckT >= 0) {
      gx = t.x - t.fx * 22 + t.fz * 18;
      gz = t.z - t.fz * 22 - t.fx * 18;
    }
    if (d > t.radius + p.radius + 8) {
      inp
        ..mx = gx - p.x
        ..mz = gz - p.z
        ..run = d > 70;
    } else if (_swingT <= 0 && r.stamina > 10) {
      p.face(t.x - p.x, t.z - p.z);
      inp.attack = true;
      _swingT = 0.24;
    }
    return inp;
  }
}

class Outcome {
  Outcome(this.secs, this.taken, this.knocked, this.healsUsed, this.dodges, this.won, this.by, this.bossHp);
  final double secs, taken, bossHp;
  final bool knocked, won;
  final int healsUsed, dodges;
  final Map<String, int> by;
  @override
  String toString() =>
      '${won ? 'won' : (knocked ? 'KO ' : 'timeout')} ${secs.toStringAsFixed(1)}s took ${taken.round()} heals $healsUsed dodges $dodges'
      '${bossHp > 0 ? ' boss ${(bossHp * 100).round()}%' : ''} ${by.entries.map((e) => '${e.key}:${e.value}').join(',')}';
}

Outcome fight(Raid r, {double skill = 0.8, int seed = 1, double limit = 180, bool boss = false}) {
  final bot = Bot(r, skill: skill, seed: seed);
  var taken = 0.0;
  var last = r.pet.hp;
  var t = 0.0;
  final by = <String, int>{};
  Outcome out(bool knocked, bool won) => Outcome(t, taken, knocked, bot.healsUsed, bot.dodges, won, by, r.boss?.hpFrac ?? 0);
  while (t < limit) {
    r.tick(dt, bot.input());
    t += dt;
    for (final e in r.events) {
      if (e.type == 'hurt') by[e.text ?? '?'] = (by[e.text ?? '?'] ?? 0) + e.value.round();
    }
    r.events.clear();
    if (r.pet.hp < last) taken += last - r.pet.hp;
    last = r.pet.hp;
    if (r.phase == RaidPhase.knocked) return out(true, false);
    final done = boss ? r.bossState == BossState.calm : r.hostile.isEmpty;
    if (done) return out(false, true);
  }
  final b = r.boss;
  if (boss && b != null) {
    // ignore: avoid_print
    print('  stalled: pet (${r.pet.x.round()}, ${r.pet.z.round()}) boss (${b.x.round()}, ${b.z.round()}) ${b.st} ${b.move} '
        'foes ${[for (final f in r.hostile) '${f.kind}@(${f.x.round()},${f.z.round()}) ${f.st}']}');
  }
  return out(false, false);
}

Actor pet(double x, double z) => Actor(id: 'pet', kind: 'pet', team: Team.party, x: x, z: z, radius: 9, health: 140)..face(0, -1);

Actor sher(double x, double z) => Actor(id: 'sher', kind: 'sher', team: Team.party, x: x, z: z, radius: 7, health: 150);

Raid zone(List<FoeSpawn> spawns, int seed, {bool withSher = false}) {
  final r = Raid(ground: field(), pet: pet(0, 60), sher: withSher ? sher(14, 70) : null, spawns: spawns, level: 3, seed: seed);
  if (withSher) r.join();
  for (final f in r.foes) {
    f.face(0, 1);
  }
  return r;
}

/// The arena as the map has it now (tools/art/wilds_maps.py ARENA, ARENA_ROCKS, the boss and summon spots).
Raid wideArena(int seed, {double bossScale = 0.85}) {
  const ax = -14.0, az = -470.0, ar = 135.0;
  final blocks = <(double, double, double)>[
    for (final (dx, dz, r) in const [(-88.0, -30.0, 6.5), (72.0, -56.0, 6.5), (-60.0, 62.0, 15.0), (62.0, 56.0, 6.5), (6.0, -76.0, 6.5),
      (98.0, 6.0, 15.0), (-100.0, -78.0, 6.5), (34.0, 104.0, 6.5)])
      (ax + dx, az + dz, r),
  ];
  for (var k = 0; k < 32; k++) {
    final a = 2 * math.pi * k / 32;
    blocks.add((ax + math.cos(a) * (ar - 4), az + math.sin(a) * (ar - 4) * 0.92, 9.5));
  }
  return Raid(
    ground: field(blocks),
    pet: pet(-20, -410), // a few steps in: where the guardian wakes
    bossDef: const BossDef(
        x: ax + 4, z: az - 48, ax: ax, az: az, ar: ar, wall: [], summon: [(ax - 52, az + 8), (ax + ar - 40, az - 10), (ax - 36, az - ar + 48), (ax + 36, az - ar + 48)]),
    level: 3,
    seed: seed,
    bossScale: bossScale,
  );
}

Raid arena(int seed, {bool withSher = false, double bossScale = 1.0}) {
  // the arena's pillars and boulder, its rim of brambles
  final blocks = <(double, double, double)>[(-62.0, -416.0, 6.5), (26.0, -428.0, 6.5), (-44.0, -364.0, 15.0), (20.0, -368.0, 6.5)];
  for (var k = 0; k < 22; k++) {
    final a = 2 * math.pi * k / 22;
    blocks.add((-14 + math.cos(a) * 70, -398 + math.sin(a) * 64, 9.5));
  }
  final r = Raid(
    ground: field(blocks),
    pet: pet(-14, -380),
    sher: withSher ? sher(0, -370) : null,
    bossDef: const BossDef(x: -10, z: -432, ax: -14, az: -398, ar: 74, wall: [], summon: [(-50.0, -392.0), (30.0, -406.0), (-40.0, -438.0), (12.0, -438.0)]),
    level: 3,
    seed: seed,
    bossScale: bossScale,
  );
  if (withSher) r.join();
  return r;
}

void main() {
  const fern = [FoeSpawn('a', 'thornling', 'fern', -30, -10), FoeSpawn('b', 'thornling', 'fern', 4, 2)];
  const ring = [FoeSpawn('a', 'sporecap', 'ring', -16, -14), FoeSpawn('b', 'sporecap', 'ring', 22, 14)];
  const stand = [FoeSpawn('a', 'thornling', 'stand', -16, 16), FoeSpawn('b', 'thornling', 'stand', 18, -8), FoeSpawn('c', 'sporecap', 'stand', 2, -30)];

  for (final (name, spawns) in [('Fern Clearing', fern), ('Mushroom Ring', ring), ('Thorn Stand', stand)]) {
    test('$name: a decent player wins, and it costs something', () {
      final res = <Outcome>[];
      for (var seed = 1; seed <= 6; seed++) {
        res.add(fight(zone(spawns, seed), seed: seed));
      }
      final withSher = [for (var seed = 1; seed <= 6; seed++) fight(zone(spawns, seed, withSher: true), seed: seed)];
      // ignore: avoid_print
      print('$name solo:      ${res.join(' | ')}');
      // ignore: avoid_print
      print('$name with Sher: ${withSher.join(' | ')}');
      expect(res.where((o) => o.won).length, greaterThanOrEqualTo(5));
      expect(withSher.where((o) => o.won).length, 6);
      expect(res.map((o) => o.taken).reduce(math.max), greaterThan(5)); // they do bite
    });
  }

  test('the Briarback: winnable with Sher, harder alone, never quick', () {
    final duo = [for (var seed = 1; seed <= 5; seed++) fight(arena(seed, withSher: true), seed: seed, boss: true, limit: 300)];
    final solo = [for (var seed = 1; seed <= 5; seed++) fight(arena(seed), seed: seed, boss: true, limit: 300)];
    final sloppy = [for (var seed = 1; seed <= 5; seed++) fight(arena(seed, withSher: true), seed: seed, boss: true, limit: 300, skill: 0.45)];
    // ignore: avoid_print
    print('Briarback with Sher: ${duo.join(' | ')}');
    // ignore: avoid_print
    print('Briarback solo:      ${solo.join(' | ')}');
    // ignore: avoid_print
    print('Briarback sloppy:    ${sloppy.join(' | ')}');
    expect(duo.where((o) => o.won).length, greaterThanOrEqualTo(3));
    expect(duo.where((o) => o.won).every((o) => o.secs > 30), isTrue);
  });

  test('the Briarback alone, as players meet it now (Sher keeps the camp): winnable, still a fight', () {
    final solo = [for (var seed = 1; seed <= 5; seed++) fight(arena(seed, bossScale: 0.85), seed: seed, boss: true, limit: 300)];
    // ignore: avoid_print
    print('Briarback solo, eased: ${solo.join(' | ')}');
    expect(solo.where((o) => o.won).length, greaterThanOrEqualTo(4));
    expect(solo.where((o) => o.won).every((o) => o.secs > 30), isTrue);
  });

  test('the Briarback in the full-size arena: room to move, still won, not a slog', () {
    final solo = [for (var seed = 1; seed <= 5; seed++) fight(wideArena(seed), seed: seed, boss: true, limit: 300)];
    // ignore: avoid_print
    print('Briarback, wide arena: ${solo.join(' | ')}');
    expect(solo.where((o) => o.won).length, greaterThanOrEqualTo(4));
    expect(solo.where((o) => o.won).every((o) => o.secs > 30 && o.secs < 100), isTrue);
  });
}
