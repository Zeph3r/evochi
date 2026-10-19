// Layered 2.5D habitat scene + animated pet (style guide §03 layering, §20 animation).
// Back to front: sky -> far -> mid -> back decorations -> pet shadow -> pet -> front decorations -> near flora -> UI.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/services/asset_manifest.dart';
import '../../game/vitality/vitality.dart';

const _worldScale = {1: 0.205, 2: 0.2, 3: 0.165};

class PetConfig {
  const PetConfig({
    required this.stage,
    required this.palette,
    this.status = PetStatus.healthy,
    this.equipped = const [],
    this.sleeping = false,
    this.scale = 1,
    this.expr = 'default',
    this.visible = true,
  });
  final int stage;
  final String palette;
  final PetStatus status;
  final List<String> equipped;
  final bool sleeping;
  final double scale;
  final String expr;
  final bool visible;
}

class SceneConfig {
  const SceneConfig({
    required this.habitat,
    this.focus = const Offset(0.5, 0.4),
    this.zoom = 1,
    this.decor = const {},
    this.platform = false,
    this.pet,
    this.forceExpr,
    this.reducedMotion = false,
    this.background = const Color(0xFF86C95B),
  });
  final String habitat; // meadow | market | welcome
  /// Where the pet's ground point lands: fractions (<= 1) of the scene size, or pixels.
  final Offset focus;
  final double zoom;
  final Map<String, String> decor;
  final bool platform;
  final PetConfig? pet;
  final String? forceExpr;
  final bool reducedMotion;
  final Color background;
}

/// Where [HabitatScene] draws the pet in a scene of [size] (its atlas frame, before any reaction
/// motion), or null without a visible pet. The same placement as HabitatScene.build: keep them in step.
Rect? scenePetRect(SceneConfig cfg, Size size) {
  final p = cfg.pet;
  if (p == null || !p.visible || size.isEmpty) return null;
  final m = AssetManifest.instance!;
  final hab = m.habitat(cfg.habitat);
  final w = size.width, h = size.height;
  final k = w / hab.w * cfg.zoom;
  final anchor = hab.pet;
  final fx = cfg.focus.dx <= 1 ? cfg.focus.dx * w : cfg.focus.dx;
  final fy = cfg.focus.dy <= 1 ? cfg.focus.dy * h : cfg.focus.dy;
  final ox = (fx - anchor.dx * k).clamp(math.min(0.0, w - hab.w * k), 0.0).toDouble();
  final oy = math.min(0.0, fy - anchor.dy * k);
  final ground = Offset(ox + anchor.dx * k, oy + anchor.dy * k);
  final e = m.char(p.stage);
  final s = hab.petPxPerUnit * k * (_worldScale[p.stage] ?? 0.2) * p.scale / e.scale;
  final a = e.anchor('ground');
  return Rect.fromLTWH(ground.dx - a.dx * s, ground.dy - a.dy * s, e.w * s, e.h * s);
}

class _Reaction {
  _Reaction(this.expr, this.motion, this.start, this.dur);
  final String expr;
  final String motion;
  final Duration start;
  final Duration dur;
}

class _Particle {
  _Particle(this.kind, this.born, this.life, this.x, this.vx, this.vy, this.s, this.rot);
  final String kind;
  final Duration born;
  final Duration life;
  final double x, vx, vy, s, rot;
}

/// Imperative handle for one-shot pet reactions (pet, play, inspect, reward, equip...).
class SceneController extends ChangeNotifier {
  final List<String> _queue = [];
  Rect? petRect;
  void react(String kind) {
    _queue.add(kind);
    notifyListeners();
  }
}

class HabitatScene extends StatefulWidget {
  const HabitatScene({super.key, required this.config, required this.controller, this.onPetTap, this.petLabel = 'Your Evochi'});
  final SceneConfig config;
  final SceneController controller;
  final VoidCallback? onPetTap;
  final String petLabel;
  @override
  State<HabitatScene> createState() => _HabitatSceneState();
}

