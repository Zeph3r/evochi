// Lumen Trails: the trail places, scene first. The Mossy Ruins (tangled in Hollow while Tangled Lumen
// is underway) and the Old Gate past the bridge fill the whole screen, living (the waterfall falls, the
// trees sway, the crystals pulse), and everything you can do is in the world:
// - the friends who live there stand in the scene: tap one for its own page (Field Notes);
// - a trail job's creature waits at its spot with a "!": tap it to prepare the encounter;
// - a ready discovery glints where it was found: tap to inspect;
// - your Evochi is there with you (tap it for a hello).
// The scene is wider than a phone: drag to look around (an edge hint points at anything off to the
// side). A small dock at the bottom says where you are and offers the one action that matters now.

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/story/story.dart' as q;
import '../../game/trails/trails.dart' as tr;
import '../home/home_widgets.dart';
import '../shared/kit.dart';
import '../shared/live_scene.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import '../village/story_widgets.dart';
import '../village/village_screen.dart';
import 'creature_page.dart';
import 'trails_widgets.dart';

/// Where something stands in a scene: its feet, in the scene image's own pixels, how wide it is (a
/// fraction of the image's width) and whether it faces left.
class _Spot {
  const _Spot(this.x, this.y, [this.w = 0.18, this.flip = false]);
  final double x;
  final double y;
  final double w;
  final bool flip;
}

const _ruins = <String, _Spot>{
  'petalune': _Spot(566, 632, 0.2, true),
  'hollow_sprout': _Spot(226, 606, 0.17),
  'pet': _Spot(352, 690, 0.17),
  'clue': _Spot(108, 604),
  'focus': _Spot(390, 560),
};

const _spots = <String, Map<String, _Spot>>{
  'mossy_ruins': _ruins,
  'mossy_ruins_hollow': _ruins,
  'sentinel_gate': {
    'sentinel': _Spot(390, 566, 0.42),
    'pet': _Spot(300, 694, 0.17),
    'clue': _Spot(664, 646),
    'focus': _Spot(390, 520),
  },
};

/// The scene's ground (the feet line of whoever stands nearest) stays above the dock.
const _groundY = 700.0;

class TrailPlaceScreen extends StatefulWidget {
  const TrailPlaceScreen({super.key, required this.placeId});
  final String placeId; // ruins | gate

  @override
  State<TrailPlaceScreen> createState() => _TrailPlaceScreenState();
}

class _TrailPlaceScreenState extends State<TrailPlaceScreen> with TickerProviderStateMixin {
  ScrollController? _cam;
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
  late final AnimationController _hop = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  bool _rm = false;

