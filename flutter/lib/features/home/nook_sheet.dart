// The Hatching Nook (game/hatch/hatch.dart; docs: the Hatching Nook & Companion Collection bible): a
// warm little room off the cottage. The eggs are the picture: the cradles in a row you swipe through
// (one egg each, an empty cradle for every free one), the chosen egg's panel under them with how far
// along it is in words and a bar, where it came from, care once a day, and the hatch when it is ready.
// The collection (every egg you keep, not in a cradle) is one button away, each with "Set in a cradle"
// when there is room. Nothing here nags: no timers, nothing spoils.
//
// An egg is drawn, not a picture: its shell and spots from its kind, cracks as it comes along, a wobble
// now and then once it stirs, a soft aura when it is ready. The hatch is a short celebration (wobble,
// crack, burst, reveal) with a skip once you have seen one.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/game_state.dart';
import '../../core/services/haptics.dart';
import '../../core/utils/day_keys.dart';
import '../../game/engine.dart' as g;
import '../../game/hatch/hatch.dart' as hatch;
import '../shared/kit.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import 'companions_sheet.dart';

/// Open the nook (a window over whatever screen you are on).
Future<void> showNook(BuildContext context) => showEvochiSheet<void>(context, builder: (_) => const NookSheet());

class NookSheet extends StatefulWidget {
  const NookSheet({super.key});
  @override
  State<NookSheet> createState() => _NookSheetState();
}

class _NookSheetState extends State<NookSheet> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  late final PageController _page = PageController(viewportFraction: 0.46, initialPage: _pageMemory);
  static int _pageMemory = 0; // where you left the carousel (kept while the app runs)
  bool _collection = false;

  @override
  void dispose() {
    _anim.dispose();
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final cradled = hatch.cradled(s);
    final slots = s.hatch.slots;
    // the cradles: each occupied one, then an empty cradle for every free one
    final cards = <Egg?>[...cradled, for (var i = cradled.length; i < slots; i++) null];
    final page = _page.hasClients && _page.page != null ? _page.page!.round().clamp(0, cards.length - 1) : _pageMemory.clamp(0, cards.length - 1);
    final sel = cards.isEmpty ? null : cards[page];
    return Semantics(
      container: true,
      label: 'The Hatching Nook',
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Center(child: WoodPlaque(child: Text('Hatching Nook', style: WoodPlaque.text(EvochiText.section))))),
        ]),
        const SizedBox(height: 10),
        if (_collection)
          _Collection(onBack: () => setState(() => _collection = false), onAssigned: (i) {
            setState(() => _collection = false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (_page.hasClients) _page.jumpToPage(i);
            });
          })
        else ...[
          // the cradles, in a row you swipe
          SizedBox(
            height: 176,
            child: Stack(children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF5A3A2C), Color(0xFF3E2719)]),
                    border: Border.all(color: KitColor.woodEdge, width: 2),
                  ),
                ),
              ),
              PageView.builder(
                controller: _page,
                itemCount: cards.length,
                onPageChanged: (i) => setState(() => _pageMemory = i),
                itemBuilder: (_, i) => AnimatedBuilder(
                  animation: _anim,
                  builder: (_, __) => _Cradle(egg: cards[i], t: _anim.value * 4, selected: i == page, slot: i, onTap: () => _page.animateToPage(i, duration: const Duration(milliseconds: 280), curve: Curves.easeOut)),
                ),
              ),
              if (cards.length > 1) ...[
                Positioned(left: 4, top: 0, bottom: 0, child: _Arrow(left: true, on: page > 0, onTap: () => _page.previousPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut))),
                Positioned(right: 4, top: 0, bottom: 0, child: _Arrow(left: false, on: page < cards.length - 1, onTap: () => _page.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOut))),
              ],
              Positioned(
                left: 0,
                right: 0,
                bottom: 6,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  for (var i = 0; i < cards.length; i++)
                    Container(
                      width: i == page ? 14 : 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(color: i == page ? KitColor.goldRing : const Color(0x66FFF0D2), borderRadius: BorderRadius.circular(3)),
                    ),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 10),
          if (sel == null) _EmptyPanel(stored: hatch.stored(s).length, onCollection: () => setState(() => _collection = true)) else _EggPanel(egg: sel, onChanged: () => setState(() {})),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: EvochiButton(
                label: 'Egg collection${hatch.stored(s).isEmpty ? '' : ' (${hatch.stored(s).length})'}',
                tone: ButtonTone.cream,
                small: true,
                icon: const VoxelIcon('chest', size: 22),
                onPressed: () => setState(() => _collection = true),
              ),
            ),
            const SizedBox(width: 8),
            EvochiButton(label: 'Close', tone: ButtonTone.cream, small: true, expand: false, onPressed: () => Navigator.of(context).pop()),
          ]),
        ],
      ]),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.left, required this.on, required this.onTap});
  final bool left, on;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          button: true,
          label: left ? 'Previous cradle' : 'Next cradle',
          child: GestureDetector(
            onTap: on ? onTap : null,
            child: Opacity(
              opacity: on ? 1 : 0.25,
              child: Container(
                width: 30,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: const Color(0x66000000), borderRadius: BorderRadius.circular(8)),
                child: Icon(left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded, color: const Color(0xFFFFF0D2), size: 26),
              ),
            ),
          ),
        ),
      );
}

