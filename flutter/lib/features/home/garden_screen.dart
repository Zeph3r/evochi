// Home Tales: the Garden. Four raised beds on one plate with the crops drawn where the art's anchors
// put them, a chip per bed (Plant / % grown / Harvest! / locked), and a panel for the selected bed:
// the seed picker, the growth bar split into time, walking, watering and Sprout Tonic, and Harvest.
// One tap harvests a ripe bed. Mirrors `garden` in web/src/screens/homeland.js.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/engine.dart' as g;
import '../../game/home/home.dart' as h;
import '../shared/widgets.dart';
import '../village/village_screen.dart';
import 'home_widgets.dart';

const _sparkColor = Color(0xFFFFE27A);
const _dropColor = Color(0xFF5BAFE0);

/// A bed's rectangle and its crop sprite, as fractions of the garden plate (from the art's anchors).
class _BedGeom {
  const _BedGeom(this.bed, this.crop);
  final Rect bed;
  final Rect crop;
}

_BedGeom _bedGeom(HomeArt a, String pid) {
  final gs = a.gardenSize;
  final an = a.gardenAnchor(pid);
  final l = a.gardenAnchor('${pid}l');
  final r = a.gardenAnchor('${pid}r');
  final bw = r.dx - l.dx;
  final sc = bw / a.cropBedW;
  final cs = a.cropSize;
  final gr = a.cropGround;
  return _BedGeom(
    Rect.fromLTWH(l.dx / gs.width, (an.dy - bw * 0.27) / gs.height, bw / gs.width, bw * 0.52 / gs.height),
    Rect.fromLTWH((an.dx - gr.dx * sc) / gs.width, (an.dy - gr.dy * sc) / gs.height, cs.width * sc / gs.width, cs.height * sc / gs.height),
  );
}

int _bedNumber(String pid) => h.plotDefs.indexWhere((p) => p.id == pid) + 1;

class GardenScreen extends StatefulWidget {
  const GardenScreen({super.key});
  @override
  State<GardenScreen> createState() => _GardenScreenState();
}

class _GardenScreenState extends State<GardenScreen> {
  String? _sel;
  String? _planted; // pops in once
  String? _splash; // watered just now
  final Map<String, Map<String, int>> _pops = {}; // just harvested: "+3" over the bed
  Timer? _tick;
  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    // crops grow on real time: refresh the bars and chips
    _tick = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _later(int ms, VoidCallback f) {
    _timers.add(Timer(Duration(milliseconds: ms), () {
      if (mounted) setState(f);
    }));
  }

  void _harvest(GameController c, String pid) {
    final r = c.run((s, n) => h.harvest(s, pid, n));
    if (!r.ok) return;
    final ev = r.events.firstWhere((e) => e.type == 'harvested');
    setState(() => _pops[pid] = (ev.data['items'] as Map).cast<String, int>());
    _later(1300, () => _pops.remove(pid));
    c.audio.play('coin', volume: 0.6);
  }

  void _tapBed(GameController c, h.PlotView p) {
    if (p.ripe) {
      // one tap harvests a ripe bed
      setState(() => _sel = p.id);
      _harvest(c, p.id);
      return;
    }
    c.audio.play('ui_tap', volume: 0.4);
    setState(() => _sel = p.id);
  }

  void _plant(GameController c, String pid, String crop) {
    final r = c.run((s, n) => h.plant(s, pid, crop, n));
    if (!r.ok) return;
    c.audio.play('pet_chirp', volume: 0.5);
    c.analytics.track('crop_planted', {'crop': crop});
    setState(() => _planted = pid);
    _later(700, () {
      if (_planted == pid) _planted = null;
    });
  }

  void _water(GameController c, String pid) {
    final r = c.run((s, n) => h.water(s, pid, n));
    if (!r.ok) return;
    c.audio.play('ui_tap', volume: 0.6);
    setState(() => _splash = pid);
    _later(900, () => _splash = null);
  }

  void _tonic(GameController c, String pid) {
    if (c.run((s, n) => h.useSproutTonic(s, pid, n)).ok) c.audio.play('reward_chime', volume: 0.5);
  }