class _HabitatSceneState extends State<HabitatScene> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration _t = Duration.zero;
  final _repaint = ValueNotifier<int>(0);
  _Reaction? _reaction;
  final List<_Particle> _particles = [];
  Duration _nextBlink = const Duration(seconds: 2);
  Duration _blinkUntil = Duration.zero;
  Duration _nextIdle = const Duration(seconds: 8);
  Duration _idleUntil = Duration.zero;
  String _idleExpr = 'curious';
  final _rng = math.Random();
  ui.Image? _atlas, _overlays, _heart, _star;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((t) {
      // 30 fps target (style guide §20)
      if ((t - _t).inMilliseconds >= 32) {
        _t = t;
        _repaint.value++;
      }
    })
      ..start();
    widget.controller.addListener(_onReact);
    _loadImages();
    final m = AssetManifest.instance!;
    AtlasCache.load(m.icon('heart')).then((i) => _heart = i);
    AtlasCache.load(m.icon('star')).then((i) => _star = i);
  }

  @override
  void didUpdateWidget(HabitatScene old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onReact);
      widget.controller.addListener(_onReact);
    }
    final a = old.config.pet, b = widget.config.pet;
    if (a?.stage != b?.stage || a?.palette != b?.palette) _loadImages();
  }

  void _loadImages() {
    final p = widget.config.pet;
    if (p == null) return;
    final e = AssetManifest.instance!.char(p.stage);
    AtlasCache.load(artBase + e.atlasFile(p.palette)).then((i) {
      if (mounted) setState(() => _atlas = i);
    });
    AtlasCache.load(artBase + e.overlaysFile).then((i) {
      if (mounted) setState(() => _overlays = i);
    });
  }

  void _onReact() {
    final q = widget.controller._queue;
    while (q.isNotEmpty) {
      final kind = q.removeAt(0);
      const spec = {
        'pet': ['happy', 'bounce', '1000', 'hearts'],
        'play': ['excited', 'hop', '1300', 'stars'],
        'inspect': ['curious', 'tilt', '1200', ''],
        'reward': ['happy', 'bounce', '1100', 'stars'],
        'surprised': ['surprised', 'hop', '900', ''],
        'equip': ['happy', 'wiggle', '700', 'stars'],
        'sad': ['sad', 'none', '1400', ''],
        'snack': ['excited', 'hop', '1000', 'hearts'], // food picked in the Bag
      };
      final s = spec[kind];
      if (s == null) continue;
      final motion = widget.config.reducedMotion ? 'none' : s[1];
      _reaction = _Reaction(s[0], motion, _t, Duration(milliseconds: int.parse(s[2])));
      if (s[3].isNotEmpty) _burst(s[3]);
    }
  }

  void _burst(String kind) {
    final n = widget.config.reducedMotion ? 2 : 6;
    for (var i = 0; i < n; i++) {
      _particles.add(_Particle(
        kind,
        _t + Duration(milliseconds: i * 60),
        Duration(milliseconds: 1100 + _rng.nextInt(300)),
        (_rng.nextDouble() - 0.5) * 0.6,
        (_rng.nextDouble() - 0.5) * 0.25,
        -0.6 - _rng.nextDouble() * 0.4,
        0.7 + _rng.nextDouble() * 0.5,
        (_rng.nextDouble() - 0.5) * 0.6,
      ));
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    widget.controller.removeListener(_onReact);
    _repaint.dispose();
    super.dispose();
  }

  String _expression() {
    final p = widget.config.pet!;
    if (widget.config.forceExpr != null) return widget.config.forceExpr!;
    var expr = switch (p.status) {
      PetStatus.dead => 'memorial',
      PetStatus.sick => 'sick',
      PetStatus.neutral => 'neutral',
      PetStatus.healthy => p.expr,
    };
    if (p.sleeping && p.status != PetStatus.dead) expr = 'sleepy';
    final r = _reaction;
    if (r != null && _t < r.start + r.dur) return r.expr;
    _reaction = null;
    final alive = p.status != PetStatus.dead;
    if (alive && !p.sleeping && p.status == PetStatus.healthy && !widget.config.reducedMotion) {
      if (_t > _nextIdle) {
        _idleUntil = _t + const Duration(milliseconds: 1400);
        _idleExpr = _rng.nextBool() ? 'curious' : 'happy';
        _nextIdle = _t + Duration(milliseconds: 9000 + _rng.nextInt(9000));
      }
      if (_t < _idleUntil) expr = _idleExpr;
    }
    if (alive && (expr == 'default' || expr == 'neutral')) {
      if (_t > _nextBlink) {
        _blinkUntil = _t + const Duration(milliseconds: 130);
        _nextBlink = _t + Duration(milliseconds: 2600 + _rng.nextInt(3200));
      }
      if (_t < _blinkUntil) expr = 'blink';
    }
    return expr;
  }

  @override
  Widget build(BuildContext context) {
    final m = AssetManifest.instance!;
    final cfg = widget.config;
    final hab = m.habitat(cfg.habitat);
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth, h = box.maxHeight;
      final k = w / hab.w * cfg.zoom;
      final anchor = hab.pet;
      final fx = cfg.focus.dx <= 1 ? cfg.focus.dx * w : cfg.focus.dx;
      final fy = cfg.focus.dy <= 1 ? cfg.focus.dy * h : cfg.focus.dy;
      final ox = (fx - anchor.dx * k).clamp(math.min(0.0, w - hab.w * k), 0.0).toDouble();
      final oy = math.min(0.0, fy - anchor.dy * k);
      final ground = Offset(ox + anchor.dx * k, oy + anchor.dy * k);
      Widget layer(String name) {
        final f = hab.layer(name);
        if (f == null) return const SizedBox.shrink();
        return Positioned(left: ox, top: oy, width: hab.w * k, child: Image.asset(artBase + f, fit: BoxFit.fitWidth, gaplessPlayback: true, excludeFromSemantics: true));
      }

      final back = <Widget>[];
      final front = <Widget>[];
      if (cfg.habitat == 'meadow') {
        final entries = cfg.platform ? {'nest': 'platform'} : cfg.decor;
        entries.forEach((slot, itemId) {
          final d = hab.decor['$itemId@$slot'];
          if (d == null) return;
          final wgt = Positioned(
            left: ox + (d['x'] as num) * k,
            top: oy + (d['y'] as num) * k,
            width: (d['w'] as num) * k,
            child: Image.asset(artBase + (d['file'] as String), fit: BoxFit.fitWidth, excludeFromSemantics: true),
          );
          (slot == 'left' || slot == 'right' ? front : back).add(wgt);
        });
      }

      final p = cfg.pet;
      Rect? petRect;
      double petScale = 1;
      if (p != null && p.visible) {
        final e = m.char(p.stage);
        final unit = hab.petPxPerUnit * k * (_worldScale[p.stage] ?? 0.2) * p.scale;
        petScale = unit / e.scale;
        final a = e.anchor('ground');
        petRect = Rect.fromLTWH(ground.dx - a.dx * petScale, ground.dy - a.dy * petScale, e.w * petScale, e.h * petScale);
        widget.controller.petRect = petRect;
      }

      return ClipRect(
        child: ColoredBox(
          color: cfg.background,
          child: Stack(children: [
            layer('sky'),
            layer('far'),
            layer('mid'),
            ...back,
            if (p != null && p.visible)
              Positioned.fill(
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: _PetPainter(
                      state: this,
                      repaint: _repaint,
                      ground: ground,
                      scale: petScale,
                    ),
                  ),
                ),
              ),
            ...front,
            layer('near'),
            if (petRect != null && widget.onPetTap != null)
              Positioned(
                left: ground.dx - petRect.width * 0.31,
                top: ground.dy - petRect.height * 0.8,
                width: petRect.width * 0.62,
                height: petRect.height * 0.8,
                child: Semantics(
                  button: true,
                  label: widget.petLabel,
                  child: GestureDetector(behavior: HitTestBehavior.opaque, onTap: widget.onPetTap),
                ),
              ),
          ]),
        ),
      );
    });
  }
}

