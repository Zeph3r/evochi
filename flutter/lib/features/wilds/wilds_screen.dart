// The Lumen Wilds: a floor you explore with your Evochi (F1, the Sunlit Thicket). Scene first: the map
// fills the screen, the five tabs are gone, and the HUD is what the design asks for: your party (top
// left), a minimap (top right, tap for the whole floor), an Interact button when something is near and a
// Run button (bottom right).
//
// Moving: drag anywhere (a joystick appears under your finger; push it far to run), tap a spot to walk
// there (far spots you run to), or WASD / the arrow keys, Shift to run. Run toggles running for touch.
// Your Evochi walks or runs in 8 directions in its own stage and palette, wearing what it has on.
// Trees, rocks, logs and water block the way; everything is drawn back to front, so you pass behind a
// tree and in front of a rock.
//
// Sher waits at his camp by the fire. Talk to him and he offers to join your party: an NPC ally (the
// Guild Raids design: he never replaces your Evochi). Then he follows your path, a step to the side.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../shared/ambience.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../trails/trails_widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'wilds_art.dart';

class _Walker {
  _Walker(this.art, this.x, this.z);
  final WalkerArt art;
  double x, z;
  int dir = 0; // index into S, SE, E, NE, N, NW, W, SW
  double phase = 0; // 0..1 through the 8-frame cycle
  bool moving = false;
  bool running = false;

  void face(double vx, double vz) {
    final a = math.atan2(vx, vz) * 180 / math.pi; // 0 = toward you (S), 90 = right (E)
    dir = (((a / 45).round()) % 8 + 8) % 8;
  }

  WildsGait get gait => art.gait(running && moving);
  int get col => moving ? 1 + (phase * 8).floor() % 8 : 0;
}

class WildsScreen extends StatefulWidget {
  const WildsScreen({super.key, this.mapId = 'thicket'});
  final String mapId;
  @override
  State<WildsScreen> createState() => _WildsScreenState();
}

class _WildsScreenState extends State<WildsScreen> with SingleTickerProviderStateMixin {
  WildsMap? _map;
  _Walker? _pet, _sher;
  List<Offset> _sherRoute = const [];
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _t = 0; // seconds, for the fire and glints
  final _focus = FocusNode();
  final _keys = <LogicalKeyboardKey>{};
  Offset? _stickOrigin, _stick;
  Offset? _target; // tap-to-move (world x, z)
  bool _targetRun = false;
  bool _runToggle = false;
  Size _view = Size.zero;
  double _u = 2.7; // screen px per world unit
  Offset _cam = Offset.zero; // top-left of the view, in screen px of the scaled ground
  bool _party = false;
  String? _card; // a spot id, or 'sher' (his offer), or 'map'
  MapSpot? _near; // something you can interact with
  bool _nearSher = false;
  final _crumbs = <Offset>[];
  int _leg = 0;
  double _pause = 2.0;
  String? _bubble;
  double _bubbleT = 0;
  int _line = 0;
  double _hintT = 7;
  final _repaint = ValueNotifier<int>(0);

  static const _walk = 26.0, _run = 52.0, _sherWalk = 15.0;

