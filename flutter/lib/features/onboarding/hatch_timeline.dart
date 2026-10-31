// The first hatch, as data and as paint. assets/config/hatch.json holds the beats (when the egg goes quiet,
// shakes, cracks and bursts, when the Eggling comes out, looks round and does its own thing, and what each one
// sounds and feels like) and each egg's style (its light and the shape of its burst); HatchFx paints the egg
// through it: the shakes, the crack light, then the egg's own sprite broken along jagged lines and thrown
// apart, with the gold Lumen motes every egg shares and the burst of its affinity.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart' show rootBundle;

class HatchBeat {
  const HatchBeat(this.t, {this.sfx, this.vol = 0.5, this.buzz, this.shake = 0, this.crack = 0, this.burst = false, this.react});
  final double t;
  final String? sfx;
  final double vol;
  final String? buzz; // a Haptic name
  final double shake; // strength 0-1
  final int crack; // the crack stage it reaches, 1-3
  final bool burst;
  final String? react; // emerge, look, hatch

  factory HatchBeat.fromJson(Map<String, dynamic> j) => HatchBeat(
        (j['t'] as num).toDouble(),
        sfx: j['sfx'] as String?,
        vol: ((j['vol'] as num?) ?? 0.5).toDouble(),
        buzz: j['buzz'] as String?,
        shake: ((j['shake'] as num?) ?? 0).toDouble(),
        crack: ((j['crack'] as num?) ?? 0).toInt(),
        burst: j['burst'] == true,
        react: j['react'] as String?,
      );
}

class HatchStyle {
  const HatchStyle(this.glow, this.burst);
  final Color glow;
  final String burst; // motes, leaves, sparks, droplets, grit, stars
}

class HatchPlan {
  HatchPlan(this.beats, this.naming, this.styles)
      : burst = beats.firstWhere((b) => b.burst, orElse: () => const HatchBeat(0.3, burst: true)).t,
        crackFrom = beats.where((b) => b.crack > 0).fold<double>(double.infinity, (a, b) => math.min(a, b.t));
  final List<HatchBeat> beats;
  final double naming; // when the name card comes up
  final double burst; // when the shell breaks
  final double crackFrom; // when the cracks start opening
  final Map<String, HatchStyle> styles;

  /// A short hatch for a build without the config: burst, out, named.
  static final fallback = HatchPlan(const [
    HatchBeat(0.0, sfx: 'cine_footstep', vol: 0.6),
    HatchBeat(0.3, burst: true, sfx: 'mine_lumen_break', vol: 0.6),
    HatchBeat(0.36, react: 'emerge'),
    HatchBeat(1.4, react: 'hatch'),
  ], 2.2, const {});

  static HatchPlan? _cache;

  static Future<HatchPlan> load() async {
    final c = _cache;
    if (c != null) return c;
    try {
      final j = jsonDecode(await rootBundle.loadString('assets/config/hatch.json')) as Map<String, dynamic>;
      Color hex(String s) => Color(int.parse(s.substring(1), radix: 16) | 0xFF000000);
      final styles = {
        for (final e in (j['styles'] as Map<String, dynamic>).entries)
          e.key: HatchStyle(hex((e.value as Map)['glow'] as String), (e.value as Map)['burst'] as String),
      };
      final beats = [for (final b in j['beats'] as List) HatchBeat.fromJson((b as Map).cast<String, dynamic>())]..sort((a, b) => a.t.compareTo(b.t));
      return _cache = HatchPlan(beats, (j['naming'] as num).toDouble(), styles);
    } catch (_) {
      return fallback;
    }
  }

  HatchStyle style(String palette) => styles[palette] ?? const HatchStyle(Color(0xFFF4B84E), 'motes');

  /// The crack stage the hatch has reached u seconds in.
  int crack(double u) {
    var s = 0;
    for (final b in beats) {
      if (b.crack > s && b.t <= u) s = b.crack;
    }
    return s;
  }

