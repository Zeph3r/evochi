// The walkable maps: the Sunlit Village, and the Old Trail east of it to the Crossing.
//
// The whole village pictured at the walking camera's detail (tools/art/village_walk_pack.py), in
// 1024 px tiles loaded as you walk, drawn through shaders/village_fx.frag so it lives like the other
// scenes (water, trees, grass, smoke, glows, leaves and motes); a walk grid with the height you stand
// at; your Evochi walking where you tap, drawn 1.2x its true size with the sun's shadow; and the
// villagers outside in the classic look (Pip and Alder by the Guild's bridge, Bram at his Workshop,
// Mira at her Glasshouse). Tap one and your Evochi walks over, turns to them, and the conversation
// opens. No labels on the buildings: a name shows when you walk up, a "!" marks who has something for
// you. The road home leaves south through the gate; the Old Trail leaves east, and is a map of its own
// (the same screen with tools/art/village_trail.py's picture): a ledge under autumn cliffs, the bridge by
// the waterfall, and Flint at the Crossing beside the mine. Walk off one map's edge onto the next.
//
// Depth: the picture knows the world z of what each pixel shows (and whether it stands up off the
// ground). After each character is drawn, the picture is drawn again over it, only where something
// stands nearer the camera than its feet (a wall, a trunk, a post, the Waystone).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/game_state.dart';
import '../../game/hatch/hatch.dart' as hatch;
import '../../game/mining/mining.dart' as mine;
import '../../game/story/story.dart' as q;
import '../shared/ambience.dart';
import '../shared/live_scene.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../home/companions_sheet.dart';
import '../home/home_widgets.dart' show goHome, openCottage, openGarden, openSkills, openStation;
import '../home/nook_sheet.dart';
import '../wilds/wilds_art.dart';
import '../wilds/wilds_screen.dart';
import 'chathead_talk.dart';
import 'flint_talk.dart';
import 'forge_minigame.dart';
import 'mining.dart';
import 'mining_gear_ui.dart';
import '../trails/trails_widgets.dart' show openPrep;
import 'story_widgets.dart';
import 'village_screen.dart';

String _layoutAsset(String map) => 'assets/config/${map}_walk.json';
const _evochiH = 3.4 * 1.45; // world units: an Elder, drawn 1.45x in the village (it is the hero of the picture) (the Wilds keep theirs)
const _sheetH = 202.0; // an Elder's height on its walk sheet, px
const _npcH = {'pip': 3.4, 'alder': 3.8, 'bram': 4.0, 'mira': 4.2}; // world units (Flint's comes with his art)
const _npcName = {'pip': 'Pip', 'alder': 'Alder', 'bram': 'Bram', 'mira': 'Mira', 'flint': 'Flint'};
const _unitsAcross = 25.0; // the walking camera: 25 world units across the screen (zoomed back from 18)
const _npcRing = [Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1), Offset(0.7, 0.7), Offset(-0.7, 0.7), Offset(0.7, -0.7), Offset(-0.7, -0.7)];
final _npcInk = Paint()
  ..filterQuality = FilterQuality.medium
  ..colorFilter = const ColorFilter.mode(Color(0x8C3B2416), BlendMode.srcIn);
final _npcPop = Paint()
  ..filterQuality = FilterQuality.medium
  ..colorFilter = const ColorFilter.matrix([1.1602, -0.0909, -0.0092, 0, -7.68, -0.0270, 1.0963, -0.0092, 0, -7.68, -0.0270, -0.0909, 1.1780, 0, -7.68, 0, 0, 0, 1, 0]);
const _speed = 5.6; // walking, world units a second
const _runSpeed = 10.5; // running: any way longer than [_runFrom] is run, and the last [_walkIn] walked
const _runFrom = 7.0, _walkIn = 3.6;
const _frontBias = 1.0; // world units: what is this much nearer than a character's feet covers it (half a body)
const _shadowLong = 2.0; // characters' shadows drawn this much longer than the sun makes them

/// Open the walkable village (the preview).
void openVillageWalk(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Ambience('village', child: VillageWalkScreen())));

/// From one map to the next: this screen gives way to the other map's, arriving by [at].
Route<void> _mapRoute(String map, String? at) => PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 450),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => Ambience(switch (map) { 'home' => 'home', 'cottage' => 'kitchen', 'lodge' || 'glasshouse' || 'workshop' => villagePlace(map), _ => 'village' },
          child: VillageWalkScreen(map: map, arrive: at)),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeInOut), child: child),
    );

/// Someone standing on a map: where, the place their conversation opens in, and (for those who aren't
/// villagers, like Flint) their own sprite: its file, the point under their feet, the top of their head,
/// and their height in world units.
class WalkNpc {
  WalkNpc(Map j)
      : id = j['id'] as String,
        x = (j['x'] as num).toDouble(),
        z = (j['z'] as num).toDouble(),
        place = j['place'] as String,
        art = j['art'] as String?,
        ground = j['ground'] == null ? null : Offset(((j['ground'] as List)[0] as num).toDouble(), ((j['ground'] as List)[1] as num).toDouble()),
        top = j['top'] == null ? null : Offset(((j['top'] as List)[0] as num).toDouble(), ((j['top'] as List)[1] as num).toDouble()),
        height = (j['height'] as num?)?.toDouble();
  final String id, place;
  final double x, z;
  final String? art;
  final Offset? ground, top;
  final double? height;
}

/// A walkable map: its picture, camera and walk grid (assets/config/<map>_walk.json).
class WalkLayout {
  WalkLayout(Map<String, dynamic> j)
      : map = (j['map'] as String?) ?? 'village',
        title = (j['title'] as String?) ?? 'Sunlit Village',
        tileDir = (j['tiles'] as Map)['dir'] as String,
        tiles = [
          for (final t in ((j['tiles'] as Map)['list'] as List).cast<Map>())
            WalkTile(
              t['i'] as int,
              t['j'] as int,
              Rect.fromLTWH((t['x'] as num).toDouble(), (t['y'] as num).toDouble(), (t['w'] as num).toDouble(), (t['h'] as num).toDouble()),
              Rect.fromLTWH(((t['core'] as List)[0] as num).toDouble(), ((t['core'] as List)[1] as num).toDouble(), ((t['core'] as List)[2] as num).toDouble(),
                  ((t['core'] as List)[3] as num).toDouble()),
            )
        ],
        emit = (j['emit'] as List?) ?? const [],
        exits = {
          for (final e in ((j['exits'] as Map?) ?? const {}).entries)
            e.key as String: (
              ((e.value as List)[0] as num).toDouble(),
              ((e.value as List)[1] as num).toDouble(),
              ((e.value as List)[2] as num).toDouble(),
              (e.value as List).length > 3 ? (e.value as List)[3] as String? : null,
              (e.value as List).length > 4 ? (e.value as List)[4] as String? : null,
            )
        },
        w = (j['w'] as num).toDouble(),
        h = (j['h'] as num).toDouble(),
        ppu = (j['ppu'] as num).toDouble(),
        cx = ((j['centre'] as List)[0] as num).toDouble(),
        cz = ((j['centre'] as List)[1] as num).toDouble(),
        sinP = math.sin((j['pitch'] as num).toDouble() * math.pi / 180),
        cosP = math.cos((j['pitch'] as num).toDouble() * math.pi / 180),
        z0 = ((j['depthRange'] as List)[0] as num).toDouble(),
        z1 = ((j['depthRange'] as List)[1] as num).toDouble(),
        gx0 = ((j['grid'] as Map)['x0'] as num).toDouble(),
        gz0 = ((j['grid'] as Map)['z0'] as num).toDouble(),
        cell = ((j['grid'] as Map)['cell'] as num).toDouble(),
        cols = ((j['grid'] as Map)['cols'] as num).toInt(),
        rows = ((j['grid'] as Map)['rows'] as num).toInt(),
        npcs = [for (final n in (j['npcs'] as List).cast<Map>()) WalkNpc(n)],
        ores = [
          for (final o in ((j['ores'] as List?) ?? const []).cast<Map>()) (o['kind'] as String, (o['x'] as num).toDouble(), (o['z'] as num).toDouble())
        ],
        spawn = Offset(((j['spawn'] as List)[0] as num).toDouble(), ((j['spawn'] as List)[1] as num).toDouble()),
        arrive = {
          for (final e in ((j['arrive'] as Map?) ?? const {}).entries)
            e.key as String: Offset(((e.value as List)[0] as num).toDouble(), ((e.value as List)[1] as num).toDouble())
        },
        spots = {
          for (final e in (j['spots'] as Map).entries) e.key as String: Offset(((e.value as List)[0] as num).toDouble(), ((e.value as List)[1] as num).toDouble())
        },
        sun = [for (final v in j['sun'] as List) (v as num).toDouble()],
        hz = (((j['grid'] as Map)['hz'] as num?) ?? 0).toInt(),
        cart = j['cart'] is Map ? ((j['cart']['x'] as num).toDouble(), (j['cart']['z0'] as num).toDouble(), (j['cart']['z1'] as num).toDouble()) : null {
    final rowsData = ((j['grid'] as Map)['walk'] as List).cast<String>();
    final hData = (((j['grid'] as Map)['height'] as List?) ?? const []).cast<String>();
    walk = Uint8List(cols * rows);
    height = Uint8List(cols * rows);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        walk[r * cols + c] = rowsData[r].codeUnitAt(c) == 49 ? 1 : 0;
        if (r < hData.length) height[r * cols + c] = hData[r].codeUnitAt(c) - 48;
      }
    }
  }
  final String map, title;
  final String tileDir;
  final List<WalkTile> tiles;
  final List<dynamic> emit; // the emitters, in the whole picture's px (SceneFx)
  final Map<String, (double, double, double, String?, String?)> exits; // x, z, radius, the map it leads to and where you arrive there
  final double w, h, ppu, cx, cz, sinP, cosP, z0, z1, gx0, gz0, cell;
  final int cols, rows;
  late final Uint8List walk;
  late final Uint8List height; // what you stand on, in quarter units from [hz] below zero (the bridge's deck is a unit up, the lane to the Thicket sinks)
  final int hz;
  final (double, double, double)? cart; // the ore cart's rails: x, z inside the mine, z at the end outside
  final List<WalkNpc> npcs;
  final List<(String, double, double)> ores; // ore nodes to Pounce: kind, x, z
  final Offset spawn; // a fresh visit starts here
  final Map<String, Offset> arrive; // where you arrive, by the way you came in
  final Map<String, Offset> spots;
  final List<double> sun;

  /// World (x, height, z) -> picture px.
  Offset toImage(double x, double z, [double y = 0]) => Offset(w / 2 + (x - cx) * ppu, h / 2 + ((z - cz) * sinP - y * cosP) * ppu);

  /// Picture px -> the ground point there (x, z).
  Offset toGround(Offset p) => Offset(cx + (p.dx - w / 2) / ppu, cz + (p.dy - h / 2) / (ppu * sinP));

  /// 0-1 of the depth range, as the picture's depth stores it.
  double depthQ(double z) => ((z - z0) / (z1 - z0)).clamp(0.0, 1.0);

  int _c(double x) => ((x - gx0) / cell).floor();
  int _r(double z) => ((z - gz0) / cell).floor();
  bool _ok(int c, int r) => c >= 0 && r >= 0 && c < cols && r < rows && walk[r * cols + c] == 1;
  Offset _centre(int c, int r) => Offset(gx0 + (c + 0.5) * cell, gz0 + (r + 0.5) * cell);
  bool walkable(double x, double z) => _ok(_c(x), _r(z));

  /// The height of what you walk on at (x, z).
  double heightAt(double x, double z) {
    final c = _c(x), r = _r(z);
    if (c < 0 || r < 0 || c >= cols || r >= rows) return 0;
    return (height[r * cols + c] - hz) * 0.25;
  }

  /// The walkable cell nearest (c, r), within [reach] cells.
  (int, int)? _nearest(int c, int r, {int reach = 16}) {
    if (_ok(c, r)) return (c, r);
    (int, int)? best;
    var bd = 1 << 30;
    for (var dr = -reach; dr <= reach; dr++) {
      for (var dc = -reach; dc <= reach; dc++) {
        final d = dr * dr + dc * dc;
        if (d < bd && _ok(c + dc, r + dr)) {
          bd = d;
          best = (c + dc, r + dr);
        }
      }
    }
    return best;
  }

  /// Nothing solid on the straight line between two points.
  bool clear(Offset a, Offset b) {
    final n = ((b - a).distance / (cell * 0.5)).ceil();
    for (var i = 1; i <= n; i++) {
      final p = Offset.lerp(a, b, i / n)!;
      if (!walkable(p.dx, p.dy)) return false;
    }
    return true;
  }

  /// A walk from [from] to [to] (or the nearest place you can stand): A* over the grid, then cut
  /// straight wherever the way is clear. Empty if there is no way there.
  List<Offset> path(Offset from, Offset to) {
    final s = _nearest(_c(from.dx), _r(from.dy));
    final e = _nearest(_c(to.dx), _r(to.dy));
    if (s == null || e == null) return const [];
    final goal = _ok(_c(to.dx), _r(to.dy)) ? to : _centre(e.$1, e.$2);
    if (clear(from, goal)) return [goal];
    final n = cols * rows;
    final g = Float64List(n)..fillRange(0, n, double.infinity);
    final came = Int32List(n)..fillRange(0, n, -1);
    final closed = Uint8List(n);
    final si = s.$2 * cols + s.$1, ei = e.$2 * cols + e.$1;
    double hh(int i) {
      final dc = (i % cols - e.$1).abs(), dr = (i ~/ cols - e.$2).abs();
      return (dc + dr) + (math.sqrt2 - 2) * math.min(dc, dr);
    }

    final heap = _Heap();
    g[si] = 0;
    heap.push(si, hh(si));
    while (heap.isNotEmpty) {
      final i = heap.pop();
      if (i == ei) break;
      if (closed[i] == 1) continue;
      closed[i] = 1;
      final c = i % cols, r = i ~/ cols;
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          if (dr == 0 && dc == 0) continue;
          final nc = c + dc, nr = r + dr;
          if (!_ok(nc, nr)) continue;
          // no cutting corners past something solid
          if (dr != 0 && dc != 0 && (!_ok(c + dc, r) || !_ok(c, r + dr))) continue;
          final j = nr * cols + nc;
          final ng = g[i] + (dr != 0 && dc != 0 ? math.sqrt2 : 1.0);
          if (ng < g[j]) {
            g[j] = ng;
            came[j] = i;
            heap.push(j, ng + hh(j));
          }
        }
      }
    }
    if (came[ei] == -1 && ei != si) return const [];
    final cells = <Offset>[];
    for (var i = ei; i != -1 && i != si; i = came[i]) {
      cells.add(_centre(i % cols, i ~/ cols));
    }
    final pts = [...cells.reversed];
    if (pts.isEmpty) return [goal];
    pts[pts.length - 1] = goal;
    // string-pull: from each point, jump to the farthest one in plain sight
    final out = <Offset>[];
    var at = from;
    var k = 0;
    while (k < pts.length) {
      var far = k;
      for (var m = pts.length - 1; m > k; m--) {
        if (clear(at, pts[m])) {
          far = m;
          break;
        }
      }
      out.add(pts[far]);
      at = pts[far];
      k = far + 1;
    }
    return out;
  }
}