/// A cradle: a woven straw bowl on a little stand, with its egg (or empty, "+").
class _Cradle extends StatelessWidget {
  const _Cradle({required this.egg, required this.t, required this.selected, required this.slot, required this.onTap});
  final Egg? egg;
  final double t;
  final bool selected;
  final int slot;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final e = egg;
    final frac = e == null ? 0.0 : hatch.fractionOf(e);
    final stage = e == null ? 'empty' : hatch.hatchStage(frac);
    final name = e == null ? 'Empty cradle' : hatch.eggTemplates[e.templateId]?.name ?? 'Egg';
    return Semantics(
      button: true,
      selected: selected,
      label: e == null ? 'Empty cradle ${slot + 1}' : '$name, ${(frac * 100).round()} percent, ${hatch.stageWords[stage]}',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedScale(
          scale: selected ? 1 : 0.86,
          duration: const Duration(milliseconds: 220),
          child: AnimatedOpacity(
            opacity: selected ? 1 : 0.7,
            duration: const Duration(milliseconds: 220),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              SizedBox(
                width: 120,
                height: 118,
                child: CustomPaint(painter: _CradlePainter(e, t, stage, selected)),
              ),
              Text(e == null ? 'Empty' : '${(frac * 100).round()}%',
                  style: EvochiText.tag.copyWith(color: const Color(0xFFFFF0D2), fontSize: 12.5, shadows: kitWoodTextShadow)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CradlePainter extends CustomPainter {
  _CradlePainter(this.egg, this.t, this.stage, this.selected);
  final Egg? egg;
  final double t;
  final String stage;
  final bool selected;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.62);
    // the stand and the bowl
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: c + const Offset(0, 40), width: 56, height: 10), const Radius.circular(4)), Paint()..color = const Color(0xFF6E4224));
    final bowl = Rect.fromCenter(center: c + const Offset(0, 22), width: 92, height: 44);
    canvas.drawOval(bowl, Paint()..color = const Color(0xFFD4AE4E));
    canvas.drawOval(bowl.deflate(5), Paint()..color = const Color(0xFFB98B2E));
    for (var i = 0; i < 9; i++) {
      final a = -math.pi + i * math.pi / 8;
      canvas.drawArc(bowl.deflate(2), a, 0.25, false, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xFFE8C766));
    }
    canvas.drawOval(Rect.fromCenter(center: c + const Offset(0, 16), width: 74, height: 26), Paint()..color = const Color(0xFFF5E6C8)); // the blanket
    final e = egg;
    if (e == null) {
      canvas.drawCircle(c, 15, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = const Color(0x99FFF0D2));
      canvas.drawLine(c - const Offset(7, 0), c + const Offset(7, 0), Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xCCFFF0D2));
      canvas.drawLine(c - const Offset(0, 7), c + const Offset(0, 7), Paint()
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..color = const Color(0xCCFFF0D2));
      return;
    }
    paintEgg(canvas, c - const Offset(0, 6), 30, e, t, stage, aura: stage == 'ready' || selected);
  }

  @override
  bool shouldRepaint(_CradlePainter old) => true;
}

