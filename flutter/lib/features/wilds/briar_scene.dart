part of 'boss_intro.dart';

// The Briarback's entrance, shot by shot (the timeline is in boss_intro.dart):
//   A  wide: it steps out of the dark (Anticipation), a hoof lands (Hoof Impact), its antlers draw the light in
//      (Antler Charge), it rears and roars (Roar Release), thorn waves roll out over the wood (Shockwave), your
//      Evochi in front, seen over its shoulder
//   B  your Evochi inside the wave: its own Shock -> Strain -> Resolve (Evochi Reaction)
//   C  back on the guardian as it comes down; the waves break apart into leaves, sparks and fading runes; the
//      title (Title Reveal)
//   D  it settles, the energy ebbing, your Evochi in front again (Settle Pose)
// Depth: the wood behind, the guardian, the grass and your Evochi, the plants nearest; the camera pushes in on
// the roar and each layer moves its own amount.

const _lilac = Color(0xFFEDE2FF);
const _violet = Color(0xFFB48CFF);
const _waveSpeed = 1.25; // screen widths a second
const _waves = 6; // thorn waves in the roar
const _waveGap = 0.2;

mixin _BriarScene on _IntroFx {
  BossIntroArt get art;
  _BossIntroState get s;
  IntroCut get cut;
  Color get tint;
  double get len;
  int frameAt(double t);

  ReactArt? get react => s.widget.react;

  // ---- timing

  /// how charged the antlers are: rising as it lowers its head, full through the roar, ebbing as it settles
  double charge() {
    switch (cut) {
      case IntroCut.still:
        return 0.55;
      case IntroCut.short:
        return 0.35 + 0.6 * math.exp(-math.max(0.0, t - s.impactT) * 1.6);
      case IntroCut.full:
        if (t < _step) return 0.2 * (t / _step).clamp(0.0, 1.0);
        if (t < _rearEnd) return 0.2 + 0.8 * Curves.easeInCubic.transform((t - _step) / (_rearEnd - _step));
        if (t < _slam) return 1.0;
        return 0.35 + 0.65 * math.exp(-(t - _slam) * 1.3);
    }
  }

  /// when each thorn wave leaves the mouth (the roar), and the two that break apart as it lands
  List<double> waveStarts() => [
        if (cut == IntroCut.full) for (var i = 0; i < _waves; i++) _rearEnd + 0.08 + i * _waveGap,
        if (cut != IntroCut.still) ...[s.impactT, s.impactT + 0.16],
      ];

  // ---- the wide shots on the guardian (A, C, D)

  void guardianShot(Canvas canvas, Size size, double env, {required bool settle}) {
    final W = size.width, H = size.height;
    final fi = frameAt(t);
    final img = art.frame(fi);
    final k = charge();
    final base = math.min(H * 0.95 / art.size.height, W * 1.3 / art.size.width);
    // where it stands, and the camera: pushing in on the roar, easing back as it lands, pulled out to settle
    var scale = base;
    var at = Offset(W * 0.55, H * 0.86);
    var zoom = 1.0;
    var drift = Offset.zero;
    if (cut == IntroCut.full && t < _blast) {
      final p = _ease((t - 1.05) / (_blast - 1.05));
      zoom = 1 + 0.13 * p;
      drift = Offset(-W * 0.03 * p, H * 0.01 * p);
    } else if (!settle) {
      zoom = 1.06 - 0.06 * _ease((t - (cut == IntroCut.full ? _slam : 0.0)) / 0.9);
    }
    if (settle) {
      final p = _ease((t - _faceOff) / 0.55);
      // smaller and lower, so its lit antlers stay clear of the title above
      scale = base * (1.0 - 0.28 * p);
      at = Offset.lerp(Offset(W * 0.55, H * 0.86), Offset(W * 0.64, H * 0.885), p)!;
      // its breath as it holds
      scale *= 1 + 0.008 * math.sin(t * 2.4);
    }
    final origin = at - art.ground[0] * scale;
    Offset toScreen(Offset p) => origin + p * scale;
    final tips = (art.antlers.length > fi) ? [for (final p in art.antlers[fi]) toScreen(p)] : <Offset>[];
    final crown = tips.isEmpty ? toScreen(art.mouth[fi]) - Offset(0, H * 0.2) : tips.reduce((a, b) => a + b) / tips.length.toDouble();
    final eye = (art.eyes.length > fi) ? toScreen(art.eyes[fi][0]) : null;
    final mouth = toScreen(art.mouth[fi]);
    final focus = Offset.lerp(crown, mouth, 0.5)!;
    final starts = waveStarts();

    // the wood behind: far, hazy, purple; moonlight up on the right
    canvas.save();
    _cam(canvas, focus, zoom, 0.35, drift);
    _farWood(canvas, size, env, k);
    canvas.restore();
    // the near wood, the floor, the guardian, the grass
    canvas.save();
    _cam(canvas, focus, zoom, 1.0, drift);
    _woods(canvas, size, env, false);
    // the antlers' light over the wood
    canvas.drawCircle(crown, W * 0.75,
        Paint()..shader = ui.Gradient.radial(crown, W * 0.75, [Color.fromRGBO(150, 100, 240, 0.22 * k * env), const Color(0x00966EF0)]));
    _shadow(canvas, at, art.size.width * scale * 0.32, env * 0.55);
    if (img != null) {
      final dst = Rect.fromLTWH(origin.dx, origin.dy, art.size.width * scale, art.size.height * scale);
      final src = Rect.fromLTWH(0, 0, art.size.width, art.size.height);
      // a rim of the antlers' violet round its body: a soft glowing copy behind it
      canvas.drawImageRect(
          img,
          src,
          dst.shift(Offset(W * 0.004, -H * 0.004)),
          Paint()
            ..colorFilter = ColorFilter.mode(Color.fromRGBO(178, 136, 255, (0.35 + 0.45 * k) * env), BlendMode.srcIn)
            ..imageFilter = ui.ImageFilter.blur(sigmaX: 7, sigmaY: 7));
      // out of the dark: it is a silhouette at first, its crystals lit
      final dark = cut == IntroCut.full ? 0.82 * (1 - _ease((t - _open) / 0.75)) : 0.0;
      canvas.drawImageRect(
          img,
          src,
          dst,
          Paint()
            ..filterQuality = FilterQuality.medium
            ..color = Color.fromRGBO(0, 0, 0, env)
            ..colorFilter = dark > 0.01 ? ColorFilter.mode(Color.fromRGBO(10, 7, 18, dark), BlendMode.srcATop) : null);
    }
    _glows(canvas, size, tips, crown, eye, k, env);
    if (cut == IntroCut.full && t > _step - 0.05 && t < _rearEnd + 0.15) _chargeIn(canvas, size, tips, crown, eye ?? crown, k, env);
    // the hoof landing as it steps out (frame 6), and as it comes down (the impact)
    final stepAt = _step;
    if (cut == IntroCut.full && t >= stepAt && t < stepAt + 1.0 && art.hooves.length > 6) {
      for (final h in art.hooves[6]) {
        _dust(canvas, toScreen(h), t - stepAt, W * 0.22, env, 9, const Offset(0, 1));
        _kick(canvas, toScreen(h), t - stepAt, W, env, 7);
      }
    }
    final since = t - s.impactT;
    if (cut != IntroCut.still && since >= 0 && since < 1.2) {
      for (final h in art.hooves[art.impact]) {
        _dust(canvas, toScreen(h), since, W * 0.5, env, 18, const Offset(0, 1));
        _kick(canvas, toScreen(h), since, W, env, 10);
      }
      _shock(canvas, at, since, W, env);
    }
    // the roar's burst out of the antlers as it rears
    if (cut == IntroCut.full && t >= _rearEnd && t < _rearEnd + 0.45) _burst(canvas, crown, t - _rearEnd, W, env);
    // the thorn waves rolling out of its mouth, and the wood reacting
    for (var i = 0; i < starts.length; i++) {
      final age = t - starts[i];
      if (age < 0 || age > 1.5) continue;
      final decay = starts[i] >= s.impactT - 0.01;
      thornWave(canvas, mouth, age * W * (decay ? 0.8 : _waveSpeed) + W * 0.05, W, env, i, decay: decay, age: age);
    }
    _grass(canvas, size, env, mouth, starts);
    _sweep(canvas, size, env, mouth, starts);
    // a low fog over the feet, purple in the antlers' light
    canvas.drawRect(
        Rect.fromLTWH(-W * 0.2, H * 0.7, W * 1.4, H * 0.32),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, H * 0.7), Offset(0, H), [
            const Color(0x0016121F),
            Color.fromRGBO(34, 24, 52, 0.8 * env),
          ]));
    _fogBands(canvas, size, env, k, starts);
    canvas.restore();
    // nearest: plants at the corners (out of focus), and your Evochi seen over its shoulder
    canvas.save();
    _cam(canvas, focus, zoom, 1.6, drift);
    final ev = react;
    if (ev != null && cut == IntroCut.full && (t < _blast || settle)) {
      final inK = settle ? Curves.easeOutBack.transform(((t - _faceOff) / 0.5).clamp(0.0, 1.0)) : 1.0;
      final h = math.min(H * 0.42, W * 0.78);
      final feet = Offset(-W * 0.25 + W * 0.44 * inK, H * 1.0);
      // it leans into the waves as they pass over it
      final push = settle ? 0.0 : _push(feet - Offset(0, h * 0.5), mouth, W, starts);
      canvas.save();
      canvas.translate(feet.dx, feet.dy);
      canvas.transform((Matrix4.identity()..setEntry(0, 1, 0.12 * push)).storage);
      canvas.scale(1 + 0.04 * push, 1 - 0.05 * push);
      ev.drawBack(canvas, h, Paint()
        ..filterQuality = FilterQuality.medium
        ..color = Color.fromRGBO(0, 0, 0, env)
        ..colorFilter = ColorFilter.mode(Color.fromRGBO(24, 16, 40, 0.28 * (1 - k * 0.3)), BlendMode.srcATop));
      canvas.restore();
      // the antlers' light catching its edge
      canvas.drawCircle(feet - Offset(-h * 0.25, h * 0.6), h * 0.5,
          Paint()
            ..blendMode = BlendMode.plus
            ..shader = ui.Gradient.radial(feet - Offset(-h * 0.25, h * 0.6), h * 0.5,
                [Color.fromRGBO(120, 80, 200, 0.18 * k * env), const Color(0x00785AC8)]));
    }
    _plants(canvas, size, env, mouth, starts);
    canvas.restore();
  }

  void _cam(Canvas canvas, Offset focus, double zoom, double depth, Offset drift) {
    final z = 1 + (zoom - 1) * depth;
    canvas.translate(focus.dx + drift.dx * depth, focus.dy + drift.dy * depth);
    canvas.scale(z);
    canvas.translate(-focus.dx, -focus.dy);
  }

  // ---- the wood

  void _farWood(Canvas canvas, Size size, double env, double k) {
    final W = size.width, H = size.height;
    canvas.drawCircle(Offset(W * 0.8, H * 0.1), W * 0.55,
        Paint()..shader = ui.Gradient.radial(Offset(W * 0.8, H * 0.1), W * 0.55, [Color.fromRGBO(196, 176, 255, 0.2 * env), const Color(0x00C4B0FF)]));
    canvas.drawCircle(Offset(W * 0.8, H * 0.1), W * 0.045, Paint()..color = Color.fromRGBO(236, 228, 255, 0.55 * env));
    // far trunks, lost in the haze
    final p = Paint();
    for (var i = 0; i < 11; i++) {
      final x = W * (-0.05 + 1.1 * i / 10) + (_h(i, 80) - 0.5) * W * 0.06;
      final wid = W * (0.025 + 0.03 * _h(i, 81));
      final top = H * (-0.05 + 0.1 * _h(i, 82));
      p.color = Color.fromRGBO(46 + (12 * _h(i, 83)).round(), 34, 70, (0.55 + 0.2 * _h(i, 84)) * env);
      canvas.drawPath(
          Path()
            ..moveTo(x - wid * 0.6, top)
            ..lineTo(x + wid * 0.6, top)
            ..lineTo(x + wid, H * 0.82)
            ..lineTo(x - wid, H * 0.82)
            ..close(),
          p);
      // a branch or two
      final bp = Paint()
        ..color = p.color
        ..strokeWidth = wid * 0.35
        ..strokeCap = StrokeCap.round;
      final by = H * (0.2 + 0.3 * _h(i, 85));
      final dir = _h(i, 86) > 0.5 ? 1 : -1;
      canvas.drawLine(Offset(x, by), Offset(x + dir * W * 0.08, by - H * 0.06), bp);
    }
    // a haze band between the far and the near wood
    canvas.drawRect(
        Rect.fromLTWH(-W * 0.2, H * 0.35, W * 1.4, H * 0.45),
        Paint()
          ..shader = ui.Gradient.linear(Offset(0, H * 0.35), Offset(0, H * 0.8),
              [const Color(0x00281E3C), Color.fromRGBO(60, 44, 92, (0.35 + 0.15 * k) * env), const Color(0x00281E3C)], [0, 0.6, 1]));
  }

  // slow purple fog drifting across, shoved outward by the waves
  void _fogBands(Canvas canvas, Size size, double env, double k, List<double> starts) {
    final W = size.width, H = size.height;
    var shove = 0.0;
    for (final s0 in starts) {
      final a = t - s0;
      if (a > 0) shove += math.min(a, 0.8) * 0.35;
    }
    for (var i = 0; i < 5; i++) {
      final y = H * (0.62 + 0.07 * i);
      final x = W * ((_h(i, 90) + t * 0.02 * (1 + i * 0.3) + shove * (i.isEven ? 1 : -1) * 0.2) % 1.4 - 0.2);
      final r = W * (0.35 + 0.2 * _h(i, 91));
      canvas.drawOval(
          Rect.fromCenter(center: Offset(x, y), width: r * 2, height: r * 0.45),
          Paint()
            ..shader = ui.Gradient.radial(Offset(x, y), r,
                [Color.fromRGBO(120, 96, 170, (0.14 + 0.08 * k) * env), const Color(0x00786AAA)]));
    }
  }

  /// how hard the waves press at [p] right now (0: still): a pulse as each wave's front passes, and a
  /// lingering push behind it
  double _push(Offset p, Offset c, double W, List<double> starts) {
    var f = 0.0;
    final d = math.sqrt(math.pow(p.dx - c.dx, 2) + math.pow((p.dy - c.dy) / 0.62, 2));
    for (final s0 in starts) {
      final a = t - s0;
      if (a < 0) continue;
      final decay = s0 >= s.impactT - 0.01;
      final r = a * W * (decay ? 0.8 : _waveSpeed) + W * 0.05;
      final x = (r - d) / (W * 0.1);
      f += x > 0 ? math.exp(-x * 0.9) * (decay ? 0.4 : 0.7) : math.exp(-x * x * 6) * (decay ? 0.4 : 0.7);
    }
    return f.clamp(0.0, 1.6);
  }

  // grass along the floor: swaying, laid flat outward as each wave passes
  void _grass(Canvas canvas, Size size, double env, Offset c, List<double> starts) {
    final W = size.width, H = size.height;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 64; i++) {
      final x = W * (-0.05 + 1.1 * _h(i, 100));
      final y = H * (0.8 + 0.18 * _h(i, 101));
      final len = H * (0.035 + 0.05 * _h(i, 102)) * (0.7 + (y - H * 0.8) / (H * 0.2));
      final away = x < c.dx ? -1.0 : 1.0;
      final bend = math.sin(t * 2 + i) * 0.15 + away * _push(Offset(x, y), c, W, starts) * 0.9;
      final tip = Offset(x + bend * len, y - len * (1 - 0.35 * bend.abs()).clamp(0.3, 1.0));
      p
        ..strokeWidth = 2 + 2 * _h(i, 103)
        ..color = Color.lerp(const Color(0xFF233A26), const Color(0xFF4A5E3A), _h(i, 104))!.withAlpha(_a(0.95 * env));
      canvas.drawPath(Path()..moveTo(x, y)..quadraticBezierTo(x, y - len * 0.5, tip.dx, tip.dy), p);
    }
  }

  // big leaves at the corners, nearest the camera and out of focus, bending away from the roar
  void _plants(Canvas canvas, Size size, double env, Offset c, List<double> starts) {
    final W = size.width, H = size.height;
    final p = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3.5);
    for (var i = 0; i < 9; i++) {
      final left = i < 5;
      final root = Offset(left ? W * (-0.04 + 0.05 * i) : W * (1.04 - 0.05 * (i - 5)), H * (1.02 + 0.02 * _h(i, 110)));
      final away = root.dx < c.dx ? -1.0 : 1.0;
      final push = _push(root - Offset(0, H * 0.1), c, W, starts);
      final ang = (left ? -0.35 : 0.35) + (_h(i, 111) - 0.5) * 0.9 + math.sin(t * 1.3 + i) * 0.05 + away * push * 0.35;
      final L = H * (0.16 + 0.12 * _h(i, 112));
      final wdt = L * 0.32;
      canvas.save();
      canvas.translate(root.dx, root.dy);
      canvas.rotate(ang);
      p.color = Color.lerp(const Color(0xFF0C0A12), const Color(0xFF1C1626), _h(i, 113))!.withAlpha(_a(0.96 * env));
      canvas.drawPath(
          Path()
            ..moveTo(0, 0)
            ..quadraticBezierTo(-wdt, -L * 0.45, 0, -L)
            ..quadraticBezierTo(wdt, -L * 0.45, 0, 0)
            ..close(),
          p);
      canvas.restore();
    }
  }

  // ---- light

  void _glows(Canvas canvas, Size size, List<Offset> tips, Offset crown, Offset? eye, double k, double env) {
    final W = size.width;
    final flash = cut == IntroCut.full && t >= _rearEnd ? 1.2 * math.exp(-(t - _rearEnd) * 5) : 0.0;
    final b = (0.35 + 0.65 * k + flash) * env;
    final add = Paint()..blendMode = BlendMode.plus;
    // a soft crown of light round the antlers
    canvas.drawCircle(crown, W * 0.34,
        add..shader = ui.Gradient.radial(crown, W * 0.34, [Color.fromRGBO(150, 110, 255, 0.22 * b), const Color(0x00966EFF)]));
    for (var i = 0; i < tips.length; i++) {
      final p = tips[i];
      final r = W * (0.03 + 0.02 * k + 0.015 * math.sin(t * 6 + i * 1.7));
      canvas.drawCircle(p, r * 2.4,
          add..shader = ui.Gradient.radial(p, r * 2.4, [Color.fromRGBO(196, 160, 255, 0.4 * b), const Color(0x00C4A0FF)]));
      canvas.drawCircle(p, r * 0.8,
          add..shader = ui.Gradient.radial(p, r * 0.8, [Color.fromRGBO(255, 250, 255, 0.7 * b), const Color(0x00FFFFFF)]));
    }
    if (eye != null) {
      final e = (0.3 + 0.7 * k) * env;
      canvas.drawCircle(eye, W * 0.035,
          add..shader = ui.Gradient.radial(eye, W * 0.035, [Color.fromRGBO(240, 225, 255, 0.85 * e), const Color(0x00F0E1FF)]));
      // a thin streak of it while it roars
      if (cut == IntroCut.full && t >= _rearEnd && t < _slam) {
        canvas.drawOval(Rect.fromCenter(center: eye, width: W * 0.22, height: W * 0.012),
            add..shader = ui.Gradient.radial(eye, W * 0.11, [Color.fromRGBO(220, 200, 255, 0.45 * e), const Color(0x00DCC8FF)]));
      }
    }
  }

  // motes pulled in from all round into the antler tips, and thin thorn arcs forming round its head
  void _chargeIn(Canvas canvas, Size size, List<Offset> tips, Offset crown, Offset head, double k, double env) {
    final W = size.width;
    if (tips.isEmpty) return;
    final dot = Paint()..blendMode = BlendMode.plus;
    final trail = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (var i = 0; i < 48; i++) {
      final t0 = _step + 0.02 + 0.6 * _h(i, 120);
      final dur = 0.42 + 0.22 * _h(i, 121);
      final u = (t - t0) / dur;
      if (u < 0 || u > 1) continue;
      final tip = tips[i % tips.length];
      final a = math.pi * 2 * _h(i, 122);
      final start = tip + Offset(math.cos(a), math.sin(a) * 0.8) * W * (0.22 + 0.25 * _h(i, 123));
      Offset at(double v) {
        final e = Curves.easeInCubic.transform(v.clamp(0.0, 1.0));
        final side = Offset(-math.sin(a), math.cos(a)) * W * 0.06 * math.sin(v * math.pi) * (1 - v);
        return Offset.lerp(start, tip, e)! + side;
      }
      final pnow = at(u), pback = at(u - 0.12);
      final alpha = (0.25 + 0.75 * u) * env;
      trail
        ..strokeWidth = 1.5 + 1.5 * _h(i, 124)
        ..color = Color.fromRGBO(200, 170, 255, 0.5 * alpha);
      canvas.drawLine(pback, pnow, trail);
      dot.color = Color.fromRGBO(240, 228, 255, alpha);
      canvas.drawCircle(pnow, 1.6 + 1.8 * _h(i, 125), dot);
    }
    // the arcs
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 3; i++) {
      final r = W * (0.15 + 0.06 * i);
      final rot = t * (1.3 + 0.4 * i) * (i.isEven ? 1 : -1) + i * 2.1;
      final sweep = math.pi * (0.38 + 0.12 * i);
      final rect = Rect.fromCenter(center: head, width: r * 2, height: r * 1.5);
      arc
        ..strokeWidth = 2.2
        ..color = Color.fromRGBO(214, 190, 255, 0.65 * k * env);
      canvas.drawArc(rect, rot, sweep, false, arc);
      // thorns along it, pointing outward
      for (var j = 1; j < 6; j++) {
        final th = rot + sweep * j / 6;
        final o = Offset(head.dx + math.cos(th) * r, head.dy + math.sin(th) * r * 0.75);
        final out = Offset(math.cos(th), math.sin(th) * 0.75);
        final along = Offset(-math.sin(th), math.cos(th) * 0.75) * (i.isEven ? 1.0 : -1.0);
        _thorn(canvas, o, out, along, 7 * k, Color.fromRGBO(214, 190, 255, 0.65 * k * env));
      }
    }
  }

  void _thorn(Canvas canvas, Offset at, Offset out, Offset along, double size, Color c) {
    if (size < 0.5) return;
    final n = out / (out.distance == 0 ? 1 : out.distance);
    final a = along / (along.distance == 0 ? 1 : along.distance);
    canvas.drawPath(
        Path()
          ..moveTo(at.dx - a.dx * size * 0.45, at.dy - a.dy * size * 0.45)
          ..lineTo(at.dx + a.dx * size * 0.45, at.dy + a.dy * size * 0.45)
          ..lineTo(at.dx + n.dx * size * 1.3 - a.dx * size * 0.5, at.dy + n.dy * size * 1.3 - a.dy * size * 0.5)
          ..close(),
        Paint()..color = c);
  }

  // as it rears: light thrown out of the antlers in streaks
  void _burst(Canvas canvas, Offset c, double u, double W, double env) {
    final k = u / 0.45;
    final p = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus;
    for (var i = 0; i < 26; i++) {
      final a = math.pi * 2 * _h(i, 130);
      final r0 = W * (0.06 + 0.5 * k * (0.6 + 0.4 * _h(i, 131)));
      final r1 = r0 + W * (0.08 + 0.18 * _h(i, 132)) * (1 - k);
      p
        ..strokeWidth = 2 + 3 * _h(i, 133)
        ..color = Color.fromRGBO(230, 215, 255, (1 - k) * 0.8 * env);
      canvas.drawLine(c + Offset(math.cos(a), math.sin(a)) * r0, c + Offset(math.cos(a), math.sin(a)) * r1, p);
    }
  }

  // ---- the roar: thorn waves

  /// One wave of the roar out of [c], [r] across: a ring that is not a ring. A wobbling line of energy with
  /// thorns along it, a broken circle of runes just inside, streaks just outside, a soft glow under it all.
  /// As it ages (and when it [decay]s, as the guardian lands) it breaks into pieces.
  void thornWave(Canvas canvas, Offset c, double r, double W, double env, int seed, {bool decay = false, double age = 0}) {
    final maxR = W * 1.7;
    if (r > maxR) return;
    final fade = math.pow(1 - r / maxR, 0.9).toDouble() * (age * 6).clamp(0.0, 1.0);
    final a = fade * env * (decay ? 0.7 : 1.0);
    if (a < 0.02) return;
    const squash = 0.62; // seen low and from the side, flatter than it is wide
    final broken = (decay ? 0.35 + age * 0.9 : age * 0.35).clamp(0.0, 0.85);
    Offset at(double th, double rr) {
      final wob = rr * (0.03 * math.sin(5 * th + seed * 1.3) + 0.018 * math.sin(13 * th + seed * 2.7 + age * 3));
      return Offset(c.dx + math.cos(th) * (rr + wob), c.dy + math.sin(th) * (rr + wob) * squash);
    }
    bool gap(double th) => math.sin(3 * th + seed * 1.9 + age * 2.5) > 1 - broken * 1.6;
    const steps = 96;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 14 + r * 0.025
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 9)
      ..color = Color.fromRGBO(150, 96, 255, 0.5 * a);
    // a wider, fainter rose-violet bloom, added on, so the arcs read as light and not as wire
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..blendMode = BlendMode.plus
      ..strokeWidth = 30 + r * 0.04
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16)
      ..color = Color.fromRGBO(190, 90, 230, 0.16 * a);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 2.4 + 2.5 * (1 - r / maxR)
      ..color = Color.fromRGBO(228, 210, 255, 0.9 * a);
    final path = Path();
    var open = false;
    for (var i = 0; i <= steps; i++) {
      final th = math.pi * 2 * i / steps;
      if (gap(th)) {
        open = false;
        continue;
      }
      final p = at(th, r);
      if (!open) {
        path.moveTo(p.dx, p.dy);
        open = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(path, halo);
    canvas.drawPath(path, glow);
    canvas.drawPath(path, core);
    // thorns along the line, raked back like bramble
    final tc = Color.fromRGBO(226, 208, 255, 0.85 * a);
    for (var i = 0; i < 30; i++) {
      final th = math.pi * 2 * (i + 0.5 * _h(i + seed * 31, 140)) / 30;
      if (gap(th)) continue;
      final p = at(th, r);
      final out = Offset(math.cos(th), math.sin(th) * squash);
      final along = Offset(-math.sin(th), math.cos(th) * squash);
      _thorn(canvas, p, out, along, (6 + 6 * _h(i + seed * 31, 141)) * (1 - 0.5 * r / maxR), tc);
    }
    // runes, a broken ring just inside
    final rune = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.8
      ..color = Color.fromRGBO(206, 178, 255, 0.75 * a * (1 - broken * 0.6));
    for (var i = 0; i < 14; i++) {
      final th = math.pi * 2 * (i + 0.3) / 14 + seed * 0.4;
      if (gap(th + 0.2)) continue;
      final p = at(th, r * 0.9);
      _rune(canvas, p, th, 5 + r * 0.008, (i + seed) % 5, rune);
    }
    // streaks just outside
    final st = Paint()
      ..strokeCap = StrokeCap.round
      ..blendMode = BlendMode.plus
      ..strokeWidth = 1.6
      ..color = Color.fromRGBO(220, 200, 255, 0.55 * a);
    for (var i = 0; i < 12; i++) {
      final th = math.pi * 2 * _h(i + seed * 17, 142);
      final o = Offset(math.cos(th), math.sin(th) * squash);
      final p0 = c + o * r * 1.03;
      canvas.drawLine(p0, p0 + o * W * (0.03 + 0.05 * _h(i + seed, 143)), st);
    }
    // breaking up: sparks and leaves thrown off the broken ends
    if (broken > 0.2) {
      final sp = Paint()..blendMode = BlendMode.plus;
      for (var i = 0; i < 16; i++) {
        final th = math.pi * 2 * _h(i + seed * 13, 144);
        final p = at(th, r * (1 + 0.06 * _h(i, 145))) + Offset(0, -age * 30 * _h(i, 146));
        if (i % 3 == 0) {
          _leaf(canvas, p, t * 5 + i, 7, i, a);
        } else {
          sp.color = Color.fromRGBO(230, 210, 255, a * 0.8);
          canvas.drawCircle(p, 1.5 + 1.5 * _h(i, 147), sp);
        }
      }
    }
  }

  // a small rune: a few strokes, one of five shapes, turned along the ring
  void _rune(Canvas canvas, Offset at, double th, double s, int kind, Paint p) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(th + math.pi / 2);
    final path = Path();
    switch (kind) {
      case 0: // a staff with a hook
        path
          ..moveTo(0, -s)
          ..lineTo(0, s)
          ..moveTo(0, -s)
          ..lineTo(s * 0.7, -s * 0.3)
          ..lineTo(0, s * 0.2);
      case 1: // a chevron over a bar
        path
          ..moveTo(-s * 0.7, -s * 0.2)
          ..lineTo(0, -s)
          ..lineTo(s * 0.7, -s * 0.2)
          ..moveTo(-s * 0.6, s * 0.6)
          ..lineTo(s * 0.6, s * 0.6);
      case 2: // a diamond
        path
          ..moveTo(0, -s)
          ..lineTo(s * 0.6, 0)
          ..lineTo(0, s)
          ..lineTo(-s * 0.6, 0)
          ..close();
      case 3: // a branch
        path
          ..moveTo(0, s)
          ..lineTo(0, -s)
          ..moveTo(0, -s * 0.1)
          ..lineTo(-s * 0.6, -s * 0.7)
          ..moveTo(0, s * 0.3)
          ..lineTo(s * 0.6, -s * 0.3);
      default: // a crossed tick
        path
          ..moveTo(-s * 0.6, -s * 0.6)
          ..lineTo(s * 0.6, s * 0.6)
          ..moveTo(s * 0.6, -s * 0.6)
          ..lineTo(0, 0);
    }
    canvas.drawPath(path, p);
    canvas.restore();
  }

  void _leaf(Canvas canvas, Offset at, double spin, double size, int i, double a) {
    canvas.save();
    canvas.translate(at.dx, at.dy);
    canvas.rotate(spin);
    final c = i % 3 == 0 ? const Color(0xFF6E9A4A) : (i % 3 == 1 ? const Color(0xFF9C7040) : const Color(0xFF55704A));
    canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: size * 2, height: size * 0.85), Paint()..color = c.withAlpha(_a(0.95 * a)));
    canvas.restore();
  }

  // leaves, pollen and small stones kicked up by a hoof
  void _kick(Canvas canvas, Offset at, double since, double W, double env, int n) {
    if (since > 1.1) return;
    for (var i = 0; i < n; i++) {
      final dir = (_h(i, 150) - 0.5) * 2;
      final vx = dir * W * (0.18 + 0.2 * _h(i, 151));
      final vy = -W * (0.35 + 0.3 * _h(i, 152));
      final p = at + Offset(vx * since, vy * since + 0.5 * W * 1.4 * since * since);
      final a = (1 - since / 1.1) * env;
      if (i % 3 == 2) {
        canvas.drawRect(Rect.fromCenter(center: p, width: 4 + 3 * _h(i, 153), height: 4 + 3 * _h(i, 154)),
            Paint()..color = Color.fromRGBO(44, 34, 40, a));
      } else {
        _leaf(canvas, p, since * 9 + i, 6, i, a);
      }
    }
  }

  // swept out by the waves: leaves, pollen catching the antler light, dust and small stones
  void _sweep(Canvas canvas, Size size, double env, Offset c, List<double> starts) {
    final W = size.width, H = size.height;
    final dot = Paint()..blendMode = BlendMode.plus;
    for (var w = 0; w < starts.length; w++) {
      final age = t - starts[w];
      if (age < 0 || age > 1.6) continue;
      final decay = starts[w] >= s.impactT - 0.01;
      for (var i = 0; i < (decay ? 10 : 16); i++) {
        final j = i + w * 40;
        // things lying in the wave's path: on the floor, mostly, and a few in the air
        final a0 = math.pi * (0.05 + 0.9 * _h(j, 160)) * (_h(j, 165) > 0.8 ? -1 : 1);
        final r0 = W * (0.25 + 0.7 * _h(j, 161));
        final reach = age * W * (decay ? 0.8 : _waveSpeed) + W * 0.05;
        if (reach < r0) continue; // the wave hasn't got there yet
        final since = (reach - r0) / (W * (decay ? 0.8 : _waveSpeed));
        final o = Offset(math.cos(a0), math.sin(a0) * 0.62);
        final p = c + o * (r0 + since * W * (0.5 + 0.5 * _h(j, 162))) + Offset(0, -since * H * 0.12 * _h(j, 163) + since * since * H * 0.1);
        final alpha = (1 - since / 1.1).clamp(0.0, 1.0) * env;
        if (alpha <= 0) continue;
        switch (j % 4) {
          case 0:
          case 1:
            _leaf(canvas, p, since * 8 + j, 5 + 4 * _h(j, 164), j, alpha);
          case 2:
            dot.color = Color.fromRGBO(255, 236, 200, 0.8 * alpha);
            canvas.drawCircle(p, 1.4 + 1.2 * _h(j, 166), dot);
          default:
            canvas.drawRect(Rect.fromCenter(center: p, width: 3 + 3 * _h(j, 167), height: 3 + 3 * _h(j, 168)),
                Paint()..color = Color.fromRGBO(40, 32, 38, alpha));
        }
      }
    }
  }

  // ---- B: your Evochi inside the wave

  void reactShot(Canvas canvas, Size size, double env, ReactArt ev) {
    final W = size.width, H = size.height;
    final u = t - _blast;
    final gust = u < 0.12 ? u / 0.12 : (u < ev.end * 0.75 ? 1.0 : math.max(0.25, 1 - (u - ev.end * 0.75) / 0.6 * 0.75));
    _woods(canvas, size, env * 0.85, true);
    // the roar's pressure from the right, purple
    canvas.drawRect(
        Rect.fromLTWH(0, 0, W, H),
        Paint()
          ..shader = ui.Gradient.radial(Offset(W * 1.1, H * 0.42), W * 1.2,
              [Color.fromRGBO(160, 110, 240, 0.4 * gust * env), const Color(0x00A06EF0)]));
    // the waves rolling over it from the right: the near side of rings out of a mouth off the screen
    final src = Offset(W * 1.65, H * 0.4);
    for (var i = 0; i < 4; i++) {
      final age = u - i * 0.28 + 0.15;
      if (age < 0 || age > 1.6) continue;
      thornWave(canvas, src, W * 0.55 + age * W * 1.2, W * 1.4, env * 0.9, i + 3, age: age + 0.2);
    }
    _wind(canvas, size, gust * env, false);
    // it: pushed back a little as the blast hits, trembling as it strains, steady once it holds
    final pushBack = W * 0.06 * Curves.easeOutCubic.transform((u / 0.3).clamp(0.0, 1.0)) * (1 - 0.6 * _ease((u - ev.end * 0.7) / 0.4));
    final straining = u > ev.end * 0.3 && u < ev.end * 0.68;
    final tremble = straining ? math.sin(u * 90) * 2.2 : 0.0;
    final h = math.min(H * 0.5, W * 0.88);
    final feet = Offset(W * 0.5 - pushBack + tremble, H * 0.84);
    _shadow(canvas, feet, h * 0.45, 0.5 * env);
    // the dust off its feet as it digs in
    if (u > ev.end * 0.25 && u < ev.end * 0.9) {
      final p = Paint();
      for (var i = 0; i < 12; i++) {
        final ph = ((u * 2.2 + i / 12) % 1.0);
        final x = feet.dx + h * 0.12 - ph * W * 0.4 * (0.6 + _h(i, 16));
        final y = feet.dy - 6 - ph * 34 * _h(i, 17);
        p.color = Color.fromRGBO(200, 186, 160, (1 - ph) * 0.55 * env);
        canvas.drawCircle(Offset(x, y), 5 + 11 * ph, p);
      }
    }
    // its own colour round it as it holds
    if (u > ev.end * 0.7) {
      final a = ((u - ev.end * 0.7) / 0.3).clamp(0.0, 1.0) * 0.5 * env;
      final c = feet - Offset(0, h * 0.42);
      canvas.drawCircle(c, h * 0.7, Paint()..shader = ui.Gradient.radial(c, h * 0.7, [tint.withAlpha(_a(a)), tint.withAlpha(0)]));
    }
    canvas.save();
    canvas.translate(feet.dx, feet.dy);
    ev.draw(canvas, u, h, Paint()
      ..filterQuality = FilterQuality.medium
      ..color = Color.fromRGBO(0, 0, 0, env));
    canvas.restore();
    _swooshes(canvas, feet - Offset(0, h * 0.46), h, gust * env);
    _wind(canvas, size, gust * env * 0.6, true);
    // grass in front, laid flat to the left
    final gp = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 40; i++) {
      final x = W * (-0.05 + 1.1 * _h(i, 170));
      final y = H * (0.9 + 0.1 * _h(i, 171));
      final len = H * (0.05 + 0.05 * _h(i, 172));
      final bend = -(0.3 + 0.9 * gust) + math.sin(t * 9 + i) * 0.12 * gust;
      gp
        ..strokeWidth = 2.5 + 2 * _h(i, 173)
        ..color = Color.fromRGBO(22, 30, 22, 0.95 * env);
      canvas.drawPath(Path()..moveTo(x, y)..quadraticBezierTo(x, y - len * 0.5, x + bend * len, y - len * (1 - 0.3 * bend.abs())), gp);
    }
  }

  // a soft frame of dark round the edges, warmer at the top where the moon is
  void vignette(Canvas canvas, Size size, double env) {
    final W = size.width, H = size.height;
    canvas.drawRect(
        Rect.fromLTWH(0, 0, W, H),
        Paint()
          ..shader = ui.Gradient.radial(Offset(W * 0.5, H * 0.45), math.max(W, H) * 0.75,
              [const Color(0x00000000), Color.fromRGBO(10, 6, 18, 0.55 * env)], [0.55, 1.0]));
  }
}
