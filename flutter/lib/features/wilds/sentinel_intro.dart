// The Forgotten Sentinel's entrance (the Sentinel's Gate, F5): a short cinematic before the fight.
//
//   1. Letterbox. Low down, looking up at the gate: the Sentinel slumped against it, asleep. Its eyes
//      ignite; it heaves itself up, stone grinding, dust pouring off it.
//   2. It throws its fists up and roars: a boom of violet light out of its chest rune, rings of it,
//      the screen shaking.
//   3. It leans in. Light gathers in its eyes, and it fires: a beam straight at you.
//   4. Cut to your Evochi, braced. The beam comes down; it leaps clear (a heroic arc, time slowing at
//      the top) as the beam smashes the ground where it stood and rakes after it, and it lands, fierce.
//   5. Back on the Sentinel, lower and closer, looming over you, a ring of runes turning behind it: the
//      title card slams in.
//
// The Sentinel is a pre-rendered sequence (tools/art/sentinel_intro.py); your Evochi is the same heroic
// cut-out as the Briarback's entrance (tools/art/cine_evochi.py). The beam, light, runes and wind are
// drawn here. Tap to skip. The full version plays the first time; after that a short one (the looming
// shot and the title); with reduced motion, a still title card.

part of 'boss_intro.dart';

// the full cut's timeline (seconds)
const _sOpen = 0.35; // letterbox in; the frames start (asleep, then waking at 9 fps)
const _sRoar = 1.68; // frames 12.. at 12 fps: fists up; the roar holds
const _sCharge = 2.9; // frames 20..25: it leans in, its eyes gathering light
const _sFire = 3.4; // the beam
const _sDodge = 3.7; // cut to your Evochi
const _sMenace = 5.1; // back to the Sentinel, looming: frames 26.. at 9 fps
const _sTitle = 5.35;
const _sFullLen = 7.4;
const _sShortLen = 2.3;
const _sStillLen = 2.4;

class SentinelIntro extends StatefulWidget {
  const SentinelIntro({
    super.key,
    required this.art,
    required this.evochi,
    required this.cut,
    required this.petName,
    required this.tint,
    required this.onCue,
    required this.onDone,
  });
  final BossIntroArt art;
  final CineEvochiArt? evochi;
  final IntroCut cut;
  final String petName;
  final Color tint;
  final void Function(String cue) onCue;
  final VoidCallback onDone;

  @override
  State<SentinelIntro> createState() => _SentinelIntroState();
}

