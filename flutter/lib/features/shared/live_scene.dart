// Living scenes: the pre-rendered backgrounds, with motion layered on. Where tools/art/scene_fx.py
// baked a mask for an image, [LiveImage] draws it through shaders/scene_fx.frag (trees sway in
// gusts, grass catches travelling light, water ripples and falls, fire flickers, lamps breathe,
// smoke wavers) and paints the scene's emitters over it (glows, embers, smoke and steam, bubbles,
// dust, pollen, fireflies, sparks, drifting leaves). An image without a mask is just an image, so
// LiveImage can stand in for Image.asset anywhere a scene is drawn.
//
// Cheap on purpose: one shader pass, one or two drawAtlas calls, repainted at ~30 fps, and only while
// the scene's route and tab are on screen (the Ticker follows TickerMode). Reduced motion: a still
// picture with its lights on.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

/// One scene's effects: its mask and its emitters, from assets/config/scene_fx.json.
class SceneFx {
  SceneFx._(this.mask, this.width, this.height, this.emitters);
  final String mask;
  final double width;
  final double height;
  final List<FxEmitter> emitters;

  static final Map<String, SceneFx> _all = {};
  static Future<ui.FragmentProgram?>? _program;
  static ui.Image? _atlas;

  /// The scene effects for an asset path (as passed to Image.asset), or null.
  static SceneFx? of(String asset) => _all[asset];

  /// Read the effect table and warm the shader. Safe to skip: scenes then stay still.
  static Future<void> load() async {
    try {
      final raw = jsonDecode(await rootBundle.loadString('assets/config/scene_fx.json')) as Map<String, dynamic>;
      raw.forEach((path, v) {
        final m = v as Map<String, dynamic>;
        final list = (m['emit'] as List? ?? const []);
        _all[path] = SceneFx._(
          m['mask'] as String,
          (m['w'] as num).toDouble(),
          (m['h'] as num).toDouble(),
          [for (var i = 0; i < list.length; i++) FxEmitter.fromJson(list[i] as Map<String, dynamic>, i)],
        );
      });
    } catch (e) {
      debugPrint('scene fx: $e');
    }
    unawaited(program());
    _atlas ??= _buildAtlas();
  }

  /// Paint [fx]'s emitters at time [t] (in the scene image's own px: scale the canvas first), for a
  /// screen that draws a scene itself (the walkable village).
  static void paintEmitters(Canvas canvas, SceneFx fx, double t, {bool moving = true, ColorFilter? filter}) {
    final atlas = _atlas;
    if (atlas == null || fx.emitters.isEmpty) return;
    _Particles(atlas, t, moving).paint(canvas, fx.emitters, filter);
  }

  static Future<ui.FragmentProgram?> program() => _program ??= () async {
        try {
          return await ui.FragmentProgram.fromAsset('shaders/scene_fx.frag');
        } catch (e) {
          debugPrint('scene fx shader: $e');
          return null;
        }
      }();

  /// Four 64 px sprites side by side: a soft dot, a square, a leaf and a ring. Drawn white and tinted
  /// per particle.
  static ui.Image _buildAtlas() {
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    // 0: soft dot
    c.drawCircle(
      const Offset(32, 32),
      31,
      Paint()
        ..shader = ui.Gradient.radial(const Offset(32, 32), 31, const [Color(0xFFFFFFFF), Color(0x8CFFFFFF), Color(0x00FFFFFF)], const [0, 0.35, 1]),
    );
    // 1: a voxel square
    c.drawRect(const Rect.fromLTWH(64 + 8, 8, 48, 48), Paint()..color = const Color(0xFFFFFFFF));
    // 2: a voxel leaf: blocks in a teardrop, a lighter half and a darker vein
    const leaf = [
      (2, 0, 1.0), (1, 1, 1.0), (2, 1, 0.85), (3, 1, 0.8),
      (0, 2, 1.0), (1, 2, 0.95), (2, 2, 0.7), (3, 2, 0.8), (4, 2, 0.75),
      (1, 3, 0.9), (2, 3, 0.7), (3, 3, 0.75), (2, 4, 0.6),
    ];
    for (final (x, y, l) in leaf) {
      final v = (255 * l).round();
      c.drawRect(Rect.fromLTWH(128 + 7 + x * 10.0, 7 + y * 10.0, 10, 10), Paint()..color = Color.fromARGB(255, v, v, v));
    }
    // 3: a bubble ring with a glint
    c.drawCircle(const Offset(192 + 32, 32), 24, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..color = const Color(0xFFFFFFFF));
    c.drawCircle(const Offset(192 + 24, 23), 5, Paint()..color = const Color(0xFFFFFFFF));
    return rec.endRecording().toImageSync(256, 64);
  }
}

