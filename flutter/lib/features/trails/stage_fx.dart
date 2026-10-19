// Canvas effects for the encounter stage: particles, trails, rings, rays and glows on two layers (one
// behind the creatures, one in front), drawn from soft pre-rendered sprites with additive light, and the
// encounter board's effect library (Lumen Wisps, Flower Petals, Healing Sparkles, Golden Pulse, Hollow
// Shards, Violet Crackle, Dust Burst).
//
// Positions are fractions of the world box (the backdrop), like [ShotGeometry]; sizes and speeds are
// in units of 1% of the world's width ("u"), so an effect looks the same on any phone. One clock,
// driven by a [Ticker], that the turn choreography can freeze for a hit-stop. Port of web/src/ui/fx.js.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

const _tau = math.pi * 2;
const _spriteSize = 96.0; // the pre-rendered sprites' edge, in their own pixels
const _spriteOrigin = Offset(-_spriteSize / 2, -_spriteSize / 2);

/// core, mid, edge
const Map<String, List<Color>> fxPalettes = {
  'gold': [Color(0xFFFFFFFF), Color(0xFFFFF1B8), Color(0xFFFFC24A)],
  'violet': [Color(0xFFFFFFFF), Color(0xFFE9DBFF), Color(0xFF9B6BE8)],
  'dark': [Color(0xFF6A48B8), Color(0xFF3D2670), Color(0xFF1C1038)],
  'teal': [Color(0xFFFFFFFF), Color(0xFFCFF7E6), Color(0xFF4FBF99)],
  'pink': [Color(0xFFFFFFFF), Color(0xFFFDD6DE), Color(0xFFF28CA6)],
  'dust': [Color(0xFFF1E9D6), Color(0xFFD8CBB0), Color(0xFFB9AB90)],
  'white': [Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF)],
  'red': [Color(0xFFFFFFFF), Color(0xFFFFD0C4), Color(0xFFF06A5A)],
  'green': [Color(0xFFFFFFFF), Color(0xFFDDF5C8), Color(0xFF7AC24F)],
  'leaf': [Color(0xFFF2FFE0), Color(0xFF9FDB6A), Color(0xFF4E9E3A)],
  'crystal': [Color(0xFFF3E9FF), Color(0xFF8B5BD8), Color(0xFF3A2368)],
  'rock': [Color(0xFFE9DFCB), Color(0xFFB5A58A), Color(0xFF7D6E58)],
};

List<Color> _pal(String name) => fxPalettes[name] ?? fxPalettes['white']!;

final math.Random _random = math.Random();
double _rnd(double a, double b) => a + _random.nextDouble() * (b - a);
double _easeOut(double t) => 1 - (1 - t) * (1 - t);
double _easeIn(double t) => t * t;
double _easeInOut(double t) => t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) * (-2 * t + 2) / 2;
double _clamp01(double t) => t < 0 ? 0 : (t > 1 ? 1 : t);
Color _withA(Color c, double a) => c.withAlpha((_clamp01(a) * 255).round());

/// size over life
double _sizeK(String k, double t) {
  switch (k) {
    case 'hold':
      return 1;
    case 'grow':
      return 0.3 + 0.7 * _easeOut(t);
    case 'pop':
      return t < 0.18 ? 0.4 + 0.75 * (t / 0.18) : 1.15 - 0.3 * ((t - 0.18) / 0.82);
    case 'spark':
      return t < 0.12 ? 0.5 + 0.5 * (t / 0.12) : 1 - 0.9 * math.pow((t - 0.12) / 0.88, 1.4).toDouble();
    case 'bloom':
      return 0.2 + 1.3 * _easeOut(t);
    default: // shrink
      return 1 - t * 0.85;
  }
}

/// alpha over life
double _alphaK(String k, double t) {
  switch (k) {
    case 'fade2':
      return (1 - t) * (1 - t);
    case 'inout':
      return t < 0.25 ? t / 0.25 : 1 - (t - 0.25) / 0.75;
    case 'hold':
      return t < 0.7 ? 1 : 1 - (t - 0.7) / 0.3;
    case 'flash':
      return t < 0.1 ? 1 : math.pow(1 - (t - 0.1) / 0.9, 2).toDouble();
    case 'soft':
      return math.sin(t * math.pi);
    default: // fade
      return 1 - t;
  }
}

// ------------------------------------------------------------------ sprites
final Map<String, ui.Image> _spriteCache = {};

