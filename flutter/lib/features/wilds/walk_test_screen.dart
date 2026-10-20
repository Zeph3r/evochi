// The Lumen Wilds, first slice: a walk test. A sunny clearing seen from the map camera (tools/art/
// wilds_art.py), your Evochi walking in 8 directions (tools/art/walk.py), trees, rocks, stumps and
// bushes in the way, and Sher, a scout you meet on the path: tap him and he offers to join your party
// (an NPC ally, as in the Guild Raids design: he never replaces your Evochi); then he follows you, and
// the party panel shows you both. Drag anywhere to walk (a joystick appears under your finger), tap
// a spot to walk there, or use WASD / the arrow keys. Everything stands on the ground and is drawn
// back to front, so you pass behind a tree and in front of a rock.
//
// World units: x right, z toward you (down the screen); the art maps world (x, 0, z) to image pixels
// origin + (x, z * sin(pitch)) * scale.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import '../trails/trails_widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';

const _base = 'assets/art/wilds/';

/// A walk sheet: rows are the 8 directions (S, SE, E, NE, N, NW, W, SW), columns an idle stance then
/// the 8 walk frames.
class _Sheet {
  _Sheet(this.img, Map<String, dynamic> j)
      : fw = (j['frameW'] as num).toDouble(),
        fh = (j['frameH'] as num).toDouble(),
        gx = ((j['ground'] as List)[0] as num).toDouble(),
        gy = ((j['ground'] as List)[1] as num).toDouble(),
        roll = [for (final v in j['roll'] as List) (v as num).toDouble()],
        squash = [for (final v in j['squash'] as List) (v as num).toDouble()];
  final ui.Image img;
  final double fw, fh, gx, gy;
  final List<double> roll, squash;
}

class _Prop {
  _Prop(this.kind, this.x, this.z, this.img, this.ax, this.ay, this.radius, this.flip);
  final String kind;
  final double x, z;
  final ui.Image img;
  final double ax, ay, radius;
  final bool flip;
}

class _Art {
  _Art({required this.ground, required this.ox, required this.oy, required this.world, required this.scale, required this.pitch,
      required this.fps, required this.pet, required this.sher, required this.props});
  final ui.Image ground;
  final double ox, oy; // world origin, in ground-image pixels
  final Rect world; // walkable bounds (x0, z0, x1, z1)
  final double scale; // image px per world unit
  final double pitch;
  final double fps;
  final _Sheet pet, sher;
  final List<_Prop> props;

  double get sinP => math.sin(pitch * math.pi / 180);

  static Future<ui.Image> _img(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  static Future<_Art> load(String palette) async {
    final walk = await _json('wilds_walk.json');
    final test = await _json('wilds_test.json');
    final walkers = (walk['walkers'] as Map).cast<String, dynamic>();
    final s01 = (walkers['s01'] as Map).cast<String, dynamic>();
    final sheets = (s01['sheets'] as Map).cast<String, dynamic>();
    final petFile = (sheets[palette] ?? sheets['amber'] ?? sheets.values.first) as String;
    final sherJ = (walkers['sher'] as Map).cast<String, dynamic>();
    final g = (test['ground'] as Map).cast<String, dynamic>();
    final images = (test['images'] as Map).cast<String, dynamic>();
    final imgs = <String, ui.Image>{};
    for (final e in images.entries) {
      imgs[e.key] = await _img(_base + ((e.value as Map)['image'] as String));
    }
    final w = [for (final v in g['world'] as List) (v as num).toDouble()];
    final props = <_Prop>[];
    var i = 0;
    for (final p in test['props'] as List) {
      final m = (p as Map).cast<String, dynamic>();
      final im = (images[m['kind']] as Map).cast<String, dynamic>();
      final a = im['anchor'] as List;
      props.add(_Prop(m['kind'] as String, (m['x'] as num).toDouble(), (m['z'] as num).toDouble(), imgs[m['kind']]!,
          (a[0] as num).toDouble(), (a[1] as num).toDouble(), (im['radius'] as num).toDouble(), i++ % 3 == 1));
    }
    return _Art(
      ground: await _img(_base + (g['image'] as String)),
      ox: ((g['origin'] as List)[0] as num).toDouble(),
      oy: ((g['origin'] as List)[1] as num).toDouble(),
      world: Rect.fromLTRB(w[0], w[1], w[2], w[3]),
      scale: (walk['scale'] as num).toDouble(),
      pitch: (walk['pitch'] as num).toDouble(),
      fps: (walk['fps'] as num).toDouble(),
      pet: _Sheet(await _img(_base + petFile), s01),
      sher: _Sheet(await _img(_base + ((sherJ['sheets'] as Map).values.first as String)), sherJ),
      props: props,
    );
  }

  static Future<Map<String, dynamic>> _json(String f) async =>
      (jsonDecode(await rootBundle.loadString(_base + f)) as Map).cast<String, dynamic>();
}

/// One walker on the map: where it stands, which way it faces, how far into its stride it is.
class _Walker {
  _Walker(this.sheet, this.x, this.z, this.radius);
  final _Sheet sheet;
  double x, z;
  final double radius;
  int dir = 0; // index into S, SE, E, NE, N, NW, W, SW
  double phase = 0; // 0..1 through the 8-frame cycle
  bool moving = false;

