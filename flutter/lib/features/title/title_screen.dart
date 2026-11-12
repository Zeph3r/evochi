// The start screen, from the environment production sheet (11 Nov 2026): a night sky with twinkling stars
// and a softly glowing moon; clouds drifting at two depths; far hills whose village lights flicker; the lake and
// its shoreline village, their lights laid on the water; the floating island with the sleeping Elder (a
// pre-rendered breathing loop) and the props in front of her, bobbing as one; the moon's shimmer and the lights'
// reflections on the lake; fireflies, and now and then a shooting star. Under the logo, "Tap to begin".
//
// The art comes from tools/art/title_layers.py (assets/art/title/title.json, everything at 2x). Everything
// animated is painted by one CustomPainter from a single clock, with gradients for every glow (no blur: one
// blurred draw is a GPU pass on Impeller). The screen is self-contained: mount it ahead of Welcome and pass
// [onBegin] for the tap. Settings > Developer tools previews it.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// The start screen's art: the manifest and the decoded layers. A missing image is skipped when painting, so
/// the scene still draws (and tests run) without the asset bundle.
class TitleArt {
  TitleArt(this.j, this.images, {this.bgCodec});
  final Map<String, dynamic> j;
  final Map<String, ui.Image?> images;

  /// The Blender-rendered backdrop and water (sky, moon, clouds, the lake and its reflections), a looping
  /// animated WebP decoded one frame at a time by the screen's clock; [bgFrame] is the frame to draw.
  final ui.Codec? bgCodec;
  ui.Image? bgFrame;
  double bgNextAt = 0;
  bool bgDecoding = false;

  static const base = 'assets/art/title/';

  static Future<TitleArt> load() async {
    final j = json.decode(await rootBundle.loadString('${base}title.json')) as Map<String, dynamic>;
    final names = ['moon', 'clouds', 'hills', 'shore', 'village', 'lily', 'logo', 'island', 'front', 'elder'];
    final files = <String, String>{};
    for (final n in names) {
      final e = n == 'island' || n == 'front' || n == 'elder' ? (j['island'] as Map)[n] : j[n];
      files[n] = (e as Map)['file'] as String? ?? '$n.webp';
    }
    final images = <String, ui.Image?>{};
    for (final e in files.entries) {
      try {
        final bytes = await rootBundle.load(base + e.value);
        final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
        images[e.key] = (await codec.getNextFrame()).image;
      } catch (_) {
        images[e.key] = null;
      }
    }
    ui.Codec? bg;
    final bgFile = (j['bg'] as Map?)?['file'] as String?;
    if (bgFile != null) {
      try {
        final bytes = await rootBundle.load(base + bgFile);
        bg = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      } catch (_) {
        bg = null;
      }
    }
    return TitleArt(j, images, bgCodec: bg);
  }

  Map<String, dynamic> get bg => sub('bg');

  /// Advances the backdrop to the frame due at [t] seconds (one decode in flight at a time; the loop's own
  /// frame durations set the pace, so a slow device skips nothing it has not yet drawn).
  void advanceBg(double t) {
    final codec = bgCodec;
    if (codec == null || bgDecoding || t < bgNextAt) return;
    bgDecoding = true;
    codec.getNextFrame().then((f) {
      bgFrame?.dispose();
      bgFrame = f.image;
      final ms = f.duration.inMilliseconds;
      bgNextAt = (bgNextAt == 0 ? t : bgNextAt) + (ms > 0 ? ms : 66) / 1000.0;
      if (bgNextAt < t - 0.5) bgNextAt = t;   // fell far behind (the app was in the background): catch up from now
      bgDecoding = false;
    }, onError: (_) => bgDecoding = false);
  }

  Map<String, dynamic> sub(String k) => (j[k] as Map?)?.cast<String, dynamic>() ?? const {};
  Map<String, dynamic> get island => sub('island');

  /// the layout, as fractions of the screen (title_layers.py's LAYOUT, so the preview there and the app agree)
  double lay(String k, double fallback) => (sub('layout')[k] as num?)?.toDouble() ?? fallback;
  List<double> layList(String k, List<double> fallback) => (sub('layout')[k] as List?)?.cast<num>().map((v) => v.toDouble()).toList() ?? fallback;
  Map<String, dynamic> get elder => (island['elder'] as Map?)?.cast<String, dynamic>() ?? const {};
}

