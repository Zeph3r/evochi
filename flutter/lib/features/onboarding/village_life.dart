// The village at dusk, lived in (the cold open's village_push shot, onboarding_cine.json's 'villagers' layer):
// the villagers out walking in their own walk sheets (tools/art/npc_walk.py, the same ones the Wilds uses), at the
// plate's perspective, drawn in the dusk light; a lantern swinging in a hand with its pool of light on the ground;
// hatchlings chasing each other round the green. All in the plate's own px under the shot's camera.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/services.dart' show rootBundle;

import '../../core/services/asset_manifest.dart';

/// One walker's sheet: frame size, where its feet are, how tall it stands, and its frames per direction.
class WalkSheet {
  WalkSheet(this.image, this.fw, this.fh, this.ground, this.heightPx, this.frames);
  final ui.Image image;
  final double fw, fh;
  final ui.Offset ground;
  final double heightPx;
  final int frames; // walk frames after the standing one

  static Map<String, dynamic>? _meta;
  static final Map<String, Future<WalkSheet?>> _loading = {};

  /// [who] a key in wilds_walk.json ('npc_mira', 's01'); [look] which sheet ('default', or an Evochi's palette)
  static Future<WalkSheet?> load(String who, String look) => _loading['$who/$look'] ??= () async {
        try {
          _meta ??= jsonDecode(await rootBundle.loadString('${artBase}wilds/wilds_walk.json')) as Map<String, dynamic>;
          final w = ((_meta!['walkers'] as Map)[who] as Map).cast<String, dynamic>();
          final sheets = (((w['gaits'] as Map)['walk'] as Map)['sheets'] as Map).cast<String, dynamic>();
          final file = (sheets[look] ?? sheets.values.first) as String;
          final im = await AtlasCache.load('${artBase}wilds/$file');
          final g = (w['ground'] as List).cast<num>();
          final fw = (w['frameW'] as num).toDouble(), fh = (w['frameH'] as num).toDouble();
          return WalkSheet(im, fw, fh, ui.Offset(g[0].toDouble(), g[1].toDouble()), ((w['heightPx'] as num?) ?? fh * 0.66).toDouble(),
              ((w['frames'] as num?) ?? (_meta!['frames'] as num)).toInt());
        } catch (_) {
          return null;
        }
      }();
}

double _frac(double x) {
  final s = math.sin(x * 12.9898) * 43758.5453;
  return s - s.floorToDouble();
}

