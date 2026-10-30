// The Hollow Sprout's entrance (the Mossy Ruins, F3): a short cinematic before the fight, the way the
// Briarback and the Sentinel have theirs.
//
//   1. Letterbox. Low down among the broken stones of the ruins at dusk: the Sprout wilted in its roots,
//      asleep. Its slit eyes ignite.
//   2. It uncurls and rears back; Hollow vines lash up round it, its crystals flare.
//   3. It swells, shaking, and bursts: a storm of Hollow spores and petals rolls out of it.
//   4. Cut to your Evochi as the spores roll over it: Shock, Strain, Resolve (the Briarback's reaction shot,
//      in a cloud of spores).
//   5. Back on the Sprout: it slams its bulb down; the flagstones crack, dust and leaves jump.
//   6. A second camera, lower and closer: it sways over you, crystals pulsing, a ring of drifting petals
//      behind it; the title card slams in.
//
// The Sprout is a pre-rendered sequence (tools/art/sprout_intro.py); your Evochi is its reaction art
// (tools/art/cine_react_export.py). The ruins, light, spores and vines are drawn here. Tap to skip. The
// full version plays the first time; after that a short one (the swaying shot and the title); with
// reduced motion, a still title card.

part of 'boss_intro.dart';

// the full cut's timeline (seconds)
const _pOpen = 0.35; // letterbox in; frames 0..9 at 8 fps: asleep, its eyes igniting
const _pRise = 1.6; // frames 10..15 at 10 fps: it uncurls and rears back
const _pSwell = 2.2; // frames 16..18 at 8 fps: swelling, then held, shaking
const _pBurst = 2.75; // frame 19: the spores burst out of it
const _pReact = 3.0; // cut to your Evochi in the spores
const _pSlam = 4.85; // back on it: frames 20..25 at 12 fps, its bulb on the ground at frame 23
const _pMenace = 5.6; // the second camera: frames 26.. at 8 fps
const _pTitle = 5.85;
const _pFullLen = 7.9;
const _pShortLen = 2.3;
const _pStillLen = 2.4;

class SproutIntro extends StatefulWidget {
  const SproutIntro({
    super.key,
    required this.art,
    this.react,
    required this.cut,
    required this.petName,
    required this.tint,
    required this.onCue,
    required this.onDone,
  });
  final BossIntroArt art;
  final ReactArt? react;
  final IntroCut cut;
  final String petName;
  final Color tint;
  final void Function(String cue) onCue;
  final VoidCallback onDone;

  @override
  State<SproutIntro> createState() => _SproutIntroState();
}