  void face(double vx, double vz) {
    final a = math.atan2(vx, vz) * 180 / math.pi; // 0 = toward you (S), 90 = right (E)
    dir = (((a / 45).round()) % 8 + 8) % 8;
  }

  int get col => moving ? 1 + (phase * 8).floor() % 8 : 0;
}

class WalkTestScreen extends StatefulWidget {
  const WalkTestScreen({super.key});
  @override
  State<WalkTestScreen> createState() => _WalkTestScreenState();
}

class _WalkTestScreenState extends State<WalkTestScreen> with SingleTickerProviderStateMixin {
  _Art? _art;
  _Walker? _pet, _sher;
  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  final _focus = FocusNode();
  final _keys = <LogicalKeyboardKey>{};
  Offset? _stickOrigin, _stick; // joystick (screen)
  Offset? _target; // tap-to-move target (world x, z)
  Size _view = Size.zero;
  double _k = 0.45; // screen px per image px
  Offset _cam = Offset.zero; // top-left of the view, in screen px of the scaled ground
  // Sher wanders between spots by the path, pausing at each
  final _route = const [Offset(10, 40), Offset(-24, 110), Offset(-6, -60), Offset(30, -150), Offset(-40, -10)];
  int _leg = 0;
  double _pause = 1.5;
  String? _bubble;
  double _bubbleT = 0;
  bool _party = false; // Sher has joined
  bool _offer = false; // his offer is showing
  final _crumbs = <Offset>[]; // where your Evochi has walked (Sher follows the path, not a beeline)
  int _line = 0;
  double _hintT = 6;
  final _repaint = ValueNotifier<int>(0);

  static const _petSpeed = 26.0; // world units / s
  static const _sherSpeed = 15.0;