class _PetPainter extends CustomPainter {
  _PetPainter({required this.state, required Listenable repaint, required this.ground, required this.scale}) : super(repaint: repaint);
  final _HabitatSceneState state;
  final Offset ground;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    final cfg = state.widget.config;
    final p = cfg.pet!;
    final atlas = state._atlas;
    if (atlas == null) return;
    final m = AssetManifest.instance!;
    final e = m.char(p.stage);
    final expr = state._expression();
    final src = e.frame(p.palette, expr);
    final a = e.anchor('ground');
    final t = state._t.inMicroseconds / 1e6;
    final reduce = cfg.reducedMotion;
    final alive = p.status != PetStatus.dead;
    final rate = p.status == PetStatus.sick ? 0.22 : (p.status == PetStatus.neutral ? 0.3 : 0.38);
    final amp = !alive ? 0.0 : (reduce ? 0.004 : (p.status == PetStatus.sick ? 0.008 : 0.014));
    var sx = 1 - amp * 0.5 * math.sin(t * math.pi * 2 * rate);
    var sy = 1 + amp * math.sin(t * math.pi * 2 * rate);
    var dy = 0.0;
    var rot = 0.0;
    final r = state._reaction;
    if (r != null) {
      final mt = ((state._t - r.start).inMicroseconds / r.dur.inMicroseconds).clamp(0.0, 1.0);
      final hpx = e.h * scale;
      switch (r.motion) {
        case 'bounce':
          final b = math.sin(math.min(1, mt * 2) * math.pi);
          dy = -b * hpx * 0.08;
          sy *= 1 + b * 0.04;
          sx *= 1 - b * 0.03;
          if (mt > 0.5) dy = -math.sin((mt - 0.5) * 2 * math.pi) * hpx * 0.035;
        case 'hop':
          final ph = (mt * 2) % 1;
          final b = math.sin(ph * math.pi);
          dy = -b * hpx * 0.13;
          final squash = (ph < 0.12 || ph > 0.88) ? 0.06 : 0.0;
          sy *= 1 - squash + b * 0.03;
          sx *= 1 + squash;
        case 'tilt':
          rot = math.sin(math.min(1, mt * 1.6) * math.pi) * 0.09;
        case 'wiggle':
          rot = math.sin(mt * math.pi * 6) * 0.05 * (1 - mt);
      }
    }
    // shadow
    final shW = math.max(4.0, e.w * scale * (p.stage == 1 ? 0.42 : 0.5) * (1 + dy / (e.h * scale) * 0.8));
    canvas.drawOval(Rect.fromCenter(center: ground.translate(0, -2), width: shW * 2, height: math.max(4.0, shW * 0.32)), Paint()..color = const Color(0x38342616));
    canvas.save();
    canvas.translate(ground.dx, ground.dy + dy);
    canvas.rotate(rot);
    canvas.scale(scale * sx, scale * sy);
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, alive ? 1 : 0.92);
    canvas.drawImageRect(atlas, src, Rect.fromLTWH(-a.dx, -a.dy, src.width, src.height), paint);
    final ov = state._overlays;
    if (ov != null && alive) {
      for (final id in p.equipped) {
        final o = e.overlay(id);
        if (o != null) canvas.drawImageRect(ov, o, Rect.fromLTWH(-a.dx, -a.dy, o.width, o.height), paint);
      }
    }
    canvas.restore();
    // particles
    final head = Offset(ground.dx + (e.anchor('head_top').dx - a.dx) * scale, ground.dy + dy + (e.anchor('head_top').dy - a.dy) * scale);
    final hpx = e.h * scale;
    state._particles.removeWhere((q) => state._t - q.born > q.life);
    for (final q in state._particles) {
      final age = state._t - q.born;
      if (age.isNegative) continue;
      final k = age.inMicroseconds / q.life.inMicroseconds;
      final alpha = k < 0.15 ? k / 0.15 : 1 - math.max(0, (k - 0.6) / 0.4);
      final img = q.kind == 'hearts' ? state._heart : state._star;
      if (img == null) continue;
      final x = head.dx + (q.x + q.vx * k * 2) * hpx;
      final y = head.dy + hpx * 0.25 + q.vy * k * hpx * 0.7;
      final size = 22 * q.s;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(q.rot * k);
      canvas.drawImageRect(img, Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()), Rect.fromCenter(center: Offset.zero, width: size, height: size),
          Paint()..color = Color.fromRGBO(255, 255, 255, alpha.clamp(0.0, 1.0).toDouble()));
      canvas.restore();
    }
    if (p.sleeping && alive && !reduce) _drawZ(canvas, t, head);
  }

  void _drawZ(Canvas canvas, double t, Offset head) {
    for (var i = 0; i < 2; i++) {
      final k = (t * 0.35 + i * 0.5) % 1;
      final tp = TextPainter(
        text: TextSpan(
          text: 'z',
          style: TextStyle(
            fontFamily: 'Nunito',
            fontWeight: FontWeight.w900,
            fontSize: 16.0 + i * 6,
            color: Color.fromRGBO(59, 41, 35, math.sin(k * math.pi)),
            shadows: const [Shadow(color: Color(0xFFFFF9F0), blurRadius: 3)],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(head.dx + 30 + k * 18, head.dy - 10 - k * 34));
    }
  }

  @override
  bool shouldRepaint(_PetPainter old) => old.ground != ground || old.scale != scale || old.state != state;
}