/// An egg, drawn: [h] half its height. Its kind gives the shell and spots; [stage] the cracks and the
/// movement; [t] seconds, for the wobble and the breathing.
void paintEgg(Canvas canvas, Offset c, double h, Egg e, double t, String stage, {bool aura = false, double crackExtra = 0, bool reduced = false}) {
  final tpl = hatch.eggTemplates[e.templateId];
  final shell = Color(tpl?.shell ?? 0xFFE8DCC0), spots = Color(tpl?.spots ?? 0xFF9C8A66);
  final seed = e.id.hashCode;
  // the wobble: once it stirs, a tilt now and then; cracking, oftener and bigger
  var tilt = 0.0;
  if (!reduced) {
    final period = stage == 'cracking' ? 1.6 : 2.6;
    final ph = (t + seed % 7) % period;
    if (stage == 'stirring' && ph < 0.5) tilt = 0.12 * math.sin(ph / 0.5 * math.pi * 3) * (1 - ph / 0.5);
    if (stage == 'cracking' && ph < 0.6) tilt = 0.2 * math.sin(ph / 0.6 * math.pi * 4) * (1 - ph / 0.6);
    if (stage == 'ready') tilt = 0.05 * math.sin(t * 2.2);
  }
  final breathe = reduced ? 0.0 : 0.5 + 0.5 * math.sin(t * 1.3 + seed % 5);
  if (aura) {
    final r = h * (1.6 + 0.15 * breathe);
    canvas.drawCircle(c, r, Paint()..shader = RadialGradient(colors: [shell.withAlpha(stage == 'ready' ? 150 : 70), shell.withAlpha(0)]).createShader(Rect.fromCircle(center: c, radius: r)));
  }
  canvas.save();
  canvas.translate(c.dx, c.dy + h * 0.9);
  canvas.rotate(tilt);
  canvas.translate(-c.dx, -(c.dy + h * 0.9));
  // the shape: an egg, rounder below, pointier above
  final path = Path();
  const n = 40;
  for (var i = 0; i <= n; i++) {
    final a = -math.pi / 2 + i * 2 * math.pi / n;
    final y = math.sin(a);
    final w = h * 0.74 * math.cos(a) * (1 - 0.18 * y);
    final p = Offset(c.dx + w, c.dy + y * h);
    if (i == 0) {
      path.moveTo(p.dx, p.dy);
    } else {
      path.lineTo(p.dx, p.dy);
    }
  }
  path.close();
  canvas.drawPath(path.shift(Offset(h * 0.08, h * 0.1)), Paint()..color = const Color(0x33000000));
  canvas.drawPath(path, Paint()..color = shell);
  canvas.save();
  canvas.clipPath(path);
  // shading and a highlight
  canvas.drawOval(Rect.fromCenter(center: c + Offset(h * 0.25, h * 0.35), width: h * 1.3, height: h * 1.6), Paint()..color = Color.alphaBlend(const Color(0x1F000000), shell).withAlpha(120));
  canvas.drawOval(Rect.fromCenter(center: c + Offset(-h * 0.28, -h * 0.4), width: h * 0.4, height: h * 0.62), Paint()..color = const Color(0x66FFFFFF));
  // spots, placed by the egg's own seed
  final rng = math.Random(seed);
  for (var i = 0; i < 9; i++) {
    final a = rng.nextDouble() * math.pi * 2, d = rng.nextDouble() * 0.7;
    final sp = c + Offset(math.cos(a) * h * 0.6 * d, math.sin(a) * h * 0.85 * d);
    canvas.drawOval(Rect.fromCenter(center: sp, width: h * (0.12 + rng.nextDouble() * 0.16), height: h * (0.1 + rng.nextDouble() * 0.12)), Paint()..color = spots.withAlpha(200));
  }
  // cracks: a few at cracking, a web when ready
  final cracks = (stage == 'cracking' ? 3 : (stage == 'ready' ? 6 : 0)) + (crackExtra * 6).round();
  final ink = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.2, h * 0.045)
    ..strokeCap = StrokeCap.round
    ..color = Color.alphaBlend(const Color(0x99000000), spots);
  final cr = math.Random(seed + 3);
  for (var i = 0; i < cracks; i++) {
    var p = c + Offset((cr.nextDouble() - 0.5) * h * 0.8, (cr.nextDouble() - 0.5) * h * 1.2);
    final zig = Path()..moveTo(p.dx, p.dy);
    var a = cr.nextDouble() * math.pi * 2;
    for (var k = 0; k < 4; k++) {
      a += (cr.nextDouble() - 0.5) * 1.6;
      p += Offset(math.cos(a), math.sin(a)) * h * (0.14 + crackExtra * 0.1);
      zig.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(zig, ink);
    if (stage == 'ready' || crackExtra > 0.3) {
      canvas.drawPath(zig, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ink.strokeWidth * 2.2
        ..color = const Color(0x55FFF4C8)); // light leaking out
    }
  }
  canvas.restore();
  canvas.drawPath(path, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = math.max(1.5, h * 0.05)
    ..color = Color.alphaBlend(const Color(0x66000000), spots));
  canvas.restore();
}

