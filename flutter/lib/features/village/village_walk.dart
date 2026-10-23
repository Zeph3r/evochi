// The walkable Sunlit Village, a first playable piece: the plaza, the bridge and the Trail Guild.
//
// One picture of the village at the walking camera's detail (tools/art/village_walk_slice.py) drawn
// through shaders/village_fx.frag, so it lives like the other scenes (water, trees, grass, smoke,
// glows, leaves and motes); a walk grid; your Evochi walking where you tap, drawn 1.2x its true size
// with the sun's shadow; and the villagers standing outside in the classic look. Tap one and your
// Evochi walks over, turns to them, and the conversation opens. No labels on the buildings: a name
// shows when you walk up, a "!" marks who has something for you.
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
import '../../game/story/story.dart' as q;
import '../shared/ambience.dart';
import '../shared/live_scene.dart';
import '../shared/widgets.dart';
import '../wilds/wilds_art.dart';
import 'story_widgets.dart';
import 'village_screen.dart';

const _layoutAsset = 'assets/config/village_walk.json';
const _evochiH = 3.4 * 1.2; // world units: an Elder, drawn 1.2x in the village (the Wilds keep theirs)
const _sheetH = 202.0; // an Elder's height on its walk sheet, px
const _npcH = {'pip': 3.4, 'alder': 3.8, 'bram': 4.0, 'mira': 4.2};
const _npcName = {'pip': 'Pip', 'alder': 'Alder', 'bram': 'Bram', 'mira': 'Mira'};
const _unitsAcross = 18.0; // the walking camera: 18 world units across the screen (2x the concept's)
const _speed = 5.0; // world units a second
const _frontBias = 1.0; // world units: what is this much nearer than a character's feet covers it (half a body)
const _shadowLong = 2.0; // characters' shadows drawn this much longer than the sun makes them

/// Open the walkable village (the preview).
void openVillageWalk(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Ambience('village', child: VillageWalkScreen())));

/// The piece of village: its picture, camera and walk grid (assets/config/village_walk.json).
class WalkLayout {
  WalkLayout(Map<String, dynamic> j)
      : image = j['image'] as String,
        depth = j['depth'] as String,
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
        npcs = [
          for (final n in (j['npcs'] as List).cast<Map>()) (n['id'] as String, (n['x'] as num).toDouble(), (n['z'] as num).toDouble(), n['place'] as String)
        ],
        spawn = Offset(((j['spawn'] as List)[0] as num).toDouble(), ((j['spawn'] as List)[1] as num).toDouble()),
        spots = {
          for (final e in (j['spots'] as Map).entries) e.key as String: Offset(((e.value as List)[0] as num).toDouble(), ((e.value as List)[1] as num).toDouble())
        },
        sun = [for (final v in j['sun'] as List) (v as num).toDouble()] {
    final rowsData = ((j['grid'] as Map)['walk'] as List).cast<String>();
    walk = Uint8List(cols * rows);
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        walk[r * cols + c] = rowsData[r].codeUnitAt(c) == 49 ? 1 : 0;
      }
    }
  }
  final String image, depth;
  final double w, h, ppu, cx, cz, sinP, cosP, z0, z1, gx0, gz0, cell;
  final int cols, rows;
  late final Uint8List walk;
  final List<(String, double, double, String)> npcs; // id, x, z, place
  final Offset spawn;
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
  int dir = 4; // S SE E NE N NW W SW
  bool moving = false;
  double phase = 0;
  List<Offset> path = const [];
  String? talkTo; // a villager to talk to on arrival
  double wait = -1; // seconds until that conversation opens

  static int dirOf(double dx, double dz) => ((math.atan2(dx, dz) / (math.pi / 4)).round() % 8 + 8) % 8;
}

class _Npc {
  _Npc(this.id, this.x, this.z, this.place, this.img, this.ground, this.top);
  final String id, place;
  final double x, z;
  final ui.Image img;
  final Offset ground, top;
}

class VillageWalkScreen extends StatefulWidget {
  const VillageWalkScreen({super.key});

  /// The one on screen (the recorder drives it).
  static VillageWalkScreenState? current;

  @override
  State<VillageWalkScreen> createState() => VillageWalkScreenState();
}

class VillageWalkScreenState extends State<VillageWalkScreen> with SingleTickerProviderStateMixin {
  WalkLayout? lay;
  ui.Image? _img, _mask, _depth;
  final _shaders = <ui.FragmentShader>[];
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
  (double, double, double)? _mark; // where you tapped (x, z) and when: a ring on the ground