  @override
  void initState() {
    super.initState();
    final c = context.read<GameController>();
    final pet = c.state.pet;
    final key = 's0${(pet?.stage ?? 1).clamp(1, 3)}';
    final palette = pet?.paletteId ?? 'amber';
    final wearing = pet?.equipped.values.toList() ?? const <String>[];
    Future.wait([
      WildsMap.load(widget.mapId),
      WalkerArt.load(key, palette, wearing: wearing),
      WalkerArt.load('sher', 'sher'),
    ]).then((r) {
      if (!mounted) return;
      final m = r[0] as WildsMap;
      final (sx, sz, sdir) = m.start;
      setState(() {
        _map = m;
        _pet = _Walker(r[1] as WalkerArt, sx, sz)..dir = sdir;
        final s = m.sher;
        if (s != null) {
          _sher = _Walker(r[2] as WalkerArt, s.$1, s.$2);
          _sherRoute = s.$3;
        }
      });
      _ticker.start();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _focus.dispose();
    _repaint.dispose();
    super.dispose();
  }

  // ---- mapping: world (x, z) -> ground image px -> screen
  Offset _toGround(double x, double z) {
    final m = _map!;
    return m.origin + Offset(x * m.scale, z * m.sinP * m.scale);
  }

  double get _gk => _u / _map!.scale; // screen px per ground px

  Offset _toScreen(double x, double z) => _toGround(x, z) * _gk - _cam;

  Offset _toWorld(Offset screen) {
    final m = _map!;
    final p = (screen + _cam) / _gk - m.origin;
    return Offset(p.dx / m.scale, p.dy / (m.sinP * m.scale));
  }

  // ---- the loop
  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : math.min(0.05, (now - _last).inMicroseconds / 1e6);
    _last = now;
    _t += dt;
    final m = _map, pet = _pet;
    if (m == null || pet == null || _view == Size.zero) return;
    final sher = _sher;
    // input: keys, then the joystick, then a tap target
    var vx = 0.0, vz = 0.0;
    bool k(LogicalKeyboardKey a, LogicalKeyboardKey b) => _keys.contains(a) || _keys.contains(b);
    if (k(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA)) vx -= 1;
    if (k(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD)) vx += 1;
    if (k(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW)) vz -= 1;
    if (k(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS)) vz += 1;
    var speed = 1.0;
    var run = _runToggle || k(LogicalKeyboardKey.shiftLeft, LogicalKeyboardKey.shiftRight);
    if (vx != 0 || vz != 0) {
      _target = null;
    } else if (_stickOrigin != null && _stick != null) {
      final d = _stick! - _stickOrigin!;
      if (d.distance > 8) {
        vx = d.dx;
        vz = d.dy / m.sinP; // the screen's up is foreshortened north
        speed = (d.distance / 40).clamp(0.4, 1.0);
        if (d.distance > 52) run = true; // pushed to the rim
      }
    } else if (_target != null) {
      vx = _target!.dx - pet.x;
      vz = _target!.dy - pet.z;
      run = run || _targetRun;
      if (math.sqrt(vx * vx + vz * vz) < 3) {
        _target = null;
        vx = vz = 0;
      }
    }
    if (_card != null) vx = vz = 0;
    pet.running = run;
    _move(pet, vx, vz, (run ? _run : _walk) * speed, dt, [if (sher != null) sher]);
    if (_crumbs.isEmpty || (Offset(pet.x, pet.z) - _crumbs.last).distance > 3) {
      _crumbs.add(Offset(pet.x, pet.z));
      if (_crumbs.length > 80) _crumbs.removeAt(0);
    }
    if (sher != null) _sherTick(sher, pet, dt);
    if (_bubble != null) {
      _bubbleT -= dt;
      if (_bubbleT <= 0) _bubble = null;
    }
    // what's near enough to interact with
    MapSpot? near;
    var best = double.infinity;
    for (final s in m.spots) {
      final d = math.sqrt(math.pow(pet.x - s.x, 2) + math.pow(pet.z - s.z, 2));
      if (d < s.r + pet.art.radius && d < best) {
        best = d;
        near = s;
      }
    }
    final nearSher = sher != null && math.sqrt(math.pow(pet.x - sher.x, 2) + math.pow(pet.z - sher.z, 2)) < 52;
    if (near?.id != _near?.id || nearSher != _nearSher) {
      setState(() {
        _near = near;
        _nearSher = nearSher;
      });
    }
    if (_hintT > 0) {
      final before = _hintT;
      _hintT -= dt;
      if ((before > 1) != (_hintT > 1) || _hintT <= 0) setState(() {});
    }
    // the camera follows your Evochi, kept inside the ground
    final p = _toGround(pet.x, pet.z) * _gk;
    final gw = m.groundW * _gk, gh = m.groundH * _gk;
    final want = Offset((p.dx - _view.width / 2).clamp(0.0, math.max(0.0, gw - _view.width)),
        (p.dy - _view.height * 0.58).clamp(0.0, math.max(0.0, gh - _view.height)));
    _cam = _last == Duration.zero ? want : Offset.lerp(_cam, want, math.min(1.0, dt * 6))!;
    _repaint.value++;
  }

  void _sherTick(_Walker sher, _Walker pet, double dt) {
    final gap = math.sqrt(math.pow(pet.x - sher.x, 2) + math.pow(pet.z - sher.z, 2));
    if (_party) {
      if (gap > 40) {
        // a spot about 34 units back along your path, a step off to its side
        var t = Offset(pet.x, pet.z);
        var acc = 0.0;
        var side = Offset.zero;
        for (var i = _crumbs.length - 1; i >= 0; i--) {
          final step = _crumbs[i] - t;
          acc += step.distance;
          if (step.distance > 0) side = Offset(-step.dy, step.dx) / step.distance;
          t = _crumbs[i];
          if (acc >= 34) break;
        }
        t += side * 12;
        sher.running = gap > 70;
        _move(sher, t.dx - sher.x, t.dy - sher.z, gap > 70 ? _run * 1.1 : _walk, dt, [pet]);
      } else {
        sher.moving = false;
        if (pet.moving) sher.dir = pet.dir;
      }
      return;
    }
    if (gap < 64) {
      // you're here: he stops and turns to you
      sher.moving = false;
      sher.face(pet.x - sher.x, pet.z - sher.z);
      return;
    }
    if (_pause > 0) {
      _pause -= dt;
      sher.moving = false;
      return;
    }
    if (_sherRoute.isEmpty) return;
    final t = _sherRoute[_leg % _sherRoute.length];
    final dx = t.dx - sher.x, dz = t.dy - sher.z;
    if (math.sqrt(dx * dx + dz * dz) < 2) {
      _leg++;
      _pause = 2.5 + (_leg % 3) * 1.5;
      sher.face(_map!.fx.isEmpty ? 0 : _map!.fx.first.$1 - sher.x, _map!.fx.isEmpty ? 1 : _map!.fx.first.$2 - sher.z);
    } else {
      sher.running = false;
      _move(sher, dx, dz, _sherWalk, dt, [pet]);
    }
  }

  void _move(_Walker w, double vx, double vz, double speed, double dt, List<_Walker> others) {
    final len = math.sqrt(vx * vx + vz * vz);
    if (len < 1e-6 || speed <= 0) {
      w.moving = false;
      return;
    }
    final m = _map!;
    vx /= len;
    vz /= len;
    w.face(vx, vz);
    var nx = w.x + vx * speed * dt, nz = w.z + vz * speed * dt;
    final r = w.art.radius;
    // slide round trees, rocks, logs and the other walker
    for (final (ox, oz, br) in m.blocks) {
      final dx = nx - ox, dz = nz - oz;
      if (dx.abs() > br + r || dz.abs() > br + r) continue;
      final d = math.sqrt(dx * dx + dz * dz);
      if (d < br + r && d > 1e-6) {
        nx = ox + dx / d * (br + r);
        nz = oz + dz / d * (br + r);
      }
    }
    for (final o in others) {
      final dx = nx - o.x, dz = nz - o.z, rr = o.art.radius + r;
      final d = math.sqrt(dx * dx + dz * dz);
      if (d < rr && d > 1e-6) {
        nx = o.x + dx / d * rr;
        nz = o.z + dz / d * rr;
      }
    }
    // water: try the move, else slide along one axis
    bool wet(double x, double z) => m.blocked(x, z) || m.blocked(x + r * 0.6, z) || m.blocked(x - r * 0.6, z) || m.blocked(x, z + r * 0.5) || m.blocked(x, z - r * 0.5);
    if (wet(nx, nz)) {
      if (!wet(nx, w.z)) {
        nz = w.z;
      } else if (!wet(w.x, nz)) {
        nx = w.x;
      } else {
        nx = w.x;
        nz = w.z;
      }
    }
    final b = m.bounds;
    nx = nx.clamp(b.left, b.right);
    nz = nz.clamp(b.top, b.bottom);
    final moved = math.sqrt(math.pow(nx - w.x, 2) + math.pow(nz - w.z, 2));
    w.x = nx;
    w.z = nz;
    w.moving = moved > speed * dt * 0.2;
    if (w.moving) w.phase = (w.phase + moved / w.gait.cycle) % 1.0;
  }

  // ---- taps and actions
  void _tap(Offset pos) {
    final m = _map, sher = _sher, pet = _pet;
    if (m == null || pet == null || _card != null) return;
    if (sher != null) {
      final s = _toScreen(sher.x, sher.z);
      final k = _u / walkerDrawScale;
      final r = Rect.fromLTWH(s.dx - sher.art.gx * k * 0.6, s.dy - sher.art.gy * k * 0.9, sher.art.fw * k * 0.6, sher.art.gy * k * 0.95);
      if (r.contains(pos)) {
        _talkToSher();
        return;
      }
    }
    final w = _toWorld(pos);
    _target = w;
    _targetRun = (w - Offset(pet.x, pet.z)).distance > 140;
  }

  void _talkToSher() {
    context.read<GameController>().audio.play('pet_chirp', volume: 0.5);
    setState(() {
      if (_party) {
        const lines = ['Lead the way!', 'I\'ve got your back.', 'Smell that? Rain later.', 'Stay close to the path.', 'The stream\'s cold. Bridge is drier.'];
        _bubble = lines[_line++ % lines.length];
        _bubbleT = 2.6;
      } else {
        _card = 'sher';
        _target = null;
      }
    });
  }

  void _interact() {
    if (_nearSher && !_party) {
      _talkToSher();
      return;
    }
    final s = _near;
    if (s == null) {
      if (_nearSher) _talkToSher();
      return;
    }
    context.read<GameController>().audio.play('ui_tap', volume: 0.4);
    setState(() {
      _card = s.id;
      _target = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _map;
    final rm = MediaQuery.of(context).disableAnimations;
    final mq = MediaQuery.of(context);
    return Ambience(
      'village',
      child: Scaffold(
        backgroundColor: const Color(0xFF2E4A24),
        body: LayoutBuilder(builder: (ctx, b) {
          _view = Size(b.maxWidth, b.maxHeight);
          _u = (b.maxWidth / 145).clamp(2.4, 3.6);
          if (m != null) _u = math.max(_u, b.maxWidth / (m.groundW / m.scale));
          final card = _card;
          return Focus(
            focusNode: _focus,
            autofocus: true,
            onKeyEvent: (_, e) {
              if (e is KeyDownEvent) {
                _keys.add(e.logicalKey);
                if (e.logicalKey == LogicalKeyboardKey.keyE || e.logicalKey == LogicalKeyboardKey.enter) _interact();
                if (e.logicalKey == LogicalKeyboardKey.escape && _card != null) setState(() => _card = null);
              }
              if (e is KeyUpEvent) _keys.remove(e.logicalKey);
              return KeyEventResult.handled;
            },
            child: Stack(children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (d) => _tap(d.localPosition),
                  onPanStart: (d) => setState(() {
                    _target = null;
                    _stickOrigin = d.localPosition;
                    _stick = d.localPosition;
                  }),
                  onPanUpdate: (d) => setState(() => _stick = d.localPosition),
                  onPanEnd: (_) => setState(() => _stickOrigin = _stick = null),
                  onPanCancel: () => setState(() => _stickOrigin = _stick = null),
                  child: m == null
                      ? const Center(child: CircularProgressIndicator())
                      : CustomPaint(painter: _MapPainter(this, rm, repaint: _repaint)),
                ),
              ),
              if (_stickOrigin != null && _stick != null) _Stick(origin: _stickOrigin!, knob: _stick!),
              // the header over a soft shade
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x80141A10), Color(0x00141A10)]),
                  ),
                  child: SafeArea(
                    bottom: false,
                    child: PlaceHeader(
                      title: m == null ? 'Lumen Wilds' : '${m.name} · ${m.floor}',
                      short: m?.floor ?? 'Wilds',
                      backLabel: 'Leave',
                      onBack: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ),
              ),
              if (m != null) ...[
                Positioned(left: 10, top: mq.padding.top + 62, child: _PartyPanel(sher: _party)),
                Positioned(
                  right: 10,
                  top: mq.padding.top + 62,
                  child: _MiniMap(state: this, onTap: () => setState(() => _card = 'map')),
                ),
                // actions
                Positioned(
                  right: 14,
                  bottom: 16 + mq.padding.bottom,
                  child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
                    if ((_near != null || _nearSher) && card == null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ActionButton(
                          label: _nearSher && (_near == null || !_party) ? (_party ? 'Chat' : 'Talk') : _near!.label,
                          icon: _nearSher && (_near == null || !_party) ? Icons.chat_bubble_rounded : Icons.touch_app_rounded,
                          big: true,
                          onTap: _interact,
                        ),
                      ),
                    _ActionButton(
                      label: 'Run',
                      icon: Icons.directions_run_rounded,
                      on: _runToggle,
                      onTap: () => setState(() => _runToggle = !_runToggle),
                    ),
                  ]),
                ),
                if (_hintT > 0 && card == null)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 22 + mq.padding.bottom,
                    child: IgnorePointer(
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _hintT > 1 ? 1 : 0,
                          duration: const Duration(milliseconds: 600),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
                            decoration: BoxDecoration(color: const Color(0xD92A1D10), borderRadius: BorderRadius.circular(14)),
                            child: Text('Drag to walk · push far to run · tap a spot', style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC))),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              if (card != null && m != null) _cardFor(card, m),
            ]),
          );
        }),
      ),
    );
  }

  Widget _cardFor(String card, WildsMap m) {
    final mq = MediaQuery.of(context);
    void close() => setState(() => _card = null);
    if (card == 'map') {
      return Positioned.fill(child: _FullMap(state: this, onClose: close));
    }
    final Widget body;
    if (card == 'sher') {
      body = _Offer(
        onJoin: () {
          context.read<GameController>().audio.play('reward_chime', volume: 0.6);
          setState(() {
            _card = null;
            _party = true;
            _bubble = 'Lead the way!';
            _bubbleT = 2.4;
          });
        },
        onLater: close,
      );
    } else {
      final s = m.spots.firstWhere((x) => x.id == card);
      final c = context.read<GameController>();
      final lvl = c.view.pet?.level.level ?? 1;
      final locked = s.need != null && lvl < s.need!;
      body = _SpotCard(
        spot: s,
        note: s.kind == 'gate' ? (locked ? 'Your Evochi is Lv. $lvl. It needs Lv. ${s.need}.' : 'The light flickers. Not yet, but soon.') : null,
        primary: s.kind == 'exit' ? 'Leave' : 'OK',
        secondary: s.kind == 'exit' ? 'Stay' : null,
        onPrimary: () {
          if (s.kind == 'exit') {
            Navigator.of(context).maybePop();
          } else {
            close();
          }
        },
        onSecondary: close,
      );
    }
    return Positioned(left: 12, right: 12, bottom: 12 + mq.padding.bottom, child: body);
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.s, this.rm, {required Listenable repaint}) : super(repaint: repaint);
  final _WildsScreenState s;
  final bool rm;

  @override
  void paint(Canvas canvas, Size size) {
    final m = s._map, pet = s._pet;
    if (m == null || pet == null) return;
    final sher = s._sher;
    final gk = s._gk;
    final pq = Paint()..filterQuality = FilterQuality.medium;
    final view = Offset.zero & size;
    // the ground, in tiles (only those on screen)
    canvas.save();
    canvas.translate(-s._cam.dx, -s._cam.dy);
    canvas.scale(gk);
    final vis = Rect.fromLTWH(s._cam.dx / gk, s._cam.dy / gk, size.width / gk, size.height / gk).inflate(4);
    for (final t in m.tiles) {
      if (t.rect.overlaps(vis)) canvas.drawImage(t.img, t.rect.topLeft, pq);
    }
    canvas.restore();
    // soft shadows under the walkers (the props' shadows are in the ground)
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final w in [pet, if (sher != null) sher]) {
      final g = s._toScreen(w.x, w.z);
      canvas.drawOval(Rect.fromCenter(center: g, width: w.art.radius * 2.4 * s._u, height: w.art.radius * 1.1 * s._u), shadow);
    }
    // everything standing, back to front (only what can be on screen); a tall prop in front of a walker
    // turns see-through while it hides them
    final wk = s._u / walkerDrawScale;
    final hidden = [
      for (final w in [pet, if (sher != null) sher])
        (w.z, Rect.fromCenter(center: s._toScreen(w.x, w.z) - Offset(0, w.art.gy * wk * 0.45), width: w.art.fw * wk * 0.5, height: w.art.gy * wk * 0.8)),
    ];
    final items = <(double, void Function())>[];
    for (final p in m.props) {
      final a = m.propArt[p.kind];
      if (a == null) continue;
      final g = s._toScreen(p.x, p.z);
      final k = s._u / a.scale;
      final r = Rect.fromLTWH(g.dx - a.ax * k, g.dy - a.ay * k, a.img.width * k, a.img.height * k);
      if (!r.overlaps(view)) continue;
      final tall = p.kind.startsWith('oak') || p.kind.startsWith('pine') || p.kind.startsWith('birch') || p.kind == 'gate' || p.kind == 'tent';
      final see = tall && hidden.any((h) => p.z > h.$1 && r.deflate(r.width * 0.12).overlaps(h.$2));
      items.add((p.z, () => _prop(canvas, p, a, g, k, see ? _see : pq)));
    }
    for (final w in [pet, if (sher != null) sher]) {
      items.add((w.z, () => _walker(canvas, w, pq, w == pet)));
    }
    for (final (x, z, kind) in m.fx) {
      if (kind == 'fire') items.add((z + 0.5, () => _fire(canvas, s._toScreen(x, z))));
    }
    items.sort((a, b) => a.$1.compareTo(b.$1));
    for (final it in items) {
      it.$2();
    }
    // a glint where something waits to be found
    for (final sp in m.spots) {
      if (sp.kind != 'glint') continue;
      final g = s._toScreen(sp.x, sp.z) - Offset(0, 10 * s._u / 2.7);
      final t = rm ? 0.5 : (math.sin(s._t * 3) + 1) / 2;
      final p = Paint()
        ..color = Color.lerp(const Color(0x66FFF3B0), const Color(0xEEFFF3B0), t)!
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      canvas.drawCircle(g, 5 + 3 * t, p);
      final star = Paint()..color = const Color(0xFFFFFDF0);
      final r = 7 + 4 * t;
      canvas.drawPath(
          Path()
            ..moveTo(g.dx, g.dy - r)
            ..lineTo(g.dx + 1.6, g.dy)
            ..lineTo(g.dx, g.dy + r)
            ..lineTo(g.dx - 1.6, g.dy)
            ..close()
            ..moveTo(g.dx - r, g.dy)
            ..lineTo(g.dx, g.dy + 1.6)
            ..lineTo(g.dx + r, g.dy)
            ..lineTo(g.dx, g.dy - 1.6)
            ..close(),
          star);
    }
    // Sher's bubble
    final b = s._bubble;
    if (b != null && sher != null) {
      final g = s._toScreen(sher.x, sher.z);
      final tp = TextPainter(
        text: TextSpan(text: b, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: 13)),
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: 190);
      final top = g.dy - sher.art.gy * s._u / walkerDrawScale - tp.height - 16;
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(g.dx, top + tp.height / 2), width: tp.width + 20, height: tp.height + 14),
          const Radius.circular(12));
      canvas.drawRRect(r.shift(const Offset(0, 2)), Paint()..color = const Color(0x55000000));
      canvas.drawRRect(r, Paint()..color = const Color(0xFFFFF7E8));
      canvas.drawRRect(
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = const Color(0xFF3B2923));
      tp.paint(canvas, Offset(g.dx - tp.width / 2, top));
    }
  }

  static final _see = Paint()
    ..filterQuality = FilterQuality.medium
    ..color = const Color.fromRGBO(0, 0, 0, 0.42);

  void _prop(Canvas canvas, MapProp p, PropArt a, Offset g, double k, Paint pq) {
    canvas.save();
    canvas.translate(g.dx, g.dy);
    if (p.flip) canvas.scale(-1, 1);
    canvas.scale(k);
    canvas.drawImage(a.img, Offset(-a.ax, -a.ay), pq);
    canvas.restore();
  }

  void _walker(Canvas canvas, _Walker w, Paint pq, bool isPet) {
    final art = w.art;
    final gait = w.gait;
    final g = s._toScreen(w.x, w.z);
    final col = w.col;
    final k = s._u / walkerDrawScale;
    canvas.save();
    canvas.translate(g.dx, g.dy);
    if (!rm) {
      // the waddle: a roll about its own forward axis (seen full from the front, not at all side-on)
      final face = w.dir * math.pi / 4;
      canvas.rotate(gait.roll[col] * math.pi / 180 * math.cos(face));
      canvas.scale(1, gait.squash[col]);
    }
    final dst = Rect.fromLTWH(-art.gx * k, -art.gy * k, art.fw * k, art.fh * k);
    canvas.drawImageRect(gait.img, Rect.fromLTWH(col * art.fw, w.dir * art.fh, art.fw, art.fh), dst, pq);
    // what it wears rides the body's bob
    if (isPet) {
      final lift = col < gait.lift.length ? gait.lift[col] : 0.0;
      for (final img in art.wear.values) {
        canvas.drawImageRect(img, Rect.fromLTWH(w.dir * art.fw, 0, art.fw, art.fh), dst.shift(Offset(0, -lift * k)), pq);
      }
    }
    canvas.restore();
  }

  void _fire(Canvas canvas, Offset g) {
    final t = s._t;
    final k = s._u / 2.7;
    final flick = rm ? 0.5 : (math.sin(t * 13) + math.sin(t * 7.3 + 1) + 2) / 4;
    canvas.drawCircle(
        g - Offset(0, 4 * k),
        (16 + 4 * flick) * k,
        Paint()
          ..color = const Color(0x55FFB347)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 10 * k));
    for (var i = 0; i < 3; i++) {
      final h = (12 + 6 * flick - i * 3.5) * k;
      final w = (7 - i * 1.8) * k;
      final c = [const Color(0xFFE9592C), const Color(0xFFFF9A3A), const Color(0xFFFFE08A)][i];
      final sway = rm ? 0.0 : math.sin(t * 9 + i) * 1.2 * k;
      canvas.drawPath(
          Path()
            ..moveTo(g.dx - w, g.dy - 2 * k)
            ..quadraticBezierTo(g.dx - w * 0.6, g.dy - h * 0.6, g.dx + sway, g.dy - h - 2 * k)
            ..quadraticBezierTo(g.dx + w * 0.6, g.dy - h * 0.6, g.dx + w, g.dy - 2 * k)
            ..close(),
          Paint()..color = c);
    }
    if (!rm) {
      // sparks rising
      for (var i = 0; i < 5; i++) {
        final ph = (t * 0.7 + i / 5) % 1.0;
        final x = g.dx + math.sin(i * 2.1 + t * 2) * 6 * k;
        final y = g.dy - (14 + ph * 34) * k;
        canvas.drawCircle(Offset(x, y), 1.4 * k, Paint()..color = Color.fromRGBO(255, 214, 120, 1 - ph));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}

/// The party: your Evochi first (it leads), then any NPC ally. Raid HP and Energy are the design's; here
/// they sit full (no combat yet).
class _PartyPanel extends StatelessWidget {
  const _PartyPanel({required this.sher});
  final bool sher;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet;
    Widget row(Widget face, String name, {bool lead = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            face,
            const SizedBox(width: 6),
            Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(name, style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC), fontSize: lead ? 13 : 12)),
              const SizedBox(height: 3),
              _Bar(width: lead ? 84 : 66, color: const Color(0xFF6CC24A)),
              const SizedBox(height: 2),
              _Bar(width: lead ? 84 : 66, color: const Color(0xFF4FA3E0), height: 5),
            ]),
          ]),
        );
    return Semantics(
      label: sher ? 'Party: ${pet?.name ?? 'your Evochi'} and Sher' : 'Party: ${pet?.name ?? 'your Evochi'}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 10, 0),
          decoration: BoxDecoration(color: const Color(0xB32A1D10), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            if (pet != null) row(EncFace.pet(pet, size: 38), pet.name, lead: true),
            if (sher) row(const SherFace(size: 32), 'Sher'),
          ]),
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.width, required this.color, this.height = 7});
  final double width, height;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
        width: width,
        height: height,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(color: const Color(0xFF1A120A), borderRadius: BorderRadius.circular(height)),
        child: DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(height))),
      );
}