/// A soft sprite for a shape in a palette, rendered once and cached (the web's offscreen canvases).
ui.Image _sprite(String shape, String pal) {
  final key = '$shape|$pal';
  final hit = _spriteCache[key];
  if (hit != null) return hit;
  final colors = _pal(pal);
  final core = colors[0];
  final mid = colors[1];
  final edge = colors[2];
  const s = _spriteSize;
  const h = s / 2;
  const c = Offset(h, h);
  const box = Rect.fromLTWH(0, 0, s, s);
  const u = s / 64; // the web's sprites are 64 px: its absolute pixel sizes scale by this
  Path poly(List<Offset> pts) {
    final p = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (final q in pts.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    return p..close();
  }

  final rec = ui.PictureRecorder();
  final g = Canvas(rec, box);
  final paint = Paint();
  switch (shape) {
    case 'dot':
      paint.shader = ui.Gradient.radial(c, h, [core, mid, _withA(edge, 0.9), _withA(edge, 0)], [0, 0.5, 0.78, 1]);
      g.drawRect(box, paint);
    case 'puff':
      paint.shader = ui.Gradient.radial(c, h, [_withA(mid, 0.55), _withA(edge, 0.25), _withA(edge, 0)], [0, 0.6, 1]);
      g.drawRect(box, paint);
    case 'star':
      final p = Path();
      for (var i = 0; i < 8; i++) {
        final a = (i / 8) * _tau - math.pi / 2;
        final rr = i.isOdd ? h * 0.3 : h * 0.95;
        final pt = Offset(h + math.cos(a) * rr, h + math.sin(a) * rr);
        if (i == 0) {
          p.moveTo(pt.dx, pt.dy);
        } else {
          p.lineTo(pt.dx, pt.dy);
        }
      }
      p.close();
      g.drawPath(
        p,
        Paint()
          ..color = edge
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3 * s / 64),
      );
      g.drawPath(p, Paint()..color = mid);
      g.drawCircle(c, h * 0.22, Paint()..color = core);
    case 'shard':
      // a long diamond along x, bright in the middle: drawn stretched in the direction of flight
      paint.shader = ui.Gradient.linear(const Offset(0, h), const Offset(s, h), [_withA(edge, 0), mid, core, mid, _withA(edge, 0)], [0, 0.35, 0.5, 0.65, 1]);
      final p = Path()
        ..moveTo(0, h)
        ..quadraticBezierTo(h, h - s * 0.16, s, h)
        ..quadraticBezierTo(h, h + s * 0.16, 0, h);
      g.drawPath(p, paint);
    case 'petal':
      g.translate(h, h);
      paint.shader = ui.Gradient.linear(const Offset(-h, 0), const Offset(h, 0), [mid, edge]);
      final p = Path()
        ..moveTo(-h * 0.9, 0)
        ..cubicTo(-h * 0.5, -h * 0.75, h * 0.5, -h * 0.75, h * 0.9, 0)
        ..cubicTo(h * 0.5, h * 0.55, -h * 0.5, h * 0.55, -h * 0.9, 0);
      g.drawPath(p, paint);
      g.save();
      g.translate(-h * 0.25, -h * 0.15);
      g.rotate(-0.4);
      g.drawOval(Rect.fromCenter(center: Offset.zero, width: h * 0.5, height: h * 0.24), Paint()..color = _withA(core, 0.5));
      g.restore();
    case 'heart':
      g.translate(h, h * 1.08);
      g.scale(h / 12, h / 12);
      final p = Path()
        ..moveTo(0, 9)
        ..cubicTo(-7.5, 4.4, -9.4, -1.3, -7, -5)
        ..cubicTo(-5, -8, -1.5, -7.5, 0, -4.5)
        ..cubicTo(1.5, -7.5, 5, -8, 7, -5)
        ..cubicTo(9.4, -1.3, 7.5, 4.4, 0, 9)
        ..close();
      g.drawPath(p, Paint()..color = edge);
      g.drawPath(
        p,
        Paint()
          ..color = core
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round,
      );
    case 'leafbit':
      g.drawOval(Rect.fromCenter(center: c, width: h * 1.6, height: h * 0.7), Paint()..color = mid);
    case 'smoke':
      paint.shader = ui.Gradient.radial(c, h, [_withA(core, 0.6), _withA(mid, 0.5), _withA(edge, 0)], [0, 0.45, 1]);
      g.drawRect(box, paint);
    case 'leaf':
      // a leaf with a soft glow and a vein (Lumen Wisps, Soothe)
      g.translate(h, h);
      g.drawRect(const Rect.fromLTWH(-h, -h, s, s), Paint()..shader = ui.Gradient.radial(Offset.zero, h, [_withA(mid, 0.55), _withA(edge, 0)]));
      paint.shader = ui.Gradient.linear(const Offset(-h * 0.6, -h * 0.4), const Offset(h * 0.6, h * 0.4), [core, mid, edge], [0, 0.45, 1]);
      final p = Path()
        ..moveTo(-h * 0.62, h * 0.05)
        ..cubicTo(-h * 0.3, -h * 0.55, h * 0.38, -h * 0.5, h * 0.62, -h * 0.05)
        ..cubicTo(h * 0.3, h * 0.42, -h * 0.32, h * 0.42, -h * 0.62, h * 0.05);
      g.drawPath(p, paint);
      final vein = Path()
        ..moveTo(-h * 0.55, h * 0.04)
        ..quadraticBezierTo(0, -h * 0.08, h * 0.55, -h * 0.05);
      g.drawPath(
        vein,
        Paint()
          ..color = _withA(core, 0.85)
          ..style = PaintingStyle.stroke
          ..strokeWidth = s * 0.025,
      );
    case 'sparkle':
      // a four-point twinkle with long thin rays (Healing Sparkles)
      g.translate(h, h);
      g.drawRect(const Rect.fromLTWH(-h, -h, s, s), Paint()..shader = ui.Gradient.radial(Offset.zero, h * 0.55, [_withA(mid, 0.8), _withA(edge, 0)]));
      g.drawPath(
        poly([
          for (var i = 0; i < 8; i++)
            Offset(math.cos((i / 8) * _tau - math.pi / 2) * (i.isOdd ? h * 0.11 : h * 0.96), math.sin((i / 8) * _tau - math.pi / 2) * (i.isOdd ? h * 0.11 : h * 0.96)),
        ]),
        Paint()..color = core,
      );
    case 'plus':
      // a rounded plus (Soothe's recovery)
      g.translate(h, h);
      g.drawRect(const Rect.fromLTWH(-h, -h, s, s), Paint()..shader = ui.Gradient.radial(Offset.zero, h, [_withA(mid, 0.5), _withA(edge, 0)]));
      const w = h * 0.32;
      const l = h * 0.72;
      final outer = Paint()..color = edge;
      final inner = Paint()..color = core;
      g.drawRRect(RRect.fromLTRBR(-w / 2 - 2 * u, -l / 2 - 2 * u, w / 2 + 2 * u, l / 2 + 2 * u, const Radius.circular(w / 2)), outer);
      g.drawRRect(RRect.fromLTRBR(-l / 2 - 2 * u, -w / 2 - 2 * u, l / 2 + 2 * u, w / 2 + 2 * u, const Radius.circular(w / 2)), outer);
      g.drawRRect(RRect.fromLTRBR(-w / 2, -l / 2, w / 2, l / 2, const Radius.circular(w / 2)), inner);
      g.drawRRect(RRect.fromLTRBR(-l / 2, -w / 2, l / 2, w / 2, const Radius.circular(w / 2)), inner);
    case 'crystal':
      // a faceted Hollow shard (Hollow Shards)
      g.translate(h, h);
      g.drawRect(const Rect.fromLTWH(-h, -h, s, s), Paint()..shader = ui.Gradient.radial(Offset.zero, h, [_withA(mid, 0.55), _withA(mid, 0)]));
      g.drawPath(poly(const [Offset(0, -h * 0.85), Offset(h * 0.3, -h * 0.2), Offset(h * 0.18, h * 0.7), Offset(-h * 0.2, h * 0.62), Offset(-h * 0.32, -h * 0.1)]), Paint()..color = edge);
      g.drawPath(poly(const [Offset(0, -h * 0.85), Offset(h * 0.3, -h * 0.2), Offset(h * 0.18, h * 0.7), Offset(0, h * 0.1)]), Paint()..color = mid);
      g.drawLine(
        const Offset(-h * 0.04, -h * 0.7),
        const Offset(-h * 0.2, 0),
        Paint()
          ..color = _withA(core, 0.9)
          ..strokeWidth = s * 0.03,
      );
    case 'rock':
      // a chunk of stone (Dust Burst)
      g.translate(h, h);
      g.drawPath(poly(const [Offset(-h * 0.7, h * 0.1), Offset(-h * 0.45, -h * 0.55), Offset(h * 0.15, -h * 0.72), Offset(h * 0.68, -h * 0.25), Offset(h * 0.6, h * 0.45), Offset(-h * 0.1, h * 0.65)]), Paint()..color = edge);
      g.drawPath(poly(const [Offset(-h * 0.45, -h * 0.55), Offset(h * 0.15, -h * 0.72), Offset(h * 0.68, -h * 0.25), Offset(h * 0.05, -h * 0.05), Offset(-h * 0.55, 0)]), Paint()..color = mid);
      g.drawPath(poly(const [Offset(-h * 0.3, -h * 0.45), Offset(h * 0.12, -h * 0.58), Offset(h * 0.05, -h * 0.35)]), Paint()..color = _withA(core, 0.8));
    default: // glow
      paint.shader = ui.Gradient.radial(c, h, [core, mid, _withA(edge, 0.55), _withA(edge, 0)], [0, 0.22, 0.55, 1]);
      g.drawRect(box, paint);
  }
  final img = rec.endRecording().toImageSync(s.toInt(), s.toInt());
  _spriteCache[key] = img;
  return img;
}

// ------------------------------------------------------------------ particles and movers
class _Seek {
  _Seek(this.x, this.y, this.k);
  final double x, y, k;
}

class _Orbit {
  _Orbit({required this.x, required this.y, required this.r, required this.a, required this.w, required this.dr});
  final double x, y;
  double r, a;
  final double w, dr;
}

/// One particle (positions and sizes in pixels of the world box).
class FxParticle {
  FxParticle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.ax,
    required this.ay,
    required this.drag,
    required this.life,
    required this.size,
    required this.sizeK,
    required this.alpha,
    required this.alphaK,
    required this.rot,
    required this.spin,
    required this.align,
    required this.stretch,
    required this.sprite,
    required this.blend,
    required this.layer,
    required this.turb,
    required this.turbW,
    required this.ph,
    this.seek,
  });
  double x, y, vx, vy, ax, ay, drag, life, size, alpha, rot, spin, stretch, turb, turbW, ph;
  double age = 0;
  String sizeK, alphaK;
  final bool align;
  final ui.Image sprite;
  final BlendMode blend;
  final String layer;
  _Seek? seek;
  _Orbit? orbit;
  bool swirl = false; // a streamed petal that will orbit its target once it gets near
  bool dead = false;
}

