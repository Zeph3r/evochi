// The guardian's entrance: a short cinematic before the Briarback fight, built from anticipation to impact.
//
//   1. Anticipation: letterbox; out of the dark and the fog, the Briarback steps in, its crystals lit first.
//      Your Evochi in front, seen over its shoulder.
//   2. Hoof Impact: a heavy step lands; dust and leaves kick up.
//   3. Antler Charge: it lowers its head; motes are pulled into the antler tips, thorn arcs form round it.
//   4. Roar Release: it rears and roars; light bursts out of the antlers; the camera pushes in, shaking.
//   5. Shockwave: thorn-and-rune waves roll out of its mouth over the wood; grass lies flat, leaves, pollen
//      and stones are swept out; the fog is shoved aside.
//   6. Evochi Reaction: cut to your Evochi inside the wave, its own Shock -> Strain -> Resolve.
//   7. Title Reveal: back on the guardian as it comes down; the last waves break into leaves, sparks and
//      fading runes; the title.
//   8. Settle: its energy ebbs; your Evochi in front again; then the fight starts.
//
// The Briarback is a pre-rendered sequence (tools/art/boss_intro.py, with its antler tips and eyes marked);
// your Evochi is its reaction's frames and a view from behind (tools/art/cine_react_export.py). An Evochi
// wearing something keeps the older art for now (tools/art/cine_evochi.py: its faces, worn pieces on). Light,
// fog, waves, the wood and the title are drawn here (briar_scene.dart). Tap to skip. The full version plays the
// first time; after that a short one (the landing and the title); with reduced motion, a still title card. The
// Forgotten Sentinel's entrance is in sentinel_intro.dart.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';
import 'wilds_art.dart' show wildsBase;

part 'briar_scene.dart';
part 'sprout_intro.dart';
part 'sentinel_intro.dart';
part 'jump_art.dart';

Future<ui.Image> _img(String path) async {
  final data = await rootBundle.load(path);
  final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

Offset _pt(dynamic p) => Offset(((p as List)[0] as num).toDouble(), (p[1] as num).toDouble());

/// The guardian's frames and where things land in them. The frames stay compressed until they are
/// needed: a few ahead of the playhead are decoded and the ones behind are let go, so a phone never
/// holds the whole sequence as pictures at once.
class BossIntroArt {
  BossIntroArt._(this.bytes, this.size, this.impact, this.ground, this.mouth, this.hooves, {this.decode = true, this.meta = const {}});

  /// A stand-in with no pictures (tests: the timeline, the cues, skipping).
  @visibleForTesting
  factory BossIntroArt.blank({int frames = 36, int impact = 25}) => BossIntroArt._(
        List.filled(frames, Uint8List(0)),
        const Size(864, 1296),
        impact,
        List.filled(frames, const Offset(432, 1240)),
        List.filled(frames, const Offset(450, 700)),
        List.filled(frames, const [Offset(400, 1240), Offset(470, 1240)]),
        decode: false,
      );
  final List<Uint8List> bytes;
  final Size size;
  final int impact;
  final List<Offset> ground, mouth;
  final List<List<Offset>> hooves;
  final bool decode;

  /// The sequence's own marks (the Sentinel's: where its runes and shots start, its chest per frame).
  final Map<String, dynamic> meta;

  /// The Briarback's antler tips and eyes per frame (the near eye first), where the sequence has them.
  late final List<List<Offset>> antlers = [for (final f in (meta['antlers'] as List?) ?? const []) [for (final p in f as List) _pt(p)]];
  late final List<List<Offset>> eyes = [for (final f in (meta['eyes'] as List?) ?? const []) [for (final p in f as List) _pt(p)]];
  final _decoded = <int, ui.Image>{};
  final _pending = <int>{};

  int get count => bytes.length;

  /// [warm]: the frames to have ready before it starts (the openings of its cuts).
  static Future<BossIntroArt> load(String key, {List<int> warm = const [0, 1, 2, 22, 23, 24]}) async {
    final j = (jsonDecode(await rootBundle.loadString('$wildsBase${key}_intro.json')) as Map).cast<String, dynamic>();
    final n = (j['frames'] as num).toInt();
    // one at a time: a bundle may hand back already-finished futures (tests do), and Future.wait loses
    // those
    final bytes = <Uint8List>[];
    for (var i = 0; i < n; i++) {
      final d = await rootBundle.load('$wildsBase${key}_intro_${i.toString().padLeft(2, '0')}.webp');
      bytes.add(d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes));
    }
    // the Briarback's mouth and hooves; the Sentinel's eyes and fists
    final art = BossIntroArt._(
      bytes,
      Size((j['w'] as num).toDouble(), (j['h'] as num).toDouble()),
      ((j['impact'] ?? j['menace']) as num).toInt(),
      [for (final p in j['ground'] as List) _pt(p)],
      [for (final p in (j['mouth'] ?? j['eyes']) as List) _pt(p)],
      [for (final h in (j['hooves'] ?? j['fists']) as List) [for (final p in h as List) _pt(p)]],
      meta: j,
    );
    if (art.count == 0) throw StateError('$key intro: no frames (json says $n, loaded ${bytes.length})');
    await art.want([...warm, n - 1]);
    return art;
  }

  /// Decode these (if not already); let go of every other frame except [keep].
  Future<void> want(Iterable<int> idx, {Iterable<int> keep = const []}) async {
    if (!decode) return;
    final need = {for (final i in idx) i.clamp(0, count - 1)};
    final hold = {...need, for (final i in keep) i.clamp(0, count - 1), count - 1};
    for (final k in _decoded.keys.toList()) {
      if (!hold.contains(k)) _decoded.remove(k)!.dispose();
    }
    await Future.wait([
      for (final i in need)
        if (!_decoded.containsKey(i) && _pending.add(i))
          ui.instantiateImageCodec(bytes[i]).then((c) => c.getNextFrame()).then((f) {
            _pending.remove(i);
            _decoded[i] = f.image;
          }),
    ]);
  }

  /// The frame, or the nearest one already decoded (behind it first).
  ui.Image? frame(int i) {
    final f = _decoded[i];
    if (f != null) return f;
    for (var d = 1; d < count; d++) {
      final a = _decoded[i - d] ?? _decoded[i + d];
      if (a != null) return a;
    }
    return null;
  }

  void dispose() {
    for (final f in _decoded.values) {
      f.dispose();
    }
    _decoded.clear();
  }
}

