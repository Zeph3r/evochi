// The Hollow taking Alder's map, for the cold open's 'hollow' layer (onboarding_cine.json): the shader
// (shaders/hollow_fx.frag) does the map itself; here, its field (when the Hollow reaches each point: tools/art/
// hollow_field.py) and what rises off the front as it comes: violet sparks where it burns, dark ash behind.

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

/// The field, decoded once: the image for the shader, and the board's points binned by when the Hollow reaches
/// them (where the sparks rise as it passes).
class HollowField {
  HollowField._(this.image, this.w, this.h, this.bins);
  final ui.Image image;
  final int w, h;
  final List<Int32List> bins; // per arrival-time bin (0..1 in [bins.length] steps): pixel indices

  static const nBins = 48;
  static final Map<String, Future<HollowField?>> _loading = {};
  static Future<ui.FragmentProgram?>? _programLoading;

  static Future<ui.FragmentProgram?> program() => _programLoading ??= () async {
        try {
          return await ui.FragmentProgram.fromAsset('shaders/hollow_fx.frag');
        } catch (_) {
          return null;
        }
      }();

  static Future<HollowField?> load(String asset) => _loading[asset] ??= () async {
        try {
          final data = await rootBundle.load(asset);
          final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
          final image = (await codec.getNextFrame()).image;
          final bytes = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
          final w = image.width, h = image.height;
          final lists = List.generate(nBins, (_) => <int>[]);
          for (var i = 0; i < w * h; i++) {
            final r = bytes[i * 4];
            if (r >= 255 || bytes[i * 4 + 1] < 128) continue;
            final t = r / 254 * 1.25;
            if (t >= 1) continue;
            lists[(t * nBins).floor().clamp(0, nBins - 1)].add(i);
          }
          return HollowField._(image, w, h, [for (final l in lists) Int32List.fromList(l)]);
        } catch (_) {
          return null;
        }
      }();

  /// a point (field px, as a fraction of the field) the front reaches at [p], picked by [seed]; null if none
  ui.Offset? pointAt(double p, int seed) {
    final b = (p * nBins).floor();
    for (var k = 0; k < 3; k++) {
      final i = b - k;
      if (i < 0 || i >= bins.length || bins[i].isEmpty) continue;
      final list = bins[i];
      final idx = list[_hash(seed, i) % list.length];
      return ui.Offset(((idx % w) + _frac(seed * 1.7)) / w, ((idx ~/ w) + _frac(seed * 2.3)) / h);
    }
    return null;
  }

  static int _hash(int a, int b) {
    var x = (a * 73856093) ^ (b * 19349663);
    x = (x ^ (x >> 13)) * 0x5bd1e995;
    return (x ^ (x >> 15)) & 0x7fffffff;
  }

  static double _frac(double x) {
    final s = math.sin(x * 12.9898) * 43758.5453;
    return s - s.floorToDouble();
  }
}

/// The map as the Hollow takes it: [p] how far it has come (0..1), [dim] how dark the room is, [t] seconds (the
/// veins and smoke move with it), [progressAt] the shot's own p at an earlier time (for the motes rising off where
/// the front was). The plate is placed by [g] (the shot's camera).
void paintHollow(ui.Canvas c, ui.Size size, ({double scale, ui.Offset origin}) g, ui.FragmentShader sh,
    {required ui.Image lit, required ui.Image faded, required ui.Image hollow, required HollowField field,
    required double p, required double dim, required double t, required double Function(double tAgo) progressAt, bool motes = true}) {
  final pw = lit.width.toDouble(), ph = lit.height.toDouble();
  final whole = ui.Rect.fromLTWH(-g.origin.dx * g.scale, -g.origin.dy * g.scale, pw * g.scale, ph * g.scale);
  sh
    ..setFloat(0, whole.left)
    ..setFloat(1, whole.top)
    ..setFloat(2, whole.width)
    ..setFloat(3, whole.height)
    ..setFloat(4, pw)
    ..setFloat(5, ph)
    ..setFloat(6, size.width)
    ..setFloat(7, size.height)
    ..setFloat(8, t % 600.0)
    ..setFloat(9, p)
    ..setFloat(10, dim)
    ..setImageSampler(0, lit)
    ..setImageSampler(1, faded)
    ..setImageSampler(2, hollow)
    ..setImageSampler(3, field.image);
  c.drawRect(ui.Offset.zero & size, ui.Paint()..shader = sh);
  if (!motes || p <= 0.01) return;
  // what rises off the front: each mote born at a moment, where the front was then, drifting up and fading
  final spark = ui.Paint()..blendMode = ui.BlendMode.plus;
  final ash = ui.Paint();
  const life = 1.6, n = 70;
  for (var i = 0; i < n; i++) {
    final phase = HollowField._frac(i * 3.17);
    final cyc = (t / life + phase);
    final age = (cyc - cyc.floorToDouble()) * life;
    final born = cyc.floor();
    final pb = progressAt(age);
    if (pb <= 0.005 || pb >= 0.995) continue;
    final at = field.pointAt(pb, i * 7919 + born * 104729);
    if (at == null) continue;
    final isSpark = i % 3 != 0;
    final u = age / life;
    final drift = HollowField._frac(i * 5.1 + born * 0.37) - 0.5;
    final x = whole.left + at.dx * whole.width + drift * 26 * g.scale * u;
    final y = whole.top + at.dy * whole.height - (isSpark ? 46.0 : 28.0) * g.scale * u;
    final fade = math.sin(math.pi * u);
    if (isSpark) {
      final r = (1.6 + 1.8 * HollowField._frac(i * 1.3)) * g.scale;
      spark.shader = ui.Gradient.radial(ui.Offset(x, y), r * 3.2, [
        ui.Color.fromRGBO(214, 140, 255, 0.85 * fade),
        const ui.Color.fromRGBO(150, 60, 255, 0.0),
      ]);
      c.drawCircle(ui.Offset(x, y), r * 3.2, spark);
    } else {
      final r = (2.2 + 2.5 * HollowField._frac(i * 2.9)) * g.scale * (0.7 + 0.6 * u);
      ash.color = ui.Color.fromRGBO(20, 10, 30, 0.55 * fade);
      c.drawCircle(ui.Offset(x, y), r, ash);
    }
  }
}
