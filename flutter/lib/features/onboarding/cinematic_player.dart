// The onboarding's cold open, "The Fading Paths": the cinematic plates (tools/art/cine_scenes.py, rendered in
// Cycles) cut together by the shot list in assets/art/cine/onboarding_cine.json (tools/art/onboarding_cine.py
// writes it and previews the same cut as a video), played here frame by frame on one ticker: a plate seen
// through an eased camera, reveals growing along the trails or in from the edges, the golden Lumen footprint,
// tiny Evochi silhouettes walking the lit trails, captions, and a skip pill from the first frame.
//
// One golden footprint is the spine of the whole onboarding (the black opening, the map, the egg's cracks, the
// lit path after naming), so the footprint sprite and the trail-lighting live here as LumenPrint and
// TrailReveal for the later beats to reuse.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../core/services/asset_manifest.dart';
import '../shared/live_scene.dart';
import '../shared/widgets.dart';

const cineDir = 'assets/art/cine';

/// The shot list and the plates' projected anchors and trails, loaded once.
class CineTimeline {
  CineTimeline(this.fps, this.shots, this.meta);
  final int fps;
  final List<Map<String, dynamic>> shots;
  final Map<String, dynamic> meta; // cine.json: per plate its size, anchors, lines, scale

  static Future<CineTimeline>? _loading;

  static Future<CineTimeline> load() => _loading ??= () async {
        final t = jsonDecode(await rootBundle.loadString('$cineDir/onboarding_cine.json')) as Map<String, dynamic>;
        final m = jsonDecode(await rootBundle.loadString('$cineDir/cine.json')) as Map<String, dynamic>;
        return CineTimeline((t['fps'] as num).toInt(), (t['shots'] as List).cast<Map<String, dynamic>>(), m);
      }();

  double get total => shots.fold(0.0, (a, s) => a + (s['dur'] as num).toDouble());

  Map<String, dynamic> plateMeta(String plate) => (meta[plate] as Map<String, dynamic>?) ?? const {};

  /// a point given as [x, y] fractions, 'anchor:<name>' or 'trail:<name>:<t>' -> plate pixels (at the plate's
  /// rendered size)
  Offset platePoint(String plate, Object spec, Size plateSize) {
    final m = plateMeta(plate);
    final sc = ((m['scale'] as num?) ?? 1).toDouble();
    if (spec is String) {
      if (spec.startsWith('anchor:')) {
        final a = (m['anchors'] as Map<String, dynamic>)[spec.substring(7)] as List;
        return Offset((a[0] as num).toDouble() * sc, (a[1] as num).toDouble() * sc);
      }
      if (spec.startsWith('trail:')) {
        final parts = spec.split(':');
        final pts = trail(plate, parts[1]);
        final t = double.parse(parts[2]);
        return _along(pts, t);
      }
    }
    final l = spec as List;
    return Offset((l[0] as num).toDouble() * plateSize.width, (l[1] as num).toDouble() * plateSize.height);
  }

  List<Offset> trail(String plate, String key) {
    final m = plateMeta(plate);
    final sc = ((m['scale'] as num?) ?? 1).toDouble();
    final raw = ((m['lines'] as Map<String, dynamic>?)?[key] as List?) ?? const [];
    return [for (final p in raw) Offset((p[0] as num).toDouble() * sc, (p[1] as num).toDouble() * sc)];
  }

  List<String> trailKeys(String plate) => ((plateMeta(plate)['lines'] as Map<String, dynamic>?)?.keys.toList()) ?? const [];

  static Offset _along(List<Offset> pts, double t) {
    if (pts.isEmpty) return Offset.zero;
    if (pts.length == 1) return pts.first;
    final k = t.clamp(0.0, 1.0) * (pts.length - 1);
    final i = k.floor().clamp(0, pts.length - 2);
    final f = k - i;
    return Offset.lerp(pts[i], pts[i + 1], f)!;
  }
}

double _ease(double t, String kind) {
  t = t.clamp(0.0, 1.0);
  switch (kind) {
    case 'in':
      return t * t;
    case 'out':
      return 1 - (1 - t) * (1 - t);
    case 'inout':
      return t * t * (3 - 2 * t);
    default:
      return t;
  }
}

/// A plate seen through the shot's camera: cover-fit (zoom 1 = the plate's height fills the screen), centred on
/// a plate point, never showing past the plate.
class CineCamera {
  CineCamera(this.center, this.zoom);
  final Offset center; // plate pixels
  final double zoom;

  /// the plate -> screen transform for a screen of [size] and a plate of [plate]
  ({double scale, Offset origin}) fit(Size size, Size plate) {
    final base = math.max(size.height / plate.height, size.width / plate.width);
    final s = base * zoom;
    final vw = size.width / s, vh = size.height / s;
    final x0 = (center.dx - vw / 2).clamp(0.0, math.max(0.0, plate.width - vw)).toDouble();
    final y0 = (center.dy - vh / 2).clamp(0.0, math.max(0.0, plate.height - vh)).toDouble();
    return (scale: s, origin: Offset(x0, y0));
  }
}