  /// The egg's tilt (radians) and hop (in egg heights) u seconds in: each shake a few quick swings that die away,
  /// and a tremble that grows while the cracks open.
  (double, double) shake(double u) {
    var rot = 0.0, hop = 0.0;
    for (final b in beats) {
      if (b.shake <= 0) continue;
      final a = u - b.t;
      if (a < 0 || a > 0.24) continue;
      final k = a / 0.24;
      rot += b.shake * 0.12 * math.sin(k * math.pi * 3) * (1 - k);
      hop += b.shake * 0.035 * math.sin(k * math.pi);
    }
    if (u > crackFrom && u < burst) {
      final k = (u - crackFrom) / math.max(0.01, burst - crackFrom);
      rot += 0.02 * k * math.sin(u * 71) + 0.012 * k * math.sin(u * 43);
    }
    return (rot, hop);
  }
}

/// A piece of the shell: a jagged polygon on the egg sprite (fractions of the image) and how it flies (egg
/// heights a second, radians a second); the bottom pieces only tip outward and fade.
class _Shard {
  const _Shard(this.poly, this.vx, this.vy, this.spin, this.fadeFrom, this.fadeTo);
  final List<Offset> poly;
  final double vx, vy, spin, fadeFrom, fadeTo;
  Offset get centre => poly.fold(Offset.zero, (a, b) => a + b) / poly.length.toDouble();
}

// the break: a zigzag round the egg's waist, two cracks up through the top half and one down through the cup
// (the egg sprites are 700 x 760, the egg between about x 0.17-0.86 and y 0.17-0.83; the pieces stop at 0.85 so
// the shadow under it stays put)
final _shards = <_Shard>[
  // top left, top (with the crest), top right: thrown up and out
  const _Shard([Offset(0, 0), Offset(0.38, 0), Offset(0.42, 0.28), Offset(0.36, 0.38), Offset(0.4, 0.48), Offset(0.3, 0.55), Offset(0.2, 0.49), Offset(0, 0.53)],
      -1.25, -1.5, -4.0, 0.5, 1.0),
  const _Shard([Offset(0.38, 0), Offset(0.63, 0), Offset(0.58, 0.26), Offset(0.64, 0.36), Offset(0.6, 0.47), Offset(0.5, 0.54), Offset(0.4, 0.48), Offset(0.36, 0.38), Offset(0.42, 0.28)],
      0.1, -2.1, 2.5, 0.55, 1.05),
  const _Shard([Offset(0.63, 0), Offset(1, 0), Offset(1, 0.52), Offset(0.8, 0.48), Offset(0.7, 0.53), Offset(0.6, 0.47), Offset(0.64, 0.36), Offset(0.58, 0.26)],
      1.3, -1.35, 4.5, 0.5, 1.0),
  // the cup, in two halves that tip outward and fade
  const _Shard([Offset(0, 0.53), Offset(0.2, 0.49), Offset(0.3, 0.55), Offset(0.4, 0.48), Offset(0.5, 0.54), Offset(0.47, 0.66), Offset(0.53, 0.76), Offset(0.5, 0.85), Offset(0, 0.85)],
      -0.45, -0.25, -1.4, 0.2, 0.6),
  const _Shard([Offset(0.5, 0.54), Offset(0.6, 0.47), Offset(0.7, 0.53), Offset(0.8, 0.48), Offset(1, 0.52), Offset(1, 0.85), Offset(0.5, 0.85), Offset(0.53, 0.76), Offset(0.47, 0.66)],
      0.45, -0.2, 1.6, 0.2, 0.6),
];

class HatchFx {
  HatchFx._();

  static Path _path(List<Offset> poly, Rect dst) {
    final p = Path();
    for (var i = 0; i < poly.length; i++) {
      final q = Offset(dst.left + poly[i].dx * dst.width, dst.top + poly[i].dy * dst.height);
      i == 0 ? p.moveTo(q.dx, q.dy) : p.lineTo(q.dx, q.dy);
    }
    return p..close();
  }