enum _Kind { glow, embers, smoke, bubbles, motes, leaves }

/// An emitter from the table (sizes in image px). See tools/art/scene_fx.py.
class FxEmitter {
  FxEmitter._(this.kind, this.style, this.x, this.y, this.w, this.h, this.r, this.n, this.s, this.a, this.drift, this.colors, this.seed);
  final _Kind kind;
  final String style; // glow: fire|lamp|crystal|sun; smoke: smoke|steam; motes: dust|pollen|firefly|spark
  final double x, y, w, h, r, s, a, drift;
  final int n;
  final List<Color> colors;
  final int seed;

  static Color _hex(String v) => Color(int.parse('FF${v.replaceFirst('#', '')}', radix: 16));

  factory FxEmitter.fromJson(Map<String, dynamic> j, int index) {
    final kind = _Kind.values.byName(j['t'] as String);
    double d(String k, double or) => (j[k] as num?)?.toDouble() ?? or;
    final c = j['c'];
    final colors = c is List
        ? [for (final x in c) _hex(x as String)]
        : c is String
            ? [_hex(c)]
            : switch (kind) {
                _Kind.glow => [const Color(0xFFFFC66B)],
                _Kind.embers => [const Color(0xFFFF7A2A)],
                _Kind.smoke => [const Color(0xFFF2EEE8)],
                _Kind.bubbles => [const Color(0xFFE8FFF0)],
                _Kind.motes => [const Color(0xFFFFF6C8)],
                _Kind.leaves => const [Color(0xFF6FAE3C), Color(0xFF8CC152), Color(0xFFA7C957), Color(0xFF5C9A34)],
              };
    return FxEmitter._(
      kind,
      (j['kind'] as String?) ?? switch (kind) { _Kind.glow => 'lamp', _Kind.smoke => 'smoke', _Kind.motes => 'dust', _ => '' },
      d('x', 0),
      d('y', 0),
      d('w', 20),
      d('h', kind == _Kind.smoke ? 120 : 60),
      d('r', 40),
      (j['n'] as num?)?.toInt() ?? switch (kind) { _Kind.glow => 1, _Kind.leaves => 3, _Kind.smoke => 6, _ => 10 },
      d('s', switch (kind) { _Kind.smoke => 12, _Kind.bubbles => 5, _Kind.leaves => 9, _ => 3 }),
      d('a', kind == _Kind.smoke ? 0.45 : 0.5),
      d('drift', 0),
      colors,
      index * 977 + 13,
    );
  }
}

/// A scene image that moves where its mask says. Give it a size (it fills its box like Image.asset
/// with [fit] and [alignment]). Unknown images are drawn still.
class LiveImage extends StatefulWidget {
  const LiveImage(
    this.asset, {
    super.key,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.colorFilter,
    this.semanticLabel,
    this.excludeFromSemantics = false,
    this.particles = true,
    this.motion = 1,
  });
  final String asset;
  final BoxFit fit;
  final Alignment alignment;
  final ColorFilter? colorFilter;
  final String? semanticLabel;
  final bool excludeFromSemantics;

  /// Draw the emitters (glows, smoke, leaves...). Off for small previews.
  final bool particles;

  /// How much it all moves (the wind; 0 = still).
  final double motion;

  @override
  State<LiveImage> createState() => _LiveImageState();
}

class _LiveImageState extends State<LiveImage> with TickerProviderStateMixin {
  ImageStream? _stream;
  ImageStreamListener? _listener;
  ImageInfo? _image;
  ImageStream? _maskStream;
  ImageStreamListener? _maskListener;
  ImageInfo? _mask;
  ui.FragmentShader? _shader;
  Ticker? _ticker;
  final _time = ValueNotifier<double>(0);
  double _lastFrame = -1;
  final double _t0 = math.Random().nextDouble() * 120; // scenes don't move in lockstep
  bool _still = false;

  SceneFx? get _fx => SceneFx.of(widget.asset);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _resolve();
    _sync();
  }

  @override
  void didUpdateWidget(LiveImage old) {
    super.didUpdateWidget(old);
    if (old.asset != widget.asset) _resolve();
    _sync();
  }

  void _resolve() {
    final cfg = createLocalImageConfiguration(context);
    final s = AssetImage(widget.asset).resolve(cfg);
    if (s.key != _stream?.key) {
      if (_listener != null) _stream?.removeListener(_listener!);
      _stream = s;
      _listener = ImageStreamListener((info, _) {
        if (!mounted) {
          info.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = info;
        });
      });
      s.addListener(_listener!);
    }
    final fx = _fx;
    if (fx == null) {
      if (_maskListener != null) _maskStream?.removeListener(_maskListener!);
      _maskStream = null;
      _mask?.dispose();
      _mask = null;
      return;
    }
    final ms = AssetImage(fx.mask).resolve(cfg);
    if (ms.key != _maskStream?.key) {
      if (_maskListener != null) _maskStream?.removeListener(_maskListener!);
      _maskStream = ms;
      _maskListener = ImageStreamListener((info, _) {
        if (!mounted) {
          info.dispose();
          return;
        }
        setState(() {
          _mask?.dispose();
          _mask = info;
        });
      }, onError: (e, _) => debugPrint('scene fx mask: $e'));
      ms.addListener(_maskListener!);
    }
  }

