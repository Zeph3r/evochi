// Developer tools: the live pet lab. The Eggling drawn live (live_model.dart) and driven by the live brain
// (game/personality/brain.dart): its genes rolled from a seed (or set by hand), its needs draining at the rates
// its genes give, what it is doing and why (every action's score: needs x genes), and things to put in front of
// it: food, something new, a visitor, your touch. Breed it with another egg to see a child's genes. Nothing here
// is saved or touches your Evochi.

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../game/personality/brain.dart';
import '../../game/personality/genome.dart';
import 'live_animator.dart';
import 'live_model.dart';

Future<void> openLiveLab(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LiveLabScreen()));

class LiveLabScreen extends StatefulWidget {
  const LiveLabScreen({super.key, this.seed});
  final int? seed;
  @override
  State<LiveLabScreen> createState() => _LiveLabScreenState();
}

class _LiveLabScreenState extends State<LiveLabScreen> with SingleTickerProviderStateMixin {
  late Genome genome;
  late Brain brain;
  late LiveAnimator anim;
  LiveModel? model;
  LiveRenderer? renderer;
  final _images = <String, ui.Image>{};
  String palette = 'amber';
  double speed = 1;
  String? lineage;
  final frame = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Timer? _ui;
  final _rng = math.Random();

  @override
  void initState() {
    super.initState();
    _seat(Genome.fromSeed(widget.seed ?? 20261112));
    LiveModel.load('assets/live/eggling').then((m) {
      if (!mounted) return;
      setState(() {
        model = m;
        renderer = LiveRenderer(m);
      });
    });
    for (final (k, path) in [('food', 'assets/art/items/berry_snack.webp'), ('object', 'assets/art/items/dazzle_pebble.webp')]) {
      rootBundle.load(path).then((d) async {
        final c = await ui.instantiateImageCodec(d.buffer.asUint8List());
        final f = await c.getNextFrame();
        if (mounted) _images[k] = f.image;
      });
    }
    _ticker = createTicker(_tick)..start();
    _ui = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
  }

  /// a new genome in the same body: where it stands, how it is and what is around it carry over
  void _seat(Genome g, {bool fresh = false}) {
    final old = fresh ? null : _maybeBrain;
    genome = g;
    final b = Brain(g, rng: math.Random(g.seed), halfW: 32, halfD: 14);
    if (old != null) {
      b.x = old.x;
      b.z = old.z;
      b.heading = old.heading;
      old.needs.all.forEach(b.needs.set);
      b.things.addAll(old.things);
    }
    brain = b;
    _maybeBrain = b;
    anim = LiveAnimator(b);
  }

  Brain? _maybeBrain;