class _SentinelIntroState extends State<SentinelIntro> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  bool _done = false;
  final _fired = <String>{};

  double get _len => switch (widget.cut) { IntroCut.full => _sFullLen, IntroCut.short => _sShortLen, IntroCut.still => _sStillLen };

  /// when the title slams in
  double get titleT => switch (widget.cut) { IntroCut.full => _sTitle, IntroCut.short => 0.25, IntroCut.still => 0.0 };

  int get _lit => (widget.art.meta['lit'] as num?)?.toInt() ?? 4;
  int get _roarF => (widget.art.meta['roar'] as num?)?.toInt() ?? 12;
  int get _beamF => (widget.art.meta['beam'] as num?)?.toInt() ?? 20;
  int get _menaceF => widget.art.impact;

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

  void _prefetch(double t) {
    final idx = <int>{};
    for (var d = 0.0; d <= 0.5; d += 1 / 12) {
      idx.add(frameAt(t + d));
    }
    final roar = widget.cut == IntroCut.full && t > _sRoar - 0.4 && t < _sCharge;
    widget.art.want(idx, keep: roar ? [for (var i = _roarF + 3; i < _beamF; i++) i] : const []);
  }

  /// The Sentinel's frame at [t].
  int frameAt(double t) {
    final n = widget.art.count;
    switch (widget.cut) {
      case IntroCut.still:
        return n - 1;
      case IntroCut.short:
        return (_menaceF + (t.clamp(0.0, 9.0) * 9).floor()).clamp(0, n - 1);
      case IntroCut.full:
        if (t < _sRoar) return ((t - _sOpen).clamp(0.0, 9.0) * 9).floor().clamp(0, _roarF - 1);
        if (t < _sCharge) {
          final k = ((t - _sRoar) * 12).floor();
          if (k < _beamF - _roarF) return _roarF + k;
          // the roar held: back and forth through its last frames
          final seq = [for (var i = _beamF - 1; i >= _roarF + 3; i--) i, for (var i = _roarF + 4; i < _beamF - 1; i++) i];
          return seq[(k - (_beamF - _roarF)) % seq.length];
        }
        if (t < _sMenace) return (_beamF + ((t - _sCharge) * 12).floor()).clamp(_beamF, _menaceF - 1);
        return (_menaceF + ((t - _sMenace) * 9).floor()).clamp(_menaceF, n - 1);
    }
  }

  void _cue(String id, double at) {
    if (_t >= at && _fired.add(id)) widget.onCue(id);
  }

  void _cues() {
    switch (widget.cut) {
      case IntroCut.full:
        _cue('open', 0);
        _cue('ignite', _sOpen + _lit / 9);
        _cue('rise', _sOpen + 0.85);
        _cue('roar', _sRoar + 0.18);
        _cue('charge', _sCharge);
        _cue('beam', _sFire);
        _cue('leap', _sDodge + 0.12);
        _cue('blast', _sDodge + 0.2);
        _cue('land', _sDodge + 0.95);
        _cue('title', titleT);
      case IntroCut.short:
        _cue('title', titleT);
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

  Offset _shake(double t) {
    if (widget.cut == IntroCut.still) return Offset.zero;
    var s = 0.0;
    final since = t - titleT;
    if (since >= 0 && since < 0.6) s = math.max(s, 14 * math.pow(1 - since / 0.6, 2).toDouble());
    if (widget.cut == IntroCut.full) {
      if (t > _sOpen + 0.7 && t < _sRoar) s = math.max(s, 2.5); // stone grinding as it rises
      if (t > _sRoar + 0.15 && t < _sCharge) s = math.max(s, 6 * (1 - ((t - _sRoar - 0.15) / 1.2).clamp(0.0, 0.7)));
      if (t > _sFire && t < _sDodge) s = math.max(s, 7);
      final b = t - _sDodge - 0.2;
      if (b > 0 && b < 0.5) s = math.max(s, 13 * (1 - b / 0.5));
    }
    if (s == 0) return Offset.zero;
    return Offset(math.sin(t * 97) * s, math.cos(t * 83) * s * 0.7);
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    final since = t - titleT;
    final titleOn = widget.cut == IntroCut.still || since >= 0;
    final pop = widget.cut == IntroCut.still ? 1.0 : Curves.easeOutBack.transform((since / 0.22).clamp(0.0, 1.0));
    final fadeOut = ((_len - t) / 0.45).clamp(0.0, 1.0);
    final shake = _shake(t);
    return Semantics(
      label: 'The Forgotten Sentinel, Guardian of the Gate. Tap to skip.',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: LayoutBuilder(builder: (ctx, b) {
          final size = Size(b.maxWidth, b.maxHeight);
          final bar = size.height * (widget.cut == IntroCut.full ? 0.1 : 0.07);
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _SentinelPainter(this, t, shake))),
            if (titleOn)
              Positioned(
                left: 12,
                right: 12,
                top: bar + 14 + shake.dy,
                child: Opacity(
                  opacity: (pop.clamp(0.0, 1.0) * fadeOut).toDouble(),
                  child: Transform.scale(
                      scale: 1 + (1 - pop) * 0.9,
                      child: _Title(name: 'The Forgotten Sentinel', title: 'Guardian of the Gate', width: size.width)),
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
}

class _SentinelPainter extends CustomPainter with _IntroFx {
  _SentinelPainter(this.s, this.t, this.shake);
  final _SentinelIntroState s;
  @override
  final double t;
  final Offset shake;

  BossIntroArt get art => s.widget.art;
  IntroCut get cut => s.widget.cut;
  Color get tint => s.widget.tint;
  double get len => s._len;

  static const _violet = Color(0xFFB48CFF);

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    final env = math.min((t / _sOpen).clamp(0.0, 1.0), ((len - t) / 0.45).clamp(0.0, 1.0));
    final bg = Rect.fromLTWH(0, 0, W, H);
    canvas.drawRect(
        bg,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, H), [
            Color.fromRGBO(14, 10, 26, env),
            Color.fromRGBO(30, 22, 46, env),
            Color.fromRGBO(20, 26, 30, env),
          ], [0, 0.6, 1]));
    canvas.save();
    canvas.translate(shake.dx, shake.dy);
    final dodge = cut == IntroCut.full && t >= _sDodge && t < _sMenace;
    _woods(canvas, size, env, dodge);
    _rays(canvas, size, env * 0.6);
    _motes(canvas, size, env);
    if (dodge) {
      _dodgeShot(canvas, size, env);
    } else {
      _sentinelShot(canvas, size, env);
    }
    canvas.restore();
    // the flash as the title slams in, and as the beam fires
    final since = t - s.titleT;
    if (cut != IntroCut.still && since >= 0 && since < 0.22) {
      canvas.drawRect(bg, Paint()..color = Color.fromRGBO(245, 235, 255, 0.55 * (1 - since / 0.22)));
    }
    if (cut == IntroCut.full) {
      final f = t - _sFire;
      if (f >= 0 && f < 0.18) canvas.drawRect(bg, Paint()..color = Color.fromRGBO(225, 205, 255, 0.6 * (1 - f / 0.18)));
    }
    // the letterbox
    final barH = H * (cut == IntroCut.full ? 0.1 : 0.07);
    final slide = math.min((t / 0.3).clamp(0.0, 1.0), ((len - t) / 0.35).clamp(0.0, 1.0));
    final bh = barH * Curves.easeOutCubic.transform(slide);
    final bp = Paint()..color = const Color(0xFF07060B);
    canvas.drawRect(Rect.fromLTWH(0, 0, W, bh), bp);
    canvas.drawRect(Rect.fromLTWH(0, H - bh, W, bh), bp);
  }

  // ---- the Sentinel: the frames fill the screen's height (wider screens see more of the gate's dark)
  void _sentinelShot(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    final fi = s.frameAt(t);
    final img = art.frame(fi);
    final menace = fi >= s._menaceF;
    // a slow push in, about the ground under it
    final push = menace
        ? 1.0 + 0.08 * _ease(cut == IntroCut.full ? (t - _sMenace) / (len - _sMenace) : t / len)
        : 1.0 + 0.06 * _ease((t - _sOpen) / (_sDodge - _sOpen));
    final k = math.max(H / art.size.height, W / art.size.width) * push;
    final g = art.ground[fi];
    final at = Offset(W * 0.5, H - (art.size.height - g.dy) * k);
    final origin = at - g * k;
    Offset toScreen(Offset p) => origin + p * k;
    // behind it: the gate's Hollow light, and (looming) a ring of runes turning
    final chest = toScreen((art.meta['chest'] as List?) == null ? art.mouth[fi] : _pt((art.meta['chest'] as List)[fi]));
    final eyes = toScreen(art.mouth[fi]);
    final lit = fi >= s._lit;
    canvas.drawCircle(
        chest,
        W * 0.9,
        Paint()
          ..shader = ui.Gradient.radial(chest, W * 0.9, [
            Color.fromRGBO(150, 100, 230, (lit ? 0.32 : 0.12) * env),
            const Color.fromRGBO(150, 100, 230, 0),
          ]));
    if (menace || cut == IntroCut.still) _runeRing(canvas, eyes + Offset(0, W * 0.12), W * 0.62, env);
    _shadow(canvas, at, art.size.width * k * 0.3, 0.6 * env);
    if (img != null) {
      canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, art.size.width, art.size.height),
          Rect.fromLTWH(origin.dx, origin.dy, art.size.width * k, art.size.height * k),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(0, 0, 0, env));
    }
    if (cut == IntroCut.full && !menace) {
      // its eyes ignite
      final ig = t - (_sOpen + s._lit / 9);
      if (ig >= 0 && ig < 0.6) _flare(canvas, eyes, W * 0.25 * (1 - ig / 0.6) + 8, (1 - ig / 0.6) * env);
      // dust pouring off it as it rises
      if (t > _sOpen + 0.6 && t < _sRoar + 0.4) {
        for (final f in art.hooves[fi]) {
          _dust(canvas, toScreen(f), ((t - _sOpen - 0.6) % 0.9), W * 0.14, env * 0.8, 6, const Offset(0, 6));
        }
      }
      // the roar: a boom of light out of its chest rune
      if (t >= _sRoar + 0.18 && t < _sCharge) _boom(canvas, chest, W, t - _sRoar - 0.18, env);
      // its eyes gather the beam
      if (t >= _sCharge && t < _sFire) _gather(canvas, eyes, W, (t - _sCharge) / (_sFire - _sCharge), env);
      // and fire: straight at you (down and to the left, past the camera)
      if (t >= _sFire) _beamOut(canvas, eyes, size, t - _sFire, env);
    }
    if (menace || cut == IntroCut.still) {
      // looming: its eyes burn, the Hollow mist rises round it
      final flick = 0.85 + 0.15 * math.sin(t * 11);
      _flare(canvas, eyes, W * 0.07 * flick, 0.7 * env);
      final since = t - s.titleT;
      if (since >= 0 && since < 0.5) _flare(canvas, eyes, W * 0.3 * (1 - since / 0.5) + 10, (1 - since / 0.5) * env);
      _mist(canvas, size, env);
    }
    // a low fog over its base
    canvas.drawRect(
        Rect.fromLTWH(-20, H * 0.74, W + 40, H * 0.3),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, H * 0.74), Offset(0, H), [
            const Color(0x0016121F),
            Color.fromRGBO(20, 16, 32, 0.8 * env),
          ]));
  }

  /// A flare of light (its eyes): a soft halo and a cross of light through it.
  void _flare(Canvas canvas, Offset c, double r, double a) {
    if (a <= 0.01 || r <= 0) return;
    canvas.drawCircle(c, r, Paint()..shader = ui.Gradient.radial(c, r, [Color.fromRGBO(250, 244, 255, 0.9 * a), Color.fromRGBO(190, 150, 255, 0.4 * a), const Color(0x00B48CFF)], [0, 0.35, 1]));
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.5
      ..shader = ui.Gradient.linear(c - Offset(r * 1.6, 0), c + Offset(r * 1.6, 0),
          [const Color(0x00FFFFFF), Color.fromRGBO(255, 250, 255, 0.85 * a), const Color(0x00FFFFFF)], [0, 0.5, 1]);
    canvas.drawLine(c - Offset(r * 1.6, 0), c + Offset(r * 1.6, 0), p);
  }

  /// The roar: rings of violet light out of its chest, and a burst of lines.
  void _boom(Canvas canvas, Offset c, double W, double u, double env) {
    for (var i = 0; i < 4; i++) {
      final ph = ((u * 1.5 + i / 4) % 1.0);
      final r = 30 + ph * W * 0.95;
      final p = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 + 9 * (1 - ph)
        ..color = Color.fromRGBO(210, 180, 255, (1 - ph) * 0.6 * env);
      canvas.drawOval(Rect.fromCenter(center: c, width: r * 2, height: r * 1.4), p);
    }
    if (u < 0.4) {
      final k = u / 0.4;
      final p = Paint()
        ..strokeCap = StrokeCap.round
        ..color = Color.fromRGBO(255, 250, 255, (1 - k) * 0.75 * env);
      for (var i = 0; i < 26; i++) {
        final a = math.pi * 2 * _h(i, 70);
        final r0 = W * (0.12 + 0.35 * k + 0.1 * _h(i, 71));
        final r1 = r0 + W * (0.15 + 0.25 * _h(i, 72));
        p.strokeWidth = 2 + 4 * _h(i, 73);
        canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0, c + Offset(math.cos(a), math.sin(a)) * r1, p);
      }
    }
  }

  /// Light gathering into its eyes: motes streaming in, a ball of it growing.
  void _gather(Canvas canvas, Offset c, double W, double k, double env) {
    final p = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 22; i++) {
      final a = math.pi * 2 * _h(i, 80);
      final ph = (k * 2.2 + _h(i, 81)) % 1.0;
      final r = W * 0.5 * (1 - ph);
      final o = c + Offset(math.cos(a), math.sin(a)) * r;
      p
        ..strokeWidth = 2 + 2 * _h(i, 82)
        ..color = Color.fromRGBO(220, 200, 255, ph * 0.8 * env);
      canvas.drawLine(o, o + (c - o) * 0.18, p);
    }
    _flare(canvas, c, W * (0.04 + 0.12 * k), (0.5 + 0.5 * k) * env);
  }

  /// The beam fired at you: out of its eyes, down past the camera's left.
  void _beamOut(Canvas canvas, Offset eyes, Size size, double u, double env) {
    final W = size.width, H = size.height;
    final grow = Curves.easeOutCubic.transform((u / 0.12).clamp(0.0, 1.0));
    final end = Offset.lerp(eyes, Offset(-W * 0.35, H * 1.25), grow)!;
    _beam(canvas, eyes, end, W * 0.05, W * 0.42, env);
    _flare(canvas, eyes, W * 0.16, env);
  }

  /// A beam from [a] to [b]: narrow at its source, wide where it comes at you; a violet glow round a
  /// white-hot core, flickering.
  void _beam(Canvas canvas, Offset a, Offset b, double w0, double w1, double env) {
    final d = b - a;
    final len = math.max(d.distance, 1e-6);
    final n = Offset(-d.dy / len, d.dx / len);
    final flick = 0.85 + 0.15 * math.sin(t * 47);
    for (final (scale, col) in [
      (1.0, Color.fromRGBO(150, 90, 240, 0.35 * env * flick)),
      (0.62, Color.fromRGBO(196, 156, 255, 0.6 * env * flick)),
      (0.28, Color.fromRGBO(255, 250, 255, 0.95 * env)),
    ]) {
      final path = Path()
        ..moveTo(a.dx + n.dx * w0 * scale, a.dy + n.dy * w0 * scale)
        ..lineTo(b.dx + n.dx * w1 * scale, b.dy + n.dy * w1 * scale)
        ..lineTo(b.dx - n.dx * w1 * scale, b.dy - n.dy * w1 * scale)
        ..lineTo(a.dx - n.dx * w0 * scale, a.dy - n.dy * w0 * scale)
        ..close();
      canvas.drawPath(path, Paint()..color = col);
    }
    // sparks streaming along it
    final p = Paint()..strokeCap = StrokeCap.round;
    for (var i = 0; i < 16; i++) {
      final ph = (t * 3 + _h(i, 90)) % 1.0;
      final o = a + d * ph + n * ((_h(i, 91) - 0.5) * 2 * (w0 + (w1 - w0) * ph) * 1.2);
      p
        ..strokeWidth = 2 + 2 * _h(i, 92)
        ..color = Color.fromRGBO(240, 228, 255, (1 - ph) * 0.8 * env);
      canvas.drawLine(o, o + d / len * 18, p);
    }
  }

  /// A ring of runes turning slowly behind it as it looms.
  void _runeRing(Canvas canvas, Offset c, double r, double env) {
    final a = 0.32 * env;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(1, 0.92);
    canvas.rotate(t * 0.25);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2
      ..color = _violet.withAlpha(_a(a));
    canvas.drawCircle(Offset.zero, r, p);
    canvas.drawCircle(Offset.zero, r * 0.86, p..strokeWidth = 1.4);
    for (var i = 0; i < 16; i++) {
      final ang = i * math.pi * 2 / 16;
      final o = Offset(math.cos(ang), math.sin(ang)) * r * 0.93;
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(ang);
      final g = Path();
      switch (i % 4) {
        case 0:
          g
            ..moveTo(-5, -6)
            ..lineTo(0, 6)
            ..lineTo(5, -6);
        case 1:
          g
            ..moveTo(-6, 0)
            ..lineTo(6, 0)
            ..moveTo(0, -6)
            ..lineTo(0, 6);
        case 2:
          g.addOval(Rect.fromCircle(center: Offset.zero, radius: 4));
        default:
          g
            ..moveTo(-5, 6)
            ..lineTo(-5, -6)
            ..lineTo(5, -6);
      }
      canvas.drawPath(g, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFFD9C2FF).withAlpha(_a(a * 1.4)));
      canvas.restore();
    }
    canvas.restore();
  }

  /// The Hollow mist rising round it.
  void _mist(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    final p = Paint();
    for (var i = 0; i < 14; i++) {
      final ph = (t * 0.18 + _h(i, 100)) % 1.0;
      final x = W * _h(i, 101) + math.sin(t * 0.7 + i) * 20;
      final y = H * (1.0 - 0.45 * ph);
      final r = W * (0.12 + 0.12 * _h(i, 102));
      p.shader = ui.Gradient.radial(Offset(x, y), r, [Color.fromRGBO(120, 80, 190, 0.22 * (1 - ph) * env), const Color(0x00785ABE)]);
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  // ---- the dodge: your Evochi braced; the beam comes down; it leaps clear as the ground explodes
  void _dodgeShot(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    final ev = s.widget.evochi;
    final u = t - _sDodge; // 0 .. 1.4
    final h = math.min(H * 0.34, W * 0.62);
    final from = Offset(W * 0.64, H * 0.8), to = Offset(W * 0.32, H * 0.8);
    // the beam's light floods in from the upper right before it lands
    canvas.drawRect(
        Rect.fromLTWH(0, 0, W, H),
        Paint()
          ..shader = ui.Gradient.radial(Offset(W * 1.1, -H * 0.05), W * 1.4, [
            Color.fromRGBO(170, 120, 255, (u < 1.1 ? 0.45 : math.max(0.0, 0.45 - (u - 1.1) * 1.5)) * env),
            const Color(0x00AA78FF),
          ]));
    // the leap: up and over to the left, hanging at the top as time slows, then down
    double k;
    if (u < 0.12) {
      k = 0;
    } else if (u < 0.42) {
      k = 0.5 * Curves.easeOutCubic.transform((u - 0.12) / 0.3);
    } else if (u < 0.75) {
      k = 0.5 + 0.12 * (u - 0.42) / 0.33;
    } else if (u < 0.95) {
      k = 0.62 + 0.38 * Curves.easeInCubic.transform((u - 0.75) / 0.2);
    } else {
      k = 1;
    }
    Offset feetAt(double k) => Offset.lerp(from, to, k)! - Offset(0, h * 0.95 * math.sin(math.pi * k));
    final feet = feetAt(k);
    // where the beam strikes: where it stood, then raking after it, always a step behind
    final strike = u < 0.2 ? from : Offset.lerp(from, Offset(W * 0.44, H * 0.82), Curves.easeInOut.transform(((u - 0.2) / 0.85).clamp(0.0, 1.0)))!;
    // the scorch it leaves on the ground
    if (u > 0.2) {
      final glow = (1 - ((u - 1.05) / 0.4).clamp(0.0, 1.0));
      canvas.drawLine(
          from,
          strike,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = W * 0.07
            ..color = Color.fromRGBO(30, 20, 36, 0.8 * env));
      canvas.drawLine(
          from,
          strike,
          Paint()
            ..strokeCap = StrokeCap.round
            ..strokeWidth = W * 0.03
            ..color = Color.fromRGBO(220, 170, 255, 0.8 * glow * env));
    }
    _shadow(canvas, Offset(feet.dx, H * 0.8), h * 0.42 * (1 - 0.4 * math.sin(math.pi * k)), 0.5 * env);
    // the beam itself (from off the top right), while it burns
    if (u >= 0.12 && u < 1.1) {
      final on = u < 0.2 ? (u - 0.12) / 0.08 : (u > 0.95 ? (1.1 - u) / 0.15 : 1.0);
      _beam(canvas, Offset(W * 1.2, -H * 0.15), strike, W * 0.16, W * 0.09, env * on.clamp(0.0, 1.0));
    }
    // the ground bursting where it hits
    final b = u - 0.2;
    if (b >= 0 && b < 1.0) {
      _shock(canvas, from, b, W, env);
      _dust(canvas, from, b, W * 0.5, env, 16, const Offset(0, 1));
      // chunks of earth thrown up
      final cp = Paint();
      for (var i = 0; i < 12; i++) {
        final a = -math.pi * (0.15 + 0.7 * _h(i, 110));
        final v = W * (0.6 + 0.6 * _h(i, 111));
        final x = from.dx + math.cos(a) * v * b;
        final y = from.dy + math.sin(a) * v * b + 900 * b * b;
        cp.color = (i.isEven ? const Color(0xFF4A3B30) : const Color(0xFF6E4FA3)).withAlpha(_a((1 - b) * env));
        canvas.drawRect(Rect.fromCenter(center: Offset(x, y), width: 7 + 6 * _h(i, 112), height: 6 + 5 * _h(i, 113)), cp);
      }
    }
    if (ev == null) return;
    final air = u >= 0.12 && u < 0.95;
    final face = air ? 'shout' : 'fierce';
    // afterimages along the arc, in its own colour
    if (air) {
      for (var i = 4; i >= 1; i--) {
        final kk = (k - i * 0.05).clamp(0.0, 1.0);
        final ghost = feetAt(kk);
        canvas.save();
        canvas.translate(ghost.dx, ghost.dy);
        canvas.rotate(-0.32 * math.sin(math.pi * kk));
        ev.draw(canvas, face, h, Paint()
          ..filterQuality = FilterQuality.low
          ..colorFilter = ColorFilter.mode(tint.withAlpha(_a((0.4 - i * 0.07) * env)), BlendMode.srcIn));
        canvas.restore();
      }
      // speed lines behind it
      final lp = Paint()..strokeCap = StrokeCap.round;
      for (var i = 0; i < 10; i++) {
        final y = feet.dy - h * (0.15 + 0.7 * _h(i, 120));
        final x = feet.dx + h * (0.3 + 0.6 * _h(i, 121)) + ((t * 900 + _h(i, 122) * 400) % 300);
        lp
          ..strokeWidth = 2 + 3 * _h(i, 123)
          ..color = Color.fromRGBO(255, 255, 255, 0.5 * env);
        canvas.drawLine(Offset(x, y), Offset(x + h * 0.5, y + h * 0.18), lp);
      }
    }
    // its colour pouring off it as it lands, and dust from its feet
    final land = u - 0.95;
    if (land >= 0) {
      final c = to - Offset(0, h * 0.45);
      final a = (land / 0.25).clamp(0.0, 1.0) * 0.5 * env;
      canvas.drawCircle(c, h * 0.8, Paint()..shader = ui.Gradient.radial(c, h * 0.8, [tint.withAlpha(_a(a)), tint.withAlpha(0)]));
      if (land < 0.8) _dust(canvas, to, land, W * 0.2, env, 9, const Offset(0, 2));
    }
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    // launch: a stretch; in the air: it leans back from the beam; landing: a squash, then it rises fierce
    var sx = 1.0, sy = 1.0, lean = 0.0, rot = 0.0;
    if (u < 0.12) {
      final c = u / 0.12;
      sx = 1 + 0.1 * c;
      sy = 1 - 0.12 * c; // crouching to spring
    } else if (u < 0.2) {
      sx = 0.9;
      sy = 1.14;
    } else if (air) {
      rot = -0.32 * math.sin(math.pi * k);
    } else if (land >= 0 && land < 0.22) {
      final c = math.sin(land / 0.22 * math.pi);
      sx = 1 + 0.12 * c;
      sy = 1 - 0.16 * c;
    } else if (land >= 0.22) {
      lean = -0.08;
    }
    canvas.rotate(rot);
    canvas.transform((Matrix4.identity()..setEntry(0, 1, lean)).storage);
    canvas.scale(sx, sy);
    ev.draw(canvas, face, h, Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, env));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SentinelPainter old) => true;
}