  /// Start or stop the clock and fetch the shader, as the scene needs.
  void _sync() {
    final live = _fx != null && !_still && widget.motion > 0;
    if (live && _ticker == null) {
      _ticker = createTicker((elapsed) {
        final t = elapsed.inMicroseconds / 1e6;
        if (t - _lastFrame >= 1 / 30) {
          _lastFrame = t;
          _time.value = t;
        }
      })
        ..start();
    } else if (!live && _ticker != null) {
      _ticker!.dispose();
      _ticker = null;
    }
    if (_fx != null && _shader == null) {
      SceneFx.program().then((p) {
        if (!mounted || p == null || _shader != null) return;
        setState(() => _shader = p.fragmentShader());
      });
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    if (_listener != null) _stream?.removeListener(_listener!);
    if (_maskListener != null) _maskStream?.removeListener(_maskListener!);
    _image?.dispose();
    _mask?.dispose();
    _shader?.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = _image?.image;
    final fx = _fx;
    Widget child = img == null
        ? const SizedBox.expand()
        : SizedBox.expand(
            child: CustomPaint(
              isComplex: true,
              willChange: _ticker != null,
              painter: _LivePainter(
                image: img,
                mask: fx == null ? null : _mask?.image,
                shader: _shader,
                fx: fx,
                time: _time,
                t0: _t0,
                fit: widget.fit,
                alignment: widget.alignment,
                colorFilter: widget.colorFilter,
                motion: _still ? 0 : widget.motion,
                particles: widget.particles,
              ),
            ),
          );
    child = RepaintBoundary(child: child);
    if (widget.excludeFromSemantics || widget.semanticLabel == null) return ExcludeSemantics(child: child);
    return Semantics(image: true, label: widget.semanticLabel, child: child);
  }
}

class _LivePainter extends CustomPainter {
  _LivePainter({
    required this.image,
    required this.mask,
    required this.shader,
    required this.fx,
    required this.time,
    required this.t0,
    required this.fit,
    required this.alignment,
    required this.colorFilter,
    required this.motion,
    required this.particles,
  }) : super(repaint: time);
  final ui.Image image;
  final ui.Image? mask;
  final ui.FragmentShader? shader;
  final SceneFx? fx;
  final ValueNotifier<double> time;
  final double t0;
  final BoxFit fit;
  final Alignment alignment;
  final ColorFilter? colorFilter;
  final double motion;
  final bool particles;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final iw = image.width.toDouble(), ih = image.height.toDouble();
    final isz = Size(iw, ih);
    final fitted = applyBoxFit(fit, isz, size);
    final src = alignment.inscribe(fitted.source, Offset.zero & isz);
    final dst = alignment.inscribe(fitted.destination, Offset.zero & size);
    if (src.isEmpty || dst.isEmpty) return;
    final sx = dst.width / src.width, sy = dst.height / src.height;
    final whole = Rect.fromLTWH(dst.left - src.left * sx, dst.top - src.top * sy, iw * sx, ih * sy);
    final t = (t0 + time.value) % 600.0;
    final paint = Paint()
      ..filterQuality = FilterQuality.medium
      ..colorFilter = colorFilter;
    final m = mask;
    final sh = shader;
    if (sh != null && m != null && m.width == image.width && m.height == image.height && motion > 0) {
      sh
        ..setFloat(0, whole.left)
        ..setFloat(1, whole.top)
        ..setFloat(2, whole.width)
        ..setFloat(3, whole.height)
        ..setFloat(4, iw)
        ..setFloat(5, ih)
        ..setFloat(6, t)
        ..setFloat(7, motion)
        ..setFloat(8, 0)
        ..setFloat(9, 0)
        ..setImageSampler(0, image)
        ..setImageSampler(1, m);
      paint.shader = sh;
      canvas.drawRect(dst, paint);
    } else {
      canvas.drawImageRect(image, src, dst, paint);
    }
    final f = fx;
    final atlas = SceneFx._atlas;
    if (f == null || !particles || atlas == null || f.emitters.isEmpty) return;
    canvas.save();
    canvas.clipRect(dst);
    canvas.translate(whole.left, whole.top);
    canvas.scale(sx, sy);
    _Particles(atlas, t, motion > 0).paint(canvas, f.emitters, colorFilter);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_LivePainter old) =>
      old.image != image ||
      old.mask != mask ||
      old.shader != shader ||
      old.fx != fx ||
      old.fit != fit ||
      old.alignment != alignment ||
      old.colorFilter != colorFilter ||
      old.motion != motion ||
      old.particles != particles;
}

