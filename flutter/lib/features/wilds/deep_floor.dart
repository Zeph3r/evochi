// The Deep Wilds: below the Sunlit Thicket, Fernwood Trail goes down floor after floor, and every floor is
// made fresh from the room kit (tools/art/wilds_kit.py) when you arrive.
//
// A floor is a small grid of cells. A winding main way runs from where you arrive (a room on the bottom
// row) to the old doorway down to the next floor (a room near the top, its doorway sealed until the floor
// is calmed), with a branch or two off it to a treasure nook, a shrine or a camp. Each cell is a chunk of
// pre-rendered forest floor (a clearing or a narrow way, paths out to the doorways it opens on); the
// rest of the grid, and a ring round it, is plain forest floor. The forest is grown at runtime over
// everything you cannot walk on, so every floor looks like the Thicket's wood.
//
// Everything here is decided by the floor's seed, so a seed always makes the same floor (a daily floor
// everyone shares is just a seed from the date). The plan is pure data and testable without pictures;
// [makeFloor] then loads the pictures and turns the plan into a [WildsMap] the Wilds screen plays like
// the Thicket.
//
// Deeper floors are bigger, with more creatures in each room, and from F3 a tough elite guards the way
// to the doorway down.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'wilds_art.dart';

const deepTrail = 'Fernwood Trail';

/// The floor numbers: the Thicket is F1, the Deep Wilds start at F2.
const firstDeepFloor = 2;

// ------------------------------------------------------------------------------------- the kit
class KitChunk {
  KitChunk(Map<String, dynamic> j)
      : id = '',
        image = j['image'] as String,
        kind = j['kind'] as String,
        mask = (j['mask'] as num).toInt(),
        r = (j['r'] as num).toDouble(),
        clear = [for (final p in j['clear'] as List) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
        paths = [
          for (final l in j['paths'] as List) [for (final p in l as List) Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble())],
        ];
  final String id, image, kind;
  final int mask; // doorways: 1 N, 2 E, 4 S, 8 W
  final double r;
  final List<Offset> clear; // the clearing's outline (chunk units)
  final List<List<Offset>> paths;
}

class RoomKit {
  RoomKit(Map<String, dynamic> j)
      : chunk = (j['chunk'] as num).toDouble(),
        scale = (j['scale'] as num).toDouble(),
        pitch = (j['pitch'] as num).toDouble(),
        chunks = {for (final e in (j['chunks'] as Map).entries) e.key as String: KitChunk((e.value as Map).cast<String, dynamic>())};
  final double chunk, scale, pitch;
  final Map<String, KitChunk> chunks;

  static RoomKit? _cached;
  static Future<RoomKit> load() async =>
      _cached ??= RoomKit((jsonDecode(await rootBundle.loadString('${wildsBase}wilds_kit.json')) as Map).cast<String, dynamic>());
}

// ------------------------------------------------------------------------------------- the plan
const _dn = 1, _de = 2, _ds = 4, _dw = 8;

class FloorRoom {
  FloorRoom(this.i, this.gx, this.gz, this.role);
  final int i, gx, gz;
  String role; // start | way | fight | elite | exit | treasure | shrine | camp
  int mask = 0;
  bool get hall => role == 'way';
}

class FloorPlan {
  FloorPlan(this.depth, this.seed, this.gw, this.gh, this.chunk);
  final int depth, seed, gw, gh;
  final double chunk;
  final rooms = <FloorRoom>[];
  final placed = <(String, double, double)>[]; // chunk id, world x0, z0
  final props = <Map<String, Object>>[];
  final blocks = <(double, double, double)>[];
  final shade = <(double, double, double)>[]; // canopy shadows: x, z, r
  final zones = <Map<String, Object>>[];
  final foes = <Map<String, Object>>[];
  final spots = <Map<String, Object>>[];
  final fx = <Map<String, Object>>[];
  late Uint8List grid; // walkable bits, 1 = blocked
  late int cols, rows;
  late double cell, x0, z0;
  late (double, double) start, gate;

