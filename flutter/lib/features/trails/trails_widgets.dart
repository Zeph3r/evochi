// Lumen Trails: shared UI. Navigation (the Guild Board, trail places, encounter prep), creature and
// affinity tags, the Guild rank card, discovery rows, the Journey > Daily discoveries panel, the Home
// discovery chip, the glinting clue on place plates, the discovery and "Found it!" cards, the creature
// card, the EvoDex friends panel, the Village's Trail Guild row and trail places, the Journey's calls to
// a waiting encounter, and the encounter pieces the prep and the encounter share (the big call to
// action, reward tiles, round portraits, thin meter bars). No sixth tab: the board opens from the
// Village and Journey > Daily; encounters start from a quest's prep screen.
// Mirrors the shared bits of web/src/screens/trails.js and encounter.js.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/story/story.dart' as q;
import '../../game/trails/trails.dart' as tr;
import '../home/home_widgets.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'guild_screen.dart';
import 'prep_screen.dart';
import 'trail_place_screen.dart';

TrailsArt get trailsArt => art.trails;

// ---------------------------------------------------------------- navigation ----
void _pushTrail(BuildContext context, String name, WidgetBuilder builder) {
  final here = ModalRoute.of(context)?.settings.name;
  if (here == name) return;
  Navigator.of(context).push(MaterialPageRoute<void>(settings: RouteSettings(name: name), builder: builder));
}

const guildRouteName = 'guild';

Route<void> guildRoute() => MaterialPageRoute<void>(settings: const RouteSettings(name: guildRouteName), builder: (_) => const GuildScreen());

void openGuild(BuildContext context) => _pushTrail(context, guildRouteName, (_) => const GuildScreen());
void openTrailPlace(BuildContext context, String id) => _pushTrail(context, 'trailplace:$id', (_) => TrailPlaceScreen(placeId: id));
void openPrep(BuildContext context, String questId) => _pushTrail(context, 'prep:$questId', (_) => PrepScreen(questId: questId));

/// Where a discovery is inspected: a village place, a trail place, or somewhere at home.
void goDiscoveryPlace(BuildContext context, String place) {
  switch (place) {
    case 'glasshouse' || 'workshop' || 'lodge' || 'waystone':
      openPlace(context, place);
    case 'ruins' || 'gate':
      openTrailPlace(context, place);
    case 'homemap':
      openHomeMap(context);
    case 'garden':
      openGarden(context);
    case 'cottage':
      openCottage(context);
  }
}

// -------------------------------------------------------------------- labels ----
/// "5 h 12 min" until the board resets.
String resetText(int ms) => durationText(ms);

/// "Oct 5" for companion and restoration dates.
String shortDate(int ms) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${months[d.month - 1]} ${d.day}';
}

/// "Lumen Shard, Sunberry Tart" for a list of item ids.
String itemNames(Iterable<String> ids) => ids.map((i) => catalog[i]?.name ?? i).join(', ');

// ------------------------------------------------------------- small widgets ----
/// A little pill like [Tag], in any colours (Hollow purple, an affinity's edge).
class TrailTag extends StatelessWidget {
  const TrailTag(this.text, {super.key, this.icon, this.bg = const Color(0xFFF6EBDD), this.fg = EvochiColor.textSecondary, this.edge = const Color(0xFFE5D3BE)});
  final String text;
  final String? icon;
  final Color bg;
  final Color fg;
  final Color edge;
  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8), border: Border.all(color: edge, width: 1.5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[VoxelIcon(icon!, size: 16), const SizedBox(width: 4)],
          Text(text, style: EvochiText.tag.copyWith(color: fg, fontSize: 12)),
        ]),
      );
}

const _hollowBg = Color(0xFFE2D3F4);
const _hollowFg = Color(0xFF4E357A);
const _hollowEdge = Color(0xFFAA8BCF);

/// "Special Encounter", "Hollow" or "Story Boss".
Widget kindTag(tr.Creature c) {
  if (c.boss) return const TrailTag('Story Boss', bg: _hollowBg, fg: _hollowFg, edge: _hollowEdge);
  if (c.kind == 'hollow') return const TrailTag('Hollow', bg: _hollowBg, fg: _hollowFg, edge: _hollowEdge);
  return const Tag('Special Encounter', tone: TagTone.stage);
}

/// "Nature" with its icon and colour.
Widget affinityTag(String aff) {
  final a = tr.affinityDefs[aff]!;
  return TrailTag(a.name, icon: a.icon, edge: Color(a.color));
}

/// A creature sprite in one of its states (they face left; [flip] turns one toward the right). Older art
/// packs without the trails block show the creature's icon instead.
class CreatureImage extends StatelessWidget {
  const CreatureImage(this.id, {super.key, this.state, this.height = 120, this.flip = false, this.silhouette = false});
  final String id;
  final String? state; // defaults to the creature's 'done' state (happy / restored)
  final double height;
  final bool flip;
  final bool silhouette;
  @override
  Widget build(BuildContext context) {
    Widget img;
    if (!trailsArt.available) {
      img = VoxelIcon('creature_$id', size: height);
    } else {
      final st = state ?? tr.creatureDefs[id]!.states.done;
      img = Image.asset(trailsArt.creature(id, st), height: height, fit: BoxFit.contain, excludeFromSemantics: true, filterQuality: FilterQuality.medium, gaplessPlayback: true);
    }
    if (flip) img = Transform.flip(flipX: true, child: img);
    if (silhouette) img = ColorFiltered(colorFilter: const ColorFilter.mode(Color(0x4D000000), BlendMode.srcIn), child: img);
    return img;
  }
}

/// A creature's round icon (rows, chips), dark when it hasn't been met.
class CreatureFace extends StatelessWidget {
  const CreatureFace(this.id, {super.key, this.size = 50, this.dim = false});
  final String id;
  final double size;
  final bool dim;
  @override
  Widget build(BuildContext context) {
    final icon = VoxelIcon('creature_$id', size: size);
    return dim ? ColorFiltered(colorFilter: const ColorFilter.mode(Color(0x59000000), BlendMode.srcIn), child: icon) : icon;
  }
}