  @override
  void initState() {
    super.initState();
    final c = context.read<GameController>();
    _Art.load(c.state.pet?.paletteId ?? 'amber').then((a) {
      if (!mounted) return;
      setState(() {
        _art = a;
        _pet = _Walker(a.pet, -10, 200, 9);
        _sher = _Walker(a.sher, 10, 40, 7);
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

  // ---- mapping
  Offset _toImage(double x, double z) {
    final a = _art!;
    return Offset(a.ox + x * a.scale, a.oy + z * a.sinP * a.scale);
  }

  Offset _toScreen(double x, double z) => _toImage(x, z) * _k - _cam;

  Offset _toWorld(Offset screen) {
    final a = _art!;
    final p = (screen + _cam) / _k;
    return Offset((p.dx - a.ox) / a.scale, (p.dy - a.oy) / (a.sinP * a.scale));
  }

  // ---- the loop
  void _tick(Duration now) {
    final dt = _last == Duration.zero ? 0.0 : math.min(0.05, (now - _last).inMicroseconds / 1e6);
    _last = now;
    final a = _art, pet = _pet, sher = _sher;
    if (a == null || pet == null || sher == null || _view == Size.zero) return;
    // input: keys, then the joystick, then a tap target
    var vx = 0.0, vz = 0.0;
    bool k(LogicalKeyboardKey a, LogicalKeyboardKey b) => _keys.contains(a) || _keys.contains(b);
    if (k(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.keyA)) vx -= 1;
    if (k(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.keyD)) vx += 1;
    if (k(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.keyW)) vz -= 1;
    if (k(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.keyS)) vz += 1;
    var speed = 1.0;
    if (vx != 0 || vz != 0) {
      _target = null;
    } else if (_stickOrigin != null && _stick != null) {
      final d = _stick! - _stickOrigin!;
      if (d.distance > 8) {
        vx = d.dx;
        vz = d.dy / a.sinP; // the screen's up is foreshortened north
        speed = (d.distance / 48).clamp(0.35, 1.0);
      }
    } else if (_target != null) {
      vx = _target!.dx - pet.x;
      vz = _target!.dy - pet.z;
      if (math.sqrt(vx * vx + vz * vz) < 2.5) {
        _target = null;
        vx = vz = 0;
      }
    }
    if (_offer) vx = vz = 0;
    _move(pet, vx, vz, _petSpeed * speed, dt, [sher]);
    if (_crumbs.isEmpty || (Offset(pet.x, pet.z) - _crumbs.last).distance > 3) {
      _crumbs.add(Offset(pet.x, pet.z));
      if (_crumbs.length > 60) _crumbs.removeAt(0);
    }
    // Sher: in your party he follows your path a little behind; otherwise off to the next spot, or
    // waiting (turned toward you when you come close)
    final gap = math.sqrt(math.pow(pet.x - sher.x, 2) + math.pow(pet.z - sher.z, 2));
    final near = gap < 46;
    if (_party) {
      if (gap > 40) {
        // a spot about 34 units back along your path, a step off to its side (so he walks beside and
        // behind you rather than hidden right behind you)
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
        _move(sher, t.dx - sher.x, t.dy - sher.z, _petSpeed * (gap > 80 ? 1.3 : 1.0), dt, [pet]);
      } else {
        sher.moving = false;
        if (pet.moving) sher.dir = pet.dir;
      }
    } else if (near) {
      sher.moving = false;
      sher.face(pet.x - sher.x, pet.z - sher.z);
    } else if (_pause > 0) {
      _pause -= dt;
      sher.moving = false;
    } else {
      final t = _route[_leg];
      final dx = t.dx - sher.x, dz = t.dy - sher.z;
      if (math.sqrt(dx * dx + dz * dz) < 2) {
        _leg = (_leg + 1) % _route.length;
        _pause = 1.5 + (_leg % 3) * 1.2;
        sher.dir = 0;
      } else {
        _move(sher, dx, dz, _sherSpeed, dt, [pet]);
      }
    }
    if (_bubble != null) {
      _bubbleT -= dt;
      if (_bubbleT <= 0) _bubble = null;
    }
    if (_hintT > 0) {
      final before = _hintT;
      _hintT -= dt;
      if ((before > 1) != (_hintT > 1) || _hintT <= 0) setState(() {});
    }
    // the camera follows your Evochi, kept inside the clearing's picture
    final p = _toImage(pet.x, pet.z) * _k;
    final gw = a.ground.width * _k, gh = a.ground.height * _k;
    final want = Offset((p.dx - _view.width / 2).clamp(0.0, math.max(0.0, gw - _view.width)),
        (p.dy - _view.height * 0.55).clamp(0.0, math.max(0.0, gh - _view.height)));
    _cam = Offset.lerp(_cam, want, math.min(1.0, dt * 6))!;
    _repaint.value++;
  }

  void _move(_Walker w, double vx, double vz, double speed, double dt, List<_Walker> others) {
    final len = math.sqrt(vx * vx + vz * vz);
    if (len < 1e-6) {
      w.moving = false;
      return;
    }
    final a = _art!;
    vx /= len;
    vz /= len;
    w.face(vx, vz);
    var nx = w.x + vx * speed * dt, nz = w.z + vz * speed * dt;
    // slide round trees, rocks and the other walker
    final obstacles = <(double, double, double)>[
      for (final p in a.props) (p.x, p.z, p.radius + w.radius),
      for (final o in others) (o.x, o.z, o.radius + w.radius),
    ];
    for (final (ox, oz, r) in obstacles) {
      final dx = nx - ox, dz = nz - oz;
      final d = math.sqrt(dx * dx + dz * dz);
      if (d < r && d > 1e-6) {
        nx = ox + dx / d * r;
        nz = oz + dz / d * r;
      }
    }
    final b = a.world;
    nx = nx.clamp(b.left + 12, b.right - 12);
    nz = nz.clamp(b.top + 26, b.bottom - 10);
    final moved = math.sqrt(math.pow(nx - w.x, 2) + math.pow(nz - w.z, 2));
    w.x = nx;
    w.z = nz;
    w.moving = moved > speed * dt * 0.2;
    // the stride keeps pace with the ground covered (a cycle is ~10 units of travel)
    if (w.moving) w.phase = (w.phase + moved / 10.0) % 1.0;
  }

  void _tap(Offset pos) {
    final a = _art, sher = _sher;
    if (a == null || sher == null) return;
    // Sher?
    final s = _toScreen(sher.x, sher.z);
    final r = Rect.fromLTWH(s.dx - sher.sheet.gx * _k * 0.6, s.dy - sher.sheet.gy * _k * 0.9, sher.sheet.fw * _k * 0.6,
        sher.sheet.gy * _k * 0.95);
    if (r.contains(pos)) {
      context.read<GameController>().audio.play('pet_chirp', volume: 0.5);
      setState(() {
        if (_party) {
          const lines = ['Lead the way!', 'I\'ve got your back.', 'Smell that? Rain later.', 'Stay close to the path.'];
          _bubble = lines[_line++ % lines.length];
          _bubbleT = 2.6;
        } else {
          _offer = true;
          _target = null;
        }
      });
      return;
    }
    if (_offer) return;
    final w = _toWorld(pos);
    _target = w;
  }

  @override
  Widget build(BuildContext context) {
    final a = _art;
    final rm = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: const Color(0xFF2E4A24),
      body: LayoutBuilder(builder: (ctx, b) {
        _view = Size(b.maxWidth, b.maxHeight);
        if (a != null) {
          _k = math.max(0.45, math.max(b.maxWidth / a.ground.width, b.maxHeight / a.ground.height));
        }
        return Focus(
          focusNode: _focus,
          autofocus: true,
          onKeyEvent: (_, e) {
            if (e is KeyDownEvent) _keys.add(e.logicalKey);
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
                child: a == null
                    ? const Center(child: CircularProgressIndicator())
                    : CustomPaint(painter: _MapPainter(this, rm, repaint: _repaint)),
              ),
            ),
            if (_stickOrigin != null && _stick != null) _Stick(origin: _stickOrigin!, knob: _stick!),
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
                    child: PlaceHeader(title: 'Sunlit Thicket', short: 'Thicket', backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
                  ),
              ),
            ),
            if (a != null)
              Positioned(
                left: 10,
                top: MediaQuery.of(context).padding.top + 62,
                child: _PartyPanel(sher: _party),
              ),
            if (_offer)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12 + MediaQuery.of(context).padding.bottom,
                child: _Offer(
                  onJoin: () {
                    context.read<GameController>().audio.play('reward_chime', volume: 0.6);
                    setState(() {
                      _offer = false;
                      _party = true;
                      _bubble = 'Lead the way!';
                      _bubbleT = 2.4;
                    });
                  },
                  onLater: () => setState(() => _offer = false),
                ),
              ),
            if (_hintT > 0 && a != null && !_offer)
              Positioned(
                left: 0,
                right: 0,
                bottom: 18 + MediaQuery.of(context).padding.bottom,
                child: IgnorePointer(
                  child: Center(
                    child: AnimatedOpacity(
                      opacity: _hintT > 1 ? 1 : 0,
                      duration: const Duration(milliseconds: 600),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 6, 12, 7),
                        decoration: BoxDecoration(color: const Color(0xD92A1D10), borderRadius: BorderRadius.circular(14)),
                        child: Text('Drag to walk · tap to go there · WASD', style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC))),
                      ),
                    ),
                  ),
                ),
              ),
          ]),
        );
      }),
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.s, this.rm, {required Listenable repaint}) : super(repaint: repaint);
  final _WalkTestScreenState s;
  final bool rm;

  @override
  void paint(Canvas canvas, Size size) {
    final a = s._art;
    final pet = s._pet, sher = s._sher;
    if (a == null || pet == null || sher == null) return;
    final k = s._k;
    final pq = Paint()..filterQuality = FilterQuality.medium;
    // ground
    canvas.save();
    canvas.translate(-s._cam.dx, -s._cam.dy);
    canvas.scale(k);
    canvas.drawImage(a.ground, Offset.zero, pq);
    canvas.restore();
    // shadows first (all on the ground), then everything standing, back to front
    final shadow = Paint()
      ..color = const Color(0x40000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
    for (final p in a.props) {
      final g = s._toScreen(p.x, p.z);
      canvas.drawOval(Rect.fromCenter(center: g, width: p.radius * 2.6 * a.scale * k, height: p.radius * 1.3 * a.scale * k), shadow);
    }
    for (final w in [pet, sher]) {
      final g = s._toScreen(w.x, w.z);
      canvas.drawOval(Rect.fromCenter(center: g, width: w.radius * 2.4 * a.scale * k, height: w.radius * 1.1 * a.scale * k), shadow);
    }
    final items = <(double, void Function())>[
      for (final p in a.props) (p.z, () => _prop(canvas, p, k, pq)),
      for (final w in [pet, sher]) (w.z, () => _walker(canvas, w, k, pq, a)),
    ]..sort((x, y) => x.$1.compareTo(y.$1));
    for (final it in items) {
      it.$2();
    }
    // Sher's speech bubble
    final b = s._bubble;
    if (b != null) {
      final g = s._toScreen(sher.x, sher.z);
      final tp = TextPainter(
        text: TextSpan(text: b, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: 13)),
        textDirection: TextDirection.ltr,
        maxLines: 3,
      )..layout(maxWidth: 190);
      final top = g.dy - sher.sheet.gy * k - tp.height - 16;
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(g.dx, top + tp.height / 2), width: tp.width + 20, height: tp.height + 14),
          const Radius.circular(12));
      canvas.drawRRect(r.shift(const Offset(0, 2)), Paint()..color = const Color(0x55000000));
      canvas.drawRRect(r, Paint()..color = const Color(0xFFFFF7E8));
      canvas.drawRRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF3B2923));
      tp.paint(canvas, Offset(g.dx - tp.width / 2, top));
    }
  }

  void _prop(Canvas canvas, _Prop p, double k, Paint pq) {
    final g = s._toScreen(p.x, p.z);
    canvas.save();
    canvas.translate(g.dx, g.dy);
    if (p.flip) canvas.scale(-1, 1);
    canvas.scale(k);
    canvas.drawImage(p.img, Offset(-p.ax, -p.ay), pq);
    canvas.restore();
  }

  void _walker(Canvas canvas, _Walker w, double k, Paint pq, _Art a) {
    final sh = w.sheet;
    final g = s._toScreen(w.x, w.z);
    final col = w.col;
    final src = Rect.fromLTWH(col * sh.fw, w.dir * sh.fh, sh.fw, sh.fh);
    canvas.save();
    canvas.translate(g.dx, g.dy);
    if (!rm) {
      // the waddle: a roll about its own forward axis (seen full from the front, not at all side-on)
      final face = w.dir * math.pi / 4;
      canvas.rotate(sh.roll[col] * math.pi / 180 * math.cos(face));
      canvas.scale(1, sh.squash[col]);
    }
    canvas.drawImageRect(sh.img, src, Rect.fromLTWH(-sh.gx * k, -sh.gy * k, sh.fw * k, sh.fh * k), pq);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}