class _SproutIntroState extends State<SproutIntro> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _t = 0;
  bool _done = false;
  final _fired = <String>{};

  double get _len => switch (widget.cut) { IntroCut.full => _pFullLen, IntroCut.short => _pShortLen, IntroCut.still => _pStillLen };

  /// when the title slams in
  double get titleT => switch (widget.cut) { IntroCut.full => _pTitle, IntroCut.short => 0.25, IntroCut.still => 0.0 };

  int _m(String k, int d) => (widget.art.meta[k] as num?)?.toInt() ?? d;
  int get _lit => _m('lit', 4);
  int get _menaceF => _m('menace', 26);

  /// when its bulb hits the ground
  double get impactT => _pSlam + (widget.art.impact - _m('slam', 20)) / 12;

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
    // the slam's frames ready before the cut back to it
    final react = widget.cut == IntroCut.full && t > _pBurst && t < _pSlam;
    widget.art.want(idx, keep: react ? const [20, 21, 22, 23] : const []);
  }

  /// The Sprout's frame at [t].
  int frameAt(double t) {
    final n = widget.art.count;
    switch (widget.cut) {
      case IntroCut.still:
        return n - 1;
      case IntroCut.short:
        return (_menaceF + (t.clamp(0.0, 9.0) * 8).floor()).clamp(0, n - 1);
      case IntroCut.full:
        if (t < _pRise) return ((t - _pOpen).clamp(0.0, 9.0) * 8).floor().clamp(0, 9);
        if (t < _pSwell) return (10 + ((t - _pRise) * 10).floor()).clamp(10, 15);
        if (t < _pBurst) return (16 + ((t - _pSwell) * 8).floor()).clamp(16, 18);
        if (t < _pSlam) return 19;
        if (t < _pMenace) return (20 + ((t - _pSlam) * 12).floor()).clamp(20, 25);
        return (_menaceF + ((t - _pMenace) * 8).floor()).clamp(_menaceF, n - 1);
    }
  }

  void _cue(String id, double at) {
    if (_t >= at && _fired.add(id)) widget.onCue(id);
  }

  void _cues() {
    switch (widget.cut) {
      case IntroCut.full:
        _cue('open', 0);
        _cue('ignite', _pOpen + _lit / 8);
        _cue('rise', _pRise);
        _cue('swell', _pSwell);
        _cue('burst', _pBurst);
        if (widget.react != null) _cue('react', _pReact);
        _cue('slam', impactT);
        _cue('title', titleT);
      case IntroCut.short:
        _cue('title', titleT);
      case IntroCut.still:
        _cue('burst', 0);
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
    if (since >= 0 && since < 0.6) s = math.max(s, 12 * math.pow(1 - since / 0.6, 2).toDouble());
    if (widget.cut == IntroCut.full) {
      if (t > _pSwell && t < _pBurst) s = math.max(s, 2 + 5 * (t - _pSwell) / (_pBurst - _pSwell)); // swelling, trembling
      final b = t - _pBurst;
      if (b > 0 && b < 0.45) s = math.max(s, 11 * (1 - b / 0.45));
      final rv = widget.react;
      if (rv != null && t > _pReact && t < _pSlam) s = math.max(s, 6 * math.min(1.0, rv.impulse(t - _pReact)));
      final i = t - impactT;
      if (i > 0 && i < 0.5) s = math.max(s, 15 * math.pow(1 - i / 0.5, 2).toDouble());
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
      label: 'The Hollow Sprout, Lost Heart of the Ruins. Tap to skip.',
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _finish,
        child: LayoutBuilder(builder: (ctx, b) {
          final size = Size(b.maxWidth, b.maxHeight);
          final bar = size.height * (widget.cut == IntroCut.full ? 0.1 : 0.07);
          return Stack(children: [
            Positioned.fill(child: CustomPaint(painter: _SproutPainter(this, t, shake))),
            if (titleOn)
              Positioned(
                left: 12,
                right: 12,
                top: bar + 14 + shake.dy,
                child: Opacity(
                  opacity: (pop.clamp(0.0, 1.0) * fadeOut).toDouble(),
                  child: Transform.scale(
                      scale: 1 + (1 - pop) * 0.9,
                      child: _Title(name: 'Hollow Sprout', title: 'Lost Heart of the Ruins', width: size.width, emblem: _SproutEmblem())),
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

class _SproutPainter extends CustomPainter with _IntroFx, _BriarScene {
  _SproutPainter(this.s, this.t, this.shake);
  final _SproutIntroState s;
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
  @override
  int frameAt(double t) => s.frameAt(t);
  @override
  double get reactAt => _pReact;
  @override
  String get waveStyle => 'spore';

  List<Offset> _marks(String k, int fi) {
    final l = art.meta[k] as List?;
    if (l == null || fi >= l.length) return const [];
    final f = l[fi] as List;
    if (f.isNotEmpty && f.first is num) return [_pt(f)];
    return [for (final p in f) _pt(p)];
  }

  @override
  void paint(Canvas canvas, Size size) {
    final W = size.width, H = size.height;
    final env = math.min((t / _pOpen).clamp(0.0, 1.0), ((len - t) / 0.45).clamp(0.0, 1.0));
    final bg = Rect.fromLTWH(0, 0, W, H);
    // dusk over the ruins: violet above, a cold teal haze low down
    canvas.drawRect(
        bg,
        Paint()
          ..shader = ui.Gradient.linear(Offset.zero, Offset(0, H), [
            Color.fromRGBO(18, 12, 30, env),
            Color.fromRGBO(40, 28, 58, env),
            Color.fromRGBO(22, 34, 36, env),
          ], [0, 0.55, 1]));
    canvas.save();
    canvas.translate(shake.dx, shake.dy);
    final rv = react;
    final reacting = cut == IntroCut.full && rv != null && t >= _pReact && t < _pSlam;
    if (reacting) {
      reactShot(canvas, size, env, rv);
    } else {
      _ruins(canvas, size, env);
      _sproutShot(canvas, size, env);
    }
    _drift(canvas, size, env);
    canvas.restore();
    // the flashes: as it bursts, and as the title slams in
    final since = t - s.titleT;
    if (cut != IntroCut.still && since >= 0 && since < 0.22) {
      canvas.drawRect(bg, Paint()..color = Color.fromRGBO(245, 235, 255, 0.5 * (1 - since / 0.22)));
    }
    if (cut == IntroCut.full) {
      final b = t - _pBurst;
      if (b >= 0 && b < 0.2) canvas.drawRect(bg, Paint()..color = Color.fromRGBO(210, 180, 255, 0.55 * (1 - b / 0.2)));
    }
    vignette(canvas, size, env);
    // the letterbox
    final barH = H * (cut == IntroCut.full ? 0.1 : 0.07);
    final slide = math.min((t / 0.3).clamp(0.0, 1.0), ((len - t) / 0.35).clamp(0.0, 1.0));
    final bh = barH * Curves.easeOutCubic.transform(slide);
    final bp = Paint()..color = const Color(0xFF07060B);
    canvas.drawRect(Rect.fromLTWH(0, 0, W, bh), bp);
    canvas.drawRect(Rect.fromLTWH(0, H - bh, W, bh), bp);
  }

  // ---- the ruins: broken pillars and an arch against the dusk, flagstones underfoot, moss on everything
  void _ruins(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    final floor = H * 0.74;
    // the far wall: a broken arch, dim
    final far = Paint()..color = Color.fromRGBO(30, 24, 44, 0.95 * env);
    final arch = Path()
      ..moveTo(W * 0.18, floor)
      ..lineTo(W * 0.18, H * 0.36)
      ..quadraticBezierTo(W * 0.5, H * 0.12, W * 0.82, H * 0.36)
      ..lineTo(W * 0.82, floor)
      ..lineTo(W * 0.72, floor)
      ..lineTo(W * 0.72, H * 0.42)
      ..quadraticBezierTo(W * 0.5, H * 0.25, W * 0.28, H * 0.42)
      ..lineTo(W * 0.28, floor)
      ..close();
    canvas.drawPath(arch, far);
    // a bite out of the arch's crown, and moss on its top
    canvas.drawCircle(Offset(W * 0.6, H * 0.2), W * 0.07, Paint()..color = Color.fromRGBO(40, 28, 58, env));
    final moss = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round
      ..color = Color.fromRGBO(66, 92, 60, 0.9 * env);
    canvas.drawPath(
        Path()
          ..moveTo(W * 0.2, H * 0.34)
          ..quadraticBezierTo(W * 0.38, H * 0.2, W * 0.52, H * 0.19),
        moss);
    // the Hollow's light through the arch, behind it
    final c = Offset(W * 0.5, floor - H * 0.12);
    canvas.drawCircle(c, W * 0.6, Paint()..shader = ui.Gradient.radial(c, W * 0.6, [Color.fromRGBO(150, 100, 230, 0.3 * env), const Color(0x009664E6)]));
    // pillars at the edges, near and dark, their tops broken
    final pp = Paint()..color = Color.fromRGBO(12, 10, 18, 0.96 * env);
    for (var i = 0; i < 4; i++) {
      final left = i.isEven;
      final x = left ? W * (0.02 + 0.1 * (i ~/ 2)) - 20 : W * (0.98 - 0.1 * (i ~/ 2)) - W * 0.1 + 20;
      final w = W * (0.12 - 0.02 * (i ~/ 2));
      final top = H * (0.12 + 0.2 * _h(i, 200));
      final path = Path()
        ..moveTo(x, H)
        ..lineTo(x, top + 18)
        ..lineTo(x + w * 0.3, top)
        ..lineTo(x + w * 0.55, top + 22)
        ..lineTo(x + w * 0.8, top + 6)
        ..lineTo(x + w, top + 26)
        ..lineTo(x + w, H)
        ..close();
      canvas.drawPath(path, pp);
      canvas.drawLine(Offset(x + 4, top + 22), Offset(x + w * 0.7, top + 14), moss..strokeWidth = 4);
    }
    // the floor: flagstones going away, moss in the joints
    canvas.drawRect(
        Rect.fromLTWH(0, floor, W, H - floor),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, floor), Offset(0, H), [Color.fromRGBO(44, 42, 52, env), Color.fromRGBO(20, 22, 26, env)]));
    final joint = Paint()
      ..strokeWidth = 2
      ..color = Color.fromRGBO(70, 96, 62, 0.55 * env);
    for (var r = 0; r < 6; r++) {
      final y = floor + (H - floor) * math.pow((r + 1) / 6, 1.7).toDouble();
      canvas.drawLine(Offset(0, y), Offset(W, y), joint);
    }
    for (var i = -6; i <= 6; i++) {
      canvas.drawLine(Offset(W * 0.5 + i * W * 0.06, floor), Offset(W * 0.5 + i * W * 0.32, H), joint);
    }
  }

  // ---- the Sprout: its frames, low in the picture
  void _sproutShot(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    final fi = s.frameAt(t);
    final img = art.frame(fi);
    final menace = fi >= s._menaceF;
    final full = cut == IntroCut.full;
    // a slow push in, about the ground under it
    final push = menace ? 1.0 + 0.07 * _ease(full ? (t - _pMenace) / (len - _pMenace) : t / len) : 1.0 + 0.08 * _ease((t - _pOpen) / (_pBurst - _pOpen));
    // its frames are drawn close; here it stands back among the ruins, its roots on the flagstones
    final k = math.min(H / art.size.height, W / art.size.width) * (menace ? 0.82 : 0.72) * push;
    final g = art.ground[fi];
    final at = Offset(W * 0.5, H * (menace ? 0.84 : 0.8));
    final origin = at - g * k;
    Offset toScreen(Offset p) => origin + p * k;
    final eyes = _marks('eyes', fi).map(toScreen).toList();
    final eye = eyes.isEmpty ? toScreen(art.mouth[fi]) : eyes.first;
    final crystals = _marks('crystals', fi).map(toScreen).toList();
    final mouth = toScreen(art.mouth[fi]);
    final roots = [for (final r in art.hooves[fi]) toScreen(r)];
    final lit = fi >= s._lit || !full;
    // behind it: a ring of drifting petals while it looms, and its glow
    canvas.drawCircle(eye, W * 0.8, Paint()..shader = ui.Gradient.radial(eye, W * 0.8, [Color.fromRGBO(150, 100, 230, (lit ? 0.28 : 0.1) * env), const Color(0x009664E6)]));
    if (menace || cut == IntroCut.still) _petalRing(canvas, eye + Offset(0, W * 0.05), W * 0.55, env);
    // Hollow vines lashing up round it as it rises and slams
    if (full && t > _pRise && t < _pMenace) _vines(canvas, at, k * art.size.height * 0.5, W, env);
    if (menace || cut == IntroCut.still) _vines(canvas, at, k * art.size.height * 0.42, W, env * 0.7);
    _shadow(canvas, at, art.size.width * k * 0.22, 0.6 * env);
    if (img != null) {
      canvas.drawImageRect(
          img,
          Rect.fromLTWH(0, 0, art.size.width, art.size.height),
          Rect.fromLTWH(origin.dx, origin.dy, art.size.width * k, art.size.height * k),
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(0, 0, 0, env));
    }
    if (full && !menace) {
      // its eyes ignite
      final ig = t - (_pOpen + s._lit / 8);
      if (ig >= 0 && ig < 0.6) {
        for (final e in eyes.isEmpty ? [eye] : eyes) {
          _glint(canvas, e, W * 0.22 * (1 - ig / 0.6) + 6, (1 - ig / 0.6) * env);
        }
      }
      // its crystals flare as it swells
      if (t > _pRise) {
        final f = ((t - _pRise) / (_pBurst - _pRise)).clamp(0.0, 1.0);
        for (final c in crystals) {
          _glint(canvas, c, W * (0.04 + 0.08 * f) * (0.85 + 0.15 * math.sin(t * 17 + c.dx)), (0.4 + 0.6 * f) * env);
        }
      }
      // spores leaking out of it as it swells, then the burst
      if (t > _pSwell && t < _pBurst) _leak(canvas, mouth, W, (t - _pSwell) / (_pBurst - _pSwell), env);
      if (t >= _pBurst) {
        final b = t - _pBurst;
        for (var i = 0; i < 3; i++) {
          final age = b - i * 0.12;
          if (age > 0) thornWave(canvas, mouth, W * 0.08 + age * W * 1.6, W, env, 11 + i, age: age, style: 'spore');
        }
      }
      // the slam: the flagstones crack, dust and leaves jump off the roots
      final i = t - s.impactT;
      if (i >= 0) {
        _cracks(canvas, at, W, (i / 0.25).clamp(0.0, 1.0), env * (1 - ((i - 0.8) / 0.4).clamp(0.0, 1.0)));
        if (i < 1.0) {
          _shock(canvas, at, i, W, env);
          for (final r in roots) {
            _dust(canvas, r, i, W * 0.25, env, 8, const Offset(0, 1));
          }
          for (var j = 0; j < 10; j++) {
            final a = -math.pi * (0.1 + 0.8 * _h(j, 210));
            final v = W * (0.4 + 0.5 * _h(j, 211));
            final p = at + Offset(math.cos(a) * v * i, math.sin(a) * v * i + 700 * i * i);
            _leaf(canvas, p, t * 6 + j, 8, j, (1 - i) * env);
          }
        }
      }
    }
    if (menace || cut == IntroCut.still) {
      final flick = 0.85 + 0.15 * math.sin(t * 9);
      for (final e in eyes.isEmpty ? [eye] : eyes) {
        _glint(canvas, e, W * 0.06 * flick, 0.65 * env);
      }
      for (final c in crystals) {
        _glint(canvas, c, W * 0.05 * (0.8 + 0.2 * math.sin(t * 5 + c.dy)), 0.7 * env);
      }
    }
  }

  // a point of violet light with a bright core
  void _glint(Canvas canvas, Offset c, double r, double a) {
    if (a <= 0.01) return;
    canvas.drawCircle(c, r * 2.2, Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(c, r * 2.2, [Color.fromRGBO(190, 150, 255, 0.5 * a), const Color(0x00BE96FF)]));
    canvas.drawCircle(c, r * 0.5, Paint()
      ..blendMode = BlendMode.plus
      ..shader = ui.Gradient.radial(c, r * 0.5, [Color.fromRGBO(255, 250, 255, 0.9 * a), const Color(0x00FFFFFF)]));
  }

  // spores leaking out as it swells: puffs rising and spreading, more and faster toward the burst
  void _leak(Canvas canvas, Offset from, double W, double k, double env) {
    final p = Paint();
    for (var i = 0; i < 14; i++) {
      final ph = (t * (0.8 + 1.2 * k) + _h(i, 220)) % 1.0;
      final a = -math.pi * (0.15 + 0.7 * _h(i, 221));
      final d = W * (0.05 + 0.25 * ph) * (0.6 + 0.6 * k);
      final c = from + Offset(math.cos(a) * d, math.sin(a) * d - ph * W * 0.1);
      final r = 4 + 10 * ph;
      p.shader = ui.Gradient.radial(c, r, [Color.fromRGBO(200, 160, 255, (1 - ph) * 0.6 * k * env), const Color(0x00C8A0FF)]);
      canvas.drawCircle(c, r, p);
    }
  }

  // Hollow vines: dark violet tendrils curling up out of the ground round it, swaying, lit at the buds
  void _vines(Canvas canvas, Offset at, double reach, double W, double env) {
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 6; i++) {
      final side = i.isEven ? -1.0 : 1.0;
      final base = at + Offset(side * reach * (0.45 + 0.25 * _h(i, 230)), 4);
      final lash = math.sin(t * (2.2 + _h(i, 231)) + i * 1.7);
      final tip = base + Offset(side * reach * (0.35 + 0.15 * lash), -reach * (0.8 + 0.4 * _h(i, 232)));
      final mid = Offset.lerp(base, tip, 0.5)! + Offset(-side * reach * 0.25 * lash, 0);
      final path = Path()
        ..moveTo(base.dx, base.dy)
        ..quadraticBezierTo(mid.dx, mid.dy, tip.dx, tip.dy);
      p
        ..strokeWidth = 9 - i * 0.6
        ..color = Color.fromRGBO(52, 36, 82, 0.95 * env);
      canvas.drawPath(path, p);
      p
        ..strokeWidth = 2.5
        ..color = Color.fromRGBO(110, 80, 160, 0.8 * env);
      canvas.drawPath(path, p);
      // thorns along it, and a glowing bud at the tip
      for (var j = 1; j < 4; j++) {
        final q = Offset.lerp(Offset.lerp(base, mid, j / 4)!, Offset.lerp(mid, tip, j / 4)!, j / 4)!;
        canvas.drawLine(q, q + Offset(side * 8, -6), p..strokeWidth = 2);
      }
      _glint(canvas, tip, 7, 0.8 * env);
    }
  }

  // the flagstones cracking out from under it
  void _cracks(Canvas canvas, Offset at, double W, double k, double env) {
    if (env <= 0) return;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (var i = 0; i < 7; i++) {
      final a = math.pi * (0.05 + 0.9 * i / 6) + (_h(i, 240) - 0.5) * 0.3;
      final len = W * (0.25 + 0.2 * _h(i, 241)) * k;
      var q = at;
      final path = Path()..moveTo(q.dx, q.dy);
      for (var j = 1; j <= 4; j++) {
        q = at + Offset(math.cos(a) * len * j / 4 + (_h(i * 7 + j, 242) - 0.5) * 18, math.sin(a) * len * j / 4 * 0.28);
        path.lineTo(q.dx, q.dy);
      }
      p
        ..strokeWidth = 5
        ..color = Color.fromRGBO(10, 8, 14, 0.85 * env);
      canvas.drawPath(path, p);
      p
        ..strokeWidth = 1.8
        ..color = Color.fromRGBO(200, 160, 255, 0.7 * env);
      canvas.drawPath(path, p);
    }
  }

  // a slow ring of Hollow petals turning behind it
  void _petalRing(Canvas canvas, Offset c, double r, double env) {
    for (var i = 0; i < 16; i++) {
      final a = t * 0.4 + i * math.pi * 2 / 16;
      final p = c + Offset(math.cos(a) * r, math.sin(a) * r * 0.45);
      _leaf(canvas, p, t * 2 + i, 7, i + 5, 0.6 * env);
    }
  }

  // motes drifting across it all: violet, a few spores
  void _drift(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    final p = Paint();
    for (var i = 0; i < 24; i++) {
      final x = (W * _h(i, 250) + t * 18 * (0.5 + _h(i, 251))) % W;
      final y = (H * _h(i, 252) - t * 14 * (0.4 + _h(i, 253))) % H;
      final r = 1.5 + 2.5 * _h(i, 254);
      p.color = Color.fromRGBO(210, 180, 255, (0.35 + 0.35 * math.sin(t * 2 + i)).clamp(0.0, 1.0) * env);
      canvas.drawCircle(Offset(x, y), r, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SproutPainter old) => true;
}

/// The Hollow Sprout's sigil over its name: a bulb and its two leaves, a crack of Hollow light down it.
class _SproutEmblem extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final c = Offset(w / 2, h * 0.64);
    canvas.drawCircle(c, w * 0.4, Paint()..shader = ui.Gradient.radial(c, w * 0.4, [const Color(0x889A6BFF), const Color(0x009A6BFF)]));
    final line = Paint()
      ..color = const Color(0xFFD9C6FF)
      ..strokeWidth = math.max(1.6, w * 0.022)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    // the bulb
    final bulb = Rect.fromCenter(center: c + Offset(0, h * 0.08), width: w * 0.3, height: h * 0.5);
    canvas.drawOval(bulb, Paint()..color = const Color(0xFF3F2E62));
    canvas.drawOval(bulb, line);
    // its two leaves, wilting
    for (final s in [-1.0, 1.0]) {
      final leaf = Path()
        ..moveTo(c.dx, c.dy - h * 0.18)
        ..quadraticBezierTo(c.dx + s * w * 0.2, c.dy - h * 0.62, c.dx + s * w * 0.42, c.dy - h * 0.3)
        ..quadraticBezierTo(c.dx + s * w * 0.2, c.dy - h * 0.3, c.dx, c.dy - h * 0.18);
      canvas.drawPath(leaf, Paint()..color = const Color(0xFF6B5594));
      canvas.drawPath(leaf, line);
    }
    // the crack of light down it
    final crack = Path()
      ..moveTo(c.dx, c.dy - h * 0.1)
      ..lineTo(c.dx + w * 0.03, c.dy + h * 0.04)
      ..lineTo(c.dx - w * 0.02, c.dy + h * 0.14)
      ..lineTo(c.dx + w * 0.01, c.dy + h * 0.26);
    canvas.drawPath(crack, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(2.0, w * 0.03)
      ..color = const Color(0xFFF1E6FF));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
