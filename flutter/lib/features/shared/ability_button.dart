// Evochi's combat button: one design for every ability, in four ranks. A carved wood rim with a thin gold edge
// and stepped pixel highlights; a parchment face (an affinity's colour for the ultimate); a custom pixel icon in
// the middle that reads without its name. Cooling down, a dark sweep with the seconds left; ready, a glow (a
// faint one for an ordinary ability, a strong one with motes orbiting the rim for an ultimate); pressed, it sinks
// a little and its rim lights. Names are small and light under it; a long press shows the full name.
//
//   primary   Pounce: the largest, warm gold
//   secondary Dodge, Bolt, Pulse: their own accent each, kept quiet
//   utility   Eat, Drink: smaller, plain parchment, a count
//   ultimate  an Elder's: its affinity's colour, its charge ring, the strongest glow
//
// The icons are drawn small on a pixel grid and scaled up without smoothing (pixel art, like the game's own),
// cached once each.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/theme.dart';

enum AbilityRank { primary, secondary, utility, ultimate }

/// The pixel icons (drawn by [PixelIcons]).
enum AbilityIcon { claws, bolt, dodge, pulse, mist, star, potion, apple }

class AbilityButton extends StatefulWidget {
  const AbilityButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onDown,
    this.onUp,
    this.rank = AbilityRank.secondary,
    this.accent = const Color(0xFFF4B84E),
    this.size,
    this.cooldown = 0,
    this.cooldownLeft = 0,
    this.charge,
    this.ready = false,
    this.dim = false,
    this.badge,
    this.semantic,
    this.showLabel = true,
    this.flash = 0,
  });
  final AbilityIcon icon;
  final String label; // small under it; the full name on a long press
  final VoidCallback onDown;
  final VoidCallback? onUp;
  final AbilityRank rank;

  /// its own colour: the icon's glow, the rim's light, an ultimate's face and ring
  final Color accent;
  final double? size;

  /// 1 just used .. 0 ready (a dark sweep), and the seconds left (shown from one up)
  final double cooldown, cooldownLeft;

  /// 0..1: an ultimate's ring filling
  final double? charge;
  final bool ready, dim;
  final String? badge;
  final String? semantic;
  final bool showLabel;

  /// 1 .. 0: just used (a ring of light breaking outward)
  final double flash;

  static double sizeOf(AbilityRank r) => switch (r) {
        AbilityRank.primary => 70,
        AbilityRank.ultimate => 62,
        AbilityRank.secondary => 52,
        AbilityRank.utility => 46,
      };

  @override
  State<AbilityButton> createState() => _AbilityButtonState();
}