  String get _id => widget.placeId == 'gate' ? 'gate' : 'ruins';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rm = MediaQuery.of(context).disableAnimations;
    if (_rm) {
      _idle.stop();
    } else if (!_idle.isAnimating) {
      _idle.repeat();
    }
  }

  @override
  void dispose() {
    _cam?.dispose();
    _idle.dispose();
    _hop.dispose();
    super.dispose();
  }

  String _sceneFor(GameController c) {
    final st = c.storyView;
    if (_id == 'gate') return 'sentinel_gate';
    final e2 = st.quest('eq02').phase;
    return st.flag('sprout_restored') || !st.flag('petalune_befriended')
        ? 'mossy_ruins'
        : (e2 == 'ruins_ready' || e2 == 'accepted_walk' ? 'mossy_ruins_hollow' : 'mossy_ruins');
  }

  q.StoryQuestView? _quest(GameController c) => c.storyView.trail.where((v) => v.next.place == _id && v.accepted && !v.completed).firstOrNull;

  /// The trail job's creature, waiting here for an encounter (null: none).
  tr.EncounterDef? _target(q.StoryQuestView? v) {
    if (v == null || v.next.kind != 'encounter') return null;
    final e = tr.encounterDefs[v.id];
    return e != null && e.place == _id ? e : null;
  }

  List<String> _friends(GameController c) {
    final t = c.trailsView;
    return _id == 'ruins' ? ['petalune', 'hollow_sprout'].where(t.known).toList() : (t.isRestored('sentinel') ? ['sentinel'] : <String>[]);
  }

  void _lookAt(double x, double viewW) {
    final cam = _cam;
    if (cam == null || !cam.hasClients) return;
    final to = (x - viewW / 2).clamp(0.0, cam.position.maxScrollExtent).toDouble();
    if (_rm) {
      cam.jumpTo(to);
    } else {
      cam.animateTo(to, duration: const Duration(milliseconds: 520), curve: Curves.easeInOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final id = _id;
    final t = c.trailsView;
    final sceneId = _sceneFor(c);
    final name = id == 'gate' ? 'The Old Gate' : 'Mossy Ruins';
    final quest = _quest(c);
    final target = _target(quest);
    final friends = _friends(c);
    final clues = tr.cluesAt(c.state, id, c.now);
    final String text;
    if (id == 'gate') {
      text = t.isRestored('sentinel')
          ? 'The gate stands open. Beyond it the third trail glows faintly, on and on past the horizon.'
          : 'The bridge creaks but holds. Past it, the old gate waits in the dusk, humming with Hollow light.';
    } else if (t.isRestored('hollow_sprout')) {
      text = 'The ruins are peaceful now. Petals drift from the arch, and the little sprout waves at everyone who passes.';
    } else if (c.storyView.flag('petalune_befriended')) {
      text = 'The ruins are quiet. Somewhere under the moss, trail runes point north.';
    } else {
      text = 'A quiet ruin where the forest has taken the stones back. Runes under the moss, a waterfall behind the arch.';
    }
    final ta = trailsArt;
    final mq = MediaQuery.of(context);
    final sp = _spots[sceneId]!;
    final pet = c.state.pet;
    final petAlive = pet != null && !(c.view.pet?.vitality.dead ?? false);
    final cta = quest != null || clues.isNotEmpty;

    return Scaffold(
      backgroundColor: const Color(0xFF1E2418),
      body: LayoutBuilder(builder: (ctx, b) {
        final w = b.maxWidth, h = b.maxHeight;
        final size = ta.available ? ta.sceneSize(sceneId) : const Size(780, 867);
        // the dock's height (estimated: two lines of text, and a button when there's something to do)
        final reserve = (cta ? 128.0 : 66.0) + 12 + mq.padding.bottom + 10;
        // cover the screen; the ground sits just above the dock (the scene may rise a little for that,
        // its foot then fading into the shade under the dock)
        final s = math.max(w / size.width, h / size.height);
        final iw = size.width * s, ih = size.height * s;
        final top = (h - reserve - _groundY * s).clamp(h - ih - reserve * 0.6, 0.0).toDouble();
        Offset at(_Spot p) => Offset(p.x * s, p.y * s + top);

        // the camera starts on whatever matters most here (the job's creature, a clue, the arch)
        if (_cam == null) {
          final f = (target != null ? sp[target.creature] : null) ?? (clues.isNotEmpty ? sp['clue'] : null);
          // else frame whoever is here (the friends and your Evochi), or the arch
          final xs = [for (final k in [...friends, if (petAlive) 'pet']) if (sp[k] != null) sp[k]!.x];
          final fx = f?.x ?? (xs.isEmpty ? sp['focus']!.x : (xs.reduce(math.min) + xs.reduce(math.max)) / 2);
          _cam = ScrollController(initialScrollOffset: (fx * s - w / 2).clamp(0.0, math.max(0.0, iw - w)).toDouble());
        }

        final scene = <Widget>[
          Positioned(
            left: 0,
            top: top,
            width: iw,
            height: ih,
            child: ta.available && ta.hasScene(sceneId)
                ? LiveImage(
                    ta.scene(sceneId),
                    fit: BoxFit.fill,
                    semanticLabel: id == 'gate' ? 'A great broken gate at dusk, Hollow crystals glowing around it.' : 'A quiet forest ruin: a mossy arch, flagstones and a waterfall.',
                  )
                : const ColoredBox(color: Color(0xFF6E8F54)),
          ),
          // friends, where they live
          for (final f in friends)
            if (sp[f] != null && f != target?.creature)
              ..._creature(f, tr.creatureDefs[f]!.states.done, sp[f]!, size.width * s, at(sp[f]!),
                  onTap: () => openCreaturePage(context, f, flip: sp[f]!.flip)),
          // the job's creature, waiting
          if (target != null && sp[target.creature] != null)
            ..._creature(target.creature, tr.creatureDefs[target.creature]!.states.start, sp[target.creature]!, size.width * s, at(sp[target.creature]!),
                marker: true, onTap: () => openPrep(context, quest!.id)),
          // your Evochi, here with you
          if (petAlive) _pet(c, at(sp['pet']!), sp['pet']!.w * iw),
          if (clues.isNotEmpty)
            Positioned(
              left: at(sp['clue']!).dx,
              top: at(sp['clue']!).dy,
              child: FractionalTranslation(
                translation: const Offset(-0.5, -1),
                child: InspectBadge(label: 'Inspect: ${clues.first.title}', onTap: () => inspectClue(context, clues.first.id)),
              ),
            ),
        ];

        // what's off to the side: the job's creature and a clue
        final marks = <(double, String, String)>[
          if (target != null && sp[target.creature] != null) (at(sp[target.creature]!).dx, 'creature_${target.creature}', tr.creatureDefs[target.creature]!.name),
          if (clues.isNotEmpty) (at(sp['clue']!).dx, 'discover', clues.first.title),
        ];
        final cam = _cam!;

        return Stack(children: [
          Positioned.fill(
            // look around by dragging (a mouse too) or with the wheel
            child: Listener(
              onPointerSignal: (e) {
                if (e is PointerScrollEvent && cam.hasClients && e.scrollDelta.dx == 0) {
                  cam.jumpTo((cam.offset + e.scrollDelta.dy).clamp(0.0, cam.position.maxScrollExtent).toDouble());
                }
              },
              child: ScrollConfiguration(
                behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false, dragDevices: PointerDeviceKind.values.toSet()),
                child: SingleChildScrollView(
                  controller: cam,
                  scrollDirection: Axis.horizontal,
                  physics: const ClampingScrollPhysics(),
                  child: SizedBox(width: iw, height: h, child: Stack(clipBehavior: Clip.none, children: scene)),
                ),
              ),
            ),
          ),
          // the dock sits on a soft shade
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: reserve + 40,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.5, 1],
                    colors: [Color(0x001E2418), Color(0xB31E2418), Color(0xFF1E2418)],
                  ),
                ),
              ),
            ),
          ),
          // the header reads over a soft shade
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 140,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x8C141A10), Color(0x00141A10)])),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: SafeArea(
              bottom: false,
              child: PlaceHeader(title: name, short: name.replaceFirst('The ', ''), backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
            ),
          ),
          // edge hints
          Positioned.fill(
            child: AnimatedBuilder(
              animation: cam,
              builder: (_, __) {
                final off = cam.hasClients ? cam.offset : cam.initialScrollOffset;
                return Stack(children: [
                  for (final m in marks)
                    if (m.$1 - off < 24 || m.$1 - off > w - 24)
                      Positioned(
                        top: math.min(h * 0.44, h - reserve - 60),
                        left: m.$1 - off < 24 ? 8 : null,
                        right: m.$1 - off < 24 ? null : 8,
                        child: _EdgeHint(left: m.$1 - off < 24, icon: m.$2, label: m.$3, onTap: () => _lookAt(m.$1, w)),
                      ),
                ]);
              },
            ),
          ),
          // the dock
          Positioned(
            left: 12,
            right: 12,
            bottom: 12 + mq.padding.bottom,
            child: _Dock(text: text, quest: quest, target: target, clue: clues.isEmpty ? null : clues.first),
          ),
        ]);
      }),
    );
  }

  /// A creature standing with its feet at [feet]: a soft shadow, itself (breathing), and a name tag or
  /// a job marker. [sceneW]: the scene's width on screen.
  List<Widget> _creature(String id, String state, _Spot p, double sceneW, Offset feet, {bool marker = false, required VoidCallback onTap}) {
    final ta = trailsArt;
    final def = tr.creatureDefs[id]!;
    final cs = ta.available ? ta.creatureSize(id) : const Size(180, 200);
    final ground = ta.available ? ta.creatureAnchor(id, 'ground') : Offset(cs.width / 2, cs.height * 0.9);
    final cw = p.w * sceneW;
    final ch = cw * cs.height / cs.width;
    final ax = (p.flip ? cs.width - ground.dx : ground.dx) / cs.width;
    final left = feet.dx - cw * ax;
    final topY = feet.dy - ch * (ground.dy / cs.height);
    final phase = (id.hashCode % 100) / 100.0;
    return [
      Positioned(
        left: feet.dx - cw * 0.36,
        top: feet.dy - cw * 0.07,
        width: cw * 0.72,
        height: cw * 0.14,
        child: const IgnorePointer(
          child: DecoratedBox(decoration: BoxDecoration(gradient: RadialGradient(colors: [Color(0x59000000), Color(0x00000000)]))),
        ),
      ),
      Positioned(
        left: left,
        top: topY,
        width: cw,
        height: ch,
        child: Semantics(
          button: true,
          label: marker ? '${def.name}: a trail job. Prepare the encounter' : '${def.name}. Open its page',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: ExcludeSemantics(
              child: AnimatedBuilder(
                animation: _idle,
                builder: (_, child) {
                  final v = math.sin((_idle.value + phase) * 2 * math.pi);
                  return Transform(alignment: Alignment.bottomCenter, transform: Matrix4.identity()..scale(1 + 0.014 * v, 1 - 0.014 * v), child: child);
                },
                child: Hero(tag: 'creature-$id', child: CreatureImage(id, state: state, height: ch, flip: p.flip)),
              ),
            ),
          ),
        ),
      ),
      if (marker)
        Positioned(
          left: feet.dx,
          top: topY - 4,
          child: FractionalTranslation(
            translation: const Offset(-0.5, -1),
            child: GestureDetector(onTap: onTap, child: ExcludeSemantics(child: _JobMarker(idle: _idle, rm: _rm))),
          ),
        )
      else
        Positioned(
          left: feet.dx,
          top: feet.dy + 2,
          child: FractionalTranslation(
            translation: const Offset(-0.5, 0),
            child: IgnorePointer(child: _NameTag(def.name)),
          ),
        ),
    ];
  }

  Widget _pet(GameController c, Offset feet, double width) {
    final pet = c.state.pet!;
    final h = width * 1.05;
    return Positioned(
      left: feet.dx - h / 2,
      top: feet.dy - h * 0.94,
      width: h,
      height: h,
      child: Semantics(
        button: true,
        label: '${pet.name}, here with you',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            c.audio.play('pet_chirp', volume: 0.6);
            if (!_rm) _hop.forward(from: 0);
          },
          child: ExcludeSemantics(
            child: AnimatedBuilder(
              animation: _hop,
              builder: (_, child) => Transform.translate(offset: Offset(0, -18 * math.sin(math.pi * _hop.value)), child: child),
              child: Align(
                alignment: Alignment.bottomCenter,
                child: PetSprite(stage: pet.stage, palette: pet.paletteId, expr: 'happy', overlays: pet.equipped.values.toList(), height: h),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A gold "!" over a creature that a trail job is waiting on.
class _JobMarker extends StatelessWidget {
  const _JobMarker({required this.idle, required this.rm});
  final Animation<double> idle;
  final bool rm;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: idle,
        builder: (_, child) => Transform.translate(offset: Offset(0, rm ? 0 : -5 * math.sin(idle.value * 4 * math.pi).abs()), child: child),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2.5),
            gradient: const RadialGradient(center: Alignment(-0.2, -0.3), colors: [Color(0xFFFFF0B0), EvochiColor.primary]),
            boxShadow: const [
              BoxShadow(color: Color(0x99FFD86E), blurRadius: 16, spreadRadius: 2),
              BoxShadow(color: EvochiColor.primaryShadow, offset: Offset(0, 3)),
            ],
          ),
          child: Text('!', style: EvochiText.pageTitle.copyWith(fontSize: 24, height: 1, color: EvochiColor.ink)),
        ),
      );
}

/// A friend's name under its feet.
class _NameTag extends StatelessWidget {
  const _NameTag(this.name);
  final String name;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 3),
        decoration: BoxDecoration(
          color: const Color(0xCC2A1D10),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0x80F3D9A6), width: 1),
        ),
        child: Text(name, style: EvochiText.tag.copyWith(color: const Color(0xFFFFF3DC), fontSize: 12)),
      );
}