  Rect get bounds => Rect.fromLTRB(x0 + 4, z0 + 4, x0 + cols * cell - 4, z0 + rows * cell - 4);
  bool blocked(double x, double z) {
    final i = ((x - x0) / cell).floor(), k = ((z - z0) / cell).floor();
    if (i < 0 || k < 0 || i >= cols || k >= rows) return true;
    final bit = k * cols + i;
    return (grid[bit >> 3] >> (7 - (bit & 7))) & 1 == 1;
  }

  FloorRoom roomAt(String role) => rooms.firstWhere((r) => r.role == role);
  (double, double) centre(FloorRoom r) => (r.gx * chunk + chunk / 2, r.gz * chunk + chunk / 2);
}

class _Rng {
  _Rng(int seed) : r = math.Random(seed);
  final math.Random r;
  double d([double a = 0, double b = 1]) => a + r.nextDouble() * (b - a);
  int i(int n) => r.nextInt(n);
  bool p(double chance) => r.nextDouble() < chance;
  T pick<T>(List<T> l) => l[r.nextInt(l.length)];
}

int _dir(int dx, int dz) => dz < 0 ? _dn : (dx > 0 ? _de : (dz > 0 ? _ds : _dw));

/// The floor's shape: the main way, the branches, each cell's role and doorways.
FloorPlan planLayout(RoomKit kit, int depth, int seed) {
  final big = depth >= 6;
  final gw = big ? 5 : 4, gh = big ? 6 : 5;
  final want = (5 + depth ~/ 2).clamp(5, big ? 11 : 9);
  for (var attempt = 0; attempt < 400; attempt++) {
    final rng = _Rng(seed * 977 + attempt);
    final plan = FloorPlan(depth, seed, gw, gh, kit.chunk);
    final taken = <(int, int)>{};
    final path = <(int, int)>[(rng.i(gw), gh - 1)];
    taken.add(path.first);
    // a random walk that likes going north and never crosses itself; back up when it is stuck
    var guard = 0;
    while (path.length < want && path.isNotEmpty && guard++ < 400) {
      final (x, z) = path.last;
      final opts = <((int, int), double)>[];
      for (final (dx, dz, w) in const [(0, -1, 2.4), (1, 0, 1.0), (-1, 0, 1.0), (0, 1, 0.35)]) {
        final n = (x + dx, z + dz);
        if (n.$1 < 0 || n.$2 < 0 || n.$1 >= gw || n.$2 >= gh || taken.contains(n)) continue;
        opts.add((n, w));
      }
      if (opts.isEmpty) {
        path.removeLast();
        continue;
      }
      var t = rng.d(0, opts.fold(0.0, (a, o) => a + o.$2));
      var next = opts.last.$1;
      for (final o in opts) {
        t -= o.$2;
        if (t <= 0) {
          next = o.$1;
          break;
        }
      }
      path.add(next);
      taken.add(next);
    }
    if (path.length < want) continue;
    // the doorway down stands on the north side of the last room: it must not have come down into it
    final (lx, lz) = path.last;
    final (_, pz) = path[path.length - 2];
    if (pz < lz) continue;
    if (lz > gh - 2) continue; // and the way should climb
    final rooms = <(int, int), FloorRoom>{};
    for (var i = 0; i < path.length; i++) {
      rooms[path[i]] = FloorRoom(i, path[i].$1, path[i].$2, i == 0 ? 'start' : (i == path.length - 1 ? 'exit' : 'fight'));
    }
    void link((int, int) a, (int, int) b) {
      rooms[a]!.mask |= _dir(b.$1 - a.$1, b.$2 - a.$2);
      rooms[b]!.mask |= _dir(a.$1 - b.$1, a.$2 - b.$2);
    }

    for (var i = 1; i < path.length; i++) {
      link(path[i - 1], path[i]);
    }
    // the elite guards the last stretch; between fights, some cells are just narrow ways
    if (depth >= 3) rooms[path[path.length - 2]]!.role = 'elite';
    for (var i = 1; i < path.length - 2; i++) {
      if (i.isEven && rng.p(0.55)) rooms[path[i]]!.role = 'way';
    }
    // branches off the main way: a treasure nook, then a shrine, then (deep down) a camp
    final ends = ['treasure', if (depth >= 3) 'shrine', if (depth >= 5) 'camp'];
    var made = 0;
    for (final role in ends) {
      for (var tries = 0; tries < 30; tries++) {
        final from = path[1 + rng.i(path.length - 3)];
        final dirs = [(0, -1), (1, 0), (-1, 0), (0, 1)]..shuffle(rng.r);
        (int, int)? got;
        for (final (dx, dz) in dirs) {
          final n = (from.$1 + dx, from.$2 + dz);
          if (n.$1 < 0 || n.$2 < 0 || n.$1 >= gw || n.$2 >= gh || rooms.containsKey(n)) continue;
          // the room north of the doorway down stays empty (nothing walks into the seal's back)
          if (n == (lx, lz - 1)) continue;
          got = n;
          break;
        }
        if (got == null) continue;
        rooms[got] = FloorRoom(rooms.length, got.$1, got.$2, role);
        link(from, got);
        made++;
        break;
      }
    }
    if (made < ends.length - 1) continue;
    plan.rooms.addAll(rooms.values);
    return plan;
  }
  throw StateError('no floor layout for seed $seed');
}