/// A discovery's picture: an item when the art has one, otherwise an icon.
class DiscoveryIcon extends StatelessWidget {
  const DiscoveryIcon(this.id, {super.key, this.size = 44});
  final String id;
  final double size;
  @override
  Widget build(BuildContext context) {
    if (art.hasItem(id)) return ItemImage(id, size: size);
    return VoxelIcon(art.hasIcon(id) ? id : 'discover', size: size);
  }
}

/// The four-point spark used by the clue glint and the travel button.
class SparkIcon extends StatelessWidget {
  const SparkIcon({super.key, this.size = 24});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _SparkPainter()));
}

class _SparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = Path()
      ..moveTo(12 * s, 2 * s)
      ..lineTo(14.2 * s, 9.8 * s)
      ..lineTo(22 * s, 12 * s)
      ..lineTo(14.2 * s, 14.2 * s)
      ..lineTo(12 * s, 22 * s)
      ..lineTo(9.8 * s, 14.2 * s)
      ..lineTo(2 * s, 12 * s)
      ..lineTo(9.8 * s, 9.8 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = const Color(0xFFFFE27A));
    canvas.drawPath(
      p,
      Paint()
        ..color = const Color(0xFFC8832C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * s
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => false;
}

/// A tiny reward chip ("20", "x2", "+12 Guild").
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.image, this.label = ''});
  final Widget image;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        padding: const EdgeInsets.only(left: 3, right: 7),
        decoration: BoxDecoration(color: const Color(0xFFF6EBDD), borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFE5D3BE), width: 1.5)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [image, if (label.isNotEmpty) ...[const SizedBox(width: 3), Text(label, style: EvochiText.tag.copyWith(fontSize: 12))]]),
      );
}

// ----------------------------------------------------------- encounter pieces ----
/// The big green call to action of the encounter and prep screens; [alt] is the amber one ("Talk to
/// Pip"), [gold] the bright gold "Begin Encounter".
class EncCta extends StatefulWidget {
  const EncCta({super.key, required this.label, required this.onTap, this.big = false, this.alt = false, this.gold = false, this.leading, this.trailing, this.semanticLabel});
  final String label;
  final VoidCallback onTap;
  final bool big;
  final bool alt; // amber: "Talk to Pip"
  final bool gold; // gold: "Begin Encounter"
  final Widget? leading;
  final Widget? trailing;
  final String? semanticLabel;
  @override
  State<EncCta> createState() => _EncCtaState();
}

class _EncCtaState extends State<EncCta> {
  bool _down = false;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);
  @override
  Widget build(BuildContext context) {
    final alt = widget.alt;
    final gold = widget.gold;
    final fg = gold ? const Color(0xFF4A2E0C) : (alt ? const Color(0xFF4E3010) : const Color(0xFF1F4A22));
    return Semantics(
      button: true,
      label: widget.semanticLabel ?? widget.label,
      child: ExcludeSemantics(
        child: GestureDetector(
          onTapDown: (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: () {
            final t = DateTime.now();
            if (t.difference(_last).inMilliseconds < 350) return;
            _last = t;
            context.read<GameController>().audio.tick();
            widget.onTap();
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 60),
            constraints: BoxConstraints(minHeight: widget.big ? 62 : 56),
            transform: Matrix4.translationValues(0, _down ? 3 : 0, 0),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: gold ? const Color(0xFFD99A2B) : (alt ? const Color(0xFFA86F1F) : const Color(0xFF5A9C42)), width: 2.5),
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: gold
                    ? const [Color(0xFFFFF1B0), Color(0xFFFFD45E), Color(0xFFF5B53A)]
                    : alt
                        ? const [Color(0xFFFFF0B8), Color(0xFFF9CF6A), Color(0xFFEFB247)]
                        : const [Color(0xFFD2F4B0), Color(0xFF98D872), Color(0xFF71BD50)],
                stops: gold ? const [0, 0.52, 1] : const [0, 0.5, 1],
              ),
              boxShadow: [
                BoxShadow(color: gold ? const Color(0xFFBC7E1F) : (alt ? const Color(0xFFB87A2A) : const Color(0xFF4A8834)), offset: Offset(0, _down ? 1 : 4)),
                BoxShadow(color: gold ? const Color(0x4D78460A) : (alt ? const Color(0x38784614) : const Color(0x40285A14)), blurRadius: 16, offset: const Offset(0, 8)),
              ],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.leading != null) ...[widget.leading!, const SizedBox(width: 10)],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: widget.big ? 21 : 19, color: fg),
                ),
              ),
              if (widget.trailing != null) ...[const SizedBox(width: 10), widget.trailing!],
            ]),
          ),
        ),
      ),
    );
  }
}

/// A reward tile: an icon or item, a name and a line under it.
class RewardTile {
  const RewardTile({this.icon, this.item, required this.name, required this.sub});
  final String? icon;
  final String? item;
  final String name;
  final String sub;
}

/// What an encounter quest pays out, as tiles: the EvoDex entry (or the restoration), keepsakes,
/// coins, gifts and titles. Mirrors `rewardTiles` in web/src/screens/encounter.js.
List<RewardTile> rewardTilesFor(q.StoryRewards r, tr.Creature c, String goal) => [
      if (r.companion != null || goal == 'befriend') RewardTile(icon: 'evodex', name: 'EvoDex entry', sub: c.name),
      if (goal == 'restore') RewardTile(icon: 'evodex', name: 'Restored', sub: c.name),
      for (final id in r.items) RewardTile(item: id, name: catalog[id]?.name ?? id, sub: 'Keepsake'),
      if (r.coins > 0) RewardTile(icon: 'coin', name: 'EvoCoins', sub: '×${r.coins}'),
      for (final e in r.gifts.entries) RewardTile(item: e.key, name: catalog[e.key]?.name ?? e.key, sub: '×${e.value}'),
      for (final t in r.titles) RewardTile(icon: 'crown', name: q.titles[t] ?? t, sub: 'Title'),
    ];