/// At the screen's edge: something you'd want to see is off to that side.
class _EdgeHint extends StatelessWidget {
  const _EdgeHint({required this.left, required this.icon, required this.label, required this.onTap});
  final bool left;
  final String icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Look ${left ? 'left' : 'right'}: $label',
        child: GestureDetector(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Container(
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: const Color(0xE62A1D10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: EvochiColor.primary, width: 2),
                boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 6, offset: Offset(0, 2))],
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (left) const Icon(Icons.chevron_left_rounded, color: Color(0xFFFFE6A8), size: 22),
                VoxelIcon(icon, size: 28),
                if (!left) const Icon(Icons.chevron_right_rounded, color: Color(0xFFFFE6A8), size: 22),
              ]),
            ),
          ),
        ),
      );
}

/// The dock: where you are, and the one thing to do here now (the job, else a clue). The friends who
/// live here are in the scene itself.
class _Dock extends StatelessWidget {
  const _Dock({required this.text, required this.quest, required this.target, required this.clue});
  final String text;
  final q.StoryQuestView? quest;
  final tr.EncounterDef? target;
  final tr.DiscoveryView? clue;

  @override
  Widget build(BuildContext context) {
    final v = quest;
    final e = target;
    final cl = clue;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: Kit.parchment(radius: 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(text, maxLines: 2, overflow: TextOverflow.ellipsis, style: EvochiText.bodyText.copyWith(height: 1.35)),
        if (v != null && e != null) ...[
          const SizedBox(height: 10),
          EvochiButton(
            label: '${e.goal == 'befriend' ? 'Meet' : 'Help'} ${tr.creatureDefs[e.creature]!.name}',
            semanticLabel: 'Trail job, ${v.title}: ${e.goal == 'befriend' ? 'meet' : 'help'} ${tr.creatureDefs[e.creature]!.name}',
            tone: e.goal == 'befriend' ? ButtonTone.green : ButtonTone.gold,
            icon: CreatureFace(e.creature, size: 30),
            onPressed: () => openPrep(context, v.id),
          ),
        ] else if (v != null) ...[
          const SizedBox(height: 10),
          TapCard(
            label: '${v.title}. ${nextText(v)}',
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            onTap: () => showStoryQuest(context, v.id),
            child: Row(children: [
              const VoxelIcon('trail_badge', size: 30),
              const SizedBox(width: 8),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Trail job · ${v.title}', maxLines: 1, overflow: TextOverflow.ellipsis, style: EvochiText.caption.copyWith(fontSize: 12)),
                  Text(nextText(v), maxLines: 1, overflow: TextOverflow.ellipsis, style: EvochiText.cardTitle.copyWith(fontSize: 14)),
                ]),
              ),
              const Icon(Icons.chevron_right_rounded, color: EvochiColor.textHelper),
            ]),
          ),
        ] else if (cl != null) ...[
          const SizedBox(height: 10),
          EvochiButton(
            label: 'Inspect the glint',
            semanticLabel: 'Inspect: ${cl.title}',
            tone: ButtonTone.gold,
            icon: const SparkIcon(size: 24),
            onPressed: () => inspectClue(context, cl.id),
          ),
        ],
      ]),
    );
  }
}