/// The chosen egg: its name, its stage, the bar, where it came from, care and the hatch.
class _EggPanel extends StatelessWidget {
  const _EggPanel({required this.egg, required this.onChanged});
  final Egg egg;
  final VoidCallback onChanged;
  @override
  Widget build(BuildContext context) {
    final c = context.read<GameController>();
    final tpl = hatch.eggTemplates[egg.templateId];
    final frac = hatch.fractionOf(egg);
    final stage = hatch.hatchStage(frac);
    final today = dayKey(c.now, g.zoneOf(c.state));
    final cared = egg.careDays.contains(today);
    final ready = egg.state == 'ready';
    final need = tpl?.need ?? 2000;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: Kit.card(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(tpl?.name ?? 'Egg', style: EvochiText.cardTitle)),
          Tag(hatch.stageWords[stage]!, tone: ready ? TagTone.ok : TagTone.neutral),
        ]),
        const SizedBox(height: 6),
        ProgressBarX(value: frac, height: 10, tone: ready ? 'gold' : 'green'),
        const SizedBox(height: 6),
        Text(
          ready ? 'Ready. It is waiting for you.' : '${(frac * 100).round()}% developed · ${math.max(0, need - egg.progress)} steps to go',
          style: EvochiText.caption,
        ),
        const SizedBox(height: 4),
        Text('${egg.origin}. ${tpl?.blurb ?? ''}', style: EvochiText.bodyText.copyWith(fontSize: 13)),
        const SizedBox(height: 4),
        Text('Could hatch: ${(tpl?.palettes ?? const []).map(hatch.paletteLabel).join(' or ')}', style: EvochiText.caption),
        const SizedBox(height: 10),
        if (ready)
          EvochiButton(
              label: 'Hatch',
              icon: const VoxelIcon('star', size: 22),
              onPressed: () async {
                await showHatch(context, egg);
                onChanged();
              })
        else
          Row(children: [
            Expanded(
              child: EvochiButton(
                label: cared ? 'Cared for today' : 'Give gentle care',
                tone: cared ? ButtonTone.cream : ButtonTone.green,
                small: true,
                icon: const VoxelIcon('heart', size: 22),
                onPressed: cared
                    ? null
                    : () {
                        final r = c.run((s, n) => hatch.careEgg(s, egg.id, n), quiet: true);
                        if (r.ok) {
                          c.audio.play('enc_soothe', volume: 0.5);
                          c.audio.buzz(Haptic.purr);
                          if (r.events.any((e) => e.type == 'egg_ready')) c.toast('It is ready to hatch!', icon: 'star');
                        }
                        onChanged();
                      },
              ),
            ),
            const SizedBox(width: 8),
            EvochiButton(
              label: 'Move to collection',
              tone: ButtonTone.cream,
              small: true,
              expand: false,
              onPressed: () async {
                final ok = await showEvochiDialog<bool>(context,
                    builder: (d) => Column(mainAxisSize: MainAxisSize.min, children: [
                          const Text('Move it to the collection?', style: EvochiText.section),
                          const SizedBox(height: 8),
                          const Text('It keeps everything it has. It only stops growing until it is set in a cradle again.', textAlign: TextAlign.center, style: EvochiText.bodyText),
                          const SizedBox(height: 12),
                          EvochiButton(label: 'Move it', onPressed: () => Navigator.pop(d, true)),
                          const SizedBox(height: 6),
                          EvochiButton(label: 'Leave it', tone: ButtonTone.cream, onPressed: () => Navigator.pop(d, false)),
                        ]));
                if (ok == true) {
                  c.run((s, n) => hatch.unassignEgg(s, egg.id), quiet: true);
                  onChanged();
                }
              },
            ),
          ]),
      ]),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.stored, required this.onCollection});
  final int stored;
  final VoidCallback onCollection;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: Kit.inset(),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('An empty cradle', style: EvochiText.cardTitle),
          const SizedBox(height: 4),
          Text(
            stored > 0 ? 'You have $stored egg${stored == 1 ? '' : 's'} in the collection. Set one here and your walking grows it.' : 'Find an egg out in the Wilds, or choose one at the Caravan, and set it here. Your walking grows it.',
            style: EvochiText.bodyText.copyWith(fontSize: 13),
          ),
          if (stored > 0) ...[
            const SizedBox(height: 10),
            EvochiButton(label: 'Choose an egg', icon: const VoxelIcon('chest', size: 22), small: true, onPressed: onCollection),
          ],
        ]),
      );
}