/// Your Evochi from the low heroic angle: the three cinematic faces and whatever it wears.
class CineEvochiArt {
  CineEvochiArt._(this.faces, this.wear, this.cell, this.faceIds, this.cells, this.ground, this.face);
  final ui.Image faces;
  final ui.Image? wear;
  final Size cell;
  final List<String> faceIds;
  final List<Offset> cells; // the worn pieces' cells in the wear sheet (col, row)
  final Offset ground, face;

  static Future<CineEvochiArt?> load(int stage, String palette, Iterable<String> worn) async {
    final j = (jsonDecode(await rootBundle.loadString('${wildsBase}wilds_cine.json')) as Map).cast<String, dynamic>();
    final st = (j['s0${stage.clamp(1, 3)}'] as Map?)?.cast<String, dynamic>();
    if (st == null) return null;
    final sheet = (st['sheets'] as Map)[palette] ?? (st['sheets'] as Map)['amber'];
    if (sheet == null) return null;
    final wearMap = (st['wear'] as Map).cast<String, dynamic>();
    final cells = [for (final k in worn) if (wearMap[k] != null) _pt(wearMap[k])];
    final anchors = (st['anchors'] as Map).cast<String, dynamic>();
    return CineEvochiArt._(
      await _img(wildsBase + (sheet as String)),
      cells.isEmpty ? null : await _img(wildsBase + (st['wearSheet'] as String)),
      Size((st['w'] as num).toDouble(), (st['h'] as num).toDouble()),
      [for (final f in j['faces'] as List) f as String],
      cells,
      _pt(anchors['ground']),
      _pt(anchors['face']),
    );
  }

  /// Draws it with its feet at the canvas origin, [h] tall.
  void draw(Canvas canvas, String face, double h, Paint paint) {
    final k = h / cell.height;
    final i = math.max(0, faceIds.indexOf(face));
    final dst = Rect.fromLTWH(-ground.dx * k, -ground.dy * k, cell.width * k, cell.height * k);
    canvas.drawImageRect(faces, Rect.fromLTWH(i * cell.width, 0, cell.width, cell.height), dst, paint);
    final w = wear;
    if (w != null) {
      for (final c in cells) {
        canvas.drawImageRect(w, Rect.fromLTWH(c.dx * cell.width, c.dy * cell.height, cell.width, cell.height), dst, paint);
      }
    }
  }
}

/// Your Evochi taking the roar (tools/art/cine_react_export.py): frames of its Shock -> Strain -> Resolve from
/// the entrance's camera, at the times they show from, and itself from behind, over its shoulder, for the wide
/// shots.
class ReactArt {
  ReactArt._(this.stage, this.sheet, this.cell, this.cols, this.times, this.end, this.ground, this.feet, this.back, this.backCell,
      this.backGround, this.wear, this.backWear, this.backCells);
  final int stage;

  /// what it wears, over every frame (one sheet per piece, laid out as the frames are), and over the view
  /// from behind (one cell per piece in [backWear])
  final List<ui.Image> wear;
  final ui.Image? backWear;
  final List<int> backCells;
  final ui.Image sheet;
  final Size cell;
  final int cols;
  final List<double> times;
  final double end;
  final Offset ground;

  /// per frame, where each foot meets the ground (near front, far front, near back, far back): its footprint's
  /// centre and radii in the cell's pixels, and how far it is off the ground (world units, 0 planted)
  final List<List<FootContact?>> feet;
  final ui.Image back;
  final Size backCell;
  final Offset backGround;

  static Future<ReactArt?> load(int stage, String palette, [Iterable<String> worn = const []]) async {
    try {
      final j = (jsonDecode(await rootBundle.loadString('${wildsBase}wilds_react.json')) as Map).cast<String, dynamic>();
      final st = (j['s0${stage.clamp(1, 3)}'] as Map?)?.cast<String, dynamic>();
      if (st == null) return null;
      final sheets = (st['sheets'] as Map).cast<String, dynamic>();
      final b = (st['back'] as Map).cast<String, dynamic>();
      final bs = (b['sheets'] as Map).cast<String, dynamic>();
      // every piece it wears needs its frames; without them (an older build, a piece not drawn yet) the
      // entrance uses the older art, so nothing it wears goes missing
      final wm = ((st['wear'] as Map?) ?? const {}).cast<String, dynamic>();
      final bw = ((b['wear'] as Map?) ?? const {}).cast<String, dynamic>();
      if (worn.any((k) => wm[k] == null || bw[k] == null)) return null;
      return ReactArt._(
        stage.clamp(1, 3),
        await _img(wildsBase + ((sheets[palette] ?? sheets['amber']) as String)),
        Size((st['w'] as num).toDouble(), (st['h'] as num).toDouble()),
        (j['cols'] as num).toInt(),
        [for (final x in st['times'] as List) (x as num).toDouble()],
        (st['end'] as num).toDouble(),
        _pt(st['ground']),
        [
          for (final f in (st['feet'] as List?) ?? const [])
            [
              for (final c in f as List)
                c == null
                    ? null
                    : FootContact(_pt(c), ((c as List)[2] as num).toDouble(), (c[3] as num).toDouble(), (c[4] as num).toDouble())
            ]
        ],
        await _img(wildsBase + ((bs[palette] ?? bs['amber']) as String)),
        Size((b['w'] as num).toDouble(), (b['h'] as num).toDouble()),
        _pt(b['ground']),
        [for (final k in worn) await _img(wildsBase + (wm[k] as String))],
        worn.isEmpty ? null : await _img(wildsBase + (b['wearSheet'] as String)),
        [for (final k in worn) (bw[k] as num).toInt()],
      );
    } catch (_) {
      return null; // no reaction art: the older art is used
    }
  }

  // ---- how the roar's waves hit it (the frames are keyed to these: the first wave full on, a second shove, the
  // third as it slams down into its brace)

  /// how heavy it is: the Eggling is knocked about most, the Elder least
  double get give => switch (stage) { 1 => 1.25, 3 => 0.7, _ => 1.0 };

  /// when the waves reach it, seconds into the reaction, and how hard
  List<double> get hits => [0.0, end * 0.17, end * 0.3];
  static const hitForce = [1.0, 0.55, 0.35];