abstract class _Mover {
  _Mover(this.layer);
  final String layer;
  bool dead = false;
  bool get drawUnder => false;
  void tick(double dt, StageFx fx);
  void draw(Canvas g, StageFx fx) {}
}

/// Petals (or confetti) carried toward a point along a curve.
class _Stream extends _Mover {
  _Stream(this.ax, this.ay, this.bx, this.by, this.n, this.ms, this.pal, this.shape, this.swirl, this.size) : super('front');
  final double ax, ay, bx, by, ms, size;
  final int n;
  final String pal, shape;
  final bool swirl;
  double t = 0;
  int emitted = 0;

  @override
  void tick(double dt, StageFx fx) {
    t += dt * 1000;
    final want = math.min(n, (t / ms * n).floor() + 1);
    while (emitted < want) {
      emitted++;
      final d = math.sqrt((bx - ax) * (bx - ax) + (by - ay) * (by - ay));
      final ang = math.atan2(by - ay, bx - ax);
      final part = fx.emit(Offset(ax + _rnd(-3, 3) * fx.u, ay + _rnd(-6, 6) * fx.u),
          raw: true, shape: shape, pal: pal, blend: BlendMode.srcOver, size: size * _rnd(0.7, 1.2), sizeK: 'hold', alphaK: 'hold', life: 1.8, speed: (d / fx.u) * _rnd(0.8, 1.1), angle: ang, spread: 0.2, drag: 0.95, turb: 60, turbW: _rnd(5, 9), spin: _rnd(-8, 8));
      part.seek = _Seek(bx + _rnd(-4, 4) * fx.u, by + _rnd(-4, 4) * fx.u, 6);
      if (swirl) part.swirl = true;
    }
    if (emitted >= n && t > ms + 1900) dead = true;
  }
}

/// The swirl: once near the target, a streamed petal orbits it and fades.
class _StreamNear extends _Mover {
  _StreamNear(this.bx, this.by, this.ms) : super('front');
  final double bx, by, ms;
  double t = 0;

  @override
  void tick(double dt, StageFx fx) {
    t += dt;
    for (final p in fx._ps) {
      if (!p.swirl || p.orbit != null) continue;
      final dx = p.x - bx;
      final dy = p.y - by;
      final dist = math.sqrt(dx * dx + dy * dy);
      if (dist < 9 * fx.u) {
        p.orbit = _Orbit(x: bx, y: by, r: math.max(5 * fx.u, dist), a: math.atan2(dy, dx), w: _rnd(3, 5), dr: -1.6 * fx.u);
        p.life = p.age + _rnd(0.7, 1.1);
        p.alphaK = 'hold';
      }
    }
    if (t > ms / 1000 + 2.2) dead = true;
  }
}

/// A bright head with a trail that flies from a to b along a bow; calls onArrive at the end.
class FxComet extends _Mover {
  FxComet({
    required String layer,
    required this.ax,
    required this.ay,
    required this.bx,
    required this.by,
    required this.cx,
    required this.cy,
    required this.ms,
    required this.pal,
    required this.size,
    required this.trail,
    required this.ease,
    required this.sparks,
    required this.img,
    required this.imgSize,
    required this.spin,
    required this.onArrive,
  })  : x = ax,
        y = ay,
        px = ax,
        py = ay,
        super(layer);
  final double ax, ay, bx, by, cx, cy, ms, size, imgSize, spin;
  final int trail;
  final String pal, ease;
  final bool sparks;
  final VoidCallback? onArrive;

  /// The thrown thing itself (set late if it was still loading when the comet left).
  ui.Image? img;

  /// A Lumen Wisp: a glowing leaf rides the head, swaying as it flies.
  bool leaf = false;
  double t = 0, x, y, px, py, rot = 0;

  @override
  void tick(double dt, StageFx fx) {
    t += (dt * 1000) / ms;
    final kk = _clamp01(t);
    final k = ease == 'in' ? _easeIn(kk) : (ease == 'out' ? _easeOut(kk) : _easeInOut(kk));
    px = x;
    py = y;
    x = (1 - k) * (1 - k) * ax + 2 * (1 - k) * k * cx + k * k * bx;
    y = (1 - k) * (1 - k) * ay + 2 * (1 - k) * k * cy + k * k * by;
    // trail: glow dots laid along the path this frame
    for (var i = 0; i < trail; i++) {
      final f = i / trail;
      fx.emit(Offset(px + (x - px) * f, py + (y - py) * f), raw: true, shape: 'glow', pal: pal, size: size * _rnd(0.6, 0.9), sizeK: 'shrink', alphaK: 'fade2', life: 0.32, layer: layer);
    }
    if (sparks && _random.nextDouble() < 0.8) fx.emit(Offset(x, y), raw: true, shape: 'star', pal: pal, size: size * 0.35, sizeK: 'spark', life: 0.45, speed: _rnd(6, 16), spin: 8, gravity: 30, layer: layer);
    rot += spin * dt;
    if (t >= 1) {
      dead = true;
      onArrive?.call();
    }
  }

  @override
  void draw(Canvas g, StageFx fx) {
    final sp = _sprite('glow', pal);
    final s = size * fx.u;
    final dx = x - px;
    final dy = y - py;
    final ang = math.atan2(dy, dx);
    final v = math.sqrt(dx * dx + dy * dy) / fx.u;
    final sx = 1 + math.min(2.2, v * 0.25);
    final paint = fx._paint
      ..blendMode = BlendMode.plus
      ..color = const Color(0xFFFFFFFF)
      ..colorFilter = null
      ..maskFilter = null;
    g.save();
    g.translate(x, y);
    g.rotate(ang);
    g.save();
    g.scale(s * sx / _spriteSize, s / _spriteSize);
    g.drawImage(sp, _spriteOrigin, paint);
    g.restore();
    if (img == null && !leaf) {
      g.scale(s * 0.5 / _spriteSize, s * 0.5 / _spriteSize);
      g.drawImage(sp, _spriteOrigin, paint);
    }
    g.restore();
    if (leaf) {
      final q = s * 1.1;
      paint.blendMode = BlendMode.srcOver;
      g.save();
      g.translate(x, y);
      g.rotate(ang + math.sin(t * 12) * 0.5);
      g.scale(q / _spriteSize, q / _spriteSize);
      g.drawImage(_sprite('leaf', 'leaf'), _spriteOrigin, paint);
      g.restore();
    }
    final im = img;
    if (im != null) {
      // the thrown thing itself, turning over as it flies
      final isz = imgSize * fx.u;
      final src = Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
      final dst = Rect.fromLTWH(-isz / 2, -isz / 2, isz, isz);
      g.save();
      g.translate(x, y);
      g.rotate(rot);
      g.drawImageRect(
        im,
        src,
        dst.shift(Offset(0, fx.u * 0.5)),
        Paint()
          ..colorFilter = const ColorFilter.mode(Color(0x59000000), BlendMode.srcIn)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, fx.u * 0.4)
          ..filterQuality = FilterQuality.low,
      );
      g.drawImageRect(im, src, dst, Paint()..filterQuality = FilterQuality.medium);
      g.restore();
    }
  }
}

/// A shockwave ring. r0 -> r1 in u.
class _Ring extends _Mover {
  _Ring(String layer, this.x, this.y, this.r0, this.r1, this.ms, this.pal, this.width, this.alpha, this.squash, this.blend) : super(layer);
  final double x, y, r0, r1, ms, width, alpha, squash;
  final String pal;
  final BlendMode blend;
  double t = 0;

  @override
  void tick(double dt, StageFx fx) {
    t += (dt * 1000) / ms;
    if (t >= 1) dead = true;
  }