/// One tile of the picture: the [crop] it covers (with a few px of its neighbours round it) and the
/// [core] it draws.
class WalkTile {
  WalkTile(this.i, this.j, this.crop, this.core);
  final int i, j;
  final Rect crop, core;
  ui.Image? pic, mask, depth;
  bool loading = false;
  bool get ready => pic != null && mask != null && depth != null;
  void drop() {
    pic?.dispose();
    mask?.dispose();
    depth?.dispose();
    pic = mask = depth = null;
    loading = false;
  }
}

class _Heap {
  final _k = <int>[];
  final _v = <double>[];
  bool get isNotEmpty => _k.isNotEmpty;
  void push(int k, double v) {
    _k.add(k);
    _v.add(v);
    var i = _k.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_v[p] <= _v[i]) break;
      _swap(i, p);
      i = p;
    }
  }

  int pop() {
    final top = _k[0];
    final lk = _k.removeLast(), lv = _v.removeLast();
    if (_k.isNotEmpty) {
      _k[0] = lk;
      _v[0] = lv;
      var i = 0;
      while (true) {
        final l = 2 * i + 1, r = l + 1;
        var m = i;
        if (l < _k.length && _v[l] < _v[m]) m = l;
        if (r < _k.length && _v[r] < _v[m]) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  void _swap(int a, int b) {
    final tk = _k[a], tv = _v[a];
    _k[a] = _k[b];
    _v[a] = _v[b];
    _k[b] = tk;
    _v[b] = tv;
  }
}

/// Your Evochi in the village (where it is, which way it faces, where it is going).
class VillageWalker {
  VillageWalker(this.x, this.z);
  double x, z;
  double y = 0; // how high it stands (eased, so stepping up onto the bridge isn't a jump)
  int dir = 4; // S SE E NE N NW W SW
  bool moving = false;
  double phase = 0;
  double speed = 0; // units a second now (it ramps up from a stop and eases in to arrive)
  bool running = false; // it breaks into a run on a long way, and drops back to a walk to arrive
  double stoppedAt = -9; // when it last came to rest (a little settle)
  int lastStep = 0; // the footfall count (dust)
  List<Offset> path = const [];
  String? talkTo; // a villager to talk to on arrival
  double wait = -1; // seconds until that conversation opens

  static int dirOf(double dx, double dz) => ((math.atan2(dx, dz) / (math.pi / 4)).round() % 8 + 8) % 8;
}

class _Npc {
  _Npc(this.id, this.x, this.z, this.place, this.img, this.ground, this.top, this.h, {this.walker})
      : homeX = x,
        homeZ = z;
  final String id, place;
  double x, z;
  final double homeX, homeZ;
  final ui.Image img; // the portrait sprite (the fallback when there are no outdoor sheets)
  final Offset ground, top;
  final double h; // world units, feet to the top of the head
  final WalkerArt? walker; // their outdoor sheets: eight directions, standing and walking
  int dir = 0; // S SE E NE N NW W SW
  double phase = 0;
  bool moving = false;
  List<Offset> route = const []; // the way to where they're walking, corner by corner
  Offset? face; // what they turn to when they get there
  double wait = 1.0; // seconds before the next thing they do
  int stop = 0; // which stop of their routine is next
  double look = 0; // seconds until they glance somewhere else while standing
  double busy = 0; // seconds they stay turned to what they're doing before glancing about

  /// dp per sheet px at [upk] dp a world unit.
  double k(double upk) => upk * h / (walker?.heightPx ?? 200);
}

/// One stop on a villager's routine: where (from where they stand) and, if they have something to do
/// there, what they turn to (from where they stand too).
class _Stop {
  const _Stop(this.dx, this.dz, [this.fx, this.fz]);
  final double dx, dz;
  final double? fx, fz;
}

/// Each villager's routine outside: the stops they wander between, how fast they walk (units a second),
/// and how long they linger at each stop (seconds, from - to). They find their own way between stops,
/// round whatever stands in between.
const _routines = <String, (List<_Stop>, double, double, double)>{
  'bram': ([_Stop(0, 0), _Stop(-2.8, 2.0), _Stop(2.4, 1.6)], 1.5, 3.0, 6.0), // between his door and the forge
  'mira': ([_Stop(0, 0), _Stop(3.2, 2.0), _Stop(-2.4, 2.4)], 1.3, 3.5, 7.0), // out to her flower beds
  'pip': ([_Stop(0, 0), _Stop(-2.8, 1.8), _Stop(1.6, 2.6), _Stop(-0.8, 3.4)], 2.4, 1.2, 3.0), // he can't keep still
  'alder': ([_Stop(0, 0), _Stop(1.0, 1.4)], 0.8, 6.0, 11.0), // mostly stands and looks about
  // Flint's day round the camp: the flag by his tent, the fire, the front of the yard watching the trail,
  // the tool rack by the wheelbarrow, and now and then out to check the ore cart on its rails.
  // indoors: Bram between the anvil, the forge, his bench, the ore crates and his lantern wall
  'workshop:bram': ([
    _Stop(0, 0, -3.0, -1.0),
    _Stop(-4.4, -1.0, -6.0, -2.5),
    _Stop(-9.0, -4.6, -9.0, -8.0),
    _Stop(4.6, -3.5, 7.6, -3.5),
    _Stop(-8.5, 5.6, -11.5, 5.6),
    _Stop(3.5, -6.4, 3.5, -9.4),
  ], 1.2, 4.0, 9.0),
  // Mira: the potting bench, the beds either side, the far end of the cross aisle, the bench by the door
  'glasshouse:mira': ([
    _Stop(0, 0, 0, 2.6),
    _Stop(0, -8.2, 0, -10.7),
    _Stop(0.5, -5.2, -4.0, -5.2),
    _Stop(0, 0.8, 4.0, 0.8),
    _Stop(-9.0, -2.4, -9.0, -4.7),
    _Stop(-5.5, 4.3, -8.5, 5.0),
    _Stop(8.0, -8.2, 10.0, -10.2),
  ], 1.1, 4.0, 9.0),
  // Pip: the notice board, the head of the table, the fire, the door, the map table
  'lodge:pip': ([
    _Stop(0, 0, 0, 3.0),
    _Stop(-2.0, -10.0, -2.0, -12.6),
    _Stop(-7.5, -9.2, -5.0, -5.6),
    _Stop(11.5, -2.2, 15.0, -4.6),
    _Stop(3.0, 3.4, 3.0, 6.4),
    _Stop(6.0, -1.6, 9.0, -1.6),
  ], 2.0, 2.5, 6.0),
  // Alder: mostly at his desk, now and then the map table, the board, or a look at the fire
  'lodge:alder': ([
    _Stop(0, 0, 0, -3.2),
    _Stop(-2.0, 6.6, 0, 6.4),
    _Stop(-7.5, -2.0, -9.0, -4.6),
    _Stop(-3.0, 3.4, 6.0, 3.4),
  ], 0.9, 7.0, 14.0),
  'flint': ([
    _Stop(0, 0, -2.0, -1.4), // by the tent, looking back into it
    _Stop(-4.6, 2.2, -6.5, 2.4), // the fire (it stands at 95.5, -12.6)
    _Stop(-2.0, 3.4, -2.0, 7.0), // the front of the yard, eyes on the trail
    _Stop(-9.4, 1.6, -9.4, -3.6), // the tool rack, by the wheelbarrow
    _Stop(-0.8, 1.8, 14.5, -1.5), // mid-yard, looking over at the portal
    _Stop(10.5, 4.8, 14.5, -5.0), // out on the trail by the rails, checking the cart
  ], 1.4, 3.0, 7.0),
};

class VillageWalkScreen extends StatefulWidget {
  const VillageWalkScreen({super.key, this.map = 'village', this.arrive});

  /// Which map ('village', 'trail'), and the way you came in (null: a fresh visit).
  final String map;
  final String? arrive;

  /// The one on screen (the recorder drives it).
  static VillageWalkScreenState? current;

  @override
  State<VillageWalkScreen> createState() => VillageWalkScreenState();
}

class VillageWalkScreenState extends State<VillageWalkScreen> with SingleTickerProviderStateMixin {
  WalkLayout? lay;
  ui.FragmentProgram? _prog;
  final _shaders = <ui.FragmentShader>[]; // a pool: a draw a shader (each keeps its own uniforms)
  SceneFx? _fx;
  WalkerArt? _pet;
  final _npcs = <_Npc>[];
  late final VillageWalker me;
  Ticker? _ticker;
  final _frame = ValueNotifier<double>(0);
  double _t = 0, _last = 0;
  Offset? _cam; // picture px at the middle of the view
  Size _view = Size.zero;
  bool _talking = false;
  ui.Image? _cartImg; // the ore cart's sprite (tools/art/village_trail.py --cart), on the mine's rails
  Offset _cartGround = Offset.zero;
  double _cartPpu = 45.8;
  double _cartZ = 0, _cartAt = 0; // where it is along its rails, and when its current move started
  int _cartPhase = 0; // 0 resting inside, 1 rolling out, 2 resting outside, 3 rolling in
  double _cartWait = 14;
  final _petNames = <String, String>{}; // the resting companions in the Grove, by their id
  ui.Image? _mini; // the map's overview (tools/art/walk_minimap.py), for the minimap and the map window
  (double, double, double)? _mark; // where you tapped (x, z) and when: a ring on the ground

  bool _leaving = false;
  String? _talkNpc; // the villager you're talking to (the chathead panel is up)

  // mining (mining.dart)
  MiningArt? _mining;
  final ores = <OreNode>[];
  OreNode? _goingTo; // walking up to it
  OreNode? target; // standing at it, ready to strike
  final pounce = Pounce();
  final _bits = <MineBit>[];
  final satchel = <String, int>{}; // this trip's ore
  double _bumpAt = -9;
  final _satchelKey = GlobalKey();
  final _mapKey = GlobalKey();
  int _stage = 3;
  bool _reduced = false; // the system asks for less motion
  static const _regrow = 40.0; // seconds until a burst node is whole again (the preview's pace)

  /// Loaded, with the picture round you in (the recorder waits for this).
  bool get ready => lay != null && _pet != null && _cam != null && _viewTiles().every((t) => t.ready);

  double get _k => _view.width / (_unitsAcross * lay!.ppu); // dp per picture px

  @override
  void initState() {
    super.initState();
    VillageWalkScreen.current = this;
    me = VillageWalker(0, 0);
    _load();
  }

  Future<ui.Image> _image(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  Future<void> _load() async {
    final c = context.read<GameController>();
    final pet = c.state.pet;
    final WalkLayout l;
    try {
      l = WalkLayout((jsonDecode(await rootBundle.loadString(_layoutAsset(widget.map))) as Map).cast<String, dynamic>());
    } catch (e) {
      debugPrint('walk map ${widget.map}: $e'); // not built yet
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('This way opens soon.')));
      Navigator.of(context).maybePop();
      return;
    }
    final r = await Future.wait<Object?>([
      WalkerArt.load('s0${(pet?.stage ?? 1).clamp(1, 3)}', pet?.paletteId ?? 'amber', wearing: _wearing(c.state)),
      SceneFx.program(),
      ui.FragmentProgram.fromAsset('shaders/village_fx.frag'),
    ]);
    final npcs = <_Npc>[];
    for (final n in l.npcs) {
      final art = n.art;
      // their outdoor sheets when this build has them (the portrait sprite otherwise)
      final walker = await WalkerArt.exists('npc_${n.id}') ? await WalkerArt.load('npc_${n.id}', 'default') : null;
      if (art != null) {
        npcs.add(_Npc(n.id, n.x, n.z, n.place, await _image(art), n.ground!, n.top!, n.height ?? 4.0, walker: walker));
      } else {
        final key = 'npc_${n.id}';
        npcs.add(_Npc(n.id, n.x, n.z, n.place, await _image(villageArt.npc(key, 'neutral', true)), villageArt.npcGround(key), villageArt.npcTop(key),
            _npcH[n.id] ?? 4.0,
            walker: walker));
      }
    }
    if (widget.map == 'home') {
      // the Grove: the companions resting at home, two or three on the moss beds (favourites first)
      final resting = List.of(c.state.companions)
        ..sort((a, b) => (hatch.isFavorite(c.state, b.id) ? 1 : 0).compareTo(hatch.isFavorite(c.state, a.id) ? 1 : 0));
      const beds = [(-35.2, 26.6), (-26.6, 26.2), (-31.0, 21.5)];
      for (var i = 0; i < resting.length && i < beds.length; i++) {
        final p = resting[i];
        final w = await WalkerArt.load('s0${p.stage.clamp(1, 3)}', p.paletteId, wearing: p.equipped.values.toList());
        _petNames['pet:${p.id}'] = p.name;
        npcs.add(_Npc('pet:${p.id}', beds[i].$1, beds[i].$2, 'grove', w.gait(false).img, Offset.zero, Offset.zero, _evochiH * 200 / _sheetH, // drawn as your own Evochi is
            walker: w)
          ..dir = i == 0 ? 2 : 6);
      }
    }
    final mining = l.ores.isEmpty ? null : await MiningArt.load(l.ores.map((o) => o.$1));
    ui.Image? mini, cartImg;
    Map<String, dynamic>? cartMeta;
    try {
      mini = await _image('${l.tileDir}mini.webp');
    } catch (_) {} // an older build without one: no minimap
    if (l.cart != null) {
      try {
        cartMeta = (jsonDecode(await rootBundle.loadString('assets/art/trail/cart.json')) as Map).cast<String, dynamic>();
        cartImg = await _image(cartMeta['src'] as String);
      } catch (_) {}
    }
    if (!mounted) return;
    final prog = r[2] as ui.FragmentProgram;
    setState(() {
      lay = l;
      _fx = SceneFx.emitters(l.emit, l.w, l.h);
      _pet = r[0] as WalkerArt;
      _npcs.addAll(npcs);
      _prog = prog;
      _mining = mining;
      _mini = mini;
      if (cartImg != null && cartMeta != null) {
        _cartImg = cartImg;
        _cartGround = Offset(((cartMeta['ground'] as List)[0] as num).toDouble(), ((cartMeta['ground'] as List)[1] as num).toDouble());
        _cartPpu = (cartMeta['ppu'] as num).toDouble();
        _cartZ = l.cart!.$2;
      }
      _lookKey = _wearing(c.state).join(',');
      ores.addAll([for (final (k, x, z) in l.ores) OreNode(k, x, z)]);
      _stage = (pet?.stage ?? 3).clamp(1, 3);
      final at = l.arrive[widget.arrive] ?? l.spawn;
      me
        ..x = at.dx
        ..z = at.dy
        ..y = l.heightAt(at.dx, at.dy);
      // coming in from another map, face the way you were going (away from the edge you came over)
      final from = l.exits[widget.arrive];
      if (from != null) me.dir = VillageWalker.dirOf(at.dx - from.$1, at.dy - from.$2);
    });
    _ticker = createTicker(_tick)..start();
  }

  /// What your Evochi wears here: the wearables, and on the trail and in the mines the mining loadout, a
  /// helmet covering the head's wearable and anything on the back covering the back's (they come back
  /// as you leave; nothing is taken off).
  List<String> _wearing(GameState s) {
    final eq = Map.of(s.pet?.equipped ?? const <String, String>{});
    if (widget.map == 'village') return eq.values.toList();
    final worn = mine.wornGear(s);
    if (worn.containsKey('helmet')) eq.remove('head');
    if (worn.keys.any((k) => k == 'harness' || k == 'satchel' || k == 'tool' || k == 'lantern')) eq.remove('back');
    const order = ['paws', 'harness', 'satchel', 'lantern', 'tool', 'helmet']; // drawn in this order
    return [...eq.values, for (final k in order) if (worn[k] != null) worn[k]!.id];
  }

  String _lookKey = '';

  /// The loadout changed (bought, forged, swapped): your Evochi's sprites again.
  Future<void> _refreshLook(GameState s) async {
    final key = _wearing(s).join(',');
    if (key == _lookKey || _pet == null) return;
    _lookKey = key;
    final pet = s.pet;
    final art = await WalkerArt.load('s0${(pet?.stage ?? 1).clamp(1, 3)}', pet?.paletteId ?? 'amber', wearing: _wearing(s));
    if (mounted) setState(() => _pet = art);
  }

  @override
  void dispose() {
    if (VillageWalkScreen.current == this) VillageWalkScreen.current = null;
    _ticker?.dispose();
    for (final s in _shaders) {
      s.dispose();
    }
    for (final t in lay?.tiles ?? const <WalkTile>[]) {
      t.drop();
    }
    _frame.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------------------------ moving
  void _tick(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    final dt = (t - _last).clamp(0.0, 0.05);
    _last = t;
    _t = t;
    final l = lay;
    if (l == null) return;
    if (me.path.isNotEmpty) {
      // how far there is to go: ease in over the last stretch; ramp up from a standstill
      var left = 0.0;
      var px = me.x, pz = me.z;
      for (final q in me.path) {
        left += (q - Offset(px, pz)).distance;
        px = q.dx;
        pz = q.dy;
      }
      // a long way is run (it breaks into the run a stride in, and walks the last stretch to arrive)
      if (!me.running && left > _runFrom && me.speed > _speed * 0.6 && !_reduced) me.running = true;
      if (me.running && left < _walkIn) me.running = false;
      final pace = me.running ? _runSpeed : _speed;
      final target = pace * (left < 1.4 ? (0.35 + 0.65 * left / 1.4) : 1.0);
      me.speed += (target - me.speed) * math.min(1.0, dt * (target > me.speed ? 6 : 9));
      var step = me.speed * dt;
      final cycle = _cycleFor(me.running);
      while (step > 0 && me.path.isNotEmpty) {
        final to = me.path.first;
        final dx = to.dx - me.x, dz = to.dy - me.z;
        final d = math.sqrt(dx * dx + dz * dz);
        if (d < 1e-4) {
          me.path = me.path.sublist(1);
          continue;
        }
        me.dir = VillageWalker.dirOf(dx, dz);
        final s = math.min(step, d);
        me.x += dx / d * s;
        me.z += dz / d * s;
        me.phase += s / cycle;
        step -= s;
        if (s >= d) me.path = me.path.sublist(1);
      }
      me.moving = me.path.isNotEmpty;
      // dust at each footfall (more of it kicked up at a run)
      final stepN = (me.phase * 2).floor();
      if (stepN != me.lastStep) {
        me.lastStep = stepN;
        if (!_reduced && me.moving) {
          final rnd = math.Random(stepN);
          final n = me.running ? 4 : 2;
          final kick = me.running ? 1.6 : 1.0;
          for (var i = 0; i < n; i++) {
            _bits.add(MineBit('dust', me.x + (rnd.nextDouble() - 0.5) * 0.6, 0.1, me.z + 0.2 + (rnd.nextDouble() - 0.5) * 0.3,
                (rnd.nextDouble() - 0.5) * 0.8 * kick, (0.5 + rnd.nextDouble() * 0.4) * kick, (rnd.nextDouble() - 0.5) * 0.4, _t, 0.38 + 0.1 * (kick - 1),
                const Color(0xCCD9CCB4), 0.45 * kick));
          }
        }
      }
      if (!me.moving) {
        me.speed = 0;
        me.running = false;
        me.stoppedAt = _t;
        _arrived();
      }
    }
    me.y += (l.heightAt(me.x, me.z) - me.y) * math.min(1.0, dt * 14);
    _mineTick(l, dt);
    _npcTick(l, dt);
    _checkExits(l);
    _cartTick(l);
    if (me.wait > 0) {
      me.wait -= dt;
      if (me.wait <= 0) _openTalk();
    }
    _follow(dt);
    _streamTiles();
    _frame.value = t;
  }

  /// Go to another map now (the recorder uses it after its exit hook), arriving by [at].
  void goTo(String map, String? at) => Navigator.of(context).pushReplacement(_mapRoute(map, at));

  /// Hooks for the recorder: what happens when you walk out (null: leave as the game does).
  static void Function(String exit)? onExit;

  void _checkExits(WalkLayout l) {
    if (_leaving || _talking) return;
    for (final e in l.exits.entries) {
      final (x, z, r, to, at) = e.value;
      if ((me.x - x) * (me.x - x) + (me.z - z) * (me.z - z) > r * r) continue;
      _leaving = true;
      me.path = const [];
      me.moving = false;
      final hook = onExit;
      if (hook != null) {
        hook(e.key);
      } else if (to != null) {
        Navigator.of(context).pushReplacement(_mapRoute(to, at));
      } else if (e.key == 'home') {
        Navigator.of(context).maybePop();
      } else if (e.key == 'mine') {
        _enterMine(x, z);
      } else if (_indoors || widget.map == 'home') {
        _door(e.key);
      } else {
        final say = switch (e.key) {
          'mine' => "Flint's still shoring up the mine's timbers. It opens soon.",
          'thicket' => 'The Sunlit Thicket lies beyond the arch. Its paths open soon.',
          _ => 'This way opens soon.',
        };
        context.read<GameController>().toast(say, icon: e.key == 'mine' ? 'aff_stone' : 'aff_nature');
      }
      return;
    }
  }

  /// The ore cart: it sits in the lit tunnel, and now and then rolls out into the yard and back (while
  /// your Evochi is clear of the rails), the portal's arch covering it while it is inside.
  void _cartTick(WalkLayout l) {
    final rails = l.cart;
    if (rails == null || _cartImg == null) return;
    final (rx, zIn, zOut) = rails;
    final onRails = (me.x - rx).abs() < 3.0 && me.z > zIn - 2.5 && me.z < zOut + 3.0;
    final e = _t - _cartAt;
    const roll = 5.5;
    switch (_cartPhase) {
      case 0 || 2:
        _cartZ = _cartPhase == 0 ? zIn : zOut;
        if (e > _cartWait && !onRails && !_reduced) {
          _cartPhase = _cartPhase == 0 ? 1 : 3;
          _cartAt = _t;
        }
      case 1 || 3:
        final f = (e / roll).clamp(0.0, 1.0);
        final c = Curves.easeInOutSine.transform(f);
        _cartZ = _cartPhase == 1 ? zIn + (zOut - zIn) * c : zOut + (zIn - zOut) * c;
        if (f >= 1) {
          _cartPhase = _cartPhase == 1 ? 2 : 0;
          _cartAt = _t;
          _cartWait = _cartPhase == 2 ? 9 + 8 * math.Random().nextDouble() : 16 + 20 * math.Random().nextDouble();
        }
    }
  }

  /// A door at home (or a station inside the cottage): the room or screen behind it opens; back out,
  /// your Evochi stands on the step.
  Future<void> _door(String key) async {
    final l = lay;
    final c = context.read<GameController>();
    switch (key) {
      case 'cottage':
        if (c.storyView.flag('cottage_restored')) {
          // the restored cottage is a room to walk into; until then, its story screen
          Navigator.of(context).pushReplacement(_mapRoute('cottage', 'home'));
          return;
        }
        openCottage(context);
      case 'garden':
        openGarden(context);
      case 'nook':
        await showNook(context);
      case 'grove':
        await showCompanions(context);
      case 'nest':
        goHome(context, 'nest');
        return;
      case 'kitchen':
        openStation(context, 'kitchen');
      case 'apothecary':
        if (c.homeView.apothecary) {
          openStation(context, 'apothecary');
        } else {
          c.toast("The cauldron's cold for now. The apothecary opens with a Home Tale.", icon: 'skill_alchemy');
        }
      case 'desk':
        openSkills(context);
      case 'forge':
        await showBramForge(context);
      default:
        c.toast('This way opens soon.');
    }
    if (!mounted) return;
    // wait for a pushed screen to come back, then step off the door
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final spot = l?.spots[key];
    if (spot != null) {
      me
        ..path = const []
        ..moving = false
        ..x = spot.dx
        ..z = spot.dy
        ..dir = 0;
      me.y = l!.heightAt(me.x, me.z);
    }
    _leaving = false;
    _refreshLook(c.state);
    if (mounted) setState(() {});
  }

  /// Into the mine: its first gallery (a floor made by the Wilds' room kit, mine: true). Back out, your
  /// Evochi stands in the mouth again, facing the yard.
  Future<void> _enterMine(double x, double z) async {
    final c = context.read<GameController>();
    c.audio.play('enc_whoosh', volume: 0.5);
    final day = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 86400000;
    await Navigator.of(context).push(PageRouteBuilder<void>(
      transitionDuration: const Duration(milliseconds: 600),
      pageBuilder: (_, __, ___) => WildsScreen(depth: 1, seed: day * 131 + 1, mine: true),
      transitionsBuilder: (_, a, __, child) => FadeTransition(opacity: a, child: child),
    ));
    if (!mounted) return;
    final l = lay;
    final spot = l?.spots['mine'];
    me
      ..path = const []
      ..moving = false
      ..x = spot?.dx ?? x
      ..z = (spot?.dy ?? z + 4)
      ..dir = 0;
    if (l != null) me.y = l.heightAt(me.x, me.z);
    _leaving = false;
    _refreshLook(c.state);
    setState(() {});
  }

  /// Back from a way out you didn't take (step off it and it arms again).
  void _rearm() => _leaving = false;

  // ------------------------------------------------------------------------------------ tiles
  /// The view, in picture px.
  Rect _viewRect() {
    final cam = _cam, l = lay;
    if (cam == null || l == null || _view.isEmpty) return Rect.zero;
    final k = _k;
    return Rect.fromCenter(center: cam, width: _view.width / k, height: _view.height / k);
  }

  Iterable<WalkTile> _viewTiles() {
    final v = _viewRect();
    return (lay?.tiles ?? const <WalkTile>[]).where((t) => t.core.overlaps(v));
  }

  int _inFlight = 0;

  /// Load the tiles round the view (a tile's width ahead), let go of the ones far behind.
  void _streamTiles() {
    final l = lay;
    final v = _viewRect();
    if (l == null || v.isEmpty) return;
    final want = v.inflate(700), keep = v.inflate(1800);
    final c = v.center;
    final need = l.tiles.where((t) => !t.ready && !t.loading && t.core.overlaps(want)).toList()
      ..sort((a, b) => (a.core.center - c).distanceSquared.compareTo((b.core.center - c).distanceSquared));
    for (final t in need) {
      if (_inFlight >= 3) break;
      _loadTile(t, l);
    }
    for (final t in l.tiles) {
      if ((t.ready || t.loading) && !t.core.overlaps(keep) && !t.loading) t.drop();
    }
  }

  Future<void> _loadTile(WalkTile t, WalkLayout l) async {
    t.loading = true;
    _inFlight++;
    try {
      final r = await Future.wait([
        _image('${l.tileDir}t_${t.i}_${t.j}.webp'),
        _image('${l.tileDir}m_${t.i}_${t.j}.webp'),
        _image('${l.tileDir}d_${t.i}_${t.j}.png'),
      ]);
      if (!mounted || !t.loading) {
        for (final im in r) {
          im.dispose();
        }
        return;
      }
      t
        ..pic = r[0]
        ..mask = r[1]
        ..depth = r[2]
        ..loading = false;
    } catch (e) {
      t.loading = false;
      debugPrint('village tile ${t.i},${t.j}: $e');
    } finally {
      _inFlight--;
    }
  }

  /// A shader from the pool (one per draw this frame: each holds its own uniforms until drawn).
  ui.FragmentShader? _shader(int i) {
    final p = _prog;
    if (p == null || i >= 64) return null;
    while (_shaders.length <= i) {
      _shaders.add(p.fragmentShader());
    }
    return _shaders[i];
  }

  /// World units per walk cycle: the sheet's stride, drawn at the village's size.
  /// World units a walk (or run) cycle covers, as your Evochi is drawn here: the sheets' strides, so the
  /// feet take the ground rather than slide.
  double _cycleFor(bool running) => _pet!.gait(running).cycle * walkerDrawScale * _evochiH / _sheetH;

  void _follow(double dt) {
    final l = lay!;
    if (_view.isEmpty) return;
    final k = _k;
    final p = l.toImage(me.x, me.z, me.y);
    // your Evochi a little below the middle, as in the Wilds
    var want = Offset(p.dx, p.dy - 0.08 * _view.height / k);
    final hw = _view.width / 2 / k, hh = _view.height / 2 / k;
    want = Offset(want.dx.clamp(hw, math.max(hw, l.w - hw)), want.dy.clamp(hh, math.max(hh, l.h - hh)));
    _cam = _cam == null ? want : Offset.lerp(_cam, want, math.min(1.0, dt * 5))!;
  }

  void _arrived() {
    final ore = _goingTo;
    if (ore != null) {
      _goingTo = null;
      target = ore;
      me.dir = VillageWalker.dirOf(ore.x - me.x, ore.z - me.z);
      setState(() {});
      return;
    }
    final id = me.talkTo;
    if (id == null) return;
    final n = _npcs.firstWhere((v) => v.id == id);
    me.dir = VillageWalker.dirOf(n.x - me.x, n.z - me.z);
    me.wait = 0.45;
  }

  void _openTalk() {
    final id = me.talkTo;
    me.talkTo = null;
    me.wait = -1;
    if (id == null || !mounted) return;
    final n = _npcs.firstWhere((v) => v.id == id);
    setState(() => _talking = true);
    if (n.place == 'grove') {
      // a resting companion: its card in My Evochis
      showCompanions(context, focus: id.substring(4)).then((_) {
        if (mounted) setState(() => _talking = false);
      });
      return;
    }
    if (n.place == 'crossing') {
      showFlintTalk(context).then((pick) async {
        if (pick == 'gear' && mounted) await showFlintShop(context);
        if (mounted) setState(() => _talking = false);
        if (pick == 'enter' && mounted) {
          final e = lay?.exits['mine'];
          if (e != null) walkTo(e.$1, e.$2);
        }
      });
      return;
    }
    if (const {'lodge', 'glasshouse', 'workshop'}.contains(n.place)) {
      // a villager: the talk opens where they stand (the chathead panel), the world still behind
      c_().audio.play('ui_tap', volume: 0.3);
      setState(() => _talkNpc = 'npc_${n.id}');
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'place'),
            builder: (_) => Ambience(villagePlace(n.place), child: PlaceScreen(placeId: n.place, npc: 'npc_${n.id}'))))
        .then((_) {
      if (mounted) setState(() => _talking = false);
    });
  }

  GameController c_() => context.read<GameController>();
  bool get _indoors => const {'cottage', 'lodge', 'glasshouse', 'workshop'}.contains(widget.map);

  // ------------------------------------------------------------------------------------ the chathead talk
  void _talkClose() {
    if (!mounted) return;
    setState(() {
      _talkNpc = null;
      _talking = false;
    });
  }

  /// Another villager takes over the talk: in this room they stop and turn to you; elsewhere, the talk
  /// closes and the way to their house is yours to walk.
  void _talkSwitch(String npcId) {
    final id = npcId.replaceFirst('npc_', '');
    if (_npcs.any((n) => n.id == id)) {
      setState(() => _talkNpc = npcId);
      return;
    }
    _talkClose();
    final place = q.npcs[npcId]?.location;
    if (place != null) _talkGoto(place);
  }

  /// Where a choice leads outside the talk.
  Future<void> _talkGoto(String to) async {
    final c = c_();
    _talkClose();
    if (!mounted) return;
    if (to == 'forge') {
      setState(() => _talking = true);
      await showBramForge(context);
      if (mounted) setState(() => _talking = false);
    } else if (to.startsWith('reward:')) {
      showStoryReward(context, to.substring(7), backToVillage: false);
    } else if (to == 'waystone') {
      openPlace(context, 'waystone');
    } else if (const {'lodge', 'glasshouse', 'workshop'}.contains(to)) {
      if (to == widget.map) return;
      if (widget.map == 'village') {
        final e = lay?.exits[to];
        if (e != null) walkTo(e.$1, e.$2); // across the Square to their door
      } else {
        Navigator.of(context).pushReplacement(_mapRoute(to, 'village'));
      }
    } else if (to == 'journey' || to == 'discover') {
      c.goTab('journey', journey: 'daily');
    } else if (to.startsWith('prep:')) {
      openPrep(context, to.substring(5));
    } else if (const {'garden', 'cottage', 'kitchen', 'apothecary'}.contains(to)) {
      goHome(context, to);
    } else {
      openPlace(context, to);
    }
  }

  /// Walk to a ground point.
  void walkTo(double x, double z) {
    final l = lay;
    if (l == null || _talking) return;
    _rearm();
    _leaveOre();
    me.talkTo = null;
    me.wait = -1;
    me.path = l.path(Offset(me.x, me.z), Offset(x, z));
    me.moving = me.path.isNotEmpty;
    if (me.moving) _mark = (me.path.last.dx, me.path.last.dy, _t);
  }

  /// Walk up to a villager and talk.
  void talkTo(String id) {
    final l = lay;
    if (l == null || _talking) return;
    _rearm();
    _leaveOre();
    final n = _npcs.firstWhere((v) => v.id == id);
    // stand in front of them, a little to the side you come from
    final side = me.x >= n.x ? 1.0 : -1.0;
    me.path = l.path(Offset(me.x, me.z), Offset(n.x + side * 1.4, n.z + 2.3));
    me.talkTo = id;
    me.wait = -1;
    me.moving = me.path.isNotEmpty;
    if (!me.moving) _arrived();
  }

  void _tap(Offset local) {
    final l = lay, cam = _cam;
    if (l == null || cam == null) return;
    if (_talkNpc != null) _talkClose(); // walking off ends the talk, as it would
    final k = _k;
    final p = cam + (local - _view.center(Offset.zero)) / k;
    // a villager first (tap their sprite)
    for (final n in _npcs.reversed) {
      if (_npcRect(n).inflate(6).contains(p)) return talkTo(n.id);
    }
    for (final o in ores) {
      final r = _oreRect(o);
      if (r != null && r.inflate(8).contains(p)) return mineOre(o);
    }
    final g = l.toGround(p);
    walkTo(g.dx, g.dy);
  }

  // ------------------------------------------------------------------------------------ the villagers
  final _rnd = math.Random(5);

  /// The villagers' own lives: they wander their routine, linger, glance about; when your Evochi comes
  /// near they stop and turn to it, and while you're on your way to talk to one, they wait for you.
  void _npcTick(WalkLayout l, double dt) {
    for (final n in _npcs) {
      final w = n.walker;
      final dx = me.x - n.x, dz = me.z - n.z;
      final near = dx * dx + dz * dz < 5.5 * 5.5;
      final waiting = me.talkTo == n.id || (_talking && me.talkTo == null && near) || _talkNpc == 'npc_${n.id}';
      if (w == null) continue;
      if (near || waiting) {
        // stop where they are and turn to your Evochi (they pick their walk up again once you've gone)
        n.moving = false;
        n.dir = VillageWalker.dirOf(dx, dz);
        n.wait = math.max(n.wait, 1.5);
        n.busy = 0;
        continue;
      }
      final r = _routines['${widget.map}:${n.id}'] ?? _routines[n.id];
      if (n.route.isNotEmpty) {
        final g = n.route.first;
        final gx = g.dx - n.x, gz = g.dy - n.z;
        final d = math.sqrt(gx * gx + gz * gz);
        final speed = r?.$2 ?? 1.4;
        final s = math.min(d, speed * dt);
        if (d > 0.001) {
          n.x += gx / d * s;
          n.z += gz / d * s;
          n.dir = VillageWalker.dirOf(gx, gz);
          n.moving = true;
          n.phase += s / (w.gait(false).cycle * walkerDrawScale * n.h / (w.heightPx ?? 200));
        }
        if (d - s < 0.05) {
          n.route = n.route.sublist(1);
          if (n.route.isEmpty) {
            // there: turn to what they came for, and stay with it a while before glancing about
            n.moving = false;
            n.wait = (r?.$3 ?? 3) + _rnd.nextDouble() * ((r?.$4 ?? 6) - (r?.$3 ?? 3));
            final f = n.face;
            if (f != null) {
              n.dir = VillageWalker.dirOf(f.dx - n.x, f.dy - n.z);
              n.busy = n.wait * 0.7;
            }
            n.look = 1.0 + _rnd.nextDouble() * 1.5;
          }
        }
        continue;
      }
      n.wait -= dt;
      n.look -= dt;
      n.busy -= dt;
      if (n.look <= 0 && n.busy <= 0) {
        // a glance one way or the other, now and then back toward the path
        n.dir = (n.dir + (_rnd.nextBool() ? 1 : -1) + 8) % 8;
        n.look = 1.4 + _rnd.nextDouble() * 2.6;
      }
      if (n.wait <= 0 && r != null && r.$1.length > 1) {
        // the next stop they can get to (a blocked one is skipped, not stood in front of)
        for (var tries = 0; tries < r.$1.length; tries++) {
          n.stop = (n.stop + 1) % r.$1.length;
          final o = r.$1[n.stop];
          final g = Offset(n.homeX + o.dx, n.homeZ + o.dz);
          if (!l.walkable(g.dx, g.dy)) continue;
          final from = Offset(n.x, n.z);
          final way = l.path(from, g);
          if (way.isEmpty) continue;
          var len = 0.0;
          var at = from;
          for (final p in way) {
            len += (p - at).distance;
            at = p;
          }
          if (len > (g - from).distance * 2.5 + 6) continue; // no long way round
          n.route = way;
          n.face = o.fx == null ? null : Offset(n.homeX + o.fx!, n.homeZ + o.fz!);
          break;
        }
        if (n.route.isEmpty) n.wait = 2.0;
      }
    }
  }

  // ------------------------------------------------------------------------------------ mining
  /// Walk up to an ore node and face it (the Pounce button shows when you're there). Never strikes by itself.
  void mineOre(OreNode o) {
    final l = lay;
    if (l == null || _talking) return;
    if (target == o && !me.moving) return; // already there: the button is the way to strike
    _rearm();
    _leaveOre();
    me.talkTo = null;
    me.wait = -1;
    // stand in front of it, on the side you come from (or the nearest side you can stand on)
    final a = math.atan2(me.z - o.z, me.x - o.x);
    Offset? at;
    for (final da in const [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.4, -2.4, 3.1]) {
      final c = Offset(o.x + math.cos(a + da) * 2.6, o.z + math.sin(a + da) * 2.6);
      if (l.walkable(c.dx, c.dy)) {
        at = c;
        break;
      }
    }
    at ??= Offset(o.x, o.z + 2.6);
    me.path = l.path(Offset(me.x, me.z), at);
    me.moving = me.path.isNotEmpty;
    _goingTo = o;
    if (!me.moving) _arrived();
  }

  /// Off somewhere else: a strike that hasn't landed yet is called off (no loot without a contact).
  void _leaveOre() {
    final had = target != null;
    _goingTo = null;
    target = null;
    if (had && mounted) setState(() {}); // the Pounce button goes
    if (pounce.active && !pounce.contacted) pounce.t = -1;
    pounce
      ..held = false
      ..queued = false;
  }

  /// The Pounce button went down: strike now, or (mid-strike, past its contact) queue one more.
  void pounceDown() {
    final o = target;
    pounce.held = true;
    if (o == null || o.broken || me.moving) return;
    if (!pounce.active) {
      _strike(o);
    } else if (pounce.contacted && !pounce.tooHard) {
      pounce.queued = true;
    }
  }

  void pounceUp() => pounce.held = false;

  bool get pounceReady => target != null && !target!.broken && !me.moving && (!pounce.active || pounce.contacted);

  void _strike(OreNode o) {
    me.dir = VillageWalker.dirOf(o.x - me.x, o.z - me.z);
    pounce
      ..node = o
      ..t = 0
      ..contacted = false
      ..tooHard = (oreTier[o.kind] ?? 1) > mine.oreTierOf(context.read<GameController>().state); // your loadout decides
  }

  void _mineTick(WalkLayout l, double dt) {
    final p = pounce;
    if (p.active) {
      p.t += dt;
      if (!p.contacted && p.t >= pounceContact) {
        p.contacted = true;
        _contact();
      }
      if (p.t >= pounceEnd) {
        final o = p.node;
        final again = o != null && o == target && !o.broken && !p.tooHard && (p.queued || p.held);
        p.queued = false;
        if (again) {
          _strike(o);
        } else {
          p.t = -1;
          p.contacted = false;
        }
      }
    }
    // the bits in the air; nuggets that reach the satchel go in it
    stepBits(_bits, _t, dt, (x, z) => l.heightAt(x, z));
    final done = _bits.where((b) => b.kind == 'nugget' && b.flyAt > 0 && _t - b.flyAt >= _flyTime).toList();
    for (final b in done) {
      _bits.remove(b);
      satchel[b.ore!] = (satchel[b.ore!] ?? 0) + 1;
      _bumpAt = _t;
      context.read<GameController>().audio.play('mine_collect', volume: 0.5);
    }
    if (done.isNotEmpty) setState(() {});
    for (final o in ores) {
      if (o.broken && _t - o.brokeAt > _regrow) o.regrow();
    }
  }

  static const _flyTime = 0.45;

  /// The contact: everything the hit does, once.
  void _contact() {
    final o = pounce.node, art = _mining?.ores[pounce.node?.kind];
    if (o == null || art == null) return;
    final to = Offset(me.x - o.x, me.z - o.z);
    final toward = to.distance > 0 ? to / to.distance : const Offset(0, 1);
    o.hitAt = _t;
    o.hitDir = me.x <= o.x ? 1 : -1; // shoved away from you
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final audio = context.read<GameController>().audio;
    if (pounce.tooHard) {
      o.noteAt = _t;
      pounce.tiltAt = _t;
      audio.play('mine_clink', volume: 0.6);
      _bits.addAll(contactBits(o, _t, toward, broke: false, reduced: true).where((b) => b.kind == 'dust'));
      return;
    }
    final first = o.damage == 0;
    final c0 = context.read<GameController>();
    c0.run((st, now) => mine.markFirstTrip(st, now), quiet: true); // gear on its first trip remembers it
    final broke = o.strike(mine.miningPowerOf(c0.state), art.hits);
    audio.play('mine_${o.kind}_${broke ? 'break' : first ? 'chip' : 'crack'}', volume: broke ? 0.8 : 0.6);
    _bits.addAll(contactBits(o, _t, toward, broke: broke, reduced: reduced));
    if (broke) {
      o.brokeAt = _t;
      final n = o.kind == 'copper' ? 3 : 2;
      _bits.addAll(nuggets(o, _t, toward, n));
      // the loot, once, at the break (the nuggets flying to the satchel are only the show)
      final c = context.read<GameController>();
      final r = c.run((st, now) => mine.breakOre(st, o.kind, n, '${widget.map}:${ores.indexOf(o)}:${DateTime.now().millisecondsSinceEpoch}', now), quiet: true);
      if (r.events.any((e) => e.type == 'ore_first')) {
        final name = oreName[o.kind] ?? o.kind;
        Future.delayed(const Duration(milliseconds: 900), () => c.toast('Your first $name! It is in your Bag, ready for Bram.', icon: 'gem'));
      }
      setState(() {});
    }
  }

  /// An ore node's sprite, in picture px (null: no art).
  Rect? _oreRect(OreNode o) {
    final l = lay, art = _mining?.ores[o.kind];
    if (l == null || art == null) return null;
    final sp = art.states[o.state];
    final s = art.unit * l.ppu;
    final g = l.toImage(o.x, o.z, l.heightAt(o.x, o.z));
    return Rect.fromLTWH(g.dx - sp.ground.dx * s, g.dy - sp.ground.dy * s, sp.img.width * s, sp.img.height * s);
  }

  /// The satchel's middle, in the map's own coordinates (where the nuggets fly to).
  Offset? satchelPoint() {
    final sb = _satchelKey.currentContext?.findRenderObject() as RenderBox?;
    final mb = _mapKey.currentContext?.findRenderObject() as RenderBox?;
    if (sb == null || mb == null || !sb.attached || !mb.attached) return null;
    return mb.globalToLocal(sb.localToGlobal(sb.size.center(Offset.zero)));
  }

  /// A villager's sprite, in picture px.
  Rect _npcRect(_Npc n) {
    final l = lay!;
    final g = l.toImage(n.x, n.z, l.heightAt(n.x, n.z));
    final w = n.walker;
    if (w != null) {
      final s = n.k(l.ppu);
      return Rect.fromLTWH(g.dx - w.gx * s, g.dy - w.gy * s, w.fw * s, w.fh * s);
    }
    final s = n.h * l.ppu / (n.ground.dy - n.top.dy);
    return Rect.fromLTWH(g.dx - n.ground.dx * s, g.dy - n.ground.dy * s, n.img.width * s, n.img.height * s);
  }

  // ------------------------------------------------------------------------------------ the screen
  @override
  Widget build(BuildContext context) {
    _reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final c = context.watch<GameController>();
    if (lay != null && _wearing(c.state).join(',') != _lookKey) _refreshLook(c.state);
    final marks = q.npcMarkers(c.state);
    return Scaffold(
      backgroundColor: _indoors ? const Color(0xFF2C2019) : const Color(0xFF86B566),
      body: Column(children: [
        Container(
          color: EvochiColor.panel,
          child: SafeArea(
            bottom: false,
            child: PlaceHeader(
                title: lay?.title ?? switch (widget.map) { 'trail' => 'The Old Trail', 'home' => 'Your Home', 'cottage' => 'Your Cottage', 'lodge' => 'The Guild Lodge', 'workshop' => "Bram's Workshop", 'glasshouse' => "Mira's Glasshouse", _ => 'Sunlit Village' },
                short: switch (widget.map) { 'trail' => 'Trail', 'home' => 'Home', 'cottage' => 'Cottage', 'lodge' => 'Guild', 'workshop' => 'Workshop', 'glasshouse' => 'Glasshouse', _ => 'Village' },
                backLabel: 'Back',
                onBack: () => Navigator.of(context).maybePop()),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (ctx, b) {
            final size = Size(b.maxWidth, b.maxHeight);
            if (size != _view) {
              _view = size;
              if (lay != null) _cam = null;
            }
            if (lay == null || _pet == null) return const Center(child: CircularProgressIndicator());
            if (_cam == null) _follow(1);
            final map = GestureDetector(
              key: _mapKey,
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition),
              child: CustomPaint(size: size, painter: _WalkPainter(this, marks)),
            );
            final mining = _mining, mini = _mini;
            return Stack(children: [
              map,
              // top left: the minimap (tap: the map window), and on the trail your mining gear
              Positioned(
                top: 10,
                left: 10,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (mini != null) _MiniMap(s: this, image: mini, onOpen: _openMap),
                  if (mining != null) ...[
                    const SizedBox(height: 8),
                    _HudChip(label: 'Gear', semantic: 'Mining gear', onTap: () => showGearLoadout(context), child: const ItemImage('gear_copper_headlamp', size: 26)),
                  ],
                ]),
              ),
              if (mining != null)
                Positioned(
                  top: 10,
                  right: 10,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _frame,
                    builder: (_, t, __) => satchel.values.any((v) => v > 0)
                        ? SatchelChip(counts: satchel, bumpAt: _bumpAt, now: t, art: mining, anchor: _satchelKey)
                        : SizedBox(key: _satchelKey, width: 40, height: 40),
                  ),
                ),
              if (mining != null && target != null)
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: ValueListenableBuilder<double>(
                    valueListenable: _frame,
                    builder: (_, __, ___) => PounceButton(ready: pounceReady, onDown: pounceDown, onUp: pounceUp),
                  ),
                ),
              if (_talkNpc != null)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: ChatheadTalk(npc: _talkNpc!, forge: bramForges(c.state), onSwitch: _talkSwitch, onClose: _talkClose, onGoto: _talkGoto),
                ),
            ]);
          }),
        ),
        if (_talkNpc == null)
          _QuickTravel(
              items: switch (widget.map) {
                'trail' => _trailTravel,
                'home' => _homeTravel,
                'cottage' => _cottageTravel,
                'workshop' => _workshopTravel,
                'glasshouse' => _glasshouseTravel,
                'lodge' => _lodgeTravel,
                _ => _villageTravel
              },
              onPick: _quick),
      ]),
    );
  }

  /// The map window: the whole place, with where you are and pins for where you can go; tap a pin
  /// and your Evochi walks there (to whoever keeps it, or out the way it leads).
  Future<void> _openMap() async {
    final l = lay, mini = _mini;
    if (l == null || mini == null) return;
    final names = _placeNames[widget.map] ?? const {};
    final places = <(String, String, String, Offset)>[];
    void add(String id, double x, double z) {
      final n = names[id];
      if (n != null && !places.any((p) => p.$1 == id)) places.add((id, n.$1, n.$2, l.toImage(x, z, l.heightAt(x, z))));
    }
    for (final e in l.exits.entries) {
      add(e.key, e.value.$1, e.value.$2);
    }
    for (final n in _npcs) {
      add(n.id, n.x, n.z);
    }
    for (final e in l.spots.entries) {
      add(e.key, e.key == 'mine' ? l.exits['mine']?.$1 ?? e.value.dx : e.value.dx, e.value.dy);
    }
    final pick = await showEvochiDialog<String>(context,
        builder: (_) => _MapWindow(title: l.title, image: mini, picture: Size(l.w, l.h), places: places, me: l.toImage(me.x, me.z, me.y)));
    if (pick == null || !mounted) return;
    if (_npcs.any((n) => n.id == pick)) return talkTo(pick);
    final e = l.exits[pick];
    if (e != null) return walkTo(e.$1, e.$2);
    final w = l.spots[pick];
    if (w != null) walkTo(w.dx, w.dy);
  }

  void _quick(String id) {
    final l = lay;
    if (l == null) return;
    switch (id) {
      case 'flint':
        talkTo('flint');
      case 'village' || 'trail' || 'home': // to the way out: walk to it and over
        final e = l.exits[id];
        if (e != null) walkTo(e.$1, e.$2);
      case 'lodge' || 'glasshouse' || 'workshop' when widget.map == 'village': // across the Square to a door
        final e = l.exits[id];
        if (e != null) walkTo(e.$1, e.$2);
      case 'anvil' when widget.map == 'workshop':
        final e = l.exits['forge'];
        if (e != null) walkTo(e.$1, e.$2);
      case _ when _npcs.any((n) => n.id == id):
        talkTo(id);
      case 'cottage' || 'garden' || 'nook' || 'grove' || 'nest' when widget.map == 'home': // to a door: walk in
        final e = l.exits[id];
        if (e != null) walkTo(e.$1, e.$2);
      case 'kitchen' || 'apothecary' || 'desk' when widget.map == 'cottage': // to a station: walk up to it
        final e = l.exits[id];
        if (e != null) walkTo(e.$1, e.$2);
      default:
        final w = l.spots[id];
        if (w != null) walkTo(w.dx, w.dy);
    }
  }
}