  /// the jolt of the waves now: 1 the instant the first lands, falling away fast
  double impulse(double u) {
    var s = 0.0;
    final h = hits;
    for (var i = 0; i < h.length; i++) {
      final x = u - h[i];
      if (x < 0) continue;
      s += hitForce[i] * (x < 0.05 ? x / 0.05 : math.exp(-(x - 0.05) / 0.13));
    }
    return s;
  }

  /// how far the waves have shoved it back (screen widths), less what it wins back as it recovers
  double skid(double u) {
    final h = hits;
    double s(double x) => Curves.easeOutCubic.transform((x / 0.24).clamp(0.0, 1.0));
    final back = 0.075 * s(u - h[0]) + 0.035 * s(u - h[1]) + 0.02 * s(u - h[2]);
    return back * give * (1 - 0.3 * Curves.easeInOutCubic.transform(((u - end * 0.7) / 0.3).clamp(0.0, 1.0)));
  }

  /// the moment the hit lands hardest (thrown back, mouth open, front feet up), and one deep in the brace
  double get peak => switch (stage) { 1 => 0.13, 3 => 0.08, _ => 0.06 };
  double get braced => end * 0.33;

  /// the first hit holds a beat (a hit-stop) on the frame where it lands hardest: the reaction's own time for [u]
  double frameTime(double u) {
    final p = switch (stage) { 1 => 0.05, 3 => 0.08, _ => 0.06 };
    return u < p ? u : (u < p + 0.06 ? p : u - 0.06);
  }

  /// the frame showing [u] seconds into the reaction
  int frameAt(double u) {
    var i = 0;
    for (var k = 0; k < times.length; k++) {
      if (times[k] <= u + 1e-6) i = k;
    }
    return i;
  }

  /// Where its feet meet the ground [u] seconds in, drawn [h] tall with its ground point at the origin (the same
  /// space [draw] draws in). Empty for older art.
  List<FootContact> contacts(double u, double h) => contactsAt(frameAt(frameTime(u)), h);

  /// The same for frame [i].
  List<FootContact> contactsAt(int i, double h) {
    if (i >= feet.length) return const [];
    final k = h / cell.height;
    return [
      for (final c in feet[i])
        if (c != null) FootContact((c.at - ground) * k, c.rx * k, c.ry * k, c.lift),
    ];
  }

  /// Draws it with its feet at the canvas origin, [h] tall, [u] seconds into its reaction.
  void draw(Canvas canvas, double u, double h, Paint paint) => drawFrame(canvas, frameAt(frameTime(u)), h, paint);

  /// Draws frame [i] (see [frameAt]) the same way.
  void drawFrame(Canvas canvas, int i, double h, Paint paint) {
    final k = h / cell.height;
    final src = Rect.fromLTWH((i % cols) * cell.width, (i ~/ cols) * cell.height, cell.width, cell.height);
    final dst = Rect.fromLTWH(-ground.dx * k, -ground.dy * k, cell.width * k, cell.height * k);
    canvas.drawImageRect(sheet, src, dst, paint);
    for (final w in wear) {
      canvas.drawImageRect(w, src, dst, paint);
    }
  }

  /// Draws it from behind, feet at the origin, [h] tall.
  void drawBack(Canvas canvas, double h, Paint paint) {
    final k = h / backCell.height;
    final dst = Rect.fromLTWH(-backGround.dx * k, -backGround.dy * k, backCell.width * k, backCell.height * k);
    canvas.drawImageRect(back, Rect.fromLTWH(0, 0, backCell.width, backCell.height), dst, paint);
    final bw = backWear;
    if (bw != null) {
      for (final c in backCells) {
        canvas.drawImageRect(bw, Rect.fromLTWH(c * backCell.width, 0, backCell.width, backCell.height), dst, paint);
      }
    }
  }
}

/// One foot on the ground: its footprint's centre, its radii as seen, and how high it is lifted (world units).
class FootContact {
  const FootContact(this.at, this.rx, this.ry, this.lift);
  final Offset at;
  final double rx, ry, lift;
}

enum IntroCut { full, short, still }

class BossIntro extends StatefulWidget {
  const BossIntro({
    super.key,
    required this.art,
    required this.evochi,
    this.react,
    required this.cut,
    required this.name,
    required this.title,
    required this.petName,
    required this.tint,
    required this.onCue,
    required this.onDone,
  });
  final BossIntroArt art;
  final CineEvochiArt? evochi;

  /// its reaction and its view from behind; without them, [evochi]'s faces are used
  final ReactArt? react;
  final IntroCut cut;
  final String name, title, petName;
  final Color tint;
  final void Function(String cue) onCue;
  final VoidCallback onDone;

  @override
  State<BossIntro> createState() => _BossIntroState();
}

// the full cut's timeline (seconds)
const _open = 0.35; // letterbox in; the frames start, out of the dark
const _step = 0.85; // frame 6: the hoof lands
const _rearEnd = 1.52; // frames 0..14 at 12 fps: paw, step, lower the antlers (charging), rear: the roar
const _blast = 2.9; // cut to your Evochi in the wave
const _slam = 5.0; // back to the guardian coming down: frames 22..35 at 15 fps
const _faceOff = 6.1; // it settles; your Evochi in front
const _fullLen = 7.95;
const _shortLen = 1.8;
const _stillLen = 2.4;

