// The Garden's helpers and harvests: the helper row in a bed's panel (who tends it, or who could), the
// picker sheet, the little badge on a tended bed, and the harvest burst (the crop popping out of the bed
// in an arc, its count rising; a Golden harvest with a gold flash, a ring of glints and its banner).
// The rules are in game/home/home.dart (garden helpers).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/game_state.dart';
import '../../core/services/asset_manifest.dart';
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
    // one helper to a field: this field's could move here
    final inField = h.fieldHelper(s, h.fieldOf(plotId));
    if (inField != null) {
      final (bed, pet) = inField;
      return _Box(children: [
        const Icon(Icons.eco_rounded, color: _leaf, size: 26),
        const SizedBox(width: 8),
        Expanded(child: Text('${pet.name} tends bed ${_bedNo(bed)} in this field. One helper to a field.', style: EvochiText.caption.copyWith(fontSize: 12.5))),
        EvochiButton(label: 'Move ${pet.name} here', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => _assign(c, plotId, pet.id)),
      ]);
    }
    // every helper slot in use (an old save): the one at work could move here, and the next slot's level
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

/// Could [p] tend [plotId]: no other helper in that field, and a slot for it if it isn't at work already.
bool _canTake(GameState s, Pet p, String plotId) =>
    h.fieldHelper(s, h.fieldOf(plotId), except: p.id) == null && (h.bedOf(s, p.id) != null || h.helpersAtWork(s) < h.helperSlots(s));

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
          // one helper to a field: the garden's, and the lower field's once it opens
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
            child: Row(children: [
              Expanded(child: _Slot(label: 'Garden', open: true, used: h.fieldHelper(s, 'garden') != null, level: null)),
              const SizedBox(width: 6),
              Expanded(child: _Slot(label: 'Lower field', open: h.fieldOpen(s, 'lower'), used: h.fieldHelper(s, 'lower') != null, level: h.nextHelperSlot(s))),
            ]),
          ),
          for (final p in h.helperCandidates(s))
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () {
                  if (!_canTake(s, p, plotId)) return; // its field has a helper already
                  _assign(c, plotId, p.id);
                  Navigator.of(ctx).maybePop();
                },
                child: Opacity(
                  opacity: _canTake(s, p, plotId) ? 1 : 0.5,
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

/// Where the Forest Juvenile's eyes are on its standing frames (tools/art/walker_faces.py found them), by facing.
const _eyesAt = {
  0: [Offset(92.2, 154.7), Offset(141.5, 154.4)],
  7: [Offset(36.7, 130.1), Offset(72.2, 150.1)],
  1: [Offset(161.6, 149.4), Offset(197.0, 129.2)],
};

/// A held thing's telekinetic glow: a soft green copy of its outline behind it.
Widget _aura(Offset at, double size, double angle, double a, Color color, Widget child, {bool flip = false}) => Positioned(
      left: at.dx - size / 2,
      top: at.dy - size / 2,
      width: size,
      height: size,
      child: IgnorePointer(
        child: Opacity(
          opacity: a.clamp(0.0, 1.0),
          child: Transform(
            alignment: Alignment.bottomCenter,
            transform: Matrix4.identity()
              ..rotateZ(angle)
              ..scale(flip ? -1.14 : 1.14, 1.14, 1.0),
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 3, sigmaY: 3),
              child: ColorFiltered(colorFilter: ColorFilter.mode(color, BlendMode.srcIn), child: child),
            ),
          ),
        ),
      ),
    );

/// The same glow wrapped round a small held thing (a crop in flight).
Widget _held(Widget child, double size, double a, Color color) => Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
      if (a > 0.02)
        Opacity(
          opacity: a.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: 1.22,
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
              child: ColorFiltered(colorFilter: ColorFilter.mode(color, BlendMode.srcIn), child: child),
            ),
          ),
        ),
      child,
    ]);

/// What a helper is doing.
enum HelperMood { sleeping, idle, glancing, butterfly, admiring, cheering, watering, nurturing, harvest }

const _waterLen = 3.2, _nurtureLen = 2.8;

/// How long a harvest plays: a helper's (anticipation, the crop into the basket, a hop) or the plain burst.
int harvestMillis({required bool golden, required bool tended}) => tended ? (golden ? 3800 : 2600) : HarvestBurst.millis(golden);

