// The Garden's helpers and harvests: the helper row in a bed's panel (who tends it, or who could), the
// picker sheet, the little badge on a tended bed, and the harvest burst (the crop popping out of the bed
// in an arc, its count rising; a Golden harvest with a gold flash, a ring of glints and its banner).
// The rules are in game/home/home.dart (garden helpers).

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/game_state.dart';
import '../../core/services/haptics.dart';
import '../../game/home/home.dart' as h;
import '../shared/kit.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';

const _gold = Color(0xFFFFD45A);
const _leaf = Color(0xFF5FA046);

/// A bed's helper: who tends it (and what that does), or who could, or how one is found.
class HelperRow extends StatelessWidget {
  const HelperRow({super.key, required this.plotId});
  final String plotId;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final helper = h.helperOf(s, plotId);
    final plot = s.home.plots[plotId];
    final can = h.helperCandidates(s);
    if (helper != null) {
      final now = plot == null || h.tended(s, plotId);
      final grownUp = !h.canHelp(helper);
      final note = grownUp
          ? 'An Elder now: it finishes this crop, then rests.'
          : now
              ? 'Keeps it watered, +1 every harvest, a chance of Golden.'
              : 'Tends this bed from its next planting.';
      final view = h.plotView(s, plotId, c.now);
      final mood = grownUp
          ? 'Grown up!'
          : view.empty
              ? 'Resting until you plant'
              : view.ripe
                  ? 'Cheering: it\'s ripe!'
                  : now
                      ? 'Tending: watering, weeding, nurturing'
                      : 'Waiting for the next planting';
      return Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F6E6),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFC9DDB0), width: 1.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // the helper, whole, in its slot
          Container(
            width: 96,
            height: 108,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFBF2), Color(0xFFDDEBC8)]),
              border: Border.all(color: _leaf, width: 2),
            ),
            child: Column(children: [
              Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(4, 6, 4, 0), child: _Breathing(pet: helper, expr: view.empty ? 'sleepy' : (view.ripe ? 'excited' : 'happy')))),
              Container(
                margin: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: _leaf, borderRadius: BorderRadius.circular(8)),
                child: Text(stageLabels[helper.stage] ?? '', style: EvochiText.tag.copyWith(fontSize: 10.5, color: Colors.white, fontWeight: FontWeight.w900)),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              TendedPill(name: helper.name),
              const SizedBox(height: 4),
              Text(mood, style: EvochiText.cardTitle.copyWith(fontSize: 14.5)),
              Text(note, style: EvochiText.caption.copyWith(fontSize: 12.5)),
              const SizedBox(height: 6),
              const Wrap(spacing: 6, runSpacing: 4, children: [
                _Perk(Icons.water_drop_rounded, Color(0xFF5BAFE0), 'Watered'),
                _Perk(Icons.add_rounded, _leaf, '1 harvest'),
                _Perk(Icons.auto_awesome, Color(0xFFE0A21E), 'Golden 10%'),
              ]),
              const SizedBox(height: 6),
              EvochiButton(
                label: can.length > 1 ? 'Change helper' : 'Let it rest',
                small: true,
                expand: false,
                tone: ButtonTone.cream,
                onPressed: () => can.length > 1 ? showHelperPicker(context, plotId) : _assign(c, plotId, null),
              ),
            ]),
          ),
        ]),
      );
    }
    if (can.isEmpty) {
      return _Box(children: [
        const Icon(Icons.eco_rounded, color: _leaf, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text('A Forest Evochi at its Juvenile stage, resting at home, can tend a bed: watered, +1 every harvest, and a chance of a Golden crop.',
              style: EvochiText.caption.copyWith(fontSize: 12.5)),
        ),
      ]);
    }
    return _Box(children: [
      const Icon(Icons.eco_rounded, color: _leaf, size: 26),
      const SizedBox(width: 8),
      Expanded(child: Text(can.length == 1 ? '${can.first.name} could tend this bed.' : 'Your Forest Juveniles could tend this bed.', style: EvochiText.caption.copyWith(fontSize: 13))),
      EvochiButton(
        label: 'Ask a helper',
        small: true,
        expand: false,
        tone: ButtonTone.green,
        onPressed: () => can.length == 1 ? _assign(c, plotId, can.first.id) : showHelperPicker(context, plotId),
      ),
    ]);
  }
}