class _AbilityButtonState extends State<AbilityButton> with SingleTickerProviderStateMixin {
  bool _down = false;
  late final Ticker _ticker;
  final _t = ValueNotifier(0.0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _t.value = d.inMicroseconds / 1e6);
    _sync();
  }

  @override
  void didUpdateWidget(AbilityButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  // only an ultimate that is ready animates on its own (its motes); everything else repaints with the pad
  void _sync() {
    final live = widget.rank == AbilityRank.ultimate && widget.ready;
    if (live && !_ticker.isActive) _ticker.start();
    if (!live && _ticker.isActive) _ticker.stop();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  void _name() {
    final o = Overlay.maybeOf(context);
    final box = context.findRenderObject() as RenderBox?;
    if (o == null || box == null) return;
    final at = box.localToGlobal(Offset(box.size.width / 2, 0));
    late OverlayEntry e;
    e = OverlayEntry(
      builder: (_) => Positioned(
        left: at.dx - 90,
        top: at.dy - 40,
        width: 180,
        child: IgnorePointer(
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xF2FFF6E4),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF8A5A3B), width: 2),
              ),
              child: Text(widget.semantic ?? widget.label, style: EvochiText.tag.copyWith(color: EvochiColor.ink), textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
    o.insert(e);
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (e.mounted) e.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final size = w.size ?? AbilityButton.sizeOf(w.rank);
    final hit = math.max(48.0, size); // never a touch target under 48 dp
    final labelSize = w.rank == AbilityRank.primary ? 11.5 : 10.5;
    return Semantics(
      button: true,
      enabled: !w.dim,
      label: w.semantic ?? w.label,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) {
          setState(() => _down = true);
          w.onDown();
        },
        onPointerUp: (_) {
          setState(() => _down = false);
          w.onUp?.call();
        },
        onPointerCancel: (_) {
          setState(() => _down = false);
          w.onUp?.call();
        },
        child: GestureDetector(
          onLongPress: w.rank == AbilityRank.primary ? null : _name, // (Pounce: holding keeps striking)
          child: SizedBox(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              SizedBox(
                width: hit,
                height: hit,
                child: Center(
                  child: AnimatedScale(
                    scale: _down ? 0.9 : 1,
                    duration: Duration(milliseconds: _down ? 50 : 140),
                    curve: _down ? Curves.easeOut : Curves.elasticOut,
                    child: CustomPaint(
                      size: Size.square(size),
                      painter: _AbilityPainter(w, _down, _t),
                    ),
                  ),
                ),
              ),
              if (w.showLabel && (w.rank == AbilityRank.primary || w.rank == AbilityRank.ultimate))
                Container(
                  margin: const EdgeInsets.only(top: 1),
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                  decoration: BoxDecoration(
                    color: const Color(0xE64E3324),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xCCF2C76A), width: 1),
                  ),
                  child: Text(w.label,
                      maxLines: 1,
                      softWrap: false,
                      style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: labelSize, height: 1.15, color: const Color(0xFFFFF0D2))),
                )
              else if (w.showLabel)
                Text(
                  w.label,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: 'Nunito',
                    fontWeight: FontWeight.w900,
                    fontSize: labelSize,
                    height: 1.1,
                    color: const Color(0xFFFFF6E4).withValues(alpha: w.dim ? 0.6 : 0.95),
                    shadows: const [Shadow(color: Color(0xCC3B2923), blurRadius: 3, offset: Offset(0, 1))],
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _AbilityPainter extends CustomPainter {
  _AbilityPainter(this.w, this.down, this.t) : super(repaint: t);
  final AbilityButton w;
  final bool down;
  final ValueNotifier<double> t;

  static const _wood = Color(0xFF76513B), _woodDark = Color(0xFF4E3324), _woodLight = Color(0xFFA0714F);
  static const _gold = Color(0xFFF2C76A), _parch = Color(0xFFFFF3DC), _parch2 = Color(0xFFEED9B8);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2;
    final ult = w.rank == AbilityRank.ultimate;
    final util = w.rank == AbilityRank.utility;
    final prim = w.rank == AbilityRank.primary;
    final rim = r * (util ? 0.17 : 0.19);
    final face = r - rim;
    final dim = w.dim && ult ? 0.7 : 1.0;
    final grey = w.dim && !ult;
    if (grey) {
      canvas.saveLayer(Offset.zero & size, Paint()
        ..colorFilter = const ColorFilter.matrix([0.30, 0.55, 0.15, 0, 0, 0.30, 0.55, 0.15, 0, 0, 0.30, 0.55, 0.15, 0, 0, 0, 0, 0, 0.75, 0]));
    }
    // the ready glow: faint for an ordinary ability, strong for an ultimate
    if (w.ready && !w.dim) {
      final k = ult ? 0.75 + 0.25 * math.sin(t.value * 4) : 0.45;
      canvas.drawCircle(c, r * (ult ? 1.22 : 1.08), Paint()
        ..color = w.accent.withValues(alpha: (ult ? 0.55 : 0.22) * k)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * (ult ? 0.35 : 0.18)));
    }
    // a drop shadow, then the carved wood rim with its gold edge
    canvas.drawCircle(c + Offset(0, r * 0.08), r, Paint()..color = const Color(0x55241208));
    canvas.drawCircle(c, r, Paint()
      ..shader = ui.Gradient.linear(c - Offset(0, r), c + Offset(0, r), [_woodLight, _wood, _woodDark], const [0.0, 0.5, 1.0]));
    canvas.drawCircle(c, r - 0.8, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = (down ? w.accent : _gold).withValues(alpha: down ? 1 : 0.9 * dim));
    // stepped pixel highlights on the rim, upper left (the game's pixel edge)
    final px = math.max(1.5, r * 0.06);
    for (var i = 0; i < 5; i++) {
      final a = math.pi * (1.08 + i * 0.09);
      final p = c + Offset(math.cos(a), math.sin(a)) * (r - rim * 0.5);
      canvas.drawRect(Rect.fromCenter(center: p, width: px, height: px), Paint()..color = const Color(0x66FFE9C4));
    }
    // the face: parchment, or the ultimate's affinity colour
    final faceCols = ult
        ? [Color.lerp(w.accent, Colors.white, 0.45)!, w.accent, Color.lerp(w.accent, Colors.black, 0.25)!]
        : prim
            ? [const Color(0xFFFFF0C2), const Color(0xFFFFD775), const Color(0xFFE9A93E)]
            : util
                ? [_parch, _parch2, Color.lerp(_parch2, const Color(0xFFB98A5E), 0.2)!]
                : [Color.lerp(w.accent, Colors.white, 0.55)!, Color.lerp(w.accent, Colors.white, 0.15)!, Color.lerp(w.accent, Colors.black, 0.22)!];
    canvas.drawCircle(c, face, Paint()
      ..shader = ui.Gradient.radial(c - Offset(face * 0.3, face * 0.35), face * 1.4, faceCols, const [0.0, 0.55, 1.0]));
    canvas.drawCircle(c, face, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = const Color(0x664E3324));
    if (down) {
      canvas.drawCircle(c, face, Paint()..color = w.accent.withValues(alpha: 0.22));
    }
    // the icon
    final img = PixelIcons.of(w.icon);
    final isz = face * (util ? 1.42 : 1.5);
    final dst = Rect.fromCenter(center: c + Offset(0, down ? 1 : 0), width: isz, height: isz);
    canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint()
      ..filterQuality = FilterQuality.none
      ..color = Color.fromRGBO(255, 255, 255, dim));
    // an ultimate still charging sits darker, its ring showing how far
    if (ult && !w.ready) canvas.drawCircle(c, face, Paint()..color = const Color(0x73101830));
    // an ultimate: its charge ring round the rim, motes orbiting when it is full, a gold crest
    if (ult && w.charge != null) {
      final ch = w.charge!.clamp(0.0, 1.0);
      canvas.drawArc(Rect.fromCircle(center: c, radius: r - rim * 0.5), -math.pi / 2, math.pi * 2, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim * 0.55
        ..color = const Color(0x55241208));
      canvas.drawArc(Rect.fromCircle(center: c, radius: r - rim * 0.5), -math.pi / 2, math.pi * 2 * ch, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rim * 0.55
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(w.accent, Colors.white, ch >= 1 ? 0.35 : 0.0)!);
      _crest(canvas, c - Offset(0, r * 0.98), r * 0.3, w.ready);
      _crest(canvas, c + Offset(0, r * 0.98), r * 0.14, w.ready);
      if (w.ready) {
        for (var i = 0; i < 6; i++) {
          final a = t.value * 1.6 + i * math.pi / 3;
          final p = c + Offset(math.cos(a), math.sin(a)) * (r + 1.5);
          canvas.drawCircle(p, 1.8, Paint()..color = Colors.white.withValues(alpha: 0.85));
        }
      }
    }
    // cooling down: a dark sweep, and the seconds left
    if (w.cooldown > 0.001) {
      canvas.save();
      canvas.clipPath(Path()..addOval(Rect.fromCircle(center: c, radius: face)));
      canvas.drawArc(Rect.fromCircle(center: c, radius: face * 1.5), -math.pi / 2, math.pi * 2 * w.cooldown.clamp(0.0, 1.0), true,
          Paint()..color = const Color(0x99241208));
      canvas.restore();
      if (w.cooldownLeft >= 1) {
        final tp = TextPainter(
          text: TextSpan(
            text: '${w.cooldownLeft.ceil()}',
            style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: face * 0.75, color: Colors.white, shadows: const [
              Shadow(color: Color(0xFF241208), blurRadius: 3),
            ]),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      }
    }
    // just used: a ring of light breaking outward
    if (w.flash > 0) {
      final e = 1 - w.flash;
      canvas.drawCircle(c, r * (1 + 0.5 * e), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * w.flash
        ..color = Color.lerp(w.accent, Colors.white, 0.5)!.withValues(alpha: w.flash));
    }
    if (grey) canvas.restore();
    // a count
    final b = w.badge;
    if (b != null) {
      final bc = c + Offset(r * 0.68, -r * 0.62);
      final br = math.max(8.0, r * 0.3);
      canvas.drawCircle(bc, br, Paint()..color = const Color(0xFF4E3324));
      canvas.drawCircle(bc, br - 1.6, Paint()..color = const Color(0xFFFFF3DC));
      final tp = TextPainter(
        text: TextSpan(text: b, style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: br * 1.15, color: EvochiColor.ink)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, bc - Offset(tp.width / 2, tp.height / 2));
    }
  }

  /// the ultimate's gold four-pointed crest (top) and its small keystone (bottom)
  void _crest(Canvas canvas, Offset o, double r, bool lit) {
    final p = Path()
      ..moveTo(o.dx, o.dy - r)
      ..quadraticBezierTo(o.dx + r * 0.12, o.dy - r * 0.12, o.dx + r * 0.62, o.dy)
      ..quadraticBezierTo(o.dx + r * 0.12, o.dy + r * 0.12, o.dx, o.dy + r)
      ..quadraticBezierTo(o.dx - r * 0.12, o.dy + r * 0.12, o.dx - r * 0.62, o.dy)
      ..quadraticBezierTo(o.dx - r * 0.12, o.dy - r * 0.12, o.dx, o.dy - r)
      ..close();
    if (lit) canvas.drawCircle(o, r * 0.9, Paint()
      ..color = const Color(0x88FFE9A6)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 0.5));
    canvas.drawPath(p, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0xFF6B4423));
    canvas.drawPath(p, Paint()
      ..shader = ui.Gradient.linear(o - Offset(0, r), o + Offset(0, r), const [Color(0xFFFFF4C4), Color(0xFFF2C76A), Color(0xFFC8832C)], const [0.0, 0.5, 1.0]));
  }

  @override
  bool shouldRepaint(_AbilityPainter old) => true;
}