  /// The shell breaking, u seconds after the burst: the sprite (drawn at [dst], ground-relative) cut into its
  /// pieces, each thrown, turned and fading. Reduced motion: the egg simply fades.
  static void shell(Canvas c, ui.Image im, Rect dst, double u, double h, {bool reduce = false}) {
    final src = Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
    final paint = Paint()..filterQuality = FilterQuality.medium;
    if (reduce) {
      final a = (1 - u / 0.4).clamp(0.0, 1.0);
      if (a > 0) c.drawImageRect(im, src, dst, paint..color = Color.fromRGBO(255, 255, 255, a));
      return;
    }
    const g = 4.5; // egg heights per second per second
    for (final s in _shards) {
      final a = u < s.fadeFrom ? 1.0 : (1 - (u - s.fadeFrom) / (s.fadeTo - s.fadeFrom)).clamp(0.0, 1.0);
      if (a <= 0) continue;
      final ctr = Offset(dst.left + s.centre.dx * dst.width, dst.top + s.centre.dy * dst.height);
      final dx = s.vx * h * u, dy = s.vy * h * u + 0.5 * g * h * u * u;
      c.save();
      c.translate(ctr.dx + dx, ctr.dy + dy);
      c.rotate(s.spin * u);
      c.translate(-ctr.dx, -ctr.dy);
      c.clipPath(_path(s.poly, dst));
      c.drawImageRect(im, src, dst, paint..color = Color.fromRGBO(255, 255, 255, a));
      c.restore();
    }
  }