void _assign(GameController c, String plotId, String? petId) {
  final r = c.run((s, n) => h.assignHelper(s, plotId, petId, n));
  if (!r.ok) return;
  if (petId != null) {
    c.audio.play('pet_chirp', volume: 0.55);
    c.audio.buzz(Haptic.purr);
  } else {
    c.audio.play('ui_tap', volume: 0.4);
  }
}

/// Pick which Forest Juvenile tends [plotId] (or none).
Future<void> showHelperPicker(BuildContext context, String plotId) => showEvochiSheet<void>(
      context,
      builder: (ctx) {
        final c = ctx.watch<GameController>();
        final s = c.state;
        final current = s.home.helpers[plotId];
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Padding(padding: EdgeInsets.fromLTRB(4, 4, 4, 2), child: Text('Who tends this bed?', style: EvochiText.cardTitle)),
          const Padding(
            padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
            child: Text('A helper keeps its bed watered, adds one to every harvest and sometimes brings a Golden one. One bed each.', style: EvochiText.caption),
          ),
          for (final p in h.helperCandidates(s))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  _assign(c, plotId, p.id);
                  Navigator.of(ctx).maybePop();
                },
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: Kit.card(highlight: p.id == current),
                  child: Row(children: [
                    _Face(p, size: 52),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(p.name, style: EvochiText.cardTitle.copyWith(fontSize: 15)),
                        Text(_where(s, p), style: EvochiText.caption.copyWith(fontSize: 12.5)),
                      ]),
                    ),
                    if (p.id == current) const Icon(Icons.check_circle_rounded, color: _leaf),
                  ]),
                ),
              ),
            ),
          if (current != null)
            EvochiButton(
              label: 'Let it rest',
              tone: ButtonTone.cream,
              onPressed: () {
                _assign(c, plotId, null);
                Navigator.of(ctx).maybePop();
              },
            ),
        ]);
      },
    );

String _where(GameState s, Pet p) {
  final bed = h.bedOf(s, p.id);
  if (bed == null) return '${stageLabels[p.stage]} · resting';
  return '${stageLabels[p.stage]} · tending bed ${h.plotDefs.indexWhere((d) => d.id == bed) + 1}';
}

class _Box extends StatelessWidget {
  const _Box({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 10),
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF1F6E6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFC9DDB0), width: 1.5),
        ),
        child: Row(children: children),
      );
}

class _Face extends StatelessWidget {
  const _Face(this.pet, {required this.size});
  final Pet pet;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: PetSprite(stage: pet.stage, palette: pet.paletteId, expr: 'happy', overlays: pet.equipped.values.toList(), height: size),
      );
}

/// The little helper on a tended bed (top left of the bed).
class HelperBadge extends StatelessWidget {
  const HelperBadge({super.key, required this.pet, required this.tending, this.size = 34});
  final Pet pet;
  final bool tending; // tending this crop now (dimmer when it waits for the next planting)
  final double size;
  @override
  Widget build(BuildContext context) => Opacity(
        opacity: tending ? 1 : 0.7,
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0xF2F1F6E6),
            border: Border.all(color: tending ? _leaf : const Color(0xFFB8C9A0), width: 2),
            boxShadow: const [BoxShadow(color: Color(0x40281910), blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: ClipOval(child: PetSprite(stage: pet.stage, palette: pet.paletteId, expr: 'happy', height: size)),
        ),
      );
}

/// A harvest popping out of its bed: each item flies up in an arc and falls away, its count rising over the
/// bed. Golden: a gold flash, a ring of glints and "Golden harvest!".
class HarvestBurst extends StatefulWidget {
  const HarvestBurst({super.key, required this.items, required this.golden, this.animate = true, this.scale = 1});
  final Map<String, int> items;
  final bool golden;
  final bool animate;
  final double scale; // smaller beds, smaller burst

  static int millis(bool golden) => golden ? 2200 : 1300;

  @override
  State<HarvestBurst> createState() => _HarvestBurstState();
}

class _Bit {
  _Bit(this.item, this.vx, this.vy, this.spin, this.delay, this.size);
  final String item;
  final double vx, vy, spin, delay, size;
}

class _HarvestBurstState extends State<HarvestBurst> with SingleTickerProviderStateMixin {
  late final AnimationController _a;
  late final List<_Bit> _bits;

