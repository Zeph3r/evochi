// The onboarding beats after the cold open, on the cinematic plates (tools/art/cine_scenes.py):
//
//   EggPickScreen   Mira's nest: six unhatched eggs in the Glasshouse at evening (the nest plate without eggs
//                   plus each egg as its own lit sprite), tap one and it lifts in a glow of its colour, with a
//                   glimpse of the Elder it becomes; "This one?" creates the pet (named later, after the hatch).
//   HatchScreen     the egg in the Home nest: real steps since the egg was chosen crack it (the four crack
//                   sprites), a ring shows the way to 150, "Hatch now" is never far; the hatch plays the beats
//                   in assets/config/hatch.json (hatch_timeline.dart): quiet, shakes, cracks pouring light, the
//                   shell breaking apart with its affinity's burst, the Eggling springing out, looking round and
//                   doing its personality's hatch act; then the name is asked while it watches, the name flies
//                   in Lumen to Alder's map and one trail near Sunlit Village lights up: "One path lit. Many
//                   more to go."
//
// Both fall back to the game's own sprites when a plate is missing from the pack, so a build without the
// cinematic art still plays through.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/motion.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/services/asset_manifest.dart';
import '../../core/services/haptics.dart';
import '../../core/utils/ids.dart';
import '../../game/engine.dart' as g;
import '../../game/story/story.dart' show freshDays;
import '../shared/scene_scaffold.dart';
import '../shared/scene_view.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import 'cinematic_player.dart';
import 'hatch_timeline.dart';
import 'posed_plate.dart';

const hatchSteps = 150;
const _placeholderName = 'Eggling';

// ------------------------------------------------------------------------------------------- the egg pick ----
class EggPickScreen extends StatefulWidget {
  const EggPickScreen({super.key});
  @override
  State<EggPickScreen> createState() => _EggPickScreenState();
}

