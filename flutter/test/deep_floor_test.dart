import 'dart:convert';
import 'dart:io';

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
      // an Evochi's body (radius 9) has to fit past the trunks
      if (dx * dx + dz * dz < (r + 9) * (r + 9)) return true;
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
    for (var seed = 1; seed <= 80; seed++) {
      final depth = 2 + seed % 9;
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

  test('deeper floors are bigger and busier, and from F3 an elite guards the way down', () {
    final shallow = planFloor(k, 2, 7, rd), deep = planFloor(k, 9, 7, rd);
    expect(deep.rooms.length, greaterThan(shallow.rooms.length));
    expect(deep.foes.length, greaterThan(shallow.foes.length));
    expect(shallow.foes.any((f) => (f['id'] as String).startsWith('elite')), isFalse);
    expect(deep.foes.any((f) => (f['id'] as String).startsWith('elite')), isTrue);
  });
}