  /// Loaded and drawn (the recorder waits for this).
  bool get ready => lay != null && _img != null && _pet != null;

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
    final l = WalkLayout((jsonDecode(await rootBundle.loadString(_layoutAsset)) as Map).cast<String, dynamic>());
    final fx = SceneFx.of(l.image);
    final r = await Future.wait<Object?>([
      _image(l.image),
      fx == null ? Future.value(null) : _image(fx.mask),
      _image(l.depth),
      WalkerArt.load('s0${(pet?.stage ?? 1).clamp(1, 3)}', pet?.paletteId ?? 'amber', wearing: pet?.equipped.values.toList() ?? const []),
      SceneFx.program(),
      ui.FragmentProgram.fromAsset('shaders/village_fx.frag'),
    ]);
    final npcs = <_Npc>[];
    for (final (id, x, z, place) in l.npcs) {
      final key = 'npc_$id';
      npcs.add(_Npc(id, x, z, place, await _image(villageArt.npc(key, 'neutral', true)), villageArt.npcGround(key), villageArt.npcTop(key)));
    }
    if (!mounted) return;
    final prog = r[5] as ui.FragmentProgram;
    setState(() {
      lay = l;
      _fx = fx;
      _img = r[0] as ui.Image;
      _mask = r[1] as ui.Image?;
      _depth = r[2] as ui.Image;
      _pet = r[3] as WalkerArt;
      _npcs.addAll(npcs);
      for (var i = 0; i < 2 + npcs.length; i++) {
        _shaders.add(prog.fragmentShader());
      }
      me
        ..x = l.spawn.dx
        ..z = l.spawn.dy;
    });
    _ticker = createTicker(_tick)..start();
  }

  @override
  void dispose() {
    if (VillageWalkScreen.current == this) VillageWalkScreen.current = null;
    _ticker?.dispose();
    for (final s in _shaders) {
      s.dispose();
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
      var step = _speed * dt;
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
        me.phase += s / _cycle;
        step -= s;
        if (s >= d) me.path = me.path.sublist(1);
      }
      me.moving = me.path.isNotEmpty;
      if (!me.moving) _arrived();
    }
    if (me.wait > 0) {
      me.wait -= dt;
      if (me.wait <= 0) _openTalk();
    }
    _follow(dt);
    _frame.value = t;
  }

  /// World units per walk cycle: the sheet's stride, drawn at the village's size.
  double get _cycle => _pet!.gait(false).cycle * walkerDrawScale * _evochiH / _sheetH;

  void _follow(double dt) {
    final l = lay!;
    if (_view.isEmpty) return;
    final k = _k;
    final p = l.toImage(me.x, me.z);
    // your Evochi a little below the middle, as in the Wilds
    var want = Offset(p.dx, p.dy - 0.08 * _view.height / k);
    final hw = _view.width / 2 / k, hh = _view.height / 2 / k;
    want = Offset(want.dx.clamp(hw, math.max(hw, l.w - hw)), want.dy.clamp(hh, math.max(hh, l.h - hh)));
    _cam = _cam == null ? want : Offset.lerp(_cam, want, math.min(1.0, dt * 5))!;
  }

  void _arrived() {
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
    Navigator.of(context)
        .push(MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'place'),
            builder: (_) => Ambience(villagePlace(n.place), child: PlaceScreen(placeId: n.place, npc: 'npc_${n.id}'))))
        .then((_) {
      if (mounted) setState(() => _talking = false);
    });
  }

  /// Walk to a ground point.
  void walkTo(double x, double z) {
    final l = lay;
    if (l == null || _talking) return;
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
    final k = _k;
    final p = cam + (local - _view.center(Offset.zero)) / k;
    // a villager first (tap their sprite)
    for (final n in _npcs.reversed) {
      if (_npcRect(n).inflate(6).contains(p)) return talkTo(n.id);
    }
    final g = l.toGround(p);
    walkTo(g.dx, g.dy);
  }

  /// A villager's sprite, in picture px.
  Rect _npcRect(_Npc n) {
    final l = lay!;
    final s = _npcH[n.id]! * l.ppu / (n.ground.dy - n.top.dy);
    final g = l.toImage(n.x, n.z);
    return Rect.fromLTWH(g.dx - n.ground.dx * s, g.dy - n.ground.dy * s, n.img.width * s, n.img.height * s);
  }

  // ------------------------------------------------------------------------------------ the screen
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final marks = q.npcMarkers(c.state);
    return Scaffold(
      backgroundColor: const Color(0xFF86B566),
      body: Column(children: [
        Container(
          color: EvochiColor.panel,
          child: SafeArea(
            bottom: false,
            child: PlaceHeader(title: 'Sunlit Village', short: 'Village', backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
          ),
        ),
        Expanded(
          child: LayoutBuilder(builder: (ctx, b) {
            final size = Size(b.maxWidth, b.maxHeight);
            if (size != _view) {
              _view = size;
              if (lay != null) _cam = null;
            }
            if (!ready) return const Center(child: CircularProgressIndicator());
            if (_cam == null) _follow(1);
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _tap(d.localPosition),
              child: CustomPaint(size: size, painter: _WalkPainter(this, marks)),
            );
          }),
        ),
        _QuickTravel(onPick: _quick),
      ]),
    );
  }

  void _quick(String id) {
    final l = lay;
    if (l == null) return;
    switch (id) {
      case 'lodge':
        talkTo('pip');
      case 'waystone':
        final w = l.spots['waystone']!;
        walkTo(w.dx, w.dy);
      default:
        // a room: straight in (Back returns here)
        Navigator.of(context).push(MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'place'), builder: (_) => Ambience(villagePlace(id), child: PlaceScreen(placeId: id))));
    }
  }
}