/// the villagers layer at [ts] seconds into the shot; [sheets] by 'who/look'; [toScreen] plate px -> canvas
void paintVillagers(ui.Canvas c, Map<String, dynamic> L, double ts, Map<String, WalkSheet> sheets, double scale, ui.Offset Function(ui.Offset) toScreen) {
  final tint = ((L['tint'] as List?) ?? const [0.62, 0.56, 0.74]).cast<num>().map((v) => v.toDouble()).toList();
  final drawn = <({double y, void Function() draw})>[];
  for (final w in (L['walkers'] as List).cast<Map<String, dynamic>>()) {
    final sheet = sheets['${w['who']}/${w['look'] ?? 'default'}'];
    if (sheet == null) continue;
    final speed = ((w['speed'] as num?) ?? 20).toDouble(); // plate px a second
    final h0 = (w['h'] as List).cast<num>();
    final t0 = ((w['start'] as num?) ?? 0).toDouble();
    final t = math.max(0.0, ts - t0);
    ui.Offset at, dir;
    double k; // 0..1 along (for the height)
    var moving = true;
    if (w['circle'] != null) {
      // round and round a point (hatchlings at play), a hop in the step
      final cc = (w['circle'] as List).cast<num>();
      final r = cc[2].toDouble();
      final ang = t * speed / r + ((w['phase'] as num?) ?? 0).toDouble();
      at = ui.Offset(cc[0] + math.cos(ang) * r, cc[1] + math.sin(ang) * r * 0.45);
      dir = ui.Offset(-math.sin(ang), math.cos(ang) * 0.45);
      k = 0.5 + 0.5 * math.sin(ang);
    } else {
      final pts = [for (final p in (w['path'] as List)) ui.Offset((p[0] as num).toDouble(), (p[1] as num).toDouble())];
      var total = 0.0;
      for (var i = 1; i < pts.length; i++) {
        total += (pts[i] - pts[i - 1]).distance;
      }
      var d = t * speed;
      if (d >= total) {
        d = total;
        moving = false;
      }
      k = total <= 0 ? 0 : d / total;
      var i = 1;
      var acc = 0.0;
      while (i < pts.length - 1 && acc + (pts[i] - pts[i - 1]).distance < d) {
        acc += (pts[i] - pts[i - 1]).distance;
        i++;
      }
      final seg = pts[i] - pts[i - 1];
      final u = seg.distance <= 0 ? 0.0 : ((d - acc) / seg.distance).clamp(0.0, 1.0);
      at = pts[i - 1] + seg * u;
      dir = seg;
      if (!moving && w['face'] != null) {
        final f = (w['face'] as List).cast<num>();
        dir = ui.Offset(f[0].toDouble(), f[1].toDouble());
      }
    }
    final hPx = h0[0] + (h0[h0.length - 1] - h0[0]) * k;
    final s = hPx / sheet.heightPx;
    // its direction among the sheet's eight (S, SE, E, NE, N, NW, W, SW), from how it moves on screen
    final a = math.atan2(dir.dx, dir.dy) * 180 / math.pi;
    final row = ((a / 45).round() % 8 + 8) % 8;
    final fps = ((w['fps'] as num?) ?? 12).toDouble();
    final col = moving ? 1 + ((t * fps).floor() % sheet.frames) : 0;
    final hop = w['circle'] != null ? (math.sin(t * fps * math.pi / 3).abs() * hPx * 0.18) : 0.0;
    final lantern = w['lantern'] == true;
    drawn.add((
      y: at.dy,
      draw: () {
        final scr = toScreen(at);
        final ss = s * scale;
        // a soft shadow under it, and a lantern's pool of light
        if (lantern) {
          final r = hPx * 1.6 * scale;
          c.drawOval(ui.Rect.fromCenter(center: scr, width: r * 2, height: r * 0.8),
              ui.Paint()
                ..blendMode = ui.BlendMode.plus
                ..shader = ui.Gradient.radial(scr, r, [const ui.Color(0x55FFB347), const ui.Color(0x00FFB347)]));
        }
        c.drawOval(ui.Rect.fromCenter(center: scr, width: hPx * 0.7 * scale, height: hPx * 0.2 * scale), ui.Paint()..color = const ui.Color(0x55100818));
        final src = ui.Rect.fromLTWH(col * sheet.fw, row * sheet.fh, sheet.fw, sheet.fh);
        final dst = ui.Rect.fromLTWH(scr.dx - sheet.ground.dx * ss, scr.dy - sheet.ground.dy * ss - hop * scale, sheet.fw * ss, sheet.fh * ss);
        // the dusk on it: dimmer and bluer, the lantern warming its front
        final warm = lantern ? 0.16 : 0.05;
        c.drawImageRect(
            sheet.image,
            src,
            dst,
            ui.Paint()
              ..filterQuality = ui.FilterQuality.medium
              ..colorFilter = ui.ColorFilter.matrix(<double>[
                tint[0] + warm, 0, 0, 0, 8,
                0, tint[1] + warm * 0.6, 0, 0, 4,
                0, 0, tint[2], 0, 6,
                0, 0, 0, 1, 0,
              ]));
        if (lantern) {
          // the lantern in its hand, swinging with the step
          final sw = math.sin(t * fps * math.pi / 4) * hPx * 0.04;
          final hand = ui.Offset(scr.dx + (dir.dx >= 0 ? 1 : -1) * hPx * 0.28 * scale + sw * scale, scr.dy - hPx * 0.42 * scale);
          final flick = 0.85 + 0.15 * _frac((ts * 9).floorToDouble() + at.dx);
          c.drawCircle(hand, hPx * 0.75 * scale,
              ui.Paint()
                ..blendMode = ui.BlendMode.plus
                ..shader = ui.Gradient.radial(hand, hPx * 0.75 * scale, [ui.Color.fromRGBO(255, 190, 90, 0.55 * flick), const ui.Color(0x00FFB050)]));
          c.drawCircle(hand, hPx * 0.07 * scale, ui.Paint()..color = ui.Color.fromRGBO(255, 236, 170, flick));
        }
      }
    ));
  }
  drawn.sort((a, b) => a.y.compareTo(b.y));
  for (final d in drawn) {
    d.draw();
  }
}