/// The emitters, as stateless functions of time: particle i of an emitter lives in cycles, and each
/// cycle re-rolls where it starts from (i, cycle). Nothing to update between frames.
class _Particles {
  _Particles(this.atlas, this.t, this.moving);
  final ui.Image atlas;
  final double t;
  final bool moving;

  static const _dot = Rect.fromLTWH(0, 0, 64, 64);
  static const _square = Rect.fromLTWH(64, 0, 64, 64);
  static const _leaf = Rect.fromLTWH(128, 0, 64, 64);
  static const _ring = Rect.fromLTWH(192, 0, 64, 64);

  final _xf = <RSTransform>[], _rc = <Rect>[], _col = <Color>[]; // normal blending
  final _axf = <RSTransform>[], _arc = <Rect>[], _acol = <Color>[]; // additive light

  static double _rnd(int a, int b, int c) {
    var x = (a * 73856093) ^ (b * 19349663) ^ (c * 83492791);
    x = (x ^ (x >> 13)) * 1274126177;
    x = x ^ (x >> 16);
    return (x & 0xFFFFFF) / 0x1000000;
  }

  void _put(Rect sprite, double x, double y, double size, Color c, double alpha, {bool light = false, double rot = 0}) {
    if (alpha <= 0.01 || size <= 0.05) return;
    final xf = RSTransform.fromComponents(rotation: rot, scale: size / 64, anchorX: 32, anchorY: 32, translateX: x, translateY: y);
    final col = c.withAlpha((alpha.clamp(0.0, 1.0) * 255).round());
    if (light) {
      _axf.add(xf);
      _arc.add(sprite);
      _acol.add(col);
    } else {
      _xf.add(xf);
      _rc.add(sprite);
      _col.add(col);
    }
  }

  static double _flick(double t, double seed) => 0.5 + 0.5 * (0.5 * math.sin(t * 9.7 + seed) + 0.3 * math.sin(t * 15.3 + seed * 2) + 0.2 * math.sin(t * 23.1 + seed * 5));