/// The collection: every egg not in a cradle, newest first, with "Set in a cradle" while there is room.
class _Collection extends StatelessWidget {
  const _Collection({required this.onBack, required this.onAssigned});
  final VoidCallback onBack;
  final ValueChanged<int> onAssigned;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final eggs = hatch.stored(s)..sort((a, b) => b.acquiredAt.compareTo(a.acquiredAt));
    final hatched = s.hatch.eggs.where((e) => e.state == 'hatched').length;
    final free = hatch.freeSlot(s);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        BackSquareButton(onTap: onBack),
        const SizedBox(width: 8),
        const Expanded(child: Text('Egg collection', style: EvochiText.section)),
        Text('${eggs.length} kept · $hatched hatched', style: EvochiText.caption),
      ]),
      const SizedBox(height: 8),
      if (eggs.isEmpty)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: Kit.inset(),
          child: Column(children: [
            SizedBox(height: 70, child: CustomPaint(size: const Size(120, 70), painter: _CradlePainter(null, 0, 'empty', false))),
            const SizedBox(height: 6),
            const Text('No eggs kept here. Find one in the Wilds or visit the Caravan.', textAlign: TextAlign.center, style: EvochiText.bodyText),
          ]),
        )
      else
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 340),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: eggs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final e = eggs[i];
              final tpl = hatch.eggTemplates[e.templateId];
              final frac = hatch.fractionOf(e);
              return Container(
                padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
                decoration: Kit.card(flat: true),
                child: Row(children: [
                  SizedBox(width: 44, height: 56, child: CustomPaint(painter: _SmallEgg(e, hatch.hatchStage(frac)))),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(tpl?.name ?? 'Egg', style: EvochiText.cardTitle),
                      Text('${e.origin} · ${(frac * 100).round()}% · could hatch ${(tpl?.palettes ?? const []).map(hatch.paletteLabel).join(' or ')}',
                          style: EvochiText.caption),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  EvochiButton(
                    label: free == null ? 'No cradle free' : 'Set in a cradle',
                    small: true,
                    expand: false,
                    tone: free == null ? ButtonTone.cream : ButtonTone.gold,
                    onPressed: free == null
                        ? null
                        : () {
                            final r = c.run((s, n) => hatch.assignEgg(s, e.id, n), quiet: true);
                            if (r.ok) {
                              c.audio.play('equip', volume: 0.5);
                              c.audio.buzz(Haptic.tap);
                              onAssigned(hatch.cradled(r.state).indexWhere((x) => x.id == e.id));
                            }
                          },
                  ),
                ]),
              );
            },
          ),
        ),
    ]);
  }
}

class _SmallEgg extends CustomPainter {
  _SmallEgg(this.egg, this.stage);
  final Egg egg;
  final String stage;
  @override
  void paint(Canvas canvas, Size size) => paintEgg(canvas, Offset(size.width / 2, size.height / 2), size.height * 0.42, egg, 0, stage, reduced: true);
  @override
  bool shouldRepaint(_SmallEgg old) => old.egg != egg;
}

// ------------------------------------------------------------------------------------ the hatch
/// The hatch: the egg committed first (one new companion, the cradle freed), then the little
/// celebration: wobble, crack, burst, reveal, a name, and where to see it. Skippable once seen.
Future<void> showHatch(BuildContext context, Egg egg) async {
  final c = context.read<GameController>();
  final r = c.run((s, n) => hatch.hatchEgg(s, egg.id, name: 'Little One', requestId: 'hatch:${egg.id}', now: n), quiet: true);
  if (!r.ok) {
    c.toast('Not just yet.', kind: 'warn');
    return;
  }
  final ev = r.events.where((e) => e.type == 'egg_hatched').firstOrNull;
  final petId = ev?.data['petId'] as String? ?? hatch.eggById(r.state, egg.id)?.hatchedPetId;
  final pet = hatch.allPets(c.state).where((p) => p.id == petId).firstOrNull;
  if (pet == null || !context.mounted) return;
  c.analytics.track('egg_hatched', {'template': egg.templateId, 'palette': pet.paletteId});
  await showEvochiDialog<void>(context, builder: (_) => _HatchShow(egg: egg, pet: pet));
}