  @override
  void initState() {
    super.initState();
    _a = AnimationController(vsync: this, duration: Duration(milliseconds: HarvestBurst.millis(widget.golden)));
    final rnd = math.Random(widget.items.keys.join().hashCode ^ widget.items.values.fold<int>(0, (a, b) => a * 31 + b));
    _bits = [];
    for (final e in widget.items.entries) {
      final gilded = e.key.startsWith('gilded_');
      final n = gilded ? 1 : math.min(e.value, widget.golden ? 7 : 5);
      for (var i = 0; i < n; i++) {
        final ang = gilded ? 0.0 : (rnd.nextDouble() - 0.5) * 1.9;
        final sp = gilded ? 300.0 : 220 + rnd.nextDouble() * 120;
        _bits.add(_Bit(e.key, math.sin(ang) * sp, -math.cos(ang) * sp, (rnd.nextDouble() - 0.5) * 6, gilded ? 0.12 : i * 0.035, gilded ? 46 : 26 + rnd.nextDouble() * 6));
      }
    }
    if (widget.animate) {
      _a.forward();
    } else {
      _a.value = 0.5;
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.scale;
    final total = HarvestBurst.millis(widget.golden) / 1000;
    return AnimatedBuilder(
      animation: _a,
      builder: (ctx, _) {
        final t = _a.value * total; // seconds
        final out = <Widget>[];
        if (widget.golden) {
          // the flash, and a ring of glints opening out
          final f = (t / 0.7).clamp(0.0, 1.0);
          out.add(Center(
            child: Opacity(
              opacity: (1 - f) * 0.9,
              child: Container(
                width: 60 * k + 220 * k * Curves.easeOut.transform(f),
                height: 60 * k + 220 * k * Curves.easeOut.transform(f),
                decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xEEFFF3C0), Color(0x88FFD45A), Color(0x00FFD45A)])),
              ),
            ),
          ));
          final rr = (t / 1.0).clamp(0.0, 1.0);
          for (var i = 0; i < 10; i++) {
            final a = i * math.pi / 5 + 0.3;
            final d = (24 + 110 * Curves.easeOut.transform(rr)) * k;
            out.add(Center(
              child: Transform.translate(
                offset: Offset(math.cos(a) * d, math.sin(a) * d * 0.7 - 10 * k),
                child: Opacity(opacity: (1 - rr).clamp(0.0, 1.0), child: Icon(Icons.auto_awesome, size: 16 * k, color: Colors.white)),
              ),
            ));
          }
        }
        // the crop, popping out
        for (final b in _bits) {
          final tt = t - b.delay;
          if (tt <= 0) continue;
          final life = total - b.delay - 0.15;
          const g = 620.0;
          final x = b.vx * tt * k;
          final y = (b.vy * tt + 0.5 * g * tt * tt) * k;
          final pop = tt < 0.12 ? Curves.easeOutBack.transform(tt / 0.12) : 1.0;
          final fade = tt > life * 0.7 ? (1 - (tt - life * 0.7) / (life * 0.3)).clamp(0.0, 1.0) : 1.0;
          out.add(Center(
            child: Transform.translate(
              offset: Offset(x, y),
              child: Transform.rotate(
                angle: b.spin * tt * (b.item.startsWith('gilded_') ? 0.0 : 1.0),
                child: Opacity(opacity: fade, child: Transform.scale(scale: pop, child: ItemImage(b.item, size: b.size * k))),
              ),
            ),
          ));
        }
        // the counts, rising
        final rise = Curves.easeOut.transform((t / 0.9).clamp(0.0, 1.0));
        final cf = t > total - 0.45 ? ((total - t) / 0.45).clamp(0.0, 1.0) : (t / 0.15).clamp(0.0, 1.0);
        out.add(Positioned(
          left: -80,
          right: -80,
          top: 0,
          child: Transform.translate(
            offset: Offset(0, (-30 - 46 * rise) * k),
            child: Opacity(
              opacity: cf,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (widget.golden)
                  Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF1B8), _gold]),
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: const [BoxShadow(color: Color(0x66A0640A), blurRadius: 8, offset: Offset(0, 2))],
                    ),
                    child: Text('Golden harvest!', style: EvochiText.tag.copyWith(fontWeight: FontWeight.w900, fontSize: 14 * k, color: const Color(0xFF6B4410))),
                  ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final e in widget.items.entries) ...[
                    ItemImage(e.key, size: 24 * k),
                    Text('+${e.value}',
                        style: EvochiText.number.copyWith(fontSize: 16 * k, color: Colors.white, shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)])),
                    const SizedBox(width: 4),
                  ],
                ]),
              ]),
            ),
          ),
        ));
        return IgnorePointer(child: Stack(clipBehavior: Clip.none, children: out));
      },
    );
  }
}