// a helper's harvest, in seconds: a Golden one starts with its surprise; then (from 0) the gathering, the crop
// arcing into the basket, and a celebration (a Golden one first lifts its Gilded crop high over its head)
const _surprise = 0.6;
double _celebrateAt(bool golden) => golden ? 1.95 : 1.3;
double _celebrateEnd(bool golden) => golden ? 3.2 : 2.6;

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
    this.scale = 1.0,
  });
  final double scale; // (the lower field's small beds: a smaller helper)
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
  _Walker? _art; // its in-world sprite (the walkable maps' 8 directions)
  int _facing = 7;
  double _turnAt = -9;

  double get _clock => (_a.lastElapsedDuration?.inMicroseconds ?? 0) / 1e6;

  @override
  void initState() {
    super.initState();
    if (widget.animate) _a.repeat();
    _a.addListener(_lean);
    if (widget.harvest != null) _harvestAt = 0;
    _loadArt();
  }

  Future<void> _loadArt() async {
    final a = await _Walker.load(widget.pet);
    if (mounted) setState(() => _art = a);
  }

  @override
  void didUpdateWidget(PlotActor old) {
    super.didUpdateWidget(old);
    if (widget.pet.id != old.pet.id || widget.rank != old.rank) _plan = _Plan(widget.pet, widget.rank);
    if (widget.pet.id != old.pet.id || widget.pet.stage != old.pet.stage) _loadArt();
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
    final toward = _leftBed ? v : -v; // (toward its helper: the left beds' stand on their left)
    if ((n.value - toward).abs() > 0.002) n.value = toward;
  }

  bool get _leftBed => widget.bed.center.dx < widget.plate.width / 2;

  void _tap() {
    setState(() => _tapAt = _clock);
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) => _art == null ? const SizedBox.shrink() : AnimatedBuilder(animation: _a, builder: (ctx, _) => _frame(widget.animate ? _clock : 0.0));

  Widget _frame(double t) {
    final w = widget;
    final bed = w.bed;
    // every helper stands on the walkway at its bed's outer front corner, turned toward it: the left beds' on
    // their left, the right beds' on their right, so each is plainly its own bed's (and the path between is clear)
    final left = _leftBed;
    final dir = left ? 1.0 : -1.0; // toward the bed
    final base = left ? 1 : 7; // its facing: down-right, or down-left, toward the bed
    final side = left ? 2 : 6; // side on, watching its can over the bed
    // its in-world sprite's frame: where its feet are (so it stands on them, and turns on them)
    final art = _art!;
    final gx = art.gx / art.fw, gy = art.gy / art.fh;
    final ph = bed.height * 1.08 * w.scale; // the frame (the body is about half of it)
    final pw = ph * art.fw / art.fh;
    final fx = (left ? bed.left - pw * 0.26 : bed.right + pw * 0.26).clamp(pw * gx + 2, w.plate.width - pw * (1 - gx) - 2);
    final foot = Offset(fx, bed.bottom - bed.height * 0.02);
    final ps = bed.height * 0.72 * w.scale; // a prop's size (the voxel props sit in their frames with a margin)
    final rest = Offset(foot.dx + dir * pw * 0.46, foot.dy - ps * 0.12); // the can, on the bed's front corner
    final over = Offset(bed.center.dx - dir * bed.width * 0.06, bed.top + bed.height * 0.12);
    final basketAt = Offset(left ? bed.left + bed.width * 0.24 : bed.right - bed.width * 0.24, bed.bottom - ps * 0.2);

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
    var crest = 0.0; // its crest glowing as it works
    var aura = 0.0;
    double ramp(double a, double b) => ((u - a) / (b - a)).clamp(0.0, 1.0);
    // butterfly path (in plate px), for its eyes to follow
    Offset? fly;
    switch (mood) {
      case HelperMood.sleeping:
        // curled up for a nap
        sy *= 0.93;
        sx *= 1.03;
      case HelperMood.idle:
        break;
      case HelperMood.glancing:
        tilt = 0.06 * dir * math.sin(ramp(0, 1.4) * math.pi);
      case HelperMood.butterfly:
        final k = u / 5.0;
        fly = Offset(
          foot.dx + dir * pw * (0.2 + 0.9 * math.sin(k * math.pi)) + 12 * math.sin(u * 3.1),
          foot.dy - ph * (1.05 + 0.25 * math.sin(u * 1.7)) - 10 * math.sin(u * 5.3),
        );
        tilt = ((fly.dx - foot.dx) / (pw * 1.2)).clamp(-1.0, 1.0) * 0.07;
      case HelperMood.admiring:
        tilt = 0.04 * dir;
      case HelperMood.cheering:
        final hop = math.max(0.0, math.sin(u * 2 * math.pi / 0.65));
        lift = ph * 0.1 * hop * (0.6 + _plan.expressive * 0.6);
        sy *= 1 + 0.05 * hop;
      case HelperMood.watering:
        crest = ramp(0, 0.3) * (1 - ramp(2.4, 3.0));
        if (u < 0.3) sy *= 1 - 0.05 * math.sin(ramp(0, 0.3) * math.pi);
        // its eyes on the can: a tilt toward where it is
        tilt = 0.07 * dir * math.sin(ramp(0.2, 3.0) * math.pi);
      case HelperMood.nurturing:
        crest = ramp(0, 0.3) * (1 - ramp(2.3, 2.8));
        aura = ramp(0.25, 0.6) * (1 - ramp(2.2, 2.8));
        if (u < 0.3) sy *= 1 - 0.05 * math.sin(ramp(0, 0.3) * math.pi);
      case HelperMood.harvest:
        final g0 = golden ? _surprise : 0.0;
        if (golden && u < g0) {
          // Golden: a jolt of surprise (a start, a lean back), and it turns to you
          tilt = -0.12 * dir * math.sin(ramp(0, g0) * math.pi);
          lift = ph * 0.09 * math.sin(ramp(0, 0.28) * math.pi);
          sy *= 1 + 0.06 * math.sin(ramp(0, 0.28) * math.pi);
        } else {
          final v = u - g0;
          final ch = golden ? 1.85 : 1.25; // the magic lets go
          double rv(double a, double b) => ((v - a) / (b - a)).clamp(0.0, 1.0);
          crest = rv(0, 0.25) * (1 - rv(ch - 0.1, ch + 0.25));
          aura = rv(0.2, 0.5) * (1 - rv(ch - 0.1, ch + 0.25));
          if (v < 0.25) sy *= 1 - 0.07 * math.sin(v / 0.25 * math.pi); // it gathers itself
          // Golden: it lifts its Gilded crop high, with a big jump and a spin
          if (golden && v > 0.55 && v < 1.25) {
            final k = (v - 0.55) / 0.7;
            lift = ph * 0.32 * math.sin(k * math.pi);
            sy *= 1 + 0.07 * math.sin(k * math.pi);
            sx *= 1 - 0.04 * math.sin(k * math.pi);
          }
          // and it celebrates: two happy hops, the second with a spin, then a wiggle
          final c0 = _celebrateAt(golden), big = golden ? 1.35 : 1.0;
          if (v > c0 && v < c0 + 0.4) {
            final k = (v - c0) / 0.4;
            lift = ph * 0.15 * big * math.sin(k * math.pi);
            sy *= 1 + 0.07 * math.sin(k * math.pi);
          } else if (v >= c0 + 0.45 && v < c0 + 0.95) {
            final k = (v - c0 - 0.45) / 0.5;
            lift = ph * 0.22 * big * math.sin(k * math.pi);
            sy *= 1 + 0.08 * math.sin(k * math.pi);
          } else if (v >= c0 + 0.95 && v < _celebrateEnd(golden)) {
            tilt = 0.07 * math.sin((v - c0) * 18) * (1 - rv(c0 + 0.95, _celebrateEnd(golden)));
          }
          // landing: a squash
          if (v >= c0 + 0.4 && v < c0 + 0.45) sy *= 0.92;
        }
    }
    // its face, as it feels it (drawn on its map sprite where its face shows)
    final blink = ((t + _plan.phase) % _plan.blinkEvery) < 0.13;
    var expr = blink ? 'blink' : 'default';
    switch (mood) {
      case HelperMood.sleeping:
        expr = 'sleepy';
      case HelperMood.glancing:
        expr = 'curious';
      case HelperMood.butterfly:
        expr = u < 4.4 ? 'curious' : 'happy';
      case HelperMood.admiring:
        expr = blink ? 'blink' : 'affectionate';
      case HelperMood.cheering:
        expr = 'excited';
      case HelperMood.watering:
        expr = u < 0.9 ? 'determined' : (u < 2.4 ? 'happy' : expr);
      case HelperMood.nurturing:
        expr = u < 0.3 ? 'determined' : 'affectionate';
      case HelperMood.harvest:
        final v = u - (golden ? _surprise : 0.0);
        final c0 = _celebrateAt(golden), c1 = _celebrateEnd(golden);
        if (golden && u < _surprise + 0.1) {
          expr = 'surprised';
        } else if (v < 0.55) {
          expr = 'determined';
        } else if (golden && v < 1.85) {
          expr = 'excited';
        } else if (v < c1) {
          expr = v >= c0 && golden ? 'excited' : 'happy';
        }
      case HelperMood.idle:
        break;
    }
    final petRect = Rect.fromLTWH(foot.dx - pw * gx, foot.dy - ph * gy - lift, pw, ph);
    final head = Offset(foot.dx + dir * pw * 0.06, foot.dy - lift - ph * 0.47);
    final body = Offset(foot.dx + dir * pw * 0.04, foot.dy - lift - ph * 0.24);
    // which way it faces (the sheet's rows: 0 toward you, then round clockwise as seen from above: 6 left, 7 down-left)
    var face = base;
    switch (mood) {
      case HelperMood.sleeping:
      case HelperMood.cheering:
        face = 0;
      case HelperMood.harvest:
        final g0 = golden ? _surprise : 0.0;
        final v = u - g0;
        final c0 = _celebrateAt(golden);
        int spin(double k) => (base + (k * 8).floor() * (left ? -1 : 1)) % 8;
        if (golden && u < g0) {
          face = 0;
        } else if (golden && v > 0.6 && v < 1.2) {
          face = spin((v - 0.6) / 0.6);
        } else if (v >= c0 + 0.45 && v < c0 + 0.95) {
          face = spin((v - c0 - 0.45) / 0.5);
        } else if (v >= c0) {
          face = 0;
        } else {
          face = base;
        }
      case HelperMood.glancing:
        face = u < 0.7 ? 0 : base;
      case HelperMood.watering:
        face = u > 0.6 && u < 2.6 ? side : base; // watching its can up over the crop
      case HelperMood.butterfly:
        final f = fly;
        if (f != null) {
          final a = math.atan2(f.dy - foot.dy, f.dx - foot.dx); // screen angle to the butterfly
          // nearest of the eight (0 is down the screen)
          face = (((math.pi / 2 - a) / (math.pi / 4)).round() % 8 + 8) % 8;
        }
      default:
        face = base;
    }
    if (face != _facing) {
      _facing = face;
      _turnAt = t;
    }
    // a little shuffle of its feet as it turns
    final turning = t - _turnAt;
    final spinning = mood == HelperMood.harvest && lift > ph * 0.05;
    final col = !spinning && turning >= 0 && turning < 0.36 ? 1 + (turning / 0.06).floor() % 12 : 0;

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

      Offset at(double u) {
        if (u < 0.3) {
          // grabbed: it trembles, then lifts a hair off the path
          final k = (u / 0.3).clamp(0.0, 1.0);
          return rest + Offset(math.sin(u * 70) * 1.6 * k, -4 * k);
        } else if (u < 0.9) {
          return arc(rest + const Offset(0, -4), over, (u - 0.3) / 0.6);
        } else if (u < 2.4) {
          // held over the crop, with a little overshoot as it arrives, bobbing
          final k = ((u - 0.9) / 0.35).clamp(0.0, 1.0);
          return over + Offset(0, -6 * math.sin(k * math.pi) * (1 - k) + math.sin(t * 5) * 1.8);
        } else if (u < 3.0) {
          return arc(over, rest + const Offset(0, -4), (u - 2.4) / 0.6);
        }
        return rest + Offset(0, -4 * (1 - ((u - 3.0) / 0.2).clamp(0.0, 1.0)) - 3 * math.sin(((u - 3.0) / 0.2).clamp(0.0, 1.0) * math.pi)); // set down, a bounce
      }

      canAt = at(u);
      // it swings with its motion, as a held thing does
      final vel = (at(u + 0.03) - at(u - 0.03)).dx / 0.06;
      canTip = (ramp(0.9, 1.15) - ramp(2.15, 2.4)) * 0.62 + (vel / 900).clamp(-0.35, 0.35) * dir + 0.06 * math.sin(t * 4.2) * ramp(0.3, 0.5) * (1 - ramp(2.9, 3.1));
      canLit = ramp(0.2, 0.35) * (1 - ramp(2.95, 3.2));
    }
    final showCan = w.tending && !w.p.empty && mood != HelperMood.harvest;

    // contact shadows: its own (smaller and fainter as it hops), the can's (on the path, or on the soil under it
    // as it floats), the basket's
    final up = (lift / (ph * 0.2)).clamp(0.0, 1.0);
    final soil = bed.center.dy + bed.height * 0.18;
    final shadows = <(Offset, double, double)>[
      (foot + const Offset(0, 1), pw * 0.5 * (1 - 0.3 * up), 0.3 * (1 - 0.45 * up)),
      if (showCan) canOut && u > 0.35 && u < 2.95 ? (Offset(canAt.dx, soil), ps * 0.5, 0.12) : (Offset(canAt.dx, rest.dy + ps * 0.4), ps * 0.62, 0.24),
    ];

    // ---- the harvest's moments (positions the painter and the widgets share)
    final crop = Offset(bed.center.dx, bed.center.dy - bed.height * 0.05);
    final held = head + Offset(0, -ph * 0.42); // a Golden crop, lifted over its head
    Offset? gilded; // where the Gilded crop is
    var gildedA = 0.0, gildedSize = 1.0, gildedSpin = 0.0;
    var link = Offset.zero, linkA = 0.0;
    var linkGold = false;
    if (canOut) {
      link = canAt;
      linkA = canLit;
    } else if (mood == HelperMood.nurturing) {
      link = crop;
      linkA = aura;
    }
    if (mood == HelperMood.harvest && harvest != null) {
      final v = u - (golden ? _surprise : 0.0);
      double rv(double a, double b) => ((v - a) / (b - a)).clamp(0.0, 1.0);
      if (golden && v >= 0) {
        final mouthAt = basketAt - Offset(0, ps * 0.22);
        if (v < 0.5) {
          final k = Curves.easeOut.transform(rv(0, 0.5));
          gilded = Offset.lerp(Offset(crop.dx, crop.dy + bed.height * 0.08), held, k);
          gildedSize = 0.6 + 0.6 * k;
        } else if (v < 1.5) {
          gilded = held + Offset(math.sin(t * 3) * 2, math.sin(t * 4.4) * 3) + Offset(0, -lift * 0.0);
          gildedSize = 1.2 + 0.05 * math.sin(t * 6);
          gildedSpin = 0.15 * math.sin(t * 2.5);
        } else if (v < 1.85) {
          final k = Curves.easeInOutSine.transform(rv(1.5, 1.85));
          final ctl = Offset((held.dx + mouthAt.dx) / 2, math.min(held.dy, mouthAt.dy) - bed.height * 0.2);
          gilded = Offset.lerp(Offset.lerp(held, ctl, k)!, Offset.lerp(ctl, mouthAt, k)!, k);
          gildedSize = 1.2 - 0.45 * k;
        }
        gildedA = v < 1.85 ? 1.0 : 0.0;
        if (gilded != null) {
          link = gilded;
          linkA = rv(0, 0.15) * (1 - rv(1.75, 1.9));
          linkGold = true;
        }
      } else if (!golden) {
        link = crop;
        linkA = rv(0.2, 0.45) * (1 - rv(1.1, 1.3));
      }
    }

    final kids = <Widget>[
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _MagicPainter(
              mood: mood, t: t, u: u, bed: bed, head: head, body: body, foot: foot, dir: dir, crest: crest, aura: aura, golden: golden,
              can: canOut ? canAt : null, canLit: canLit, canTip: canTip, fly: fly, ps: ps, pw: pw, ph: ph, shadows: shadows,
              link: link, linkA: linkA, linkGold: linkGold, held: gilded, basket: basketAt,
              eyes: [
                for (final e in (_eyesAt[_facing] ?? const <Offset>[]))
                  Offset(petRect.left + e.dx / art.fw * pw, petRect.top + e.dy / art.fh * ph),
              ],
              grabbed: canOut ? (u > 0.28 && u < 0.62 ? (u - 0.28) / 0.34 : (u > 2.92 && u < 3.25 ? -(u - 2.92) / 0.33 : 0)) : 0,
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
              // it breathes, sways and turns on its feet
              alignment: Alignment(gx * 2 - 1, gy * 2 - 1),
              transform: Matrix4.identity()
                ..rotateZ(tilt)
                ..multiply(Matrix4.skewX(sway))
                ..scale(sx, sy, 1),
              // a touch of shade at its feet, as the ground would give it
              child: ShaderMask(
                blendMode: BlendMode.modulate,
                shaderCallback: (r) => LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: const [Colors.white, Colors.white, Color(0xFFCFC6B8)],
                  stops: [0, (gy - 0.14).clamp(0.0, 1.0), gy],
                ).createShader(r),
                child: CustomPaint(size: Size(pw, ph), painter: _WalkerPainter(art, _facing, col, expr)),
              ),
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
    if (showCan) {
      final sz = ps * (canOut && u > 0.3 && u < 3.0 ? 1.1 : 0.9);
      if (canOut && canLit > 0.02) kids.add(_aura(canAt, sz, canTip * dir, canLit, const Color(0xFF9CF06A), Image.asset('assets/art/home/prop_watering_can.webp', excludeFromSemantics: true), flip: left));
      kids.add(img('prop_watering_can', canAt, sz, angle: canTip * dir, flip: left));
    }

    // ---- its harvest: the basket by the bed, the crop lifting into it, the counts over it
    if (mood == HelperMood.harvest && harvest != null) {
      final g0 = golden ? _surprise : 0.0;
      final v = u - g0;
      final land = ((v - 0.25) / 0.3).clamp(0.0, 1.0);
      final gone = ((v - (hLen - g0 - 0.3)) / 0.3).clamp(0.0, 1.0);
      final mouth = basketAt - Offset(0, ps * 0.22);
      // the pieces: up to five of each (the Gilded one is lifted on its own)
      final bits = <String>[];
      for (final e in harvest.$1.entries.where((e) => !e.key.startsWith('gilded_'))) {
        for (var i = 0; i < math.min(e.value, 5); i++) {
          bits.add(e.key);
        }
      }
      var bump = 0.0;
      final first = golden ? 0.75 : 0.55;
      for (var i = 0; i < bits.length; i++) {
        final s0 = first + i * (0.6 / math.max(1, bits.length));
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
          child: IgnorePointer(
            child: Transform.rotate(
              angle: (1 - k) * (i.isEven ? 0.8 : -0.8),
              child: _held(ItemImage(bits[i], size: gilded ? 36 : 24), gilded ? 36 : 24, math.sin(k * math.pi), const Color(0xFF9CF06A)),
            ),
          ),
        ));
      }
      // the Gilded crop, lifted on its own: glowing, turning, over its head, then into the basket
      final gid = harvest.$1.keys.where((k) => k.startsWith('gilded_')).firstOrNull;
      final gAt = gilded;
      if (gid != null && gAt != null && gildedA > 0) {
        final sz = 34 * gildedSize;
        kids.add(Positioned(
          left: gAt.dx - sz / 2,
          top: gAt.dy - sz / 2,
          child: IgnorePointer(child: Transform.rotate(angle: gildedSpin, child: _held(ItemImage(gid, size: sz), sz, 1, const Color(0xFFFFD45A)))),
        ));
      }
      if (golden && v > 1.85 && v < 1.95) bump = math.max(bump, math.sin((v - 1.85) / 0.1 * math.pi));
      shadows.add((basketAt + Offset(0, ps * 0.5), ps * 0.85, 0.24 * land * (1 - gone)));
      kids.add(img('prop_basket', basketAt + Offset(0, -10 * (1 - Curves.easeOutBack.transform(land))), ps * 1.05 * (0.6 + 0.4 * Curves.easeOutBack.transform(land)),
          opacity: land * (1 - gone), squash: 1 - 0.1 * bump));
      // the counts, rising over the basket
      final countsAt = golden ? 1.9 : 1.2;
      if (v > countsAt) {
        final r = ((v - countsAt) / 0.5).clamp(0.0, 1.0);
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
    required this.ph,
    required this.shadows,
    required this.foot,
    required this.link,
    required this.linkA,
    required this.linkGold,
    required this.held,
    required this.basket,
    required this.eyes,
    required this.grabbed,
  });
  final List<Offset> eyes; // its eyes, on screen (they glow as it casts)
  final double grabbed; // 0..1 the moment a held thing is taken up; -1..0 set down
  final List<(Offset, double, double)> shadows; // where, how wide, how dark
  final Offset foot, link, basket;
  final double linkA, ph;
  final bool linkGold;
  final Offset? held; // a Golden crop it's lifting
  final HelperMood mood;
  final double t, u, dir, crest, aura, canLit, canTip, ps, pw;
  final Rect bed;
  final Offset head, body;
  final bool golden;
  final Offset? can, fly;


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

  static const _glowA = Color(0xFFB8F07A), _glowB = Color(0xFFE8FFD2), _goldA = Color(0xFFFFD45A), _goldB = Color(0xFFFFF4C8);

  static Paint _plus(Color c, {double blur = 0, double stroke = 0}) {
    final p = Paint()
      ..color = c
      ..blendMode = BlendMode.plus;
    if (blur > 0) p.maskFilter = MaskFilter.blur(BlurStyle.normal, blur);
    if (stroke > 0) {
      p
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round;
    }
    return p;
  }

  static void _star(Canvas c, Offset at, double r, Paint p) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 - math.pi / 2;
      final rr = i.isEven ? r : r * 0.32;
      final q = at + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(q.dx, q.dy) : path.lineTo(q.dx, q.dy);
    }
    c.drawPath(path..close(), p);
  }

  Offset _bez(Offset a, Offset m, Offset b, double k) => Offset.lerp(Offset.lerp(a, m, k)!, Offset.lerp(m, b, k)!, k)!;

  /// The telekinesis: a ribbon of light from its crest to what it holds (glow, a bright core, motes and leaves
  /// riding along it), and a halo with sparkles orbiting the thing held.
  void _tether(Canvas c, Offset from, Offset to, double a, {bool gold = false}) {
    if (a <= 0.01) return;
    final ca = gold ? _goldA : _glowA, cb = gold ? _goldB : _glowB;
    final mid = Offset((from.dx + to.dx) / 2, math.min(from.dy, to.dy) - bed.height * 0.32 + math.sin(t * 3) * 3);
    // the ribbon: a glow round it, and two bright strands twisting round each other, thick at its crest and
    // thinning toward what it holds
    const n = 28;
    final pts = <Offset>[], nrm = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final k = i / n;
      final q = _bez(from, mid, to, k);
      final d = _bez(from, mid, to, math.min(1.0, k + 0.01)) - _bez(from, mid, to, math.max(0.0, k - 0.01));
      final len = d.distance == 0 ? 1.0 : d.distance;
      pts.add(q);
      nrm.add(Offset(-d.dy / len, d.dx / len));
    }
    final glow = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (final q in pts.skip(1)) {
      glow.lineTo(q.dx, q.dy);
    }
    c.drawPath(glow, _plus(ca.withValues(alpha: 0.3 * a), blur: 6, stroke: 12));
    for (final side in [1.0, -1.0]) {
      for (var i = 0; i < n; i++) {
        final k = i / n;
        final amp = 3.2 * math.sin(k * math.pi);
        Offset at(int j) => pts[j] + nrm[j] * (side * amp * math.sin(j / n * math.pi * 5 - t * 10));
        c.drawLine(at(i), at(i + 1), _plus(cb.withValues(alpha: 0.85 * a), stroke: 2.6 - 1.6 * k));
      }
    }
    // pulses running out along it, from it to the thing held
    for (var i = 0; i < 3; i++) {
      final k = ((t * 1.3) + i / 3) % 1.0;
      final q = _bez(from, mid, to, k);
      c.drawCircle(q, 4.5 * (1 - k * 0.5), _plus(cb.withValues(alpha: a * 0.9 * math.sin(k * math.pi)), blur: 2));
    }
    for (var i = 0; i < 7; i++) {
      final k = ((i / 7) + t * 0.85) % 1.0;
      final q = _bez(from, mid, to, k);
      if (i % 3 == 0) {
        _leaf(c, q, 3.6, k * 7 + t * 2, a * math.sin(k * math.pi));
      } else {
        c.drawCircle(q, 2.2, _plus(cb.withValues(alpha: a * math.sin(k * math.pi))));
      }
    }
    // the halo round what it holds
    c.drawCircle(to, ps * 0.5, _plus(ca.withValues(alpha: 0.3 * a), blur: 10));
    for (var i = 0; i < 5; i++) {
      final ang = t * 3.2 + i * 2 * math.pi / 5;
      final q = to + Offset(math.cos(ang) * ps * 0.46, math.sin(ang) * ps * 0.2);
      final tw = 0.5 + 0.5 * math.sin(t * 9 + i * 2);
      _star(c, q, 2.6 + 1.6 * tw, _plus(cb.withValues(alpha: a * (0.4 + 0.6 * tw))));
    }
  }

  @override
  void paint(Canvas c, Size size) {
    for (final (at, wd, a) in shadows) {
      if (a <= 0.01) continue;
      c.drawOval(Rect.fromCenter(center: at, width: wd, height: wd * 0.3), Paint()
        ..color = const Color(0xFF3A2A14).withValues(alpha: a)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2.5));
    }
    double ramp(double a, double b) => ((u - a) / (b - a)).clamp(0.0, 1.0);
    final g0 = golden ? _surprise : 0.0;
    final v = u - g0; // (a harvest's own clock)

    // the spell taking hold: a ring of light opening at its feet as its crest lights
    if (crest > 0.01 && crest < 0.999) {
      final k = crest;
      c.drawOval(Rect.fromCenter(center: foot, width: pw * (0.5 + 0.9 * k), height: pw * (0.16 + 0.28 * k)),
          _plus((golden && mood == HelperMood.harvest ? _goldA : _glowA).withValues(alpha: 0.7 * (1 - k)), stroke: 2.5));
    }
    // its aura
    if (aura > 0.01) {
      final r = Rect.fromCenter(center: body, width: pw * 1.2, height: pw * 0.95);
      c.drawOval(r, _plus((golden && mood == HelperMood.harvest ? _goldA : _glowA).withValues(alpha: 0.24 * aura * (0.8 + 0.2 * math.sin(t * 7))), blur: 10));
    }
    // a Golden crop's pillar of light out of the bed
    if (mood == HelperMood.harvest && golden && v > -0.1 && v < 0.8) {
      final k = ((v + 0.1) / 0.9).clamp(0.0, 1.0);
      final a = math.sin(k * math.pi);
      final col = Rect.fromCenter(center: Offset(bed.center.dx, bed.center.dy - bed.height * 0.9), width: bed.width * (0.25 + 0.1 * a), height: bed.height * 2.4);
      c.drawRect(col, _plus(Colors.white, blur: 8)..shader = LinearGradient(begin: Alignment.bottomCenter, end: Alignment.topCenter, colors: [_goldB.withValues(alpha: 0.75 * a), _goldA.withValues(alpha: 0.35 * a), const Color(0x00FFD45A)]).createShader(col));
    }
    // what it holds by magic
    _tether(c, head, link, linkA, gold: linkGold);
    // taken up: a burst of sparks round it; set down: a puff of leaves
    if (grabbed > 0 && can != null) {
      final k = grabbed;
      for (var i = 0; i < 10; i++) {
        final ang = i * math.pi / 5 + 0.2;
        final q = can! + Offset(math.cos(ang), math.sin(ang) * 0.7) * ps * (0.25 + 0.55 * Curves.easeOut.transform(k));
        _star(c, q, 3.2 * (1 - k) + 1, _plus(_glowB.withValues(alpha: 1 - k)));
      }
      c.drawCircle(can!, ps * (0.3 + 0.4 * k), _plus(_glowA.withValues(alpha: 0.5 * (1 - k)), stroke: 2.5));
    } else if (grabbed < 0 && can != null) {
      final k = -grabbed;
      for (var i = 0; i < 6; i++) {
        final ang = math.pi + i * math.pi / 5;
        final q = can! + Offset(math.cos(ang) * ps * (0.2 + 0.4 * k), ps * 0.35 - math.sin(ang).abs() * ps * 0.2 * k);
        _leaf(c, q, 3.2, ang + k * 3, 1 - k);
      }
    }
    // its eyes, lit as it casts
    if (crest > 0.05) {
      for (final e in eyes) {
        c.drawCircle(e, 3.6, _plus((golden && mood == HelperMood.harvest ? _goldA : _glowA).withValues(alpha: 0.75 * crest), blur: 2.5));
      }
    }
    // its crest, lit
    if (crest > 0.01) {
      final cc = golden && mood == HelperMood.harvest ? _goldA : _glowA;
      c.drawCircle(head, ps * 0.34, _plus(cc.withValues(alpha: 0.6 * crest), blur: 8));
      c.drawCircle(head, ps * 0.12, _plus(_glowB.withValues(alpha: 0.8 * crest), blur: 3));
      for (var i = 0; i < 4; i++) {
        final f = ((t * 1.4) + i / 4) % 1.0;
        c.drawCircle(head + Offset(math.sin(i * 2.3 + t) * 6, -f * ph * 0.25), 1.6, _plus(_glowB.withValues(alpha: crest * math.sin(f * math.pi))));
      }
    }
    final crop = Offset(bed.center.dx, bed.center.dy - bed.height * 0.05);
    switch (mood) {
      case HelperMood.watering:
        final cn = can;
        if (cn != null && u > 1.1 && u < 2.3) {
          // the pour: drops from the rose, a splash where they land
          final spout = cn + Offset(dir * ps * 0.5, ps * 0.05);
          for (var i = 0; i < 8; i++) {
            final f = ((u * 2.2) + i / 8) % 1.0;
            final p = spout + Offset(dir * f * ps * 0.15 + math.sin(i * 7.0) * 3, f * bed.height * 0.5);
            c.drawOval(Rect.fromCenter(center: p, width: 3, height: 5.5), Paint()..color = const Color(0xFF8CCDF5).withValues(alpha: 0.95 * (1 - f * 0.5)));
            if (f > 0.82) {
              final k = (f - 0.82) / 0.18;
              final land = spout + Offset(dir * ps * 0.15 + math.sin(i * 7.0) * 3, bed.height * 0.52);
              c.drawOval(Rect.fromCenter(center: land, width: 4 + 10 * k, height: 2 + 4 * k), Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.4
                ..color = const Color(0xFFBFE4FA).withValues(alpha: 0.9 * (1 - k)));
            }
          }
        }
      case HelperMood.nurturing:
        // leaves circling it, then the crop's pulse and motes rising out of it
        for (var i = 0; i < 3; i++) {
          final ang = t * 2.6 + i * 2 * math.pi / 3;
          final p = body + Offset(math.cos(ang) * pw * 0.6, math.sin(ang) * pw * 0.2 - pw * 0.08);
          _leaf(c, p, ps * 0.1, ang + math.pi / 2, aura * (0.6 + 0.4 * math.sin(ang).abs()));
        }
        final k = ramp(1.5, 2.3);
        if (k > 0 && k < 1) {
          c.drawOval(Rect.fromCenter(center: crop, width: bed.width * (0.3 + 0.75 * k), height: bed.height * (0.25 + 0.65 * k)), _plus(_glowA.withValues(alpha: 0.9 * (1 - k)), stroke: 3));
          c.drawRect(bed.deflate(bed.height * 0.08), _plus(_glowA.withValues(alpha: 0.22 * math.sin(k * math.pi)), blur: 10));
          for (var i = 0; i < 8; i++) {
            final x = bed.left + bed.width * (0.12 + 0.76 * ((i * 0.39) % 1));
            final y = bed.center.dy - k * bed.height * (0.6 + 0.3 * ((i * 0.53) % 1));
            _star(c, Offset(x, y), 2.4, _plus(_glowB.withValues(alpha: math.sin(k * math.pi))));
          }
        }
      case HelperMood.harvest:
        if (golden && u < g0 + 0.15) {
          // "!": a Golden one surprises it
          final k = (u / 0.12).clamp(0.0, 1.0);
          final at = head + Offset(-pw * 0.25, -16 - 6 * Curves.easeOutBack.transform(k));
          final a = 1 - ((u - g0 + 0.05) / 0.2).clamp(0.0, 1.0);
          c.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: at, width: 16, height: 19), const Radius.circular(6)), Paint()..color = Colors.white.withValues(alpha: a));
          final tp = TextPainter(
            text: TextSpan(text: '!', style: TextStyle(fontFamily: 'Nunito', fontWeight: FontWeight.w900, fontSize: 15, color: const Color(0xFFE0A21E).withValues(alpha: a))),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(c, at - Offset(tp.width / 2, tp.height / 2));
        }
        // the Gilded crop held high: a sunburst behind it
        final h = held;
        if (golden && h != null && v > 0.3 && v < 1.75) {
          final a = math.min(((v - 0.3) / 0.25).clamp(0.0, 1.0), ((1.75 - v) / 0.25).clamp(0.0, 1.0));
          for (var i = 0; i < 12; i++) {
            final ang = t * 0.9 + i * math.pi / 6;
            final r1 = ps * 0.35, r2 = ps * (1.15 + 0.12 * math.sin(t * 4 + i));
            final path = Path()
              ..moveTo(h.dx + math.cos(ang - 0.09) * r1, h.dy + math.sin(ang - 0.09) * r1)
              ..lineTo(h.dx + math.cos(ang) * r2, h.dy + math.sin(ang) * r2)
              ..lineTo(h.dx + math.cos(ang + 0.09) * r1, h.dy + math.sin(ang + 0.09) * r1)
              ..close();
            c.drawPath(path, _plus(_goldB.withValues(alpha: 0.35 * a), blur: 2));
          }
          c.drawCircle(h, ps * 0.55, _plus(_goldA.withValues(alpha: 0.45 * a), blur: 12));
        }
        // landing in the basket: a burst, and gold confetti and leaves raining down
        if (golden && v > 1.85 && v < 3.4) {
          final k = ((v - 1.85) / 1.55).clamp(0.0, 1.0);
          final at = basket - Offset(0, ps * 0.2);
          final b = ((v - 1.85) / 0.5).clamp(0.0, 1.0);
          if (b < 1) {
            c.drawCircle(at, ps * (0.3 + 2.0 * Curves.easeOut.transform(b)), _plus(Colors.white, blur: 6)
              ..shader = RadialGradient(colors: [_goldB.withValues(alpha: 0.9 * (1 - b)), _glowA.withValues(alpha: 0.4 * (1 - b)), const Color(0x00FFD45A)])
                  .createShader(Rect.fromCircle(center: at, radius: ps * 2.4)));
          }
          final rnd = math.Random(7);
          for (var i = 0; i < 22; i++) {
            final vx = (rnd.nextDouble() - 0.5) * ps * 5, vy = -ps * (2.2 + rnd.nextDouble() * 2.2);
            final tt = k * 1.55;
            final q = at + Offset(vx * tt, vy * tt + ps * 4.2 * tt * tt);
            final a = (1 - k) * 1.0;
            final spin = tt * (4 + i % 3) + i;
            if (i % 3 == 0) {
              _leaf(c, q, 3.5, spin, a);
            } else {
              c.save();
              c.translate(q.dx, q.dy);
              c.rotate(spin);
              c.drawRect(Rect.fromCenter(center: Offset.zero, width: 4, height: 2.6 + 1.4 * math.sin(spin * 2).abs()), Paint()..color = (i.isEven ? _goldA : _goldB).withValues(alpha: a));
              c.restore();
            }
          }
        }
        // the celebration: hearts and twinkles rising round it
        final c0 = _celebrateAt(golden), c1 = _celebrateEnd(golden);
        if (v > c0 && v < c1) {
          final n = golden ? 6 : 4;
          for (var i = 0; i < n; i++) {
            final f = (((v - c0) / (c1 - c0)) * 1.6 + i / n) % 1.0;
            final a = math.sin(f * math.pi) * (1 - ((v - c1 + 0.3) / 0.3).clamp(0.0, 1.0));
            final p = body + Offset(math.sin(i * 2.1 + f * 3) * pw * 0.55, -f * ph * 0.6 - ph * 0.15);
            if (i.isEven) {
              final hp = Path()
                ..moveTo(p.dx, p.dy + 3.5)
                ..cubicTo(p.dx - 7, p.dy - 2, p.dx - 3.5, p.dy - 7, p.dx, p.dy - 3.5)
                ..cubicTo(p.dx + 3.5, p.dy - 7, p.dx + 7, p.dy - 2, p.dx, p.dy + 3.5);
              c.drawPath(hp, Paint()..color = const Color(0xFFFF8FA8).withValues(alpha: a));
            } else {
              _star(c, p, 3.4, _plus((golden ? _goldB : _glowB).withValues(alpha: a)));
            }
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
  const _Slot({required this.label, required this.open, required this.used, required this.level});
  final String label;
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
              ? Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(used ? Icons.eco_rounded : Icons.add_rounded, color: _leaf, size: 18),
                  const SizedBox(width: 3),
                  Text(label, style: EvochiText.tag.copyWith(fontSize: 11.5, color: const Color(0xFF2F5A22))),
                ])
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.lock_rounded, size: 14, color: Color(0xFF9C8A70)),
                  const SizedBox(width: 2),
                  Text('$label · Farming $level', style: EvochiText.tag.copyWith(fontSize: 11, color: const Color(0xFF8A7860))),
                ]),
        ),
      );
}

