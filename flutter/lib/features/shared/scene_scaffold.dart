// Screen frame used by every scene screen: full-bleed habitat behind, a header, a flexible
// hero area (min 200 dp, style guide §23 "Small phone") where the pet stands, and a bottom
// panel that shrinks and scrolls on short phones. The pet's ground point tracks the bottom
// of the hero area, so it always stands just above the cards.

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

  @override
  void dispose() {
    _ground.dispose();
    super.dispose();
  }

  void _measure(BuildContext probe) {
    final stackBox = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final box = probe.findRenderObject() as RenderBox?;
    if (stackBox == null || box == null || !box.hasSize) return;
    final bottom = box.localToGlobal(Offset(0, box.size.height), ancestor: stackBox).dy;
    final gy = bottom - widget.groundOffset;
    if ((gy - _ground.value).abs() > 0.5) _ground.value = gy;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final maxPanel = math.max(140.0, box.maxHeight - widget.headerAllowance - widget.minHero - widget.bottomInset - MediaQuery.of(context).padding.top);
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
          Expanded(
            child: Builder(builder: (probe) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && probe.mounted) _measure(probe);
              });
              return widget.hero ?? const SizedBox.expand();
            }),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxPanel),
            child: SingleChildScrollView(child: widget.panel),
          ),
          SizedBox(height: widget.bottomInset),
        ]),
        if (widget.overlay != null) widget.overlay!,
      ]);
    });
  }
}