/// "Tended by Fern": a leaf and its name, on a green pill.
class TendedPill extends StatelessWidget {
  const TendedPill({super.key, required this.name, this.small = false});
  final String name;
  final bool small;
  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: small ? 6 : 8, vertical: small ? 1 : 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFBF0), Color(0xFFE6F0D4)]),
          border: Border.all(color: _leaf, width: small ? 1.5 : 2),
          boxShadow: const [BoxShadow(color: Color(0x33281910), blurRadius: 4, offset: Offset(0, 2))],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.eco_rounded, size: small ? 11 : 14, color: _leaf),
          const SizedBox(width: 3),
          Text(small ? name : 'Tended by $name', style: EvochiText.tag.copyWith(fontSize: small ? 9.5 : 12, fontWeight: FontWeight.w900, color: const Color(0xFF2F5A22))),
        ]),
      );
}

class _Perk extends StatelessWidget {
  const _Perk(this.icon, this.color, this.text);
  final IconData icon;
  final Color color;
  final String text;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.75), borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 2),
          Text(text, style: EvochiText.tag.copyWith(fontSize: 11.5, color: EvochiColor.ink)),
        ]),
      );
}

/// The helper, whole, breathing (and blinking now and then).
class _Breathing extends StatefulWidget {
  const _Breathing({required this.pet, required this.expr});
  final Pet pet;
  final String expr;
  @override
  State<_Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<_Breathing> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return LayoutBuilder(builder: (ctx, b) {
      return AnimatedBuilder(
        animation: _a,
        builder: (_, __) {
          final t = reduce ? 0.0 : _a.value * 4;
          final blink = widget.expr != 'sleepy' && (t % 4) > 3.25 && (t % 4) < 3.4;
          final br = math.sin(t * math.pi);
          return Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.diagonal3Values(1 - 0.012 * br, 1 + 0.02 * br, 1),
            child: PetSprite(stage: widget.pet.stage, palette: widget.pet.paletteId, expr: blink ? 'blink' : widget.expr, overlays: widget.pet.equipped.values.toList(), height: b.maxHeight),
          );
        },
      );
    });
  }
}

// ------------------------------------------------------------------ the plot actor ----
/// What a helper is doing on its bed, from what the bed is doing (and what just happened).
enum HelperMood { resting, idle, planting, watering, tending, nurturing, ready, harvest }

HelperMood helperMood({required h.PlotView p, required bool tending, required double t, double offset = 0}) {
  if (p.empty) return HelperMood.resting;
  if (p.ripe) return HelperMood.ready;
  if (!tending) return HelperMood.idle;
  // growing: a working loop, each a little under two and a half seconds
  const loop = [HelperMood.idle, HelperMood.tending, HelperMood.watering, HelperMood.idle, HelperMood.nurturing];
  return loop[((t + offset) / _beat).floor() % loop.length];
}

const _beat = 2.4;

/// The helper on its bed: perched at the bed's inner corner, facing it, with its telekinesis props (a floating
/// watering can, a swirl of leaves, a green glow from the soil, a seed pouch, a harvest basket). [bed] and
/// [plate] are in the plate's pixels.
class PlotActor extends StatefulWidget {
  const PlotActor({
    super.key,
    required this.pet,
    required this.p,
    required this.tending,
    required this.bed,
    required this.plate,
    this.planted = false,
    this.splashed = false,
    this.harvested = false,
    this.animate = true,
  });
  final Pet pet;
  final h.PlotView p;
  final bool tending;
  final Rect bed;
  final Size plate;
  final bool planted, splashed, harvested, animate;

  @override
  State<PlotActor> createState() => _PlotActorState();
}