/// Sher's face in a round frame, from his villager sprite (centred a little up and left of the face
/// point: his head turns to the right, and his ears stay in frame).
class SherFace extends StatelessWidget {
  const SherFace({super.key, this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) {
    final sz = villageArt.npcSize('sher');
    final f = villageArt.npcFace('sher');
    final k = size * 1.08 / sz.width;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(shape: BoxShape.circle, color: const Color(0xFFFFF0DE), border: Border.all(color: const Color(0xFFEE9C47), width: 2)),
      child: ClipOval(
        child: Stack(clipBehavior: Clip.hardEdge, children: [
          Positioned(
            left: size / 2 - (f.dx - 0.06 * sz.width) * k,
            top: size * 0.5 - (f.dy - 0.06 * sz.height) * k,
            width: sz.width * k,
            height: sz.height * k,
            child: Image.asset(villageArt.npc('sher'), fit: BoxFit.fill, filterQuality: FilterQuality.medium, excludeFromSemantics: true),
          ),
        ]),
      ),
    );
  }
}

/// A round action button (bottom right): Interact (big, labelled with what it does) and Run (a toggle).
class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.label, required this.icon, required this.onTap, this.big = false, this.on = false});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool big, on;
  @override
  Widget build(BuildContext context) {
    final d = big ? 74.0 : 58.0;
    return Semantics(
      button: true,
      toggled: big ? null : on,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                center: const Alignment(-0.2, -0.35),
                colors: big
                    ? const [Color(0xFFFFF0B0), EvochiColor.primary]
                    : (on ? const [Color(0xFFD8F2B8), Color(0xFF6CC24A)] : const [Color(0xFFFFF7E8), Color(0xFFE6D3AE)]),
              ),
              border: Border.all(color: const Color(0xFF3B2923), width: 2.5),
              boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 3))],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: big ? 26 : 22, color: EvochiColor.ink),
              Text(label, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: big ? 13 : 11, height: 1.1)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The minimap: the floor around you, top-down, north up; the gate, the camp and Sher marked. Tap for