/// Reward tiles: a horizontal row (the result panel) or a wrapping grid (prep).
class RewardTiles extends StatelessWidget {
  const RewardTiles(this.tiles, {super.key, this.row = false});
  final List<RewardTile> tiles;
  final bool row;
  @override
  Widget build(BuildContext context) {
    Widget tile(RewardTile t) => Semantics(
          label: '${t.name}, ${t.sub}',
          child: ExcludeSemantics(
            child: Container(
              width: 78,
              padding: const EdgeInsets.fromLTRB(4, 8, 4, 7),
              decoration: BoxDecoration(color: const Color(0xFFFBF4EA), borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFEFE0CC), width: 1.5)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                t.item != null ? ItemImage(t.item!, size: 46) : VoxelIcon(t.icon ?? 'star', size: 46),
                const SizedBox(height: 2),
                Text(t.name, textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12.5, height: 1.15, color: EvochiColor.ink)),
                Text(t.sub, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 11.5, color: EvochiColor.textHelper)),
              ]),
            ),
          ),
        );
    if (row) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(children: [for (var i = 0; i < tiles.length; i++) ...[if (i > 0) const SizedBox(width: 8), tile(tiles[i])]]),
      );
    }
    return Wrap(spacing: 8, runSpacing: 8, children: [for (final t in tiles) tile(t)]);
  }
}

/// A round portrait (the encounter's nameplates, prep's nameplate and team rows): a creature's icon on
/// a soft disc (violet for the Hollow), your Evochi's face cropped from its sprite, or a "?" for a
/// companion not yet found.
class EncFace extends StatelessWidget {
  const EncFace.creature(String this.creature, {super.key, this.size = 54, this.hollow = false})
      : pet = null,
        question = false,
        wearables = false;
  const EncFace.pet(Pet this.pet, {super.key, this.size = 46, this.wearables = true})
      : creature = null,
        hollow = false,
        question = false;
  const EncFace.question({super.key, this.size = 46})
      : creature = null,
        pet = null,
        hollow = false,
        question = true,
        wearables = false;
  final String? creature;
  final Pet? pet;
  final double size;
  final bool hollow;
  final bool question;
  final bool wearables; // your Evochi with what it wears (the encounter) or without (prep)

  @override
  Widget build(BuildContext context) {
    final (inner, outer, ring) = question
        ? (const Color(0xFFEFE4D6), const Color(0xFFEFE4D6), const Color(0xFFD9C7B1))
        : pet != null
            ? (const Color(0xFFFFF6EC), const Color(0xFFFBDCC6), const Color(0xFFEE9A78))
            : hollow
                ? (const Color(0xFF5E468A), const Color(0xFF33244F), const Color(0xFF9B6BE8))
                : (const Color(0xFFF6FCEC), const Color(0xFFD7ECBE), const Color(0xFF9ACB76));
    final p = pet;
    final Widget face;
    if (question) {
      face = const Center(child: Text('?', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 22, height: 1, color: Color(0xFFA8937F))));
    } else if (p != null) {
      // its face from the front sprite: 150% of the disc, anchored left and a little below the top
      face = Stack(clipBehavior: Clip.none, children: [
        Positioned(
          left: -0.06 * size,
          top: -0.04 * size,
          width: 1.5 * size,
          height: 1.5 * size,
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: const Alignment(-1, -0.56),
            clipBehavior: Clip.hardEdge,
            child: PetSprite(stage: p.stage, palette: p.paletteId, expr: 'happy', overlays: wearables ? p.equipped.values.toList() : const [], height: 90),
          ),
        ),
      ]);
    } else {
      face = Center(child: VoxelIcon('creature_${creature ?? ''}', size: 50));
    }
    return SizedBox(
      width: size,
      height: size,
      child: Stack(fit: StackFit.expand, children: [
        DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // radial-gradient(circle at 50% 35%) out to the farthest corner
            gradient: RadialGradient(center: const Alignment(0, -0.3), radius: 0.82, colors: [inner, outer]),
            border: Border.all(color: ring, width: question ? 2.0 : 2.5),
            boxShadow: question ? null : const [BoxShadow(color: Color(0x14000000), offset: Offset(0, 2))],
          ),
        ),
        ClipOval(child: face),
      ]),
    );
  }
}

/// A thin meter bar (12px): Calm (green), Instability (magenta) or Energy (gold).
class ThinBar extends StatelessWidget {
  const ThinBar({super.key, required this.kind, required this.frac, this.width});
  final String kind; // calm | inst | energy
  final double frac;
  final double? width;
  @override
  Widget build(BuildContext context) {
    final track = switch (kind) {
      'inst' => const Color(0xFF4C3F60),
      'energy' => const Color(0xFF5E4A36),
      _ => const Color(0xFF6E6A50),
    };
    final (fills, stops) = switch (kind) {
      'inst' => (const [Color(0xFFF6C3F8), Color(0xFFDA6FE9), Color(0xFFA13ED0)], const [0.0, 0.5, 1.0]),
      'energy' => (const [Color(0xFFFFE8A0), Color(0xFFF7C548), Color(0xFFE9A535)], const [0.0, 0.55, 1.0]),
      _ => (const [Color(0xFFC3F2A4), Color(0xFF74C95A), Color(0xFF4FA544)], const [0.0, 0.55, 1.0]),
    };
    return Container(
      width: width,
      height: 12,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(6)),
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: frac, end: frac),
        duration: const Duration(milliseconds: 700),
        curve: const Cubic(0.3, 0.8, 0.3, 1),
        builder: (_, t, __) => FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: t.clamp(0.0, 1.0),
          heightFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: fills, stops: stops),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------- Journey: the calls ----
/// The trail jobs whose encounter is waiting, at the top of the Journey's Story tab under "Main
/// Quests" (the UX board's Trail Discovery). Mirrors `disturbanceCards` in web/src/screens/village.js.
class DisturbanceCards extends StatelessWidget {
  const DisturbanceCards({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final ids = [for (final v in c.storyView.encounters) if (tr.encounterDefs.containsKey(v.id)) v.id];
    if (ids.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHead('Main Quests'),
      for (final id in ids) Padding(padding: const EdgeInsets.only(bottom: 8), child: _DisturbCard(questId: id)),
      const SizedBox(height: 2),
    ]);
  }
}

class _DisturbCard extends StatefulWidget {
  const _DisturbCard({required this.questId});
  final String questId;
  @override
  State<_DisturbCard> createState() => _DisturbCardState();
}