class _PlotActorState extends State<PlotActor> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 60));

  // something that just happened plays its own loop through, from when it happened
  HelperMood? _event;
  double _t0 = 0;
  static const _lengths = {HelperMood.planting: 2.2, HelperMood.watering: _beat, HelperMood.harvest: 2.1};

  @override
  void initState() {
    super.initState();
    if (widget.animate) _a.repeat();
    if (widget.harvested) _start(HelperMood.harvest);
  }

  void _start(HelperMood m) {
    _event = m;
    _t0 = _clock;
  }

  @override
  void didUpdateWidget(PlotActor old) {
    super.didUpdateWidget(old);
    if (widget.harvested && !old.harvested) _start(HelperMood.harvest);
    if (widget.planted && !old.planted) _start(HelperMood.planting);
    if (widget.splashed && !old.splashed) _start(HelperMood.watering);
  }

  double get _clock => (_a.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final off = (w.p.id.hashCode % 97) / 97 * _beat * 5;
    return AnimatedBuilder(
      animation: _a,
      builder: (ctx, _) {
        final t = w.animate ? _clock : 0.0;
        // planted, it sows and then waters
        if (_event == HelperMood.planting && t - _t0 >= _lengths[HelperMood.planting]! && w.tending) {
          _event = HelperMood.watering;
          _t0 += _lengths[HelperMood.planting]!;
        }
        final ev = _event;
        if (ev != null && w.animate && t - _t0 < _lengths[ev]!) return _actor(ev, t, t - _t0);
        final mood = helperMood(p: w.p, tending: w.tending, t: t, offset: off);
        return _actor(mood, t, (t + off) % _beat);
      },
    );
  }

  Widget _actor(HelperMood mood, double t, double u) {
    final w = widget;
    final bed = w.bed;
    // perched at the bed's outer front corner, facing in: the left beds' left corner, the right beds' right
    // (the art faces left: the left beds' helpers are turned round)
    final left = bed.center.dx < w.plate.width / 2;
    final ph = bed.height * 0.92;
    final pw = ph * 330 / 375;
    final dir = left ? 1.0 : -1.0; // toward the bed
    final foot = Offset(left ? bed.left + pw * 0.2 : bed.right - pw * 0.2, bed.bottom + bed.height * 0.08);
    // its body: breathing, and what the mood does to it
    final br = math.sin(t * math.pi * (mood == HelperMood.resting ? 0.66 : 1.0));
    var sy = 1 + 0.022 * br, sx = 1 - 0.012 * br, lift = 0.0, lean = 0.0;
    var expr = 'default';
    switch (mood) {
      case HelperMood.resting:
        expr = 'sleepy';
      case HelperMood.idle:
        expr = (t % 3.7) < 0.14 ? 'blink' : 'default';
        lean = 0.03 * math.sin(t * 0.9);
      case HelperMood.planting:
        expr = 'curious';
        lean = 0.05 * dir;
      case HelperMood.watering:
        expr = 'determined';
        lean = 0.06 * dir;
      case HelperMood.tending:
        expr = 'happy';
        lift = 3 * math.sin(u / 0.6 * math.pi).abs();
      case HelperMood.nurturing:
        expr = 'affectionate';
      case HelperMood.ready:
        expr = 'excited';
        final hop = math.max(0.0, math.sin(t * 2 * math.pi / 0.9));
        lift = ph * 0.12 * hop;
        sy *= 1 + 0.05 * hop;
        sx *= 1 - 0.03 * hop;
      case HelperMood.harvest:
        expr = 'happy';
        final k = (u / 0.7).clamp(0.0, 1.0);
        lift = ph * 0.22 * math.sin(k * math.pi);
    }
    final petRect = Rect.fromLTWH(foot.dx - pw / 2, foot.dy - ph - lift, pw, ph);
    final kids = <Widget>[
      // the soil glowing as it nurtures (behind everything on the bed)
      Positioned.fill(child: CustomPaint(painter: _MagicPainter(mood: mood, t: t, u: u, bed: bed, head: Offset(petRect.left + pw * (left ? 0.62 : 0.38), petRect.top + ph * 0.3), dir: dir))),
      // the helper
      Positioned.fromRect(
        rect: petRect,
        child: Transform(
          alignment: Alignment.bottomCenter,
          transform: Matrix4.identity()
            ..rotateZ(lean)
            ..scale(left ? -sx : sx, sy, 1),
          child: PetSprite(stage: w.pet.stage, palette: w.pet.paletteId, expr: expr, overlays: w.pet.equipped.values.toList(), height: ph),
        ),
      ),
    ];
    // the props it floats
    final over = Offset(bed.center.dx - dir * bed.width * 0.05, bed.top + bed.height * 0.05);
    final ps = bed.height * 0.62;
    Widget prop(String file, Offset at, double angle, {double opacity = 1, double size = 1}) => Positioned(
          left: at.dx - ps * size / 2,
          top: at.dy - ps * size / 2,
          width: ps * size,
          height: ps * size,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..rotateZ(angle)
                ..scale(left ? -1.0 : 1.0, 1.0, 1.0),
              child: Image.asset('assets/art/home/$file.webp', filterQuality: FilterQuality.none, excludeFromSemantics: true, gaplessPlayback: true),
            ),
          ),
        );
    double inOut(double u, double len) => (math.min(u / 0.3, (len - u) / 0.3)).clamp(0.0, 1.0);
    switch (mood) {
      case HelperMood.watering:
        // up, tilt, pour, back
        final tilt = u < 0.4 ? 0.0 : (u < 0.7 ? (u - 0.4) / 0.3 : (u < 1.9 ? 1.0 : math.max(0.0, 1 - (u - 1.9) / 0.4)));
        final bob = math.sin(t * 5) * 2;
        kids.add(prop('prop_watering_can', over + Offset(0, -ps * 0.1 + bob), -0.6 * tilt * (left ? -1 : 1), opacity: inOut(u, _beat)));
      case HelperMood.planting:
        kids.add(prop('prop_seed_pouch', over + Offset(0, -ps * 0.15 + math.sin(t * 4) * 2), 0.35 * math.sin(u * 6), opacity: inOut(u, 2.2), size: 0.8));
      case HelperMood.harvest:
        final k = (u / 1.6).clamp(0.0, 1.0);
        kids.add(prop('prop_basket', Offset(bed.center.dx, bed.top - bed.height * 0.2 * Curves.easeOut.transform(k)), 0.06 * math.sin(t * 6), opacity: (1 - (u - 1.6) / 0.5).clamp(0.0, 1.0), size: 1.05));
      default:
        break;
    }
    return IgnorePointer(child: Stack(clipBehavior: Clip.none, children: kids));
  }
}

