// A plate with a character in it that moves. The shot is rendered again in a few poses (tools/art/cine_scenes.py
// PIP_POSES, MIRA_POSES), and tools/art/cine_poses.py cuts the same feathered box round the character out of each
// pose into one sheet (assets/art/cine/<plate>_poses.webp, described in cine_poses.json): the box is drawn over the
// plate in whichever pose is playing. Every frame is the whole shot re-rendered, so light, shadow and focus match.
//
// cine_poses.json also holds the clips (a blink, a tilt, presenting the letter...) and how the character idles:
// a blink every few seconds, a gesture now and then, one to open with. [PoseController.play] starts a clip from
// the screen (Mira looks down at the egg you pick). Reduced motion: the plate as it is.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../app/motion.dart';
import 'cinematic_player.dart';

/// Starts one of a posed plate's clips from outside (say, when the player picks an egg).
class PoseController extends ChangeNotifier {
  String? _clip;
  void play(String clip) {
    _clip = clip;
    notifyListeners();
  }
}

class _Poses {
  _Poses(this.plate, this.atlas, this.box, this.frames, this.clips, this.idle);
  final String plate;
  final String atlas;
  final Rect box; // in the plate's packed px
  final Map<String, Rect> frames; // in the sheet
  final Map<String, List<(String, double)>> clips; // frame, seconds
  final Map<String, dynamic> idle;

  static Map<String, _Poses>? _all;

  static Future<Map<String, _Poses>> load() async {
    final a = _all;
    if (a != null) return a;
    Rect r(List l) => Rect.fromLTWH((l[0] as num).toDouble(), (l[1] as num).toDouble(), (l[2] as num).toDouble(), (l[3] as num).toDouble());
    try {
      final j = jsonDecode(await rootBundle.loadString('$cineDir/cine_poses.json')) as Map<String, dynamic>;
      return _all = {
        for (final e in j.entries)
          e.key: _Poses(
            e.key,
            (e.value as Map)['atlas'] as String,
            r((e.value as Map)['box'] as List),
            {for (final f in ((e.value as Map)['frames'] as Map).entries) f.key as String: r(f.value as List)},
            {
              for (final c in ((e.value as Map)['clips'] as Map).entries)
                c.key as String: [for (final s in c.value as List) ((s as List)[0] as String, ((s[1] as num).toDouble()) / 1000)],
            },
            ((e.value as Map)['idle'] as Map).cast<String, dynamic>(),
          ),
      };
    } catch (_) {
      return _all = const {};
    }
  }
}

/// [name]'s plate, cover-fitted with [alignment] like [CinePlate], with its character playing its poses.
class PosedPlate extends StatefulWidget {
  const PosedPlate(this.name, {super.key, this.alignment = Alignment.center, this.onMissing, this.controller});
  final String name;
  final Alignment alignment;
  final Widget? onMissing;
  final PoseController? controller;

  @override
  State<PosedPlate> createState() => _PosedPlateState();
}