/// The bottom row: the places, a tap away (the Guild and the Waystone are a walk; the others open).
class _QuickTravel extends StatelessWidget {
  const _QuickTravel({required this.onPick});
  final void Function(String) onPick;
  @override
  Widget build(BuildContext context) {
    const items = [('lodge', 'mail', 'Guild'), ('glasshouse', 'care', 'Glasshouse'), ('workshop', 'bell', 'Workshop'), ('waystone', 'star', 'Waystone')];
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF6B4528),
        border: Border(top: BorderSide(color: Color(0xFF3E2513), width: 3)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: Row(children: [
            for (final (id, icon, label) in items)
              Expanded(
                child: Semantics(
                  button: true,
                  label: label,
                  child: GestureDetector(
                    onTap: () => onPick(id),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Container(
                        width: 50,
                        height: 50,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE9C793),
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF4A2A14), width: 2.5),
                        ),
                        child: VoxelIcon(icon, size: 30),
                      ),
                      const SizedBox(height: 4),
                      ExcludeSemantics(
                        child: Text(label,
                            style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 11.5, color: Color(0xFFFFF0DC))),
                      ),
                    ]),
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
    final l = s.lay, cam = s._cam, img = s._img;
    if (l == null || cam == null || img == null) return;
    final k = s._k;
    final mid = size.center(Offset.zero);
    Offset scr(Offset p) => (p - cam) * k + mid;
    final whole = Rect.fromLTWH(scr(Offset.zero).dx, scr(Offset.zero).dy, l.w * k, l.h * k);
    final view = Offset.zero & size;
    canvas.save();
    canvas.clipRect(view);
    // the picture
    var si = 0;
    _scene(canvas, s._shaders.isEmpty ? null : s._shaders[si++], whole, view, -1);
    // where you tapped: a ring on the ground that opens and fades
    final mk = s._mark;
    if (mk != null && s._t - mk.$3 < 0.7) {
      final a = (s._t - mk.$3) / 0.7;
      final c = scr(l.toImage(mk.$1, mk.$2));
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
      items.add((n.z, () {
        final r = s._npcRect(n);
        final g = scr(l.toImage(n.x, n.z));
        final sc = upk * _npcH[n.id]! / (n.ground.dy - n.top.dy);
        _castShadow(canvas, n.img, Rect.fromLTWH(0, 0, n.img.width.toDouble(), n.img.height.toDouble()), g, n.ground * sc, sc, l);
        final breathe = 1 + 0.012 * math.sin(s._t * 2.3 + n.x);
        canvas.save();
        canvas.translate(g.dx, g.dy);
        canvas.scale(2 - breathe, breathe);
        canvas.drawImageRect(n.img, Rect.fromLTWH(0, 0, n.img.width.toDouble(), n.img.height.toDouble()),
            Rect.fromLTWH(-n.ground.dx * sc, -n.ground.dy * sc, n.img.width * sc, n.img.height * sc), Paint()..filterQuality = FilterQuality.medium);
        canvas.restore();
        final sr = Rect.fromPoints(scr(r.topLeft), scr(r.bottomRight));
        if (si < s._shaders.length) _scene(canvas, s._shaders[si++], whole, sr.inflate(2), l.depthQ(n.z + _frontBias));
      }));
    }
    items.add((s.me.z, () {
      final rect = _pet(canvas, scr(l.toImage(s.me.x, s.me.z)), upk, l);
      if (si < s._shaders.length) _scene(canvas, s._shaders[si++], whole, rect.inflate(2), l.depthQ(s.me.z + _frontBias));
    }));
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final (_, draw) in items) {
      draw();
    }
    // the air: glows, smoke, leaves, motes
    final fx = s._fx;
    if (fx != null) {
      canvas.save();
      canvas.translate(whole.left, whole.top);
      canvas.scale(k, k);
      SceneFx.paintEmitters(canvas, fx, s._t);
      canvas.restore();
    }
    // a "!" over whoever has something for you; a name when you are close
    for (final n in s._npcs) {
      final head = scr(l.toImage(n.x, n.z)) - Offset(0, _npcH[n.id]! * upk * 1.0);
      final near = math.sqrt(math.pow(s.me.x - n.x, 2) + math.pow(s.me.z - n.z, 2)) < 6.5;
      final mark = marks['npc_${n.id}'];
      var y = head.dy - 8;
      if (near) {
        _chip(canvas, Offset(head.dx, y - 12), _npcName[n.id] ?? n.id);
        y -= 34;
      }
      if (mark != null) _marker(canvas, Offset(head.dx, y - 4 * math.sin(s._t * 3.2).abs()), mark == 'handin');
    }
    canvas.restore();
  }

  /// The living picture over [area]; [front] >= 0 only what stands nearer than that.
  void _scene(Canvas canvas, ui.FragmentShader? sh, Rect whole, Rect area, double front) {
    final img = s._img!, mask = s._mask, depth = s._depth!;
    if (sh == null || mask == null) {
      if (front < 0) canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), whole, Paint()..filterQuality = FilterQuality.medium);
      return;
    }
    sh
      ..setFloat(0, whole.left)
      ..setFloat(1, whole.top)
      ..setFloat(2, whole.width)
      ..setFloat(3, whole.height)
      ..setFloat(4, img.width.toDouble())
      ..setFloat(5, img.height.toDouble())
      ..setFloat(6, s._t % 600.0)
      ..setFloat(7, 1)
      ..setFloat(8, 0)
      ..setFloat(9, 0)
      ..setFloat(10, front)
      ..setImageSampler(0, img)
      ..setImageSampler(1, mask)
      ..setImageSampler(2, depth);
    canvas.drawRect(area, Paint()..shader = sh);
  }

  /// Your Evochi (and what it wears): its shade, the sun's shadow, the sprite. Returns where it drew.
  Rect _pet(Canvas canvas, Offset g, double upk, WalkLayout l) {
    final art = s._pet!;
    final me = s.me;
    final gait = art.gait(false);
    final col = me.moving ? 1 + (me.phase * 8).floor() % 8 : 0;
    final kp = upk * _evochiH / _sheetH; // dp per sheet px
    final src = Rect.fromLTWH(col * art.fw, me.dir * art.fh, art.fw, art.fh);
    // a soft pool of shade under the body
    canvas.drawOval(Rect.fromCenter(center: g + Offset(art.fw * kp * 0.02, -kp * 4), width: art.fw * kp * 0.62, height: art.fw * kp * 0.17),
        Paint()
          ..color = const Color(0x3A16241F)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4));
    _castShadow(canvas, gait.img, src, g, Offset(art.gx * kp, art.gy * kp), kp, l);
    final dst = Rect.fromLTWH(-art.gx * kp, -art.gy * kp, art.fw * kp, art.fh * kp);
    canvas.save();
    canvas.translate(g.dx, g.dy);
    canvas.rotate(gait.roll[col] * math.pi / 180 * math.cos(me.dir * math.pi / 4));
    canvas.scale(1, gait.squash[col]);
    final p = Paint()..filterQuality = FilterQuality.medium;
    canvas.drawImageRect(gait.img, src, dst, p);
    final lift = col < gait.lift.length ? gait.lift[col] : 0.0;
    for (final w in art.wear.values) {
      canvas.drawImageRect(w, Rect.fromLTWH(me.dir * art.fw, 0, art.fw, art.fh), dst.shift(Offset(0, -lift * kp)), p);
    }
    canvas.restore();
    return dst.shift(g);
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