  @override
  void draw(Canvas g, StageFx fx) {
    final colors = _pal(pal);
    final k = _easeOut(_clamp01(t));
    final r = (r0 + (r1 - r0) * k) * fx.u;
    final a = alpha * math.pow(1 - k, 1.3).toDouble();
    final w = math.max(0.5, width * fx.u * (1 - k * 0.7));
    g.save();
    g.translate(x, y);
    g.scale(1, squash);
    final glow = Paint()
      ..blendMode = blend
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = _withA(colors[2], a)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.25);
    g.drawCircle(Offset.zero, r, glow);
    final line = Paint()
      ..blendMode = blend
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..color = _withA(colors[1], a);
    g.drawCircle(Offset.zero, r, line);
    line
      ..strokeWidth = w * 0.45
      ..color = _withA(colors[0], a * 0.9);
    g.drawCircle(Offset.zero, r, line);
    g.restore();
  }
}

/// Rays of light turning slowly behind a point.
class _Rays extends _Mover {
  _Rays(String layer, this.x, this.y, this.n, this.r, this.ms, this.pal, this.alpha, this.spin)
      : rot = _rnd(0, _tau),
        super(layer);
  final double x, y, r, ms, alpha, spin;
  final int n;
  final String pal;
  double t = 0, rot;

  @override
  bool get drawUnder => true;

  @override
  void tick(double dt, StageFx fx) {
    t += (dt * 1000) / ms;
    rot += spin * dt;
    if (t >= 1) dead = true;
  }

  @override
  void draw(Canvas g, StageFx fx) {
    final colors = _pal(pal);
    final a = alpha * _alphaK('inout', _clamp01(t));
    if (a <= 0.002) return;
    final rr = r * fx.u * (0.6 + 0.4 * _easeOut(_clamp01(t * 2)));
    final paint = Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(Offset(x, y), rr, [_withA(colors[0], 0.9 * a), _withA(colors[1], 0.6 * a), _withA(colors[2], 0)], [0, 0.3, 1]);
    final rect = Rect.fromCircle(center: Offset(x, y), radius: rr);
    final w = (_tau / n) * 0.34;
    for (var i = 0; i < n; i++) {
      final a0 = rot + (i / n) * _tau;
      final p = Path()
        ..moveTo(x, y)
        ..arcTo(rect, a0 - w / 2, w, false)
        ..close();
      g.drawPath(p, paint);
    }
  }
}

/// A soft vignette pulse in a colour (the Hollow's surge), drawn in front.
class _Pulse extends _Mover {
  _Pulse(this.pal, this.ms, this.alpha) : super('front');
  final String pal;
  final double ms, alpha;
  double t = 0;

  @override
  void tick(double dt, StageFx fx) {
    t += (dt * 1000) / ms;
    if (t >= 1) dead = true;
  }

  @override
  void draw(Canvas g, StageFx fx) {
    final colors = _pal(pal);
    final a = alpha * _alphaK('soft', _clamp01(t));
    if (a <= 0.002) return;
    final c = Offset(fx.w / 2, fx.h / 2);
    final paint = Paint()
      ..blendMode = BlendMode.srcOver
      ..shader = ui.Gradient.radial(c, fx.w * 0.8, [_withA(colors[1], 0), _withA(colors[2], a)], [0.25 / 0.8, 1]);
    g.drawRect(Rect.fromLTWH(0, 0, fx.w, fx.h), paint);
  }
}

/// Motes of light leaving a body (the Hollow dissolving): emitted across a box for ms.
class _Dissolve extends _Mover {
  _Dissolve(this.box, this.n, this.ms, this.pal) : super('front');
  final Rect box; // fractions of the world
  final int n;
  final double ms;
  final String pal;
  double t = 0;
  int emitted = 0;

  @override
  void tick(double dt, StageFx fx) {
    t += dt * 1000;
    final want = math.min(n, (t / ms * n).floor() + 1);
    while (emitted < want) {
      emitted++;
      final p = Offset(box.left + _rnd(0, box.width), box.top + _rnd(0, box.height));
      fx.emit(p, shape: emitted % 4 == 0 ? 'star' : 'glow', pal: pal, size: _rnd(1.4, 3.2), sizeK: 'shrink', alphaK: 'inout', life: _rnd(0.9, 1.6), speed: _rnd(4, 12), angle: -math.pi / 2, spread: 0.7, gravity: -14, turb: 24, spin: 5);
    }
    if (emitted >= n) dead = true;
  }
}

/// Runs [fn] once [ms] have passed on the effects clock (a staggered spawn).
class _Delayed extends _Mover {
  _Delayed(this.ms, this.fn) : super('front');
  final double ms;
  final void Function(StageFx fx) fn;
  double t = 0;

  @override
  void tick(double dt, StageFx fx) {
    t += dt * 1000;
    if (t >= ms) {
      dead = true;
      fn(fx);
    }
  }
}

/// Golden Pulse: spiral arcs of light winding out around a point.
class _GoldenPulse extends _Mover {
  _GoldenPulse(String layer, this.x, this.y, this.r0, this.r1, this.ms, this.pal, this.arms, this.squash, this.width)
      : rot = _rnd(0, _tau),
        super(layer);
  final double x, y, r0, r1, ms, squash, width;
  final int arms;
  final String pal;
  double t = 0, rot;

  @override
  void tick(double dt, StageFx fx) {
    t += (dt * 1000) / ms;
    rot += dt * 7;
    if (t >= 1) dead = true;
  }

  @override
  void draw(Canvas g, StageFx fx) {
    final colors = _pal(pal);
    final k = _easeOut(_clamp01(t));
    final rr = (r0 + (r1 - r0) * k) * fx.u;
    final a = math.pow(1 - k, 1.2).toDouble();
    if (a <= 0.002) return;
    final glow = fx._stroke
      ..blendMode = BlendMode.plus
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, width * fx.u);
    final line = fx._stroke2..blendMode = BlendMode.plus;
    g.save();
    g.translate(x, y);
    g.scale(1, squash);
    const span = 2.1;
    const n = 14;
    for (var i = 0; i < arms; i++) {
      final a0 = rot + (i / arms) * _tau;
      for (var j = 0; j < n; j++) {
        final t0 = j / n;
        final t1 = (j + 1) / n;
        final rA = rr * (0.55 + 0.45 * t0);
        final rB = rr * (0.55 + 0.45 * t1);
        final aa = a0 + span * t0;
        final ab = a0 + span * t1;
        final al = a * (0.25 + 0.75 * t1);
        final lw = math.max(0.5, width * fx.u * (0.35 + 0.65 * t1));
        final p0 = Offset(math.cos(aa) * rA, math.sin(aa) * rA);
        final p1 = Offset(math.cos(ab) * rB, math.sin(ab) * rB);
        glow
          ..strokeWidth = lw
          ..color = _withA(colors[2], al);
        g.drawLine(p0, p1, glow);
        line
          ..strokeWidth = lw
          ..color = _withA(j > n - 4 ? colors[0] : colors[1], al);
        g.drawLine(p0, p1, line);
      }
    }
    g.restore();
  }
}

/// Violet Crackle: a jagged bolt between two points that flickers and re-forms every 60 ms.
class _Crackle extends _Mover {
  _Crackle(String layer, this.ax, this.ay, this.bx, this.by, this.ms, this.pal, this.width, this.jag, this.segs, this.branches, this.alpha) : super(layer);
  final double ax, ay, bx, by, ms, width, jag, alpha;
  final int segs, branches;
  final String pal;
  double t = 0, next = 0;
  Path? bolt;
  final Path forks = Path();