// smooth noise for picking tree species in stands
double _vnoise(double x, double z, int seed) {
  double h(int i, int k) {
    final v = math.sin(i * 127.1 + k * 311.7 + seed * 74.7) * 43758.5453;
    return v - v.floorToDouble();
  }

  final i = x.floor(), k = z.floor();
  final fx = x - i, fz = z - k;
  final sx = fx * fx * (3 - 2 * fx), sz = fz * fz * (3 - 2 * fz);
  final a = h(i, k) + (h(i + 1, k) - h(i, k)) * sx;
  final b = h(i, k + 1) + (h(i + 1, k + 1) - h(i, k + 1)) * sx;
  return a + (b - a) * sz;
}

bool _inPoly(List<Offset> poly, double x, double z) {
  var inside = false;
  for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    final a = poly[i], b = poly[j];
    if ((a.dy > z) != (b.dy > z) && x < (b.dx - a.dx) * (z - a.dy) / (b.dy - a.dy) + a.dx) inside = !inside;
  }
  return inside;
}

double _segDist(Offset a, Offset b, double x, double z) {
  final dx = b.dx - a.dx, dz = b.dy - a.dy;
  final l2 = math.max(dx * dx + dz * dz, 1e-9);
  final t = (((x - a.dx) * dx + (z - a.dy) * dz) / l2).clamp(0.0, 1.0);
  final px = a.dx + t * dx - x, pz = a.dy + t * dz - z;
  return math.sqrt(px * px + pz * pz);
}