/// The opening's golden footprint, pressed into dark ground: drawn additively from the rendered sprite
/// (cine/lumen_print.webp, on black) in a soft halo, with a slow pulse, or as a soft glow before the sprite loads.
/// The smaller prints everywhere else are [FootTrail].
class LumenPrint {
  static ui.Image? _sprite;
  static Future<ui.Image>? _loading;

  static void warm() {
    _loading ??= AtlasCache.load('$cineDir/lumen_print.webp').then((im) => _sprite = im);
  }

  static void paint(Canvas c, Offset at, double size, {double strength = 1, double heading = 0}) {
    final s = _sprite;
    c.save();
    c.translate(at.dx, at.dy);
    if (heading != 0) c.rotate(heading);
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..color = Colors.white.withValues(alpha: strength.clamp(0.0, 1.0))
      ..filterQuality = FilterQuality.medium;
    if (s != null) {
      // a soft warm halo the print sits in (the light pooled in the step spilling out round it)
      c.drawCircle(
          Offset.zero,
          size * 0.42,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(Offset.zero, size * 0.42, [const Color(0xFFFFB84A).withValues(alpha: 0.28 * strength.clamp(0.0, 1.0)), const Color(0x00FFB84A)]));
      c.drawImageRect(s, Rect.fromLTWH(0, 0, s.width.toDouble(), s.height.toDouble()),
          Rect.fromCenter(center: Offset.zero, width: size, height: size), paint);
    } else {
      final g = Paint()
        ..blendMode = BlendMode.plus
        ..shader = ui.Gradient.radial(Offset.zero, size * 0.5,
            [const Color(0xFFFFD56A).withValues(alpha: 0.9 * strength), const Color(0x00FFC24E)]);
      c.drawCircle(Offset.zero, size * 0.5, g);
    }
    c.restore();
  }
}

/// Lumen footsteps: faint golden prints pressed into the ground, left behind as something walks. The Eggling's
/// own foot (a rounded pad and three toes) drawn in code, so it costs a few fills and two cheap gradients a print:
/// a dark rim where the ground is pressed, the light pooled inside it, a soft halo. A print flares as the foot
/// lands, then cools to a faint ember; older ones fade away behind. Shared by the cold open's map shots, the
/// steps screen and the naming beat.
class FootTrail {
  /// the foot, one unit long, toes toward -y (forward = up when the heading is 0)
  static final Path _foot = () {
    final p = Path()..addRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: const Offset(0, 0.14), width: 0.6, height: 0.56), const Radius.circular(0.24)));
    for (final (x, y) in const [(-0.22, -0.3), (0.0, -0.38), (0.22, -0.3)]) {
      p.addOval(Rect.fromCenter(center: Offset(x, y), width: 0.17, height: 0.2));
    }
    return p;
  }();

  /// one print at [at], [size] px long, facing [heading] on the ground (radians, 0 = toes up the screen), lit
  /// [glow] 0..1; [squash] foreshortens the ground (1 = straight down on it); [side] steps it left or right
  static void stamp(Canvas c, Offset at, double size, {double heading = 0, double glow = 0.5, double squash = 1, double side = 0, double land = 1}) {
    if (glow <= 0.01) return;
    final g = glow.clamp(0.0, 1.0);
    c.save();
    c.translate(at.dx, at.dy);
    c.scale(1, squash);
    c.rotate(heading);
    c.translate(side * size * 0.36, 0);
    c.scale(size * (1 + 0.12 * (1 - land))); // a touch bigger as the foot comes down, then settled
    // the halo first, then the pressed rim (the ground a shade darker on the far edge), then the light inside
    c.drawCircle(
        const Offset(0, -0.02),
        0.62,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(const Offset(0, -0.02), 0.62, [const Color(0xFFFFC14E).withValues(alpha: 0.32 * g), const Color(0x00FFC14E)]));
    // the body in amber (normal blending, so it stays gold on bright parchment and sand instead of washing out to
    // white), the light pooled in its middle added on top
    c.drawPath(_foot.shift(const Offset(0, -0.04)), Paint()..color = const Color(0xFF4A2C10).withValues(alpha: 0.22 + 0.16 * g));
    c.drawPath(_foot, Paint()..color = const Color(0xFFE59528).withValues(alpha: 0.22 + 0.5 * g));
    c.drawPath(
        _foot,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(const Offset(0, 0.05), 0.5, [const Color(0xFFFFE08A).withValues(alpha: 0.5 * g), const Color(0x00FFD27A)]));
    c.restore();
  }

  /// a walk along [path] (screen points) up to [head] (0..1 of its length): a print every [stride] px,
  /// alternating feet. Each flares as it lands and cools over [flare] px of further walking to [ember]; with
  /// [fadeLen] the oldest fade out entirely that far behind. A few motes lift off the newest.
  static void walk(Canvas c, List<Offset> path, double head,
      {required double stride, required double size, double squash = 1, double ember = 0.22, double flare = 0, double fadeLen = double.infinity, double from = 0, int? seed}) {
    if (path.length < 2 || head <= from) return;
    final cum = <double>[0];
    for (var i = 1; i < path.length; i++) {
      cum.add(cum.last + (path[i] - path[i - 1]).distance);
    }
    final total = cum.last;
    if (total <= 0) return;
    final flareLen = flare > 0 ? flare : stride * 2.5;
    final h = head.clamp(0.0, 1.0) * total, s0 = from.clamp(0.0, 1.0) * total;
    var seg = 0;
    // start inside the fade window (the step count keeps the feet alternating the same way)
    var k = fadeLen.isFinite ? math.max(0, ((h - fadeLen - s0) / stride).ceil()) : 0;
    for (var s = s0 + k * stride; s <= h; s += stride, k++) {
      final behind = h - s;
      while (seg < cum.length - 2 && cum[seg + 1] < s) {
        seg++;
      }
      final a = path[seg], b = path[seg + 1];
      final u = (cum[seg + 1] - cum[seg]) <= 0 ? 0.0 : (s - cum[seg]) / (cum[seg + 1] - cum[seg]);
      final at = Offset.lerp(a, b, u)!;
      final d = b - a;
      final heading = math.atan2(d.dx, -d.dy / squash);
      final land = (behind / (stride * 0.5)).clamp(0.0, 1.0);
      var glow = ember + (1 - ember) * math.exp(-behind / flareLen);
      if (fadeLen.isFinite) glow *= (1 - behind / fadeLen).clamp(0.0, 1.0);
      stamp(c, at, size, heading: heading, glow: glow, squash: squash, side: k.isEven ? -1 : 1, land: land);
      if (behind < stride * 1.5) _motes(c, at, size, behind / (stride * 1.5), (seed ?? 0) * 31 + k);
    }
  }

  /// two or three motes drifting up off a fresh print, gone by the next step
  static void _motes(Canvas c, Offset at, double size, double u, int seed) {
    final rnd = math.Random(seed);
    final p = Paint()..blendMode = BlendMode.plus;
    for (var i = 0; i < 3; i++) {
      final dx = (rnd.nextDouble() - 0.5) * size * 0.9;
      final rise = size * (0.5 + rnd.nextDouble() * 0.9) * u;
      final a = (1 - u) * (0.5 + 0.4 * rnd.nextDouble());
      p.color = const Color(0xFFFFD27A).withValues(alpha: a);
      c.drawCircle(at + Offset(dx + math.sin(u * 5 + i) * size * 0.06, -rise), size * (0.05 + 0.03 * rnd.nextDouble()), p);
    }
  }
}