  void _reform(StageFx fx) {
    final dx = bx - ax;
    final dy = by - ay;
    final len = math.max(1e-6, math.sqrt(dx * dx + dy * dy));
    final nx = -dy / len;
    final ny = dx / len;
    final pts = <Offset>[Offset(ax, ay)];
    for (var i = 1; i < segs; i++) {
      final f = i / segs;
      final off = _rnd(-jag, jag) * fx.u * math.sin(f * math.pi);
      pts.add(Offset(ax + dx * f + nx * off, ay + dy * f + ny * off));
    }
    pts.add(Offset(bx, by));
    final p = Path()..moveTo(ax, ay);
    for (final q in pts.skip(1)) {
      p.lineTo(q.dx, q.dy);
    }
    bolt = p;
    forks.reset();
    for (var k = 0; k < branches; k++) {
      final i = 1 + (_random.nextDouble() * (segs - 2)).floor();
      final st = pts[i];
      final ang = math.atan2(dy, dx) + _rnd(-1.1, 1.1);
      final l = _rnd(2, 5) * fx.u;
      forks
        ..moveTo(st.dx, st.dy)
        ..lineTo(st.dx + math.cos(ang) * l * 0.5 + _rnd(-1, 1) * fx.u, st.dy + math.sin(ang) * l * 0.5 + _rnd(-1, 1) * fx.u)
        ..lineTo(st.dx + math.cos(ang) * l, st.dy + math.sin(ang) * l);
    }
  }

  @override
  void tick(double dt, StageFx fx) {
    t += (dt * 1000) / ms;
    next -= dt;
    if (bolt == null || next <= 0) {
      _reform(fx);
      next = 0.06;
    }
    if (t >= 1) dead = true;
  }

  @override
  void draw(Canvas g, StageFx fx) {
    final b = bolt;
    if (b == null) return;
    final colors = _pal(pal);
    final k = _clamp01(t);
    final flick = 0.65 + 0.35 * _random.nextDouble();
    final al = alpha * flick * (k < 0.15 ? k / 0.15 : 1 - (k - 0.15) / 0.85);
    if (al <= 0.002) return;
    final w = width * fx.u;
    // the glow (the canvas shadow) and the coloured stroke, then the white-hot core
    final glow = fx._stroke
      ..blendMode = BlendMode.plus
      ..strokeWidth = w * 2.6
      ..color = _withA(colors[2], al * 0.55)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 2);
    g.drawPath(b, glow);
    g.drawPath(forks, glow);
    final line = fx._stroke2
      ..blendMode = BlendMode.plus
      ..strokeWidth = w * 2.6
      ..color = _withA(colors[1], al * 0.55);
    g.drawPath(b, line);
    g.drawPath(forks, line);
    line
      ..strokeWidth = w
      ..color = _withA(colors[0], al);
    g.drawPath(b, line);
    line.strokeWidth = w * 0.6;
    g.drawPath(forks, line);
  }
}

class _Ambient {
  _Ambient(this.kind, this.region);
  final String kind;
  final Rect? region;
  double left = 0;
}

// ------------------------------------------------------------------ the engine
/// The effects on the stage. Listeners (the two [StageFxPainter]s) are notified every tick while
/// anything is alive; [freeze] holds the whole simulation still for a hit-stop.
class StageFx extends ChangeNotifier {
  StageFx({required TickerProvider vsync}) {
    _ticker = vsync.createTicker(_onTick);
  }

  late final Ticker _ticker;
  final List<FxParticle> _ps = [];
  final List<_Mover> _movers = [];
  final Paint _paint = Paint()..filterQuality = FilterQuality.low;
  // strokes for the movers' lines (golden pulse arcs, crackle bolts): a blurred glow and a crisp line
  final Paint _stroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _stroke2 = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  _Ambient? _ambient;
  double _freezeLeft = 0; // ms
  double? _last;
  bool _disposed = false;
  final Map<String, bool> _drawn = {'back': false, 'front': false};

  /// The world box, in logical pixels (set by the view from its layout).
  double w = 1, h = 1;

  /// 1% of the world's width, in pixels.
  double u = 0.01;

  bool get alive => _ps.isNotEmpty || _movers.isNotEmpty;

  /// Whether the last paint of a layer put anything down (so the next one clears it).
  bool drew(String layer) => _drawn[layer] ?? false;

  void resize(double width, double height) {
    if (width <= 0 || height <= 0) return;
    if (width == w && height == h) return;
    w = width;
    h = height;
    u = w / 100;
  }

  /// fractions of the world -> pixels
  Offset px(Offset p) => Offset(p.dx * w, p.dy * h);

  /// Hold everything still for a moment (the hit-stop).
  void freeze(int ms) {
    if (ms <= 0) return;
    _freezeLeft = math.max(_freezeLeft, ms.toDouble());
    _ensureTicking();
  }

  void _ensureTicking() {
    if (_disposed || _ticker.isActive) return;
    _last = null;
    _ticker.start();
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final last = _last ?? now;
    _last = now;
    final dt = math.min(0.05, now - last);
    if (_freezeLeft > 0) {
      _freezeLeft -= dt * 1000;
      return;
    }
    final amb = _ambient;
    if (amb != null) {
      amb.left -= dt;
      if (amb.left <= 0) _emitAmbient(amb);
    }
    // particles (new ones appended by a mover's onArrive this tick get a first step too)
    for (var i = 0; i < _ps.length; i++) {
      final p = _ps[i];
      p.age += dt;
      if (p.age >= p.life) {
        p.dead = true;
        continue;
      }
      final seek = p.seek;
      if (seek != null) {
        p.vx += (seek.x - p.x) * seek.k * dt;
        p.vy += (seek.y - p.y) * seek.k * dt;
      }
      final orbit = p.orbit;
      if (orbit != null) {
        orbit.a += orbit.w * dt;
        orbit.r += orbit.dr * dt;
        p.x = orbit.x + math.cos(orbit.a) * orbit.r;
        p.y = orbit.y + math.sin(orbit.a) * orbit.r * 0.55;
      } else {
        p.vx += p.ax * dt;
        p.vy += p.ay * dt;
        if (p.turb != 0) {
          p.ph += dt * p.turbW;
          p.vx += math.cos(p.ph) * p.turb * dt;
          p.vy += math.sin(p.ph * 1.3) * p.turb * 0.6 * dt;
        }
        final d = math.max(0.0, 1 - p.drag * dt);
        p.vx *= d;
        p.vy *= d;
        p.x += p.vx * dt;
        p.y += p.vy * dt;
      }
      p.rot += p.spin * dt;
    }
    _ps.removeWhere((p) => p.dead);
    for (var i = 0; i < _movers.length; i++) {
      final m = _movers[i];
      if (!m.dead) m.tick(dt, this);
    }
    _movers.removeWhere((m) => m.dead);
    if (!_disposed) notifyListeners();
    if (_ps.isEmpty && _movers.isEmpty && _ambient == null && _freezeLeft <= 0) _ticker.stop();
  }

  /// Draws one layer ('back' or 'front') onto [g], the world box being [size].
  void paintLayer(Canvas g, Size size, String layer) {
    resize(size.width, size.height);
    var any = false;
    for (final m in _movers) {
      if (m.layer == layer && m.drawUnder) {
        m.draw(g, this);
        any = true;
      }
    }
    final paint = _paint
      ..colorFilter = null
      ..maskFilter = null;
    for (final p in _ps) {
      if (p.layer != layer) continue;
      final t = p.age / p.life;
      final a = p.alpha * _alphaK(p.alphaK, t);
      if (a <= 0.002) continue;
      final s = p.size * _sizeK(p.sizeK, t);
      if (s <= 0) continue;
      var rot = p.rot;
      var sx = 1.0;
      if (p.align) {
        rot = math.atan2(p.vy, p.vx);
        if (p.stretch != 0) sx = 1 + math.min(4.0, (math.sqrt(p.vx * p.vx + p.vy * p.vy) / u) * p.stretch);
      }
      paint
        ..blendMode = p.blend
        ..color = Color.fromRGBO(255, 255, 255, math.min(1.0, a));
      g.save();
      g.translate(p.x, p.y);
      g.rotate(rot);
      g.scale(s * sx / _spriteSize, s / _spriteSize);
      g.drawImage(p.sprite, _spriteOrigin, paint);
      g.restore();
      any = true;
    }
    for (final m in _movers) {
      if (m.layer == layer && !m.drawUnder) {
        m.draw(g, this);
        any = true;
      }
    }
    _drawn[layer] = any;
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker.dispose();
    _ps.clear();
    _movers.clear();
    super.dispose();
  }