/// the whole floor.
class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.state, required this.onTap});
  final _WildsScreenState state;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Map of the floor',
        child: GestureDetector(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF3B2923), width: 2.5),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: CustomPaint(painter: _MiniPainter(state, span: 220, repaint: state._repaint)),
              ),
            ),
          ),
        ),
      );
}

class _MiniPainter extends CustomPainter {
  _MiniPainter(this.s, {required this.span, required Listenable repaint, this.whole = false}) : super(repaint: repaint);
  final _WildsScreenState s;
  final double span; // world units across
  final bool whole;

  @override
  void paint(Canvas canvas, Size size) {
    final m = s._map, pet = s._pet;
    if (m == null || pet == null) return;
    final wr = m.miniWorld;
    final img = m.minimap;
    // world -> canvas
    final double k;
    final Offset c0;
    if (whole) {
      k = math.min(size.width / wr.width, size.height / wr.height);
      c0 = Offset((size.width - wr.width * k) / 2 - wr.left * k, (size.height - wr.height * k) / 2 - wr.top * k);
    } else {
      k = size.width / span;
      c0 = Offset(size.width / 2 - pet.x * k, size.height / 2 - pet.z * k);
    }
    Offset at(double x, double z) => Offset(x * k, z * k) + c0;
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF2E4A24));
    final src = Offset.zero & Size(img.width.toDouble(), img.height.toDouble());
    final dst = Rect.fromPoints(at(wr.left, wr.top), at(wr.right, wr.bottom));
    canvas.drawImageRect(img, src, dst, Paint()..filterQuality = FilterQuality.low);
    final dot = Paint();
    for (final sp in m.spots) {
      final p = at(sp.x, sp.z);
      if (sp.kind == 'gate') {
        dot.color = const Color(0xFF8FE3D0);
        canvas.drawCircle(p, whole ? 7 : 5, dot);
        canvas.drawCircle(p, whole ? 7 : 5, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF3B2923));
      } else if (sp.kind == 'exit') {
        dot.color = const Color(0xFFFFF3DC);
        canvas.drawCircle(p, whole ? 5 : 4, dot);
      } else if (sp.kind == 'glint' && whole) {
        dot.color = const Color(0xFFFFE08A);
        canvas.drawCircle(p, 4, dot);
      }
    }
    for (final (x, z, kind) in m.fx) {
      if (kind == 'fire') {
        dot.color = const Color(0xFFFF9A3A);
        canvas.drawCircle(at(x, z), whole ? 5 : 4, dot);
      }
    }
    final sher = s._sher;
    if (sher != null) {
      dot.color = const Color(0xFFEE9C47);
      canvas.drawCircle(at(sher.x, sher.z), whole ? 5 : 4, dot);
    }
    // you: a pointer in the way you face
    final p = at(pet.x, pet.z);
    final a = pet.dir * math.pi / 4; // 0 = facing south (down)
    final dir = Offset(math.sin(a), math.cos(a));
    final side = Offset(-dir.dy, dir.dx);
    final r = whole ? 8.0 : 6.0;
    canvas.drawPath(
        Path()
          ..moveTo(p.dx + dir.dx * r, p.dy + dir.dy * r)
          ..lineTo(p.dx - dir.dx * r * 0.6 + side.dx * r * 0.7, p.dy - dir.dy * r * 0.6 + side.dy * r * 0.7)
          ..lineTo(p.dx - dir.dx * r * 0.6 - side.dx * r * 0.7, p.dy - dir.dy * r * 0.6 - side.dy * r * 0.7)
          ..close(),
        Paint()..color = Colors.white);
    canvas.drawPath(
        Path()
          ..moveTo(p.dx + dir.dx * r, p.dy + dir.dy * r)
          ..lineTo(p.dx - dir.dx * r * 0.6 + side.dx * r * 0.7, p.dy - dir.dy * r * 0.6 + side.dy * r * 0.7)
          ..lineTo(p.dx - dir.dx * r * 0.6 - side.dx * r * 0.7, p.dy - dir.dy * r * 0.6 - side.dy * r * 0.7)
          ..close(),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..color = const Color(0xFF3B2923));
  }

  @override
  bool shouldRepaint(covariant _MiniPainter old) => true;
}

