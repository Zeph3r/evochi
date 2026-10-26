// A round game button for the action pads (the Wilds' combat pad, the Pounce on the Old Trail and in the
// mines): the kit's chunky button, round, with its name under it, a dark sweep while it cools down, a
// ring that fills as a move charges, a glow when it is ready, a count badge, and a 3 px sink while it is
// held. One widget, so every pad reads the same.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'kit.dart';
import 'widgets.dart';

class ActionButton extends StatefulWidget {
  const ActionButton({
    super.key,
    required this.label,
    required this.size,
    required this.onDown,
    this.onUp,
    this.palette = KitButtonPalette.gold,
    this.icon,
    this.image,
    this.child,
    this.cooldown = 0,
    this.charge,
    this.ready = false,
    this.dim = false,
    this.held = false,
    this.badge,
    this.semantic,
    this.hint,
  });
  final String label; // drawn under it
  final String? semantic, hint; // for the screen reader (the label when null)
  final double size;
  final VoidCallback onDown;
  final VoidCallback? onUp;
  final KitButtonPalette palette;
  final String? icon; // a voxel icon
  final String? image; // or an item's picture
  final Widget? child; // or anything
  final double cooldown; // 1 just used .. 0 ready (a dark sweep)
  final double? charge; // 0..1: a ring round it fills (a signature move)
  final bool ready; // glows (a charged move, a strike that can land)
  final bool dim; // can't be used now (no stamina, nothing to drink)
  final bool held; // drawn sunk whatever the finger does (a strike playing out)
  final String? badge;

  @override
  State<ActionButton> createState() => _ActionButtonState();
}

class _ActionButtonState extends State<ActionButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final sz = widget.size;
    final down = _down || widget.held;
    final ring = widget.charge != null;
    final pad = ring ? 6.0 : 0.0;
    return Semantics(
      button: true,
      label: widget.semantic ?? widget.label,
      hint: widget.hint,
      child: Listener(
        onPointerDown: (_) {
          setState(() => _down = true);
          widget.onDown();
        },
        onPointerUp: (_) {
          setState(() => _down = false);
          widget.onUp?.call();
        },
        onPointerCancel: (_) {
          setState(() => _down = false);
          widget.onUp?.call();
        },
        child: ExcludeSemantics(
          child: Opacity(
            opacity: widget.dim ? 0.5 : 1,
            child: SizedBox(
              width: sz + pad * 2,
              height: sz + pad * 2 + 22,
              child: Stack(clipBehavior: Clip.none, alignment: Alignment.topCenter, children: [
                if (ring)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: CustomPaint(size: Size(sz + pad * 2, sz + pad * 2), painter: _ChargePainter(widget.charge!.clamp(0.0, 1.0), widget.ready)),
                  ),
                Positioned(
                  left: pad,
                  top: pad,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [if (widget.ready && !widget.dim) const BoxShadow(color: Color(0x99FFE3A0), blurRadius: 16, spreadRadius: 2)],
                    ),
                    child: CustomPaint(
                      // the orb: a soft shadow, its depth under it (gone while pressed), a bronze bezel,
                      // a domed face lit from the top left, a gloss across its top
                      painter: _OrbPainter(widget.palette, down),
                      child: AnimatedContainer(
                      duration: const Duration(milliseconds: 70),
                      width: sz,
                      height: sz,
                      transform: Matrix4.translationValues(0, down ? 3 : 0, 0),
                      alignment: Alignment.center,
                      child: ClipOval(
                        child: Stack(alignment: Alignment.center, children: [
                          if (widget.child != null)
                            widget.child!
                          else if (widget.image != null)
                            ItemImage(widget.image!, size: sz * 0.58)
                          else if (widget.icon != null)
                            VoxelIcon(widget.icon!, size: sz * 0.56),
                          if (widget.cooldown > 0.001)
                            Positioned.fill(child: CustomPaint(painter: _CooldownSweep(widget.cooldown.clamp(0.0, 1.0)))),
                          // the gloss, over the icon too
                          Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _GlossPainter()))),
                        ]),
                      ),
                    ),
                    ),
                  ),
                ),
                if (widget.badge != null)
                  Positioned(
                    right: pad - 3,
                    top: pad - 3,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 20),
                      height: 20,
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF6E4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: KitColor.woodInk, width: 2),
                      ),
                      child: Text(widget.badge!, style: EvochiText.tag.copyWith(color: KitColor.signInk, fontSize: 11, height: 1.1, fontWeight: FontWeight.w900)),
                    ),
                  ),
                // its name on a small dark plate under it
                Positioned(
                  left: -24,
                  right: -24,
                  top: sz + pad * 2 + 4,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 1, 8, 2),
                      decoration: BoxDecoration(
                        color: const Color(0xD9241710),
                        borderRadius: BorderRadius.circular(9),
                        border: Border.all(color: const Color(0xFF8A6A3E), width: 1),
                      ),
                      child: Text(
                        widget.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        softWrap: false,
                        style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12.5, height: 1.15, letterSpacing: 0.2, color: Color(0xFFFFF1D6)),
                      ),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// The orb under an action button's icon: a soft shadow, the button's depth (its palette's edge colour,
