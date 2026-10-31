// The onboarding beats after the cold open, on the cinematic plates (tools/art/cine_scenes.py):
//
//   EggPickScreen   Mira's nest: six unhatched eggs in the Glasshouse at evening (the nest plate without eggs
//                   plus each egg as its own lit sprite), tap one and it lifts in a glow of its colour, with a
//                   glimpse of the Elder it becomes; "This one?" creates the pet (named later, after the hatch).
//   HatchScreen     the egg in the Home nest: real steps since the egg was chosen crack it (the four crack
//                   sprites), a ring shows the way to 150, "Hatch now" is never far; the hatch pops the shell
//                   into shards and gold motes, the Eggling tumbles in with its hatch act, then the name is asked
//                   while it watches, the name flies in Lumen to Alder's map and one trail near Sunlit Village
//                   lights up: "One path lit. Many more to go."
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
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/services/asset_manifest.dart';
import '../../core/utils/ids.dart';
import '../../game/engine.dart' as g;
import '../../game/story/story.dart' show freshDays;
import '../shared/scene_scaffold.dart';
import '../shared/scene_view.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import 'cinematic_player.dart';

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
    super.dispose();
  }

  void _pick(String id) {
    final c = context.read<GameController>();
    c.mutate((s) => s.onboarding.draftPalette = id);
    c.audio.play('ui_tap', volume: 0.5);
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
        CinePlate('nest_empty', alignment: const Alignment(0, 0.2), onMissing: Image.asset(AssetManifest.instance!.thumb('meadow'), fit: BoxFit.cover)),
        // the eggs, each its own sprite lit in place; the picked one lifts and glows
        LayoutBuilder(builder: (ctx, box) {
          final m = _meta;
          if (m == null) return const SizedBox.shrink();
          // the plate is cover-fitted, aligned at (0, 0.2): where each plate point lands on the screen
          final pw = (m['w'] as num).toDouble(), ph = (m['h'] as num).toDouble();
          final k = math.max(box.maxWidth / pw, box.maxHeight / ph);
          final dx = (box.maxWidth - pw * k) / 2;
          final dy = (box.maxHeight - ph * k) * 0.6;
          return AnimatedBuilder(
            animation: _lift,
            builder: (_, __) => Stack(children: [
              for (final p in palettes)
                Positioned(
                  left: dx,
                  top: dy - (p.id == picked ? 26 * Curves.easeOutBack.transform(_lift.value) : 0),
                  width: pw * k,
                  height: ph * k,
                  child: IgnorePointer(
                    child: Opacity(opacity: picked == null || p.id == picked ? 1 : 0.78, child: CinePlate('nest_egg_${p.id}', fit: BoxFit.fill)),
                  ),
                ),
              if (picked != null && _slot(picked) != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(painter: _GlowPainter(Offset(dx + _slot(picked)!.dx * pw * k, dy + _slot(picked)!.dy * ph * k - 26 * _lift.value), _paletteGlow(picked), _lift.value)),
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
            ]),
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
  _GlowPainter(this.at, this.color, this.k);
  final Offset at;
  final Color color;
  final double k;
  @override
  void paint(Canvas c, Size size) {
    final r = 70.0 + 30 * k;
    c.drawCircle(at.translate(0, -30), r, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(at.translate(0, -30), r, [color.withValues(alpha: 0.55 * k), color.withValues(alpha: 0)]));
  }

  @override
  bool shouldRepaint(_GlowPainter o) => o.at != at || o.k != k || o.color != color;
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
  double _t = 0;
  double _burstAt = 0;
  double _mapAt = 0;
  Timer? _hatchNow;
  bool _hatchNowReady = false;
  late final TextEditingController _name = TextEditingController();
  String? _err;
  CineTimeline? _tl;
  ui.Image? _mapPlate;
  ui.Image? _mapLit;

  @override
  void initState() {
    super.initState();
    LumenPrint.warm();
    _ticker = createTicker((d) {
      if (!mounted) return;
      setState(() => _t = d.inMicroseconds / 1e6);
    })..start();
    final c = context.read<GameController>();
    final noSteps = c.state.steps.connection == 'none';
    final reduce = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _hatchNow = Timer(Duration(seconds: reduce ? 1 : (noSteps ? 4 : 75)), () {
      if (mounted) setState(() => _hatchNowReady = true);
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
    final c = context.read<GameController>();
    c.audio.play('cine_footstep', volume: 0.6); // the footstep from the opening
    setState(() {
      _phase = _HatchPhase.bursting;
      _burstAt = _t;
    });
    Timer(const Duration(milliseconds: 650), () {
      if (!mounted) return;
      setState(() => _phase = _HatchPhase.hatched);
      _scene.react('hatch'); // its signature, the first thing it ever does
      c.audio.play('evolve_fanfare', volume: 0.5);
      Timer(const Duration(milliseconds: 1600), () {
        if (mounted) setState(() => _phase = _HatchPhase.naming);
      });
    });
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
        SceneScaffold(
          controller: _scene,
          onPetTap: () => _scene.react('pet'),
          petLabel: p.name,
          headerAllowance: 40,
          config: (gy) => SceneConfig(
            habitat: 'meadow',
            decor: c.state.placements,
            focus: Offset(0.5, gy),
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
                      t: _t,
                      burstAt: _burstAt,
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
        if (mapping) Positioned.fill(child: _MapBeat(tl: _tl, plate: _mapPlate, lit: _mapLit, t: _t - _mapAt, name: p.name)),
        if (_phase == _HatchPhase.done)
          Positioned(
            left: 16,
            right: 16,
            bottom: 40,
            child: SafeArea(
              top: false,
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
      ]),
    );
  }

  Widget _panel(GameController c, String name, int steps, bool reduce) {
    switch (_phase) {
      case _HatchPhase.waiting:
      case _HatchPhase.bursting:
        final left = math.max(0, hatchSteps - steps);
        return GameCard(
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
        );
      case _HatchPhase.hatched:
        return GameCard(
          padding: const EdgeInsets.all(16),
          child: Column(children: [
            Semantics(liveRegion: true, child: const Text('It hatched!', style: EvochiText.pageTitle, textAlign: TextAlign.center)),
            const SizedBox(height: 6),
            const Text('It blinks at you.', textAlign: TextAlign.center, style: EvochiText.bodyText),
          ]),
        );
      case _HatchPhase.naming:
        return GameCard(
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
        );
      case _HatchPhase.mapping:
      case _HatchPhase.done:
        return const SizedBox.shrink();
    }
  }
}

/// The egg over the nest (the crack-stage sprite from the pack, else a painted egg), the step ring under it, and
/// the burst: shell pieces flung out and gold motes rising.
class _EggPainter extends CustomPainter {
  _EggPainter({required this.palette, required this.stage, required this.phase, required this.t, required this.burstAt, required this.pet, required this.progress});
  final String palette;
  final int stage;
  final _HatchPhase phase;
  final double t;
  final double burstAt;
  final Rect pet;
  final double progress;

  static final Map<String, ui.Image?> _sprites = {};
  static final Set<String> _loading = {};

  ui.Image? _sprite(String key) {
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
    final ground = Offset(pet.center.dx, pet.bottom);
    final h = pet.height * 0.92;
    final bob = math.sin(t * 2.6) * (2 + 6 * progress);
    final rock = math.sin(t * 3.1) * (0.02 + 0.06 * progress) * (stage >= 1 ? 1 : 0.5);
    if (phase == _HatchPhase.waiting || phase == _HatchPhase.bursting) {
      // the ring: the way to 150 steps, filling clockwise
      final rr = Rect.fromCenter(center: ground.translate(0, -h * 0.42), width: h * 1.25, height: h * 1.25);
      c.drawArc(rr, -math.pi / 2, 2 * math.pi, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..color = const Color(0x66FFF0DE));
      c.drawArc(rr, -math.pi / 2, 2 * math.pi * progress, false, Paint()..style = PaintingStyle.stroke..strokeWidth = 5..strokeCap = StrokeCap.round..color = const Color(0xFFF4B84E));
    }
    if (phase == _HatchPhase.waiting || (phase == _HatchPhase.bursting && t - burstAt < 0.25)) {
      c.save();
      c.translate(ground.dx, ground.dy);
      c.rotate(rock);
      c.translate(0, bob * 0.2);
      final im = _sprite('egg_${palette}_$stage');
      if (im != null) {
        final w = h * im.width / im.height;
        c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), Rect.fromLTWH(-w / 2, -h, w, h), Paint()..filterQuality = FilterQuality.medium);
      } else {
        _plainEgg(c, h, stage);
      }
      c.restore();
      if (stage >= 2) {
        final k = 0.35 + 0.25 * math.sin(t * 4);
        c.drawCircle(ground.translate(0, -h * 0.45), h * 0.7, Paint()..blendMode = BlendMode.plus..shader = ui.Gradient.radial(ground.translate(0, -h * 0.45), h * 0.7, [const Color(0xFFFFD56A).withValues(alpha: 0.35 * k * (stage - 1)), const Color(0x00FFD56A)]));
      }
    }
    if (phase == _HatchPhase.bursting || (phase == _HatchPhase.hatched && t - burstAt < 2.2)) {
      final u = t - burstAt;
      // a flash, then the shards and the motes
      if (u < 0.35) {
        c.drawCircle(ground.translate(0, -h * 0.45), h * (0.6 + u * 2.5), Paint()..blendMode = BlendMode.plus..color = const Color(0xFFFFF0C0).withValues(alpha: (1 - u / 0.35) * 0.9));
      }
      final rnd = math.Random(7);
      final shardCol = palette == 'obsidian' ? const Color(0xFF3E414B) : const Color(0xFFFFF0DE);
      for (var i = 0; i < 14; i++) {
        final a = rnd.nextDouble() * math.pi * 2;
        final sp = 120 + rnd.nextDouble() * 220;
        final x = ground.dx + math.cos(a) * sp * u;
        final y = ground.dy - h * 0.45 + math.sin(a) * sp * u * 0.6 + 260 * u * u;
        final s = h * (0.06 + rnd.nextDouble() * 0.08);
        final alpha = (1 - u / 2.0).clamp(0.0, 1.0);
        c.save();
        c.translate(x, y);
        c.rotate(a + u * 6);
        c.drawRect(Rect.fromCenter(center: Offset.zero, width: s, height: s * 0.7), Paint()..color = shardCol.withValues(alpha: alpha));
        c.restore();
      }
      for (var i = 0; i < 22; i++) {
        final a = rnd.nextDouble() * math.pi * 2;
        final sp = 40 + rnd.nextDouble() * 120;
        final x = ground.dx + math.cos(a) * sp * u + math.sin(u * 5 + i) * 6;
        final y = ground.dy - h * 0.45 - (30 + rnd.nextDouble() * 160) * u;
        final alpha = (1 - u / 2.2).clamp(0.0, 1.0);
        c.drawCircle(Offset(x, y), 3 + rnd.nextDouble() * 4, Paint()..blendMode = BlendMode.plus..color = const Color(0xFFFFC24E).withValues(alpha: alpha * 0.9));
      }
    }
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
    // the print lands, then the trail lights from it
    final p = ((t - 1.6) / 1.6).clamp(0.0, 1.0);
    if (t > 1.4) {
      LumenPrint.paint(c, land, size.height * 0.05, strength: ((t - 1.4) / 0.3).clamp(0.0, 1.0) * (0.85 + 0.15 * math.sin(t * 6)));
    }
    final li = lit;
    if (p > 0 && li != null) {
      final trail = tl_.trail('map_lit', 'grove');
      c.save();
      c.translate(-g.origin.dx * g.scale, -g.origin.dy * g.scale);
      c.scale(g.scale);
      final plateRect = Rect.fromLTWH(0, 0, li.width.toDouble(), li.height.toDouble());
      c.saveLayer(plateRect, Paint());
      c.drawImage(li, Offset.zero, Paint());
      const width = 28.0;
      c.drawPath(
          TrailReveal.path([trail], p),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = width
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..blendMode = BlendMode.dstIn
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, width * 0.3)
            ..color = Colors.white);
      c.restore();
      c.restore();
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