class _DisturbCardState extends State<_DisturbCard> with SingleTickerProviderStateMixin {
  late final AnimationController _motes = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  bool _rm = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rm = MediaQuery.of(context).disableAnimations;
    if (_rm) {
      _motes.stop();
    } else if (!_motes.isAnimating) {
      _motes.repeat();
    }
  }

  @override
  void dispose() {
    _motes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = tr.encounterDefs[widget.questId]!;
    final cdef = tr.creatureDefs[e.creature]!;
    final hollow = cdef.kind == 'hollow';
    final befriend = e.goal == 'befriend';
    final place = tr.trailPlaceNames[e.place] ?? e.place; // "the Mossy Ruins"
    final placeCap = tr.placeTitle(e.place); // "The Mossy Ruins"
    final (title, text) = cdef.boss
        ? ('$placeCap: a presence awakens', 'Something ancient sleeps in the gate past the bridge. Its light is fading.')
        : befriend
            ? ('Something stirs in $place', 'A rare ${cdef.name} was seen near the arch. It seems cautious, but curious. Go and say hello.')
            : ('$placeCap: disturbance detected', 'Strange Hollow energy has been detected in $placeCap. Investigate the source.');
    final shown = title.startsWith('the ') ? 'The ${title.substring(4)}' : title;
    final ta = trailsArt;
    final glow = hollow ? const Color(0xF2B478FF) : const Color(0xF2FFDC78);
    final icon = VoxelIcon('creature_${cdef.id}', size: 54);
    Widget mote(int i) {
      final x = (8 + (i * 41) % 84) / 100;
      return AnimatedBuilder(
        animation: _motes,
        builder: (_, child) {
          // moteUp 2.6s linear, each one a little later
          final t = ((_motes.value + i * 0.29 / 2.6) % 1.0);
          final op = t < 0.15 ? t / 0.15 : 1 - (t - 0.15) / 0.85;
          return Positioned(
            left: 76 * x,
            bottom: -6 + 84 * t,
            child: Transform.translate(offset: Offset(6 * t, 0), child: Opacity(opacity: op.clamp(0.0, 1.0), child: child)),
          );
        },
        child: Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: hollow ? const Color(0xFFD9C2FF) : const Color(0xFFFFE58A),
            boxShadow: [BoxShadow(color: hollow ? const Color(0xD9B482FF) : const Color(0xCCFFDC78), blurRadius: 6, spreadRadius: 2)],
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: '$shown. $text',
      child: GestureDetector(
        onTap: () {
          context.read<GameController>().audio.tick();
          openPrep(context, widget.questId);
        },
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: hollow ? const [Color(0xFFFCF9FF), Color(0xFFF1E9FC)] : const [Color(0xFFFFFCF2), Color(0xFFFFF3DA)]),
              border: Border.all(color: hollow ? const Color(0xFFA57BE0) : const Color(0xFFEAB64C), width: 2.5),
              boxShadow: [
                BoxShadow(color: hollow ? const Color(0x2EA57BE0) : const Color(0x2EF4B84E), spreadRadius: 4),
                BoxShadow(color: hollow ? const Color(0xFF8A62C8) : const Color(0xFFD8A040), offset: const Offset(0, 4)),
              ],
            ),
            child: Row(children: [
              // the scene, the creature's silhouette with a glow, motes rising
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: SizedBox(
                  width: 76,
                  height: 76,
                  child: Stack(clipBehavior: Clip.hardEdge, children: [
                    Positioned.fill(
                      child: ta.available && ta.hasScene(e.scene) ? Image.asset(ta.scene(e.scene), fit: BoxFit.cover, excludeFromSemantics: true) : const ColoredBox(color: EvochiColor.panel2),
                    ),
                    Positioned(
                      left: 11,
                      bottom: 3,
                      width: 54,
                      child: Stack(clipBehavior: Clip.none, alignment: Alignment.bottomCenter, children: [
                        ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3), child: ColorFiltered(colorFilter: ColorFilter.mode(glow, BlendMode.srcIn), child: icon)),
                        ColorFiltered(
                          colorFilter: ColorFilter.matrix(<double>[
                            hollow ? 0.25 : 0.28, 0, 0, 0, 0, //
                            0, hollow ? 0.25 : 0.28, 0, 0, 0, //
                            0, 0, hollow ? 0.25 : 0.28, 0, 0, //
                            0, 0, 0, 1, 0,
                          ]),
                          child: icon,
                        ),
                      ]),
                    ),
                    if (!_rm) for (var i = 0; i < 9; i++) mote(i),
                  ]),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.fromLTRB(8, 1, 8, 1),
                    decoration: BoxDecoration(color: hollow ? const Color(0xFFE7D8FB) : const Color(0xFFFCE3A8), borderRadius: BorderRadius.circular(8)),
                    child: Text(befriend ? 'Encounter ready' : 'Hollow detected',
                        style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 11, color: hollow ? const Color(0xFF5B3AA0) : const Color(0xFF8A5A12))),
                  ),
                  const SizedBox(height: 3),
                  Text(shown, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15.5, height: 1.2, color: EvochiColor.ink)),
                  const SizedBox(height: 2),
                  Text(text, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 12.5, height: 17 / 12.5, color: EvochiColor.textHelper)),
                ]),
              ),
              const SizedBox(width: 12),
              const SizedBox(width: 14, child: Text('›', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 24, color: Color(0xFFB49A7E)))),
            ]),
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ the rank ----
class GuildRankCard extends StatelessWidget {
  const GuildRankCard({super.key});
  @override
  Widget build(BuildContext context) {
    final r = context.watch<GameController>().trailsView.rank;
    return Semantics(
      label: 'Trail Guild rank ${r.name}',
      child: GameCard(
        padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
        child: Row(children: [
          const VoxelIcon('trail_badge', size: 54),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Trail Guild', style: EvochiText.caption),
              Row(children: [
                Expanded(child: Text(r.name, style: EvochiText.cardTitle)),
                if (r.next != null) Text('${r.into} / ${r.need} to ${r.next!.name}', style: EvochiText.caption) else const Tag('Top rank', tone: TagTone.ok),
              ]),
              const SizedBox(height: 5),
              SkillBar(value: r.pct, color: const Color(0xFFC9874E)),
            ]),
          ),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------- discoveries ----
void beginDiscoveryAction(GameController c, String id) {
  final r = c.run((s, n) => tr.beginDiscovery(s, id, n));
  if (r.ok) c.audio.play('reward_chime', volume: 0.5);
}

/// One of today's discoveries: what to do, progress, rewards, and its button.
class DiscoveryRow extends StatelessWidget {
  const DiscoveryRow(this.d, {super.key, this.compact = false});
  final tr.DiscoveryView d;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final c = context.read<GameController>();
    final found = d.phase == 'found';
    final limit = compact ? 60 : 90;
    final sub = found ? (d.found.length > limit ? '${d.found.substring(0, limit)}…' : d.found) : 'Walk ${fmt(d.target)} steps, then inspect ${d.placeName}.';
    final Widget action = switch (d.phase) {
      'offered' => EvochiButton(label: 'Begin', small: true, expand: false, tone: ButtonTone.green, onPressed: () => beginDiscoveryAction(c, d.id)),
      'walking' => EvochiButton(label: 'Walk', small: true, expand: false, tone: ButtonTone.cream, icon: const VoxelIcon('steps', size: 18), onPressed: () => goWalk(context)),
      'ready' => EvochiButton(label: 'Inspect', small: true, expand: false, onPressed: () => goDiscoveryPlace(context, d.place)),
      _ => const Tag('Found', tone: TagTone.ok),
    };
    final label = found
        ? '${d.title}: found'
        : (d.phase == 'ready' ? '${d.title}: ready to inspect at ${d.placeName}' : '${d.title}: walk ${fmt(d.target)} steps, then inspect at ${d.placeName}');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: found ? 0.8 : 1,
        child: GameCard(
          padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
          child: Row(children: [
            Expanded(
              child: Semantics(
                button: true,
                label: label,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => showDiscovery(context, d.id),
                  child: ExcludeSemantics(
                    child: Row(children: [
                      DiscoveryIcon(d.icon, size: 44),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(d.title, style: EvochiText.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w900, height: 1.2)),
                          Text(sub, style: EvochiText.caption.copyWith(fontSize: 12.5)),
                          if (d.phase == 'walking' || d.phase == 'ready') ...[
                            const SizedBox(height: 5),
                            ProgressBarX(value: d.pct, height: 8, tone: 'green'),
                            const SizedBox(height: 2),
                            Text('${fmt(d.walked)} / ${fmt(d.target)} steps${d.phase == 'ready' ? ' ✓' : ''}', style: EvochiText.caption.copyWith(fontSize: 11)),
                          ],
                          if (!compact && !found) ...[
                            const SizedBox(height: 5),
                            Wrap(spacing: 4, runSpacing: 4, children: [
                              _MiniChip(image: const VoxelIcon('coin', size: 20), label: '${d.reward.coins}'),
                              for (final e in d.reward.items.entries) _MiniChip(image: ItemImage(e.key, size: 20), label: e.value > 1 ? 'x${e.value}' : ''),
                              _MiniChip(image: const VoxelIcon('trail_badge', size: 20), label: '+${d.reward.guildXp} Guild'),
                            ]),
                          ],
                        ]),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            ConstrainedBox(constraints: const BoxConstraints(minWidth: 76), child: Center(widthFactor: 1, child: action)),
          ]),
        ),
      ),
    );
  }
}

/// Journey > Daily: today's discoveries in brief.
class DiscoveriesPanel extends StatelessWidget {
  const DiscoveriesPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    if (c.state.player == null) return const SizedBox.shrink();
    final t = c.trailsView;
    return Semantics(
      container: true,
      label: 'Trail Guild discoveries',
      child: GameCard(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            const VoxelIcon('discover', size: 24),
            const SizedBox(width: 6),
            const Expanded(child: Text("Today's discoveries", style: EvochiText.cardTitle)),
            Text('Resets in ${resetText(t.msToReset)}', style: EvochiText.caption.copyWith(fontSize: 11)),
          ]),
          const SizedBox(height: 4),
          const Text('The Trail Guild posts three small adventures a day: walk, then inspect the place.', style: EvochiText.caption),
          const SizedBox(height: 8),
          for (final d in t.discoveries) DiscoveryRow(d, compact: true),
          const SizedBox(height: 2),
          EvochiButton(label: 'Open the Guild Board', tone: ButtonTone.cream, icon: const VoxelIcon('trail_badge', size: 22), onPressed: () => openGuild(context)),
        ]),
      ),
    );
  }
}