class _BossIntroState extends State<BossIntro> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  bool _done = false;
  final _fired = <String>{};

  double get _len => switch (widget.cut) { IntroCut.full => _fullLen, IntroCut.short => _shortLen, IntroCut.still => _stillLen };

  /// when the hooves hit the ground
  double get impactT => switch (widget.cut) {
        IntroCut.full => _slam + (widget.art.impact - 22) / 15,
        IntroCut.short => 0.15 + (widget.art.impact - 22) / 15,
        IntroCut.still => 0.0,
      };

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((e) {
      final t = e.inMicroseconds / 1e6;
      setState(() => _t = t);
      _prefetch(t);
      _cues();
      if (t >= _len) _finish();
    })
      ..start();
  }

  /// the frames the next half second will need (the roar's loop is kept while it plays)
  void _prefetch(double t) {
    final p = _IntroPainter(this, 0, Offset.zero);
    final idx = <int>{};
    for (var d = 0.0; d <= 0.5; d += 1 / 15) {
      idx.add(p.frameAt(t + d));
    }
    final roar = widget.cut == IntroCut.full && t > _rearEnd - 0.6 && t < _slam;
    widget.art.want(idx, keep: roar ? const [15, 16, 17, 18, 19, 20, 21] : const []);
  }

  void _cue(String id, double at) {
    if (_t >= at && _fired.add(id)) widget.onCue(id);
  }

  void _cues() {
    switch (widget.cut) {
      case IntroCut.full:
        _cue('open', 0);
        _cue('step', _step);
        _cue('charge', _step + 0.15);
        _cue('roar', _rearEnd);
        _cue('blast', _blast);
        _cue('dig', _blast + 0.42);
        _cue('slam', impactT);
        _cue('whoosh', _faceOff);
        _cue('ready', _faceOff + 0.45);
      case IntroCut.short:
        _cue('slam', impactT);
      case IntroCut.still:
        _cue('roar', 0);
    }
  }

  void _finish() {
    if (_done) return;
    _done = true;
    _ticker.stop();
    widget.onDone();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final it = impactT;
    // the title slams in with the hooves and stays to the end
    final since = t - it;
    final titleOn = widget.cut == IntroCut.still || since >= 0;
    final pop = widget.cut == IntroCut.still ? 1.0 : Curves.easeOutBack.transform((since / 0.22).clamp(0.0, 1.0));
    final fadeOut = ((_len - t) / 0.45).clamp(0.0, 1.0);
    final shake = _shake(t);
    return Semantics(
      label: '${widget.name}, ${widget.title}. Tap to skip.',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: LayoutBuilder(builder: (ctx, b) {
          final size = Size(b.maxWidth, b.maxHeight);
          final bar = size.height * (widget.cut == IntroCut.full ? 0.1 : 0.07);
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _IntroPainter(this, t, shake))),
            if (titleOn)
              Positioned(
                left: 12,
                right: 12,
                top: bar + 14 + shake.dy,
                child: Opacity(
                  opacity: (pop.clamp(0.0, 1.0) * fadeOut).toDouble(),
                  child: Transform.scale(scale: 1 + (1 - pop) * 0.9, child: _Title(name: widget.name, title: widget.title, width: size.width, sigil: true)),
                ),
              ),
            if (widget.cut == IntroCut.full && t > _faceOff + 0.35)
              Positioned(
                left: 16,
                bottom: bar + 10,
                child: Opacity(
                  opacity: (((t - _faceOff - 0.35) / 0.25).clamp(0.0, 1.0) * fadeOut).toDouble(),
                  child: _NameTag(name: widget.petName, tint: widget.tint),
                ),
              ),
            Positioned(
              right: 14,
              bottom: math.max(6, bar / 2 - 8),
              child: Opacity(
                opacity: 0.65 * fadeOut,
                child: const Text('Tap to skip', style: TextStyle(fontFamily: EvochiText.body, fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFE8E2F2))),
              ),
            ),
          ]);
        }),
      ),
    );
  }

  Offset _shake(double t) {
    if (widget.cut == IntroCut.still) return Offset.zero;
    var s = 0.0;
    final since = t - impactT;
    if (since >= 0 && since < 0.6) s = math.max(s, 16 * math.pow(1 - since / 0.6, 2).toDouble());
    if (widget.cut == IntroCut.full) {
      // the step thumps; the roar kicks, then rumbles; the blast shoves
      if (t > _step && t < _step + 0.35) s = math.max(s, 6 * (1 - (t - _step) / 0.35));
      if (t > _rearEnd && t < _rearEnd + 0.4) s = math.max(s, 8 * (1 - (t - _rearEnd) / 0.4));
      if (t > _rearEnd && t < _blast) s = math.max(s, 3.0);
      if (t > _blast && t < _blast + 0.5) s = math.max(s, 9 * (1 - (t - _blast) / 0.5));
      // each wave that reaches your Evochi jolts the shot
      final rv = widget.react;
      if (rv != null && t > _blast && t < _slam) s = math.max(s, 7 * math.min(1.0, rv.impulse(t - _blast)));
    }
    if (s == 0) return Offset.zero;
    return Offset(math.sin(t * 97) * s, math.cos(t * 83) * s * 0.7);
  }
}

int _a(double a) => (a * 255).round().clamp(0, 255);
double _ease(double t) => Curves.easeInOutCubic.transform(t.clamp(0.0, 1.0));
double _h(int i, int k) {
  final v = math.sin(i * 12.9898 + k * 78.233) * 43758.5453;
  return v - v.floorToDouble();
}

class _IntroPainter extends CustomPainter with _IntroFx, _BriarScene {
  _IntroPainter(this.s, this.t, this.shake);
  final _BossIntroState s;
  @override
  final double t;
  final Offset shake;

  @override
  BossIntroArt get art => s.widget.art;
  @override
  ReactArt? get react => s.widget.react;
  @override
  double get impactT => s.impactT;
  @override
  IntroCut get cut => s.widget.cut;
  @override
  Color get tint => s.widget.tint;
  @override
  double get len => s._len;

  int _frame() => frameAt(t);