  // ---------------------------------------------------------------- particles
  /// One particle. [p] in fractions of the world (pixels when [raw]); size, speed in u; life in seconds.
  FxParticle emit(
    Offset p, {
    bool raw = false,
    double speed = 0,
    double? angle,
    double spread = 0,
    double jitter = 0,
    double vx = 0,
    double vy = 0,
    double ax = 0,
    double gravity = 0,
    double drag = 0,
    double life = 0.8,
    double size = 1.2,
    String sizeK = 'shrink',
    double alpha = 1,
    String alphaK = 'fade',
    double? rot,
    double spin = 0,
    bool align = false,
    double stretch = 0,
    String shape = 'glow',
    String pal = 'gold',
    BlendMode blend = BlendMode.plus,
    String layer = 'front',
    double turb = 0,
    double? turbW,
    Offset? seek,
    double seekK = 30,
  }) {
    final at = raw ? p : px(p);
    final sp = speed * u;
    final ang = angle ?? _rnd(0, _tau);
    final a = ang + _rnd(-spread, spread);
    final sk = seek == null ? null : px(seek);
    final part = FxParticle(
      x: at.dx + _rnd(-jitter, jitter) * u,
      y: at.dy + _rnd(-jitter, jitter) * u,
      vx: math.cos(a) * sp + vx * u,
      vy: math.sin(a) * sp + vy * u,
      ax: ax * u,
      ay: gravity * u,
      drag: drag,
      life: life,
      size: size * u,
      sizeK: sizeK,
      alpha: alpha,
      alphaK: alphaK,
      rot: rot ?? _rnd(0, _tau),
      spin: spin,
      align: align,
      stretch: stretch,
      sprite: _sprite(shape, pal),
      blend: blend,
      layer: layer,
      turb: turb * u,
      turbW: turbW ?? _rnd(2, 5),
      ph: _rnd(0, _tau),
      seek: sk == null ? null : _Seek(sk.dx, sk.dy, seekK),
    );
    _ps.add(part);
    _ensureTicking();
    return part;
  }

  /// n particles from one point.
  void burst(
    Offset p,
    int n, {
    double speed = 0,
    double? angle,
    bool even = false,
    double vary = 0,
    double spread = 0,
    double jitter = 0,
    double gravity = 0,
    double drag = 0,
    double life = 0.8,
    double size = 1.2,
    String sizeK = 'shrink',
    double alpha = 1,
    String alphaK = 'fade',
    double spin = 0,
    bool align = false,
    double stretch = 0,
    String shape = 'glow',
    String pal = 'gold',
    BlendMode blend = BlendMode.plus,
    String layer = 'front',
    double turb = 0,
  }) {
    for (var i = 0; i < n; i++) {
      emit(
        p,
        angle: angle ?? (even ? (i / n) * _tau : _rnd(0, _tau)),
        speed: speed * _rnd(vary > 0 ? 1 - vary : 1, 1),
        size: size * _rnd(vary > 0 ? 1 - vary * 0.6 : 1, 1),
        life: life * _rnd(vary > 0 ? 1 - vary * 0.5 : 1, 1),
        spread: spread,
        jitter: jitter,
        gravity: gravity,
        drag: drag,
        sizeK: sizeK,
        alpha: alpha,
        alphaK: alphaK,
        spin: spin,
        align: align,
        stretch: stretch,
        shape: shape,
        pal: pal,
        blend: blend,
        layer: layer,
        turb: turb,
      );
    }
  }

  /// Light shards flying out of an impact: fast, stretched along their flight, slowing down.
  void shards(Offset p, int n, {String pal = 'gold', double scale = 1, String layer = 'front'}) {
    burst(p, n, shape: 'shard', pal: pal, speed: 110 * scale, vary: 0.6, drag: 4.2, size: 4.2 * scale, sizeK: 'spark', life: 0.6, alphaK: 'fade2', align: true, stretch: 0.012, gravity: 25, layer: layer);
    burst(p, (n * 0.6).round(), shape: 'star', pal: pal, speed: 55 * scale, vary: 0.7, drag: 3, size: 2.4 * scale, sizeK: 'spark', life: 0.75, spin: 6, gravity: 40, layer: layer);
    burst(p, (n * 0.5).round(), shape: 'glow', pal: pal, speed: 22 * scale, vary: 0.8, drag: 1.2, size: 1.6 * scale, sizeK: 'shrink', life: 1.4, alphaK: 'inout', gravity: -6, turb: 20, layer: layer);
  }

  /// A soft flash of light at a point (behind or in front).
  void flashAt(Offset p, {double size = 30, double life = 0.35, String pal = 'gold', String layer = 'front', double alpha = 1, String sizeK = 'bloom', String alphaK = 'flash'}) {
    emit(p, shape: 'glow', pal: pal, size: size, life: life, layer: layer, alpha: alpha, sizeK: sizeK, alphaK: alphaK);
  }

  /// A glow that sits still and breathes for a while (a charge, a halo).
  FxParticle halo(Offset p, {double size = 20, double life = 0.6, String pal = 'gold', String layer = 'back', double alpha = 0.9}) =>
      emit(p, shape: 'glow', pal: pal, size: size, life: life, layer: layer, alpha: alpha, sizeK: 'grow', alphaK: 'inout');

  /// Motes gather from a ring around a point into it (a charge-up).
  void converge(Offset p, int n, {double r = 16, String pal = 'gold', double life = 0.45, double size = 1.6, String layer = 'front'}) {
    final c = px(p);
    for (var i = 0; i < n; i++) {
      final a = _rnd(0, _tau);
      final rr = r * _rnd(0.6, 1.2) * u;
      final at = Offset(c.dx + math.cos(a) * rr, c.dy + math.sin(a) * rr * 0.75);
      final part = emit(at, raw: true, shape: i % 3 == 0 ? 'star' : 'glow', pal: pal, size: size * _rnd(0.6, 1.1), sizeK: 'grow', alphaK: 'inout', life: life * _rnd(0.8, 1.1), layer: layer, spin: 4);
      part.seek = _Seek(c.dx, c.dy, 60);
      part.drag = 2.5;
    }
  }

  /// Soft dust puffs at the ground.
  void dust(Offset p, {int n = 8, String pal = 'dust', double scale = 1, double up = -12}) {
    burst(p, n, shape: 'puff', pal: pal, blend: BlendMode.srcOver, speed: 22 * scale, vary: 0.6, angle: -math.pi / 2, spread: 1.4, drag: 3.5, size: 7 * scale, sizeK: 'bloom', life: 0.8, alphaK: 'fade2', alpha: 0.9, gravity: up, spin: 1);
  }

  /// Dark puffs (the Hollow).
  void smoke(Offset p, {int n = 6, double scale = 1}) {
    burst(p, n, shape: 'smoke', pal: 'dark', blend: BlendMode.srcOver, speed: 16 * scale, vary: 0.6, drag: 2.5, size: 9 * scale, sizeK: 'bloom', life: 0.9, alphaK: 'fade2', alpha: 0.85, gravity: -10, spin: 0.8, turb: 10);
  }

