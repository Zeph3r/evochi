// The baked effect sprites an Elder's ultimate plays in the Wilds once its cut-in hands back to the fight: the
// instant flash it lands with, the Quake's rupture and tumbling rock, the Thorn Snare's roots, the Sunflare's
// burst and dazzle, the Reef Bloom's pool and coral, the Crystal Shards' star, a billow of dust (tools/art/ult_fx_bake.py -> assets/art/wilds/
// ultfx.json and ultfx_<name>.webp). Each is a flipbook: frames along a row, a row per shape.

import 'dart:convert';
import 'dart:ui';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';

class FxSheet {
  FxSheet(this.img, this.fw, this.fh, this.n, this.variants, this.kind, this.ax, this.ay);
  final ui.Image img;
  final int fw, fh, n, variants;
  final String kind; // ground (drawn from above, squashed onto the ground), stand (its root at the anchor), add (light)
  final double ax, ay; // the anchor, as a share of the frame

  /// the frame [k] (0..1) of the way through
  int at(double k) => (k * n).floor().clamp(0, n - 1);

  Rect src(int frame, [int variant = 0]) =>
      Rect.fromLTWH(frame.clamp(0, n - 1) * fw.toDouble(), (variant % variants) * fh.toDouble(), fw.toDouble(), fh.toDouble());

  /// [tint] multiplies it (a white sprite takes the tint's colour)
  void draw(Canvas canvas, int frame, Rect dst, {int variant = 0, double opacity = 1, bool? add, Color? tint}) {
    if (opacity <= 0.004) return;
    final p = Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(255, 255, 255, opacity.clamp(0.0, 1.0));
    if (tint != null) p.colorFilter = ColorFilter.mode(tint, BlendMode.modulate);
    if (add ?? kind == 'add') p.blendMode = BlendMode.plus;
    canvas.drawImageRect(img, src(frame, variant), dst, p);
  }

  /// a standing piece, its anchor (its root) at [at], [h] px tall; [flip] mirrors it; [skew] leans it from the root
  void stand(Canvas canvas, int frame, Offset at, double h, {int variant = 0, double opacity = 1, bool flip = false, double skew = 0}) {
    if (h <= 0.5 || opacity <= 0.004) return;
    final w = h * fw / fh;
    canvas.save();
    canvas.translate(at.dx, at.dy);
    if (skew != 0) canvas.skew(skew, 0);
    if (flip) canvas.scale(-1, 1);
    draw(canvas, frame, Rect.fromLTWH(-w * ax, -h * ay, w, h), variant: variant, opacity: opacity);
    canvas.restore();
  }
}

class UltFx {
  UltFx._(this.sheets);
  final Map<String, FxSheet> sheets;

  FxSheet? operator [](String name) => sheets[name];

  static Future<UltFx?> load() async {
    try {
      final meta = jsonDecode(await rootBundle.loadString('assets/art/wilds/ultfx.json')) as Map<String, dynamic>;
      final out = <String, FxSheet>{};
      await Future.wait(meta.entries.map((e) async {
        final m = e.value as Map<String, dynamic>;
        final data = await rootBundle.load('assets/art/wilds/${m['file']}');
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final img = (await codec.getNextFrame()).image;
        out[e.key] = FxSheet(img, (m['fw'] as num).toInt(), (m['fh'] as num).toInt(), (m['n'] as num).toInt(),
            (m['variants'] as num? ?? 1).toInt(), m['kind'] as String? ?? 'normal', (m['ax'] as num? ?? 0.5).toDouble(),
            (m['ay'] as num? ?? 0.5).toDouble());
      }));
      return UltFx._(out);
    } catch (_) {
      return null; // no sprites: the ultimates' painted parts still play
    }
  }
}