  void _harvestAll(GameController c) {
    for (final p in h.plotDefs) {
      if (h.plotView(c.state, p.id, c.now).ripe) _harvest(c, p.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final plots = [for (final p in h.plotDefs) h.plotView(c.state, p.id, c.now)];
    if (_sel == null || !plots.any((x) => x.id == _sel)) {
      _sel = (plots.where((x) => x.ripe).firstOrNull ?? plots.where((x) => x.empty && x.unlocked).firstOrNull ?? plots.first).id;
    }
    final sel = plots.firstWhere((x) => x.id == _sel);
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: EvochiColor.panel,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          PlaceHeader(title: 'Your Garden', short: 'Garden', backLabel: 'Back', onBack: () => Navigator.of(context).maybePop()),
          Expanded(
            child: ListView(padding: EdgeInsets.only(bottom: 20 + MediaQuery.of(context).padding.bottom), children: [
              _GardenPlate(
                plots: plots,
                selected: _sel!,
                planted: _planted,
                splash: _splash,
                pops: _pops,
                animate: !reduce,
                onBed: (p) => _tapBed(c, p),
              ),
              Transform.translate(
                offset: const Offset(0, -16),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    _BedPanel(
                      p: sel,
                      plots: plots,
                      onPlant: (crop) => _plant(c, sel.id, crop),
                      onBuy: (seed) => openSeedShop(context, seed),
                      onWater: () => _water(c, sel.id),
                      onTonic: () => _tonic(c, sel.id),
                      onHarvest: () => _harvest(c, sel.id),
                      onHarvestAll: () => _harvestAll(c),
                      onWalk: () => goWalk(context),
                    ),
                    const SizedBox(height: 10),
                    if (c.state.steps.connection == 'demo' && plots.any((x) => !x.empty && !x.ripe)) ...[
                      _PlaytestSkip(onSkip: (min) {
                        c.audio.play('ui_tap', volume: 0.4);
                        c.skipTime(min * 60000);
                      }),
                      const SizedBox(height: 10),
                    ],
                    const SkillStrip('farming'),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      child: Text(
                        'Crops grow on their own. Steps you walk after planting speed them up (every 1,000 steps adds 10%, up to 60%), and watering adds 15%.',
                        style: EvochiText.caption,
                      ),
                    ),
                  ]),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

// ------------------------------------------------------------------- the plate ----
class _GardenPlate extends StatelessWidget {
  const _GardenPlate({
    required this.plots,
    required this.selected,
    required this.planted,
    required this.splash,
    required this.pops,
    required this.animate,
    required this.onBed,
  });
  final List<h.PlotView> plots;
  final String selected;
  final String? planted;
  final String? splash;
  final Map<String, Map<String, int>> pops;
  final bool animate;
  final ValueChanged<h.PlotView> onBed;

  @override
  Widget build(BuildContext context) {
    final ha = homeArt;
    final gs = ha.gardenSize;
    // the plate's top 86% is shown: the lower edge is just grass
    return AspectRatio(
      aspectRatio: gs.width / (gs.height * 0.86),
      child: LayoutBuilder(builder: (ctx, b) {
        final w = b.maxWidth;
        final hPlate = w * gs.height / gs.width;
        Rect px(Rect f) => Rect.fromLTWH(f.left * w, f.top * hPlate, f.width * w, f.height * hPlate);
        final geo = {for (final p in plots) p.id: _bedGeom(ha, p.id)};
        return ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: hPlate,
            maxHeight: hPlate,
            child: SizedBox(
              width: w,
              height: hPlate,
              child: Stack(children: [
                Positioned.fill(child: Image.asset(ha.garden, fit: BoxFit.cover, semanticLabel: 'Your garden: four raised beds inside a little fence.')),
                for (final p in plots)
                  if (!p.empty)
                    Positioned.fromRect(
                      rect: px(geo[p.id]!.crop),
                      child: IgnorePointer(child: _Crop(p: p, pop: planted == p.id, animate: animate)),
                    ),
                for (final p in plots)
                  Positioned.fromRect(
                    rect: px(geo[p.id]!.bed),
                    child: _BedButton(
                      p: p,
                      selected: p.id == selected,
                      splash: splash == p.id,
                      pop: pops[p.id],
                      onTap: () => onBed(p),
                    ),
                  ),
              ]),
            ),
          ),
        );
      }),
    );
  }
}

class _Crop extends StatelessWidget {
  const _Crop({required this.p, required this.pop, required this.animate});
  final h.PlotView p;
  final bool pop;
  final bool animate;
  @override
  Widget build(BuildContext context) {
    Widget img = Image.asset(homeArt.crop(p.crop!, p.stage!), fit: BoxFit.fill, excludeFromSemantics: true, gaplessPlayback: true);
    if (p.ripe) {
      img = DecoratedBox(
        decoration: const BoxDecoration(boxShadow: [BoxShadow(color: Color(0x33FFECA0), blurRadius: 18, spreadRadius: -6)]),
        child: img,
      );
    }
    // a freshly planted bed pops in
    return TweenAnimationBuilder<double>(
      key: ValueKey('${p.id}:${p.plantedAt}'),
      tween: Tween<double>(begin: animate ? 0.55 : 1.0, end: 1.0),
      duration: Duration(milliseconds: animate ? 600 : 1),
      curve: Curves.elasticOut,
      builder: (_, t, child) => Transform.scale(scale: t, alignment: const Alignment(0, 0.28), child: child),
      child: img,
    );
  }
}

class _BedButton extends StatelessWidget {
  const _BedButton({required this.p, required this.selected, required this.splash, required this.pop, required this.onTap});
  final h.PlotView p;
  final bool selected;
  final bool splash;
  final Map<String, int>? pop;
  final VoidCallback onTap;

  String get _label {
    final n = _bedNumber(p.id);
    if (!p.unlocked) return 'Bed $n: locked until Farming level ${p.need}';
    if (p.empty) return 'Bed $n: empty';
    final name = h.cropDefs[p.crop]!.name;
    if (p.ripe) return 'Bed $n: $name, ripe, tap to harvest';
    return 'Bed $n: $name, ${(p.progress * 100).floor()}% grown';
  }

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: _label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ExcludeSemantics(
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: selected ? Border.all(color: const Color(0xF2FFEEB2), width: 3) : null,
                    boxShadow: selected ? const [BoxShadow(color: Color(0xD9FFD26E), blurRadius: 16)] : null,
                  ),
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    opacity: splash ? 1 : 0,
                    duration: Duration(milliseconds: splash ? 150 : 700),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        gradient: RadialGradient(colors: [Color(0xBF8CCDF5), Color(0x008CCDF5)]),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: Center(child: FractionalTranslation(translation: const Offset(0, -0.55), child: _BedChip(p))),
              ),
              if (pop != null)
                Positioned(
                  left: 0,
                  right: 0,
                  top: -44,
                  child: Center(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      for (final e in pop!.entries) ...[
                        ItemImage(e.key, size: 28),
                        Text('+${e.value}', style: EvochiText.number.copyWith(fontSize: 16, color: Colors.white, shadows: const [Shadow(color: Color(0xAA000000), blurRadius: 3)])),
                        const SizedBox(width: 4),
                      ],
                    ]),
                  ),
                ),
            ]),
          ),
        ),
      );
}

