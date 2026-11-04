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
          ? '${helper.name} has grown up!'
          : view.empty
              ? '${helper.name} is napping by the bed'
              : view.ripe
                  ? '${helper.name} is proud of this crop'
                  : now
                      ? '${helper.name} is tending your crops'
                      : '${helper.name} waits for the next planting';
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
    // every helper slot in use: the one at work could move here, and the next slot's level
    if (h.helpersAtWork(s) >= h.helperSlots(s)) {
      final busy = [for (final e in s.home.helpers.entries) if (h.helperOf(s, e.key) case final p?) (e.key, p)];
      final next = h.nextHelperSlot(s);
      final one = busy.length == 1 ? busy.first : null;
      return _Box(children: [
        const Icon(Icons.eco_rounded, color: _leaf, size: 26),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '${one != null ? '${one.$2.name} is tending bed ${_bedNo(one.$1)}.' : 'Your helpers are all at work.'}${next != null ? ' Another helper joins at Farming $next.' : ''}',
            style: EvochiText.caption.copyWith(fontSize: 12.5),
          ),
        ),
        EvochiButton(
          label: one != null ? 'Move ${one.$2.name} here' : 'Change',
          small: true,
          expand: false,
          tone: ButtonTone.cream,
          onPressed: () => one != null ? _assign(c, plotId, one.$2.id) : showHelperPicker(context, plotId),
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

int _bedNo(String plotId) => h.plotDefs.indexWhere((d) => d.id == plotId) + 1;

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
            padding: EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text('A helper keeps its bed watered, adds one to every harvest and sometimes brings a Golden one. One bed each.', style: EvochiText.caption),
          ),
          // the slots: those in use, and the ones still to open
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(children: [
              for (var i = 0; i < 1 + h.helperSlotLevels.length; i++) ...[
                Expanded(child: _Slot(open: i < h.helperSlots(s), used: i < h.helpersAtWork(s), level: i == 0 ? null : h.helperSlotLevels[i - 1])),
                if (i < h.helperSlotLevels.length) const SizedBox(width: 6),
              ],
            ]),
          ),
          for (final p in h.helperCandidates(s))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  if (h.bedOf(s, p.id) == null && h.helpersAtWork(s) >= h.helperSlots(s)) return; // no free slot
                  _assign(c, plotId, p.id);
                  Navigator.of(ctx).maybePop();
                },
                child: Opacity(
                  opacity: h.bedOf(s, p.id) == null && h.helpersAtWork(s) >= h.helperSlots(s) ? 0.5 : 1,
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
// The helper stands just outside its bed, feet on the walkway, turned toward it, its watering can resting on the
// path beside it. Most of the time it just lives there (breathing, blinking, swaying, a glance at the crop, now
// and then a butterfly to watch, napping when the bed is empty, admiring a ripe crop). Every 12-20 s (sooner for
// an energetic one; and once soon after the garden opens) it does one bit of work, by telekinesis: the can floats
// up over the crop, tips, pours and settles back; or leaves circle it while the plants lean in and pulse. Its
// harvest: it gathers itself, the basket lands by the bed, the crop lifts out piece by piece into it, and it hops.
// A Golden one surprises it first. No arms and no walking: everything it moves, it moves with nature magic.

/// What a helper is doing.
enum HelperMood { sleeping, idle, glancing, butterfly, admiring, cheering, watering, nurturing, harvest }

const _waterLen = 3.2, _nurtureLen = 2.8;

/// How long a harvest plays: a helper's (anticipation, the crop into the basket, a hop) or the plain burst.
int harvestMillis({required bool golden, required bool tended}) => tended ? (golden ? 2700 : 1900) : HarvestBurst.millis(golden);

/// The crops leaning toward their helper as it nurtures them (radians, + toward the right), by bed.
final gardenLean = <String, ValueNotifier<double>>{};

ValueNotifier<double> leanOf(String plotId) => gardenLean.putIfAbsent(plotId, () => ValueNotifier(0));

/// A helper's timetable: when its work comes round, and what it does, from its personality.
class _Plan {
  _Plan(Pet pet, this.rank)
      : energy = pet.personality.traits['energy'] ?? 0.5,
        curiosity = pet.personality.traits['curiosity'] ?? 0.5,
        expressive = pet.personality.traits['expressiveness'] ?? 0.5,
        seed = pet.id.hashCode & 0xffff;
  final double energy, curiosity, expressive;
  final int seed, rank;

  double get period => 20 - 8 * energy;
  double get first => 1.2 + rank * 2.6;
  double get blinkEvery => 3.2 + (seed % 14) / 10;
  double get phase => (seed % 100) / 100 * 6;

  /// The work under way at [t], and how far into it.
  (HelperMood, double)? work(double t) {
    if (t < first) return null;
    final k = ((t - first) / period).floor();
    final u = t - first - k * period;
    final kind = k == 0 || (k + (curiosity > 0.55 ? 1 : 0)).isEven ? HelperMood.watering : HelperMood.nurturing;
    final len = kind == HelperMood.watering ? _waterLen : _nurtureLen;
    return u < len ? (kind, u) : null;
  }

  /// A butterfly's visit (the curious get more), and how far into it.
  double? butterfly(double t) {
    final every = 30 + 22 * (1 - curiosity);
    final start = first + period * 0.5 + 3 + (seed % 7);
    if (t < start) return null;
    final u = (t - start) % every;
    return u < 5.0 ? u : null;
  }
}

class PlotActor extends StatefulWidget {
  const PlotActor({
    super.key,
    required this.pet,
    required this.p,
    required this.tending,
    required this.bed,
    required this.plate,
    this.rank = 0,
    this.harvest,
    this.onTap,
    this.animate = true,
  });
  final Pet pet;
  final h.PlotView p;
  final bool tending;
  final Rect bed;
  final Size plate;
  final int rank; // its place among the garden's helpers (their first bits of work are staggered)
  final (Map<String, int>, bool)? harvest; // just harvested, by it: the items, Golden?
  final VoidCallback? onTap;
  final bool animate;

  @override
  State<PlotActor> createState() => _PlotActorState();
}

class _PlotActorState extends State<PlotActor> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 60));
  late _Plan _plan = _Plan(widget.pet, widget.rank);
  double? _harvestAt; // when its harvest began (the clock)
  double? _tapAt; // when it was tapped (its name shows a moment)

  double get _clock => (_a.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _a.repeat();
    _a.addListener(_lean);
    if (widget.harvest != null) _harvestAt = 0;
  }

  @override
  void didUpdateWidget(PlotActor old) {
    super.didUpdateWidget(old);
    if (widget.pet.id != old.pet.id || widget.rank != old.rank) _plan = _Plan(widget.pet, widget.rank);
    if (widget.harvest != null && !identical(widget.harvest, old.harvest)) _harvestAt = _clock;
  }

  @override
  void dispose() {
    _a.removeListener(_lean);
    leanOf(widget.p.id).value = 0;
    _a.dispose();
    super.dispose();
  }

  // the plants lean toward it while it nurtures them (set on the tick, not while building)
  void _lean() {
    final w = _plan.work(_clock);
    var v = 0.0;
    if (w != null && w.$1 == HelperMood.nurturing && widget.tending && !widget.p.empty) {
      final u = w.$2;
      v = 0.09 * math.sin(((u - 0.3) / 2.1).clamp(0.0, 1.0) * math.pi);
    }
    final n = leanOf(widget.p.id);
    final toward = -v; // (its helper stands on its right: the tops lean right)
    if ((n.value - toward).abs() > 0.002) n.value = toward;
  }

  void _tap() {
    setState(() => _tapAt = _clock);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: _a, builder: (ctx, _) => _frame(widget.animate ? _clock : 0.0));

  Widget _frame(double t) {
    final w = widget;
    final bed = w.bed;
    // every helper stands on the walkway at its bed's right front corner, turned toward it (as the art faces):
    // the left beds' helpers in the path between the beds, the right beds' in the margin, so none meet
    const dir = -1.0; // toward the bed
    final ph = bed.height * 0.9;
    final pw = ph * 330 / 375;
    final fx = (bed.right + pw * 0.3).clamp(pw * 0.5 + 2, w.plate.width - pw * 0.5 - 2);
    final foot = Offset(fx, bed.bottom - bed.height * 0.04);
    final ps = bed.height * 0.5; // a prop's size
    final rest = Offset(foot.dx + dir * pw * 0.46, foot.dy - ps * 0.12); // the can, on the bed's front corner
    final over = Offset(bed.center.dx - dir * bed.width * 0.06, bed.top + bed.height * 0.12);
    final basketAt = Offset(bed.right - bed.width * 0.24, bed.bottom - ps * 0.2);

    // ---- what it's doing
    var mood = HelperMood.idle;
    var u = 0.0;
    final hv = _harvestAt;
    final harvest = w.harvest;
    final golden = harvest?.$2 ?? false;
    final hLen = harvestMillis(golden: golden, tended: true) / 1000;
    if (harvest != null && hv != null && t - hv < hLen) {
      mood = HelperMood.harvest;
      u = t - hv;
    } else if (w.p.empty) {
      mood = HelperMood.sleeping;
    } else if (w.p.ripe) {
      final c = (t + _plan.phase) % 5.5;
      mood = c < 1.3 * (0.6 + _plan.expressive * 0.6) ? HelperMood.cheering : HelperMood.admiring;
      u = c;
    } else if (w.tending && _plan.work(t) != null) {
      (mood, u) = _plan.work(t)!;
    } else if (_plan.butterfly(t) != null) {
      mood = HelperMood.butterfly;
      u = _plan.butterfly(t)!;
    } else if ((t + _plan.phase) % 7.3 < 1.4) {
      mood = HelperMood.glancing;
      u = (t + _plan.phase) % 7.3;
    }

    // ---- its body
    final br = math.sin((t + _plan.phase) * math.pi * (mood == HelperMood.sleeping ? 0.6 : 0.95));
    var sy = 1 + 0.022 * br, sx = 1 - 0.012 * br, lift = 0.0, tilt = 0.0;
    final sway = 0.012 * math.sin(t * 1.3 + _plan.phase);
    var expr = ((t + _plan.phase) % _plan.blinkEvery) < 0.13 ? 'blink' : 'default';
    var crest = 0.0; // its crest glowing as it works
    var aura = 0.0;
    double ramp(double a, double b) => ((u - a) / (b - a)).clamp(0.0, 1.0);
    // butterfly path (in plate px), for its eyes to follow
    Offset? fly;
    switch (mood) {
      case HelperMood.sleeping:
        expr = 'sleepy';
      case HelperMood.idle:
        break;
      case HelperMood.glancing:
        expr = 'curious';
        tilt = 0.06 * dir * math.sin(ramp(0, 1.4) * math.pi);
      case HelperMood.butterfly:
        expr = u < 4.4 ? 'curious' : 'happy';
        final k = u / 5.0;
        fly = Offset(
          foot.dx + dir * pw * (0.2 + 0.9 * math.sin(k * math.pi)) + 12 * math.sin(u * 3.1),
          foot.dy - ph * (1.05 + 0.25 * math.sin(u * 1.7)) - 10 * math.sin(u * 5.3),
        );
        tilt = ((fly.dx - foot.dx) / (pw * 1.2)).clamp(-1.0, 1.0) * 0.07;
      case HelperMood.admiring:
        expr = 'affectionate';
        tilt = 0.04 * dir;
      case HelperMood.cheering:
        expr = 'excited';
        final hop = math.max(0.0, math.sin(u * 2 * math.pi / 0.65));
        lift = ph * 0.1 * hop * (0.6 + _plan.expressive * 0.6);
        sy *= 1 + 0.05 * hop;
      case HelperMood.watering:
        crest = ramp(0, 0.3) * (1 - ramp(2.4, 3.0));
        expr = u < 0.9 ? 'determined' : (u < 2.4 ? 'happy' : 'default');
        if (u < 0.3) sy *= 1 - 0.05 * math.sin(ramp(0, 0.3) * math.pi);
        // its eyes on the can: a tilt toward where it is
        tilt = 0.07 * dir * math.sin(ramp(0.2, 3.0) * math.pi);
      case HelperMood.nurturing:
        crest = ramp(0, 0.3) * (1 - ramp(2.3, 2.8));
        aura = ramp(0.25, 0.6) * (1 - ramp(2.2, 2.8));
        expr = u < 0.3 ? 'determined' : 'affectionate';
        if (u < 0.3) sy *= 1 - 0.05 * math.sin(ramp(0, 0.3) * math.pi);
      case HelperMood.harvest:
        // Golden: a surprise first (a step back, wide eyes, a tilt)
        final g0 = golden ? 0.5 : 0.0;
        if (golden && u < g0) {
          expr = 'surprised';
          tilt = -0.1 * dir * math.sin(ramp(0, g0) * math.pi);
          lift = ph * 0.05 * math.sin(ramp(0, 0.25) * math.pi);
        } else {
          final v = u - g0;
          crest = (v / 0.25).clamp(0.0, 1.0) * (1 - ((v - 1.0) / 0.3).clamp(0.0, 1.0));
          aura = ((v - 0.25) / 0.3).clamp(0.0, 1.0) * (1 - ((v - 1.1) / 0.3).clamp(0.0, 1.0));
          expr = v < 0.55 ? 'determined' : (v < 1.25 ? 'happy' : (golden ? 'excited' : 'happy'));
          if (v < 0.25) sy *= 1 - 0.06 * math.sin(v / 0.25 * math.pi);
          if (v > 1.25 && v < 1.8) {
            final k = (v - 1.25) / 0.55;
            lift = ph * 0.18 * math.sin(k * math.pi);
            sy *= 1 + 0.06 * math.sin(k * math.pi);
          }
        }
    }
    final petRect = Rect.fromLTWH(foot.dx - pw / 2, foot.dy - ph - lift, pw, ph);
    final head = Offset(petRect.left + pw * 0.45, petRect.top + ph * 0.08);
    final body = Offset(petRect.center.dx, petRect.top + ph * 0.6);

    // ---- the can: resting on the path, or up over the crop
    var canAt = rest;
    var canTip = 0.0;
    var canLit = 0.0;
    final canOut = mood == HelperMood.watering;
    if (canOut) {
      Offset arc(Offset a, Offset b, double k) {
        final m = Offset((a.dx + b.dx) / 2, math.min(a.dy, b.dy) - bed.height * 0.35);
        final e = Curves.easeInOut.transform(k);
        return Offset.lerp(Offset.lerp(a, m, e)!, Offset.lerp(m, b, e)!, e)!;
      }

      if (u < 0.3) {
        canAt = rest + Offset(0, -2 * math.sin(ramp(0, 0.3) * math.pi)); // a wobble: it's noticed
      } else if (u < 0.9) {
        canAt = arc(rest, over, ramp(0.3, 0.9));
      } else if (u < 2.4) {
        canAt = over + Offset(0, math.sin(t * 5) * 1.5);
      } else if (u < 3.0) {
        canAt = arc(over, rest, ramp(2.4, 3.0));
      } else {
        canAt = rest + Offset(0, -3 * math.sin(ramp(3.0, 3.2) * math.pi)); // settles with a little bounce
      }
      canTip = (ramp(0.9, 1.15) - ramp(2.15, 2.4)) * 0.62;
      canLit = ramp(0.25, 0.4) * (1 - ramp(2.9, 3.2));
    }
    final showCan = w.tending && !w.p.empty && mood != HelperMood.harvest;

    final kids = <Widget>[
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _MagicPainter(
              mood: mood, t: t, u: u, bed: bed, head: head, body: body, dir: dir, crest: crest, aura: aura, golden: golden,
              can: canOut ? canAt : null, canLit: canLit, canTip: canTip, fly: fly, ps: ps, pw: pw,
            ),
          ),
        ),
      ),
      // the helper (tap it for its name)
      Positioned.fromRect(
        rect: petRect,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tap,
          child: Semantics(
            button: true,
            label: '${w.pet.name}, your helper',
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..rotateZ(tilt)
                ..multiply(Matrix4.skewX(sway))
                ..scale(sx, sy, 1),
              child: PetSprite(stage: w.pet.stage, palette: w.pet.paletteId, expr: expr, overlays: w.pet.equipped.values.toList(), height: ph),
            ),
          ),
        ),
      ),
    ];
    Widget img(String file, Offset at, double size, {double angle = 0, double opacity = 1, bool flip = false, double squash = 1}) => Positioned(
          left: at.dx - size / 2,
          top: at.dy - size / 2,
          width: size,
          height: size,
          child: IgnorePointer(
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform(
                alignment: Alignment.bottomCenter,
                transform: Matrix4.identity()
                  ..rotateZ(angle)
                  ..scale(flip ? -1.0 : 1.0, squash, 1.0),
                child: Image.asset('assets/art/home/$file.webp', filterQuality: FilterQuality.none, excludeFromSemantics: true, gaplessPlayback: true),
              ),
            ),
          ),
        );
    // the can's art spouts to the left: turned round to pour into a bed on its right
    if (showCan) kids.add(img('prop_watering_can', canAt, ps * (canOut && u > 0.3 && u < 3.0 ? 1.1 : 0.9), angle: canTip * dir));

    // ---- its harvest: the basket by the bed, the crop lifting into it, the counts over it
    if (mood == HelperMood.harvest && harvest != null) {
      final g0 = golden ? 0.5 : 0.0;
      final v = u - g0;
      final land = ((v - 0.25) / 0.3).clamp(0.0, 1.0);
      final gone = ((v - (hLen - g0 - 0.3)) / 0.3).clamp(0.0, 1.0);
      final mouth = basketAt - Offset(0, ps * 0.22);
      // the pieces: up to five of each, the Gilded one last
      final bits = <String>[];
      for (final e in harvest.$1.entries.where((e) => !e.key.startsWith('gilded_'))) {
        for (var i = 0; i < math.min(e.value, 5); i++) {
          bits.add(e.key);
        }
      }
      bits.addAll(harvest.$1.keys.where((k) => k.startsWith('gilded_')));
      var bump = 0.0;
      for (var i = 0; i < bits.length; i++) {
        final s0 = 0.55 + i * (0.6 / math.max(1, bits.length));
        final k = ((v - s0) / 0.42).clamp(0.0, 1.0);
        if (v - s0 > 0.42 && v - s0 < 0.6) bump = math.max(bump, math.sin((v - s0 - 0.42) / 0.18 * math.pi));
        if (k <= 0 || k >= 1) continue;
        final from = Offset(bed.left + bed.width * (0.2 + 0.6 * ((i * 0.37 + 0.13) % 1)), bed.center.dy + bed.height * 0.05);
        final ctl = Offset((from.dx + mouth.dx) / 2, math.min(from.dy, mouth.dy) - bed.height * (0.55 + 0.1 * (i % 3)));
        final e = Curves.easeInOutSine.transform(k);
        final at = Offset.lerp(Offset.lerp(from, ctl, e)!, Offset.lerp(ctl, mouth, e)!, e)!;
        final gilded = bits[i].startsWith('gilded_');
        kids.add(Positioned(
          left: at.dx - (gilded ? 18 : 12),
          top: at.dy - (gilded ? 18 : 12),
          child: IgnorePointer(child: Transform.rotate(angle: (1 - k) * (i.isEven ? 0.8 : -0.8), child: ItemImage(bits[i], size: gilded ? 36 : 24))),
        ));
      }
      kids.add(img('prop_basket', basketAt + Offset(0, -10 * (1 - Curves.easeOutBack.transform(land))), ps * 1.05 * (0.6 + 0.4 * Curves.easeOutBack.transform(land)),
          opacity: land * (1 - gone), squash: 1 - 0.1 * bump));
      // the counts, rising over the basket
      if (v > 1.2) {
        final r = ((v - 1.2) / 0.5).clamp(0.0, 1.0);
        kids.add(Positioned(
          left: basketAt.dx - 90,
          width: 180,
          top: mouth.dy - 30 - 34 * Curves.easeOut.transform(r),
          child: IgnorePointer(
            child: Opacity(
              opacity: (math.min(1.0, r * 3) * (1 - gone)).clamp(0.0, 1.0),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (golden)
                  Container(
                    margin: const EdgeInsets.only(bottom: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF1B8), _gold]),
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Text('Golden harvest!', style: EvochiText.tag.copyWith(fontWeight: FontWeight.w900, fontSize: 12.5, color: const Color(0xFF6B4410))),
                  ),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  for (final e in harvest.$1.entries) ...[
                    ItemImage(e.key, size: 20),
                    Text('+${e.value}', style: EvochiText.number.copyWith(fontSize: 14, color: Colors.white, shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)])),
                    const SizedBox(width: 3),
                  ],
                ]),
              ]),
            ),
          ),
        ));
      }
    }

    // ---- its name, a moment, when tapped
    final ta = _tapAt;
    if (ta != null && t - ta < 2.4) {
      final k = t - ta;
      final what = switch (mood) {
        HelperMood.sleeping => 'napping',
        HelperMood.watering => 'watering',
        HelperMood.nurturing => 'nurturing the crop',
        HelperMood.butterfly => 'watching a butterfly',
        HelperMood.admiring || HelperMood.cheering => 'proud of this one',
        HelperMood.harvest => 'harvesting',
        _ => 'keeping watch',
      };
      kids.add(Positioned(
        left: head.dx - 80,
        width: 160,
        top: petRect.top - 30,
        child: IgnorePointer(
          child: Opacity(
            opacity: (math.min(k / 0.15, (2.4 - k) / 0.3)).clamp(0.0, 1.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xF7FFFBF2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _leaf, width: 1.5),
                  boxShadow: const [BoxShadow(color: Color(0x33281910), blurRadius: 4, offset: Offset(0, 2))],
                ),
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(text: w.pet.name, style: const TextStyle(fontWeight: FontWeight.w900)),
                    TextSpan(text: ' · $what'),
                  ]),
                  style: EvochiText.tag.copyWith(fontSize: 11.5, color: const Color(0xFF2F5A22)),
                ),
              ),
            ),
          ),
        ),
      ));
    }
    return Stack(clipBehavior: Clip.none, children: kids);
  }
}

