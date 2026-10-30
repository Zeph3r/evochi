// An Elder's ultimate, presented (tools/art/cine_ultimate.py): the activation live (the Wilds darken, light gathers
// at its paws), the cut-in streamed full screen (the close-up, the orbit, the release, ending as the element
// fills the view), then the release marker hands back to the Wilds while that same element clears off the
// screen, revealing its effect on the battlefield. Presentation only: the combat decides what the ultimate does
// and resolves it at the marker (Raid.ultRelease).

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';

import '../../core/services/asset_manifest.dart';
import '../../game/personality/personality.dart';

const _base = '${artBase}wilds/';

/// The cut-in for one ability and personality: its frames (an opaque animated WebP), when it starts and ends in
/// the ultimate's own time, and the release marker.
class UltArt {
  UltArt._(this.bytes, this.n, this.fps, this.t0, this.t1, this.release, this.size, this.color);
  final Uint8List bytes;
  final int n;
  final double fps, t0, t1, release;
  final Size size;

  /// the element's colour (the mist clearing off the screen)
  final Color color;

  static const _palette = {'ocean': 'healing_mist'};
  static const _colors = {'healing_mist': Color(0xFFA9DCF5)};

  /// The personality the cut-in is performed in (the face kit's six; the three profiles map onto them until
  /// there are six profiles).
  static String variantFor(Personality? p) => switch (p?.profile) {
        'calm' => 'calm',
        'timid' || 'cautious' => 'timid',
        'playful' || 'lively' => 'playful',
        final String s => s,
        null => 'brave',
      };

  /// The cut-in for an Elder of [palette] with [personality], or null where there is none yet (the ultimate
  /// keeps its short wind-up). A missing personality falls back to Brave.
  static Future<UltArt?> load(String palette, Personality? personality) async {
    final ability = _palette[palette];
    if (ability == null) return null;
    try {
      final j = (jsonDecode(await rootBundle.loadString('${_base}ultimates.json')) as Map).cast<String, dynamic>();
      final a = ((j['abilities'] as Map)[ability] as Map?)?.cast<String, dynamic>();
      if (a == null) return null;
      final v = (a['variants'] as Map).cast<String, dynamic>();
      final file = (v[variantFor(personality)] ?? v['brave']) as String?;
      if (file == null) return null;
      final bytes = (await rootBundle.load(_base + file)).buffer.asUint8List();
      double d(Object? x) => (x as num).toDouble();
      return UltArt._(bytes, (a['n'] as num).toInt(), d(j['fps']), d(a['t0']), d(a['t1']), d(a['release']),
          Size(d(j['w']), d(j['h'])), _colors[ability] ?? const Color(0xFFFFFFFF));
    } catch (_) {
      return null;
    }
  }
}

/// The ultimate's presentation over the Wilds, from the button: [onRelease] at the marker (once), [onDone] when the
/// element has cleared off the screen.
class UltCutIn extends StatefulWidget {
  const UltCutIn({super.key, required this.art, required this.onRelease, required this.onDone});
  final UltArt art;
  final VoidCallback onRelease, onDone;
  @override
  State<UltCutIn> createState() => _UltCutInState();
}

class _UltCutInState extends State<UltCutIn> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = ValueNotifier(0);
  ui.Codec? _codec;
  ui.Image? _frame;
  int _at = -1;
  bool _busy = false, _released = false, _done = false;
  double _t = 0;

  /// how long the element takes to clear off the screen after the marker
  static const clear = 0.6;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
    ui.instantiateImageCodec(widget.art.bytes).then((c) {
      if (!mounted) {
        c.dispose();
        return;
      }
      _codec = c;
    });
  }

  void _want(int i) {
    final c = _codec;
    if (c == null || _busy || _at >= i || _at >= widget.art.n - 1) return;
    _busy = true;
    c.getNextFrame().then((f) {
      _busy = false;
      if (!mounted) {
        f.image.dispose();
        return;
      }
      _frame?.dispose();
      _frame = f.image;
      _at++;
      _repaint.value++;
      if (_at < i) _want(i);
    }, onError: (Object _) {
      _busy = false;
    });
  }

  void _tick(Duration d) {
    final a = widget.art;
    _t = d.inMicroseconds / 1e6;
    if (_t >= a.t0 - 0.05) _want(((_t - a.t0) * a.fps).floor().clamp(0, a.n - 1));
    if (!_released && _t >= a.release) {
      _released = true;
      widget.onRelease();
    }
    if (!_done && _t >= a.release + clear) {
      _done = true;
      _ticker.stop();
      widget.onDone();
    }
    _repaint.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame?.dispose();
    _codec?.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(child: CustomPaint(painter: _CutInPainter(this), size: Size.infinite));
}

class _CutInPainter extends CustomPainter {
  _CutInPainter(this.s) : super(repaint: s._repaint);
  final _UltCutInState s;

  @override
  void paint(Canvas canvas, Size size) {
    final a = s.widget.art;
    final t = s._t;
    final full = Offset.zero & size;
    if (t < a.t0 || s._frame == null && t < a.release) {
      // the activation, live: the Wilds darken round your Evochi as its light gathers
      final k = (t / a.t0).clamp(0.0, 1.0);
      canvas.drawRect(full, Paint()..color = Color.fromRGBO(8, 12, 30, 0.55 * k));
      return;
    }
    final im = s._frame;
    if (t < a.release && im != null) {
      // the cut-in, covering the screen (cropped at the sides of a narrower one)
      final src = Rect.fromLTWH(0, 0, im.width.toDouble(), im.height.toDouble());
      final k = math.max(size.width / src.width, size.height / src.height);
      final dst = Rect.fromCenter(center: full.center, width: src.width * k, height: src.height * k);
      canvas.drawImageRect(im, src, dst, Paint()..filterQuality = FilterQuality.medium);
      return;
    }
    // back in the Wilds: the element that filled the view clears off it, outward from the middle, as its effect
    // spreads over the battlefield underneath
    final u = ((t - a.release) / _UltCutInState.clear).clamp(0.0, 1.0);
    final e = 1 - (1 - u) * (1 - u);
    final c = a.color;
    final r = size.longestSide * (0.15 + 1.1 * e);
    final hole = Paint()
      ..shader = ui.Gradient.radial(full.center, r + 1, [
        c.withValues(alpha: 0),
        c.withValues(alpha: 0.85 * (1 - e)),
        c.withValues(alpha: 0.95 * (1 - e)),
      ], [
        0.0,
        0.75,
        1.0,
      ], TileMode.clamp);
    canvas.drawRect(full, hole);
    // drifting wisps on the way out
    for (var i = 0; i < 7; i++) {
      final ang = i * 0.9 + t;
      final at = full.center + Offset(math.cos(ang), math.sin(ang) * 1.6) * (r * 0.8);
      canvas.drawCircle(at, size.width * 0.22, Paint()
        ..color = c.withValues(alpha: 0.25 * (1 - e))
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 30));
    }
  }

  @override
  bool shouldRepaint(_CutInPainter old) => true;
}
