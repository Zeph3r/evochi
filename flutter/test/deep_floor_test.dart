import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:evochi/features/wilds/deep_floor.dart';
import 'package:flutter_test/flutter_test.dart';

RoomKit kit() => RoomKit((jsonDecode(File('assets/art/wilds/wilds_kit.json').readAsStringSync()) as Map).cast<String, dynamic>());

Map<String, double> radii() {
  final m = (jsonDecode(File('assets/art/wilds/wilds_map_thicket.json').readAsStringSync()) as Map).cast<String, dynamic>();
  return {for (final e in (m['images'] as Map).entries) e.key as String: ((e.value as Map)['radius'] as num? ?? 0).toDouble()};
}

/// Walk-grid cells reachable from (x, z), the trees' trunks counted as walls.
Set<int> reach(FloorPlan p, double x, double z) {
  bool blocked(int i, int k) {
    final cx = p.x0 + (i + 0.5) * p.cell, cz = p.z0 + (k + 0.5) * p.cell;
    // and its footprint has to be on walkable ground (as the fight checks it: 0.6 r across, 0.5 r deep)
    if (p.blocked(cx, cz) || p.blocked(cx + 5.4, cz) || p.blocked(cx - 5.4, cz) || p.blocked(cx, cz + 4.5) || p.blocked(cx, cz - 4.5)) return true;
    for (final (bx, bz, r) in p.blocks) {
      final dx = bx - cx, dz = bz - cz;
      // an Evochi's body (radius up to 12: an Elder) has to fit past the trunks
      if (dx * dx + dz * dz < (r + 12) * (r + 12)) return true;
    }
    return false;
  }

  final i0 = ((x - p.x0) / p.cell).floor(), k0 = ((z - p.z0) / p.cell).floor();
  final seen = <int>{k0 * p.cols + i0};
  final q = [(i0, k0)];
  while (q.isNotEmpty) {
    final (i, k) = q.removeLast();
    for (final (dx, dz) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final ni = i + dx, nk = k + dz;
      if (ni < 0 || nk < 0 || ni >= p.cols || nk >= p.rows) continue;
      final id = nk * p.cols + ni;
      if (seen.contains(id) || blocked(ni, nk)) continue;
      seen.add(id);
      q.add((ni, nk));
    }
  }
  return seen;
}

bool inReach(FloorPlan p, Set<int> r, double x, double z, [double slack = 12]) {
  for (var dz = -slack; dz <= slack; dz += p.cell) {
    for (var dx = -slack; dx <= slack; dx += p.cell) {
      final i = ((x + dx - p.x0) / p.cell).floor(), k = ((z + dz - p.z0) / p.cell).floor();
      if (r.contains(k * p.cols + i)) return true;
    }
  }
  return false;
}