/// The whole floor: the layout, then where you can walk, the forest, the creatures, the spots.
/// [radii] gives each prop kind's trunk (footprint) radius.
FloorPlan planFloor(RoomKit kit, int depth, int seed, Map<String, double> radii) {
  final plan = planLayout(kit, depth, seed);
  final rng = _Rng(seed * 31 + 7);
  final C = kit.chunk;
  final gw = plan.gw, gh = plan.gh;
  // the chunks: each room's, and plain forest everywhere else (a ring round the floor too)
  final byCell = {for (final r in plan.rooms) (r.gx, r.gz): r};
  for (var gz = -1; gz <= gh; gz++) {
    for (var gx = -1; gx <= gw; gx++) {
      final r = byCell[(gx, gz)];
      final id = r == null ? 'fill' : '${r.hall ? 'hall' : 'room'}_${r.mask.toString().padLeft(2, '0')}';
      plan.placed.add((kit.chunks.containsKey(id) ? id : 'fill', gx * C, gz * C));
    }
  }
  // where you can walk: the clearings (a little inside their edge) and a lane along every path
  plan.cell = 4;
  plan.x0 = -C;
  plan.z0 = -C;
  plan.cols = ((gw + 2) * C / plan.cell).round();
  plan.rows = ((gh + 2) * C / plan.cell).round();
  final walk = Uint8List(plan.cols * plan.rows); // 1 = walkable
  // wide enough for an Evochi (radius up to 12) to walk with trees either side; the dirt path runs down
  // the middle of it
  const lane = 32.0;
  for (final r in plan.rooms) {
    final k = kit.chunks['${r.hall ? 'hall' : 'room'}_${r.mask.toString().padLeft(2, '0')}']!;
    final ox = r.gx * C, oz = r.gz * C;
    final ci0 = ((ox - plan.x0) / plan.cell).floor(), ck0 = ((oz - plan.z0) / plan.cell).floor();
    final n = (C / plan.cell).round();
    final cx = C / 2, cz = C / 2;
    for (var dk = 0; dk < n; dk++) {
      for (var di = 0; di < n; di++) {
        final u = (di + 0.5) * plan.cell, v = (dk + 0.5) * plan.cell;
        var ok = false;
        if (k.clear.isNotEmpty) {
          // a little inside the clearing's edge: pull the point outward and test it
          final du = u - cx, dv = v - cz;
          final d = math.max(math.sqrt(du * du + dv * dv), 1e-6);
          ok = _inPoly(k.clear, u + du / d * 6, v + dv / d * 6);
        }
        if (!ok) {
          for (final p in k.paths) {
            for (var s = 1; s < p.length && !ok; s++) {
              if (_segDist(p[s - 1], p[s], u, v) < lane / 2) ok = true;
            }
            if (ok) break;
          }
        }
        if (ok) walk[(ck0 + dk) * plan.cols + ci0 + di] = 1;
      }
    }
  }
  // distance (in cells) from every cell to the nearest walkable one: where trees may stand, and how near
  final far = List<int>.filled(plan.cols * plan.rows, 1 << 20);
  final q = <int>[];
  for (var i = 0; i < walk.length; i++) {
    if (walk[i] == 1) {
      far[i] = 0;
      q.add(i);
    }
  }
  for (var h = 0; h < q.length; h++) {
    final c = q[h];
    final ci = c % plan.cols, ck = c ~/ plan.cols;
    for (final (dx, dz) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final ni = ci + dx, nk = ck + dz;
      if (ni < 0 || nk < 0 || ni >= plan.cols || nk >= plan.rows) continue;
      final n = nk * plan.cols + ni;
      if (far[n] > far[c] + 1) {
        far[n] = far[c] + 1;
        q.add(n);
      }
    }
  }
  int farAt(double x, double z) {
    final i = ((x - plan.x0) / plan.cell).floor(), k = ((z - plan.z0) / plan.cell).floor();
    if (i < 0 || k < 0 || i >= plan.cols || k >= plan.rows) return 1 << 20;
    return far[k * plan.cols + i];
  }

  // is there walkable ground just north of here? (a tall tree there would stand in front of the play)
  bool shadeBand(double x, double z) {
    for (var d = 6.0; d <= 52; d += 6) {
      if (farAt(x, z - d) == 0) return true;
    }
    return false;
  }

  void add(String kind, double x, double z, {double s = 1, bool? flip}) {
    plan.props.add({'kind': kind, 'x': (x * 10).round() / 10, 'z': (z * 10).round() / 10, 'flip': flip ?? rng.p(0.5), 's': (s * 100).round() / 100});
    final r = (radii[kind] ?? 0) * s;
    if (r > 0) plan.blocks.add((x, z, r));
  }

  // the walk grid's blocked bits (trees block through the fight's own blocks, not the grid)
  final bits = Uint8List((plan.cols * plan.rows + 7) >> 3);
  for (var i = 0; i < walk.length; i++) {
    if (walk[i] == 0) bits[i >> 3] |= 1 << (7 - (i & 7));
  }
  plan.grid = bits;
  // ---- the forest: trees in stands (a smooth field picks the species), the edge of the walkable ground
  // lined thick; low things only where a tree would hide the way north of it
  const pines = ['pine_a', 'pine_b', 'pine_c'], oaks = ['oak_a', 'oak_b', 'oak_c'], birches = ['birch', 'birch_b'];
  final step = 17.0;
  for (var z = plan.z0 + 6; z < plan.z0 + plan.rows * plan.cell - 6; z += step) {
    for (var x = plan.x0 + 6; x < plan.x0 + plan.cols * plan.cell - 6; x += step) {
      final px = x + rng.d(-6, 6), pz = z + rng.d(-6, 6);
      final f = farAt(px, pz) * plan.cell;
      if (f < 8) continue;
      if (shadeBand(px, pz)) {
        // low growth only, and not too much of it
        if (f < 30 && rng.p(0.42)) add(rng.pick(const ['bush', 'bush_b', 'bush', 'rock', 'stump', 'shrooms']), px, pz, s: rng.d(0.85, 1.1));
        continue;
      }
      if (f > 150 && rng.p(0.35)) continue; // deep in the wood: you only glimpse it
      final sp = _vnoise(px / 140, pz / 140, seed);
      final kinds = sp < 0.38 ? pines : (sp < 0.72 ? oaks : birches);
      final kind = rng.p(0.04) ? 'oak_old' : rng.pick(kinds);
      final s = rng.d(0.88, 1.12);
      add(kind, px, pz, s: s);
      plan.shade.add((px + 3, pz + 2, 16 * s));
    }
  }
  // ---- the rooms
  final wantFoes = 2 + (depth >= 4 ? 1 : 0) + (depth >= 7 ? 1 : 0);
  for (final r in plan.rooms) {
    final (cx, cz) = plan.centre(r);
    final k = kit.chunks['${r.hall ? 'hall' : 'room'}_${r.mask.toString().padLeft(2, '0')}']!;
    final rr = k.r;
    // a little life round the clearing's rim
    if (!r.hall) {
      for (var i = 0; i < 4; i++) {
        final a = rng.d(0, math.pi * 2);
        final x = cx + math.cos(a) * (rr - 4), z = cz + math.sin(a) * (rr - 4) * 0.95;
        if (farAt(x, z) == 0 && !_nearPath(k, x - r.gx * C, z - r.gz * C, 16)) {
          add(rng.pick(const ['shrooms', 'rock', 'bush_b']), x, z, s: rng.d(0.8, 1.0));
        }
      }
    }
    switch (r.role) {
      case 'start':
        plan.start = (cx, cz + rr * 0.45);
        add('sign', cx + 26, cz + rr * 0.3, flip: false);
        plan.spots.add({
          'id': 'sign', 'kind': 'read', 'x': cx + 26, 'z': cz + rr * 0.3 + 6, 'r': 20, 'label': 'Read', 'title': 'F$depth · $deepTrail',
          'text': depth == firstDeepFloor
              ? 'F$depth · $deepTrail. Past the Thicket the old trail winds down through deeper wood. Each floor ends at an old doorway down, sealed until the floor is calm.'
              : 'F$depth · $deepTrail. Deeper still. The Hollow is thicker down here.',
        });
        plan.spots.add({
          'id': 'exit', 'kind': 'exit', 'x': cx, 'z': cz + rr * 0.85, 'r': 22, 'label': 'Leave', 'title': 'Back up the trail',
          'text': 'Climb back up to the Thicket and the village? You take home what you have found.',
        });
      case 'exit':
        // the old doorway down: a ruin gate on the north side of the clearing, sealed with Lumen beams
        final gz = cz - rr * 0.62;
        add('gate', cx, gz, flip: false);
        for (final (dx, s) in const [(-40.0, 'pillar'), (44.0, 'pillar_low')]) {
          add(s, cx + dx, gz + 18, flip: false);
        }
        plan.gate = (cx, gz);
        plan.spots.add({
          'id': 'gate', 'kind': 'gate', 'x': cx, 'z': gz + 14, 'r': 30, 'label': 'Descend', 'title': 'F${depth + 1} · $deepTrail',
          'text': 'Worn steps lead down through the old doorway, deeper into the Wilds.',
        });
        _foes(plan, rng, r, cx, cz, rr * 0.55, wantFoes, depth);
      case 'fight':
        _foes(plan, rng, r, cx, cz, rr * 0.55, wantFoes, depth);
      case 'elite':
        // ruins to fight round, and something big
        for (var i = 0; i < 3; i++) {
          final a = i * 2.1 + rng.d(0, 0.6);
          final x = cx + math.cos(a) * rr * 0.55, z = cz + math.sin(a) * rr * 0.5;
          if (!_nearPath(k, x - r.gx * C, z - r.gz * C, 14)) add(i == 1 ? 'pillar' : 'pillar_low', x, z, flip: false);
        }
        _foes(plan, rng, r, cx, cz, rr * 0.5, wantFoes - 1, depth, elite: true);
      case 'treasure':
        add('chest', cx, cz - 6, flip: false);
        plan.spots.add({
          'id': 'chest_${r.i}', 'kind': 'chest', 'x': cx, 'z': cz - 2, 'r': 20, 'label': 'Open', 'title': 'An old chest',
          'text': 'Moss on the lid, a little light leaking out of the seam.',
        });
        if (depth >= 4) _foes(plan, rng, r, cx, cz, rr * 0.5, 2, depth);
      case 'shrine':
        add('pillar_low', cx, cz - 8, flip: false);
        plan.fx.add({'kind': 'shrine', 'x': cx, 'z': cz - 8});
        plan.spots.add({
          'id': 'shrine_${r.i}', 'kind': 'shrine', 'x': cx, 'z': cz, 'r': 20, 'label': 'Pray', 'title': 'A Lumen shrine',
          'text': 'An old stone, still warm with Lumen. It offers a blessing for this floor.',
        });
      case 'camp':
        add('tent', cx - 22, cz - 14, flip: false);
        add('seat', cx + 20, cz + 6, flip: false);
        plan.fx.add({'kind': 'fire', 'x': cx, 'z': cz});
        plan.spots.add({
          'id': 'camp_${r.i}', 'kind': 'camp', 'x': cx, 'z': cz + 10, 'r': 22, 'label': 'Rest', 'title': 'A quiet camp',
          'text': 'Someone left a fire burning low. Rest a moment: your Raid HP comes back.',
        });
    }
    if (const {'fight', 'elite', 'exit', 'treasure'}.contains(r.role)) {
      plan.zones.add({'id': 'r${r.i}', 'name': r.role == 'elite' ? 'Elite\'s Hollow' : 'Clearing', 'x': cx, 'z': cz, 'r': rr});
    }
  }
  return plan;
}