class _BedChip extends StatelessWidget {
  const _BedChip(this.p);
  final h.PlotView p;
  @override
  Widget build(BuildContext context) {
    List<Color> colors = const [Color(0xFFFFF9F0), Color(0xFFF1E2CF)];
    Color edge = const Color(0xFFE2CDB4);
    Color fg = EvochiColor.ink;
    Widget lead;
    String text;
    if (!p.unlocked) {
      fg = EvochiColor.textHelper;
      lead = const VoxelIcon('lock', size: 16);
      text = 'Farming Lv ${p.need}';
    } else if (p.empty) {
      colors = const [EvochiColor.gold100, EvochiColor.primary];
      edge = Colors.white;
      lead = const Icon(Icons.add_rounded, size: 16, color: EvochiColor.ink);
      text = 'Plant';
    } else if (p.ripe) {
      colors = const [Color(0xFFD8F0B8), Color(0xFF9ED06F)];
      edge = Colors.white;
      fg = const Color(0xFF24461B);
      lead = const Icon(Icons.auto_awesome, size: 16, color: _sparkColor);
      text = 'Harvest!';
    } else {
      lead = SizedBox(width: 14, height: 14, child: CircularProgressIndicator(value: p.progress, strokeWidth: 3, color: EvochiColor.steps, backgroundColor: const Color(0xFFE7D9C8)));
      text = '${(p.progress * 100).floor()}%';
    }
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: edge, width: 2),
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
        boxShadow: const [BoxShadow(color: Color(0x4D281910), blurRadius: 8, offset: Offset(0, 3))],
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        lead,
        const SizedBox(width: 4),
        Text(text, style: EvochiText.tag.copyWith(color: fg, fontWeight: FontWeight.w900, fontSize: p.unlocked ? 13 : 12)),
      ]),
    );
  }
}