class _HatchShow extends StatefulWidget {
  const _HatchShow({required this.egg, required this.pet});
  final Egg egg;
  final Pet pet;
  @override
  State<_HatchShow> createState() => _HatchShowState();
}

class _HatchShowState extends State<_HatchShow> with SingleTickerProviderStateMixin {
  // the beats: 0-1.0 wobble, 1.0-1.8 crack, 1.8-2.3 burst, then the reveal
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
  final _name = TextEditingController();
  String? _nameError;
  bool _revealed = false;
  bool _skippable = false;
  final _fired = <int>{};

  @override
  void initState() {
    super.initState();
    final c = context.read<GameController>();
    _skippable = c.state.flags['hatchSeen'] == true;
    final reduced = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    _a.addListener(_beats);
    _a.addStatusListener((st) {
      if (st == AnimationStatus.completed) _reveal();
    });
    if (reduced) {
      _reveal();
    } else {
      _a.forward();
    }
  }

  void _beats() {
    final c = context.read<GameController>();
    final t = _a.value * 2.6;
    void once(int k, void Function() f) {
      if (_fired.add(k)) f();
    }
    if (t > 0.1) once(0, () => c.audio.buzz(Haptic.tick, strength: 0.5));
    if (t > 0.6) once(1, () => c.audio.buzz(Haptic.tick, strength: 0.6));
    if (t > 1.0) {
      once(2, () {
        c.audio.play('mine_copper_crack', volume: 0.5);
        c.audio.buzz(Haptic.hit, strength: 0.7);
      });
    }
    if (t > 1.8) {
      once(3, () {
        c.audio.play('mine_copper_break', volume: 0.6);
        c.audio.buzz(Haptic.thump);
      });
    }
    setState(() {});
  }

  void _reveal() {
    if (_revealed) return;
    final c = context.read<GameController>();
    _a.stop();
    setState(() => _revealed = true);
    c.audio.play('reward_chime', volume: 0.7);
    c.audio.buzz(Haptic.reward);
    if (c.state.flags['hatchSeen'] != true) c.run((s, n) => hatch.setFlag(s, 'hatchSeen', true), quiet: true);
  }

  @override
  void dispose() {
    _a.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.read<GameController>();
    final pet = hatch.allPets(c.state).where((p) => p.id == widget.pet.id).firstOrNull ?? widget.pet;
    final t = _a.value * 2.6;
    return Semantics(
      container: true,
      label: _revealed ? 'A new Evochi hatched: ${hatch.paletteLabel(pet.paletteId)}' : 'The egg is hatching',
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: WoodPlaque(child: Text(_revealed ? 'Hello, little one!' : 'Something is happening…', style: WoodPlaque.text(EvochiText.section)))),
        const SizedBox(height: 12),
        SizedBox(
          height: 190,
          child: _revealed
              ? _Reveal(pet: pet)
              : CustomPaint(size: const Size(double.infinity, 190), painter: _HatchPainter(widget.egg, t)),
        ),
        const SizedBox(height: 10),
        if (_revealed) ...[
          Text(
            '${hatch.paletteLabel(pet.paletteId)} · Hatchling · ${pet.origin ?? ''}',
            textAlign: TextAlign.center,
            style: EvochiText.caption,
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _name,
            maxLength: 16,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'A name for your new Evochi', errorText: _nameError, counterText: '', border: const OutlineInputBorder()),
            onChanged: (_) => setState(() => _nameError = null),
          ),
          const SizedBox(height: 8),
          EvochiButton(
            label: 'Name it',
            onPressed: () {
              final r = c.run((s, n) => hatch.renameCompanion(s, pet.id, _name.text), quiet: true);
              if (!r.ok) {
                setState(() => _nameError = (r.info['message'] as String?) ?? 'Try another name');
                return;
              }
              c.audio.buzz(Haptic.good);
              setState(() {});
            },
          ),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: EvochiButton(
                label: 'View companion',
                tone: ButtonTone.cream,
                small: true,
                onPressed: () {
                  Navigator.of(context).pop();
                  showCompanions(context, focus: pet.id);
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: EvochiButton(label: 'Let it rest', tone: ButtonTone.cream, small: true, onPressed: () => Navigator.of(context).pop())),
          ]),
          const SizedBox(height: 4),
          Text('${pet.name} rests with your companions. Your active Evochi stays as it is; switch any time from My Evochis.',
              textAlign: TextAlign.center, style: EvochiText.caption),
        ] else if (_skippable)
          Align(alignment: Alignment.centerRight, child: EvochiButton(label: 'Skip', tone: ButtonTone.cream, small: true, expand: false, onPressed: _reveal)),
      ]),
    );
  }
}