/// gone while pressed), a bronze bezel with a lit top, the face domed by a radial light from the top left.
class _OrbPainter extends CustomPainter {
  _OrbPainter(this.p, this.down);
  final KitButtonPalette p;
  final bool down;
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final sink = down ? 3.0 : 0.0;
    final c = Offset(r, r + sink);
    // the shadow and the depth
    canvas.drawOval(Rect.fromCenter(center: Offset(r, r * 2 + 3), width: r * 1.7, height: r * 0.36), Paint()
      ..color = const Color(0x55000000)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    if (!down) canvas.drawCircle(Offset(r, r + 4), r, Paint()..color = Color.lerp(p.edge, Colors.black, 0.15)!);
    // the bezel: dark ink outside, bronze lit from above
    canvas.drawCircle(c, r, Paint()..color = p.border);
    canvas.drawCircle(c, r - 1.8, Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFF3D9A0), Color(0xFFB8864A), Color(0xFF6E4A26)]).createShader(Rect.fromCircle(center: c, radius: r)));
    // the face
    final face = r * 0.84;
    final top = p.colors.first, deep = p.colors.last;
    final lit = down ? Color.lerp(top, deep, 0.35)! : Color.lerp(top, Colors.white, 0.28)!;
    canvas.drawCircle(c, face, Paint()
      ..shader = RadialGradient(center: const Alignment(-0.35, -0.45), radius: 1.05, colors: [lit, top, deep], stops: const [0, 0.42, 1]).createShader(Rect.fromCircle(center: c, radius: face)));
    // a darker lip round the face's lower edge, a bright one round its top
    final ring = Rect.fromCircle(center: c, radius: face - 1);
    canvas.drawArc(ring, 0.15 * math.pi, 0.7 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = Color.lerp(deep, Colors.black, 0.3)!.withValues(alpha: 0.55));
    canvas.drawArc(ring, 1.15 * math.pi, 0.7 * math.pi, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = const Color(0x8CFFFFFF));
    canvas.drawCircle(c, face, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = Color.lerp(p.border, deep, 0.3)!);
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.down != down || old.p != p;
}

/// A soft gloss across the orb's top and a glint, drawn over the icon.
class _GlossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.width / 2;
    final g = Rect.fromCenter(center: Offset(r, r * 0.52), width: r * 1.3, height: r * 0.72);
    canvas.drawOval(g, Paint()
      ..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)]).createShader(g));
    canvas.drawCircle(Offset(r * 0.6, r * 0.42), r * 0.07, Paint()..color = const Color(0xB3FFFFFF));
  }

  @override
  bool shouldRepaint(_GlossPainter old) => false;
}

/// The dark sweep that clears as a move cools down.
class _CooldownSweep extends CustomPainter {
  _CooldownSweep(this.left);
  final double left; // 1 = just used, 0 = ready
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawArc(Offset.zero & size, -math.pi / 2, 2 * math.pi * left, true, Paint()..color = const Color(0x8C2A1D10));
  }

  @override
  bool shouldRepaint(_CooldownSweep old) => old.left != left;
}

/// The ring round a charging move: a dark track, gold filling clockwise, bright all round when full.
class _ChargePainter extends CustomPainter {
  _ChargePainter(this.charge, this.ready);
  final double charge;
  final bool ready;
  @override
  void paint(Canvas canvas, Size size) {
    final r = (Offset.zero & size).deflate(2.5);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..color = const Color(0xB32A1D10);
    canvas.drawOval(r, track);
    if (charge <= 0) return;
    final fill = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round
      ..color = ready ? const Color(0xFFFFE27A) : const Color(0xFFC9A6F0);
    canvas.drawArc(r, -math.pi / 2, 2 * math.pi * charge, false, fill);
    if (ready) {
      canvas.drawOval(r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xCCFFFFFF));
    }
  }

  @override
  bool shouldRepaint(_ChargePainter old) => old.charge != charge || old.ready != ready;
}