// -------------------------------------------------------------- the bed panel ----
class _BedPanel extends StatelessWidget {
  const _BedPanel({
    required this.p,
    required this.plots,
    required this.onPlant,
    required this.onBuy,
    required this.onWater,
    required this.onTonic,
    required this.onHarvest,
    required this.onHarvestAll,
    required this.onWalk,
  });
  final h.PlotView p;
  final List<h.PlotView> plots;
  final ValueChanged<String> onPlant;
  final ValueChanged<String> onBuy;
  final VoidCallback onWater;
  final VoidCallback onTonic;
  final VoidCallback onHarvest;
  final VoidCallback onHarvestAll;
  final VoidCallback onWalk;

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final ripe = plots.where((x) => x.ripe).length;
    final head = Row(children: [
      Expanded(child: Text('Bed ${_bedNumber(p.id)}${p.crop != null ? ' · ${h.cropDefs[p.crop]!.name}' : ''}', style: EvochiText.cardTitle)),
      if (ripe > 1)
        EvochiButton(
          label: 'Harvest all ($ripe)',
          small: true,
          expand: false,
          tone: ButtonTone.green,
          icon: const Icon(Icons.auto_awesome, size: 18, color: _sparkColor),
          onPressed: onHarvestAll,
        )
      else if (!p.empty && p.unlocked)
        Tag(p.ripe ? 'Ripe' : (p.stage == 'sprout' ? 'Sprouting' : 'Growing'), tone: p.ripe ? TagTone.ok : TagTone.cream),
    ]);
    final List<Widget> body;
    if (!p.unlocked) {
      body = [
        const SizedBox(height: 6),
        Text.rich(
          TextSpan(children: [
            const TextSpan(text: 'This bed opens at '),
            TextSpan(text: 'Farming Lv ${p.need}', style: const TextStyle(fontWeight: FontWeight.w900)),
            const TextSpan(text: '. Every harvest earns Farming XP.'),
          ]),
          style: EvochiText.bodyText,
        ),
      ];
    } else if (p.empty) {
      final anySeed = h.cropOrder.any((k) => g.ownedQty(c.state, h.cropDefs[k]!.seed) > 0);
      body = [
        const SizedBox(height: 4),
        Text(anySeed ? 'Pick something to plant.' : "No seeds left. Pick some up here or in the Market's Garden shelf.", style: EvochiText.caption),
        const SizedBox(height: 8),
        for (final k in h.cropOrder) _SeedRow(crop: h.cropDefs[k]!, onPlant: onPlant, onBuy: onBuy),
      ];
    } else if (p.ripe) {
      final crop = h.cropDefs[p.crop]!;
      body = [
        const SizedBox(height: 8),
        Row(children: [
          ItemImage(p.crop!, size: 56),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Ready to harvest!', style: EvochiText.cardTitle),
              Text('${yieldText(crop.yieldItems)} · +${crop.xp} Farming XP', style: EvochiText.caption),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        EvochiButton(label: 'Harvest', tone: ButtonTone.green, icon: const Icon(Icons.auto_awesome, size: 20, color: _sparkColor), onPressed: onHarvest),
      ];
    } else {
      final plot = c.state.home.plots[p.id]!;
      final gr = h.plotGrowth(c.state, plot, c.now);
      // split the bar: tonic first, then watering, walking and time (each capped by what's left)
      var left = 1.0;
      double take(double v) {
        final x = v.clamp(0.0, left).toDouble();
        left -= x;
        return x;
      }

      final tonic = take(plot.tonic ? h.growSproutTonic : 0.0);
      final water = take(plot.watered ? h.growWater : 0.0);
      final walk = take(gr.walk);
      final time = take(gr.time);
      final tonics = g.ownedQty(c.state, 'sprout_tonic');
      final pct = (p.progress * 100).floor();
      body = [
        const SizedBox(height: 10),
        Semantics(
          label: 'Growth',
          value: '$pct%',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Container(
              height: 16,
              color: const Color(0xFFE2D4C3),
              child: LayoutBuilder(builder: (ctx, b) {
                Widget seg(double f, List<Color> col) => Container(
                      width: b.maxWidth * f,
                      decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: col)),
                    );
                return Row(children: [
                  seg(time, _timeCol),
                  seg(walk, _walkCol),
                  seg(water, _waterCol),
                  seg(tonic, _tonicCol),
                ]);
              }),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$pct% grown', style: EvochiText.tag.copyWith(color: EvochiColor.ink)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'Ready in ${durationText(p.msLeft)}${p.stepsToRipe != null ? ', or walk ${fmt(p.stepsToRipe!)} steps' : ''}',
              textAlign: TextAlign.right,
              style: EvochiText.caption.copyWith(color: EvochiColor.textSecondary, fontSize: 13),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 12, runSpacing: 4, children: [
          const _KeyDot(_timeCol, 'Time'),
          _KeyDot(_walkCol, gr.steps > 0 ? 'Walking (${fmt(gr.steps)} steps)' : 'Walking'),
          if (p.watered) const _KeyDot(_waterCol, 'Watered'),
          if (p.tonic) const _KeyDot(_tonicCol, 'Sprout Tonic'),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          EvochiButton(
            label: p.watered ? 'Watered' : 'Water +15%',
            small: true,
            expand: false,
            tone: p.watered ? ButtonTone.cream : ButtonTone.gold,
            icon: const Icon(Icons.water_drop_rounded, size: 20, color: _dropColor),
            onPressed: p.watered ? null : onWater,
          ),
          if (tonics > 0 && !p.tonic)
            EvochiButton(label: 'Sprout Tonic +50%', small: true, expand: false, tone: ButtonTone.cream, icon: const ItemImage('sprout_tonic', size: 24), onPressed: onTonic),
          EvochiButton(label: 'Walk', small: true, expand: false, tone: ButtonTone.green, icon: const VoxelIcon('steps', size: 22), onPressed: onWalk),
        ]),
      ];
    }
    return Semantics(
      liveRegion: true,
      child: GameCard(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [head, ...body]),
      ),
    );
  }
}