/// Home: one compact row when a discovery is ready, or today's board hasn't been started.
class DiscoveryChip extends StatelessWidget {
  const DiscoveryChip({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    if (c.state.player == null) return const SizedBox.shrink();
    final t = c.trailsView;
    final d = t.ready.firstOrNull ?? (t.foundToday == 0 && t.walking.isEmpty ? t.offered.firstOrNull : null);
    if (d == null) return const SizedBox.shrink();
    final ready = d.phase == 'ready';
    final title = ready ? 'Discovery ready!' : 'New Daily Discovery!';
    final sub = ready ? 'Inspect ${d.placeName}: ${d.title}' : d.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        button: true,
        label: '$title $sub',
        child: GestureDetector(
          onTap: () {
            c.audio.play('ui_tap', volume: 0.4);
            if (ready) {
              goDiscoveryPlace(context, d.place);
            } else {
              showDiscovery(context, d.id);
            }
          },
          child: ExcludeSemantics(
            child: GameCard(
              color: const Color(0xF5FFF6E8),
              padding: const EdgeInsets.fromLTRB(6, 6, 10, 6),
              child: Row(children: [
                const VoxelIcon('discover', size: 34),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: EvochiText.cardTitle.copyWith(fontSize: 13, fontWeight: FontWeight.w900)),
                    Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: EvochiText.tag.copyWith(fontSize: 12)),
                  ]),
                ),
                homeChevron,
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where the clue glint sits on each place plate (fractions of the plate).
const _clueSpots = <String, Offset>{
  'glasshouse': Offset(0.68, 0.64),
  'workshop': Offset(0.30, 0.66),
  'lodge': Offset(0.72, 0.60),
  'waystone': Offset(0.50, 0.72),
  'garden': Offset(0.50, 0.36),
  'cottage': Offset(0.60, 0.60),
  'homemap': Offset(0.15, 0.44),
  'ruins': Offset(0.14, 0.70),
  'gate': Offset(0.86, 0.72),
};

/// A glinting "Inspect" button on a place plate while a discovery is ready there. Use it as a direct
/// child of the plate's [Stack]; [width] and [height] are the plate's size on screen.
class ClueGlint extends StatefulWidget {
  const ClueGlint({super.key, required this.place, required this.width, required this.height});
  final String place;
  final double width;
  final double height;
  @override
  State<ClueGlint> createState() => _ClueGlintState();
}

class _ClueGlintState extends State<ClueGlint> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _a.stop();
    } else if (!_a.isAnimating) {
      _a.repeat();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final clues = tr.cluesAt(c.state, widget.place, c.now);
    if (clues.isEmpty) return const SizedBox.shrink();
    final d = clues.first;
    final spot = _clueSpots[widget.place] ?? const Offset(0.5, 0.6);
    return Positioned(
      left: widget.width * spot.dx,
      top: widget.height * spot.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: Semantics(
          button: true,
          label: 'Inspect: ${d.title}',
          child: GestureDetector(
            onTap: () => inspectClue(context, d.id),
            child: AnimatedBuilder(
              animation: _a,
              builder: (_, child) => Transform.translate(offset: Offset(0, -6 * math.sin(_a.value * math.pi)), child: child),
              child: ExcludeSemantics(
                child: Container(
                  constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
                  padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white, width: 2),
                    gradient: const RadialGradient(center: Alignment(0, -0.3), radius: 0.9, colors: [Color(0xFFFFF6D5), EvochiColor.primary]),
                    boxShadow: const [
                      BoxShadow(color: Color(0x73FFE696), spreadRadius: 4),
                      BoxShadow(color: Color(0xE6FFD26E), blurRadius: 18),
                      BoxShadow(color: EvochiColor.primaryShadow, offset: Offset(0, 3)),
                    ],
                  ),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    RotationTransition(turns: _a, child: const SparkIcon(size: 26)),
                    Text('Inspect', style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontSize: 12, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A discovery's card: the clue (or the find), the walk, rewards and what to do next.
Future<void> showDiscovery(BuildContext context, String id) {
  final c = context.read<GameController>();
  return showEvochiSheet<void>(context, builder: (sheet) {
    final cc = sheet.watch<GameController>();
    final d = tr.discoveryView(cc.state, id, cc.now);
    final found = d.phase == 'found';
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Container(width: 44, height: 5, margin: const EdgeInsets.only(bottom: 12), decoration: BoxDecoration(color: const Color(0xFFDCC6AE), borderRadius: BorderRadius.circular(3)))),
      Row(children: [
        const VoxelIcon('discover', size: 48),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Trail Guild discovery', style: EvochiText.caption),
            Semantics(header: true, child: Text(d.title, style: EvochiText.section)),
          ]),
        ),
      ]),
      const SizedBox(height: 8),
      Text(found ? d.found : d.clue, style: EvochiText.bodyText),
      if (!found) ...[
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: EvochiColor.inset, borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Walk ${fmt(d.target)} steps, then inspect ${d.placeName}', style: EvochiText.cardTitle.copyWith(fontSize: 14)),
            const SizedBox(height: 6),
            if (d.phase == 'offered')
              const Text('Only steps after you begin count.', style: EvochiText.caption)
            else ...[
              ProgressBarX(value: d.pct, height: 10, tone: 'green', semantic: 'Discovery walk'),
              const SizedBox(height: 3),
              Text('${fmt(d.walked)} / ${fmt(d.target)} new steps${d.phase == 'ready' ? ' ✓ ready' : ''}', style: EvochiText.caption),
            ],
          ]),
        ),
      ],
      const SizedBox(height: 12),
      const Text('Reward', style: EvochiText.cardTitle),
      const SizedBox(height: 6),
      Wrap(spacing: 6, runSpacing: 6, children: [
        Tag('${d.reward.coins}', tone: TagTone.stage, icon: 'coin'),
        for (final e in d.reward.items.entries) ItemCountChip(id: e.key, label: countLabel(e.key, e.value)),
        Tag('+${d.reward.guildXp} Guild XP', tone: TagTone.ok, icon: 'trail_badge'),
      ]),
      const SizedBox(height: 14),
      if (d.phase == 'offered') ...[
        EvochiButton(label: 'Begin', tone: ButtonTone.green, onPressed: () => beginDiscoveryAction(c, id)),
        const SizedBox(height: 8),
      ],
      if (d.phase == 'walking') ...[
        EvochiButton(
          label: 'Go for a walk',
          tone: ButtonTone.green,
          onPressed: () {
            Navigator.pop(sheet);
            goWalk(context);
          },
        ),
        const SizedBox(height: 8),
      ],
      if (d.phase == 'ready') ...[
        EvochiButton(
          label: 'Go to ${d.placeName}',
          onPressed: () {
            Navigator.pop(sheet);
            goDiscoveryPlace(context, d.place);
          },
        ),
        const SizedBox(height: 8),
      ],
      EvochiButton(label: 'Close', tone: ButtonTone.cream, onPressed: () => Navigator.pop(sheet)),
    ]);
  });
}

