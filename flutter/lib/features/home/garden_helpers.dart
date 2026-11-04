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
      return _Box(children: [
        _Face(helper, size: 44),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${helper.name} is tending this bed', style: EvochiText.cardTitle.copyWith(fontSize: 15)),
            Text(note, style: EvochiText.caption.copyWith(fontSize: 12.5)),
          ]),
        ),
        EvochiButton(
          label: can.length > 1 ? 'Change' : 'Rest',
          small: true,
          expand: false,
          tone: ButtonTone.cream,
          onPressed: () => can.length > 1 ? showHelperPicker(context, plotId) : _assign(c, plotId, null),
        ),
      ]);
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