const _villageTravel = [('lodge', 'mail', 'Guild'), ('glasshouse', 'care', 'Glasshouse'), ('workshop', 'bell', 'Workshop'), ('waystone', 'star', 'Waystone'), ('trail', 'trail', 'Old Trail')];
const _workshopTravel = [('bram', 'bell', 'Bram'), ('anvil', 'aff_stone', 'Anvil'), ('bench', 'gem', 'Bench'), ('village', 'trail', 'Square')];
const _glasshouseTravel = [('mira', 'care', 'Mira'), ('bench', 'skill_farming', 'Bench'), ('beds', 'aff_nature', 'Beds'), ('village', 'trail', 'Square')];
const _lodgeTravel = [('pip', 'mail', 'Pip'), ('alder', 'journey', 'Alder'), ('board', 'pin', 'Board'), ('fire', 'aff_ember', 'Fire'), ('village', 'trail', 'Square')];
const _homeTravel = [('nest', 'home', 'Nest'), ('cottage', 'bell', 'Cottage'), ('garden', 'skill_farming', 'Farm'), ('nook', 'star', 'Nook'), ('grove', 'paw', 'Grove'), ('village', 'trail', 'Village')];
const _trailTravel = [('village', 'home', 'Village'), ('bridge', 'aff_water', 'Falls'), ('flint', 'shop', 'Flint'), ('mine', 'aff_stone', 'Mine'), ('thicket', 'aff_nature', 'Thicket')];
const _cottageTravel = [('kitchen', 'skill_cooking', 'Kitchen'), ('apothecary', 'skill_alchemy', 'Apothecary'), ('desk', 'journey', 'Skills'), ('hearth', 'aff_ember', 'Hearth'), ('home', 'home', 'Outside')];