/// The combat icons, drawn on a 24 px grid without smoothing, each in its own colours, and kept.
class PixelIcons {
  static final _cache = <AbilityIcon, ui.Image>{};
  static const n = 24.0;

  static ui.Image of(AbilityIcon i) => _cache.putIfAbsent(i, () {
        final rec = ui.PictureRecorder();
        final c = Canvas(rec, const Rect.fromLTWH(0, 0, n, n));
        _draw(c, i);
        return rec.endRecording().toImageSync(n.toInt(), n.toInt());
      });

  static Paint _p(Color c) => Paint()
    ..color = c
    ..isAntiAlias = false;

  static Paint _s(Color c, double w) => Paint()
    ..color = c
    ..isAntiAlias = false
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.square
    ..strokeJoin = StrokeJoin.miter;

  static const _ink = Color(0xFF3B2923);

  static void _draw(Canvas c, AbilityIcon i) {
    switch (i) {
      case AbilityIcon.claws:
        // three claw marks raked forward
        for (var k = 0; k < 3; k++) {
          final o = k * 5.0 - 5;
          final p = Path()
            ..moveTo(7 + o, 20)
            ..quadraticBezierTo(10 + o, 12, 17 + o, 4);
          c.drawPath(p, _s(_ink, 4.2));
          c.drawPath(p, _s(const Color(0xFFFFF4D2), 2.2));
          c.drawRect(Rect.fromLTWH(15 + o, 4, 2, 2), _p(Colors.white));
        }
      case AbilityIcon.bolt:
        // an angular bolt with two speed trails
        c.drawRect(const Rect.fromLTWH(1, 8, 6, 2), _p(const Color(0xFFF2C76A)));
        c.drawRect(const Rect.fromLTWH(3, 13, 5, 2), _p(const Color(0xFFB8EE5A)));
        final b = Path()
          ..moveTo(14, 1)
          ..lineTo(7, 13)
          ..lineTo(12, 13)
          ..lineTo(9, 23)
          ..lineTo(19, 9)
          ..lineTo(14, 9)
          ..lineTo(18, 1)
          ..close();
        c.drawPath(b, _s(_ink, 2.4));
        c.drawPath(b, _p(const Color(0xFFB8EE5A)));
        c.drawRect(const Rect.fromLTWH(14, 3, 2, 3), _p(const Color(0xFFF7FFD8)));
      case AbilityIcon.dodge:
        // a curved arrow sweeping aside, an afterimage left behind
        c.drawCircle(const Offset(6.5, 14), 4.5, _p(const Color(0x668FCBEF)));
        c.drawCircle(const Offset(9, 13.5), 4.5, _p(const Color(0x998FCBEF)));
        final a = Path()
          ..moveTo(5, 19)
          ..quadraticBezierTo(10, 6, 19, 8);
        c.drawPath(a, _s(_ink, 4.4));
        c.drawPath(a, _s(const Color(0xFF8FCBEF), 2.4));
        final h = Path()
          ..moveTo(15, 3)
          ..lineTo(22, 8)
          ..lineTo(15, 13)
          ..close();
        c.drawPath(h, _s(_ink, 2));
        c.drawPath(h, _p(const Color(0xFFD6EFFF)));
      case AbilityIcon.pulse:
        // a small orb, a wave going out from it
        c.drawCircle(const Offset(12, 12), 10.5, _s(const Color(0xFFE9A93E), 1.6));
        c.drawCircle(const Offset(12, 12), 7.5, _s(const Color(0xFFF2C76A), 1.4));
        c.drawCircle(const Offset(12, 12), 4.8, _p(_ink));
        c.drawCircle(const Offset(12, 12), 3.8, _p(const Color(0xFFFFD25A)));
        c.drawRect(const Rect.fromLTWH(10, 9, 2, 2), _p(Colors.white));
      case AbilityIcon.mist:
        // a water drop with a spiral of mist in it, a gold star at its shoulder (an ultimate)
        final d = Path()
          ..moveTo(11, 2)
          ..quadraticBezierTo(3, 11, 4, 15)
          ..quadraticBezierTo(5, 22, 11, 22)
          ..quadraticBezierTo(18, 22, 18.5, 15)
          ..quadraticBezierTo(19, 11, 11, 2)
          ..close();
        c.drawPath(d, _s(_ink, 2.2));
        c.drawPath(d, _p(const Color(0xFF4C9BCC)));
        final sp = Path()
          ..moveTo(11, 17)
          ..quadraticBezierTo(7, 16, 8, 13)
          ..quadraticBezierTo(10, 10, 13, 12)
          ..quadraticBezierTo(15, 15, 12, 15);
        c.drawPath(sp, _s(const Color(0xFFE6F7FF), 1.6));
        c.drawRect(const Rect.fromLTWH(7, 8, 2, 3), _p(const Color(0xFFBFEAFF)));
        _star(c, const Offset(19, 5), 4.2);
      case AbilityIcon.star:
        _star(c, const Offset(12, 12), 10);
      case AbilityIcon.potion:
        // a corked flask of something bright
        c.drawRect(const Rect.fromLTWH(9, 2, 6, 4), _p(_ink));
        c.drawRect(const Rect.fromLTWH(10, 3, 4, 3), _p(const Color(0xFFB07A4A)));
        c.drawRect(const Rect.fromLTWH(9, 6, 6, 4), _p(_ink));
        c.drawRect(const Rect.fromLTWH(10, 6, 4, 4), _p(const Color(0xFFE6F2F5)));
        c.drawCircle(const Offset(12, 15.5), 7.5, _p(_ink));
        c.drawCircle(const Offset(12, 15.5), 6.2, _p(const Color(0xFFE6F2F5)));
        c.drawRect(const Rect.fromLTWH(6, 15, 12, 7), _p(const Color(0xFFE0609A)));
        c.drawRect(const Rect.fromLTWH(8, 12, 2, 3), _p(Colors.white));
      case AbilityIcon.apple:
        // an apple, its leaf and stem
        c.drawCircle(const Offset(12, 14.5), 8.2, _p(_ink));
        c.drawCircle(const Offset(12, 14.5), 6.8, _p(const Color(0xFFE2493B)));
        c.drawRect(const Rect.fromLTWH(11, 5, 2, 5), _p(_ink));
        final l = Path()
          ..moveTo(13, 7)
          ..quadraticBezierTo(17, 3, 20, 5)
          ..quadraticBezierTo(17, 9, 13, 7);
        c.drawPath(l, _p(const Color(0xFF5FA046)));
        c.drawRect(const Rect.fromLTWH(8, 10, 3, 3), _p(const Color(0xFFFFB0A4)));
    }
  }

  static void _star(Canvas c, Offset o, double r) {
    final p = Path();
    for (var k = 0; k < 10; k++) {
      final a = -math.pi / 2 + k * math.pi / 5;
      final rr = k.isEven ? r : r * 0.45;
      final q = o + Offset(math.cos(a), math.sin(a)) * rr;
      if (k == 0) {
        p.moveTo(q.dx, q.dy);
      } else {
        p.lineTo(q.dx, q.dy);
      }
    }
    p.close();
    c.drawPath(p, _s(_ink, 1.6));
    c.drawPath(p, _p(const Color(0xFFFFD25A)));
  }
}
