// Lumen Trails: a creature's own page, a field-guide entry for a befriended Evochi or a restored
// guardian. It used to be a card over the scene. Now it's a focused page: the creature large over its
// home (dimmed), then a parchment page with what it is, where you met it, what it likes and what it
// does for you. Back returns to wherever you came from, as you left it (the Mossy Ruins keep their
// camera, the EvoDex its scroll).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../game/trails/trails.dart' as tr;
import '../shared/kit.dart';
import '../shared/live_scene.dart';
import '../shared/widgets.dart';
import '../village/village_screen.dart';
import 'trails_widgets.dart';

/// The scene a creature belongs to.
String creatureHome(String id) => id == 'sentinel' ? 'sentinel_gate' : 'mossy_ruins';

/// [flip]: the creature faces left where you tapped it (a scene), so the page keeps it that way.
void openCreaturePage(BuildContext context, String id, {bool flip = false}) {
  context.read<GameController>().audio.play('ui_tap', volume: 0.4);
  Navigator.of(context).push(PageRouteBuilder<void>(
    settings: RouteSettings(name: 'creature:$id'),
    transitionDuration: const Duration(milliseconds: 380),
    reverseTransitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => CreaturePage(id: id, flip: flip),
    transitionsBuilder: (ctx, a, __, child) {
      if (MediaQuery.of(ctx).disableAnimations) return FadeTransition(opacity: a, child: child);
      return FadeTransition(opacity: CurvedAnimation(parent: a, curve: Curves.easeOut), child: child);
    },
  ));
}

class CreaturePage extends StatefulWidget {
  const CreaturePage({super.key, required this.id, this.flip = false});
  final String id;
  final bool flip;
  @override
  State<CreaturePage> createState() => _CreaturePageState();
}

class _CreaturePageState extends State<CreaturePage> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _bob.stop();
    } else if (!_bob.isAnimating) {
      _bob.repeat();
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final id = widget.id;
    final def = tr.creatureDefs[id]!;
    final t = c.trailsView;
    final comp = t.companions.where((x) => x.id == id).firstOrNull;
    final restored = t.restored[id];
    final mq = MediaQuery.of(context);
    final ta = trailsArt;
    final scene = creatureHome(id);
    final artH = math.min(280.0, mq.size.height * (def.size == 'large' ? 0.34 : 0.28));

    Widget fact(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 118, child: Text(k, style: EvochiText.caption.copyWith(fontSize: 13))),
            Expanded(child: Text(v, style: EvochiText.cardTitle.copyWith(fontSize: 14))),
          ]),
        );

    return Scaffold(
      backgroundColor: const Color(0xFF1E2418),
      body: Stack(fit: StackFit.expand, children: [
        // its home, dimmed: the creature is the subject
        if (ta.available && ta.hasScene(scene))
          LiveImage(ta.scene(scene), fit: BoxFit.cover, alignment: const Alignment(0, -0.35), colorFilter: const ColorFilter.matrix(_dim), excludeFromSemantics: true),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, stops: [0, 0.3, 0.62], colors: [Color(0x99141A10), Color(0x00141A10), Color(0xE6141A10)]),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Column(children: [
            PlaceHeader(title: 'Field Notes', short: 'Field Notes', backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
            Expanded(
              child: ListView(padding: EdgeInsets.fromLTRB(16, 4, 16, 24 + mq.padding.bottom), children: [
                // the creature, large, on a soft spotlight
                SizedBox(
                  height: artH + 24,
                  child: Stack(alignment: Alignment.bottomCenter, children: [
                    Positioned(
                      bottom: 6,
                      child: Container(
                        width: artH * 0.9,
                        height: artH * 0.16,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(artH),
                          gradient: const RadialGradient(colors: [Color(0x66000000), Color(0x00000000)]),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(center: const Alignment(0, 0.15), radius: 0.62, colors: [_glow(def.affinity).withAlpha(110), _glow(def.affinity).withAlpha(0)]),
                          ),
                        ),
                      ),
                    ),
                    AnimatedBuilder(
                      animation: _bob,
                      builder: (_, child) {
                        final s = math.sin(_bob.value * 2 * math.pi);
                        return Transform(
                          alignment: Alignment.bottomCenter,
                          transform: Matrix4.identity()..scale(1 + 0.012 * s, 1 - 0.012 * s),
                          child: child,
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Hero(tag: 'creature-$id', child: CreatureImage(id, height: artH, flip: widget.flip)),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(height: 6),
                Semantics(
                  header: true,
                  child: Text(
                    def.name,
                    textAlign: TextAlign.center,
                    style: EvochiText.pageTitle.copyWith(color: const Color(0xFFFFF6DE), shadows: const [Shadow(color: Color(0xCC1E1408), offset: Offset(0, 2), blurRadius: 3)]),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                  kindTag(def),
                  affinityTag(def.affinity),
                  for (final trait in def.traits.skip(1)) Tag(trait),
                ]),
                const SizedBox(height: 14),
                // the page
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  decoration: Kit.parchment(radius: 16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(def.blurb, style: EvochiText.bodyText),
                    const SizedBox(height: 12),
                    fact('Found', def.home),
                    fact('Kind', def.boss ? 'An ancient guardian' : (def.kind == 'hollow' ? 'A forest spirit, once Hollow' : 'A wild Evochi')),
                    fact('Rarity', _cap(def.rarity)),
                    if (comp != null) fact('Companion since', shortDate(comp.since)),
                    if (restored != null) fact('Restored', shortDate(restored)),
                    if (def.likes.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text('Likes', style: EvochiText.caption.copyWith(fontSize: 13)),
                      const SizedBox(height: 6),
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final i in def.likes)
                          Container(
                            padding: const EdgeInsets.fromLTRB(4, 3, 10, 3),
                            decoration: Kit.slot(radius: 10),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              ItemImage(i, size: 28),
                              const SizedBox(width: 4),
                              Text(catalog[i]?.name ?? i, style: EvochiText.tag.copyWith(color: EvochiColor.ink)),
                            ]),
                          ),
                      ]),
                    ],
                    if (def.companion != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: Kit.inset(),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const VoxelIcon('trail_badge', size: 30),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('In encounters: ${def.companion!.name}', style: EvochiText.cardTitle.copyWith(fontSize: 14)),
                              const SizedBox(height: 2),
                              Text(def.companion!.text, style: EvochiText.caption),
                            ]),
                          ),
                        ]),
                      ),
                    ],
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ]),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static Color _glow(String affinity) => switch (affinity) {
        'celestial' => const Color(0xFFB9A6FF),
        'nature' => const Color(0xFFE6FFB0),
        _ => const Color(0xFFFFE9A8),
      };
}

/// The home behind a creature: darker and a little cooler, so the creature reads first.
const _dim = <double>[
  0.42, 0.04, 0.04, 0, 0, //
  0.03, 0.44, 0.05, 0, 0, //
  0.03, 0.05, 0.48, 0, 0, //
  0, 0, 0, 1, 0,
];