/// The helper's magic: leaves swirling over the crop, the soil glowing, water falling, seeds dropping, little
/// "!" marks when the crop is ripe, Zs when it rests, and a faint trail of green from its head to what it lifts.
class _MagicPainter extends CustomPainter {
  _MagicPainter({required this.mood, required this.t, required this.u, required this.bed, required this.head, required this.dir});
  final HelperMood mood;
  final double t, u;
  final Rect bed;
  final Offset head;
  final double dir;

  static void _leaf(Canvas c, Offset at, double size, double angle, double a) {
    c.save();
    c.translate(at.dx, at.dy);
    c.rotate(angle);
    final p = Path()
      ..moveTo(-size, 0)
      ..quadraticBezierTo(0, -size * 0.75, size, 0)
      ..quadraticBezierTo(0, size * 0.75, -size, 0)
      ..close();
    c.drawPath(p, Paint()..color = const Color(0xFF7CC350).withValues(alpha: a));
    c.drawLine(Offset(-size * 0.8, 0), Offset(size * 0.8, 0), Paint()
      ..color = const Color(0xFF4E8F33).withValues(alpha: a)
      ..strokeWidth = math.max(1, size * 0.15));
    c.restore();
  }

  @override
  void paint(Canvas c, Size size) {
    final crop = Offset(bed.center.dx, bed.center.dy - bed.height * 0.1);
    final over = Offset(bed.center.dx - dir * bed.width * 0.05, bed.top + bed.height * 0.05 - bed.height * 0.06);
    void trail(Offset to, double a) {
      // a few green motes along a soft curve from the helper's head to the prop
      final mid = Offset((head.dx + to.dx) / 2, math.min(head.dy, to.dy) - bed.height * 0.25);
      for (var i = 1; i < 6; i++) {
        final k = ((i / 6) + t * 0.6) % 1.0;
        final p = Offset.lerp(Offset.lerp(head, mid, k)!, Offset.lerp(mid, to, k)!, k)!;
        c.drawCircle(p, 1.6 + 1.2 * math.sin(k * math.pi), Paint()..color = const Color(0xFFB8F07A).withValues(alpha: a * 0.8 * math.sin(k * math.pi)));
      }
      c.drawCircle(to, bed.height * 0.28, Paint()
        ..color = const Color(0xFF9BE36A).withValues(alpha: 0.22 * a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
    }

    double inOut(double len) => (math.min(u / 0.3, (len - u) / 0.3)).clamp(0.0, 1.0);
    switch (mood) {
      case HelperMood.tending:
        // leaves circling the crop, rising
        for (var i = 0; i < 6; i++) {
          final a = t * 2.2 + i * math.pi / 3;
          final r = bed.width * 0.26;
          final p = crop + Offset(math.cos(a) * r, math.sin(a) * r * 0.35 - (u * 6 + i * 2) % 14);
          _leaf(c, p, bed.height * 0.07, a + math.pi / 2, inOut(_beat) * (0.55 + 0.45 * math.sin(a).abs()));
        }
      case HelperMood.nurturing:
        // the soil glowing, a soft column of green rising out of it
        final k = inOut(_beat);
        final pulse = 0.7 + 0.3 * math.sin(t * 5);
        final col = Rect.fromCenter(center: bed.center.translate(0, -bed.height * 0.25), width: bed.width * 0.78, height: bed.height * 1.25);
        c.drawRRect(
          RRect.fromRectAndRadius(col, Radius.circular(bed.height * 0.3)),
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [const Color(0xFFC6F58A).withValues(alpha: 0.45 * k * pulse), const Color(0x00C6F58A)],
            ).createShader(col),
        );
        for (var i = 0; i < 7; i++) {
          final x = bed.left + bed.width * (0.15 + 0.7 * ((i * 0.37) % 1));
          final y = bed.bottom - bed.height * 0.2 - ((u * 30 + i * 9) % (bed.height * 1.1));
          c.drawCircle(Offset(x, y), 1.8, Paint()..color = Colors.white.withValues(alpha: 0.8 * k));
        }
        trail(crop, k * 0.7);
      case HelperMood.watering:
        final k = inOut(_beat);
        trail(over, k);
        // the pour: drops from the spout to the soil
        if (u > 0.65 && u < 2.0) {
          final spout = over + Offset(dir * bed.height * 0.3, bed.height * 0.12);
          for (var i = 0; i < 9; i++) {
            final f = ((u * 2.4) + i / 9) % 1.0;
            final p = spout + Offset(dir * f * bed.height * 0.1 + math.sin(i * 7.0) * 3, f * bed.height * 0.55);
            c.drawOval(Rect.fromCenter(center: p, width: 3, height: 5), Paint()..color = const Color(0xFF7CC4F2).withValues(alpha: 0.9 * (1 - f * 0.5)));
          }
        }
      case HelperMood.planting:
        final k = inOut(2.2);
        trail(over, k);
        for (var i = 0; i < 6; i++) {
          final f = ((u * 1.8) + i / 6) % 1.0;
          final p = over + Offset(math.sin(i * 5.0) * bed.width * 0.12, bed.height * 0.1 + f * bed.height * 0.5);
          c.drawCircle(p, 2, Paint()..color = const Color(0xFF7A5230).withValues(alpha: k * (1 - f)));
        }
      case HelperMood.harvest:
        trail(Offset(bed.center.dx, bed.top - bed.height * 0.15), (1 - u / 2.0).clamp(0.0, 1.0));
      case HelperMood.ready:
        // "!" marks over its head
        for (var i = -1; i <= 1; i++) {
          final a = -math.pi / 2 + i * 0.5;
          final k = 0.5 + 0.5 * math.sin(t * 6 + i);
          final o = head + Offset(0, -bed.height * 0.35);
          final p1 = o + Offset(math.cos(a), math.sin(a)) * bed.height * 0.12;
          final p2 = o + Offset(math.cos(a), math.sin(a)) * bed.height * (0.22 + 0.04 * k);
          c.drawLine(p1, p2, Paint()
            ..color = const Color(0xFFFFC93C)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round);
        }
      case HelperMood.resting:
        // Zs, drifting up
        for (var i = 0; i < 3; i++) {
          final f = ((t / 3.0) + i / 3) % 1.0;
          final tp = TextPainter(
            text: TextSpan(text: 'z', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 9 + 7 * f, color: const Color(0xFF5B6B8A).withValues(alpha: math.sin(f * math.pi)))),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(c, head + Offset(-dir * (6 + f * 14), -bed.height * 0.3 - f * bed.height * 0.5));
        }
      case HelperMood.idle:
        break;
    }
  }

  @override
  bool shouldRepaint(_MagicPainter old) => true;
}