class _EggPickScreenState extends State<EggPickScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _meta;
  late final AnimationController _lift = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  String? _picked;
  bool _teaser = false;
  final _mira = PoseController();
  bool _fallback = false; // no cinematic pack: a plain row of eggs to pick from

  @override
  void initState() {
    super.initState();
    LumenPrint.warm();
    CineTimeline.load().then((tl) {
      if (!mounted) return;
      final m = tl.plateMeta('nest_empty');
      setState(() {
        _meta = m.isEmpty ? null : m;
        _fallback = m.isEmpty;
      });
    }).catchError((_) {
      if (mounted) setState(() => _fallback = true);
    });
  }

  @override
  void dispose() {
    _lift.dispose();
    _mira.dispose();
    super.dispose();
  }

  void _pick(String id) {
    if (id == _picked) return; // a second tap on the egg already in hand changes nothing
    final c = context.read<GameController>();
    c.mutate((s) => s.onboarding.draftPalette = id);
    c.audio.play('ui_tap', volume: 0.5);
    c.audio.buzz(Haptic.tick);
    _mira.play('look');
    setState(() {
      _picked = id;
      _teaser = false;
    });
    _lift.forward(from: 0);
    Timer(const Duration(milliseconds: 900), () {
      if (mounted && _picked == id) setState(() => _teaser = true);
    });
  }

  void _confirm() {
    final c = context.read<GameController>();
    final pal = _picked ?? c.state.onboarding.draftPalette;
    var req = c.state.onboarding.requestId;
    if (req == null) {
      req = newId('create');
      c.mutate((s) => s.onboarding.requestId = req);
    }
    final r = c.run((s, n) => g.createPet(s, name: _placeholderName, paletteId: pal, requestId: req!, now: n));
    if (r.ok) {
      c.audio.play('reward_chime');
      c.analytics.track('pet_created', {'palette': pal, 'via': 'nest'});
    }
  }

  /// where an egg sits on the nest plate, as a fraction of the plate (from cine.json's slot anchors)
  Offset? _slot(String id) {
    final m = _meta;
    if (m == null) return null;
    final a = (m['anchors'] as Map<String, dynamic>?)?[id] as List?;
    if (a == null) return null;
    return Offset((a[0] as num).toDouble() / (m['w'] as num).toDouble(), (a[1] as num).toDouble() / (m['h'] as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final again = c.state.pastPets.isNotEmpty;
    final picked = _picked;
    final info = picked == null ? null : palettes.firstWhere((p) => p.id == picked);
    return Scaffold(
      backgroundColor: const Color(0xFF1A2432),
      body: Stack(fit: StackFit.expand, children: [
        // the Glasshouse at evening, the nest without its eggs
        // (Mira in motion beside it: she blinks, looks down at the eggs, and at the one you pick)
        PosedPlate('nest_empty', alignment: const Alignment(0, 0.2), controller: _mira, onMissing: Image.asset(AssetManifest.instance!.thumb('meadow'), fit: BoxFit.cover)),
        // the eggs, each its own sprite lit in place; the picked one lifts and glows
        LayoutBuilder(builder: (ctx, box) {
          final m = _meta;
          if (m == null) return const SizedBox.shrink();
          // the plate is cover-fitted, aligned at (0, 0.2): where each plate point lands on the screen
          final pw = (m['w'] as num).toDouble(), ph = (m['h'] as num).toDouble();
          final k = math.max(box.maxWidth / pw, box.maxHeight / ph);
          final dx = (box.maxWidth - pw * k) / 2;
          final dy = (box.maxHeight - ph * k) * 0.6;
          final reduce = Motion.reduced(context);
          return AnimatedBuilder(
            animation: _lift,
            builder: (_, __) {
              final v = _lift.value;
              final lift = 26 * (reduce ? Curves.easeOut.transform(v) : Curves.easeOutBack.transform(v));
              // lifted, it rocks on its base a couple of times and settles
              final rock = reduce ? 0.0 : 0.075 * math.sin(v * math.pi * 3.2) * math.pow(1 - v, 1.4);
              return Stack(children: [
              for (final p in palettes)
                Positioned(
                  left: dx,
                  top: dy - (p.id == picked ? lift : 0),
                  width: pw * k,
                  height: ph * k,
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: picked == null || p.id == picked ? 1 : 0.78,
                      child: p.id == picked && rock != 0 && _slot(p.id) != null
                          ? Transform(
                              transform: Matrix4.rotationZ(rock),
                              origin: Offset(_slot(p.id)!.dx * pw * k, _slot(p.id)!.dy * ph * k + 2),
                              child: CinePlate('nest_egg_${p.id}', fit: BoxFit.fill),
                            )
                          : CinePlate('nest_egg_${p.id}', fit: BoxFit.fill),
                    ),
                  ),
                ),
              if (picked != null && _slot(picked) != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _GlowPainter(Offset(dx + _slot(picked)!.dx * pw * k, dy + _slot(picked)!.dy * ph * k), lift, _paletteGlow(picked), v)),
                  ),
                ),
              // tap targets over each egg
              for (final p in palettes)
                if (_slot(p.id) != null)
                  Positioned(
                    left: dx + _slot(p.id)!.dx * pw * k - 46,
                    top: dy + _slot(p.id)!.dy * ph * k - 70,
                    width: 92,
                    height: 110,
                    child: Semantics(
                      button: true,
                      selected: p.id == picked,
                      label: '${p.label} egg',
                      child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: () => _pick(p.id)),
                    ),
                  ),
              ]);
            },
          );
        }),
        // Mira's line and the header
        SafeArea(
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (!again) BackSquareButton(onTap: () => c.mutate((s) => s.player = null)) else const SizedBox(width: 46),
                const Expanded(child: SpeechCard(name: 'Mira', text: "I've been keeping these warm. One of them has been waiting for you.")),
                const SizedBox(width: 46),
              ]),
            ),
            const Spacer(),
            if (_fallback)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: GameCard(
                  padding: const EdgeInsets.all(10),
                  child: Row(children: [
                    for (final p in palettes)
                      Expanded(
                        child: Semantics(
                          button: true,
                          selected: p.id == picked,
                          label: '${p.label} egg',
                          child: GestureDetector(
                            onTap: () => _pick(p.id),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: p.id == picked ? const Color(0xFFFFF4D6) : const Color(0xFFFBF2E6),
                                border: Border.all(color: p.id == picked ? const Color(0xFFF2BE55) : const Color(0xFFE6D3BD), width: 2),
                              ),
                              child: PetSprite(stage: 1, palette: p.id, height: 42),
                            ),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
            // the Elder glimpse and the confirm
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 350),
                child: picked == null
                    ? const _HintCard(key: ValueKey('hint'), text: 'Tap an egg to pick it up.')
                    : GameCard(
                        key: ValueKey(picked),
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          // the Elder it becomes, a wide panel that opens above the egg once it has lifted
                          AnimatedSize(
                            duration: const Duration(milliseconds: 380),
                            curve: Curves.easeOutCubic,
                            child: _teaser
                                ? Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(height: 150, child: _ElderGlimpse(palette: picked)))
                                : const SizedBox(width: double.infinity),
                          ),
                          Row(children: [
                            SizedBox(width: 96, height: 96, child: CinePlate('egg_${picked}_0', fit: BoxFit.contain, onMissing: PetSprite(stage: 1, palette: picked, height: 80))),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${info!.label} egg', style: EvochiText.section),
                                const SizedBox(height: 4),
                                Text(_teaser ? _teaserLine(picked) : 'It rocks gently in your hands.', style: EvochiText.bodyText),
                              ]),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          EvochiButton(label: 'This one', large: true, icon: const VoxelIcon('paw', size: 28), onPressed: _confirm),
                        ]),
                      ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

String _teaserLine(String pal) {
  switch (pal) {
    case 'forest':
      return 'One day it will grow over blocked paths.';
    case 'coral':
      return 'One day it will light the ancient torches.';
    case 'ocean':
      return 'One day it will cross any water.';
    case 'obsidian':
      return 'One day it will open the sealed caves.';
    case 'amethyst':
      return 'One day it will reveal the hidden ruins.';
    default:
      return 'One day it will walk the old trails.';
  }
}

Color _paletteGlow(String pal) {
  switch (pal) {
    case 'forest':
      return const Color(0xFF78B55B);
    case 'coral':
      return const Color(0xFFDB745B);
    case 'ocean':
      return const Color(0xFF4C9BCC);
    case 'obsidian':
      return const Color(0xFFDD6A5B);
    case 'amethyst':
      return const Color(0xFF9975C9);
    default:
      return const Color(0xFFF4B84E);
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.at, this.lift, this.color, this.k);
  final Offset at; // where the egg sits in the nest
  final double lift; // how far it has risen
  final Color color;
  final double k;
  @override
  void paint(Canvas c, Size size) {
    // its own light around it, and the same light pooled on the straw where it sat
    final egg = at.translate(0, -30 - lift);
    final r = 70.0 + 30 * k;
    c.drawCircle(egg, r, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(egg, r, [color.withValues(alpha: 0.55 * k), color.withValues(alpha: 0)]));
    final pool = at.translate(0, 2);
    c.save();
    c.translate(pool.dx, pool.dy);
    c.scale(1, 0.32);
    c.drawCircle(Offset.zero, 62, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(Offset.zero, 62, [color.withValues(alpha: 0.42 * k), color.withValues(alpha: 0)]));
    c.restore();
  }
  @override
  bool shouldRepaint(_GlowPainter o) => o.at != at || o.lift != lift || o.k != k || o.color != color;
}

/// Three seconds of the Elder it becomes: the orbit frames from the cinematic pack when they are there, else
/// the Elder's hero sprite.
class _ElderGlimpse extends StatefulWidget {
  const _ElderGlimpse({required this.palette});
  final String palette;
  @override
  State<_ElderGlimpse> createState() => _ElderGlimpseState();
}

class _ElderGlimpseState extends State<_ElderGlimpse> with SingleTickerProviderStateMixin {
  final List<ui.Image> _frames = [];
  bool _missing = false;
  late final Ticker _ticker;
  double _t = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => setState(() => _t = d.inMicroseconds / 1e6))..start();
    _load();
  }

  Future<void> _load() async {
    for (var i = 0; i < 36; i++) {
      try {
        final im = await AtlasCache.load('$cineDir/elder_${widget.palette}_${i.toString().padLeft(2, '0')}.webp');
        if (!mounted) return;
        setState(() => _frames.add(im));
      } catch (_) {
        if (i == 0 && mounted) setState(() => _missing = true);
        break;
      }
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frames.isEmpty) {
      return _missing ? PetSprite(stage: 3, palette: widget.palette, height: 90) : const SizedBox.shrink();
    }
    final im = _frames[((_t * 12) % _frames.length).floor()];
    // the ring of light runs off the frame's sides as the Elder turns side-on: fade the frame's own edges
    return Center(
      child: AspectRatio(
        aspectRatio: im.width / im.height,
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (r) => const LinearGradient(
            colors: [Color(0x00FFFFFF), Color(0xFFFFFFFF), Color(0xFFFFFFFF), Color(0x00FFFFFF)],
            stops: [0.0, 0.1, 0.9, 1.0],
          ).createShader(r),
          child: RawImage(image: im, fit: BoxFit.fill),
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard({super.key, required this.text});
  final String text;
  @override
  Widget build(BuildContext context) => GameCard(padding: const EdgeInsets.all(14), child: Text(text, style: EvochiText.bodyText, textAlign: TextAlign.center));
}

// ---------------------------------------------------------------------------------------------- the hatch ----
enum _HatchPhase { waiting, bursting, hatched, naming, mapping, done }

class HatchScreen extends StatefulWidget {
  const HatchScreen({super.key});
  @override
  State<HatchScreen> createState() => _HatchScreenState();
}

class _HatchScreenState extends State<HatchScreen> with SingleTickerProviderStateMixin {
  final _scene = SceneController();
  _HatchPhase _phase = _HatchPhase.waiting;
  late final Ticker _ticker;
  // the screen's clock: the egg, the burst, the camera nudge and the map beat repaint from it, so the screen
  // itself only rebuilds when something changes (a phase, a step, a card)
  final _clock = ValueNotifier<double>(0);
  double get _t => _clock.value;
  double _burstAt = 0; // when the hatch began (the tap)
  double _mapAt = 0;
  Timer? _hatchNow;
  bool _hatchNowReady = false;
  late final TextEditingController _name = TextEditingController();
  String? _err;
  CineTimeline? _tl;
  ui.Image? _mapPlate;
  ui.Image? _mapLit;
  HatchPlan _plan = HatchPlan.fallback;
  final Set<int> _fired = {};
  bool _reduce = false;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    LumenPrint.warm();
    _ticker = createTicker((d) {
      if (!mounted) return;
      _clock.value = d.inMicroseconds / 1e6;
      if (_phase == _HatchPhase.bursting || _phase == _HatchPhase.hatched) {
        _beats();
        // the camera push: the scene (and the egg with it) is laid out again at the new zoom
        final z = _zoomAt(_t);
        if (z != _zoom) setState(() => _zoom = z);
      }
    })..start();
    final c = context.read<GameController>();
    final noSteps = c.state.steps.connection == 'none';
    _reduce = Motion.reducedNow(context);
    _hatchNow = Timer(Duration(seconds: _reduce ? 1 : (noSteps ? 4 : 75)), () {
      if (mounted) setState(() => _hatchNowReady = true);
    });
    HatchPlan.load().then((p) {
      if (mounted) setState(() => _plan = p);
    });
    CineTimeline.load().then((tl) async {
      _tl = tl;
      try {
        _mapPlate = await AtlasCache.load('$cineDir/map_hollow.webp');
        _mapLit = await AtlasCache.load('$cineDir/map_lit.webp');
      } catch (_) {}
      if (mounted) setState(() {});
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _hatchNow?.cancel();
    _name.dispose();
    _clock.dispose();
    super.dispose();
  }

  int _stepsSince(GameController c) {
    final p = c.state.pet;
    if (p == null) return 0;
    final zone = c.state.player?.timezone ?? c.state.tzHint;
    var n = 0;
    for (final d in freshDays(c.state, p.createdAt, zone).values) {
      n += d.steps;
    }
    return n;
  }

  int _crackStage(int steps) {
    if (steps >= hatchSteps) return 3;
    if (steps >= hatchSteps * 0.6) return 2;
    if (steps >= hatchSteps * 0.25) return 1;
    return 0;
  }

  void _hatch() {
    if (_phase != _HatchPhase.waiting) return;
    _reduce = Motion.reducedNow(context);
    setState(() {
      _phase = _HatchPhase.bursting;
      _burstAt = _t;
    });
    _beats();
  }

  /// Plays the hatch's beats as their times come: sounds, feels, the creature's reactions, and the name card at
  /// the end.
  void _beats() {
    final u = _t - _burstAt;
    final c = context.read<GameController>();
    for (var i = 0; i < _plan.beats.length; i++) {
      final b = _plan.beats[i];
      if (b.t > u) break;
      if (!_fired.add(i)) continue;
      // back from the background halfway through: what it missed happens, silently
      final late = u - b.t > 0.5;
      if (b.sfx != null && !late) c.audio.play(b.sfx!, volume: b.vol);
      if (b.buzz != null && !late) {
        final feel = Haptic.values.asNameMap()[b.buzz];
        if (feel != null) c.audio.buzz(feel);
      }
      switch (b.react) {
        case 'emerge':
          // out of the shell: from here the scene draws it, crouched small, springing up and landing
          _scene.react('emerge');
          setState(() => _phase = _HatchPhase.hatched);
        case null:
          break;
        default:
          _scene.react(b.react!); // look, then its personality's own hatch act
      }
    }
    if (_phase == _HatchPhase.hatched && u >= _plan.naming) setState(() => _phase = _HatchPhase.naming);
    if (_phase == _HatchPhase.bursting && u >= _plan.burst + 0.6) setState(() => _phase = _HatchPhase.hatched); // a plan with no emerge beat
  }

  /// The camera through the hatch: it pushes in slowly on the egg while it shakes and cracks, holds through the
  /// burst, and eases back out as the creature looks round, before the name card. The scene keeps the egg's
  /// ground point where it is, so the push is on the egg.
  double _zoomAt(double t) {
    if (_reduce) return 1;
    final u = t - _burstAt;
    final b = _plan.burst;
    if (u <= 0) return 1;
    if (u < b) return 1 + 0.16 * Curves.easeInOut.transform(u / b);
    if (u < b + 0.5) return 1.16;
    final back = ((u - b - 0.5) / math.max(0.3, _plan.naming - b - 0.7)).clamp(0.0, 1.0);
    return 1 + 0.16 * (1 - Curves.easeInOut.transform(back));
  }

  /// A small knock to the whole scene as the shell breaks, dying away in a few tenths of a second.
  Offset _impulse(double t) {
    if (_reduce || _phase.index > _HatchPhase.hatched.index) return Offset.zero;
    final u = t - _burstAt - _plan.burst;
    if (u < 0 || u > 0.45) return Offset.zero;
    final k = math.exp(-u * 9) * 7;
    return Offset(math.sin(u * 55) * k, math.cos(u * 47) * k * 0.6);
  }

  void _confirmName() {
    final c = context.read<GameController>();
    final v = g.validateName(_name.text);
    if (!v.ok) {
      setState(() => _err = v.error);
      return;
    }
    c.run((s, n) => g.renamePet(s, v.name));
    c.audio.play('cine_lumen_rise', volume: 0.5); // the name flies in Lumen to the map and lights the grove trail
    FocusScope.of(context).unfocus();
    setState(() {
      _phase = _HatchPhase.mapping;
      _mapAt = _t;
    });
    Timer(const Duration(milliseconds: 4200), () {
      if (mounted) setState(() => _phase = _HatchPhase.done);
    });
  }

  void _finish() {
    final c = context.read<GameController>();
    c.run((s, n) => g.setOnboardingStep(s, 'done'));
    c.analytics.track('onboarding_completed');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final p = c.state.pet!;
    final reduce = MediaQuery.of(context).disableAnimations;
    final steps = _stepsSince(c);
    final stage = _crackStage(steps);
    final showPet = _phase.index >= _HatchPhase.hatched.index;
    final mapping = _phase == _HatchPhase.mapping || _phase == _HatchPhase.done;
    return Scaffold(
      body: Stack(fit: StackFit.expand, children: [
        ValueListenableBuilder<double>(
          valueListenable: _clock,
          // always the same Transform (offset zero at rest), so the scene below is never rebuilt from scratch
          builder: (_, t, child) => Transform.translate(offset: _impulse(t), child: child),
          child: SceneScaffold(
            controller: _scene,
            onPetTap: () => _scene.react('pet'),
            petLabel: p.name,
            headerAllowance: 40,
            config: (gy) => SceneConfig(
              habitat: 'meadow',
              decor: c.state.placements,
              focus: Offset(0.5, gy),
              zoom: _zoom,
              reducedMotion: reduce,
              pet: PetConfig(stage: p.stage, palette: p.paletteId, personality: p.personality, visible: showPet),
            ),
            // the painter fills the hero (the rect is in its coordinates): a bare CustomPaint would shrink to
            // nothing in the middle and draw the egg half a screen to the right
            heroBuilder: (ctx, rect) => rect == null
                ? const SizedBox.shrink()
                : SizedBox.expand(
                    child: CustomPaint(
                      painter: _EggPainter(
                        palette: p.paletteId,
                        stage: stage,
                        phase: _phase,
                        clock: _clock,
                        start: _burstAt,
                        plan: _plan,
                        reduce: reduce,
                        pet: rect,
                        progress: (steps / hatchSteps).clamp(0.0, 1.0),
                      ),
                    ),
                  ),
            header: const SizedBox(height: 8),
            panel: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
              child: _panel(c, p.name, steps, reduce),
            ),
          ),
        ),
        if (mapping)
          Positioned.fill(
            child: ValueListenableBuilder<double>(
              valueListenable: _clock,
              builder: (_, t, __) => _MapBeat(tl: _tl, plate: _mapPlate, lit: _mapLit, t: t - _mapAt, name: p.name),
            ),
          ),
        if (_phase == _HatchPhase.done)
          Positioned(
            left: 16,
            right: 16,
            bottom: 40,
            child: SafeArea(
              top: false,
              child: Entrance(
                child: GameCard(
                  padding: const EdgeInsets.all(14),
                  child: Column(children: [
                    Text('${p.name} is home.', style: EvochiText.section, textAlign: TextAlign.center),
                    const SizedBox(height: 10),
                    EvochiButton(label: 'Enter the nest', large: true, onPressed: _finish),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  Widget _panel(GameController c, String name, int steps, bool reduce) {
    final left = math.max(0, hatchSteps - steps);
    final waiting = _phase == _HatchPhase.waiting;
    // the waiting card keeps its place (invisible) until the name card comes, so the creature comes out exactly
    // where the egg stood: the scene's ground follows the panel's top
    final wait = IgnorePointer(
      ignoring: !waiting,
      child: AnimatedOpacity(
        opacity: waiting ? 1 : 0,
        duration: Motion.base,
        curve: Motion.exit,
        child: GameCard(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Semantics(liveRegion: true, child: Text(steps >= hatchSteps ? 'It wants out.' : 'Your first $hatchSteps steps will hatch it.', style: EvochiText.pageTitle, textAlign: TextAlign.center)),
            const SizedBox(height: 6),
            Text(
              steps >= hatchSteps
                  ? 'Light is pouring through the shell.'
                  : (c.state.steps.connection == 'none' ? 'Or warm it in your hands: hold the egg.' : 'A walk to the kitchen will do. $left to go.'),
              textAlign: TextAlign.center,
              style: EvochiText.bodyText,
            ),
            const SizedBox(height: 12),
            if (steps >= hatchSteps || _hatchNowReady)
              EvochiButton(label: steps >= hatchSteps ? 'Hatch' : 'Hatch now', large: true, onPressed: _hatch)
            else
              EvochiButton(label: 'Hold the egg', tone: ButtonTone.cream, large: true, onPressed: () {
                c.audio.play('pet_chirp', volume: 0.3);
                setState(() => _hatchNowReady = true);
              }),
          ]),
        ),
      ),
    );
    switch (_phase) {
      case _HatchPhase.waiting:
      case _HatchPhase.bursting:
        return wait;
      case _HatchPhase.hatched:
        return Stack(alignment: Alignment.bottomCenter, children: [
          wait,
          Entrance(
            delay: const Duration(milliseconds: 500),
            child: GameCard(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Semantics(liveRegion: true, child: const Text('It hatched!', style: EvochiText.pageTitle, textAlign: TextAlign.center)),
                  const SizedBox(height: 6),
                  const Text('It blinks at you.', textAlign: TextAlign.center, style: EvochiText.bodyText),
                ]),
              ),
            ),
          ),
        ]);
      case _HatchPhase.naming:
        return Entrance(
          child: GameCard(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const Text('What will you name your Evochi?', style: EvochiText.section, textAlign: TextAlign.center),
              const SizedBox(height: 10),
              TextField(
                controller: _name,
                autofocus: true,
                maxLength: GameConfig.current.nameMax,
                textAlign: TextAlign.center,
                onChanged: (_) {
                  if (_err != null) setState(() => _err = null);
                },
                onSubmitted: (_) => _confirmName(),
                style: EvochiText.number.copyWith(fontSize: 22),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: 'Lumi',
                  errorText: _err,
                  filled: true,
                  fillColor: EvochiColor.inset,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 10),
              EvochiButton(label: 'Confirm', large: true, onPressed: _confirmName),
            ]),
          ),
        );
      case _HatchPhase.mapping:
      case _HatchPhase.done:
        return const SizedBox.shrink();
    }
  }
}

/// The egg over the nest (the crack-stage sprite from the pack, else a painted egg) with the step ring under it,
/// and the hatch through [plan]: it goes quiet as its light gathers, shakes, cracks with light pushing out,
/// then breaks (its own sprite in pieces) in a flash with the Lumen motes and its affinity's burst.
class _EggPainter extends CustomPainter {
  _EggPainter({
    required this.palette,
    required this.stage,
    required this.phase,
    required this.clock,
    required this.start,
    required this.plan,
    required this.reduce,
    required this.pet,
    required this.progress,
  }) : super(repaint: clock);
  final String palette;
  final int stage;
  final _HatchPhase phase;
  final ValueNotifier<double> clock;
  final double start; // when the hatch began
  final HatchPlan plan;
  final bool reduce;
  final Rect pet;
  final double progress;

  static final Map<String, ui.Image?> _sprites = {};
  static final Set<String> _loading = {};

  static ui.Image? _sprite(String key) {
    if (_sprites.containsKey(key)) return _sprites[key];
    if (!_loading.contains(key)) {
      _loading.add(key);
      AtlasCache.load('$cineDir/$key.webp').then((im) {
        _sprites[key] = im;
      }).catchError((_) {
        _sprites[key] = null;
      });
    }
    return null;
  }

  @override
  void paint(Canvas c, Size size) {
    final t = clock.value;
    final hatching = phase != _HatchPhase.waiting;
    final u = hatching ? t - start : -1.0; // seconds into the hatch
    final ground = Offset(pet.center.dx, pet.bottom);
    final h = pet.height * 0.92;
    final st = plan.style(palette);
    // waiting, it bobs and rocks more as it fills; when the hatch starts it goes still for a moment
    final calm = u < 0 ? 1.0 : (1 - u / 0.6).clamp(0.0, 1.0);
    final bob = math.sin(t * 2.6) * (2 + 6 * progress) * calm;
    var rock = math.sin(t * 3.1) * (0.02 + 0.06 * progress) * (stage >= 1 ? 1 : 0.5) * calm;
    if (reduce) rock *= 0.3;
    final sprite = _sprite('egg_${palette}_${math.max(stage, plan.crack(u))}');
    _sprite('egg_${palette}_3'); // the one that breaks, ready before it is needed
    // the ring: the way to 150 steps, filling clockwise; it fades as the hatch begins
    final ringA = u < 0 ? 1.0 : (1 - u / 0.4).clamp(0.0, 1.0);
    if (ringA > 0) {
      final rr = Rect.fromCenter(center: ground.translate(0, -h * 0.42), width: h * 1.25, height: h * 1.25);
      c.drawArc(rr, -math.pi / 2, 2 * math.pi, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = const Color(0xFFFFF0DE).withValues(alpha: 0.4 * ringA));
      c.drawArc(rr, -math.pi / 2, 2 * math.pi * progress, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round..color = const Color(0xFFF4B84E).withValues(alpha: ringA));
    }
    final centre = ground.translate(0, -h * 0.45);
    if (u < plan.burst) {
      // the light gathering inside, then pushing out through the cracks
      final gather = u < 0 ? 0.0 : Curves.easeIn.transform((u / plan.burst).clamp(0.0, 1.0));
      final rays = u < plan.crackFrom ? 0.0 : ((u - plan.crackFrom) / math.max(0.01, plan.burst - plan.crackFrom)).clamp(0.0, 1.0);
      if (stage >= 2 && u < 0) {
        final k = 0.35 + 0.25 * math.sin(t * 4);
        c.drawCircle(centre, h * 0.7, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(centre, h * 0.7, [const Color(0xFFFFD56A).withValues(alpha: 0.35 * k * (stage - 1)), const Color(0x00FFD56A)]));
      }
      final (srot, shop) = reduce || u < 0 ? (0.0, 0.0) : plan.shake(u);
      c.save();
      c.translate(ground.dx, ground.dy - shop * h);
      c.rotate(rock + srot);
      c.translate(0, bob * 0.2);
      if (sprite != null) {
        final w = h * sprite.width / sprite.height;
        c.drawImageRect(sprite, Rect.fromLTWH(0, 0, sprite.width.toDouble(), sprite.height.toDouble()), Rect.fromLTWH(-w / 2, -h, w, h), Paint()..filterQuality = FilterQuality.medium);
      } else {
        _plainEgg(c, h, math.max(stage, plan.crack(u)));
      }
      c.restore();
      HatchFx.innerLight(c, centre, h, st.glow, gather, reduce ? 0 : rays, t);
      return;
    }
    // the burst
    final b = u - plan.burst;
    if (b > 2.6) return;
    final shell = _sprites['egg_${palette}_3'];
    if (shell != null) {
      final w = h * shell.width / shell.height;
      HatchFx.shell(c, shell, Rect.fromLTWH(ground.dx - w / 2, ground.dy - h, w, h), b, h, reduce: reduce);
    }
    HatchFx.burst(c, ground, h, st, b, n: reduce ? 0.3 : 1, reduce: reduce);
  }

  void _plainEgg(Canvas c, double h, int stage) {
    final shell = Paint()..color = palette == 'obsidian' ? const Color(0xFF3E414B) : const Color(0xFFFFF0DE);
    final path = Path()..addOval(Rect.fromLTWH(-h * 0.38, -h, h * 0.76, h));
    c.drawPath(path, shell);
    if (stage > 0) {
      final crack = Paint()..style = PaintingStyle.stroke..strokeWidth = 2.5..color = const Color(0xFFFFD56A);
      for (var i = 0; i < stage * 2; i++) {
        final p = Path()..moveTo(-h * 0.1 + i * h * 0.12, -h * 0.95);
        p.relativeLineTo(h * 0.05, h * 0.12);
        p.relativeLineTo(-h * 0.06, h * 0.12);
        p.relativeLineTo(h * 0.04, h * 0.14 * stage);
        c.drawPath(p, crack);
      }
    }
  }

  @override
  bool shouldRepaint(_EggPainter o) => true;
}

/// The name flies in Lumen to Alder's map, and the trail by Sunlit Village lights up.
class _MapBeat extends StatelessWidget {
  const _MapBeat({required this.tl, required this.plate, required this.lit, required this.t, required this.name});
  final CineTimeline? tl;
  final ui.Image? plate;
  final ui.Image? lit;
  final double t;
  final String name;

  @override
  Widget build(BuildContext context) {
    final fade = (t / 0.8).clamp(0.0, 1.0);
    return IgnorePointer(
      child: Opacity(
        opacity: fade,
        child: CustomPaint(painter: _MapBeatPainter(tl, plate, lit, t, name)),
      ),
    );
  }
}

class _MapBeatPainter extends CustomPainter {
  _MapBeatPainter(this.tl, this.plate, this.lit, this.t, this.name);
  final CineTimeline? tl;
  final ui.Image? plate;
  final ui.Image? lit;
  final double t;
  final String name;

  @override
  void paint(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF120E18));
    final tl_ = tl;
    final pl = plate;
    if (tl_ == null || pl == null) {
      _caption(c, size, 'One path lit. Many more to go.', (t - 1.5).clamp(0.0, 1.0));
      return;
    }
    final plateSize = Size(pl.width.toDouble(), pl.height.toDouble());
    final centre = tl_.platePoint('map_hollow', 'trail:grove:0.5', plateSize);
    final zoom = 1.9 - 0.2 * (t / 4.0).clamp(0.0, 1.0);
    final g = CineCamera(centre, zoom).fit(size, plateSize);
    final src = Rect.fromLTWH(g.origin.dx, g.origin.dy, size.width / g.scale, size.height / g.scale);
    c.drawImageRect(pl, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
    // the name, written in Lumen, flying down to the trail
    final land = Offset((centre.dx - g.origin.dx) * g.scale, (centre.dy - g.origin.dy) * g.scale);
    final fly = ((t - 0.4) / 1.2).clamp(0.0, 1.0);
    final from = Offset(size.width / 2, size.height * 0.3);
    final at = Offset.lerp(from, land, Curves.easeInOut.transform(fly))!;
    if (fly < 1) {
      final tp = TextPainter(
        text: TextSpan(text: name, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 44 * (1 - 0.6 * fly), color: const Color(0xFFFFE08A), shadows: const [Shadow(color: Color(0xFFF4B84E), blurRadius: 22)])),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
    }
    // where the name lands, a soft flash; then its footsteps walk on along the trail, and the light spreads out
    // both ways from where it touched down
    final trail = tl_.trail('map_lit', 'grove');
    final landed = t - 1.6;
    if (landed > 0 && landed < 0.6) {
      final k = landed / 0.6;
      c.drawCircle(
          land,
          size.height * (0.03 + 0.07 * k),
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(land, size.height * (0.03 + 0.07 * k), [const Color(0xFFFFD27A).withValues(alpha: 0.7 * (1 - k)), const Color(0x00FFC24E)]));
    }
    final p = ((t - 1.75) / 1.7).clamp(0.0, 1.0);
    final li = lit;
    if (p > 0 && li != null) {
      c.save();
      c.translate(-g.origin.dx * g.scale, -g.origin.dy * g.scale);
      c.scale(g.scale);
      final plateRect = Rect.fromLTWH(0, 0, li.width.toDouble(), li.height.toDouble());
      // the mask, then the lit plate kept only inside it: this one trail, not every lit path on the map
      c.saveLayer(plateRect, Paint());
      const width = 28.0;
      final spread = Curves.easeOut.transform(p) * 0.5;
      c.drawPath(
          TrailReveal.span(trail, 0.5 - spread, 0.5 + spread),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, width * 0.3)
            ..color = Colors.white);
      c.drawImage(li, Offset.zero, Paint()..blendMode = BlendMode.srcIn);
      c.restore();
      c.restore();
    }
    if (landed > 0) {
      final sp = [for (final q in trail) Offset((q.dx - g.origin.dx) * g.scale, (q.dy - g.origin.dy) * g.scale)];
      FootTrail.walk(c, sp, 0.5 + 0.3 * (landed / 1.8).clamp(0.0, 1.0),
          from: 0.5, stride: size.height * 0.05, size: size.height * 0.042, squash: 0.8, ember: 0.4, seed: 5);
    }
    _caption(c, size, 'One path lit. Many more to go.', ((t - 2.6) / 0.5).clamp(0.0, 1.0));
  }

  void _caption(Canvas c, Size size, String text, double alpha) {
    if (alpha <= 0) return;
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: size.height * 0.024, color: const Color(0xFFFFF0DE).withValues(alpha: alpha))),
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
    )..layout(maxWidth: size.width * 0.82);
    final x = (size.width - tp.width) / 2, y = size.height * 0.74;
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x - 22, y - 14, tp.width + 44, tp.height + 28), const Radius.circular(18)), Paint()..color = const Color(0xFF140E0A).withValues(alpha: 0.58 * alpha));
    tp.paint(c, Offset(x, y));
  }

  @override
  bool shouldRepaint(_MapBeatPainter o) => true;
}