/// The whole floor, top-down, with the objective: a focused view (not over other cards).
class _FullMap extends StatelessWidget {
  const _FullMap({required this.state, required this.onClose});
  final _WildsScreenState state;
  final VoidCallback onClose;
  @override
  Widget build(BuildContext context) {
    final m = state._map!;
    final mq = MediaQuery.of(context);
    return Container(
      color: const Color(0xCC141A10),
      padding: EdgeInsets.fromLTRB(16, mq.padding.top + 12, 16, mq.padding.bottom + 16),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          decoration: Kit.parchment(radius: 14),
          child: Row(children: [
            const SparkIcon(size: 26),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${m.name} · ${m.floor}', style: EvochiText.cardTitle),
                Text(m.objective, style: EvochiText.caption),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF3B2923), width: 3),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: CustomPaint(painter: _MiniPainter(state, span: 0, whole: true, repaint: state._repaint), child: const SizedBox.expand()),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Wrap(spacing: 10, runSpacing: 4, children: [
              _legend(const Color(0xFF8FE3D0), 'Gate'),
              _legend(const Color(0xFFFF9A3A), 'Camp'),
              _legend(const Color(0xFFEE9C47), 'Sher'),
              _legend(const Color(0xFFFFE08A), 'Glint'),
            ]),
          ),
          EvochiButton(label: 'Close', tone: ButtonTone.cream, small: true, expand: false, onPressed: onClose),
        ]),
      ]),
    );
  }

  Widget _legend(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: const Color(0xFF3B2923)))),
        const SizedBox(width: 4),
        Text(t, style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC), fontSize: 12)),
      ]);
}