/// The helper's magic: its crest glowing, an aura, a trail of green from its head to what it moves, the pour,
/// leaves circling it, the crop's growth pulse, a butterfly, Zs, a heart, and a Golden harvest's burst.
class _MagicPainter extends CustomPainter {
  _MagicPainter({
    required this.mood,
    required this.t,
    required this.u,
    required this.bed,
    required this.head,
    required this.body,
    required this.dir,
    required this.crest,
    required this.aura,
    required this.golden,
    required this.can,
    required this.canLit,
    required this.canTip,
    required this.fly,
    required this.ps,
    required this.pw,
  });
  final HelperMood mood;
  final double t, u, dir, crest, aura, canLit, canTip, ps, pw;
  final Rect bed;
  final Offset head, body;
  final bool golden;
  final Offset? can, fly;

  static const _magic = Color(0xFF9BE36A);

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

  void _trail(Canvas c, Offset from, Offset to, double a) {
    if (a <= 0.01) return;
    final mid = Offset((from.dx + to.dx) / 2, math.min(from.dy, to.dy) - bed.height * 0.3);
    for (var i = 0; i < 7; i++) {
      final k = ((i / 7) + t * 0.7) % 1.0;
      final p = Offset.lerp(Offset.lerp(from, mid, k)!, Offset.lerp(mid, to, k)!, k)!;
      if (i.isEven) {
        _leaf(c, p, 3.2, k * 6 + t, a * 0.85 * math.sin(k * math.pi));
      } else {
        c.drawCircle(p, 1.8, Paint()..color = const Color(0xFFD2F7A6).withValues(alpha: a * 0.85 * math.sin(k * math.pi)));
      }
    }
  }