/// A helper's in-world sprite: the walkable maps' sheet for its stage and palette (8 directions down, the idle
/// stance then the walk across), and what it wears, a row per item (a direction per frame).
class _Walker {
  _Walker(this.sheet, this.wear, this.fw, this.fh, this.gx, this.gy, {this.faces, this.faceRows = const [], this.faceExprs = const []});
  final ui.Image sheet;
  final List<ui.Image> wear;
  final double fw, fh, gx, gy;

  /// its portrait's faces on its standing frames (tools/art/walker_faces.py): a row per facing in [faceRows],
  /// a column per expression in [faceExprs]
  final ui.Image? faces;
  final List<int> faceRows;
  final List<String> faceExprs;

  static Map<String, dynamic>? _meta;
  static final _cache = <String, _Walker>{};

  static Future<_Walker> load(Pet pet) async {
    final key = '${pet.stage}|${pet.paletteId}|${pet.equipped.values.join(',')}';
    final hit = _cache[key];
    if (hit != null) return hit;
    final meta = _meta ??= (jsonDecode(await rootBundle.loadString('${artBase}wilds/wilds_walk.json')) as Map).cast<String, dynamic>();
    final w = ((meta['walkers'] as Map)['s0${pet.stage.clamp(1, 3)}'] as Map).cast<String, dynamic>();
    final sheets = (((w['gaits'] as Map)['walk'] as Map)['sheets'] as Map).cast<String, dynamic>();
    final sheet = await AtlasCache.load('${artBase}wilds/${sheets[pet.paletteId] ?? sheets['forest']}');
    final wm = (w['wear'] as Map?)?.cast<String, dynamic>() ?? const {};
    final wear = <ui.Image>[
      for (final id in pet.equipped.values)
        if (wm[id] is Map) await AtlasCache.load('${artBase}wilds/${(wm[id] as Map)['file']}'),
    ];
    final g = w['ground'] as List;
    // its faces, where they've been made (the Forest Juvenile: every garden helper)
    ui.Image? faces;
    var rows = const <int>[];
    var exprs = const <String>[];
    final base = '${artBase}home/helper_faces_s0${pet.stage}_${pet.paletteId}';
    try {
      final fj = (jsonDecode(await rootBundle.loadString('$base.json')) as Map).cast<String, dynamic>();
      faces = await AtlasCache.load('$base.webp');
      rows = (fj['rows'] as List).cast<int>();
      exprs = (fj['exprs'] as List).cast<String>();
    } catch (_) {} // (none: its one face)
    return _cache[key] = _Walker(sheet, wear, (w['frameW'] as num).toDouble(), (w['frameH'] as num).toDouble(), (g[0] as num).toDouble(), (g[1] as num).toDouble(),
        faces: faces, faceRows: rows, faceExprs: exprs);
  }
}

class _WalkerPainter extends CustomPainter {
  _WalkerPainter(this.art, this.facing, this.col, this.expr);
  final _Walker art;
  final int facing, col;
  final String expr;
  @override
  void paint(Canvas canvas, Size size) {
    final dst = Offset.zero & size;
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final fr = art.faceRows.indexOf(facing), fe = art.faceExprs.indexOf(expr);
    final faces = art.faces;
    if (faces != null && col == 0 && fr >= 0 && fe >= 0) {
      // standing, its face showing: the frame with this face on it
      canvas.drawImageRect(faces, Rect.fromLTWH(fe * art.fw, fr * art.fh, art.fw, art.fh), dst, paint);
    } else {
      canvas.drawImageRect(art.sheet, Rect.fromLTWH(col * art.fw, facing * art.fh, art.fw, art.fh), dst, paint);
    }
    for (final w in art.wear) {
      canvas.drawImageRect(w, Rect.fromLTWH(facing * art.fw, 0, art.fw, art.fh), dst, paint);
    }
  }

  @override
  bool shouldRepaint(_WalkerPainter old) => old.facing != facing || old.col != col || old.art != art || old.expr != expr;
}
