// Screen frame used by every scene screen: full-bleed habitat behind, a header, a flexible
// hero area (min 200 dp, style guide §23 "Small phone") where the pet stands, and a bottom
// panel that shrinks and scrolls on short phones. The pet's ground point tracks the bottom
// of the hero area, so it always stands just above the cards.
//
// [heroHeight] flips it around (the Bag's pockets): a short hero of that height and a panel that
// fills the rest of the screen and scrolls inside itself. [heroBuilder] gets the pet's rect in the
// hero's coordinates, for things placed around the pet (the Bag's equipment slots).

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'scene_view.dart';

class SceneScaffold extends StatefulWidget {
  const SceneScaffold({
    super.key,
    required this.config,
    required this.controller,
    required this.header,
    required this.panel,
    this.hero,
    this.heroBuilder,
    this.heroHeight,
    this.onPetTap,
    this.petLabel = 'Your Evochi',
    this.minHero = 200,
    this.groundOffset = 24,
    this.bottomInset = 0,
    this.headerAllowance = 120,
    this.overlay,
  });

  final SceneConfig Function(double groundY) config;
  final SceneController controller;
  final Widget header;
  final Widget panel;
  final Widget? hero; // laid over the hero area (slot boxes, featured card, arrows...)
  final Widget Function(BuildContext context, Rect? pet)? heroBuilder; // instead of [hero]
  final double? heroHeight;
  final VoidCallback? onPetTap;
  final String petLabel;
  final double minHero;
  final double groundOffset;
  final double bottomInset;
  final double headerAllowance;
  final Widget? overlay;

  @override
  State<SceneScaffold> createState() => _SceneScaffoldState();
}

class _SceneScaffoldState extends State<SceneScaffold> {
  final _stackKey = GlobalKey();
  final _ground = ValueNotifier<double>(320);
  final _heroTop = ValueNotifier<double>(0);

  @override
  void dispose() {
    _ground.dispose();
    _heroTop.dispose();
    super.dispose();
  }

  void _measure(BuildContext probe) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final box = probe.findRenderObject() as RenderBox?;
    if (stackBox == null || box == null || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero, ancestor: stackBox).dy;
    final gy = top + box.size.height - widget.groundOffset;
    if ((gy - _ground.value).abs() > 0.5) _ground.value = gy;
    if ((top - _heroTop.value).abs() > 0.5) _heroTop.value = top;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = Size(box.maxWidth, box.maxHeight);
      final maxPanel = math.max(140.0, box.maxHeight - widget.headerAllowance - widget.minHero - widget.bottomInset - MediaQuery.of(context).padding.top);
      // a LayoutBuilder, not a Builder: it builds again whenever the hero's size changes (a panel growing or
      // shrinking under it) and so measures the ground again, even when nothing above it rebuilt
      final hero = LayoutBuilder(builder: (probe, _) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && probe.mounted) _measure(probe);
        });
        final hb = widget.heroBuilder;
        if (hb != null) {
          // no rect until the hero has been measured (the first frame), so nothing jumps into place
          return ListenableBuilder(
            listenable: Listenable.merge([_ground, _heroTop]),
            // (the pet's spot even while it is hidden: the hatch screen draws the egg there)
            builder: (ctx, _) => hb(ctx, _heroTop.value <= 0 ? null : scenePetRect(widget.config(_ground.value), size, evenHidden: true)?.shift(Offset(0, -_heroTop.value))),
          );
        }
        return widget.hero ?? const SizedBox.expand();
      });
      final fixed = widget.heroHeight;
      return Stack(key: _stackKey, children: [
        Positioned.fill(
          child: ValueListenableBuilder<double>(
            valueListenable: _ground,
            builder: (_, gy, __) => HabitatScene(
              config: widget.config(gy),
              controller: widget.controller,
              onPetTap: widget.onPetTap,
              petLabel: widget.petLabel,
            ),
          ),
        ),
        Column(children: [
          SafeArea(bottom: false, child: widget.header),
          if (fixed != null) ...[
            SizedBox(height: fixed, child: hero),
            Expanded(child: widget.panel),
          ] else ...[
            Expanded(child: hero),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxPanel),
              child: SingleChildScrollView(child: widget.panel),
            ),
          ],
          SizedBox(height: widget.bottomInset),
        ]),
        if (widget.overlay != null) widget.overlay!,
      ]);
    });
  }
}