  void _tick(Duration now) {
    final dt = ((now - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = now;
    if (dt <= 0) return;
    brain.update(dt * speed);
    anim.update(dt * speed);
    frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _ui?.cancel();
    frame.dispose();
    super.dispose();
  }

  void _drop(String kind) {
    final x = (_rng.nextDouble() * 2 - 1) * brain.halfW * 0.75;
    final z = (_rng.nextDouble() * 2 - 1) * brain.halfD * 0.7;
    if (kind == 'visitor') {
      brain.drop(kind, (_rng.nextBool() ? 1 : -1) * brain.halfW * 0.85, z);
    } else {
      brain.drop(kind, x, z);
    }
  }

  void _breed() {
    final mate = Genome.fromSeed(_rng.nextInt(1 << 31));
    final child = Genome.child(genome, mate, _rng.nextInt(1 << 31));
    lineage = '${genome.describe()} x ${mate.describe()}';
    _seat(child);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6EFE4),
      appBar: AppBar(title: const Text('Live pet lab'), backgroundColor: const Color(0xFFF6EFE4)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
        children: [
          AspectRatio(
            aspectRatio: 1.15,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: LayoutBuilder(
                builder: (context, box) => GestureDetector(
                  onTapUp: (d) {
                    final st = _Stage(this, box.biggest);
                    final at = st.project(brain.x, 0, brain.z);
                    final hit = (d.localPosition - Offset(at.dx, at.dy - st.scale * brain.size * 0.45)).distance < st.scale * brain.size * 0.6;
                    if (hit) brain.pet();
                  },
                  child: CustomPaint(painter: _StagePainter(this), size: box.biggest),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(genome.describe(), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF4A3426))),
          Text(
            'Seed ${genome.seed}${genome.generation > 0 ? '  ·  generation ${genome.generation}' : ''}${lineage != null ? '\nChild of $lineage' : ''}',
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A6656)),
          ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _btn('New egg', () => setState(() {
                  lineage = null;
                  _seat(Genome.fromSeed(_rng.nextInt(1 << 31)));
                })),
            _btn('Breed it', () => setState(_breed)),
            _btn('Colour: $palette', () => setState(() {
                  final ps = model?.palettes ?? const ['amber'];
                  palette = ps[(ps.indexOf(palette) + 1) % ps.length];
                })),
            _btn('Speed ${speed.toStringAsFixed(0)}x', () => setState(() => speed = speed >= 8 ? 1 : speed * 2)),
          ]),
          const SizedBox(height: 14),
          _card('Put something in front of it', Wrap(spacing: 8, runSpacing: 8, children: [
            _btn('Food', () => _drop('food')),
            _btn('Something new', () => _drop('object')),
            _btn('A visitor', () => _drop('visitor')),
            _btn('Pet it', brain.pet),
          ])),
          _card('What it is doing', _doing()),
          _card('Needs (the tick: where it acts on one)', Column(children: [
            for (final e in brain.needs.all.entries) _need(e.key, e.value, brain.tuning.threshold[e.key]!),
          ])),
          _card('Genes', Column(children: [
            for (final g in geneNames) _gene(g),
          ])),
          _card('How it moves (from its genes)', Text(
            'Pace ${brain.quirks.tempo.toStringAsFixed(2)}  ·  hop ${(brain.quirks.hop * 100).round()}% of its height  ·  '
            'glances ${brain.quirks.glance.toStringAsFixed(2)}/s  ·  posture ${brain.quirks.posture.toStringAsFixed(1)}°  ·  '
            'blinks every ${brain.quirks.blink.toStringAsFixed(1)} s  ·  idle habit: ${brain.quirks.idle}',
            style: const TextStyle(fontSize: 13, color: Color(0xFF5A4636), height: 1.4),
          )),
        ],
      ),
    );
  }

  Widget _doing() {
    final a = brain.act;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${a.name.replaceAll('_', ' ')}  (${a.step})', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF4A3426))),
      Text(a.why, style: const TextStyle(fontSize: 12, color: Color(0xFF7A6656))),
      const SizedBox(height: 6),
      for (final s in brain.scores.take(5))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            SizedBox(width: 108, child: Text(s.name.replaceAll('_', ' '), style: const TextStyle(fontSize: 12.5))),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: (s.total / 2.5).clamp(0.0, 1.0),
                  minHeight: 8,
                  backgroundColor: const Color(0xFFEADFCF),
                  color: s.name == a.name ? const Color(0xFFE0913A) : const Color(0xFFB9A58C),
                ),
              ),
            ),
            SizedBox(
                width: 110,
                child: Text('  ${s.base.toStringAsFixed(2)} x ${s.gene.toStringAsFixed(2)}',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF7A6656)))),
          ]),
        ),
    ]);
  }

  Widget _need(String k, double v, double th) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          SizedBox(width: 80, child: Text(k, style: const TextStyle(fontSize: 13))),
          Expanded(
            child: LayoutBuilder(
              builder: (c, b) => Stack(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                      value: v, minHeight: 10, backgroundColor: const Color(0xFFEADFCF), color: v < th ? const Color(0xFFD9634A) : const Color(0xFF6FA552)),
                ),
                Positioned(left: b.maxWidth * th - 1, top: -2, child: Container(width: 2, height: 14, color: const Color(0xFF4A3426))),
              ]),
            ),
          ),
          SizedBox(width: 44, child: Text(' ${(v * 100).round()}%', style: const TextStyle(fontSize: 12))),
        ]),
      );

  Widget _gene(String g) {
    final (label, low, high) = geneInfo[g]!;
    return Row(children: [
      SizedBox(width: 108, child: Text(label, style: const TextStyle(fontSize: 13))),
      Expanded(
        child: Slider(
          value: genome[g],
          onChanged: (v) => setState(() => _seat(genome.copyWith(g, (v * 100).round() / 100))),
        ),
      ),
      SizedBox(
          width: 86,
          child: Text('${genome.score(g)}  ${genome[g] >= 0.5 ? high : low}', style: const TextStyle(fontSize: 12, color: Color(0xFF7A6656)))),
    ]);
  }

  Widget _btn(String label, VoidCallback onTap) => FilledButton.tonal(
        onPressed: onTap,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFFF0E2CC),
          foregroundColor: const Color(0xFF4A3426),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          visualDensity: VisualDensity.compact,
        ),
        child: Text(label),
      );

  Widget _card(String title, Widget child) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: const Color(0xFFFFFBF4), borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFEADFCF))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF4A3426))),
          const SizedBox(height: 8),
          child,
        ]),
      );
}

/// the stage's camera: the clips' (orthographic, turned 18°, looking down 13°), fitted to the box
class _Stage {
  _Stage(this.s, this.box)
      : scale = box.width / (s.brain.halfW * 2 + s.brain.size * 1.2),
        origin = Offset(box.width / 2, box.height * 0.6);
  final _LiveLabScreenState s;
  final Size box;
  final double scale;
  final Offset origin;

  /// the clips look from 13° up; the live one can be seen from anywhere, so a little higher shows the floor
  static const pitch = 20.0;
  static final _cy = 18 * math.pi / 180, _cp = pitch * math.pi / 180;

  Offset project(double x, double y, double z) {
    final r = [math.cos(_cy), 0.0, -math.sin(_cy)];
    final d = [math.sin(_cy) * math.cos(_cp), math.sin(_cp), math.cos(_cy) * math.cos(_cp)];
    final u = [d[1] * r[2] - d[2] * r[1], d[2] * r[0] - d[0] * r[2], d[0] * r[1] - d[1] * r[0]];
    return Offset(origin.dx + (x * r[0] + y * r[1] + z * r[2]) * scale, origin.dy - (x * u[0] + y * u[1] + z * u[2]) * scale);
  }