  /// Embers drifting up around a point (the Hollow's energy). [w] and [h] are percent of the world.
  void embers(Offset p, int n, {String pal = 'violet', double w = 14, double h = 10, double life = 1.6, String layer = 'front', double size = 2.2}) {
    for (var i = 0; i < n; i++) {
      final q = Offset(p.dx + _rnd(-w / 2, w / 2) / 100, p.dy + _rnd(-h / 2, h / 2) / 100);
      emit(q, shape: 'glow', pal: pal, size: size * _rnd(0.5, 1.2), sizeK: 'shrink', alphaK: 'inout', life: life * _rnd(0.7, 1.2), speed: _rnd(2, 6), angle: -math.pi / 2, spread: 0.5, gravity: -8, turb: 18, layer: layer);
    }
  }

  /// Hearts rising. [spread] is percent of the world's width.
  void hearts(Offset p, {int n = 4, String pal = 'pink', double spread = 6}) {
    for (var i = 0; i < n; i++) {
      final q = Offset(p.dx + _rnd(-spread, spread) / 100, p.dy + _rnd(-2, 2) / 100);
      emit(q, shape: 'heart', pal: pal, blend: BlendMode.srcOver, size: _rnd(3, 4.6), sizeK: 'pop', alphaK: 'hold', life: _rnd(1.0, 1.4), speed: _rnd(8, 14), angle: -math.pi / 2, spread: 0.5, drag: 1.2, gravity: -6, turb: 14, spin: _rnd(-1, 1));
    }
  }

  /// Petals (or confetti) carried toward a point along a curve, then swirling around it.
  void stream(Offset a, Offset b, int n, {String pal = 'pink', String shape = 'petal', double ms = 700, bool swirl = true, double size = 2.4}) {
    final pa = px(a);
    final pb = px(b);
    _movers.add(_Stream(pa.dx, pa.dy, pb.dx, pb.dy, n, ms, pal, shape, swirl, size));
    _movers.add(_StreamNear(pb.dx, pb.dy, ms));
    _ensureTicking();
  }

  // ---------------------------------------------------------------- movers
  /// A bright head with a trail that flies from a to b along a bow; calls onArrive at the end.
  FxComet comet(
    Offset a,
    Offset b, {
    double ms = 240,
    String pal = 'gold',
    double size = 7,
    double bow = -10,
    int trail = 3,
    String ease = 'in',
    String layer = 'front',
    VoidCallback? onArrive,
    bool sparks = true,
    ui.Image? img,
    double imgSize = 6,
    double spin = 0,
  }) {
    final pa = px(a);
    final pb = px(b);
    final m = FxComet(
      layer: layer,
      ax: pa.dx,
      ay: pa.dy,
      bx: pb.dx,
      by: pb.dy,
      cx: (pa.dx + pb.dx) / 2,
      cy: (pa.dy + pb.dy) / 2 + bow * u,
      ms: math.max(1.0, ms),
      pal: pal,
      size: size,
      trail: trail,
      ease: ease,
      sparks: sparks,
      img: img,
      imgSize: imgSize,
      spin: spin,
      onArrive: onArrive,
    );
    _movers.add(m);
    _ensureTicking();
    return m;
  }

  /// A shockwave ring. r0 -> r1 in u.
  void ring(Offset p, {double r0 = 2, double r1 = 30, double ms = 450, String pal = 'gold', double width = 2.2, String layer = 'front', double alpha = 1, double squash = 0.7, BlendMode blend = BlendMode.plus}) {
    final c = px(p);
    _movers.add(_Ring(layer, c.dx, c.dy, r0, r1, ms, pal, width, alpha, squash, blend));
    _ensureTicking();
  }

  /// Rays of light turning slowly behind a point.
  void rays(Offset p, {int n = 7, double r = 60, double ms = 1800, String pal = 'gold', String layer = 'back', double alpha = 0.55, double spin = 0.5}) {
    final c = px(p);
    _movers.add(_Rays(layer, c.dx, c.dy, n, r, ms, pal, alpha, spin));
    _ensureTicking();
  }

  /// A soft vignette pulse in a colour (the Hollow's surge), drawn in front.
  void pulse({String pal = 'violet', double ms = 700, double alpha = 0.45}) {
    _movers.add(_Pulse(pal, ms, alpha));
    _ensureTicking();
  }

  /// Motes of light leaving a body (the Hollow dissolving): emitted across [box] (fractions) for ms.
  void dissolve(Rect box, {int n = 70, double ms = 600, String pal = 'gold'}) {
    _movers.add(_Dissolve(box, n, ms, pal));
    _ensureTicking();
  }

  // ---------------------------------------------------------------- the effect library
  // The board's names: Lumen Wisps, Flower Petals, Healing Sparkles, Golden Pulse, Hollow Shards,
  // Violet Crackle, Dust Burst.

  /// Golden Pulse: spiral arcs of light winding out around a point (Lumen Glow lands).
  void goldenPulse(Offset p, {double r0 = 4, double r1 = 26, double ms = 700, String pal = 'gold', int arms = 3, String layer = 'front', double squash = 0.62, double width = 1.6}) {
    final c = px(p);
    _movers.add(_GoldenPulse(layer, c.dx, c.dy, r0, r1, ms, pal, arms, squash, width));
    // a few sparks thrown off the ends of the arms
    burst(p, 10, shape: 'sparkle', pal: pal, speed: 34, vary: 0.5, drag: 2.6, size: 2.6, sizeK: 'spark', life: 0.7, spin: 3, layer: layer);
    _ensureTicking();
  }

  /// Violet Crackle: a jagged bolt between two points that flickers and re-forms every other frame.
  void crackle(Offset a, Offset b, {double ms = 260, String pal = 'violet', double width = 0.9, double jag = 3.2, int segs = 9, int branches = 2, String layer = 'front', double alpha = 1}) {
    final pa = px(a);
    final pb = px(b);
    _movers.add(_Crackle(layer, pa.dx, pa.dy, pb.dx, pb.dy, math.max(1.0, ms), pal, width, jag, math.max(2, segs), branches, alpha));
    _ensureTicking();
  }

  /// Violet Crackle around a body: short bolts between points on a ring ([r] in percent of the
  /// width), fired over ms.
  void crackleAround(Offset p, {double r = 14, int n = 5, double ms = 600, String pal = 'violet'}) {
    for (var i = 0; i < n; i++) {
      _movers.add(_Delayed((i / n) * ms * 0.7, (fx) {
        final a0 = _rnd(0, _tau);
        final a1 = a0 + _rnd(0.7, 1.6);
        final ar = fx.w / fx.h;
        final q0 = Offset(p.dx + math.cos(a0) * r * 0.9 / 100, p.dy + math.sin(a0) * r * 0.75 * ar / 100);
        final q1 = Offset(p.dx + math.cos(a1) * r / 100, p.dy + math.sin(a1) * r * 0.75 * ar / 100);
        fx.crackle(q0, q1, ms: _rnd(160, 260), pal: pal, width: 0.7, jag: 2.2, segs: 7, branches: 1);
      }));
    }
    _ensureTicking();
  }

  /// Hollow Shards: dark crystals breaking off and spinning away, with violet light behind them.
  void hollowShards(Offset p, {int n = 10, double scale = 1}) {
    burst(p, n, shape: 'crystal', pal: 'crystal', blend: BlendMode.srcOver, speed: 70 * scale, vary: 0.6, drag: 2.4, size: 3.6 * scale, sizeK: 'hold', alphaK: 'hold', life: 0.9, gravity: 60, spin: 9);
    burst(p, (n * 0.8).round(), shape: 'glow', pal: 'violet', speed: 40 * scale, vary: 0.7, drag: 2, size: 2.4 * scale, sizeK: 'shrink', life: 0.8, gravity: -8, turb: 20);
  }