  void paint(Canvas canvas, List<FxEmitter> list, ColorFilter? filter) {
    for (final e in list) {
      switch (e.kind) {
        case _Kind.glow:
          _glow(e);
        case _Kind.embers:
          if (moving) _embers(e);
        case _Kind.smoke:
          if (moving) _smoke(e);
        case _Kind.bubbles:
          if (moving) _bubbles(e);
        case _Kind.motes:
          if (moving) _motes(e);
        case _Kind.leaves:
          if (moving) _leaves(e);
      }
    }
    if (_xf.isNotEmpty) {
      canvas.drawAtlas(atlas, _xf, _rc, _col, BlendMode.modulate, null, Paint()..filterQuality = FilterQuality.low..colorFilter = filter);
    }
    if (_axf.isNotEmpty) {
      canvas.drawAtlas(atlas, _axf, _arc, _acol, BlendMode.modulate, null, Paint()
        ..filterQuality = FilterQuality.low
        ..blendMode = BlendMode.plus
        ..colorFilter = filter);
    }
  }

  void _glow(FxEmitter e) {
    final seed = e.seed.toDouble();
    var a = e.a, r = e.r;
    if (moving) {
      switch (e.style) {
        case 'fire':
          {
            final f = _flick(t, seed);
            a *= 0.5 + 0.5 * f;
            r *= 0.9 + 0.16 * f;
          }
        case 'crystal':
          {
            final p = 0.5 + 0.5 * math.sin(t * 1.5 + seed);
            a *= 0.62 + 0.38 * p;
            r *= 0.95 + 0.1 * p;
          }
        case 'sun':
          a *= 0.85 + 0.15 * math.sin(t * 0.31 + seed);
        default: // lamp
          a *= 0.82 + 0.14 * math.sin(t * 1.15 + seed) + 0.04 * math.sin(t * 7.3 + seed * 3);
      }
    }
    _put(_dot, e.x, e.y, r * 2, e.colors.first, a, light: true);
  }

  void _embers(FxEmitter e) {
    final hot = e.colors.first;
    for (var i = 0; i < e.n; i++) {
      final life = 1.3 + 1.3 * _rnd(e.seed, i, 0);
      final cyc = t / life + _rnd(e.seed, i, 1);
      final k = cyc.floor();
      final age = cyc - k;
      final x = e.x + (_rnd(e.seed + i, k, 2) - 0.5) * e.w + math.sin(age * 5 + _rnd(e.seed, i, k + 3) * 6) * 5 * age;
      final y = e.y - age * e.h * (0.55 + 0.45 * _rnd(e.seed + i, k, 4));
      final fade = (age < 0.1 ? age / 0.1 : 1.0) * math.pow(1 - age, 1.3).toDouble();
      final c = Color.lerp(const Color(0xFFFFE08A), hot, age.clamp(0.0, 1.0).toDouble())!;
      _put(_square, x, y, e.s * 1.3 * (1 - 0.45 * age), c, fade, light: true, rot: age * 2);
      _put(_dot, x, y, e.s * 4.5, c, fade * 0.3, light: true);
    }
  }

  void _smoke(FxEmitter e) {
    final steam = e.style == 'steam';
    for (var i = 0; i < e.n; i++) {
      final life = (steam ? 2.0 : 3.6) + (steam ? 1.0 : 1.8) * _rnd(e.seed, i, 0);
      final cyc = t / life + i / e.n;
      final k = cyc.floor();
      final age = cyc - k;
      final wob = math.sin(age * 4 + _rnd(e.seed + i, k, 5) * 6) * e.s * 0.35;
      final x = e.x + (_rnd(e.seed + i, k, 1) - 0.5) * e.s * 0.8 + e.drift * math.pow(age, 1.4) + wob;
      final y = e.y - age * e.h;
      final grow = e.s * (1 + (steam ? 1.8 : 2.6) * age);
      final fadeIn = (age / 0.15).clamp(0.0, 1.0);
      final alpha = e.a * fadeIn * (1 - age) * (steam ? (1 - age) : 1);
      _put(_dot, x, y, grow * 2, e.colors.first, alpha);
    }
  }

  void _bubbles(FxEmitter e) {
    for (var i = 0; i < e.n; i++) {
      final life = 0.8 + 0.9 * _rnd(e.seed, i, 0);
      final cyc = t / life + _rnd(e.seed, i, 1);
      final k = cyc.floor();
      final age = cyc - k;
      final u = _rnd(e.seed + i, k, 2) * 2 - 1, v = _rnd(e.seed + i, k, 3) * 2 - 1;
      final x = e.x + u * e.w * 0.85;
      final y = e.y + v * e.h * 0.55;
      final size = age < 0.75 ? e.s * age / 0.75 : e.s * (1 + (age - 0.75) * 1.6);
      final alpha = age < 0.75 ? 0.85 : 0.85 * (1 - (age - 0.75) / 0.25);
      _put(_ring, x, y, size * 2, e.colors.first, alpha);
    }
  }