  @override
  int frameAt(double t) {
    final n = art.count;
    switch (cut) {
      case IntroCut.still:
        return n - 1;
      case IntroCut.short:
        return (22 + ((t - 0.15).clamp(0.0, 9.0) * 15).floor()).clamp(0, n - 1);
      case IntroCut.full:
        if (t < _rearEnd) return ((t - _open).clamp(0.0, 9.0) * 12).floor().clamp(0, 14);
        if (t < _slam) {
          const seq = [15, 16, 17, 18, 19, 20, 21, 20, 19, 18, 17, 16];
          return seq[((t - _rearEnd) * 13).floor() % seq.length].clamp(0, n - 1);
        }
        return (22 + ((t - _slam) * 15).floor()).clamp(0, n - 1);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    final env = math.min(((t) / _open).clamp(0.0, 1.0), ((len - t) / 0.45).clamp(0.0, 1.0));
    // night in the Thicket
    final bg = Rect.fromLTWH(0, 0, W, H);
    canvas.drawRect(
        bg,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, H), [
            Color.fromRGBO(18, 12, 32, env),
            Color.fromRGBO(32, 22, 50, env),
            Color.fromRGBO(22, 28, 28, env),
          ], [0, 0.55, 1]));
    canvas.save();
    canvas.translate(shake.dx, shake.dy);
    final ev = s.widget.evochi, rv = s.widget.react;
    final inBlast = cut == IntroCut.full && t >= _blast && t < _slam;
    final faceOff = cut == IntroCut.full && t >= _faceOff;
    if (inBlast && rv != null) {
      reactShot(canvas, size, env, rv);
    } else if (inBlast && ev != null) {
      _legacyBlast(canvas, size, env);
    } else {
      guardianShot(canvas, size, env, settle: faceOff && rv != null);
      if (faceOff && rv == null && ev != null) _faceOffShot(canvas, size, env);
    }
    _motes(canvas, size, env);
    canvas.restore();
    vignette(canvas, size, env);
    // a violet flash as it roars, a white one as it lands
    if (cut == IntroCut.full && t >= _rearEnd && t < _rearEnd + 0.25) {
      canvas.drawRect(bg, Paint()..color = Color.fromRGBO(190, 150, 255, 0.28 * (1 - (t - _rearEnd) / 0.25)));
    }
    final since = t - s.impactT;
    if (cut != IntroCut.still && since >= 0 && since < 0.22) {
      canvas.drawRect(bg, Paint()..color = Color.fromRGBO(255, 250, 255, 0.4 * (1 - since / 0.22)));
    }
    // the letterbox
    final barH = H * (cut == IntroCut.full ? 0.1 : 0.07);
    final slide = math.min(((t) / 0.3).clamp(0.0, 1.0), ((len - t) / 0.35).clamp(0.0, 1.0));
    final bh = barH * Curves.easeOutCubic.transform(slide);
    final bp = Paint()..color = const Color(0xFF07060B);
    canvas.drawRect(Rect.fromLTWH(0, 0, W, bh), bp);
    canvas.drawRect(Rect.fromLTWH(0, H - bh, W, bh), bp);
  }

  // the older blast shot (an Evochi wearing something: its faces): the guardian small up on the right,
  // roaring, your Evochi in the wind in front
  void _legacyBlast(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    _woods(canvas, size, env, true);
    _rays(canvas, size, env * 0.5);
    final fi = _frame();
    final img = art.frame(fi);
    final base = math.min(H * 0.95 / art.size.height, W * 1.3 / art.size.width);
    final k = base * 0.5;
    final at = Offset(W * 0.86, H * 0.5);
    final origin = at - art.ground[0] * k;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, art.size.width, art.size.height),
        Rect.fromLTWH(origin.dx, origin.dy, art.size.width * k, art.size.height * k),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..color = Color.fromRGBO(0, 0, 0, env)
          ..colorFilter = const ColorFilter.mode(Color.fromRGBO(14, 10, 24, 0.45), BlendMode.srcATop),
      );
    }
    _rings(canvas, origin + art.mouth[fi] * k, W, env, true);
    _blastShot(canvas, size, env);
  }

  // the roar's rings, sweeping out of its mouth (toward your Evochi on the left while it braces)
  void _rings(Canvas canvas, Offset mouth, double W, double env, bool blastShot) {
    for (var i = 0; i < 4; i++) {
      final ph = ((t * 1.8 + i / 4) % 1.0);
      final r = 18 + ph * W * (blastShot ? 1.1 : 0.7);
      final a = (1 - ph) * 0.55 * env;
      final rect = Rect.fromCenter(center: mouth, width: r * 2, height: r * 1.5);
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 7 * (1 - ph)
        ..color = Color.fromRGBO(232, 222, 255, a);
      if (blastShot) {
        canvas.drawArc(rect, math.pi * 0.62, math.pi * 0.76, false, p);
      } else {
        canvas.drawOval(rect, p);
      }
    }
  }



  // ---- the blast: your Evochi in the roar
  void _blastShot(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    final ev = s.widget.evochi!;
    final u = t - _blast; // 0 .. 1.6
    // how hard the wind blows: hits, holds, eases as it holds its ground
    final gust = u < 0.15 ? u / 0.15 : (u < 1.0 ? 1.0 : math.max(0.25, 1 - (u - 1.0) / 0.6 * 0.75));
    // the roar's pressure from the right
    canvas.drawRect(
        Rect.fromLTWH(0, 0, W, H),
        Paint()
          ..shader = ui.Gradient.radial(Offset(W * 1.05, H * 0.45), W * 1.1,
              [Color.fromRGBO(170, 120, 240, 0.35 * gust * env), const Color(0x00AA78F0)]));
    // the anime burst as it lands: lines thrown out from where the roar comes
    if (u < 0.35) {
      final k = u / 0.35;
      final p = Paint()
        ..strokeCap = StrokeCap.round
        ..color = Color.fromRGBO(255, 255, 255, (1 - k) * 0.7 * env);
      final c = Offset(W * 1.02, H * 0.42);
      for (var i = 0; i < 22; i++) {
        final a = math.pi * (0.62 + 0.76 * _h(i, 12));
        final r0 = W * (0.2 + 0.4 * k + 0.2 * _h(i, 13));
        final r1 = r0 + W * (0.25 + 0.3 * _h(i, 14));
        p.strokeWidth = 2 + 4 * _h(i, 15);
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0, c + Offset(math.cos(a), math.sin(a)) * r1, p);
      }
    }
    _wind(canvas, size, gust * env, false);
    // your Evochi: shoved back, skidding, then digging in
    final face = u < 0.1 ? 'fierce' : (u < 0.38 ? 'shout' : (u < 1.12 ? 'strain' : 'fierce'));
    final slide = W * 0.1 * Curves.easeOutCubic.transform((u / 0.7).clamp(0.0, 1.0));
    double lean; // + leans back (its top pushed left, away from the wind)
    if (u < 0.1) {
      lean = 0;
    } else if (u < 0.35) {
      lean = 0.24 * Curves.easeOutBack.transform((u - 0.1) / 0.25);
    } else if (u < 0.9) {
      lean = 0.24 - 0.08 * ((u - 0.35) / 0.55);
    } else if (u < 1.15) {
      lean = 0.16 - 0.3 * Curves.easeOutBack.transform((u - 0.9) / 0.25);
    } else {
      lean = -0.14 + 0.08 * ((u - 1.15) / 0.45).clamp(0.0, 1.0);
    }
    final tremble = (u > 0.35 && u < 1.15) ? math.sin(u * 95) * 2.6 : 0.0;
    final dig = (u - 0.92).abs() < 0.14 ? 1 - (u - 0.92).abs() / 0.14 : 0.0;
    final h = math.min(H * 0.4, W * 0.7);
    final feet = Offset(W * 0.54 - slide + tremble, H * 0.8);
    _shadow(canvas, feet, h * 0.42, 0.5 * env);
    // the skid: dust streaming off its feet
    if (u > 0.1 && u < 1.3) {
      final p = Paint();
      for (var i = 0; i < 10; i++) {
        final ph = ((u * 2.4 + i / 10) % 1.0);
        final x = feet.dx + h * 0.1 - ph * W * 0.35 * (0.6 + _h(i, 16));
        final y = feet.dy - 6 - ph * 30 * _h(i, 17);
        p.color = Color.fromRGBO(200, 186, 160, (1 - ph) * 0.55 * env);
        canvas.drawCircle(Offset(x, y), 5 + 10 * ph, p);
      }
    }
    // a glow of its own colour behind it as it holds
    if (u > 0.9) {
      final a = ((u - 0.9) / 0.3).clamp(0.0, 1.0) * 0.5 * env;
      final c = feet - Offset(0, h * 0.45);
      canvas.drawCircle(c, h * 0.7, Paint()..shader = ui.Gradient.radial(c, h * 0.7, [tint.withAlpha(_a(a)), tint.withAlpha(0)]));
    }
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    canvas.transform((Matrix4.identity()..setEntry(0, 1, lean)).storage);
    canvas.scale(1 + 0.08 * dig, 1 - 0.1 * dig);
    ev.draw(canvas, face, h, Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, env));
    canvas.restore();
    // wind in front of it too: it is inside the blast, gusts curling round its body
    _swooshes(canvas, feet - Offset(0, h * 0.48), h, gust * env);
    _wind(canvas, size, gust * env * 0.6, true);
  }



  // ---- the face-off: your Evochi low on the left, the guardian up on the right
  void _faceOffShot(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    final ev = s.widget.evochi;
    final u = t - _faceOff;
    final inK = Curves.easeOutBack.transform((u / 0.5).clamp(0.0, 1.0));
    // a slash of light between them
    final sl = (u / 0.3).clamp(0.0, 1.0) * env;
    canvas.drawLine(
        Offset(-20, H * 0.98),
        Offset(W + 20, H * 0.22),
        Paint()
          ..strokeWidth = 3
          ..color = Color.fromRGBO(255, 250, 240, 0.55 * sl));
    if (ev == null) return;
    final h = math.min(H * 0.34, W * 0.6);
    final feet = Offset(-W * 0.3 + (W * 0.68) * inK, H * 0.88);
    // its colour pouring off it, speed lines behind
    final c = feet - Offset(0, h * 0.45);
    canvas.drawCircle(c, h * 0.95, Paint()..shader = ui.Gradient.radial(c, h * 0.95, [tint.withAlpha(_a(0.55 * env)), tint.withAlpha(0)]));
    final lp = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 18; i++) {
      final a = math.pi * 2 * _h(i, 40);
      final ph = (t * 1.6 + _h(i, 41)) % 1.0;
      final r0 = h * (0.5 + ph * 0.9);
      lp
        ..strokeWidth = 2 + 3 * _h(i, 42)
        ..color = Color.lerp(tint, Colors.white, 0.5)!.withAlpha(_a((1 - ph) * 0.6 * env));
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0, c + Offset(math.cos(a), math.sin(a)) * (r0 + h * 0.3), lp);
    }
    _shadow(canvas, feet, h * 0.42, 0.5 * env);
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    // it plants its feet as it lands
    final plant = (u > 0.42 && u < 0.62) ? math.sin((u - 0.42) / 0.2 * math.pi) : 0.0;
    canvas.transform((Matrix4.identity()..setEntry(0, 1, -0.08)).storage);
    canvas.scale(1 + 0.06 * plant, 1 - 0.08 * plant);
    ev.draw(canvas, 'fierce', h, Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, env));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _IntroPainter old) => true;
}