  /// Dust Burst: chunks of stone thrown up and falling, with dust puffs at the ground.
  void dustBurst(Offset p, {int n = 9, double scale = 1, Offset? ground}) {
    burst(p, n, shape: 'rock', pal: 'rock', blend: BlendMode.srcOver, speed: 62 * scale, vary: 0.6, angle: -math.pi / 2, spread: 1.25, drag: 0.9, size: 2.6 * scale, sizeK: 'hold', alphaK: 'hold', life: 0.95, gravity: 190, spin: 8);
    dust(ground ?? p, n: (n * 0.9).round(), scale: 1.1 * scale);
  }

  /// Healing Sparkles: twinkles, little plus signs and leaves rising around a body (Soothe). [w] and
  /// [h] are percent of the world.
  void healing(Offset p, {int n = 14, double w = 22, double h = 16, String pal = 'teal'}) {
    for (var i = 0; i < n; i++) {
      final q = Offset(p.dx + _rnd(-w / 2, w / 2) / 100, p.dy + _rnd(-h / 2, h / 2) / 100);
      switch (i % 3) {
        case 0:
          emit(q, shape: 'sparkle', pal: 'white', size: _rnd(2.2, 3.6), sizeK: 'pop', alphaK: 'inout', life: _rnd(0.8, 1.2), speed: _rnd(4, 9), angle: -math.pi / 2, spread: 0.4, gravity: -6, spin: _rnd(-2, 2));
        case 1:
          emit(q, shape: 'plus', pal: 'green', blend: BlendMode.srcOver, size: _rnd(2.4, 3.4), sizeK: 'pop', alphaK: 'hold', life: _rnd(0.9, 1.3), speed: _rnd(8, 14), angle: -math.pi / 2, spread: 0.3, drag: 1, gravity: -4, rot: 0.0);
        default:
          emit(q, shape: 'leaf', pal: 'leaf', blend: BlendMode.srcOver, size: _rnd(2.6, 3.8), sizeK: 'hold', alphaK: 'hold', life: _rnd(1.1, 1.5), speed: _rnd(6, 12), angle: -math.pi / 2, spread: 0.6, drag: 1, gravity: -3, turb: 26, spin: _rnd(-3, 3));
      }
    }
    burst(p, 6, shape: 'glow', pal: pal, speed: 10, vary: 0.6, drag: 1, size: 3, sizeK: 'grow', alphaK: 'inout', life: 1.1, gravity: -6);
  }

  /// Lumen Wisps: glowing leaves that wind from a to b on soft curves, leaving little trails.
  void wisps(Offset a, Offset b, {int n = 5, double ms = 520}) {
    for (var i = 0; i < n; i++) {
      final bow = _rnd(-14, 14);
      _movers.add(_Delayed(i * 50.0, (fx) {
        final c = fx.comet(
          Offset(a.dx + _rnd(-2, 2) / 100, a.dy + _rnd(-3, 3) / 100),
          Offset(b.dx + _rnd(-3, 3) / 100, b.dy + _rnd(-3, 3) / 100),
          ms: ms * _rnd(0.8, 1.1),
          pal: 'green',
          size: 3.2,
          bow: bow,
          trail: 2,
          ease: 'inout',
          sparks: false,
        );
        c.leaf = true;
      }));
    }
    _ensureTicking();
  }

  // ---------------------------------------------------------------- ambient
  /// The air: 'gold' (Flower Petals drifting across the shot and gold motes), 'hollow' (violet embers,
  /// dark wisps and floating crystals near the wild one), 'won' (petals, brighter motes and twinkles),
  /// null off. [region] in fractions of the world.
  void setAmbient(String? kind, [Rect? region]) {
    if (kind == null) {
      _ambient = null;
      return;
    }
    _ambient = _Ambient(kind, region);
    _ensureTicking();
  }

  void _emitAmbient(_Ambient a) {
    final r = a.region ?? const Rect.fromLTWH(0, 0.2, 1, 0.7);
    final p = Offset(r.left + _rnd(0, r.width), r.top + _rnd(0, r.height));
    if (a.kind == 'hollow') {
      a.left = 0.22;
      emit(p, shape: 'glow', pal: 'violet', size: _rnd(1.2, 2.6), sizeK: 'shrink', alphaK: 'inout', life: _rnd(1.6, 2.6), speed: _rnd(2, 5), angle: -math.pi / 2, spread: 0.6, gravity: -5, turb: 14, layer: _random.nextDouble() < 0.5 ? 'back' : 'front', alpha: 0.95);
      if (_random.nextDouble() < 0.3) emit(p, shape: 'smoke', pal: 'dark', blend: BlendMode.srcOver, size: _rnd(5, 9), sizeK: 'bloom', alphaK: 'inout', life: _rnd(2, 3), speed: 2, angle: -math.pi / 2, gravity: -3, alpha: 0.35, layer: 'back');
      // now and then a floating crystal of the Hollow
      if (_random.nextDouble() < 0.12) {
        emit(Offset(p.dx, p.dy + 0.06), shape: 'crystal', pal: 'crystal', blend: BlendMode.srcOver, size: _rnd(1.4, 2.2), sizeK: 'hold', alphaK: 'inout', life: _rnd(2, 3), speed: _rnd(2, 4), angle: -math.pi / 2, spread: 0.4, gravity: -3, turb: 8, spin: _rnd(-1.5, 1.5), layer: 'front', alpha: 0.85);
      }
    } else {
      // Flower Petals drifting down across the shot, a few gold motes, and twinkles after a win
      a.left = a.kind == 'won' ? 0.18 : 0.3;
      final roll = _random.nextDouble();
      if (roll < 0.45) {
        emit(Offset(_rnd(-5, 95) / 100, _rnd(-4, 30) / 100),
            shape: 'petal', pal: 'pink', blend: BlendMode.srcOver, size: _rnd(1.6, 2.6), sizeK: 'hold', alphaK: 'inout', life: _rnd(4, 6.5), speed: _rnd(3, 6), angle: _rnd(0.3, 1.0), gravity: 1.2, turb: 16, turbW: _rnd(1, 2.2), spin: _rnd(-2.5, 2.5), layer: _random.nextDouble() < 0.55 ? 'front' : 'back', alpha: 0.95);
      } else if (a.kind == 'won' && roll < 0.8) {
        emit(p, shape: 'sparkle', pal: 'gold', size: _rnd(1.8, 3.2), sizeK: 'pop', alphaK: 'soft', life: _rnd(0.9, 1.5), layer: 'front', alpha: 1);
      } else {
        emit(p, shape: 'glow', pal: 'gold', size: _rnd(0.9, 2.0), sizeK: 'hold', alphaK: 'inout', life: _rnd(3.5, 6), speed: _rnd(1, 3), angle: -math.pi / 2, spread: 1.2, turb: 10, turbW: _rnd(0.6, 1.5), layer: _random.nextDouble() < 0.6 ? 'back' : 'front', alpha: a.kind == 'won' ? 0.95 : 0.7);
      }
    }
  }
}

/// Paints one of the two effect layers of a [StageFx] ('back' behind the creatures, 'front' over
/// them). Repaints on every tick of the engine while anything is alive, and once more to clear.
class StageFxPainter extends CustomPainter {
  StageFxPainter(this.fx, {required this.layer}) : super(repaint: fx);
  final StageFx fx;
  final String layer;

  @override
  void paint(Canvas canvas, Size size) => fx.paintLayer(canvas, size, layer);

  @override
  bool shouldRepaint(StageFxPainter old) => old.fx != fx || old.layer != layer || fx.alive || fx.drew(layer);
}