/// Tapping the glint: the find, its text and rewards (and a Guild rank-up).
void inspectClue(BuildContext context, String id) {
  final c = context.read<GameController>();
  final r = c.run((s, n) => tr.inspectDiscovery(s, id, n));
  if (!r.ok) return;
  c.audio.play('reward_chime');
  final d = tr.discoveryDefs[id]!;
  final rank = r.events.where((e) => e.type == 'guild_rank').firstOrNull;
  showEvochiDialog<void>(context, builder: (dctx) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const GoldBanner('Found it!'),
        const SizedBox(height: 10),
        Text(d.title, style: EvochiText.section, textAlign: TextAlign.center),
        const SizedBox(height: 6),
        Text(d.found, style: EvochiText.bodyText, textAlign: TextAlign.center),
        const SizedBox(height: 10),
        Wrap(alignment: WrapAlignment.center, spacing: 8, runSpacing: 8, children: [
          Tag('+${d.reward.coins}', tone: TagTone.stage, icon: 'coin'),
          for (final e in d.reward.items.entries) ItemCountChip(id: e.key, label: countLabel(e.key, e.value)),
          Tag('+${d.reward.guildXp} Guild XP', tone: TagTone.ok, icon: 'trail_badge'),
        ]),
        if (rank != null) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: EvochiColor.inset, borderRadius: BorderRadius.circular(12)),
            child: Text('Guild rank up: ${rank.data['name']}!', style: EvochiText.cardTitle.copyWith(fontSize: 14), textAlign: TextAlign.center),
          ),
        ],
        const SizedBox(height: 12),
        EvochiButton(label: 'Lovely', onPressed: () => Navigator.pop(dctx)),
      ]));
}