class _PosedPlateState extends State<PosedPlate> with SingleTickerProviderStateMixin {
  ui.Image? _plate;
  ui.Image? _sheet;
  _Poses? _poses;
  bool _missing = false;
  late final Ticker _ticker = createTicker(_tick);
  final _rng = math.Random();
  double _t = 0;
  String? _frame; // the pose showing (null: the plate's own)
  List<(String, double)> _clip = const [];
  double _clipAt = 0;
  double _nextBlink = 2.4;
  double _nextGesture = 0;
  int _gesture = 0;
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onPlay);
    AtlasCache.load('$cineDir/${widget.name}.webp').then((im) {
      if (mounted) setState(() => _plate = im);
    }).catchError((_) {
      if (mounted) setState(() => _missing = true);
    });
    _Poses.load().then((all) {
      final p = all[widget.name];
      if (!mounted || p == null) return;
      _poses = p;
      AtlasCache.load('$cineDir/${p.atlas}').then((im) {
        if (!mounted) return;
        setState(() => _sheet = im);
        if (!Motion.reducedNow(context)) _ticker.start();
      }).catchError((_) {});
    });
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onPlay);
    _ticker.dispose();
    super.dispose();
  }

  void _onPlay() {
    final c = widget.controller?._clip;
    if (c != null) _start(c);
  }

  void _start(String clip) {
    final frames = _poses?.clips[clip];
    if (frames == null || frames.isEmpty) return;
    _clip = frames;
    _clipAt = _t;
  }

  double _range(String key, double a, double b) {
    final v = _poses?.idle[key];
    if (v is List && v.length == 2) {
      final lo = (v[0] as num).toDouble(), hi = (v[1] as num).toDouble();
      return lo + _rng.nextDouble() * (hi - lo);
    }
    return a + _rng.nextDouble() * (b - a);
  }

  void _tick(Duration d) {
    final p = _poses;
    if (p == null) return;
    _t = d.inMicroseconds / 1e6;
    if (!_opened) {
      _opened = true;
      final open = p.idle['opening'] as String?;
      final delay = ((p.idle['opening_at'] as num?) ?? 0.6).toDouble();
      _nextGesture = open != null ? delay : _range('gesture_every', 6.5, 10);
      if (open != null) _gesture = -1; // the first gesture is the opening one
    }
    String? frame;
    if (_clip.isNotEmpty) {
      var u = _t - _clipAt;
      for (final (f, s) in _clip) {
        if (u < s) {
          frame = f;
          break;
        }
        u -= s;
      }
      if (frame == null) _clip = const [];
    }
    if (_clip.isEmpty) {
      if (_t >= _nextGesture) {
        final gestures = ((p.idle['gestures'] as List?) ?? const []).cast<String>();
        final open = p.idle['opening'] as String?;
        final g = _gesture < 0 && open != null ? open : (gestures.isEmpty ? null : gestures[_gesture % gestures.length]);
        _gesture++;
        _nextGesture = _t + _range('gesture_every', 6.5, 10);
        _nextBlink = math.max(_nextBlink, _t + 1.2);
        if (g != null) _start(g);
      } else if (_t >= _nextBlink) {
        _nextBlink = _t + _range('blink_every', 2.6, 5.0);
        _start('blink');
      }
    }
    if (frame != _frame) setState(() => _frame = frame);
  }

  @override
  Widget build(BuildContext context) {
    final plate = _plate;
    if (plate == null) return _missing ? (widget.onMissing ?? const SizedBox.shrink()) : const SizedBox.shrink();
    final p = _poses, sheet = _sheet, f = _frame;
    final src = p == null || sheet == null || f == null ? null : p.frames[f];
    return CustomPaint(
      size: Size.infinite,
      painter: _PosedPainter(plate, widget.alignment, sheet, src, p?.box),
    );
  }
}

class _PosedPainter extends CustomPainter {
  _PosedPainter(this.plate, this.alignment, this.sheet, this.src, this.box);
  final ui.Image plate;
  final Alignment alignment;
  final ui.Image? sheet;
  final Rect? src; // the pose's cell in the sheet, or null for the plate as it is
  final Rect? box; // where the cell goes on the plate (plate px)

  @override
  void paint(Canvas c, Size size) {
    final ps = Size(plate.width.toDouble(), plate.height.toDouble());
    final fit = CineFit(size, ps, alignment: alignment);
    final paint = Paint()..filterQuality = FilterQuality.medium;
    c.save();
    c.clipRect(Offset.zero & size);
    c.drawImageRect(plate, Offset.zero & ps, Rect.fromLTWH(fit.origin.dx, fit.origin.dy, ps.width * fit.k, ps.height * fit.k), paint);
    final s = sheet, r = src, b = box;
    if (s != null && r != null && b != null) {
      c.drawImageRect(s, r, Rect.fromLTWH(fit.origin.dx + b.left * fit.k, fit.origin.dy + b.top * fit.k, b.width * fit.k, b.height * fit.k), paint);
    }
    c.restore();
  }

  @override
  bool shouldRepaint(_PosedPainter o) => o.plate != plate || o.sheet != sheet || o.src != src || o.box != box || o.alignment != alignment;
}