bool _nearPath(KitChunk k, double u, double v, double d) {
  for (final p in k.paths) {
    for (var s = 1; s < p.length; s++) {
      if (_segDist(p[s - 1], p[s], u, v) < d) return true;
    }
  }
  return false;
}

void _foes(FloorPlan plan, _Rng rng, FloorRoom r, double cx, double cz, double spread, int n, int depth, {bool elite = false}) {
  for (var i = 0; i < n + (elite ? 1 : 0); i++) {
    for (var tries = 0; tries < 20; tries++) {
      final a = rng.d(0, math.pi * 2), d = rng.d(0, spread);
      final x = cx + math.cos(a) * d, z = cz + math.sin(a) * d * 0.9;
      if (plan.blocked(x, z)) continue;
      final big = elite && i == 0;
      final kind = big ? 'thornling' : (rng.p(depth >= 3 ? 0.45 : 0.35) ? 'sporecap' : 'thornling');
      plan.foes.add({'id': '${big ? 'elite' : 'f'}_${r.i}_$i', 'kind': kind, 'zone': 'r${r.i}', 'x': x, 'z': z});
      break;
    }
  }
}

// ------------------------------------------------------------------------------------- the map
/// Loads the pictures and makes the floor's [WildsMap]. Props come from the Thicket's sprites.
Future<WildsMap> makeFloor(int depth, int seed) async {
  final kit = await RoomKit.load();
  final thicket = (jsonDecode(await rootBundle.loadString('${wildsBase}wilds_map_thicket.json')) as Map).cast<String, dynamic>();
  final images = (thicket['images'] as Map).cast<String, dynamic>();
  final radii = {for (final e in images.entries) e.key: ((e.value as Map)['radius'] as num? ?? 0).toDouble()};
  radii['gate'] = 0; // its footprint is its own shape (below)
  radii['chest'] = 6;
  final plan = planFloor(kit, depth, seed, radii);
  // the gate's footprint: its pillars and the sealed opening (as in tools/art/wilds_maps.py SHAPES)
  final (gx, gz) = plan.gate;
  for (final (dx, dz, r) in const [(-30.0, 0.0, 11.0), (30.0, 0.0, 11.0), (-16.0, 0.0, 3.5), (-8.0, 0.0, 3.5), (0.0, 0.0, 3.5), (8.0, 0.0, 3.5), (16.0, 0.0, 3.5), (42.0, 8.0, 6.0)]) {
    plan.blocks.add((gx + dx, gz + dz, r));
  }
  final s = kit.scale, sinP = math.sin(kit.pitch * math.pi / 180);
  final C = kit.chunk;
  // ground pixels: world (x, z) lands at origin + (x, z * sinP) * scale
  final origin = Offset(-plan.x0 * s, -plan.z0 * s * sinP + 12);
  final gw = plan.cols * plan.cell * s, gh = plan.rows * plan.cell * s * sinP + 24;
  final chunkImg = <String, ui.Image>{};
  for (final (id, _, _) in plan.placed) {
    chunkImg[id] ??= await _image(wildsBase + kit.chunks[id]!.image);
  }
  final tiles = [
    for (final (id, x, z) in plan.placed)
      GroundTile(chunkImg[id]!, Rect.fromLTWH(origin.dx + x * s, origin.dy + z * s * sinP, C * s, C * s * sinP)),
  ];
  final kinds = {for (final p in plan.props) p['kind'] as String};
  final propArt = <String, PropArt>{};
  for (final k in kinds) {
    if (k == 'chest') {
      final img = await _image('assets/art/economy/chest_wood_closed.webp');
      // the chest art is a UI picture: stand it on its base, about 16 units wide
      propArt[k] = PropArt(img, img.width / 2, img.height * 0.92, img.width / 16);
      continue;
    }
    final p = (images[k] as Map?)?.cast<String, dynamic>();
    if (p == null) continue;
    final a = p['anchor'] as List;
    propArt[k] = PropArt(await _image(wildsBase + (p['image'] as String)), (a[0] as num).toDouble(), (a[1] as num).toDouble(),
        (p['scale'] as num? ?? s).toDouble(), p['mask'] == null ? null : await _image(wildsBase + (p['mask'] as String)));
  }
  final j = <String, dynamic>{
    'id': 'deep_$depth',
    'name': deepTrail,
    'floor': 'F$depth',
    'level': 2 + depth,
    'pitch': kit.pitch,
    'scale': s,
    'objective': 'Calm the floor and find the way down',
    'ground': {'w': gw, 'h': gh, 'origin': [origin.dx, origin.dy], 'scale': s},
    'bounds': [plan.bounds.left, plan.bounds.top, plan.bounds.right, plan.bounds.bottom],
    'grid': {'cell': plan.cell, 'x0': plan.x0, 'z0': plan.z0, 'cols': plan.cols, 'rows': plan.rows, 'blocked': base64Encode(plan.grid)},
    'start': {'x': plan.start.$1, 'z': plan.start.$2, 'dir': 'N'},
    'fx': plan.fx,
    'zones': plan.zones,
    'foes': plan.foes,
    'gate': {'x': gx, 'z': gz, 'emit': 21.0, 'beams': [14.0, 26.0, 38.0]},
    'deep': {'depth': depth, 'seed': seed},
  };
  return WildsMap.made(
    j,
    tiles: tiles,
    propArt: propArt,
    props: [for (final p in plan.props) MapProp(p['kind'] as String, p['x'] as double, p['z'] as double, p['flip'] as bool, p['s'] as double)],
    blocks: plan.blocks,
    spots: [for (final sp in plan.spots) MapSpot(sp)],
    minimap: await _minimap(plan),
    grid: plan.grid,
    shade: plan.shade,
  );
}

Future<ui.Image> _image(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

/// The floor from above for the minimap: forest, the walkable ground, the rooms' marks.
Future<ui.Image> _minimap(FloorPlan plan) async {
  const px = 2.0; // per walk cell
  final w = (plan.cols * px).round(), h = (plan.rows * px).round();
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  c.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFF26401E));
  final ground = Paint()..color = const Color(0xFF9BC46A);
  for (var k = 0; k < plan.rows; k++) {
    for (var i = 0; i < plan.cols; i++) {
      final bit = k * plan.cols + i;
      if ((plan.grid[bit >> 3] >> (7 - (bit & 7))) & 1 == 0) c.drawRect(Rect.fromLTWH(i * px, k * px, px, px), ground);
    }
  }
  return rec.endRecording().toImage(w, h);
}