/// Something you found or reached: a focused card with what it says and what you can do.
class _SpotCard extends StatelessWidget {
  const _SpotCard({required this.spot, required this.primary, required this.onPrimary, this.secondary, this.onSecondary, this.note});
  final MapSpot spot;
  final String primary;
  final String? secondary, note;
  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: Kit.parchment(radius: 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(spot.title, style: EvochiText.cardTitle.copyWith(fontSize: 18)),
          const SizedBox(height: 6),
          Text(spot.text, style: EvochiText.bodyText.copyWith(height: 1.35)),
          if (note != null) ...[
            const SizedBox(height: 6),
            Text(note!, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary)),
          ],
          const SizedBox(height: 10),
          Row(children: [
            if (secondary != null) ...[
              Expanded(child: EvochiButton(label: secondary!, tone: ButtonTone.cream, onPressed: onSecondary)),
              const SizedBox(width: 8),
            ],
            Expanded(child: EvochiButton(label: primary, tone: spot.kind == 'exit' ? ButtonTone.gold : ButtonTone.green, onPressed: onPrimary)),
          ]),
        ]),
      );
}

/// Meeting Sher: his offer to come along.
class _Offer extends StatelessWidget {
  const _Offer({required this.onJoin, required this.onLater});
  final VoidCallback onJoin, onLater;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: Kit.parchment(radius: 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const SherFace(size: 56),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sher', style: EvochiText.cardTitle.copyWith(fontSize: 18)),
                const Text('A scout who knows the Wilds', style: EvochiText.caption),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Heading deeper? I know these paths, and two are safer than one. Mind if I join your party?',
              style: EvochiText.bodyText.copyWith(height: 1.35)),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: EvochiButton(label: 'Not now', tone: ButtonTone.cream, onPressed: onLater)),
            const SizedBox(width: 8),
            Expanded(child: EvochiButton(label: 'Join my party', tone: ButtonTone.green, onPressed: onJoin)),
          ]),
        ]),
      );
}

/// The joystick under your finger while you drag (the rim: running).
class _Stick extends StatelessWidget {
  const _Stick({required this.origin, required this.knob});
  final Offset origin, knob;
  @override
  Widget build(BuildContext context) {
    var d = knob - origin;
    final far = d.distance > 52;
    if (d.distance > 56) d = d / d.distance * 56;
    return Positioned(
      left: origin.dx - 64,
      top: origin.dy - 64,
      child: IgnorePointer(
        child: SizedBox(
          width: 128,
          height: 128,
          child: Stack(children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x33FFFFFF),
                border: Border.all(color: far ? const Color(0xFFB8E68C) : const Color(0x99FFF3DC), width: far ? 3 : 2),
              ),
            ),
            Positioned(
              left: 64 + d.dx - 22,
              top: 64 + d.dy - 22,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xE6FFF3DC),
                  border: Border.all(color: far ? const Color(0xFF6CC24A) : EvochiColor.primary, width: 2.5),
                  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