/// Playtest (simulated step device only): let time pass so crops can be checked without waiting.
class _PlaytestSkip extends StatelessWidget {
  const _PlaytestSkip({required this.onSkip});
  final ValueChanged<int> onSkip;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: const Color(0xD9FFF9F0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFCDB396), width: 1.5),
        ),
        child: Row(children: [
          const Tag('Playtest'),
          const SizedBox(width: 6),
          Expanded(child: Text('Let time pass', style: EvochiText.tag.copyWith(fontSize: 12, color: EvochiColor.textSecondary))),
          EvochiButton(label: '+10 min', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => onSkip(10)),
          const SizedBox(width: 6),
          EvochiButton(label: '+1 hour', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => onSkip(60)),
        ]),
      );
}

const _timeCol = [Color(0xFFFFE29A), Color(0xFFF4B84E)];
const _walkCol = [Color(0xFFA8D87E), Color(0xFF6FA44E)];
const _waterCol = [Color(0xFFA6DBF6), Color(0xFF4C9BCC)];
const _tonicCol = [Color(0xFFD3C1EC), Color(0xFF9975C9)];

class _KeyDot extends StatelessWidget {
  const _KeyDot(this.colors, this.label);
  final List<Color> colors;
  final String label;
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(4), gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors)),
        ),
        const SizedBox(width: 5),
        Text(label, style: EvochiText.tag.copyWith(fontSize: 12)),
      ]);
}

class _SeedRow extends StatelessWidget {
  const _SeedRow({required this.crop, required this.onPlant, required this.onBuy});
  final h.CropDef crop;
  final ValueChanged<String> onPlant;
  final ValueChanged<String> onBuy;
  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final have = g.ownedQty(c.state, crop.seed);
    final open = h.cropUnlocked(c.state, crop.id);
    final seed = item(crop.seed);
    final Widget act;
    if (!open) {
      act = Tag('Lv ${crop.level}', tone: TagTone.neutral, icon: 'lock');
    } else if (have > 0) {
      act = EvochiButton(label: 'Plant', small: true, expand: false, tone: ButtonTone.green, semanticLabel: 'Plant ${crop.name}', onPressed: () => onPlant(crop.id));
    } else {
      act = EvochiButton(
        label: '${seed.price}',
        small: true,
        expand: false,
        tone: ButtonTone.cream,
        icon: const VoxelIcon('coin', size: 18),
        semanticLabel: 'Buy ${seed.name}',
        onPressed: () => onBuy(crop.seed),
      );
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(4, 5, 6, 5),
      decoration: BoxDecoration(color: const Color(0xFFFBF1E4), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEDCC6), width: 1.5)),
      child: Row(children: [
        Opacity(opacity: open ? 1 : 0.55, child: ItemImage(crop.seed, size: 42)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(child: Text(crop.name, style: EvochiText.cardTitle.copyWith(fontSize: 14, fontWeight: FontWeight.w900, color: open ? EvochiColor.ink : EvochiColor.textHelper))),
              if (have > 0) ...[const SizedBox(width: 6), Tag('x$have')],
            ]),
            Text('${durationText(crop.growMin * 60000)} · ${yieldText(crop.yieldItems)} · +${crop.xp} XP', style: EvochiText.caption.copyWith(fontSize: 11)),
          ]),
        ),
        const SizedBox(width: 6),
        ConstrainedBox(constraints: const BoxConstraints(minWidth: 74), child: Center(child: act)),
      ]),
    );
  }
}