class TitleScreen extends StatefulWidget {
  const TitleScreen({super.key, required this.onBegin, this.art});
  final VoidCallback onBegin;

  /// Art already loaded (tests); otherwise loaded from the bundle on first build.
  final TitleArt? art;

  @override
  State<TitleScreen> createState() => _TitleScreenState();
}

class _TitleScreenState extends State<TitleScreen> with SingleTickerProviderStateMixin {
  TitleArt? _art;
  late final Ticker _ticker;
  final _clock = ValueNotifier<double>(0);
  bool _begun = false;

  @override
  void initState() {
    super.initState();
    _art = widget.art;
    if (_art == null) TitleArt.load().then((a) => mounted ? setState(() => _art = a) : null);
    _ticker = createTicker((d) {
      final t = d.inMicroseconds / 1e6;
      _art?.advanceBg(t);
      _clock.value = t;
    })..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _clock.dispose();
    _art?.bgFrame?.dispose();
    _art?.bgCodec?.dispose();
    super.dispose();
  }

  void _begin() {
    if (_begun) return;
    _begun = true;
    widget.onBegin();
  }

  @override
  Widget build(BuildContext context) {
    final art = _art;
    return Semantics(
      button: true,
      label: 'Evochi. Tap to begin',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _begin,
        child: art == null
            ? const DecoratedBox(
                decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF1B1540), Color(0xFF2B2360)])),
                child: SizedBox.expand(),
              )
            : ValueListenableBuilder<double>(
                valueListenable: _clock,
                builder: (_, t, __) => CustomPaint(painter: TitlePainter(art, t), size: Size.infinite),
              ),
      ),
    );
  }
}

/// The whole scene at time [t] seconds. Pure: the same art and time paint the same picture.
class TitlePainter extends CustomPainter {
  TitlePainter(this.art, this.t);
  final TitleArt art;
  final double t;

  static const skyTop = Color(0xFF1B1540), skyMid = Color(0xFF2B2360), skyLow = Color(0xFF4A3F82), horizonCol = Color(0xFF6E5A9A);
  static const lakeTop = Color(0xFF34306F), lakeBottom = Color(0xFF1A1842);
  static const warm = Color(0xFFFFD27A), moonCol = Color(0xFFF3E3A6), firefly = Color(0xFFFFE08A);