  void _motes(FxEmitter e) {
    final c = e.colors.first;
    for (var i = 0; i < e.n; i++) {
      final r1 = _rnd(e.seed, i, 1), r2 = _rnd(e.seed, i, 2), r3 = _rnd(e.seed, i, 3), r4 = _rnd(e.seed, i, 4);
      switch (e.style) {
        case 'pollen':
          {
            final x = e.x + (r1 * e.w + t * (6 + 10 * r2)) % e.w;
            final y = e.y + r3 * e.h + math.sin(t * (0.7 + r4) + r1 * 6) * 9;
            final edge = math.min(1.0, math.min(x - e.x, e.x + e.w - x) / 20);
            _put(_square, x, y, e.s, c, 0.75 * edge, rot: t * (0.5 + r2));
          }
        case 'firefly':
          {
            final x = e.x + e.w * (0.5 + 0.46 * math.sin(t * 0.17 * (0.6 + r1) + r2 * 6.28) * math.cos(t * 0.11 * (0.6 + r3) + r4 * 6));
            final y = e.y + e.h * (0.5 + 0.46 * math.sin(t * 0.23 * (0.6 + r4) + r1 * 6.28));
            final p = math.pow(0.5 + 0.5 * math.sin(t * (1.1 + r2) * 2 + r3 * 6.28), 2).toDouble();
            _put(_dot, x, y, e.s * 5, c, 0.45 * p, light: true);
            _put(_square, x, y, e.s, c, 0.35 + 0.65 * p, light: true);
          }
        case 'spark':
          {
            final life = 1.1 + 1.2 * r1;
            final cyc = t / life + r2;
            final k = cyc.floor();
            final age = cyc - k;
            final x = e.x + _rnd(e.seed + i, k, 5) * e.w;
            final y = e.y + _rnd(e.seed + i, k, 6) * e.h - age * 8;
            final tw = math.pow(math.sin(math.pi * age), 2).toDouble();
            _put(_dot, x, y, e.s * 4, c, 0.5 * tw, light: true);
            _put(_square, x, y, e.s * (0.6 + 0.6 * tw), c, tw, light: true, rot: math.pi / 4);
          }
        default: // dust in the light
          {
            final x = e.x + ((r1 * e.w + math.sin(t * 0.13 * (0.5 + r2) + r3 * 6.28) * e.w * 0.12 + t * 1.5 * (r4 - 0.5)) % e.w + e.w) % e.w;
            final y = e.y + ((r3 * e.h + math.sin(t * 0.21 * (0.5 + r4) + r1 * 6.28) * e.h * 0.18 - t * 1.2 * r2) % e.h + e.h) % e.h;
            final tw = 0.25 + 0.75 * math.pow(0.5 + 0.5 * math.sin(t * (0.8 + r2) + r4 * 6.28), 3).toDouble();
            _put(_square, x, y, e.s, c, 0.7 * tw, light: true);
          }
      }
    }
  }

  void _leaves(FxEmitter e) {
    for (var i = 0; i < e.n; i++) {
      final life = 7 + 5 * _rnd(e.seed, i, 0);
      final cyc = t / life + _rnd(e.seed, i, 1);
      final k = cyc.floor();
      final age = cyc - k;
      if (age > 0.7) continue; // a leaf now and then, not a stream
      final q = age / 0.7;
      final r = _rnd(e.seed + i, k, 2);
      final spin = r > 0.5 ? 1.0 : -1.0;
      final x = e.x - 30 + q * (e.w + 60);
      final y = e.y + _rnd(e.seed + i, k, 3) * e.h + math.sin(q * 9 + r * 6) * 14 + q * 34;
      final edge = math.min(1.0, math.min(q, 1 - q) / 0.06);
      final c = e.colors[(_rnd(e.seed + i, k, 4) * e.colors.length).floor() % e.colors.length];
      _put(_leaf, x, y, e.s * 2.2, c, 0.95 * edge, rot: q * 8 * spin + math.sin(q * 12) * 0.8);
    }
  }
}