/// The joystick under your finger while you drag.
class _Stick extends StatelessWidget {
  const _Stick({required this.origin, required this.knob});
  final Offset origin, knob;
  @override
  Widget build(BuildContext context) {
    var d = knob - origin;
    if (d.distance > 48) d = d / d.distance * 48;
    return Positioned(
      left: origin.dx - 56,
      top: origin.dy - 56,
      child: IgnorePointer(
        child: SizedBox(
          width: 112,
          height: 112,
          child: Stack(children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0x33FFFFFF),
                border: Border.all(color: const Color(0x99FFF3DC), width: 2),
              ),
            ),
            Positioned(
              left: 56 + d.dx - 22,
              top: 56 + d.dy - 22,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xE6FFF3DC),
                  border: Border.all(color: EvochiColor.primary, width: 2.5),
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


/// The party: your Evochi first (it leads), then any NPC ally. Raid HP and Energy are the design's; here
/// they just sit full (the walk test has no combat yet).
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
              _Bar(width: lead ? 92 : 72, color: const Color(0xFF6CC24A)),
              const SizedBox(height: 2),
              _Bar(width: lead ? 92 : 72, color: const Color(0xFF4FA3E0), height: 5),
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
            if (pet != null) row(EncFace.pet(pet, size: 40), pet.name, lead: true),
            if (sher) row(const _SherFace(size: 34), 'Sher'),
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

/// Sher's face in a round frame, from his villager sprite.
class _SherFace extends StatelessWidget {
  const _SherFace({this.size = 40});
  final double size;
  @override
  Widget build(BuildContext context) {
    final sz = villageArt.npcSize('sher');
    final f = villageArt.npcFace('sher');
    final k = size * 1.08 / sz.width;
    // centred a little up and left of the face point (his head turns to the right): ears in frame
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFFFFF0DE),
        border: Border.all(color: const Color(0xFFEE9C47), width: 2),
      ),
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

/// Meeting Sher: his offer to come along, as a focused card (not stacked over anything else).
class _Offer extends StatelessWidget {
  const _Offer({required this.onJoin, required this.onLater});
  final VoidCallback onJoin, onLater;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: Kit.parchment(radius: 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const _SherFace(size: 56),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Sher', style: EvochiText.cardTitle.copyWith(fontSize: 18)),
                const Text('A scout who knows the Wilds', style: EvochiText.caption),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          Text('Heading into the Wilds? I know these paths, and two are safer than one. Mind if I join your party?',
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