  // one seeded field of stars, fireflies and shooting stars: the same every launch
  static final _rng = math.Random(7);
  static final List<List<double>> _stars = List.generate(110, (_) => [_rng.nextDouble(), _rng.nextDouble() * 0.58, 1 + _rng.nextInt(2).toDouble(), _rng.nextDouble() * 6.3, 0.6 + _rng.nextDouble() * 1.6]);
  static final List<List<double>> _flies = List.generate(22, (_) => [_rng.nextDouble(), 0.3 + _rng.nextDouble() * 0.6, _rng.nextDouble() * 6.3, 0.15 + _rng.nextDouble() * 0.25, 6 + _rng.nextDouble() * 10]);
  // clouds: sprite, x at t=0 (fraction), y (fraction), scale, speed (px/s), opacity
  static const List<List<double>> _clouds = [
    [2, 0.05, 0.16, 0.9, 5.0, 0.72],
    [0, 0.55, 0.09, 1.0, 7.0, 0.85],
    [3, 0.85, 0.22, 0.8, 6.0, 0.7],
    [1, 0.3, 0.27, 1.15, 10.0, 1.0],
    [0, 0.78, 0.33, 1.25, 12.0, 1.0],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final bgm = art.bg;
    if (bgm.isNotEmpty) {
      // the Blender backdrop: sky, moon, clouds, the lake and its reflections, covering the screen; the island
      // and its reflection, the glows, the fireflies, the logo and the plank over it
      final bw = (bgm['w'] as num).toDouble(), bh = (bgm['h'] as num).toDouble();
      final sc = math.max(w / bw, h / bh);
      final rect = Rect.fromCenter(center: Offset(w / 2, h / 2), width: bw * sc, height: bh * sc);
      final fr = art.bgFrame;
      if (fr != null) {
        canvas.drawImageRect(fr, Rect.fromLTWH(0, 0, fr.width.toDouble(), fr.height.toDouble()), rect, Paint()..filterQuality = FilterQuality.none);
      } else {
        _sky(canvas, w, h * 0.79);
        _lake(canvas, w, h, h * 0.79);
      }
      final lakeY = rect.top + rect.height * ((bgm['lake_y'] as num?)?.toDouble() ?? 0.79);
      final im = (bgm['island'] as Map?)?.cast<String, dynamic>() ?? const {};
      final cx = rect.left + rect.width * ((im['cx'] as num?)?.toDouble() ?? 0.5);
      final cy = rect.top + rect.height * ((im['cy'] as num?)?.toDouble() ?? 0.56);
      final iw = rect.width * ((im['w'] as num?)?.toDouble() ?? 0.9);
      _islandAt(canvas, cx, cy, iw, lakeY);
      _fireflies(canvas, w, h);
      _shootingStar(canvas, w, h);
      _logo(canvas, w, h);
      _plank(canvas, w, h);
      return;
    }
    final horizon = h * art.lay('horizon', 0.60);
    _sky(canvas, w, horizon);
    _stars_(canvas, w, horizon);
    _moon(canvas, w, h);
    _clouds_(canvas, w, h);
    _hills(canvas, w, horizon);
    _lake(canvas, w, h, horizon);
    _shore(canvas, w, horizon);
    _lilies(canvas, w, h, horizon);
    _island(canvas, w, h, horizon);
    _fireflies(canvas, w, h);
    _shootingStar(canvas, w, h);
    _logo(canvas, w, h);
    _plank(canvas, w, h);
  }

  // ---- sky, stars, moon ----
  void _sky(Canvas c, double w, double horizon) {
    c.drawRect(Rect.fromLTWH(0, 0, w, horizon + 1),
        Paint()..shader = ui.Gradient.linear(Offset.zero, Offset(0, horizon), const [skyTop, skyMid, skyLow, horizonCol], const [0, 0.45, 0.82, 1]));
  }

  void _stars_(Canvas c, double w, double horizon) {
    final p = Paint();
    for (final s in _stars) {
      final tw = 0.45 + 0.55 * (0.5 + 0.5 * math.sin(t * s[4] + s[3]));
      p.color = Colors.white.withValues(alpha: 0.35 + 0.6 * tw);
      final x = (s[0] * w).roundToDouble(), y = (s[1] * horizon).roundToDouble(), sz = s[2];
      c.drawRect(Rect.fromLTWH(x, y, sz, sz), p);
      if (sz > 1 && tw > 0.8) {
        p.color = Colors.white.withValues(alpha: 0.5 * (tw - 0.8) / 0.2);
        c.drawRect(Rect.fromLTWH(x - 1, y, sz + 2, 1), p);
        c.drawRect(Rect.fromLTWH(x, y - 1, 1, sz + 2), p);
      }
    }
  }