/// The trails lighting up along their length (a mask over the lit plate), shared with the naming beat.
class TrailReveal {
  /// a path of the trails in order, each drawn up to `progress` (0..1 over all of them)
  static Path path(List<List<Offset>> trails, double progress) {
    final p = Path();
    final n = trails.length;
    for (var i = 0; i < n; i++) {
      final pts = trails[i];
      final q = ((progress * n) - i).clamp(0.0, 1.0);
      if (q <= 0 || pts.length < 2) continue;
      final k = q * (pts.length - 1);
      final whole = k.floor();
      p.moveTo(pts[0].dx, pts[0].dy);
      for (var j = 1; j <= whole && j < pts.length; j++) {
        p.lineTo(pts[j].dx, pts[j].dy);
      }
      if (whole + 1 < pts.length) {
        final tip = Offset.lerp(pts[whole], pts[whole + 1], k - whole)!;
        p.lineTo(tip.dx, tip.dy);
      }
    }
    return p;
  }

  /// one trail between [a] and [b] (0..1 of its length): light that spreads both ways from a point
  static Path span(List<Offset> pts, double a, double b) {
    final p = Path();
    if (pts.length < 2 || b <= a) return p;
    final cum = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      cum.add(cum.last + (pts[i] - pts[i - 1]).distance);
    }
    final total = cum.last, sa = a.clamp(0.0, 1.0) * total, sb = b.clamp(0.0, 1.0) * total;
    Offset at(double s) {
      var i = 0;
      while (i < cum.length - 2 && cum[i + 1] < s) {
        i++;
      }
      final len = cum[i + 1] - cum[i];
      return Offset.lerp(pts[i], pts[i + 1], len <= 0 ? 0 : (s - cum[i]) / len)!;
    }

    final start = at(sa);
    p.moveTo(start.dx, start.dy);
    for (var i = 1; i < pts.length - 1; i++) {
      if (cum[i] > sa && cum[i] < sb) p.lineTo(pts[i].dx, pts[i].dy);
    }
    final end = at(sb);
    p.lineTo(end.dx, end.dy);
    return p;
  }

  /// the point [f] (0..1) of the way along one trail, by distance
  static Offset at(List<Offset> pts, double f) {
    var total = 0.0;
    for (var i = 1; i < pts.length; i++) {
      total += (pts[i] - pts[i - 1]).distance;
    }
    var left = f.clamp(0.0, 1.0) * total;
    for (var i = 1; i < pts.length; i++) {
      final d = (pts[i] - pts[i - 1]).distance;
      if (left <= d) return Offset.lerp(pts[i - 1], pts[i], d <= 0 ? 0 : left / d)!;
      left -= d;
    }
    return pts.last;
  }

  /// where the newest tip is (for the glow that leads the light)
  static Offset? tip(List<List<Offset>> trails, double progress) {
    final n = trails.length;
    for (var i = n - 1; i >= 0; i--) {
      final q = ((progress * n) - i).clamp(0.0, 1.0);
      if (q > 0) return CineTimeline._along(trails[i], q);
    }
    return null;
  }
}

