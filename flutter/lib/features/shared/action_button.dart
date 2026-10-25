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
              height: sz + pad * 2 + 15,
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
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 70),
                      width: sz,
                      height: sz,
                      transform: Matrix4.translationValues(0, down ? 3 : 0, 0),
                      decoration: Kit.button(widget.palette, radius: sz / 2, pressed: down, dot: false, border: 2.5),
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
                        ]),
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
                Positioned(
                  left: -20,
                  right: -20,
                  top: sz + pad * 2 + 1,
                  child: Text(
                    widget.label,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.visible,
                    softWrap: false,
                    style: TextStyle(
                      fontFamily: EvochiText.game,
                      fontWeight: FontWeight.w900,
                      fontSize: 11,
                      height: 1.1,
                      color: const Color(0xFFFFF6E4),
                      shadows: const [Shadow(color: Color(0xCC1E0C00), offset: Offset(0, 1), blurRadius: 2), Shadow(color: Color(0x99000000), blurRadius: 4)],
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