  void _moon(Canvas c, double w, double h) {
    final m = art.layList('moon', const [0.22, 0.30, 0.055]);
    final cx = w * m[0], cy = h * m[1], r = w * m[2];
    final pulse = 0.9 + 0.1 * math.sin(t * 2 * math.pi / 7);
    c.drawCircle(Offset(cx, cy), r * 2.6,
        Paint()..shader = ui.Gradient.radial(Offset(cx, cy), r * 2.6, [moonCol.withValues(alpha: 0.28 * pulse), moonCol.withValues(alpha: 0.0)]));
    final im = art.images['moon'];
    if (im != null) {
      c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), Rect.fromCircle(center: Offset(cx, cy), radius: r), Paint()..filterQuality = FilterQuality.none);
    } else {
      c.drawCircle(Offset(cx, cy), r, Paint()..color = moonCol);
    }
  }

  void _clouds_(Canvas c, double w, double h) {
    final im = art.images['clouds'];
    final rects = (art.sub('clouds')['rects'] as List?) ?? const [];
    final p = Paint()..filterQuality = FilterQuality.none;
    for (final k in _clouds) {
      final i = k[0].toInt();
      if (im == null || i >= rects.length) continue;
      final r = (rects[i] as List).cast<num>();
      final cw = r[2].toDouble() * 0.5 * k[3], ch = r[3].toDouble() * 0.5 * k[3];
      final span = w + cw;
      final x = ((k[1] * w + t * k[4]) % span) - cw;
      p.color = Colors.white.withValues(alpha: k[5]);
      c.drawImageRect(im, Rect.fromLTWH(r[0].toDouble(), r[1].toDouble(), r[2].toDouble(), r[3].toDouble()),
          Rect.fromLTWH(x.roundToDouble(), (k[2] * h).roundToDouble(), cw, ch), p);
    }
  }

  // ---- the far hills and the shore, their lights ----
  void _tile(Canvas c, ui.Image im, double w, double bottom, double drift, {double scale = 0.5}) {
    final tw = im.width * scale, th = im.height * scale;
    final p = Paint()..filterQuality = FilterQuality.none;
    final off = drift % tw;
    for (var x = -off; x < w; x += tw) {
      c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), Rect.fromLTWH(x.roundToDouble(), (bottom - th).roundToDouble(), tw, th), p);
    }
  }

  void _lights(Canvas c, Map<String, dynamic> layer, double w, double bottom, double drift, double speed, {double scale = 0.5, bool reflect = false, double? horizon}) {
    final lights = (layer['lights'] as List?) ?? const [];
    final tw = (layer['w'] as num).toDouble() * scale, th = (layer['h'] as num).toDouble() * scale;
    final off = drift % tw;
    var i = 0;
    for (final l in lights) {
      final lx = (l as List).cast<num>();
      final phase = i++ * 1.7;
      final f = 0.55 + 0.45 * (0.5 + 0.5 * math.sin(t * speed + phase) * math.sin(t * 0.37 * speed + phase * 2));
      for (var x = -off; x < w; x += tw) {
        final px = x + lx[0].toDouble() * scale, py = bottom - th + lx[1].toDouble() * scale;
        if (px < -20 || px > w + 20) continue;
        c.drawCircle(Offset(px, py), 7, Paint()..shader = ui.Gradient.radial(Offset(px, py), 7, [warm.withValues(alpha: 0.35 * f), warm.withValues(alpha: 0)]));
        c.drawRect(Rect.fromCenter(center: Offset(px, py), width: 2, height: 2), Paint()..color = Colors.white.withValues(alpha: 0.5 * f));
        if (reflect && horizon != null) _reflection(c, px, horizon, 26, warm, 0.22 * f);
      }
    }
  }

  void _hills(Canvas c, double w, double horizon) {
    final im = art.images['hills'];
    if (im == null) return;
    final drift = t * 1.5;
    _tile(c, im, w, horizon + 2, drift);
    _lights(c, art.sub('hills'), w, horizon + 2, drift, 1.1);
  }

  void _shore(Canvas c, double w, double horizon) {
    final im = art.images['shore'];
    if (im != null) _tile(c, im, w, horizon + 12, 0);
    // the village across the water (the walkable Village's own voxels, seen from afar), its ground on the shore
    final v = art.images['village'];
    final vm = art.sub('village');
    if (v == null || vm.isEmpty) return;
    final vw = v.width * 0.5, vh = v.height * 0.5;
    final x0 = (w * art.lay('village_x', 0.74) - vw / 2).roundToDouble();
    final y0 = (horizon + 6 - (vm['ground'] as num).toDouble() * 0.5).roundToDouble();
    c.drawImageRect(v, Rect.fromLTWH(0, 0, v.width.toDouble(), v.height.toDouble()), Rect.fromLTWH(x0, y0, vw, vh), Paint()..filterQuality = FilterQuality.none);
    final lights = (vm['lights'] as List?) ?? const [];
    var i = 0;
    for (final l in lights) {
      final lx = (l as List).cast<num>();
      final px = x0 + lx[0].toDouble() * 0.5, py = y0 + lx[1].toDouble() * 0.5;
      final phase = i++ * 1.7;
      final f = 0.6 + 0.4 * (0.5 + 0.5 * math.sin(t * 1.6 + phase) * math.sin(t * 0.6 + phase * 2));
      c.drawCircle(Offset(px, py), 6, Paint()..shader = ui.Gradient.radial(Offset(px, py), 6, [warm.withValues(alpha: 0.35 * f), warm.withValues(alpha: 0)]));
      if (i % 2 == 0) _reflection(c, px, horizon + 8, 30, warm, 0.18 * f);
    }
  }

  // ---- the lake, its shimmer and reflections ----
  void _lake(Canvas c, double w, double h, double horizon) {
    c.drawRect(Rect.fromLTWH(0, horizon, w, h - horizon), Paint()..shader = ui.Gradient.linear(Offset(0, horizon), Offset(0, h), const [lakeTop, lakeBottom]));
    // ripples: faint lighter rows, each sliding at its own pace, in 3 px steps so they stay pixel
    final p = Paint();
    for (var y = horizon + 14; y < h; y += 9) {
      final k = (y - horizon) / (h - horizon);
      final sx = (((t * (6 + 14 * k)) + y * 3.7) % 48).floorToDouble() / 3 * 3;
      p.color = Colors.white.withValues(alpha: 0.05 + 0.04 * (1 - k));
      for (var x = -48 + sx; x < w; x += 48) {
        c.drawRect(Rect.fromLTWH(x, y, 12 + 10 * k, 1.5), p);
      }
    }
    // the moon on the water: a column of dashes under it, each flickering on its own
    _reflection(c, w * art.layList('moon', const [0.22, 0.30, 0.055])[0], horizon, h - horizon, moonCol, 0.22, wide: true);
  }

  void _reflection(Canvas c, double x, double top, double len, Color col, double alpha, {bool wide = false}) {
    final p = Paint();
    var y = top + 4;
    var i = 0;
    while (y < top + len) {
      final k = (y - top) / len;
      final a = alpha * (1 - k * 0.7) * (0.55 + 0.45 * math.sin(t * (2.2 + 0.4 * (i % 3)) + i * 1.3));
      final dw = (wide ? 10 + 26 * k : 4 + 4 * k) * (0.7 + 0.3 * math.sin(t * 1.3 + i));
      final dx = (wide ? 6 : 2) * math.sin(t * 0.8 + i * 0.9);
      p.color = col.withValues(alpha: a.clamp(0.0, 1.0).toDouble());
      c.drawRect(Rect.fromCenter(center: Offset(x + dx, y), width: dw, height: 2), p);
      y += wide ? 8 + 4 * k : 6;
      i++;
    }
  }

  void _lilies(Canvas c, double w, double h, double horizon) {
    final im = art.images['lily'];
    if (im == null) return;
    final p = Paint()..filterQuality = FilterQuality.none;
    const spots = [[0.1, 0.78, 1.0], [0.88, 0.70, 0.8], [0.2, 0.93, 1.2], [0.8, 0.9, 1.1]];
    var i = 0;
    for (final s in spots) {
      final lw = im.width * 0.5 * s[2], lh = im.height * 0.5 * s[2];
      final y = horizon + (h - horizon) * (s[1] - 0.6) / 0.4 * 0.8 + 2 * math.sin(t * 1.1 + i++ * 2.0);
      c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), Rect.fromLTWH((s[0] * w).roundToDouble(), y.roundToDouble(), lw, lh), p);
    }
  }

  // ---- the island, the Elder and the props in front ----
  void _island(Canvas c, double w, double h, double horizon) {
    final m = art.island;
    final iw = ((m['island'] as Map?)?['w'] as num? ?? 960).toDouble(), ih = ((m['island'] as Map?)?['h'] as num? ?? 800).toDouble();
    final dw = w * art.lay('island_w', 0.70);
    final dh = ih * dw / iw;
    final bob = 5 * math.sin(t * 2 * math.pi / 5.2);
    // its shadow on the water, breathing with the bob
    final sh = Rect.fromCenter(center: Offset(w / 2, horizon + 24 + bob * 0.3), width: dw * 0.5 - bob * 2, height: 14);
    c.drawOval(sh, Paint()..shader = ui.Gradient.radial(sh.center, sh.width / 2, [Colors.black.withValues(alpha: 0.22), Colors.black.withValues(alpha: 0)]));
    _islandAt(c, w / 2, h * art.lay('island_bottom', 0.56) - dh / 2, dw, null);
  }

  /// The island [dw] wide with its middle at ([cx], [cy]), bobbing, with its reflection on the water below
  /// [lakeY] (none when null).
  void _islandAt(Canvas c, double cx, double cy, double dw, double? lakeY) {
    final isl = art.images['island'];
    final m = art.island;
    final iw = ((m['island'] as Map?)?['w'] as num? ?? 960).toDouble(), ih = ((m['island'] as Map?)?['h'] as num? ?? 800).toDouble();
    final scale = dw / iw;
    final dh = ih * scale;
    final bob = 5 * math.sin(t * 2 * math.pi / 5.2);
    final x0 = cx - dw / 2, y0 = cy - dh / 2 + bob;
    final p = Paint()..filterQuality = FilterQuality.medium;
    if (lakeY != null) _reflectionOf(c, x0, y0, dw, dh, lakeY, bob);
    Rect dst(num x, num y, num ww, num hh) => Rect.fromLTWH(x0 + x * scale, y0 + y * scale, (ww * scale).toDouble(), (hh * scale).toDouble());
    if (isl != null) {
      c.drawImageRect(isl, Rect.fromLTWH(0, 0, isl.width.toDouble(), isl.height.toDouble()), dst(0, 0, iw, ih), p);
    } else {
      c.drawOval(dst(0, ih * 0.3, iw, ih * 0.4), Paint()..color = const Color(0xFF4F8E38));
    }
    final el = art.images['elder'];
    final e = art.elder;
    if (el != null && e.isNotEmpty) {
      final fw = e['frameW'] as num, fh = e['frameH'] as num, n = e['frames'] as num, fps = e['fps'] as num;
      final i = ((t * fps).floor() % n.toInt()).toDouble();
      c.drawImageRect(el, Rect.fromLTWH(i * fw, 0, fw.toDouble(), fh.toDouble()), dst(e['x'] as num, e['y'] as num, fw, fh), p);
    }
    // the egg's glow and the lantern's, before the props so the props stay crisp over them
    final egg = (m['egg'] as List?)?.cast<num>();
    if (egg != null) {
      final ec = Offset(x0 + egg[0] * scale, y0 + egg[1] * scale);
      final pulse = 0.8 + 0.2 * math.sin(t * 2 * math.pi / 3.6);
      c.drawCircle(ec, 30, Paint()..shader = ui.Gradient.radial(ec, 30, [const Color(0xFFFFF1C8).withValues(alpha: 0.45 * pulse), const Color(0xFFFFF1C8).withValues(alpha: 0)]));
    }
    final front = art.images['front'];
    if (front != null) {
      c.drawImageRect(front, Rect.fromLTWH(0, 0, front.width.toDouble(), front.height.toDouble()), dst(0, 0, iw, ih), p);
    }
    final flame = (m['flame'] as List?)?.cast<num>();
    if (flame != null) {
      final fc = Offset(x0 + flame[0] * scale, y0 + flame[1] * scale);
      final flick = 0.86 + 0.14 * (0.5 + 0.5 * math.sin(t * 9.1) * math.sin(t * 5.3 + 1));
      c.drawCircle(fc, 44, Paint()..shader = ui.Gradient.radial(fc, 44, [warm.withValues(alpha: 0.38 * flick), warm.withValues(alpha: 0.1 * flick), warm.withValues(alpha: 0)], const [0, 0.35, 1]));
    }
    final zs = (m['zs'] as List?)?.cast<num>();
    if (zs != null) _zs(c, Offset(x0 + zs[0] * scale, y0 + zs[1] * scale));
  }

  /// The island mirrored in the lake: the island, the Elder's frame and the props flipped and squashed under
  /// the water line, faint and fading with depth, each strip swaying a little on its own so the water reads
  /// as moving.
  void _reflectionOf(Canvas c, double x0, double y0, double dw, double dh, double lakeY, double bob) {
    final isl = art.images['island'];
    if (isl == null) return;
    final m = art.island;
    final iw = ((m['island'] as Map?)?['w'] as num? ?? 960).toDouble();
    final el = art.images['elder'];
    final e = art.elder;
    final front = art.images['front'];
    const squash = 0.38;
    final top = lakeY + 4 + (lakeY - (y0 + dh)) * 0.25 - bob * squash;   // the higher it floats, the further down its image lies
    final rh = dh * squash;
    const strips = 18;
    final sh = rh / strips;
    for (var k = 0; k < strips; k++) {
      final u = k / strips;
      final dx = 2.5 * math.sin(t * 1.7 + k * 0.9) + 1.5 * math.sin(t * 3.1 - k * 1.7);
      final a = 0.34 * (1 - u) * (1 - u);
      final paint = Paint()
        ..filterQuality = FilterQuality.low
        ..color = Colors.white.withValues(alpha: a);
      // this strip of the mirrored image: the whole image drawn flipped about its middle, clipped to the strip
      final dst = Rect.fromLTWH(x0 + dx, top + k * sh, dw, sh + 0.5);
      c.save();
      c.clipRect(dst);
      final full = Rect.fromLTWH(x0 + dx, top, dw, rh);
      c.translate(0, full.top + full.height / 2);
      c.scale(1, -1);
      c.translate(0, -(full.top + full.height / 2));
      c.drawImageRect(isl, Rect.fromLTWH(0, 0, isl.width.toDouble(), isl.height.toDouble()), full, paint);
      if (el != null && e.isNotEmpty) {
        final fw = (e['frameW'] as num).toDouble(), fh = (e['frameH'] as num).toDouble();
        final n = (e['frames'] as num).toInt(), fps = (e['fps'] as num).toDouble();
        final i = ((t * fps).floor() % n).toDouble();
        final s = dw / iw;
        c.drawImageRect(el, Rect.fromLTWH(i * fw, 0, fw, fh),
            Rect.fromLTWH(full.left + (e['x'] as num) * s, full.top + (e['y'] as num) * s * squash, fw * s, fh * s * squash), paint);
      }
      if (front != null) {
        c.drawImageRect(front, Rect.fromLTWH(0, 0, front.width.toDouble(), front.height.toDouble()), full, paint);
      }
      c.restore();
    }
    // the water's own colour laid back over it, so the reflection sinks into the lake rather than sitting on it
    c.drawRect(Rect.fromLTWH(x0 - 10, top, dw + 20, rh),
        Paint()..shader = ui.Gradient.linear(Offset(0, top), Offset(0, top + rh), [lakeTop.withValues(alpha: 0.15), lakeBottom.withValues(alpha: 0.6)]));
  }

  void _zs(Canvas c, Offset at) {
    for (var k = 0; k < 3; k++) {
      final u = ((t / 3.2) + k / 3) % 1.0;
      final a = u < 0.15 ? u / 0.15 : (1 - u).clamp(0, 1) * 1.2;
      final tp = TextPainter(
        text: TextSpan(text: 'z', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 10 + 10 * u, color: Colors.white.withValues(alpha: 0.85 * a.clamp(0, 1).toDouble()))),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, at + Offset(8 + 22 * u + 4 * math.sin(u * 6), -10 - 46 * u));
    }
  }

  // ---- fireflies, the shooting star ----
  void _fireflies(Canvas c, double w, double h) {
    final p = Paint();
    for (final f in _flies) {
      final x = f[0] * w + 14 * math.sin(t * f[3] * 2 + f[2]);
      final y = f[1] * h - ((t * f[3] * 8 + f[2] * 20) % 60) + 6 * math.sin(t * f[3] * 3.1 + f[2]);
      final a = (0.5 + 0.5 * math.sin(t * 2 * math.pi / f[4] * 3 + f[2])).clamp(0.0, 1.0).toDouble();
      if (a < 0.15) continue;
      p.color = firefly.withValues(alpha: 0.9 * a);
      c.drawRect(Rect.fromLTWH(x.roundToDouble(), y.roundToDouble(), 2, 2), p);
      c.drawCircle(Offset(x + 1, y + 1), 5, Paint()..shader = ui.Gradient.radial(Offset(x + 1, y + 1), 5, [firefly.withValues(alpha: 0.3 * a), firefly.withValues(alpha: 0)]));
    }
  }

  void _shootingStar(Canvas c, double w, double h) {
    // one every 15 to 30 s (a fixed sequence), 0.6 s across the top of the sky
    const period = 22.0;
    final k = (t / period).floor();
    final jitter = ((k * 7919) % 17) / 17.0;
    final start = k * period + 4 + jitter * 8;
    final u = (t - start) / 0.6;
    if (u < 0 || u > 1) return;
    final sx = w * (0.15 + 0.7 * (((k * 31) % 11) / 11.0)), sy = h * (0.05 + 0.1 * jitter);
    final head = Offset(sx + u * w * 0.35, sy + u * h * 0.1);
    final tail = head - const Offset(1, 0.286) * (70.0 * (1 - u * 0.5));
    c.drawLine(tail, head, Paint()..shader = ui.Gradient.linear(tail, head, [Colors.white.withValues(alpha: 0), Colors.white.withValues(alpha: 0.9 * (1 - u))])..strokeWidth = 2);
    c.drawRect(Rect.fromCenter(center: head, width: 3, height: 3), Paint()..color = Colors.white.withValues(alpha: 1 - u));
  }

  // ---- the logo and the plank ----
  void _logo(Canvas c, double w, double h) {
    final im = art.images['logo'];
    final lw = w * art.lay('logo_w', 0.72);
    final bob = 3 * math.sin(t * 2 * math.pi / 4.4);
    if (im == null) return;
    final lh = lw * im.height / im.width;
    c.drawImageRect(im, Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble()), Rect.fromLTWH(((w - lw) / 2).roundToDouble(), (h * art.lay('logo_y', 0.055) + bob).roundToDouble(), lw, lh), Paint()..filterQuality = FilterQuality.medium);
  }

  void _plank(Canvas c, double w, double h) {
    final pw = math.min(w * 0.62, 300.0), ph = 54.0;
    final r = Rect.fromCenter(center: Offset(w / 2, h * art.lay('plank_y', 0.865)), width: pw, height: ph);
    final pulse = 0.5 + 0.5 * math.sin(t * 2 * math.pi / 2.4);
    final rr = RRect.fromRectAndRadius(r, const Radius.circular(8));
    c.drawRRect(rr.shift(const Offset(0, 4)), Paint()..color = const Color(0xFF4A2E1E));
    c.drawRRect(rr, Paint()..color = const Color(0xFF6E4529));
    final inner = RRect.fromRectAndRadius(r.deflate(3), const Radius.circular(6));
    c.drawRRect(inner, Paint()..color = const Color(0xFFB98149));
    final grain = Paint()..color = const Color(0xFFA8703F);
    for (var y = r.top + 12; y < r.bottom - 6; y += 14) {
      c.drawRect(Rect.fromLTWH(r.left + 10, y, pw - 20, 2), grain);
    }
    for (final dx in [-pw / 2 + 9, pw / 2 - 9]) {
      for (final dy in [-ph / 2 + 9, ph / 2 - 9]) {
        c.drawRect(Rect.fromCenter(center: r.center + Offset(dx, dy), width: 3, height: 3), Paint()..color = const Color(0xFFC9C3B8));
      }
    }
    final tp = TextPainter(
      text: TextSpan(text: 'Tap to begin', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 20, color: const Color(0xFFFFF4E2).withValues(alpha: 0.88 + 0.12 * pulse), shadows: const [Shadow(color: Color(0xFF4A2E1E), offset: Offset(0, 2))])),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, r.center - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant TitlePainter old) => true;   // the clock moves every frame, and the backdrop's frame with it
}

/// Settings > Developer tools: the start screen over everything, a tap closing it.
void previewTitleScreen(BuildContext context) {
  Navigator.of(context).push(MaterialPageRoute<void>(builder: (ctx) => TitleScreen(onBegin: () => Navigator.of(ctx).pop())));
}