// ------------------------------------------------------------------ creatures ----
/// A befriended or restored creature: its picture, tags, story and what it does for you.
Future<void> showCreatureCard(BuildContext context, String id) {
  final c = context.read<GameController>();
  final def = tr.creatureDefs[id]!;
  final t = c.trailsView;
  final comp = t.companions.where((x) => x.id == id).firstOrNull;
  final restored = t.restored[id];
  Widget kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 128, child: Text(k, style: EvochiText.caption.copyWith(fontSize: 13))),
          Expanded(child: Text(v, style: EvochiText.cardTitle.copyWith(fontSize: 13))),
        ]),
      );
  return showEvochiDialog<void>(context, builder: (d) => SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const RadialGradient(center: Alignment(0, 0.4), radius: 0.9, colors: [Color(0xFFFFF9EC), Color(0xFFEFDFC9)]),
            ),
            alignment: Alignment.center,
            child: CreatureImage(id, height: def.size == 'large' ? 150 : 120),
          ),
          const SizedBox(height: 8),
          Text(def.name, style: EvochiText.section, textAlign: TextAlign.center),
          const SizedBox(height: 6),
          Wrap(alignment: WrapAlignment.center, spacing: 4, runSpacing: 4, children: [
            kindTag(def),
            affinityTag(def.affinity),
            for (final trait in def.traits.skip(1)) Tag(trait),
          ]),
          const SizedBox(height: 8),
          Text(def.blurb, style: EvochiText.bodyText, textAlign: TextAlign.center),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            decoration: BoxDecoration(color: EvochiColor.inset, borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              kv('Found', def.home),
              if (comp != null) kv('Companion since', shortDate(comp.since)),
              if (restored != null) kv('Restored', shortDate(restored)),
              if (def.companion != null) kv('In encounters', def.companion!.name),
            ]),
          ),
          if (def.companion != null && comp != null) ...[
            const SizedBox(height: 8),
            Text(def.companion!.text, style: EvochiText.caption, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 12),
          EvochiButton(label: 'Close', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d)),
        ]),
      ));
}