/// Plays the cold open. [onDone] fires when it ends or is skipped.
class CinematicPlayer extends StatefulWidget {
  const CinematicPlayer({super.key, required this.onDone, this.reducedMotion = false, this.onSfx});
  final VoidCallback onDone;
  final bool reducedMotion;
  final void Function(String name)? onSfx;

  @override
  State<CinematicPlayer> createState() => _CinematicPlayerState();
}

class _CinematicPlayerState extends State<CinematicPlayer> with SingleTickerProviderStateMixin {
  CineTimeline? _tl;
  final Map<String, ui.Image> _plates = {};
  late final Ticker _ticker;
  double _t = 0;
  int _shot = 0;
  double _shotStart = 0;
  final Set<String> _sfxDone = {};
  bool _done = false;
  // the plates that live (tools/art/fx_zones/cine.py): their masks, and the scenes' shader
  final Map<String, ui.Image> _masks = {};
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    LumenPrint.warm();
    _ticker = createTicker(_tick);
    CineTimeline.load().then((tl) async {
      if (!mounted) return;
      _tl = tl;
      final names = <String>{};
      for (final s in tl.shots) {
        if (s['plate'] != null) names.add(s['plate'] as String);
        for (final l in (s['layers'] as List? ?? const [])) {
          if (l['plate'] != null) names.add(l['plate'] as String);
        }
      }
      // the plates that live: their masks and the shader, streaming in like the plates
      for (final n in names) {
        final fx = SceneFx.of('$cineDir/$n.webp');
        if (fx == null) continue;
        AtlasCache.load(fx.mask).then((m) {
          if (mounted) _masks[n] = m;
        }).catchError((Object _) {});
      }
      SceneFx.program().then((p) {
        if (mounted && p != null) _shader ??= p.fragmentShader();
      });
      // the first two plates before we start; the rest stream in
      final list = names.toList();
      for (final n in list.take(2)) {
        _plates[n] = await AtlasCache.load('$cineDir/$n.webp');
      }
      for (final n in list.skip(2)) {
        AtlasCache.load('$cineDir/$n.webp').then((im) {
          if (mounted) setState(() => _plates[n] = im);
        }).catchError((Object _) {}); // a plate missing from the pack: its shot shows the one before
      }
      if (!mounted) return;
      setState(() {});
      _ticker.start();
    }).catchError((_) {
      // no cinematic pack in this build: straight on
      if (mounted) _finish();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  void _tick(Duration d) {
    final tl = _tl;
    if (tl == null || _done) return;
    final speed = widget.reducedMotion ? 1.6 : 1.0;
    final t = d.inMicroseconds / 1e6 * speed;
    var shot = _shot;
    var start = _shotStart;
    while (shot < tl.shots.length && t - start >= (tl.shots[shot]['dur'] as num).toDouble()) {
      start += (tl.shots[shot]['dur'] as num).toDouble();
      shot++;
    }
    if (shot >= tl.shots.length) {
      _finish();
      return;
    }
    final s = tl.shots[shot];
    final sfx = s['sfx'] as Map<String, dynamic>?;
    if (sfx != null) {
      final key = '${s['id']}:${sfx['name']}';
      if (t - start >= (sfx['t'] as num).toDouble() && !_sfxDone.contains(key)) {
        _sfxDone.add(key);
        widget.onSfx?.call(sfx['name'] as String);
      }
    }
    setState(() {
      _t = t;
      _shot = shot;
      _shotStart = start;
    });
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _ticker.stop();
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final tl = _tl;
    return Material(
      color: Colors.black,
      child: Stack(fit: StackFit.expand, children: [
        if (tl != null)
          CustomPaint(
            painter: _CinePainter(tl, _plates, _shot, _t - _shotStart, DefaultTextStyle.of(context).style,
                live: widget.reducedMotion ? null : (shader: _shader, masks: _masks, t: _t)),
            willChange: true,
          ),
        Positioned(
          right: 16,
          top: MediaQuery.of(context).padding.top + 12,
          child: Semantics(
            button: true,
            label: 'Skip intro',
            child: GestureDetector(
              onTap: _finish,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0x66140E0A),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0x88FFE5A2)),
                ),
                child: const Text('Skip', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFFFFF0DE))),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _CinePainter extends CustomPainter {
  _CinePainter(this.tl, this.plates, this.shotIndex, this.ts, this.textStyle, {this.live});
  final CineTimeline tl;
  final Map<String, ui.Image> plates;
  final int shotIndex;
  final double ts; // seconds into the shot
  final TextStyle textStyle;

  /// the living plates (trees, water, lights: live_scene.dart's shader and emitters); null under reduced
  /// motion, when they stay still with their lights on
  final ({ui.FragmentShader? shader, Map<String, ui.Image> masks, double t})? live;

  Size _size(ui.Image im) => Size(im.width.toDouble(), im.height.toDouble());

  CineCamera _camera(Map<String, dynamic> shot, ui.Image plate, double ts) {
    final c = shot['camera'] as Map<String, dynamic>?;
    final name = shot['plate'] as String;
    if (c == null) return CineCamera(Offset(plate.width / 2, plate.height / 2), 1);
    final f = c['from'] as Map<String, dynamic>, t = c['to'] as Map<String, dynamic>;
    final k = _ease(ts / (shot['dur'] as num).toDouble(), (c['ease'] as String?) ?? 'inout');
    Offset centre(Map<String, dynamic> spec) {
      final cx = spec['cx'];
      if (cx is String) return tl.platePoint(name, cx, _size(plate));
      return tl.platePoint(name, [cx, spec['cy']], _size(plate));
    }
    final cf = centre(f), ct = centre(t);
    return CineCamera(Offset.lerp(cf, ct, k)!, ui.lerpDouble((f['zoom'] as num).toDouble(), (t['zoom'] as num).toDouble(), k)!);
  }

  void _drawPlate(Canvas c, Size size, ui.Image im, ({double scale, Offset origin}) g, {Paint? paint, String? name}) {
    final src = Rect.fromLTWH(g.origin.dx, g.origin.dy, size.width / g.scale, size.height / g.scale);
    final fx = name == null ? null : SceneFx.of('$cineDir/$name.webp');
    final lv = live;
    final mask = lv?.masks[name];
    final sh = lv?.shader;
    if (fx != null && lv != null && sh != null && mask != null && mask.width == im.width && mask.height == im.height) {
      // alive: the scenes' own shader (trees sway, the fall runs, windows breathe), the whole plate placed as the
      // camera has it
      final whole = Rect.fromLTWH(-g.origin.dx * g.scale, -g.origin.dy * g.scale, im.width * g.scale, im.height * g.scale);
      sh
        ..setFloat(0, whole.left)
        ..setFloat(1, whole.top)
        ..setFloat(2, whole.width)
        ..setFloat(3, whole.height)
        ..setFloat(4, im.width.toDouble())
        ..setFloat(5, im.height.toDouble())
        ..setFloat(6, lv.t % 600.0)
        ..setFloat(7, fx.wind)
        ..setFloat(8, 0)
        ..setFloat(9, 0)
        ..setImageSampler(0, im)
        ..setImageSampler(1, mask);
      c.drawRect(Offset.zero & size, (paint ?? Paint())..shader = sh..filterQuality = FilterQuality.medium);
    } else {
      c.drawImageRect(im, src, Offset.zero & size, paint ?? (Paint()..filterQuality = FilterQuality.medium));
    }
    if (fx != null) {
      // its lights, smoke and fireflies, in the plate's own px under the camera
      c.save();
      c.clipRect(Offset.zero & size);
      c.translate(-g.origin.dx * g.scale, -g.origin.dy * g.scale);
      c.scale(g.scale);
      SceneFx.paintEmitters(c, fx, (lv?.t ?? 0) % 600.0, moving: lv != null);
      c.restore();
    }
  }

  @override
  void paint(Canvas c, Size size) {
    final shot = tl.shots[shotIndex];
    _paintShot(c, size, shot, ts);
    // a shot with an xfade dissolves in over the last moment of the one before (painted again, held at its end),
    // rather than cutting
    final xf = (shot['xfade'] as num?)?.toDouble();
    if (xf != null && shotIndex > 0 && ts < xf) {
      final prev = tl.shots[shotIndex - 1];
      final k = 1 - _ease(ts / xf, 'inout');
      c.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: k));
      _paintShot(c, size, prev, (prev['dur'] as num).toDouble());
      c.restore();
    }
    final cap = shot['caption'] as Map<String, dynamic>?;
    if (cap != null) {
      final tin = (cap['in'] as num).toDouble(), tout = (cap['out'] as num).toDouble();
      if (ts >= tin && ts <= tout) {
        final a = math.min(1.0, math.min((ts - tin) / 0.4, (tout - ts) / 0.4));
        _caption(c, size, cap['text'] as String, a);
      }
    }
  }

  void _paintShot(Canvas c, Size size, Map<String, dynamic> shot, double ts) {
    c.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final plateName = shot['plate'] as String?;
    final ui.Image? plate = plateName == null ? null : plates[plateName];
    ({double scale, Offset origin})? g;
    CineCamera? cam;
    if (plate != null) {
      cam = _camera(shot, plate, ts);
      g = cam.fit(size, _size(plate));
      _drawPlate(c, size, plate, g, name: plateName);
    }
    for (final L in (shot['layers'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final kind = L['kind'] as String;
      if (kind == 'reveal' && plate != null && g != null) {
        final over = plates[L['plate'] as String];
        if (over == null) continue;
        var p = ((ts - (L['from'] as num).toDouble()) / math.max(1e-6, (L['to'] as num).toDouble() - (L['from'] as num).toDouble())).clamp(0.0, 1.0);
        if (L['reverse'] == true) p = 1.0;
        if (L['flicker'] == true && p > 0 && p < 1) {
          final on = (math.sin(ts * 47.0) * math.sin(ts * 13.0)) > -0.5;
          p = p * (on ? 1.0 : 0.55);
        }
        var alpha = 1.0;
        if (L['dim_to'] != null) {
          alpha = 1.0 - ((ts - (L['dim_from'] as num).toDouble()) / ((L['dim_to'] as num).toDouble() - (L['dim_from'] as num).toDouble())).clamp(0.0, 1.0);
        }
        if (p <= 0 || alpha <= 0) continue;
        final how = L['how'] as String;
        // the over plate, through a mask that grows along the trails or in from the edges, drawn in plate space
        // under the shot's camera
        c.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: alpha));
        c.save();
        c.translate(-g.origin.dx * g.scale, -g.origin.dy * g.scale);
        c.scale(g.scale);
        final plateRect = Rect.fromLTWH(0, 0, over.width.toDouble(), over.height.toDouble());
        // the mask first (white where the over plate shows), then the over plate kept only inside it (srcIn): a
        // mask drawn over the picture with dstIn would leave everything outside its own strokes untouched, so the
        // whole lit plate showed at once
        c.saveLayer(plateRect, Paint());
        if (how == 'trails' || how == 'trail') {
          final keys = how == 'trail' ? [L['trail'] as String] : tl.trailKeys(L['plate'] as String);
          final trails = [for (final k in keys) tl.trail(L['plate'] as String, k)];
          final sc = ((tl.plateMeta(L['plate'] as String)['scale'] as num?) ?? 1).toDouble();
          final width = 28.0 * sc;
          // one trail grows by distance along it (so it can follow footsteps walking it); all of them by point,
          // in order, as they always have
          final path = how == 'trail' ? TrailReveal.span(trails.first, 0, p) : TrailReveal.path(trails, p);
          c.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = width
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.3)
                ..color = Colors.white);
          c.drawImage(over, Offset.zero, Paint()..blendMode = BlendMode.srcIn);
          c.restore();
          if (L['glow'] == true && p < 1) {
            final tip = how == 'trail' ? TrailReveal.at(trails.first, p) : TrailReveal.tip(trails, p);
            if (tip != null) {
              c.drawCircle(
                  tip,
                  width * 2.2,
                  Paint()
                    ..blendMode = BlendMode.plus
                    ..shader = ui.Gradient.radial(tip, width * 2.2, [const Color(0x99FFC24E), const Color(0x00FFC24E)]));
            }
          }
        } else {
          _edgeMask(c, plateRect, p);
          c.drawImage(over, Offset.zero, Paint()..blendMode = BlendMode.srcIn);
          c.restore();
        }
        c.restore();
        c.restore();
      } else if (kind == 'print') {
        final t0 = (L['in'] as num).toDouble();
        if (ts < t0) continue;
        final sz = (L['size'] as num).toDouble() * size.height;
        final pulse = 1 + 0.25 * math.sin((ts - t0) * 2 * math.pi / math.max(0.2, ((L['pulse'] as num?) ?? 1).toDouble()));
        final rise = ((ts - t0) / math.max(1e-3, ((L['rise'] as num?) ?? 0.2).toDouble())).clamp(0.0, 1.0);
        Offset at;
        if (plate == null || g == null) {
          final a = L['at'] as List;
          at = Offset((a[0] as num).toDouble() * size.width, (a[1] as num).toDouble() * size.height);
        } else {
          final pp = tl.platePoint(plateName!, L['at'] as Object, _size(plate));
          at = Offset((pp.dx - g.origin.dx) * g.scale, (pp.dy - g.origin.dy) * g.scale);
        }
        LumenPrint.paint(c, at, sz, strength: rise * (0.85 + 0.15 * pulse));
      } else if (kind == 'steps' && plate != null && g != null) {
        // footsteps walking a trail: each print lands, flares and cools, the newest leading the light
        final t0 = (L['from'] as num).toDouble(), t1 = (L['to'] as num).toDouble();
        if (ts < t0) continue;
        final pts = tl.trail((L['plate'] as String?) ?? plateName!, L['trail'] as String);
        final sp = [for (final q in pts) Offset((q.dx - g.origin.dx) * g.scale, (q.dy - g.origin.dy) * g.scale)];
        final a = ((L['start'] as num?) ?? 0).toDouble(), b = ((L['end'] as num?) ?? 1).toDouble();
        final u = ((ts - t0) / math.max(1e-3, t1 - t0)).clamp(0.0, 1.0);
        FootTrail.walk(c, sp, a + (b - a) * u,
            from: a,
            stride: (L['stride'] as num).toDouble() * size.height,
            size: (L['size'] as num).toDouble() * size.height,
            squash: ((L['squash'] as num?) ?? 0.8).toDouble(),
            ember: ((L['ember'] as num?) ?? 0.3).toDouble(),
            seed: 11);
      } else if (kind == 'walkers' && plate != null && g != null) {
        final keys = tl.trailKeys(plateName!);
        if (keys.isEmpty) continue;
        final n = (L['n'] as num).toInt();
        final speed = (L['speed'] as num).toDouble();
        final r = (L['size'] as num).toDouble() * size.height;
        final ink = Paint()..color = const Color(0xFF46320F).withValues(alpha: 0.9);
        for (var i = 0; i < n; i++) {
          final pts = tl.trail(plateName, keys[i % keys.length]);
          final ph = (ts * speed + i * 0.37) % 1.0;
          // the prints it leaves on the lit trail behind it, fading a few steps back
          final sp = [for (final q in pts) Offset((q.dx - g.origin.dx) * g.scale, (q.dy - g.origin.dy) * g.scale)];
          FootTrail.walk(c, sp, ph, stride: r * 1.35, size: r * 1.05, squash: 0.8, ember: 0.3, flare: r * 2.2, fadeLen: r * 11, seed: i);
          final q = CineTimeline._along(pts, ph);
          final at = Offset((q.dx - g.origin.dx) * g.scale, (q.dy - g.origin.dy) * g.scale - r * 0.8);
          final bob = 1 + 0.1 * math.sin(ts * 9 + i);
          c.drawOval(Rect.fromCenter(center: at, width: r * 1.6 * bob, height: r * 1.8), ink);
          c.drawOval(Rect.fromCenter(center: at.translate(0, -r * 1.1), width: r * 0.8, height: r * 1.0), ink);
        }
      } else if (kind == 'birds' && plate != null && g != null) {
        // a few birds flying home across the dusk sky, wings beating, in the plate's own px under the camera
        final n = ((L['n'] as num?) ?? 4).toInt();
        final band = (L['y'] as List).cast<num>();
        final speed = ((L['speed'] as num?) ?? 60).toDouble(); // plate px a second
        final sz = ((L['size'] as num?) ?? 7).toDouble();
        final ink = Paint()
          ..color = const Color(0xFF2B2740).withValues(alpha: 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = sz * 0.32 * g.scale
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        final pw = plate.width.toDouble();
        for (var i = 0; i < n; i++) {
          final r1 = math.sin(i * 12.9898) * 43758.5453, r2 = math.sin(i * 78.233) * 12345.6789;
          final f1 = r1 - r1.floorToDouble(), f2 = r2 - r2.floorToDouble();
          // a loose flock: each its own height, lag and pace
          final x = (f1 * pw * 0.6 + (ts + 14) * speed * (0.85 + 0.3 * f2)) % (pw + 80) - 40;
          final y = band[0] + (band[1] - band[0]) * f2 + math.sin(ts * 0.9 + i) * 4;
          final flap = math.sin(ts * (8.5 + 3 * f1) + i * 2.1);
          final at = Offset((x - g.origin.dx) * g.scale, (y - g.origin.dy) * g.scale);
          final w = sz * g.scale, up = (0.15 + 0.55 * flap) * sz * g.scale;
          c.drawPath(
              Path()
                ..moveTo(at.dx - w, at.dy - up)
                ..quadraticBezierTo(at.dx - w * 0.45, at.dy - up * 0.2, at.dx, at.dy)
                ..quadraticBezierTo(at.dx + w * 0.45, at.dy - up * 0.2, at.dx + w, at.dy - up),
              ink);
        }
      } else if (kind == 'fade') {
        final k = ((ts - (L['from'] as num).toDouble()) / (L['dur'] as num).toDouble()).clamp(0.0, 1.0);
        c.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: k));
      }
    }
  }

  void _edgeMask(Canvas c, Rect plate, double p) {
    // a ring of soft blobs around the edges, growing inward: the mask the over plate is then kept inside
    final cx = plate.center;
    final maxR = plate.longestSide * 0.85;
    final mask = Path();
    final rnd = math.Random(3);
    for (var i = 0; i < 48; i++) {
      final a = i / 48 * 2 * math.pi;
      final edge = Offset(cx.dx + math.cos(a) * plate.width * 0.62, cx.dy + math.sin(a) * plate.height * 0.62);
      final bias = 0.6 + 0.4 * (1 - (math.sin(a) + 1) / 2); // the top edge reaches further
      final reach = (p * bias * 1.3 + rnd.nextDouble() * 0.12 - 0.06).clamp(0.0, 1.0);
      final tip = Offset.lerp(edge, cx, reach)!;
      final r = plate.shortestSide * (0.07 + 0.08 * reach) + rnd.nextDouble() * 6;
      mask.addOval(Rect.fromCircle(center: tip, radius: r));
      mask.addOval(Rect.fromCircle(center: Offset.lerp(edge, tip, 0.5)!, radius: r * 1.3));
      mask.addOval(Rect.fromCircle(center: edge, radius: maxR * 0.14 + r));
    }
    c.drawPath(mask, Paint()..color = Colors.white..maskFilter = MaskFilter.blur(BlurStyle.normal, plate.shortestSide * 0.03));
  }

  void _caption(Canvas c, Size size, String text, double alpha) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: size.height * 0.024, color: const Color(0xFFFFF0DE).withValues(alpha: alpha), height: 1.3)),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width * 0.82);
    final x = (size.width - tp.width) / 2, y = size.height * 0.80;
    final box = RRect.fromRectAndRadius(Rect.fromLTWH(x - 22, y - 14, tp.width + 44, tp.height + 28), const Radius.circular(18));
    c.drawRRect(box, Paint()..color = const Color(0xFF140E0A).withValues(alpha: 0.58 * alpha));
    tp.paint(c, Offset(x, y));
  }

  @override
  bool shouldRepaint(_CinePainter o) => true;
}