  @override
  void paint(Canvas c, Size size) {
    // its crest, glowing
    if (crest > 0.01) {
      c.drawCircle(head, ps * 0.32, Paint()
        ..color = _magic.withValues(alpha: 0.55 * crest)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7));
    }
    // the aura round it
    if (aura > 0.01) {
      final r = Rect.fromCenter(center: body, width: pw * 1.25, height: pw * 0.95);
      c.drawOval(r, Paint()
        ..color = (golden && mood == HelperMood.harvest ? const Color(0xFFFFE08A) : _magic).withValues(alpha: 0.28 * aura * (0.8 + 0.2 * math.sin(t * 7)))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9));
    }
    final crop = Offset(bed.center.dx, bed.center.dy - bed.height * 0.05);
    double ramp(double a, double b) => ((u - a) / (b - a)).clamp(0.0, 1.0);
    switch (mood) {
      case HelperMood.watering:
        final cn = can;
        if (cn != null) {
          _trail(c, head, cn, canLit);
          c.drawCircle(cn, ps * 0.45, Paint()
            ..color = _magic.withValues(alpha: 0.22 * canLit)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8));
          // the pour: a few drops from the spout
          if (u > 1.1 && u < 2.25) {
            final spout = cn + Offset(dir * ps * 0.5, ps * 0.05);
            for (var i = 0; i < 6; i++) {
              final f = ((u * 2.2) + i / 6) % 1.0;
              final p = spout + Offset(dir * f * ps * 0.15 + math.sin(i * 7.0) * 2.5, f * bed.height * 0.5);
              c.drawOval(Rect.fromCenter(center: p, width: 3, height: 5), Paint()..color = const Color(0xFF7CC4F2).withValues(alpha: 0.9 * (1 - f * 0.6)));
            }
          }
        }
      case HelperMood.nurturing:
        // three leaves circling it, then the crop's pulse
        final a = aura;
        for (var i = 0; i < 3; i++) {
          final ang = t * 2.6 + i * 2 * math.pi / 3;
          final p = body + Offset(math.cos(ang) * pw * 0.62, math.sin(ang) * pw * 0.22 - pw * 0.1);
          _leaf(c, p, ps * 0.13, ang + math.pi / 2, a * (0.6 + 0.4 * math.sin(ang).abs()));
        }
        _trail(c, head, crop, a * 0.8);
        final k = ramp(1.5, 2.3);
        if (k > 0 && k < 1) {
          c.drawOval(Rect.fromCenter(center: crop, width: bed.width * (0.3 + 0.7 * k), height: bed.height * (0.25 + 0.6 * k)), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3
            ..color = const Color(0xFFC6F58A).withValues(alpha: 0.8 * (1 - k)));
          c.drawRect(bed.deflate(bed.height * 0.1), Paint()
            ..color = const Color(0xFFC6F58A).withValues(alpha: 0.18 * math.sin(k * math.pi))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10));
        }
      case HelperMood.harvest:
        final g0 = golden ? 0.5 : 0.0;
        final v = u - g0;
        if (v > 0.2 && v < 1.3) _trail(c, head, crop, (math.min((v - 0.2) / 0.2, (1.3 - v) / 0.2)).clamp(0.0, 1.0));
        // a Golden harvest's burst, gold and green, at the basket
        if (golden && v > 1.15 && v < 2.1) {
          final k = ((v - 1.15) / 0.95).clamp(0.0, 1.0);
          final at = Offset(bed.center.dx, bed.bottom - ps * 0.4);
          c.drawCircle(at, ps * (0.4 + 2.2 * Curves.easeOut.transform(k)), Paint()
            ..shader = RadialGradient(colors: [const Color(0xFFFFF3C0).withValues(alpha: 0.9 * (1 - k)), const Color(0xFFB8F07A).withValues(alpha: 0.4 * (1 - k)), const Color(0x00FFD45A)])
                .createShader(Rect.fromCircle(center: at, radius: ps * 2.6)));
          for (var i = 0; i < 10; i++) {
            final a = i * math.pi / 5 + 0.3;
            final d = ps * (0.5 + 2.0 * Curves.easeOut.transform(k));
            final p = at + Offset(math.cos(a) * d, math.sin(a) * d * 0.6);
            c.drawCircle(p, 2.4, Paint()..color = (i.isEven ? Colors.white : const Color(0xFFFFE08A)).withValues(alpha: 1 - k));
          }
        }
      case HelperMood.butterfly:
        final f = fly;
        if (f != null) {
          final flap = math.sin(t * 22).abs();
          final paint = Paint()..color = const Color(0xFFFFB3C9).withValues(alpha: math.min(1.0, math.min(u / 0.4, (5 - u) / 0.4)).clamp(0.0, 1.0));
          for (final sgn in [-1.0, 1.0]) {
            c.drawOval(Rect.fromCenter(center: f + Offset(sgn * 3.5 * (0.4 + 0.6 * flap), -1), width: 6 * (0.4 + 0.6 * flap), height: 7), paint);
          }
          c.drawLine(f + const Offset(0, -3), f + const Offset(0, 3), Paint()
            ..color = const Color(0xFF5A3A2A)
            ..strokeWidth = 1.4);
        }
      case HelperMood.sleeping:
        for (var i = 0; i < 2; i++) {
          final f = ((t / 3.4) + i / 2) % 1.0;
          final tp = TextPainter(
            text: TextSpan(text: 'z', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 9 + 6 * f, color: const Color(0xFF5B6B8A).withValues(alpha: 0.85 * math.sin(f * math.pi)))),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(c, head + Offset(-dir * (4 + f * 12) - tp.width / 2, -f * bed.height * 0.45 - 4));
        }
      case HelperMood.admiring:
        // a little heart, now and then
        final k = ((t * 0.5) % 1.0);
        if (k < 0.6) {
          final p = head + Offset(dir * 10, -8 - k * 18);
          final a = math.sin(k / 0.6 * math.pi) * 0.9;
          final hp = Path()
            ..moveTo(p.dx, p.dy + 3)
            ..cubicTo(p.dx - 6, p.dy - 2, p.dx - 3, p.dy - 6, p.dx, p.dy - 3)
            ..cubicTo(p.dx + 3, p.dy - 6, p.dx + 6, p.dy - 2, p.dx, p.dy + 3);
          c.drawPath(hp, Paint()..color = const Color(0xFFFF8FA8).withValues(alpha: a));
        }
      case HelperMood.cheering:
        for (var i = -1; i <= 1; i++) {
          final a = -math.pi / 2 + i * 0.5;
          final k = 0.5 + 0.5 * math.sin(t * 6 + i);
          final o = head + const Offset(0, -6);
          c.drawLine(o + Offset(math.cos(a), math.sin(a)) * 8, o + Offset(math.cos(a), math.sin(a)) * (15 + 3 * k), Paint()
            ..color = const Color(0xFFFFC93C)
            ..strokeWidth = 2.6
            ..strokeCap = StrokeCap.round);
        }
      case HelperMood.idle:
      case HelperMood.glancing:
        break;
    }
  }

  @override
  bool shouldRepaint(_MagicPainter old) => true;
}

/// One helper slot in the picker: in use, free, or opening at a Farming level.
class _Slot extends StatelessWidget {
  const _Slot({required this.open, required this.used, required this.level});
  final bool open, used;
  final int? level;
  @override
  Widget build(BuildContext context) => Container(
        height: 40,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: open ? (used ? const Color(0xFFE6F0D4) : const Color(0xFFF7FBEF)) : const Color(0xFFEDE4D6),
          border: Border.all(color: open ? _leaf : const Color(0xFFD2C2AA), width: 1.5),
        ),
        child: Center(
          child: open
              ? Icon(used ? Icons.eco_rounded : Icons.add_rounded, color: _leaf, size: 20)
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_rounded, size: 14, color: Color(0xFF9C8A70)),
                  const SizedBox(width: 2),
                  Text('Farming $level', style: EvochiText.tag.copyWith(fontSize: 11, color: const Color(0xFF8A7860))),
                ]),
        ),
      );
}