  /// how far from you (bigger: farther)
  double depth(double x, double z) => -(x * math.sin(_cy) * math.cos(_cp) + z * math.cos(_cy) * math.cos(_cp));
}

class _StagePainter extends CustomPainter {
  _StagePainter(this.s) : super(repaint: s.frame);
  final _LiveLabScreenState s;

  @override
  void paint(Canvas canvas, Size size) {
    final st = _Stage(s, size);
    final b = s.brain;
    // the sky and the meadow
    canvas.drawRect(Offset.zero & size, Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, size.height), const [Color(0xFFBFE3F2), Color(0xFFE9F4E4)], const [0.0, 0.5]));
    final floor = Path()
      ..moveTo(st.project(-b.halfW - 30, 0, -b.halfD - 10).dx, st.project(-b.halfW - 30, 0, -b.halfD - 10).dy)
      ..lineTo(st.project(b.halfW + 30, 0, -b.halfD - 10).dx, st.project(b.halfW + 30, 0, -b.halfD - 10).dy)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(floor, Paint()
      ..shader = ui.Gradient.linear(Offset(0, size.height * 0.35), Offset(0, size.height), const [Color(0xFF8CC063), Color(0xFF5E9A48)]));
    // what is on the floor and the Eggling, far ones first
    final draws = <(double, void Function())>[];
    for (final t in b.things) {
      draws.add((st.depth(t.x, t.z), () => _thing(canvas, st, t)));
    }
    final r = s.renderer;
    draws.add((st.depth(b.x, b.z), () {
      final at = st.project(b.x, 0, b.z);
      final lift = s.anim.pose.v[7];
      // its shadow, smaller as it leaves the ground
      final sh = (1 - (lift / b.size).clamp(0.0, 0.6));
      canvas.drawOval(Rect.fromCenter(center: at, width: st.scale * b.size * 0.95 * sh, height: st.scale * b.size * 0.28 * sh),
          Paint()..color = const Color(0x33203010));
      if (r != null) {
        r.paint(canvas, at, st.scale, s.anim.pose,
            palette: s.palette, expression: s.anim.expression, camPitch: _Stage.pitch, outlinePx: math.max(1.5, st.scale * 0.21));
      }
    }));
    draws.sort((p, q) => q.$1.compareTo(p.$1));
    for (final d in draws) {
      d.$2();
    }
    if (r == null) {
      final tp = TextPainter(text: const TextSpan(text: 'Loading the live Eggling…', style: TextStyle(color: Color(0xFF4A3426))), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(canvas, Offset(size.width / 2 - tp.width / 2, size.height / 2));
    }
  }

  void _thing(Canvas canvas, _Stage st, Thing t) {
    final at = st.project(t.x, 0, t.z);
    final w = st.scale * s.brain.size * (t.kind == 'visitor' ? 0.42 : 0.5);
    canvas.drawOval(Rect.fromCenter(center: at, width: w * 0.9, height: w * 0.25), Paint()..color = const Color(0x2A203010));
    final img = s._images[t.kind];
    if (img != null) {
      final dst = Rect.fromCenter(center: at.translate(0, -w * 0.42), width: w, height: w);
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), dst, Paint()..filterQuality = FilterQuality.medium);
    } else if (t.kind == 'visitor') {
      // a ladybird come to see
      final bob = math.sin(t.age * 9) * w * 0.04;
      final c = at.translate(0, -w * 0.28 + bob);
      canvas.drawOval(Rect.fromCenter(center: c.translate(w * 0.36, 0), width: w * 0.34, height: w * 0.3), Paint()..color = const Color(0xFF2B2422));
      canvas.drawOval(Rect.fromCenter(center: c, width: w * 0.8, height: w * 0.6), Paint()..color = const Color(0xFFD8453A));
      canvas.drawLine(c.translate(0, -w * 0.3), c.translate(0, w * 0.3), Paint()
        ..color = const Color(0xFF2B2422)
        ..strokeWidth = math.max(1, w * 0.04));
      for (final o in [const Offset(-0.2, -0.1), const Offset(0.18, 0.08), const Offset(-0.14, 0.14), const Offset(0.16, -0.14)]) {
        canvas.drawCircle(c.translate(o.dx * w, o.dy * w), w * 0.065, Paint()..color = const Color(0xFF2B2422));
      }
    }
    if (t.kind == 'object' && t.novelty > 0.05) {
      // a sparkle while it is still new to it
      final p = at.translate(w * 0.3, -w * 0.85);
      final k = 0.6 + 0.4 * math.sin(t.age * 5);
      final paint = Paint()
        ..color = Color.fromRGBO(255, 248, 210, t.novelty * k)
        ..strokeWidth = 2;
      canvas.drawLine(p.translate(-6, 0), p.translate(6, 0), paint);
      canvas.drawLine(p.translate(0, -6), p.translate(0, 6), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StagePainter old) => true;
}