  /// The light inside the egg as it gets ready: [k] 0-1 from quiet to bursting. Rays push out through the cracks
  /// once they open ([rays] 0-1).
  static void innerLight(Canvas c, Offset centre, double h, Color glow, double k, double rays, double t) {
    if (k <= 0) return;
    final warm = Color.lerp(glow, const Color(0xFFFFE08A), 0.55)!;
    final r = h * (0.62 + 0.35 * k);
    c.drawCircle(centre, r, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(centre, r, [warm.withValues(alpha: 0.42 * k), warm.withValues(alpha: 0)]));
    if (rays <= 0) return;
    final rnd = math.Random(19);
    for (var i = 0; i < 7; i++) {
      final a = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.7;
      final len = h * (0.55 + rnd.nextDouble() * 0.5) * (0.4 + 0.6 * rays);
      final w = h * (0.05 + rnd.nextDouble() * 0.05) * (0.6 + 0.4 * rays);
      final flick = 0.75 + 0.25 * math.sin(t * (9 + i) + i);
      final from = centre + Offset(math.cos(a), math.sin(a)) * h * 0.18;
      final to = centre + Offset(math.cos(a), math.sin(a)) * (h * 0.18 + len);
      final n = Offset(-math.sin(a), math.cos(a)) * w;
      final beam = Path()
        ..moveTo(from.dx + n.dx * 0.4, from.dy + n.dy * 0.4)
        ..lineTo(to.dx + n.dx, to.dy + n.dy)
        ..lineTo(to.dx - n.dx, to.dy - n.dy)
        ..lineTo(from.dx - n.dx * 0.4, from.dy - n.dy * 0.4)
        ..close();
      c.drawPath(
          beam,
          Paint()
            ..blendMode = BlendMode.plus
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.6)
            ..shader = ui.Gradient.linear(from, to, [warm.withValues(alpha: 0.55 * rays * flick), warm.withValues(alpha: 0)]));
    }
  }

  /// The burst, u seconds in: a flash, a ring of light over the ground, the gold Lumen motes and the egg's own
  /// burst. [n] scales the particle counts (fewer under reduced motion or a low quality tier).
  static void burst(Canvas c, Offset ground, double h, HatchStyle st, double u, {double n = 1, bool reduce = false}) {
    final centre = ground.translate(0, -h * 0.45);
    final warm = Color.lerp(st.glow, const Color(0xFFFFF0C0), 0.6)!;
    // the flash
    if (u < 0.4) {
      final k = 1 - u / 0.4;
      final r = h * (0.7 + u * (reduce ? 0.8 : 3.2));
      c.drawCircle(centre, r, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(centre, r, [warm.withValues(alpha: (reduce ? 0.35 : 0.95) * k), warm.withValues(alpha: 0)]));
    }
    // a ring of light running out over the ground
    if (!reduce && u < 0.7) {
      final k = u / 0.7;
      final w = h * (0.5 + 2.4 * Curves.easeOut.transform(k));
      c.save();
      c.translate(ground.dx, ground.dy - h * 0.04);
      c.scale(1, 0.28);
      c.drawCircle(Offset.zero, w, Paint()..style = PaintingStyle.stroke..strokeWidth = h * 0.06 * (1 - k)..blendMode = BlendMode.plus..color = st.glow.withValues(alpha: 0.7 * (1 - k)));
      c.restore();
    }
    final rnd = math.Random(7);
    // the Lumen every egg shares: gold motes lifting away
    final motes = (12 * n).round();
    for (var i = 0; i < motes; i++) {
      final a = rnd.nextDouble() * math.pi * 2;
      final sp = h * (0.25 + rnd.nextDouble() * 0.7);
      final rise = h * (0.25 + rnd.nextDouble() * 0.9);
      final x = centre.dx + math.cos(a) * sp * u + math.sin(u * 4 + i) * h * 0.03;
      final y = centre.dy - rise * u;
      final alpha = (1 - u / 2.4).clamp(0.0, 1.0);
      final r = h * (0.018 + rnd.nextDouble() * 0.022);
      c.drawCircle(Offset(x, y), r * 2.4, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(Offset(x, y), r * 2.4, [const Color(0xFFFFC24E).withValues(alpha: 0.8 * alpha), const Color(0x00FFC24E)]));
    }
    final count = (20 * n).round();
    switch (st.burst) {
      case 'leaves':
        // small leaves thrown out, then drifting down, turning
        for (var i = 0; i < count; i++) {
          final a = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.6;
          final sp = h * (0.9 + rnd.nextDouble() * 1.1);
          final drag = 1 - math.exp(-u * 3);
          final x = centre.dx + math.cos(a) * sp * drag / 3 * 2.2 + math.sin(u * 3 + i) * h * 0.08 * u;
          final y = centre.dy + math.sin(a) * sp * drag / 3 * 2.2 + h * 0.35 * u * u;
          final alpha = (1 - (u - 1.2) / 0.9).clamp(0.0, 1.0);
          final s = h * (0.035 + rnd.nextDouble() * 0.03);
          c.save();
          c.translate(x, y);
          c.rotate(i + u * (2 + rnd.nextDouble() * 3));
          c.drawOval(Rect.fromCenter(center: Offset.zero, width: s * 2.2, height: s), Paint()..color = (i.isEven ? const Color(0xFF78B55B) : const Color(0xFFA7D27A)).withValues(alpha: alpha));
          c.restore();
        }
      case 'sparks':
        // sparks streaking up and out, cooling from yellow to the ember's red
        for (var i = 0; i < count; i++) {
          final a = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.3;
          final sp = h * (1.4 + rnd.nextDouble() * 1.6);
          final life = 0.5 + rnd.nextDouble() * 0.5;
          if (u > life) continue;
          final k = u / life;
          final p = centre + Offset(math.cos(a), math.sin(a)) * sp * u + Offset(0, h * 1.2 * u * u);
          final tail = p - Offset(math.cos(a), math.sin(a) + 2.4 * u) * h * 0.09;
          final col = Color.lerp(const Color(0xFFFFE08A), st.glow, k)!;
          c.drawLine(tail, p, Paint()..blendMode = BlendMode.plus..strokeCap = StrokeCap.round..strokeWidth = h * 0.016..color = col.withValues(alpha: 1 - k));
        }
      case 'droplets':
        // droplets arcing up and falling back, with a little mist
        for (var i = 0; i < count; i++) {
          final a = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.2;
          final sp = h * (1.3 + rnd.nextDouble() * 1.2);
          final p = centre + Offset(math.cos(a), math.sin(a)) * sp * u + Offset(0, h * 3.2 * u * u);
          final alpha = (1 - u / 1.1).clamp(0.0, 1.0);
          final r = h * (0.016 + rnd.nextDouble() * 0.016);
          c.drawCircle(p, r, Paint()..color = const Color(0xFFBFE4F7).withValues(alpha: 0.9 * alpha));
          c.drawCircle(p.translate(-r * 0.3, -r * 0.3), r * 0.35, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: alpha));
        }
        if (u < 1.2) {
          final k = u / 1.2;
          c.drawCircle(centre, h * (0.5 + k), Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(centre, h * (0.5 + k), [st.glow.withValues(alpha: 0.28 * (1 - k)), st.glow.withValues(alpha: 0)]));
        }
      case 'grit':
        // stone grit thrown out and dropping hard, and a puff of dust where it lands
        for (var i = 0; i < count; i++) {
          final a = -math.pi / 2 + (rnd.nextDouble() - 0.5) * math.pi * 1.5;
          final sp = h * (0.9 + rnd.nextDouble() * 1.0);
          final p = centre + Offset(math.cos(a), math.sin(a)) * sp * u + Offset(0, h * 4.5 * u * u);
          if (p.dy > ground.dy) continue;
          final s = h * (0.02 + rnd.nextDouble() * 0.025);
          c.save();
          c.translate(p.dx, p.dy);
          c.rotate(i + u * 5);
          c.drawRect(Rect.fromCenter(center: Offset.zero, width: s, height: s), Paint()..color = (i.isEven ? const Color(0xFF4A4D57) : const Color(0xFF8E887E)));
          c.restore();
        }
        if (u > 0.15 && u < 1.4) {
          final k = (u - 0.15) / 1.25;
          c.save();
          c.translate(ground.dx, ground.dy - h * 0.06);
          c.scale(1, 0.4);
          c.drawCircle(Offset.zero, h * (0.4 + 0.9 * k), Paint()..color = const Color(0xFFB8AE9E).withValues(alpha: 0.35 * (1 - k)));
          c.restore();
        }
        // obsidian keeps its ember light too
        if (u < 0.8) {
          final k = u / 0.8;
          c.drawCircle(centre, h * 0.8, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(centre, h * 0.8, [st.glow.withValues(alpha: 0.35 * (1 - k)), st.glow.withValues(alpha: 0)]));
        }
      case 'stars':
        // little four-point stars rising slowly and twinkling
        for (var i = 0; i < count; i++) {
          final a = rnd.nextDouble() * math.pi * 2;
          final sp = h * (0.3 + rnd.nextDouble() * 0.8);
          final drag = 1 - math.exp(-u * 2.5);
          final p = centre + Offset(math.cos(a) * sp * drag, math.sin(a) * sp * drag * 0.7 - h * 0.25 * u);
          final tw = 0.55 + 0.45 * math.sin(u * 14 + i * 2.1);
          final alpha = (1 - (u - 1.0) / 1.2).clamp(0.0, 1.0) * tw;
          final s = h * (0.03 + rnd.nextDouble() * 0.03);
          final star = Path()
            ..moveTo(p.dx, p.dy - s)
            ..quadraticBezierTo(p.dx, p.dy, p.dx + s, p.dy)
            ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy + s)
            ..quadraticBezierTo(p.dx, p.dy, p.dx - s, p.dy)
            ..quadraticBezierTo(p.dx, p.dy, p.dx, p.dy - s)
            ..close();
          c.drawPath(star, Paint()..blendMode = BlendMode.plus..color = Color.lerp(st.glow, const Color(0xFFFFFFFF), 0.5)!.withValues(alpha: alpha));
        }
      default:
        // motes: more of the gold, wider
        for (var i = 0; i < count; i++) {
          final a = rnd.nextDouble() * math.pi * 2;
          final sp = h * (0.5 + rnd.nextDouble() * 1.0);
          final p = centre + Offset(math.cos(a) * sp * u, math.sin(a) * sp * u * 0.6 - h * 0.6 * u);
          final alpha = (1 - u / 2.0).clamp(0.0, 1.0);
          final r = h * (0.012 + rnd.nextDouble() * 0.018);
          c.drawCircle(p, r * 2.2, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(p, r * 2.2, [st.glow.withValues(alpha: 0.85 * alpha), st.glow.withValues(alpha: 0)]));
        }
    }
  }
}