void main() {
  final k = kit();
  final rd = radii();

  test('every chunk a floor can ask for is in the kit', () {
    for (var mask = 1; mask < 16; mask++) {
      expect(k.chunks.containsKey('room_${mask.toString().padLeft(2, '0')}'), isTrue);
      expect(k.chunks.containsKey('hall_${mask.toString().padLeft(2, '0')}'), isTrue);
    }
    expect(k.chunks.containsKey('fill'), isTrue);
  });

  test('a seed always makes the same floor', () {
    final a = planFloor(k, 4, 1234, rd), b = planFloor(k, 4, 1234, rd);
    expect(a.placed, b.placed);
    expect(a.props.length, b.props.length);
    expect(a.foes.map((f) => '${f['id']}@${f['x']},${f['z']}').toList(), b.foes.map((f) => '${f['id']}@${f['x']},${f['z']}').toList());
  });

  test('doorways agree: a room opening east has a neighbour opening west', () {
    for (var seed = 1; seed <= 60; seed++) {
      final p = planLayout(k, 2 + seed % 9, seed);
      final at = {for (final r in p.rooms) (r.gx, r.gz): r};
      for (final r in p.rooms) {
        for (final (bit, dx, dz, back) in const [(1, 0, -1, 4), (2, 1, 0, 8), (4, 0, 1, 1), (8, -1, 0, 2)]) {
          if (r.mask & bit == 0) continue;
          final n = at[(r.gx + dx, r.gz + dz)];
          expect(n, isNotNull, reason: 'seed $seed: a doorway into nothing');
          expect(n!.mask & back, isNot(0), reason: 'seed $seed: a one-way doorway');
        }
      }
    }
  });

  test('every floor can be walked: the start reaches every room, every creature and the doorway down', () {
    for (var seed = 1; seed <= 160; seed++) {
      final depth = 2 + seed % 13;
      final p = planFloor(k, depth, seed, rd);
      final r = reach(p, p.start.$1, p.start.$2);
      for (final room in p.rooms) {
        final (cx, cz) = p.centre(room);
        expect(inReach(p, r, cx, cz, 24), isTrue, reason: 'seed $seed F$depth: room ${room.role} at ${room.gx},${room.gz} cut off');
      }
      for (final f in p.foes) {
        expect(inReach(p, r, f['x'] as double, f['z'] as double), isTrue, reason: 'seed $seed: ${f['id']} out of reach');
      }
      final gate = p.spots.firstWhere((s) => s['kind'] == 'gate');
      expect(inReach(p, r, gate['x'] as double, gate['z'] as double, 20), isTrue, reason: 'seed $seed: the doorway down is out of reach');
      for (final s in p.spots) {
        expect(inReach(p, r, s['x'] as double, s['z'] as double, 24), isTrue, reason: 'seed $seed: ${s['id']} out of reach');
      }
    }
  });

  test('a mine floor: galleries of ore in reach instead of fights, nothing to calm, the shaft down and the way out', () {
    for (var seed = 1; seed <= 40; seed++) {
      final depth = 1 + seed % 4;
      final p = planFloor(k, depth, seed, {...rd, 'ore': 9.0}, mine: true);
      expect(p.mine, isTrue);
      expect(p.foes, isEmpty, reason: 'seed $seed: a working mine sets up no fights');
      expect(p.ores.length, greaterThanOrEqualTo(3), reason: 'seed $seed F$depth: a mine has ore');
      final kinds = {for (final o in p.ores) o['kind'] as String};
      if (depth == 1) expect(kinds.contains('copper'), isTrue);
      if (depth >= 3) expect(kinds.contains('lumen') || kinds.contains('obsidian'), isTrue, reason: 'seed $seed F$depth: the ladder climbs');
      final r = reach(p, p.start.$1, p.start.$2);
      for (final o in p.ores) {
        expect(inReach(p, r, o['x'] as double, o['z'] as double, 26), isTrue, reason: 'seed $seed: ${o['id']} out of reach');
      }
      for (final sp in p.spots) {
        expect(inReach(p, r, sp['x'] as double, sp['z'] as double, 24), isTrue, reason: 'seed $seed: ${sp['id']} out of reach');
      }
      expect(p.fx.any((f) => f['kind'] == 'lamp'), isTrue, reason: 'seed $seed: the galleries are lit');
    }
  });

  test('a floor\'s twists: none before F4, then one, two from F8, three from F12; the seed decides', () {
    for (var seed = 1; seed <= 40; seed++) {
      expect(floorMods(3, seed), isEmpty);
      expect(floorMods(4, seed).length, 1);
      expect(floorMods(8, seed).length, 2);
      expect(floorMods(13, seed).length, 3);
      expect(floorMods(9, seed), floorMods(9, seed));
      expect(floorMods(13, seed).toSet().length, 3);
      expect(floorMods(13, seed).every(floorModDefs.containsKey), isTrue);
    }
    // the fight's multiples
    final plain = floorFight(6, const []), hard = floorFight(6, const ['thick', 'fierce']), rich = floorFight(6, const ['lumen']);
    expect(hard.hp, greaterThan(plain.hp));
    expect(hard.harm, greaterThan(plain.harm));
    expect(rich.coins, greaterThan(plain.coins));
    expect(floorFight(6, const [], surge: true).hp, greaterThan(plain.hp));
  });

  test('a swarm brings more creatures to every clearing; spore season fills it with sporecaps', () {
    int most(FloorPlan p) {
      final per = <String, int>{};
      for (final f in p.foes) {
        if ((f['id'] as String).startsWith('f')) per[f['zone'] as String] = (per[f['zone'] as String] ?? 0) + 1;
      }
      return per.values.fold(0, math.max);
    }

    var swarms = 0, spores = 0, sporecaps = 0, all = 0;
    for (var seed = 1; seed <= 60; seed++) {
      final p = planFloor(k, 6, seed, rd);
      if (p.mods.contains('swarm')) {
        swarms++;
        expect(most(p), 4, reason: 'seed $seed');
      } else {
        expect(most(p), lessThanOrEqualTo(3), reason: 'seed $seed');
      }
      if (p.mods.contains('spores')) {
        spores++;
        for (final f in p.foes) {
          if ((f['id'] as String).startsWith('f')) {
            all++;
            if (f['kind'] == 'sporecap') sporecaps++;
          }
        }
      }
    }
    expect(swarms, greaterThan(0));
    expect(spores, greaterThan(0));
    expect(sporecaps / all, greaterThan(0.65));
  });

  test('a story floor: the Sentinel\'s Gate opens out round its guardian, and the way there can be walked', () {
    for (var seed = 1; seed <= 30; seed++) {
      final p = planFloor(k, 5, seed, rd, story: 'sentinel');
      expect(p.mods, isEmpty);
      expect(p.foes.any((f) => (f['id'] as String).startsWith('elite')), isFalse);
      final at = p.storyAt!;
      expect(p.blocked(at.$1, at.$2), isFalse);
      final r = reach(p, p.start.$1, p.start.$2);
      expect(inReach(p, r, at.$1, at.$2 + 40, 24), isTrue, reason: 'seed $seed: the Sentinel is cut off');
      // room to fight: open ground well round it, with cover across it
      final (ax, az) = sentinelArena;
      final (ecx, ecz) = p.centre(p.roomAt('exit'));
      var open = 0, all = 0;
      for (var a = 0.0; a < 6.28; a += 0.2) {
        for (final d in const [0.25, 0.4, 0.6, 0.8]) {
          all++;
          if (!p.blocked(ecx + math.cos(a) * ax * d, ecz + 4 + math.sin(a) * az * d)) open++;
        }
      }
      expect(open / all, greaterThan(0.8), reason: 'seed $seed');
      expect(p.props.where((q) => q['kind'] == 'pillar' || q['kind'] == 'pillar_low').length, greaterThan(10), reason: 'seed $seed');
    }
  });

  test('a story floor: the Mossy Ruins open out into a wide arena round the Hollow Sprout', () {
    for (var seed = 1; seed <= 30; seed++) {
      final p = planFloor(k, 3, seed, rd, story: 'sprout');
      final at = p.storyAt!;
      expect(p.blocked(at.$1, at.$2), isFalse);
      final r = reach(p, p.start.$1, p.start.$2);
      expect(inReach(p, r, at.$1, at.$2 + 40, 24), isTrue, reason: 'seed $seed: the Sprout is cut off');
      final (ax, az) = sproutArena;
      expect(ax, greaterThan(135)); // wider than Briarback's
      var open = 0, all = 0;
      for (var a = 0.0; a < 6.28; a += 0.2) {
        for (final d in const [0.25, 0.4, 0.6, 0.8]) {
          all++;
          if (!p.blocked(at.$1 + math.cos(a) * ax * d, at.$2 - 2 + math.sin(a) * az * d)) open++;
        }
      }
      expect(open / all, greaterThan(0.8), reason: 'seed $seed');
      expect(p.props.where((q) => q['kind'] == 'pillar' || q['kind'] == 'pillar_low').length, greaterThan(10), reason: 'seed $seed');
    }
  });

  test('deeper floors are bigger and busier, and from F3 an elite guards the way down', () {
    final shallow = planFloor(k, 2, 7, rd), deep = planFloor(k, 9, 7, rd);
    expect(deep.rooms.length, greaterThan(shallow.rooms.length));
    expect(deep.foes.length, greaterThan(shallow.foes.length));
    expect(shallow.foes.any((f) => (f['id'] as String).startsWith('elite')), isFalse);
    expect(deep.foes.any((f) => (f['id'] as String).startsWith('elite')), isTrue);
  });
}