// ------------------------------------------------------------------------------------ shared plate pieces ----
/// A cinematic plate (assets/art/cine/<name>.webp), decoded once; nothing while it loads, [onMissing] when the
/// pack doesn't have it.
class CinePlate extends StatefulWidget {
  const CinePlate(this.name, {super.key, this.fit = BoxFit.cover, this.alignment = Alignment.center, this.onMissing});
  final String name;
  final BoxFit fit;
  final Alignment alignment;
  final Widget? onMissing;
  @override
  State<CinePlate> createState() => _CinePlateState();
}

class _CinePlateState extends State<CinePlate> {
  ui.Image? _im;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    AtlasCache.load('$cineDir/${widget.name}.webp').then((im) {
      if (mounted) setState(() => _im = im);
    }).catchError((_) {
      if (mounted) setState(() => _missing = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final im = _im;
    if (im == null) return _missing ? (widget.onMissing ?? const SizedBox.shrink()) : const SizedBox.shrink();
    return RawImage(image: im, fit: widget.fit, alignment: widget.alignment, filterQuality: FilterQuality.medium);
  }
}

/// Where a plate's points land once it is drawn into a box the way [CinePlate] draws it (cover or width-fit, with
/// an alignment). [plate] is the plate's size in cine.json units (its 'w' and 'h'), so anchors map directly.
class CineFit {
  factory CineFit(Size box, Size plate, {Alignment alignment = Alignment.center, bool cover = true}) {
    final k = cover ? math.max(box.width / plate.width, box.height / plate.height) : box.width / plate.width;
    final dx = (box.width - plate.width * k) * (alignment.x + 1) / 2;
    final dy = (box.height - plate.height * k) * (alignment.y + 1) / 2;
    return CineFit._(k, Offset(dx, dy));
  }
  CineFit._(this.k, this.origin);
  final double k;
  final Offset origin;
  Offset point(Offset p) => origin + p * k;

  /// an anchor from a plate's cine.json entry, or null when it has none by that name
  static Offset? anchor(Map<String, dynamic> meta, String name) {
    final a = (meta['anchors'] as Map<String, dynamic>?)?[name] as List?;
    return a == null ? null : Offset((a[0] as num).toDouble(), (a[1] as num).toDouble());
  }

  static Size plateSize(Map<String, dynamic> meta) => Size((meta['w'] as num).toDouble(), (meta['h'] as num).toDouble());
}

/// A villager's line over a plate: their name as a tag, the line under it. The card rises in, then the line
/// writes itself out (a tap finishes it); the words not yet written already hold their place, so nothing
/// reflows. Under reduced motion the line is simply there.
class SpeechCard extends StatefulWidget {
  const SpeechCard({super.key, required this.name, required this.text, this.delay = const Duration(milliseconds: 120)});
  final String name;
  final String text;
  final Duration delay;
  @override
  State<SpeechCard> createState() => _SpeechCardState();
}

class _SpeechCardState extends State<SpeechCard> with SingleTickerProviderStateMixin {
  static const _perChar = 0.026; // seconds: about 38 characters a second
  late final AnimationController _a = AnimationController(vsync: this);
  Timer? _wait;

  @override
  void initState() {
    super.initState();
    _start();
  }

  @override
  void didUpdateWidget(SpeechCard old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) _start();
  }

  void _start() {
    _wait?.cancel();
    if (Motion.reducedNow(context)) {
      _a.value = 1;
      return;
    }
    _a.value = 0;
    _a.duration = Duration(milliseconds: (widget.text.length * _perChar * 1000).round());
    // the line starts writing as the card finishes rising in
    _wait = Timer(widget.delay + Motion.base * 0.6, () {
      if (mounted) _a.forward();
    });
  }

  @override
  void dispose() {
    _wait?.cancel();
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Entrance(
        delay: widget.delay,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            _wait?.cancel();
            _a.value = 1;
          },
          child: GameCard(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.name, style: EvochiText.tag),
              Semantics(
                label: widget.text,
                child: ExcludeSemantics(
                  child: AnimatedBuilder(
                    animation: _a,
                    builder: (_, __) {
                      final n = (widget.text.length * _a.value).round();
                      return Text.rich(TextSpan(style: EvochiText.bodyText, children: [
                        TextSpan(text: widget.text.substring(0, n)),
                        TextSpan(text: widget.text.substring(n), style: const TextStyle(color: Color(0x00000000))),
                      ]));
                    },
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}