/// A creature in a grid: its face, name and how you know it (or '???').
class FriendCard extends StatelessWidget {
  const FriendCard({super.key, required this.id, required this.known, required this.sub, this.onTap});
  final String id;
  final bool known;
  final String sub;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final name = tr.creatureDefs[id]!.name;
    return Semantics(
      button: onTap != null,
      label: known ? '$name, $sub' : 'Not met yet',
      child: GestureDetector(
        onTap: onTap,
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFEADAC6), width: 2),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFBF6), Color(0xFFF6EBDD)]),
              boxShadow: const [BoxShadow(color: Color(0xFFDCC6AC), offset: Offset(0, 2))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              CreatureFace(id, size: 64, dim: !known),
              const SizedBox(height: 2),
              Text(known ? name : '???', maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: EvochiText.tag.copyWith(color: EvochiColor.ink, fontWeight: FontWeight.w900)),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: EvochiText.caption.copyWith(fontSize: 11)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Three across, for friend cards.
class FriendGrid extends StatelessWidget {
  const FriendGrid({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => GridView.count(
        crossAxisCount: 3,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.82,
        children: children,
      );
}

/// EvoDex: companions and restored guardians.
class FriendsPanel extends StatelessWidget {
  const FriendsPanel({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    if (c.state.player == null) return const SizedBox.shrink();
    final t = c.trailsView;
    final met = tr.creatureOrder.where(t.known).length;
    String sub(String id) {
      final def = tr.creatureDefs[id]!;
      if (t.known(id)) return t.isRestored(id) ? 'Restored' : 'Companion';
      return def.boss ? 'A story boss' : (def.kind == 'hollow' ? 'A Hollow' : 'A wild Evochi');
    }

    return GameCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [const Expanded(child: Text('Friends of the trail', style: EvochiText.cardTitle)), Tag('$met / ${tr.creatureOrder.length} met')]),
        const SizedBox(height: 8),
        FriendGrid(children: [
          for (final id in tr.creatureOrder) FriendCard(id: id, known: t.known(id), sub: sub(id), onTap: t.known(id) ? () => showCreatureCard(context, id) : null),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Befriended Evochi visit your nest and help in encounters. Restored guardians light the Lumen Trails. Both are found through Trail Guild jobs.',
          style: EvochiText.caption,
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------- trail quests ----
/// A trail job on the Guild Board: the creature, its tags and what's next (opens prep when ready).
class TrailQuestRow extends StatelessWidget {
  const TrailQuestRow(this.v, {super.key});
  final q.StoryQuestView v;
  @override
  Widget build(BuildContext context) {
    final e = tr.encounterDefs[v.id]!;
    final def = tr.creatureDefs[e.creature]!;
    final ready = v.next.kind == 'encounter';
    final sub = ready ? 'Ready: travel to ${tr.trailPlaceNames[e.place]}' : nextText(v);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: v.completed ? 0.78 : 1,
        child: TapCard(
          label: '${v.title}. $sub',
          padding: const EdgeInsets.fromLTRB(6, 8, 10, 8),
          highlight: ready,
          onTap: () => ready ? openPrep(context, v.id) : showStoryQuest(context, v.id),
          child: Row(children: [
            SizedBox(width: 54, height: 60, child: Center(child: CreatureFace(e.creature, size: 50, dim: !(v.completed || v.accepted)))),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(v.title, style: EvochiText.cardTitle.copyWith(fontSize: 15, fontWeight: FontWeight.w900)),
                  storyStatusTag(v),
                ]),
                const SizedBox(height: 3),
                Wrap(spacing: 4, runSpacing: 4, children: [kindTag(def), affinityTag(def.affinity)]),
                const SizedBox(height: 3),
                Text(sub, style: EvochiText.caption.copyWith(fontSize: 13)),
                if (v.accepted && !v.completed) Padding(padding: const EdgeInsets.only(top: 4), child: WalkProgress(v)),
              ]),
            ),
            homeChevron,
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ the Village ----
/// "2 discoveries ready to inspect", "A trail job is ready", "1 discovery left today · Wanderer".
String guildBlurb(GameController c) {
  if (c.state.player == null) return 'Daily discoveries and trail jobs.';
  final t = c.trailsView;
  final ready = t.ready.length;
  if (ready > 0) return '$ready discover${ready == 1 ? 'y' : 'ies'} ready to inspect';
  if (c.storyView.encounters.isNotEmpty) return 'A trail job is ready: prepare and travel';
  final left = t.discoveries.length - t.foundToday;
  if (left > 0) return '$left discover${left == 1 ? 'y' : 'ies'} left today · ${t.rank.name}';
  return 'All found today · ${t.rank.name}';
}

/// The Square's Trail Guild Board row.
class GuildBoardRow extends StatelessWidget {
  const GuildBoardRow({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final dot = c.state.player != null && c.guildAttention;
    final blurb = guildBlurb(c);
    return TapCard(
      label: 'Trail Guild Board. $blurb${dot ? '. Something new' : ''}',
      onTap: () => openGuild(context),
      child: Row(children: [
        const VoxelIcon('trail_badge', size: 40),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Trail Guild Board', style: EvochiText.cardTitle),
            Text(blurb, style: EvochiText.caption),
          ]),
        ),
        if (dot) ...[const BadgeDot(), const SizedBox(width: 4)],
        homeChevron,
      ]),
    );
  }
}

/// The Square's Lumen Trails places, once the Forest Guardian (ruins) or the Sentinel (gate) job
/// reaches them.
class TrailPlacesSection extends StatelessWidget {
  const TrailPlacesSection({super.key});
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final st = c.storyView;
    final ruinsOpen = const {'ruins_ready', 'completed'}.contains(st.quest('eq01').phase);
    final gateOpen = const {'gate_ready', 'completed'}.contains(st.quest('eq03').phase);
    if ((!ruinsOpen && !gateOpen) || !trailsArt.available) return const SizedBox.shrink();
    final cards = <Widget>[
      if (ruinsOpen)
        _TrailPlaceCard(
          id: 'ruins',
          name: 'Mossy Ruins',
          blurb: st.flag('sprout_restored') ? 'Peaceful again. Petals on the arch.' : 'A quiet forest ruin on the old trail.',
          scene: 'mossy_ruins',
        ),
      if (gateOpen)
        _TrailPlaceCard(
          id: 'gate',
          name: 'The Old Gate',
          blurb: st.flag('sentinel_restored') ? 'Open, and humming at dusk.' : 'Past the bridge. Hollow light in the dusk.',
          scene: 'sentinel_gate',
        ),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SizedBox(height: 6),
      const SectionHead('Lumen Trails'),
      GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 1.02,
        children: cards,
      ),
    ]);
  }
}

class _TrailPlaceCard extends StatelessWidget {
  const _TrailPlaceCard({required this.id, required this.name, required this.blurb, required this.scene});
  final String id;
  final String name;
  final String blurb;
  final String scene;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final clue = tr.cluesAt(c.state, id, c.now).isNotEmpty;
    return Semantics(
      button: true,
      label: '$name. $blurb${clue ? '. Something glints here' : ''}',
      child: ExcludeSemantics(
        child: GestureDetector(
          onTap: () {
            c.audio.play('ui_tap', volume: 0.4);
            openTrailPlace(context, id);
          },
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFE6D3BD), width: 2),
              color: EvochiColor.canvas,
              boxShadow: const [BoxShadow(color: EvochiColor.cardBevel, offset: Offset(0, 3))],
            ),
            child: Stack(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SizedBox(height: 84, child: Image.asset(trailsArt.scene(scene), fit: BoxFit.cover, alignment: const Alignment(0, 0.2))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                  child: Row(children: [
                    const VoxelIcon('trail', size: 20),
                    const SizedBox(width: 5),
                    Expanded(child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: EvochiText.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w900))),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
                  child: Text(blurb, maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary, fontWeight: FontWeight.w700)),
                ),
              ]),
              if (clue) const Positioned(top: 6, right: 6, child: BadgeDot()),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- the plates ----
/// A trail scene shown [heightFactor] of its height (cropped at [alignY], 0 = top, 1 = bottom), with
/// [overlays] laid out in the full plate's coordinates and [front] in the visible box's.
class TrailPlate extends StatelessWidget {
  const TrailPlate({super.key, required this.scene, this.heightFactor = 0.8, this.alignY = 0.42, this.overlays, this.front, this.semanticLabel});
  final String scene;
  final double heightFactor;
  final double alignY;
  final List<Widget> Function(double w, double h)? overlays; // full plate size on screen
  final List<Widget> Function(double w, double h)? front; // visible box size on screen
  final String? semanticLabel;
  @override
  Widget build(BuildContext context) {
    final size = trailsArt.sceneSize(scene);
    return AspectRatio(
      aspectRatio: size.width / (size.height * heightFactor),
      child: LayoutBuilder(builder: (ctx, b) {
        final w = b.maxWidth;
        final hPlate = w * size.height / size.width;
        final visible = b.maxHeight;
        final top = -(hPlate - visible) * alignY;
        return ClipRect(
          child: Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned(
              left: 0,
              top: top,
              width: w,
              height: hPlate,
              child: Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: Image.asset(trailsArt.scene(scene), fit: BoxFit.cover, semanticLabel: semanticLabel, excludeFromSemantics: semanticLabel == null, gaplessPlayback: true),
                ),
                ...?overlays?.call(w, hPlate),
              ]),
            ),
            // fade into the page
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 48,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x00F8EBDD), EvochiColor.panel])),
                ),
              ),
            ),
            ...?front?.call(w, visible),
          ]),
        );
      }),
    );
  }
}

/// A creature standing at a plate anchor: [widthFrac] of the plate wide, feet on the anchor.
Widget creatureAt({
  required String id,
  required String state,
  required Offset anchor, // plate pixels
  required Size plate, // plate pixels
  required double w, // plate width on screen
  required double h, // plate height on screen
  required double widthFrac,
  double footFrac = 0.92,
  bool flip = true,
}) {
  final cs = trailsArt.creatureSize(id);
  final cw = w * widthFrac;
  final ch = cw * cs.height / cs.width;
  return Positioned(
    left: anchor.dx / plate.width * w - cw / 2,
    top: anchor.dy / plate.height * h - ch * footFrac,
    width: cw,
    height: ch,
    child: IgnorePointer(child: CreatureImage(id, state: state, height: ch, flip: flip)),
  );
}