/// The bottom row: the places, a walk away (to whoever keeps them, or to a landmark).
class _QuickTravel extends StatelessWidget {
  const _QuickTravel({required this.items, required this.onPick});
  final List<(String, String, String)> items; // id, icon, label
  final void Function(String) onPick;
  @override
  Widget build(BuildContext context) {
    return Container(
      color: EvochiColor.panel,
      child: SafeArea(
        top: false,
        child: Container(
          margin: const EdgeInsets.fromLTRB(6, 6, 6, 6),
          height: 68,
          padding: const EdgeInsets.all(5),
          decoration: Kit.navBar(),
          child: Row(children: [
            for (final (id, icon, label) in items)
              Expanded(
                child: Semantics(
                  button: true,
                  label: label,
                  hint: 'Walk there',
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPick(id),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        VoxelIcon(icon, size: 34),
                        ExcludeSemantics(
                          child: Text(label,
                              style: EvochiText.tag.copyWith(
                                  fontSize: 12.5, height: 1.15, color: KitColor.navText, shadows: const [Shadow(color: Color(0xA61E0C00), offset: Offset(0, 1))])),
                        ),
                      ]),
                    ),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

class _WalkPainter extends CustomPainter {
  _WalkPainter(this.s, this.marks) : super(repaint: s._frame);
  final VillageWalkScreenState s;
  final Map<String, String> marks;

  @override
  void paint(Canvas canvas, Size size) {
    final l = s.lay, cam = s._cam;
    if (l == null || cam == null) return;
    final k = s._k;
    final mid = size.center(Offset.zero);
    Offset scr(Offset p) => (p - cam) * k + mid;
    Rect scrR(Rect r) => Rect.fromPoints(scr(r.topLeft), scr(r.bottomRight));
    final whole = Rect.fromLTWH(scr(Offset.zero).dx, scr(Offset.zero).dy, l.w * k, l.h * k);
    final view = Offset.zero & size;
    canvas.save();
    canvas.clipRect(view);
    canvas.drawRect(view, Paint()..color = const Color(0xFF86B566));
    // the picture, tile by tile
    var si = 0;
    final vis = s._viewTiles().toList();
    for (final t in vis) {
      if (t.ready) _scene(canvas, s._shader(si++), t, scrR(t.crop), scrR(t.core).intersect(view), -1);
    }
    // what stands in front of a character, drawn over it: every tile under its sprite
    void cover(Rect sprite, double z) {
      final area = sprite.inflate(2);
      for (final t in vis) {
        if (!t.ready) continue;
        final a = scrR(t.core).intersect(area);
        if (a.isEmpty || a.width <= 0 || a.height <= 0) continue;
        final sh = s._shader(si++);
        if (sh != null) _scene(canvas, sh, t, scrR(t.crop), a, l.depthQ(z + _frontBias));
      }
    }
    // where you tapped: a ring on the ground that opens and fades
    final mk = s._mark;
    if (mk != null && s._t - mk.$3 < 0.7) {
      final a = (s._t - mk.$3) / 0.7;
      final c = scr(l.toImage(mk.$1, mk.$2, l.heightAt(mk.$1, mk.$2)));
      final rw = (0.9 + 0.8 * a) * l.ppu * k;
      for (final (grow, op) in const [(0.0, 0.9), (0.35, 0.45)]) {
        canvas.drawOval(Rect.fromCenter(center: c, width: rw * 2 * (1 + grow), height: rw * 2 * (1 + grow) * l.sinP),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3
              ..color = Color.fromRGBO(255, 250, 230, op * (1 - a)));
      }
    }
    // shadows, then the characters from the back, each covered by whatever stands in front of it
    final upk = l.ppu * k; // dp per world unit
    final items = <(double, void Function())>[];
    for (final n in s._npcs) {
      final w = n.walker;
      if (w != null) {
        items.add((n.z, () {
          final g = scr(l.toImage(n.x, n.z, l.heightAt(n.x, n.z)));
          final kp = n.k(upk);
          final gait = w.gait(false);
          final col = gait.col(n.phase, n.moving);
          final src = Rect.fromLTWH(col * w.fw, n.dir * w.fh, w.fw, w.fh);
          canvas.drawOval(Rect.fromCenter(center: g + Offset(0, -kp * 3), width: w.fw * kp * 0.42, height: w.fw * kp * 0.13),
              Paint()
                ..color = const Color(0x3A16241F)
                ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
          _castShadow(canvas, gait.img, src, g, Offset(w.gx * kp, w.gy * kp), kp, l);
          final breathe = n.moving ? 1.0 : 1 + 0.012 * math.sin(s._t * 2.3 + n.homeX);
          final dst = Rect.fromLTWH(-w.gx * kp, -w.gy * kp, w.fw * kp, w.fh * kp);
          canvas.save();
          canvas.translate(g.dx, g.dy);
          canvas.rotate(gait.roll[col] * math.pi / 180 * math.cos(n.dir * math.pi / 4));
          canvas.scale(2 - breathe, gait.squash[col] * breathe);
          // a soft dark-brown outline and a touch more colour, so villagers stand out from the busy ground
          for (final d in _npcRing) {
            canvas.drawImageRect(gait.img, src, dst.shift(d * 1.4), _npcInk);
          }
          canvas.drawImageRect(gait.img, src, dst, _npcPop);
          canvas.restore();
          cover(dst.shift(g), n.z);
        }));
        continue;
      }
      items.add((n.z, () {
        final r = s._npcRect(n);
        final g = scr(l.toImage(n.x, n.z));
        final sc = upk * n.h / (n.ground.dy - n.top.dy);
        _castShadow(canvas, n.img, Rect.fromLTWH(0, 0, n.img.width.toDouble(), n.img.height.toDouble()), g, n.ground * sc, sc, l);
        final breathe = 1 + 0.012 * math.sin(s._t * 2.3 + n.x);
        canvas.save();
        canvas.translate(g.dx, g.dy);
        canvas.scale(2 - breathe, breathe);
        canvas.drawImageRect(n.img, Rect.fromLTWH(0, 0, n.img.width.toDouble(), n.img.height.toDouble()),
            Rect.fromLTWH(-n.ground.dx * sc, -n.ground.dy * sc, n.img.width * sc, n.img.height * sc), Paint()..filterQuality = FilterQuality.medium);
        canvas.restore();
        cover(scrR(r), n.z);
      }));
    }
    final mining = s._mining;
    for (final o in s.ores) {
      final art = mining?.ores[o.kind];
      if (art == null) continue;
      items.add((o.z, () {
        final r = s._oreRect(o)!;
        final sp = art.states[o.state];
        var dst = scrR(r);
        // a hit shoves it 2-4 px and it settles; a regrown node pops back in
        final h = s._t - o.hitAt;
        if (h >= 0 && h < 0.24) dst = dst.shift(Offset(o.hitDir * 3.2 * math.sin(h / 0.24 * math.pi * 3) * (1 - h / 0.24), 0));
        final g = scr(l.toImage(o.x, o.z, l.heightAt(o.x, o.z)));
        canvas.drawOval(Rect.fromCenter(center: g + Offset(0, -upk * 0.1), width: upk * 2.6, height: upk * 0.8),
            Paint()
              ..color = const Color(0x3316241F)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        final d = math.sqrt(math.pow(s.me.x - o.x, 2) + math.pow(s.me.z - o.z, 2));
        paintOre(canvas, sp.img, dst, o.kind, o.state, s._t, (1 - (d - 2.6) / 3.5).clamp(0.0, 1.0), s._reduced, o.x * 0.37 + o.z * 0.11);
        cover(dst, o.z);
      }));
    }
    final cart = s._cartImg, rails = l.cart;
    if (cart != null && rails != null) {
      items.add((s._cartZ, () {
        final g = scr(l.toImage(rails.$1, s._cartZ, l.heightAt(rails.$1, s._cartZ)));
        final k = upk / s._cartPpu; // dp per sprite px
        final rolling = s._cartPhase == 1 || s._cartPhase == 3;
        final jolt = rolling ? 0.6 * math.sin(s._t * 23) : 0.0;
        final dst = Rect.fromLTWH(g.dx - s._cartGround.dx * k, g.dy - s._cartGround.dy * k + jolt, cart.width * k, cart.height * k);
        canvas.drawOval(Rect.fromCenter(center: g + Offset(0, -upk * 0.1), width: upk * 3.2, height: upk * 1.0),
            Paint()
              ..color = const Color(0x3316241F)
              ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
        canvas.drawImageRect(cart, Rect.fromLTWH(0, 0, cart.width.toDouble(), cart.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
        cover(dst, s._cartZ);
      }));
    }
    items.add((s.me.z, () {
      cover(_pet(canvas, scr(l.toImage(s.me.x, s.me.z, s.me.y)), upk, l), s.me.z);
    }));
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, draw) in items) {
      draw();
    }
    // the mining in the air: chips, dust, sparks, ore popping out and off to the satchel
    _paintBits(canvas, l, upk, scr, mining);
    // the air: glows, smoke, leaves, motes
    final fx = s._fx;
    if (fx != null) {
      canvas.save();
      canvas.translate(whole.left, whole.top);
      canvas.scale(k, k);
      SceneFx.paintEmitters(canvas, fx, s._t);
      canvas.restore();
    }
    for (final o in s.ores) {
      final a = s._t - o.noteAt;
      if (a < 0 || a > 1.8) continue;
      final top = scr(l.toImage(o.x, o.z, 3.2)) - Offset(0, 10 + 8 * math.min(1.0, a / 0.2));
      canvas.saveLayer(null, Paint()..color = Color.fromRGBO(0, 0, 0, a > 1.5 ? (1.8 - a) / 0.3 : 1));
      _chip(canvas, top, 'Needs better gear');
      canvas.restore();
    }
    // a "!" over whoever has something for you; a name when you are close
    for (final n in s._npcs) {
      final head = scr(l.toImage(n.x, n.z)) - Offset(0, n.h * upk * 1.0);
      final near = math.sqrt(math.pow(s.me.x - n.x, 2) + math.pow(s.me.z - n.z, 2)) < 6.5;
      final mark = marks['npc_${n.id}'];
      var y = head.dy - 8;
      if (near) {
        _chip(canvas, Offset(head.dx, y - 12), _npcName[n.id] ?? s._petNames[n.id] ?? n.id);
        y -= 34;
      }
      if (mark != null) _marker(canvas, Offset(head.dx, y - 4 * math.sin(s._t * 3.2).abs()), mark == 'handin');
    }
    canvas.restore();
  }

  /// A tile of the living picture over [area] ([dst]: where its crop lands); [front] >= 0 only what
  /// stands nearer than that.
  void _scene(Canvas canvas, ui.FragmentShader? sh, WalkTile t, Rect dst, Rect area, double front) {
    final img = t.pic!, mask = t.mask!, depth = t.depth!;
    if (sh == null) {
      if (front < 0) {
        canvas.save();
        canvas.clipRect(area);
        canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
        canvas.restore();
      }
      return;
    }
    sh
      ..setFloat(0, dst.left)
      ..setFloat(1, dst.top)
      ..setFloat(2, dst.width)
      ..setFloat(3, dst.height)
      ..setFloat(4, img.width.toDouble())
      ..setFloat(5, img.height.toDouble())
      ..setFloat(6, s._t % 600.0)
      ..setFloat(7, 1)
      ..setFloat(8, t.crop.left)
      ..setFloat(9, t.crop.top)
      ..setFloat(10, front)
      ..setImageSampler(0, img)
      ..setImageSampler(1, mask)
      ..setImageSampler(2, depth);
    canvas.drawRect(area, Paint()..shader = sh);
  }

  /// Your Evochi (and what it wears): its shade, the sun's shadow, the sprite. Returns where it drew.
  Rect _pet(Canvas canvas, Offset feet, double upk, WalkLayout l) {
    var g = feet; // (moves with a strike's lunge)
    final art = s._pet!;
    final me = s.me;
    final gait = art.gait(me.running && me.moving);
    var col = gait.col(me.phase, me.moving);
    final kp = upk * _evochiH / _sheetH; // dp per sheet px
    // a strike: the walk sheet posed in code (crouch, lunge, contact, recover)
    var sx = 1.0, sy = 1.0, lean = 0.0;
    final pn = s.pounce, node = pn.node;
    if (pn.active && node != null) {
      final (adv, px, py, ln, c) = pouncePose(pn.t, s._stage, hard: pn.tooHard);
      final d = Offset(node.x - me.x, node.z - me.z);
      final u = d.distance > 0 ? d / d.distance : Offset.zero;
      g = (g - (l.toImage(me.x, me.z, me.y) - l.toImage(me.x + u.dx * adv, me.z + u.dy * adv, me.y)) * (upk / l.ppu));
      sx = px;
      sy = py;
      lean = ln * (u.dx.abs() > 0.2 ? u.dx.sign : 0); // leaning into it, as the screen sees it
      col = c;
    }
    final tilt = s._t - pn.tiltAt;
    if (tilt >= 0 && tilt < 0.7) lean += 0.16 * math.sin(tilt / 0.7 * math.pi) * (me.dir <= 4 ? 1 : -1); // puzzled
    // the walk's own motion: a bounce a step, squash and stretch, a sway; a lean into starting off and
    // pulling up; a little settle on stopping
    final pose = gaitPose(me.phase, me.moving && !pn.active, run: me.running ? 1 : 0, reduced: s._reduced, heft: (s._stage.clamp(1, 3) - 1) / 2);
    final sideways = math.sin(me.dir * math.pi / 4); // facing east +1, west -1, as the screen sees it
    if (me.moving && !s._reduced) {
      final pace = me.running ? _runSpeed : _speed;
      lean += 0.11 * ((pace - me.speed) / pace).clamp(-1.0, 1.0) * sideways * (me.path.length > 1 || me.speed < pace * 0.9 ? 1 : 0);
      if (me.running) lean += 0.07 * sideways * (me.speed / _runSpeed).clamp(0.0, 1.0); // into the run
    }
    final since = s._t - me.stoppedAt;
    if (since >= 0 && since < 0.32 && !s._reduced) {
      final k = since / 0.32;
      sy *= 1 - 0.09 * math.sin(k * math.pi) * (1 - k);
      sx *= 1 + 0.07 * math.sin(k * math.pi) * (1 - k);
    }
    final src = Rect.fromLTWH(col * art.fw, me.dir * art.fh, art.fw, art.fh);
    // a soft pool of shade under the body (a touch smaller as it rises in a step)
    final shade = 1 - 8 * pose.bob;
    canvas.drawOval(Rect.fromCenter(center: g + Offset(art.fw * kp * 0.02, -kp * 4), width: art.fw * kp * 0.62 * shade, height: art.fw * kp * 0.17 * shade),
        Paint()
          ..color = const Color(0x3A16241F)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    _castShadow(canvas, gait.img, src, g, Offset(art.gx * kp, art.gy * kp), kp, l);
    final dst = Rect.fromLTWH(-art.gx * kp, -art.gy * kp, art.fw * kp, art.fh * kp);
    canvas.save();
    canvas.translate(g.dx, g.dy - pose.bob * art.fh * kp);
    canvas.rotate((gait.roll[col] + pose.roll) * math.pi / 180 * math.cos(me.dir * math.pi / 4) + lean);
    canvas.scale(sx * pose.sx, gait.squash[col] * sy * pose.sy);
    final p = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(gait.img, src, dst, p);
    final lift = col < gait.lift.length ? gait.lift[col] : 0.0;
    for (final w in art.wear.values) {
      canvas.drawImageRect(w, Rect.fromLTWH(me.dir * art.fw, 0, art.fw, art.fh), dst.shift(Offset(0, -lift * kp)), p);
    }
    canvas.restore();
    return dst.shift(g);
  }

  /// Chips, dust and sparks where they fly; nuggets popping out, then off to the satchel.
  void _paintBits(Canvas canvas, WalkLayout l, double upk, Offset Function(Offset) scr, MiningArt? art) {
    final now = s._t;
    final to = s.satchelPoint();
    for (final b in s._bits) {
      final age = now - b.born;
      final p = scr(l.toImage(b.x, b.z, b.y));
      switch (b.kind) {
        case 'dust':
          final a = (1 - age / b.life).clamp(0.0, 1.0);
          canvas.drawCircle(p, upk * b.size * (0.5 + age / b.life), Paint()
            ..color = b.color.withAlpha(((0.45 * a) * 255).round())
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        case 'spark':
          final a = (1 - age / b.life).clamp(0.0, 1.0);
          canvas.drawCircle(p, upk * b.size * (1 + a), Paint()..color = b.color.withAlpha(((a) * 255).round()));
        case 'chip':
          final a = age > b.life - 0.15 ? ((b.life - age) / 0.15).clamp(0.0, 1.0) : 1.0;
          final sz = upk * b.size;
          canvas.save();
          canvas.translate(p.dx, p.dy);
          canvas.rotate(age * 9 + b.size * 40);
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: sz, height: sz), Paint()..color = b.color.withAlpha(((a) * 255).round()));
          canvas.drawRect(Rect.fromCenter(center: Offset.zero, width: sz, height: sz), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0xFF3B2923).withAlpha(((0.7 * a) * 255).round()));
          canvas.restore();
        case 'nugget':
          final n = art?.ores[b.ore]?.nugget;
          if (n == null || art == null) continue;
          final unit = art.ores[b.ore]!.nuggetUnit;
          var at = p;
          var k = upk * unit;
          if (now >= b.flyAt && to != null) {
            b.from ??= p;
            final e = ((now - b.flyAt) / VillageWalkScreenState._flyTime).clamp(0.0, 1.0);
            final f = Curves.easeIn.transform(e);
            at = Offset.lerp(b.from, to, f)! - Offset(0, 60 * math.sin(e * math.pi));
            k *= 1 - 0.45 * f;
          }
          canvas.drawImageRect(n.img, Rect.fromLTWH(0, 0, n.img.width.toDouble(), n.img.height.toDouble()),
              Rect.fromLTWH(at.dx - n.ground.dx * k, at.dy - n.ground.dy * k, n.img.width * k, n.img.height * k), Paint()..filterQuality = FilterQuality.medium);
      }
    }
  }

  /// The sun's shadow of a standing sprite: each point above the ground lands where the sun's ray
  /// through it meets the ground, as the walking camera sees it (up and to the right, like the trees').
  void _castShadow(Canvas canvas, ui.Image img, Rect src, Offset g, Offset anchor, double sc, WalkLayout l) {
    final dx = l.sun[0], dy = l.sun[1], dz = l.sun[2];
    final ka = _shadowLong * (dx / -dy) / l.cosP;
    final kb = _shadowLong * (dz / -dy) * l.sinP / l.cosP;
    canvas.save();
    canvas.translate(g.dx, g.dy);
    // sprite (x, y) about its feet -> (x - ka y, -kb y)
    canvas.transform(Float64List.fromList([1, 0, 0, 0, -ka, -kb, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    canvas.drawImageRect(
        img,
        src,
        Rect.fromLTWH(-anchor.dx, -anchor.dy, src.width * sc, src.height * sc),
        Paint()
          ..filterQuality = FilterQuality.low
          ..colorFilter = const ColorFilter.mode(Color(0x5A1C2C2E), BlendMode.srcIn)
          ..imageFilter = ui.ImageFilter.blur(sigmaX: 1.6, sigmaY: 1.6));
    canvas.restore();
  }

  void _chip(Canvas canvas, Offset c, String text) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14, color: EvochiColor.ink)),
      textDirection: TextDirection.ltr,
    )..layout();
    final r = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: tp.width + 22, height: 26), const Radius.circular(13));
    canvas.drawRRect(r, Paint()..color = const Color(0xFFFFF8E8));
    canvas.drawRRect(r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xFFC9A78C));
    tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
  }

  void _marker(Canvas canvas, Offset c, bool handin) {
    final gold = handin ? const Color(0xFF7EC456) : const Color(0xFFF3C04E);
    final body = Rect.fromCenter(center: c - const Offset(0, 16), width: 28, height: 28);
    final path = Path()
      ..addOval(body)
      ..moveTo(c.dx - 6, c.dy - 5)
      ..lineTo(c.dx + 6, c.dy - 5)
      ..lineTo(c.dx, c.dy + 3)
      ..close();
    canvas.drawPath(path, Paint()..color = gold);
    canvas.drawOval(body, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = const Color(0xFF5A3714));
    final tp = TextPainter(
      text: TextSpan(text: handin ? '✓' : '!', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 18, color: EvochiColor.ink)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, body.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(_WalkPainter old) => old.s != s || old.marks != marks;
}


/// What each place is called on the map and its signs, and its icon (by map: ways out, people, spots).
const _placeNames = <String, Map<String, (String, String)>>{
  'village': {
    'trail': ('Old Trail', 'trail'),
    'home': ('Home', 'home'),
    'pip': ('Guild', 'mail'),
    'mira': ('Glasshouse', 'care'),
    'bram': ('Workshop', 'bell'),
    'lodge': ('Guild', 'mail'),
    'glasshouse': ('Glasshouse', 'care'),
    'workshop': ('Workshop', 'bell'),
    'waystone': ('Waystone', 'star'),
    'falls': ('Falls', 'aff_water'),
  },
  'home': {
    'nest': ('Nest', 'home'),
    'cottage': ('Cottage', 'bell'),
    'garden': ('Farm', 'skill_farming'),
    'nook': ('Hatching Nook', 'star'),
    'grove': ('Grove', 'paw'),
    'pond': ('Pond', 'aff_water'),
    'village': ('Sunlit Village', 'trail'),
  },
  'trail': {
    'village': ('Sunlit Village', 'home'),
    'mine': ('Mine', 'aff_stone'),
    'thicket': ('Sunlit Thicket', 'aff_nature'),
    'flint': ('Flint', 'shop'),
    'bridge': ('Falls', 'aff_water'),
  },
  'workshop': {
    'bram': ('Bram', 'bell'),
    'anvil': ('Anvil', 'aff_stone'),
    'forge': ('Forge', 'aff_ember'),
    'bench': ('Bench', 'gem'),
    'village': ('Square', 'trail'),
  },
  'glasshouse': {
    'mira': ('Mira', 'care'),
    'bench': ('Bench', 'skill_farming'),
    'beds': ('Beds', 'aff_nature'),
    'village': ('Square', 'trail'),
  },
  'lodge': {
    'pip': ('Pip', 'mail'),
    'alder': ('Alder', 'journey'),
    'board': ('Board', 'pin'),
    'table': ('Table', 'bell'),
    'fire': ('Fire', 'aff_ember'),
    'village': ('Square', 'trail'),
  },
  'cottage': {
    'kitchen': ('Kitchen', 'skill_cooking'),
    'apothecary': ('Apothecary', 'skill_alchemy'),
    'desk': ('Skills', 'journey'),
    'hearth': ('Hearth', 'aff_ember'),
    'bed': ('Bed', 'moon'),
    'home': ('Outside', 'home'),
  },
};

/// A parchment chip on the map (the Gear button; the satchel is its cousin in mining.dart).
class _HudChip extends StatelessWidget {
  const _HudChip({required this.label, required this.semantic, required this.onTap, required this.child});
  final String label, semantic;
  final VoidCallback onTap;
  final Widget child;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: semantic,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            height: 42,
            padding: const EdgeInsets.fromLTRB(6, 0, 12, 0),
            decoration: Kit.parchment(radius: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              child,
              const SizedBox(width: 4),
              ExcludeSemantics(child: Text(label, style: EvochiText.tag.copyWith(fontSize: 14.5, fontWeight: FontWeight.w900, color: KitColor.signInk))),
            ]),
          ),
        ),
      );
}

/// The corner minimap: the whole place small, what you can see outlined, you, the people and the ways out.
class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.s, required this.image, required this.onOpen});
  final VillageWalkScreenState s;
  final ui.Image image;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) {
    const w = 116.0;
    final h = (w * image.height / image.width).clamp(50.0, 116.0);
    return Semantics(
      button: true,
      label: 'Map',
      hint: 'Opens the map: tap a place to walk there',
      child: GestureDetector(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: Kit.parchment(radius: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ValueListenableBuilder<double>(
              valueListenable: s._frame,
              builder: (_, t, __) => CustomPaint(size: Size(w, h), painter: _MiniPainter(s, image, t)),
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniPainter extends CustomPainter {
  _MiniPainter(this.s, this.image, this.t);
  final VillageWalkScreenState s;
  final ui.Image image;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final l = s.lay;
    if (l == null) return;
    // the picture is wider than the box on the trail: keep you in the middle, sliding along it
    final fit = size.height / l.h;
    final pw = l.w * fit;
    final me = l.toImage(s.me.x, s.me.z, s.me.y) * fit;
    final dx = pw <= size.width ? (size.width - pw) / 2 : (size.width / 2 - me.dx).clamp(size.width - pw, 0.0);
    canvas.translate(dx, 0);
    canvas.drawImageRect(image, Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()), Rect.fromLTWH(0, 0, pw, size.height),
        Paint()..filterQuality = FilterQuality.medium);
    final v = s._viewRect();
    canvas.drawRect(Rect.fromLTRB(v.left * fit, v.top * fit, v.right * fit, v.bottom * fit), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = const Color(0xCCFFF6DC));
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = KitColor.woodInk;
    for (final e in l.exits.entries) {
      if (_placeNames[s.widget.map]?[e.key] == null) continue;
      final p = l.toImage(e.value.$1, e.value.$2) * fit;
      canvas.drawCircle(p, 4, Paint()..color = KitColor.goldRing);
      canvas.drawCircle(p, 4, ring);
    }
    for (final n in s._npcs) {
      final p = l.toImage(n.x, n.z) * fit;
      canvas.drawCircle(p, 2.6, Paint()..color = const Color(0xFFFFF3E0));
      canvas.drawCircle(p, 2.6, ring..strokeWidth = 1);
    }
    final pulse = 1 + 0.25 * math.sin(t * 4);
    canvas.drawCircle(me, 5.5 * pulse, Paint()..color = const Color(0x55FFFFFF));
    canvas.drawCircle(me, 4, Paint()..color = EvochiColor.primary);
    canvas.drawCircle(me, 4, ring..strokeWidth = 1.8);
  }

  @override
  bool shouldRepaint(_MiniPainter old) => true;
}

/// The map window: the place in a carved frame, you on it, a small pin for each place to walk to, and
/// the places named in a row beneath (tap either).
class _MapWindow extends StatelessWidget {
  const _MapWindow({required this.title, required this.image, required this.picture, required this.places, required this.me});
  final String title;
  final ui.Image image;
  final Size picture;
  final List<(String, String, String, Offset)> places; // id, name, icon, where (picture px)
  final Offset me;
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: WoodPlaque(child: Text(title, style: WoodPlaque.text(EvochiText.section)))),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (_, b) {
          final w = b.maxWidth, h = w * picture.height / picture.width, k = w / picture.width;
          return SizedBox(
            width: w,
            height: h,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: KitColor.woodEdge, width: 2)),
                  child: ClipRRect(borderRadius: BorderRadius.circular(8), child: RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.medium)),
                ),
              ),
              for (final (id, name, icon, at) in places)
                Positioned(
                  left: at.dx * k - 15,
                  top: at.dy * k - 34,
                  child: Semantics(
                    button: true,
                    label: 'Walk to $name',
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(id),
                      child: _Pin(icon: icon),
                    ),
                  ),
                ),
              Positioned(
                left: me.dx * k - 7,
                top: me.dy * k - 7,
                child: Semantics(
                  label: 'You are here',
                  child: Container(
                    width: 14,
                    height: 14,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: EvochiColor.primary,
                      border: Border.all(color: KitColor.woodInk, width: 2),
                      boxShadow: const [BoxShadow(color: Color(0x88FFE3A0), blurRadius: 8, spreadRadius: 1)],
                    ),
                  ),
                ),
              ),
            ]),
          );
        }),
        const SizedBox(height: 10),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (id, name, icon, _) in places)
              Semantics(
                button: true,
                label: 'Walk to $name',
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(id),
                  child: Container(
                    height: 30,
                    padding: const EdgeInsets.fromLTRB(5, 0, 9, 0),
                    decoration: Kit.parchment(radius: 9, depth: 2, drop: false),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      VoxelIcon(icon, size: 18),
                      const SizedBox(width: 4),
                      ExcludeSemantics(child: Text(name, style: EvochiText.tag.copyWith(fontSize: 12, fontWeight: FontWeight.w800, color: KitColor.signInk))),
                    ]),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Tap a place and your Evochi walks there.', textAlign: TextAlign.center, style: EvochiText.caption),
        const SizedBox(height: 8),
        Center(child: EvochiButton(label: 'Close', tone: ButtonTone.cream, small: true, expand: false, onPressed: () => Navigator.of(context).pop())),
      ]);
}

/// A map pin: a round parchment badge with the place's icon, on a short point.
class _Pin extends StatelessWidget {
  const _Pin({required this.icon});
  final String icon;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 30,
        height: 36,
        child: CustomPaint(
          painter: _PinPainter(),
          child: Padding(padding: const EdgeInsets.fromLTRB(4, 4, 4, 10), child: VoxelIcon(icon, size: 22)),
        ),
      );
}

class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, 15);
    final path = Path()
      ..addOval(Rect.fromCircle(center: c, radius: 14))
      ..moveTo(c.dx - 6, c.dy + 11)
      ..lineTo(c.dx, size.height)
      ..lineTo(c.dx + 6, c.dy + 11)
      ..close();
    canvas.drawPath(path.shift(const Offset(0, 2)), Paint()..color = const Color(0x55000000));
    canvas.drawPath(path, Paint()..color = const Color(0xFFFFF6E4));
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = KitColor.woodEdge);
  }

  @override
  bool shouldRepaint(_PinPainter old) => false;
}
