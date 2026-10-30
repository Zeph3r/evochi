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

import '../../app/theme.dart';
import '../../core/services/asset_manifest.dart';
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

/// The golden footprint: the one effect the whole onboarding shares. Drawn additively from the rendered sprite
/// (cine/lumen_print.webp, on black) with a slow pulse, or as a soft procedural glow before the sprite loads.
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
  ui.Image? _prevFrame;
  bool _done = false;

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
            painter: _CinePainter(tl, _plates, _shot, _t - _shotStart, _prevFrame, DefaultTextStyle.of(context).style),
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
  _CinePainter(this.tl, this.plates, this.shotIndex, this.ts, this.prev, this.textStyle);
  final CineTimeline tl;
  final Map<String, ui.Image> plates;
  final int shotIndex;
  final double ts; // seconds into the shot
  final ui.Image? prev;
  final TextStyle textStyle;

  Size _size(ui.Image im) => Size(im.width.toDouble(), im.height.toDouble());

  CineCamera _camera(Map<String, dynamic> shot, ui.Image plate) {
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

  void _drawPlate(Canvas c, Size size, ui.Image im, ({double scale, Offset origin}) g, {Paint? paint}) {
    final src = Rect.fromLTWH(g.origin.dx, g.origin.dy, size.width / g.scale, size.height / g.scale);
    c.drawImageRect(im, src, Offset.zero & size, paint ?? (Paint()..filterQuality = FilterQuality.medium));
  }

  @override
  void paint(Canvas c, Size size) {
    final shot = tl.shots[shotIndex];
    c.drawRect(Offset.zero & size, Paint()..color = Colors.black);
    final plateName = shot['plate'] as String?;
    final ui.Image? plate = plateName == null ? null : plates[plateName];
    ({double scale, Offset origin})? g;
    CineCamera? cam;
    if (plate != null) {
      cam = _camera(shot, plate);
      g = cam.fit(size, _size(plate));
      _drawPlate(c, size, plate, g);
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
        // the over plate, through a mask (dstIn) that grows along the trails or in from the edges, drawn in
        // plate space under the shot's camera
        c.saveLayer(Offset.zero & size, Paint()..color = Colors.white.withValues(alpha: alpha));
        c.save();
        c.translate(-g.origin.dx * g.scale, -g.origin.dy * g.scale);
        c.scale(g.scale);
        final plateRect = Rect.fromLTWH(0, 0, over.width.toDouble(), over.height.toDouble());
        c.saveLayer(plateRect, Paint());
        c.drawImage(over, Offset.zero, Paint());
        if (how == 'trails' || how == 'trail') {
          final keys = how == 'trail' ? [L['trail'] as String] : tl.trailKeys(L['plate'] as String);
          final trails = [for (final k in keys) tl.trail(L['plate'] as String, k)];
          final sc = ((tl.plateMeta(L['plate'] as String)['scale'] as num?) ?? 1).toDouble();
          final width = 28.0 * sc;
          final path = TrailReveal.path(trails, p);
          c.drawPath(
              path,
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = width
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round
                ..blendMode = BlendMode.dstIn
                ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * 0.3)
                ..color = Colors.white);
          c.restore();
          if (L['glow'] == true && p < 1) {
            final tip = TrailReveal.tip(trails, p);
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
          final q = CineTimeline._along(pts, ph);
          final at = Offset((q.dx - g.origin.dx) * g.scale, (q.dy - g.origin.dy) * g.scale - r * 0.8);
          final bob = 1 + 0.1 * math.sin(ts * 9 + i);
          c.drawOval(Rect.fromCenter(center: at, width: r * 1.6 * bob, height: r * 1.8), ink);
          c.drawOval(Rect.fromCenter(center: at.translate(0, -r * 1.1), width: r * 0.8, height: r * 1.0), ink);
        }
      } else if (kind == 'fade') {
        final k = ((ts - (L['from'] as num).toDouble()) / (L['dur'] as num).toDouble()).clamp(0.0, 1.0);
        c.drawRect(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: k));
      }
    }
    final xf = (shot['xfade'] as num?)?.toDouble();
    if (xf != null && prev != null && ts < xf) {
      final k = 1 - _ease(ts / xf, 'inout');
      c.drawImageRect(prev!, Rect.fromLTWH(0, 0, prev!.width.toDouble(), prev!.height.toDouble()), Offset.zero & size,
          Paint()..color = Colors.white.withValues(alpha: k));
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

  void _edgeMask(Canvas c, Rect plate, double p) {
    // a ring of soft blobs around the edges, growing inward: dstIn keeps the over plate where they are
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
    c.drawPath(mask, Paint()..blendMode = BlendMode.dstIn..color = Colors.white..maskFilter = MaskFilter.blur(BlurStyle.normal, plate.shortestSide * 0.03));
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

/// A villager's line over a plate: their name as a tag, the line under it.
class SpeechCard extends StatelessWidget {
  const SpeechCard({super.key, required this.name, required this.text});
  final String name;
  final String text;
  @override
  Widget build(BuildContext context) => GameCard(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name, style: EvochiText.tag),
          Text(text, style: EvochiText.bodyText),
        ]),
      );
}