class _HatchPainter extends CustomPainter {
  _HatchPainter(this.egg, this.t);
  final Egg egg;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.56);
    const h = 52.0;
    if (t < 1.8) {
      final wob = t < 1.0 ? 0.18 * math.sin(t * 18) * math.min(1.0, t * 3) : 0.1 * math.sin(t * 30);
      final extra = t < 1.0 ? 0.0 : (t - 1.0) / 0.8;
      canvas.save();
      canvas.translate(c.dx, c.dy + h);
      canvas.rotate(wob);
      canvas.translate(-c.dx, -(c.dy + h));
      paintEgg(canvas, c, h, egg, 0, t < 1.0 ? 'cracking' : 'ready', aura: true, crackExtra: extra, reduced: true);
      canvas.restore();
      return;
    }
    // the burst: a flash, shell fragments flying, sparkles
    final k = ((t - 1.8) / 0.5).clamp(0.0, 1.0);
    final tpl = hatch.eggTemplates[egg.templateId];
    final shell = Color(tpl?.shell ?? 0xFFE8DCC0);
    canvas.drawCircle(c, h * (1 + 3 * k), Paint()..color = const Color(0xFFFFF4C8).withAlpha(((1 - k) * 200).round()));
    final rng = math.Random(egg.id.hashCode);
    for (var i = 0; i < 12; i++) {
      final a = rng.nextDouble() * math.pi * 2, sp = 60 + rng.nextDouble() * 90;
      final p = c + Offset(math.cos(a) * sp * k, math.sin(a) * sp * k - 40 * k + 160 * k * k);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a + k * 6);
      final w = 8 + rng.nextDouble() * 10;
      canvas.drawPath(Path()..moveTo(-w / 2, 0)..lineTo(w / 2, -w * 0.3)..lineTo(w * 0.2, w * 0.5)..close(), Paint()..color = shell.withAlpha(((1 - k * 0.6) * 255).round()));
      canvas.restore();
    }
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + k * 2;
      final p = c + Offset(math.cos(a), math.sin(a)) * h * (0.6 + 1.6 * k);
      canvas.drawCircle(p, 3 * (1 - k) + 1, Paint()..color = const Color(0xFFFFE27A).withAlpha(((1 - k) * 255).round()));
    }
  }

  @override
  bool shouldRepaint(_HatchPainter old) => true;
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.pet});
  final Pet pet;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOutBack,
        builder: (_, k, child) => Transform.scale(scale: 0.6 + 0.4 * k, child: Opacity(opacity: k.clamp(0.0, 1.0), child: child)),
        child: Stack(alignment: Alignment.center, children: [
          Container(
            width: 170,
            height: 170,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xFFFFF1C4), Color(0x00FFF1C4)])),
          ),
          PetSprite(stage: 1, palette: pet.paletteId, expr: 'happy', height: 130, semanticLabel: 'Your new Evochi, ${hatch.paletteLabel(pet.paletteId)}'),
          for (var i = 0; i < 6; i++)
            Positioned(
              left: 85 + 70 * math.cos(i * math.pi / 3) - 6,
              top: 85 + 60 * math.sin(i * math.pi / 3) - 6,
              child: const VoxelIcon('star', size: 14),
            ),
        ]),
      );
}

/// An egg of a kind, drawn for a card (the Caravan's offers, the collection).
class EggPreviewPainter extends CustomPainter {
  EggPreviewPainter(this.templateId);
  final String templateId;
  @override
  void paint(Canvas canvas, Size size) =>
      paintEgg(canvas, Offset(size.width / 2, size.height / 2), size.height * 0.42, Egg(id: 'preview:$templateId', templateId: templateId, origin: '', acquiredAt: 0), 0, 'resting', aura: true, reduced: true);
  @override
  bool shouldRepaint(EggPreviewPainter oldDelegate) => oldDelegate.templateId != templateId;
}
