// S07 Pet details (Inspect) and the evolution cinematic (style guide §16-17).

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../app/constants.dart';
import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/engine.dart' as g;
import '../../game/vitality/vitality.dart';
import '../nest/sheets.dart';
import '../shared/scene_scaffold.dart';
import '../shared/scene_view.dart';
import '../shared/sprite.dart';
import '../shared/widgets.dart';

const _kind = {
  DayKind.goal: ('Goal met', TagTone.ok),
  DayKind.active: ('Active', TagTone.stage),
  DayKind.light: ('Light day', TagTone.cream),
  DayKind.rest: ('Rest day', TagTone.neutral),
  DayKind.low: ('Low day', TagTone.danger),
  DayKind.grace: ('Grace', TagTone.cream),
  DayKind.pending: ('Sync pending', TagTone.neutral),
  DayKind.dead: ('Resting', TagTone.neutral),
};

class PetDetailsScreen extends StatefulWidget {
  const PetDetailsScreen({super.key});
  @override
  State<PetDetailsScreen> createState() => _PetDetailsScreenState();
}

class _PetDetailsScreenState extends State<PetDetailsScreen> {
  final _scene = SceneController();
  String? _view;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scene.react('inspect'));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet;
    if (pet == null) return const SizedBox.shrink();
    final pv = c.view.pet!;
    final evo = pv.evolution;
    final vit = pv.vitality.vitality;
    final recent = pv.vitality.log.length > 7 ? pv.vitality.log.sublist(pv.vitality.log.length - 7) : pv.vitality.log;
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      body: SceneScaffold(
        controller: _scene,
        onPetTap: () {
          c.run((s, n) => g.interact(s, 'pet', n));
          _scene.react('pet');
          c.audio.play('pet_chirp');
        },
        petLabel: 'Pet ${pet.name}',
        minHero: 190,
        headerAllowance: 60,
        config: (gy) => SceneConfig(
          habitat: 'meadow',
          decor: c.state.placements,
          focus: Offset(0.5, gy),
          reducedMotion: reduce,
          pet: PetConfig(stage: pet.stage, palette: pet.paletteId, status: pv.status, equipped: pet.equipped.values.toList()),
        ),
        header: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: BackSquareButton(onTap: () => Navigator.of(context).pop()),
          ),
        ),
        panel: Container(
          padding: const EdgeInsets.fromLTRB(14, 16, 14, 20),
          decoration: const BoxDecoration(color: EvochiColor.panel, borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Semantics(header: true, child: Text(pet.name, style: EvochiText.pageTitle)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, children: [
                    Tag(stageLabel(pet.stage), tone: TagTone.stage),
                    statusTag(pv.status),
                    Tag(palettes.firstWhere((p) => p.id == pet.paletteId).label),
                  ]),
                ]),
              ),
              Column(children: [
                Text('Lv. ${pv.level.level}', style: EvochiText.number),
                Text('${fmt(pv.totalXp)} XP total', style: EvochiText.caption),
              ]),
            ]),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Turnaround', style: EvochiText.cardTitle),
                const SizedBox(height: 6),
                Row(children: [
                  for (final v in const ['front', 'left', 'back', 'right', 'top'])
                    Expanded(
                      child: Semantics(
                        button: true,
                        selected: _view == v,
                        label: '$v view',
                        child: GestureDetector(
                          onTap: () => setState(() => _view = _view == v ? null : v),
                          child: Container(
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: _view == v ? const Color(0xFFFFF4D6) : const Color(0xFFFFF9F0),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _view == v ? const Color(0xFFF2BE55) : const Color(0xFFE6D3BD), width: 1.5),
                            ),
                            child: Column(children: [
                              SizedBox(height: 40, child: PetSprite(stage: pet.stage, palette: pet.paletteId, view: v, height: 38)),
                              Text(v, style: EvochiText.tag.copyWith(fontSize: 12)),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ]),
                if (_view != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Center(child: PetSprite(stage: pet.stage, palette: pet.paletteId, view: _view, height: 160, semanticLabel: '${pet.name} $_view view')),
                  ),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Row(children: [
                  const VoxelIcon('heart', size: 26),
                  const SizedBox(width: 6),
                  const Expanded(child: Text('Vitality', style: EvochiText.cardTitle)),
                  Text('$vit / 100', style: EvochiText.number.copyWith(fontSize: 16)),
                ]),
                const SizedBox(height: 8),
                ProgressBarX(value: vit / 100, tone: vit >= 70 ? 'green' : (vit >= 35 ? 'amber' : 'red'), semantic: 'Vitality'),
                const SizedBox(height: 6),
                if (recent.isEmpty)
                  const Text('Day results appear here after each day ends.', style: EvochiText.caption)
                else
                  Wrap(spacing: 4, runSpacing: 4, children: [
                    for (final x in recent)
                      Tag('${x.key.substring(5)} ${_kind[x.kind]!.$1}${x.delta != 0 ? ' ${x.delta > 0 ? '+' : ''}${x.delta}' : ''}', tone: _kind[x.kind]!.$2),
                  ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: Text(
                      'Walking 50% of your goal restores +${c.config.restoreHalf}, 100% restores +${c.config.restoreFull}. Two low days a week are protected rest days.',
                      style: EvochiText.caption,
                    ),
                  ),
                  EvochiButton(label: 'Care', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => showCareSheet(context)),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Row(children: [VoxelIcon('evolve', size: 26), SizedBox(width: 6), Text('Evolution Path', style: EvochiText.cardTitle)]),
                const SizedBox(height: 6),
                if (evo.maxed)
                  Text('${pet.name} has reached the Elder form. Keep leveling for cosmetics, quests and future discoveries.', style: EvochiText.bodyText)
                else ...[
                  Text('Next form: ${stageLabel(evo.next!)}', style: EvochiText.caption),
                  const SizedBox(height: 6),
                  Row(children: [Expanded(child: Text('Level ${pv.level.level} / ${evo.gate!.level}', style: EvochiText.tag)), if (evo.levelOk) const Tag('Done', tone: TagTone.ok)]),
                  const SizedBox(height: 4),
                  ProgressBarX(value: evo.levelProgress, height: 10),
                  const SizedBox(height: 8),
                  Row(children: [Expanded(child: Text('Active days ${pv.activeDays} / ${evo.gate!.activeDays}', style: EvochiText.tag)), if (evo.daysOk) const Tag('Done', tone: TagTone.ok)]),
                  const SizedBox(height: 4),
                  ProgressBarX(value: evo.daysProgress, height: 10, tone: 'green'),
                  const SizedBox(height: 6),
                  const Text('An active day means reaching at least half your step goal.', style: EvochiText.caption),
                  const SizedBox(height: 8),
                  EvochiButton(
                    label: evo.eligible ? 'Evolve into ${stageLabel(evo.next!)}' : 'Not ready yet',
                    icon: const VoxelIcon('evolve', size: 24),
                    onPressed: evo.eligible && !pv.dead
                        ? () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const EvolutionScreen()))
                        : null,
                  ),
                ],
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const Text('Equipped', style: EvochiText.cardTitle),
                const SizedBox(height: 8),
                Row(children: [
                  for (final slot in const ['head', 'neck', 'back'])
                    Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(color: const Color(0xFFFFFBF6), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEADAC6), width: 2)),
                        child: Column(children: [
                          if (pet.equipped[slot] != null) ItemImage(pet.equipped[slot]!, size: 44) else const Opacity(opacity: 0.3, child: VoxelIcon('wearables', size: 44)),
                          Text(pet.equipped[slot] != null ? item(pet.equipped[slot]!).name : '${slotLabels[slot]}: empty',
                              textAlign: TextAlign.center, style: EvochiText.tag.copyWith(fontSize: 12)),
                        ]),
                      ),
                    ),
                ]),
              ]),
            ),
            const SizedBox(height: 10),
            GameCard(
              child: Column(children: [
                for (final row in [
                  ('Bond', '${pv.bond} / 100'),
                  ('Active days', '${pv.activeDays}'),
                  ('Verified steps together', fmt(pv.lifetimeSteps)),
                  ('Days together', '${pv.daysTogether}'),
                ])
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(children: [Expanded(child: Text(row.$1, style: EvochiText.bodyText)), Text(row.$2, style: EvochiText.cardTitle)]),
                  ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- evolution ----
/// 0-0.5s centre + dim, 0.5-1.4s crest glow + gathering particles, 1.4-2.3s flash-free morph,
/// 2.3-3.2s reveal + fanfare, 3.2s+ stage label and acknowledgement. Skip completes safely:
/// the evolution is committed before the animation starts.
class EvolutionScreen extends StatefulWidget {
  const EvolutionScreen({super.key});
  @override
  State<EvolutionScreen> createState() => _EvolutionScreenState();
}

class _EvolutionScreenState extends State<EvolutionScreen> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _t = Duration.zero;
  int _from = 1;
  int _to = 2;
  List<String> _removed = const [];
  bool _done = false;
  bool _started = false;
  ui.Image? _a, _b;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((t) {
      setState(() => _t = t);
      if (t.inMilliseconds > 3200 && !_done) setState(() => _done = true);
    });
    // commit after the first frame (never notify listeners during build); skipping later is always safe
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (!mounted) return;
    final c = context.read<GameController>();
    _from = c.state.pet!.stage;
    final r = c.run((s, n) => g.evolve(s, n));
    if (!r.ok) {
      Navigator.of(context).pop();
      return;
    }
    final ev = r.events.firstWhere((e) => e.type == 'evolved');
    _to = ev.data['stage'] as int;
    _removed = (ev.data['removed'] as List).cast<String>();
    c.analytics.track('evolution_completed', {'stage': _to});
    c.audio.play('evolve_fanfare', volume: 0.7);
    if (_removed.isNotEmpty) c.toast('Returned to your Bag: ${_removed.map((x) => item(x).name).join(', ')}', icon: 'bag');
    final m = AssetManifest.instance!;
    final pal = c.state.pet!.paletteId;
    AtlasCache.load(artBase + m.char(_from).atlasFile(pal)).then((i) {
      if (mounted) setState(() => _a = i);
    });
    AtlasCache.load(artBase + m.char(_to).atlasFile(pal)).then((i) {
      if (mounted) setState(() => _b = i);
    });
    _started = true;
    _ticker.start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final pet = c.state.pet;
    if (pet == null) return const SizedBox.shrink();
    final reduce = MediaQuery.of(context).disableAnimations;
    if (!_started) return const Scaffold(backgroundColor: Color(0xFF2A1F19));
    return Scaffold(
      backgroundColor: const Color(0xFF2A1F19),
      body: Stack(children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: RadialGradient(center: Alignment(0, -0.15), radius: 0.9, colors: [Color(0xFAFFEEBE), Color(0xE6FAD278), Color(0xEB281C16)], stops: [0, 0.35, 0.8]),
            ),
            child: CustomPaint(painter: _EvoPainter(t: _t.inMicroseconds / 1e6, from: _from, to: _to, palette: pet.paletteId, a: _a, b: _b, reduce: reduce)),
          ),
        ),
        SafeArea(
          child: Align(
            alignment: Alignment.topRight,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: EvochiButton(label: 'Skip', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => setState(() => _done = true)),
            ),
          ),
        ),
        if (_done)
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: GameCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Semantics(liveRegion: true, child: Text('${pet.name} became a ${stageLabel(_to)}!', textAlign: TextAlign.center, style: EvochiText.pageTitle)),
                    const SizedBox(height: 6),
                    const Text('New form unlocked in your EvoDex. Colours, bond, name and accessories all carried over.', textAlign: TextAlign.center, style: EvochiText.bodyText),
                    const SizedBox(height: 12),
                    EvochiButton(label: 'Wonderful!', large: true, onPressed: () => Navigator.of(context).pop()),
                  ]),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _EvoPainter extends CustomPainter {
  _EvoPainter({required this.t, required this.from, required this.to, required this.palette, required this.a, required this.b, required this.reduce});
  final double t;
  final int from, to;
  final String palette;
  final ui.Image? a, b;
  final bool reduce;

  void _sprite(Canvas canvas, Size size, ui.Image? img, int stage, String expr, double alpha, double white, double scaleMul) {
    if (img == null) return;
    final e = AssetManifest.instance!.char(stage);
    final src = e.frame(palette, expr);
    final sc = math.min(size.width * 0.8 / e.w, size.height * 0.55 / e.h) * scaleMul;
    final ground = Offset(size.width / 2, size.height * 0.62);
    final an = e.anchor('ground');
    final dst = Rect.fromLTWH(ground.dx - an.dx * sc, ground.dy - an.dy * sc, src.width * sc, src.height * sc);
    final p = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0).toDouble());
    canvas.drawImageRect(img, src, dst, p);
    if (white > 0) {
      canvas.saveLayer(dst, Paint());
      canvas.drawImageRect(img, src, dst, Paint()..colorFilter = ColorFilter.mode(Color.fromRGBO(255, 246, 214, white.clamp(0.0, 1.0).toDouble()), BlendMode.srcATop));
      canvas.restore();
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height * 0.5);
    if (reduce) {
      final k = ((t - 0.5) / 1.5).clamp(0.0, 1.0).toDouble();
      _sprite(canvas, size, a, from, 'default', 1 - k, 0, 1);
      _sprite(canvas, size, b, to, 'happy', k, 0, 1);
      return;
    }
    final dots = Paint()..color = const Color(0xFFFFE6A0);
    if (t < 1.4) {
      final glow = (t / 1.4).clamp(0.0, 1.0).toDouble();
      _sprite(canvas, size, a, from, 'surprised', 1, glow * 0.65, 1 + 0.02 * math.sin(t * 30) * glow);
      for (var i = 0; i < 40; i++) {
        final ang = i * 2.399 + t;
        final r = (1 - glow) * (0.6 + (i % 7) / 10) * size.width * 0.6 + 40;
        canvas.drawRect(Rect.fromLTWH(c.dx + math.cos(ang) * r, c.dy + math.sin(ang) * r * 0.7, 3 + (i % 4).toDouble(), 3 + (i % 4).toDouble()), dots..color = Color.fromRGBO(255, 236, 160, glow));
      }
    } else if (t < 2.3) {
      final k = (t - 1.4) / 0.9;
      final white = 1 - (k - 0.5).abs() * 0.4;
      _sprite(canvas, size, k < 0.5 ? a : b, k < 0.5 ? from : to, 'default', 1, white, 0.9 + k * 0.15);
      canvas.drawCircle(c, size.width * 0.45, Paint()..color = Color.fromRGBO(255, 245, 210, 0.35 * math.sin(k * math.pi)));
    } else {
      final k = ((t - 2.3) / 0.9).clamp(0.0, 1.0).toDouble();
      _sprite(canvas, size, b, to, k < 0.6 ? 'excited' : 'happy', 1, math.max(0.0, 0.6 - k), 1.05 - 0.05 * k);
      for (var i = 0; i < 40; i++) {
        final ang = i * 2.399;
        final r = k * (0.6 + (i % 7) / 10) * size.width * 0.5 + 30;
        canvas.drawRect(Rect.fromLTWH(c.dx + math.cos(ang) * r, c.dy + math.sin(ang) * r * 0.7 - k * 30, 3 + (i % 4).toDouble(), 3 + (i % 4).toDouble()),
            Paint()..color = Color.fromRGBO(255, 220, 120, 1 - k));
      }
    }
  }

  @override
  bool shouldRepaint(_EvoPainter old) => old.t != t || old.a != a || old.b != b;
}