/// The scenery and effects both entrances share: the dark wood, light shafts, Hollow motes, shadows, dust,
/// shock rings and the wind.
mixin _IntroFx {
  double get t;

  // dark trunks and brambles at the edges, a mossy floor
  void _woods(Canvas canvas, Size size, double env, bool blastShot) {
    final W = size.width, H = size.height;
    final floor = H * (blastShot ? 0.78 : 0.8);
    canvas.drawRect(
        Rect.fromLTWH(0, floor, W, H - floor),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, floor), Offset(0, H), [Color.fromRGBO(34, 52, 34, env), Color.fromRGBO(18, 26, 18, env)]));
    final p = Paint()..color = Color.fromRGBO(9, 8, 14, 0.9 * env);
    for (var i = 0; i < 7; i++) {
      final left = i.isEven;
      final x = left ? W * (0.02 + 0.09 * _h(i, 1)) - 30 : W * (0.9 + 0.09 * _h(i, 1)) + 10;
      final wid = W * (0.05 + 0.06 * _h(i, 2));
      final sway = math.sin(t * 0.6 + i) * 3;
      canvas.drawPath(
          Path()
            ..moveTo(x - wid * 0.7 + sway, -10)
            ..lineTo(x + wid * 0.7 + sway, -10)
            ..lineTo(x + wid, floor + 6)
            ..lineTo(x - wid, floor + 6)
            ..close(),
          p);
    }
    // a tangle of brambles along the floor
    final bp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = Color.fromRGBO(52, 34, 70, 0.95 * env);
    for (var i = 0; i < 9; i++) {
      final x0 = W * (i / 8.0) + (_h(i, 3) - 0.5) * 40;
      final path = Path()..moveTo(x0, H);
      for (var k = 1; k <= 4; k++) {
        path.quadraticBezierTo(x0 + (k.isEven ? 30 : -30), H - k * 22 + 10, x0 + (_h(i, k) - 0.5) * 50, H - k * 24);
      }
      canvas.drawPath(path, bp);
    }
  }

  void _rays(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    for (var i = 0; i < 3; i++) {
      final x = W * (0.12 + 0.22 * i) + math.sin(t * 0.5 + i) * 12;
      final a = (0.05 + 0.03 * math.sin(t * 1.3 + i * 2)) * env;
      canvas.drawPath(
          Path()
            ..moveTo(x, -10)
            ..lineTo(x + W * 0.1, -10)
            ..lineTo(x + W * 0.45, H * 0.85)
            ..lineTo(x + W * 0.18, H * 0.85)
            ..close(),
          Paint()
            ..shader = ui.Gradient.linear(Offset(x, 0), Offset(x + W * 0.3, H * 0.85),
                [Color.fromRGBO(226, 214, 255, a), const Color.fromRGBO(226, 214, 255, 0)]));
    }
  }

  // Hollow motes rising
  void _motes(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    final p = Paint();
    for (var i = 0; i < 34; i++) {
      final sp = 0.05 + 0.08 * _h(i, 5);
      final y = H - ((t * sp + _h(i, 6)) % 1.0) * H * 1.1;
      final x = W * _h(i, 7) + math.sin(t * 1.5 + i) * 10;
      final tw = 0.5 + 0.5 * math.sin(t * 4 + i * 1.7);
      p.color = Color.fromRGBO(196, 160, 255, (0.25 + 0.5 * tw) * env);
      canvas.drawCircle(Offset(x, y), 1.2 + 2.2 * _h(i, 8), p);
    }
  }

  void _shadow(Canvas canvas, Offset at, double r, double a) {
    canvas.drawOval(Rect.fromCenter(center: at, width: r * 2, height: r * 0.42),
        Paint()..shader = ui.Gradient.radial(at, r, [Color.fromRGBO(0, 0, 0, a), const Color(0x00000000)]));
  }

  void _dust(Canvas canvas, Offset at, double since, double spread, double env, int n, Offset drift) {
    final k = (since / 0.9).clamp(0.0, 1.0);
    final p = Paint();
    for (var i = 0; i < n; i++) {
      final dir = (i / n - 0.5) * 2;
      final x = at.dx + dir * spread * Curves.easeOutCubic.transform(k) * (0.5 + _h(i, 9));
      final y = at.dy - (20 + 50 * _h(i, 10)) * math.sin(k * math.pi * 0.8) + drift.dy * k * 20;
      p.color = Color.fromRGBO(196, 182, 160, (1 - k) * 0.6 * env);
      canvas.drawCircle(Offset(x, y), (6 + 14 * _h(i, 11)) * (0.6 + k), p);
    }
  }

  void _shock(Canvas canvas, Offset at, double since, double W, double env) {
    final k = (since / 0.7).clamp(0.0, 1.0);
    final r = W * 0.08 + W * 0.75 * Curves.easeOutCubic.transform(k);
    canvas.drawOval(
        Rect.fromCenter(center: at, width: r * 2, height: r * 0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 * (1 - k) + 1
          ..color = Color.fromRGBO(240, 232, 214, (1 - k) * 0.8 * env));
  }

  // anime gusts: bright curved strokes that wrap round it and tear off to the left
  void _swooshes(Canvas canvas, Offset c, double h, double a) {
    if (a <= 0.01) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 5; i++) {
      final ph = (t * 1.7 + i / 5) % 1.0;
      final rx = h * (0.55 + 0.25 * _h(i, 60));
      final ry = h * (0.3 + 0.25 * _h(i, 61));
      final cy = c.dy + (i - 2) * h * 0.12;
      final rect = Rect.fromCenter(center: Offset(c.dx - ph * h * 0.6, cy), width: rx * 2, height: ry * 2);
      p
        ..strokeWidth = 3 + 4 * (1 - ph)
        ..color = Color.fromRGBO(255, 255, 255, (1 - ph) * (ph * 4).clamp(0.0, 1.0) * 0.75 * a);
      // from the top right, over the top, down the back (the wind's side is the right)
      canvas.drawArc(rect, -math.pi * 0.15, -math.pi * (0.55 + 0.25 * _h(i, 62)), false, p);
    }
  }

  void _wind(Canvas canvas, Size size, double a, bool front) {
    if (a <= 0.01) return;
    final W = size.width, H = size.height;
    final p = Paint()..strokeCap = StrokeCap.round;
    final n = front ? 14 : 34;
    final seed = front ? 50 : 0;
    for (var i = 0; i < n; i++) {
      final j = i + seed;
      final speed = W * (2.4 + 2.2 * _h(j, 20));
      final len = W * (0.12 + 0.3 * _h(j, 21));
      final x = W + len - ((t * speed + _h(j, 22) * W * 2) % (W * 2 + len * 2));
      final y = H * (0.14 + 0.72 * _h(j, 23)) + math.sin(t * 6 + j) * 6;
      p
        ..strokeWidth = (front ? 2.5 : 1.4) + 3.5 * _h(j, 24)
        ..shader = ui.Gradient.linear(Offset(x, y), Offset(x + len, y), [
          Color.fromRGBO(255, 255, 255, (0.55 + 0.4 * _h(j, 25)) * a),
          const Color.fromRGBO(220, 205, 255, 0),
        ]);
      canvas.drawLine(Offset(x, y), Offset(x + len, y), p);
    }
    if (front) return;
    // leaves and Hollow sparks torn along with it
    final lp = Paint();
    for (var i = 0; i < 16; i++) {
      final speed = W * (1.4 + 1.2 * _h(i, 30));
      final x = W + 20 - ((t * speed + _h(i, 31) * W * 2) % (W * 2 + 40));
      final y = H * (0.2 + 0.65 * _h(i, 32)) + math.sin(t * 5 + i * 2) * 22;
      final spark = i % 4 == 0;
      lp.color = spark
          ? Color.fromRGBO(206, 176, 255, 0.9 * a)
          : (i.isEven ? Color.fromRGBO(110, 160, 72, 0.9 * a) : Color.fromRGBO(170, 120, 70, 0.9 * a));
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(t * (6 + 6 * _h(i, 33)) + i);
      if (spark) {
        canvas.drawCircle(Offset.zero, 3, lp);
      } else {
        canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: 14, height: 6), lp);
      }
      canvas.restore();
    }
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.name, required this.title, required this.width, this.sigil = false, this.emblem});
  final String name, title;
  final double width;

  /// the Briarback's antler sigil over the name
  final bool sigil;

  /// another guardian's sigil over the name (the Hollow Sprout's)
  final CustomPainter? emblem;

  @override
  Widget build(BuildContext context) {
    final big = math.min(width * 0.12, 58.0);
    final style = TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: big, letterSpacing: big * 0.12, height: 1.0);
    return Stack(alignment: Alignment.center, children: [
      // a band of dusk behind it, so it reads over anything
      const Positioned.fill(
        child: DecoratedBox(
          decoration: BoxDecoration(gradient: RadialGradient(radius: 0.75, colors: [Color(0x9914091F), Color(0x0014091F)])),
        ),
      ),
      Column(mainAxisSize: MainAxisSize.min, children: [
        // the guardian's sigil: its antlers round a Hollow crystal
        if (sigil || emblem != null) ...[CustomPaint(size: Size(big * 1.9, big * 0.95), painter: emblem ?? _EmblemPainter()), const SizedBox(height: 2)],
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Stack(children: [
            Text(name.toUpperCase(),
                style: style.copyWith(
                    foreground: Paint()
                      ..style = PaintingStyle.stroke
                      ..strokeWidth = big * 0.15
                      ..color = const Color(0xFF1A1024))),
            Text(name.toUpperCase(),
                style: style.copyWith(color: const Color(0xFFF6F0FF), shadows: const [
                  Shadow(color: Color(0xCC9A6BFF), blurRadius: 18),
                  Shadow(color: Color(0x889A6BFF), blurRadius: 36),
                ])),
          ]),
        ),
        const SizedBox(height: 7),
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (width >= 340) ...[_arrow(false), const SizedBox(width: 8)],
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(title.toUpperCase(),
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: EvochiText.game,
                      fontWeight: FontWeight.w800,
                      fontSize: math.min(14.0, width * 0.04),
                      letterSpacing: width < 360 ? 1.4 : 3.2,
                      color: const Color(0xFFDCCBFF),
                      shadows: const [Shadow(color: Color(0xFF120A1C), blurRadius: 6), Shadow(color: Color(0x669A6BFF), blurRadius: 12)])),
            ),
          ),
          if (width >= 340) ...[const SizedBox(width: 8), _arrow(true)],
        ]),
      ]),
    ]);
  }

  Widget _arrow(bool flip) => Transform.flip(
        flipX: flip,
        child: CustomPaint(size: const Size(52, 14), painter: _ArrowPainter()),
      );
}

/// An arrow of bramble pointing in at the title: fletched at the far end, two thorns along it.
class _ArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFFC4A8F0)
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final y = size.height / 2;
    final w = size.width;
    canvas.drawLine(Offset(2, y), Offset(w - 3, y), p);
    // the head, pointing in
    canvas.drawPath(
        Path()
          ..moveTo(w - 9, y - 4.5)
          ..lineTo(w - 1, y)
          ..lineTo(w - 9, y + 4.5),
        p);
    // the fletching
    for (final x in [2.0, 7.0]) {
      canvas.drawLine(Offset(x, y), Offset(x - 3, y - 5), p);
      canvas.drawLine(Offset(x, y), Offset(x - 3, y + 5), p);
    }
    // thorns
    for (final x in [w * 0.42, w * 0.62]) {
      canvas.drawLine(Offset(x, y), Offset(x + 4, y - 4), p);
    }
    canvas.drawCircle(Offset(w * 0.52, y), 1.8, Paint()..color = const Color(0xFFE8DAFF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

/// The Briarback's sigil over its name: two antlers of bramble rising round a Hollow crystal, glowing.
class _EmblemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w / 2, h * 0.62);
    final glow = Paint()..shader = ui.Gradient.radial(c, w * 0.42, [const Color(0x889A6BFF), const Color(0x009A6BFF)]);
    canvas.drawCircle(c, w * 0.42, glow);
    final line = Paint()
      ..color = const Color(0xFFD9C6FF)
      ..strokeWidth = math.max(1.6, w * 0.022)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final s in [-1.0, 1.0]) {
      // a main beam curving up and out, two tines off it
      final beam = Path()
        ..moveTo(c.dx + s * w * 0.06, c.dy + h * 0.12)
        ..quadraticBezierTo(c.dx + s * w * 0.3, c.dy, c.dx + s * w * 0.36, c.dy - h * 0.5);
      canvas.drawPath(beam, line);
      canvas.drawLine(Offset(c.dx + s * w * 0.22, c.dy - h * 0.06), Offset(c.dx + s * w * 0.18, c.dy - h * 0.38), line);
      canvas.drawLine(Offset(c.dx + s * w * 0.31, c.dy - h * 0.28), Offset(c.dx + s * w * 0.46, c.dy - h * 0.42), line);
      // crystal tips
      for (final tip in [Offset(c.dx + s * w * 0.36, c.dy - h * 0.5), Offset(c.dx + s * w * 0.18, c.dy - h * 0.38), Offset(c.dx + s * w * 0.46, c.dy - h * 0.42)]) {
        canvas.drawCircle(tip, w * 0.03, Paint()..shader = ui.Gradient.radial(tip, w * 0.05, [const Color(0xFFFFFFFF), const Color(0x00C4A0FF)]));
      }
      // thorns along the beam
      canvas.drawLine(Offset(c.dx + s * w * 0.27, c.dy - h * 0.16), Offset(c.dx + s * w * 0.32, c.dy - h * 0.1), line);
    }
    // the crystal: a tall diamond
    final gem = Path()
      ..moveTo(c.dx, c.dy - h * 0.42)
      ..lineTo(c.dx + w * 0.07, c.dy - h * 0.05)
      ..lineTo(c.dx, c.dy + h * 0.22)
      ..lineTo(c.dx - w * 0.07, c.dy - h * 0.05)
      ..close();
    canvas.drawPath(gem, Paint()..shader = ui.Gradient.linear(Offset(c.dx, c.dy - h * 0.42), Offset(c.dx, c.dy + h * 0.22), [const Color(0xFFFFFFFF), const Color(0xFFB48CFF)]));
    canvas.drawPath(gem, line..strokeWidth = math.max(1.2, w * 0.014));
    canvas.drawLine(Offset(c.dx, c.dy - h * 0.42), Offset(c.dx, c.dy + h * 0.22), Paint()..color = const Color(0x66FFFFFF)..strokeWidth = 1);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _NameTag extends StatelessWidget {
  const _NameTag({required this.name, required this.tint});
  final String name;
  final Color tint;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(12, 6, 14, 6),
        decoration: BoxDecoration(
          color: const Color(0xCC120E1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tint, width: 2),
          boxShadow: [BoxShadow(color: tint.withAlpha(115), blurRadius: 14)],
        ),
        child: Text(name.toUpperCase(),
            style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 18, letterSpacing: 2, color: Color(0xFFFFF8EC))),
      );
}

/// A colour to glow with for each Evochi colour.
Color cineTint(String palette) => switch (palette) {
      'forest' => const Color(0xFF7BD15A),
      'coral' => const Color(0xFFFF8A70),
      'ocean' => const Color(0xFF4FB5F0),
      'amethyst' => const Color(0xFFB98BF0),
      'obsidian' => const Color(0xFFCFD8EE),
      _ => const Color(0xFFFFC145),
    };
