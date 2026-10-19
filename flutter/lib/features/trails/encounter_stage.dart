// Lumen Trails: the battle shot. Your Evochi from behind in the foreground, the wild one facing it on
// a 2:3 backdrop with a foreground layer for depth, camera "shots" (wide / pet / wild / close / face),
// shakes, punches, a flash, a Hollow aura, the nameplates, the intro title and the result ribbon, the
// canvas effects (stage_fx.dart) on two layers and the few widget effects a turn throws around
// (floating numbers, a "?" bubble, Petalune swooping in).
//
// The stage is driven imperatively through [EncounterStage] (a ChangeNotifier the screen pokes from
// its timelines), so camera moves and effects never restart when the state re-renders. Everything
// that moves inside the world reads one [StageClock], which the hit-stop holds still for a few
// frames. Geometry is expressed in fractions of the backdrop, so it lines up at any size. Mirrors
// the stage half of web/src/screens/encounter.js and the "encounter: the battle shot" CSS.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../app/theme.dart';
import '../../core/models/game_state.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/trails/trails.dart' as tr;
import '../shared/sprite.dart';
import '../shared/widgets.dart';
import 'stage_fx.dart';

// your Evochi's frame width (share of the shot's width) per stage, and how far right its face may reach
const petWidthByStage = {1: 0.44, 2: 0.52, 3: 0.68};
const faceMaxX = 0.38;
// lift your Evochi off the scene's mark a little, so its card below covers only its feet
const petLift = 0.075;
const camCurve = Cubic(0.3, 0.75, 0.25, 1);
// the beats of a turn move the camera quickly
const fastCurve = Cubic(0.2, 0.7, 0.2, 1);
const punchCurve = Cubic(0.1, 0.7, 0.2, 1);
const popCurve = Cubic(0.2, 1.3, 0.4, 1);
const _deg = math.pi / 180;

// ---------------------------------------------------------------------- geometry ----
/// Where everything sits on the battle shot, in fractions of the backdrop (so it lines up at any size).
class ShotGeometry {
  ShotGeometry({
    required this.scene,
    required this.creature,
    required this.ar,
    required this.wildLeft,
    required this.wildTop,
    required this.wildWidth,
    required this.wildAr,
    required this.wildCx,
    required this.wildCy,
    required this.wildFace,
    required this.wildEyes,
    required this.wildEyesAbs,
    required this.wildHeadY,
    required this.wildBottom,
    required this.wildGy,
    required this.petLeft,
    required this.petTop,
    required this.petWidth,
    required this.petAr,
    required this.petCx,
    required this.petCy,
    required this.petFace,
    required this.petHead,
    required this.petFeetY,
    required this.petGy,
    required this.petHeadLocal,
  });
  final BattleScene scene;
  final BattleCreature creature;
  final double ar; // the backdrop's width / height
  // the wild one
  final double wildLeft, wildTop, wildWidth, wildAr;
  final double wildCx, wildCy; // its centre of mass (effects aim here)
  final Offset? wildFace; // backdrop fractions (the 'face' camera shot)
  final List<Offset>? wildEyes; // sprite-local fractions (the Sentinel's eye glows)
  final List<Offset>? wildEyesAbs; // the same in backdrop fractions (the eye flashes)
  final double wildHeadY; // top of its head (floating numbers sit above it)
  final double wildBottom; // the ground at its feet
  final double wildGy; // its ground line, sprite-local
  // your Evochi
  final double petLeft, petTop, petWidth, petAr;
  final double petCx, petCy; // its back (where rings and hearts centre)
  final Offset petFace, petHead; // backdrop fractions
  final double petFeetY, petGy;
  final Offset petHeadLocal; // sprite-local fractions (the "!" over its head)

  Offset get wild => Offset(wildCx, wildCy);
  Offset get face => wildFace ?? wild;
  Offset get pet => Offset(petCx, petCy);
}

/// Port of `shotGeometry` in the web build.
ShotGeometry shotGeometry(tr.EncounterView v, Pet pet) {
  final art = AssetManifest.instance!;
  final b = art.trails.battle(v.scene);
  final w = b.w;
  final hh = b.h;
  final c = v.creature;
  final cb = art.trails.battleCreature(c.id);
  // the wild one: its design height from the scene's perspective, capped in width
  final cg = cb.anchor('ground');
  final ct = cb.anchor('top');
  final aWild = b.anchor('wild');
  final aWildTop = b.anchor('wild_top');
  var s = (aWild.dy - aWildTop.dy) / (cg.dy - ct.dy);
  s = math.min(s, ((c.size == 'large' ? 0.8 : 0.4) * w) / cb.w);
  final wl = aWild.dx - cg.dx * s;
  final wt = aWild.dy - cg.dy * s;
  Offset local(Offset p) => Offset(p.dx / cb.w, p.dy / cb.h);
  Offset abs(Offset p) => Offset((wl + p.dx * s) / w, (wt + p.dy * s) / hh);
  // your Evochi: a set width per stage, feet on the scene's mark, its face kept left of the wild one
  final p = art.char(pet.stage).battle!;
  final pg = p.anchor('ground');
  final pf = p.anchor('face');
  final ps = ((petWidthByStage[pet.stage] ?? 0.5) * w) / p.w;
  final aPet = b.anchor('pet');
  final gx = math.min(aPet.dx - 0.035 * w, faceMaxX * w - (pf.dx - pg.dx) * ps);
  final gy = aPet.dy - petLift * hh;
  final pl = gx - pg.dx * ps;
  final pt = gy - pg.dy * ps;
  final head = p.headTop;
  final back = p.anchor('back');
  final eyes = cb.hasAnchor('eye_l');
  return ShotGeometry(
    scene: b,
    creature: cb,
    ar: w / hh,
    wildLeft: wl / w,
    wildTop: wt / hh,
    wildWidth: (cb.w * s) / w,
    wildAr: cb.w / cb.h,
    wildCx: aWild.dx / w,
    wildCy: (aWild.dy - (cg.dy - ct.dy) * s * 0.55) / hh,
    wildFace: cb.hasAnchor('face') ? abs(cb.anchor('face')) : null,
    wildEyes: eyes ? [local(cb.anchor('eye_l')), local(cb.anchor('eye_r'))] : null,
    wildEyesAbs: eyes ? [abs(cb.anchor('eye_l')), abs(cb.anchor('eye_r'))] : null,
    wildHeadY: (wt + ct.dy * s) / hh,
    wildBottom: aWild.dy / hh,
    wildGy: cg.dy / cb.h,
    petLeft: pl / w,
    petTop: pt / hh,
    petWidth: (p.w * ps) / w,
    petAr: p.w / p.h,
    petCx: (pl + back.dx * ps) / w,
    petCy: (pt + back.dy * ps) / hh,
    petFace: Offset((pl + pf.dx * ps) / w, (pt + pf.dy * ps) / hh),
    petHead: Offset((pl + head.dx * ps) / w, (pt + head.dy * ps) / hh),
    petFeetY: gy / hh,
    petGy: pg.dy / p.h,
    petHeadLocal: Offset(head.dx / p.w, head.dy / p.h),
  );
}

// ------------------------------------------------------------------ the clock ----
/// The stage's animation clock. [seconds] is what every animation inside the world reads; it holds
/// still during a hit-stop. [wall] never stops (the meters' tweens and whatever starts during a
/// hit-stop run on it). Notifies once per frame.
class StageClock extends ChangeNotifier {
  double seconds = 0;
  double wall = 0;
  bool _disposed = false;

  void advance(double dt, {required bool frozen}) {
    wall += dt;
    if (!frozen) seconds += dt;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// When a one-shot started and how long it runs. Progress reads the frozen clock, except for the
/// remainder of a hit-stop that was already running when it started (the web pauses only the
/// animations that were running, so a hit reaction fired right after `hitstop` plays through it).
class StageSpan {
  const StageSpan(this.ms, this.start, this.startWall, this.exempt);
  static const none = StageSpan(0, 0, 0, 0);
  final int ms;
  final double start, startWall, exempt; // seconds

  double elapsed(StageClock c) => (c.seconds - start) + math.min(exempt, c.wall - startWall);
  double t(StageClock c) => ms <= 0 ? 1.0 : (elapsed(c) / (ms / 1000)).clamp(0.0, 1.0);
}

// ------------------------------------------------------------------ the controller ----
/// A one-shot animation on something: its name, a counter so the same one can retrigger, and when
/// it runs.
class StageAnim {
  const StageAnim(this.name, this.id, this.span, {this.kind = ''});
  final String name;
  final int id;
  final StageSpan span;
  final String kind; // flash: white | gold | violet; punch: wild | pet
  int get ms => span.ms;
}

/// One effect on the widget layer (the few the canvas does not draw).
class FxItem {
  FxItem({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.span,
    this.cls = '',
    this.text = '',
    this.to,
    this.arc = 0,
    this.itemId,
  });
  final int id;
  final String kind; // float | proj | bubble | buddy
  final double x, y; // backdrop fractions
  final StageSpan span;
  final String cls; // style words: 'good violet', 'bad', 'energy', 'toss'
  final String text;
  final Offset? to; // proj: where it lands
  final double arc; // proj: lift at mid-flight (% of the view height, negative = up)
  final String? itemId; // proj toss: the item thrown
  int get ms => span.ms;
}

/// The live visual state of the stage, poked by the screen's timelines.
class EncounterStage extends ChangeNotifier {
  EncounterStage({required this.reducedMotion});
  final bool reducedMotion;

  String shot = 'wide';
  bool petIn = false; // your Evochi has stepped in from the left
  bool lit = false; // the intro's dark grade has lifted
  bool eyeL = false, eyeR = false; // the Sentinel's eyes
  bool silhouette = false; // the Hollow intro's black silhouette
  bool trembling = false; // the Sentinel's rumble (tremble + dust)
  bool won = false;
  bool hollow = false; // violet aura and grade (a Hollow kind, not yet restored)
  bool phase2 = false;
  bool introDark = false; // the boss intro's vignette (intro-boss and not lit)
  String wildState = '';
  String petExpr = 'default';
  String wildMood = '';
  StageAnim? wildAnim, petAnim, shake, flash, punchAnim;
  double meter = 0; // 0..1
  String meterText = '';
  double energy = 0;
  String energyText = '';
  final List<FxItem> fx = [];

  /// The clock everything inside the world reads (ticked by the view, frozen by [hitstop]).
  final StageClock clock = StageClock();

  /// The canvas effects (null with reduced motion, and until the view mounts the stage).
  StageFx? effects;

  int _ids = 0;
  final List<Timer> _timers = [];
  bool _disposed = false;
  Ticker? _ticker;
  double? _last;
  double _freezeLeft = 0; // ms
  bool _fast = false;
  ShotGeometry? _geometry;
  // the camera, the foreground's parallax and your Evochi's slide: each a tween on the clock
  CamPose _camFrom = const CamPose(1, 0, 0), _camTo = const CamPose(1, 0, 0);
  StageSpan _camSpan = StageSpan.none;
  Curve _camCurve = camCurve;
  CamPose _fgFrom = const CamPose(1, 0, 0), _fgTo = const CamPose(1, 0, 0);
  StageSpan _fgSpan = StageSpan.none;
  Offset _petFrom = Offset.zero, _petTo = Offset.zero;
  StageSpan _petSpan = StageSpan.none;

  ShotGeometry? get geometry => _geometry;

  /// The shot's geometry (the camera needs it); the first one snaps the camera to the current shot.
  set geometry(ShotGeometry? g) {
    final first = _geometry == null && g != null;
    _geometry = g;
    if (first) {
      _camFrom = _camTo = camPose(shot, g!);
      _camSpan = StageSpan.none;
      _fgFrom = _fgTo = fgPose(shot);
      _fgSpan = StageSpan.none;
      _petFrom = _petTo = _petTarget();
      _petSpan = StageSpan.none;
    }
  }

  void _tick() {
    if (!_disposed) notifyListeners();
  }

  Timer _after(int ms, VoidCallback fn) {
    late Timer t;
    t = Timer(Duration(milliseconds: ms), () {
      _timers.remove(t);
      if (!_disposed) fn();
    });
    _timers.add(t);
    return t;
  }

  /// A span starting now (exempt from whatever is left of a running hit-stop).
  StageSpan _span(int ms) => StageSpan(ms, clock.seconds, clock.wall, _freezeLeft / 1000);

  /// Runs [fn] once the clock has passed the end of [span] (a hit-stop stretches the wait).
  void _expire(StageSpan span, VoidCallback fn, [double? seen]) {
    final now = clock.seconds;
    final left = span.ms - span.elapsed(clock) * 1000;
    if (left > 4 && (seen == null || now > seen)) {
      _after(left.ceil(), () => _expire(span, fn, now));
    } else {
      fn();
    }
  }

  // ---------------------------------------------------------------- the clock and the effects
  /// The view hands the stage its ticker: the clock runs, and the effects engine exists (unless
  /// motion is reduced). Both pause for a hit-stop.
  void mount(TickerProvider vsync) {
    unmount();
    if (_disposed) return;
    _last = null;
    _ticker = vsync.createTicker(_onTick)..start();
    if (!reducedMotion) effects = StageFx(vsync: vsync);
  }

  void unmount() {
    _ticker?.dispose();
    _ticker = null;
    effects?.dispose();
    effects = null;
  }

  void _onTick(Duration elapsed) {
    final now = elapsed.inMicroseconds / 1e6;
    final last = _last ?? now;
    _last = now;
    final dt = math.min(0.05, now - last);
    final frozen = _freezeLeft > 0;
    if (frozen) _freezeLeft -= dt * 1000;
    clock.advance(dt, frozen: frozen);
  }

  /// The hit-stop: for a few frames everything on the shot holds still, then carries on.
  void hitstop(int ms) {
    if (ms <= 0) return;
    _freezeLeft = math.max(_freezeLeft, ms.toDouble());
    effects?.freeze(ms);
  }

  // ---------------------------------------------------------------- the camera
  /// Move the camera to a shot: eased (the default), as a cut ([instant]), or 'fast' for the beats
  /// of a turn.
  void setShot(String name, {bool instant = false, String speed = ''}) {
    shot = name;
    _fast = speed == 'fast';
    final g = _geometry;
    if (g != null) {
      final to = camPose(name, g);
      final ms = instant ? 0 : (reducedMotion ? 300 : (_fast ? 340 : to.ms));
      final other = instant ? 0 : (reducedMotion ? 300 : (_fast ? 340 : 1000));
      _camFrom = camAt(clock);
      _camTo = to;
      _camSpan = _span(ms);
      _camCurve = _fast ? fastCurve : camCurve;
      _fgFrom = fgAt(clock);
      _fgTo = fgPose(name);
      _fgSpan = _span(other);
      if (instant) {
        // a cut moves your Evochi too (the web's .cut drops every transition)
        _petFrom = _petTo = _petTarget();
        _petSpan = StageSpan.none;
      } else {
        _retargetPet(other);
      }
    }
    _tick();
  }

  Offset _petTarget() => !petIn ? const Offset(-0.75, 0.14) : (shot == 'wild' ? const Offset(-0.07, 0.04) : Offset.zero);

  /// Your Evochi slides to where the shot and [petIn] put it (a running slide is not restarted).
  void _retargetPet([int? ms]) {
    final to = _petTarget();
    if (to == _petTo) return;
    _petFrom = petSlideAt(clock);
    _petTo = to;
    _petSpan = _span(ms ?? (reducedMotion ? 300 : (_fast ? 340 : 1000)));
  }

  CamPose camAt(StageClock c) => CamPose.lerp(_camFrom, _camTo, _camCurve.transform(_camSpan.t(c)));
  CamPose fgAt(StageClock c) => CamPose.lerp(_fgFrom, _fgTo, _camCurve.transform(_fgSpan.t(c)));
  Offset petSlideAt(StageClock c) => Offset.lerp(_petFrom, _petTo, _camCurve.transform(_petSpan.t(c)))!;

  /// The camera jolts in toward the wild one (or your Evochi) and eases back.
  void punch({String at = 'wild', bool big = false}) {
    if (reducedMotion) return;
    final ms = big ? 720 : 520;
    final a = StageAnim(big ? 'big' : 'punch', ++_ids, _span(ms), kind: at);
    punchAnim = a;
    _tick();
    _expire(a.span, () {
      if (punchAnim?.id == a.id) {
        punchAnim = null;
        _tick();
      }
    });
  }

  // ---------------------------------------------------------------- the sprites
  /// Change several fields at once, then repaint.
  void update(void Function(EncounterStage s) fn) {
    fn(this);
    if (_geometry != null) _retargetPet();
    _tick();
  }

  void retriggerWild(String name, int ms) {
    final a = StageAnim(name, ++_ids, _span(ms));
    wildAnim = a;
    _tick();
    _expire(a.span, () {
      if (wildAnim?.id == a.id) {
        wildAnim = null;
        _tick();
      }
    });
  }

  void retriggerPet(String name, int ms) {
    final a = StageAnim(name, ++_ids, _span(ms));
    petAnim = a;
    _tick();
    _expire(a.span, () {
      if (petAnim?.id == a.id) {
        petAnim = null;
        _tick();
      }
    });
  }

  void doShake({bool big = false}) {
    if (reducedMotion) return;
    final a = StageAnim(big ? 'large' : 'small', ++_ids, _span(big ? 900 : 450));
    shake = a;
    _tick();
    _expire(a.span, () {
      if (shake?.id == a.id) {
        shake = null;
        _tick();
      }
    });
  }

  void doFlash([String kind = 'white']) {
    final a = StageAnim('flash', ++_ids, _span(600), kind: kind);
    flash = a;
    _tick();
    _after(600, () {
      if (flash?.id == a.id) {
        flash = null;
        _tick();
      }
    });
  }

  // ---------------------------------------------------------------- widget effects
  void addFx(FxItem Function(int id, StageSpan span) make, int ms) {
    final added = make(++_ids, _span(ms));
    fx.add(added);
    _tick();
    _expire(added.span, () {
      fx.remove(added);
      _tick();
    });
  }

  void floatText(Offset at, String text, String cls) => addFx((id, span) => FxItem(id: id, kind: 'float', x: at.dx, y: at.dy, span: span, text: text, cls: cls), 1500);

  /// Something travels from [a] to [b] along an arc (the reduced-motion stand-in for a comet).
  void projectile(String cls, Offset a, Offset b, int ms, {double arc = 0, String? itemId}) =>
      addFx((id, span) => FxItem(id: id, kind: 'proj', x: a.dx, y: a.dy, to: b, span: span, cls: cls, arc: arc, itemId: itemId), ms + 80);

  void bubble(Offset p, String text) => addFx((id, span) => FxItem(id: id, kind: 'bubble', x: p.dx, y: p.dy, span: span, text: text), 1300);

  void buddy() => addFx((id, span) => FxItem(id: id, kind: 'buddy', x: 0.14, y: 0.46, span: span), 1900);

  void setMeter(double frac, String text) {
    meter = frac.clamp(0.0, 1.0);
    meterText = text;
    _tick();
  }

  void setEnergy(double frac, String text) {
    energy = frac.clamp(0.0, 1.0);
    energyText = text;
    _tick();
  }

  void clearTimers() {
    for (final t in _timers) {
      t.cancel();
    }
    _timers.clear();
  }

  @override
  void dispose() {
    _disposed = true;
    clearTimers();
    unmount();
    clock.dispose();
    super.dispose();
  }
}

// ------------------------------------------------------------------------ helpers ----
/// Keyframes: [stops] in 0..1 with a value each, [curve] eased within each segment (like a CSS
/// animation's timing function).
double _kf(double t, List<double> stops, List<double> values, [Curve curve = Curves.linear]) {
  if (t <= stops.first) return values.first;
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      final a = stops[i - 1];
      final b = stops[i];
      final f = b == a ? 1.0 : curve.transform(((t - a) / (b - a)).clamp(0.0, 1.0));
      return values[i - 1] + (values[i] - values[i - 1]) * f;
    }
  }
  return values.last;
}

double _tri(double t) => t < 0.5 ? t * 2 : 2 - t * 2; // 0 -> 1 -> 0

/// A camera position: scale about the centre, then a translation in fractions of the world's size.
class CamPose {
  const CamPose(this.scale, this.tx, this.ty, [this.ms = 1000]);
  final double scale;
  final double tx, ty;
  final int ms;
  static CamPose lerp(CamPose a, CamPose b, double t) => CamPose(a.scale + (b.scale - a.scale) * t, a.tx + (b.tx - a.tx) * t, a.ty + (b.ty - a.ty) * t, b.ms);
  @override
  bool operator ==(Object o) => o is CamPose && o.scale == scale && o.tx == tx && o.ty == ty;
  @override
  int get hashCode => Object.hash(scale, tx, ty);
}

/// The camera for a shot (port of the `.enc-cam` rules).
CamPose camPose(String shot, ShotGeometry g) {
  switch (shot) {
    case 'wild':
      return CamPose(1.13, (0.5 - g.wildCx) * 0.4, (0.5 - g.wildCy) * 0.3, 1000);
    case 'pet':
      return CamPose(1.16, (0.5 - g.petCx) * 0.4, (0.5 - g.petCy) * 0.45, 700);
    case 'close':
      return CamPose(1.55, 0.5 - g.wildCx, 0.46 - g.wildCy, 1300);
    case 'face':
      return CamPose(2.3, 0.5 - g.face.dx, 0.48 - g.face.dy, 1400);
    default:
      return const CamPose(1, 0, 0, 1000);
  }
}

/// The foreground layer's parallax for a shot (about 85% / 70% of the world).
CamPose fgPose(String shot) => switch (shot) {
      'wild' => const CamPose(1.09, 0.02, 0.01),
      'pet' => const CamPose(1.08, -0.01, 0.01),
      _ => const CamPose(1, 0, 0),
    };

Matrix4 _poseMatrix(CamPose p, double w, double h) => Matrix4.identity()
  ..scale(p.scale, p.scale)
  ..translate(p.tx * w, p.ty * h);

/// brightness(b) saturate(s) as a colour matrix.
ColorFilter _filter(double b, double s) {
  const lr = 0.213, lg = 0.715, lb = 0.072;
  return ColorFilter.matrix(<double>[
    b * (lr + (1 - lr) * s), b * (lg - lg * s), b * (lb - lb * s), 0, 0, //
    b * (lr - lr * s), b * (lg + (1 - lg) * s), b * (lb - lb * s), 0, 0, //
    b * (lr - lr * s), b * (lg - lg * s), b * (lb + (1 - lb) * s), 0, 0, //
    0, 0, 0, 1, 0,
  ]);
}

const _whiteSilhouette = ColorFilter.mode(Colors.white, BlendMode.srcIn);

/// The gold "!" badge (over the wild one at the intro, over your Evochi when it flinches).
class _Bang extends StatelessWidget {
  const _Bang({required this.size, required this.ms});
  final double size;
  final int ms;
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: ms),
        builder: (_, t, child) {
          final sc = _kf(t, [0, 0.18, 0.26, 0.8, 1], [0, 1.15, 1, 1, 1]);
          final op = _kf(t, [0, 0.1, 0.8, 1], [0, 1, 1, 0]);
          final dy = _kf(t, [0, 0.8, 1], [0, 0, -10]);
          return Opacity(opacity: op, child: Transform.translate(offset: Offset(0, dy), child: Transform.scale(scale: sc, child: child)));
        },
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            gradient: const RadialGradient(center: Alignment(-0.3, -0.4), radius: 0.72, colors: [Color(0xFFFFF4C9), EvochiColor.primary]),
            boxShadow: const [BoxShadow(color: EvochiColor.primaryShadow, offset: Offset(0, 3))],
          ),
          child: Text('!', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: size * 0.65, height: 1, color: EvochiColor.ink)),
        ),
      );
}

// --------------------------------------------------------------------- the stage ----
/// What the stage needs from the screen besides the live [EncounterStage].
class StageProps {
  const StageProps({
    required this.view,
    required this.geometry,
    required this.pet,
    required this.petLevel,
    required this.phase,
    required this.panelHeight,
    required this.title,
    required this.titleSub,
    required this.titleShown,
    required this.onSkip,
  });
  final tr.EncounterView view;
  final ShotGeometry geometry;
  final Pet pet;
  final int petLevel;
  final String phase; // intro | card | play | outro | result
  final double panelHeight; // the panel's height (the view ends 20px above its top)
  final String title;
  final String titleSub;
  final bool titleShown;
  final VoidCallback onSkip;
}

class EncounterStageView extends StatefulWidget {
  const EncounterStageView({super.key, required this.stage, required this.props});
  final EncounterStage stage;
  final StageProps props;
  @override
  State<EncounterStageView> createState() => _EncounterStageViewState();
}

class _EncounterStageViewState extends State<EncounterStageView> with TickerProviderStateMixin {
  // the dust falling while the ruins tremble lives outside the world, on its own loop
  late final AnimationController _dust = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  @override
  void initState() {
    super.initState();
    widget.stage.mount(this);
    widget.stage.addListener(_onStage);
  }

  @override
  void didUpdateWidget(EncounterStageView old) {
    super.didUpdateWidget(old);
    if (old.stage != widget.stage) {
      old.stage.removeListener(_onStage);
      old.stage.unmount();
      widget.stage.mount(this);
      widget.stage.addListener(_onStage);
    }
  }

  void _onStage() {
    final st = widget.stage;
    if (st.trembling && !st.reducedMotion) {
      if (!_dust.isAnimating) _dust.repeat();
    } else {
      if (_dust.isAnimating) _dust.stop();
    }
  }

  @override
  void dispose() {
    widget.stage.removeListener(_onStage);
    widget.stage.unmount();
    _dust.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.props;
    final st = widget.stage;
    final safeTop = MediaQuery.of(context).padding.top;
    final intro = p.phase == 'intro';
    final hollowKind = p.view.creature.kind == 'hollow';
    return LayoutBuilder(builder: (ctx, box) {
      final sw = box.maxWidth;
      final sh = box.maxHeight;
      final bottom = math.max(0.0, p.panelHeight - 20);
      final ph = bottom + 20;
      return Stack(clipBehavior: Clip.hardEdge, children: [
        // the view: the visible part of the shot ends where the panel begins (it overlaps a little)
        AnimatedPositioned(
          duration: const Duration(milliseconds: 550),
          curve: const Cubic(0.3, 0.75, 0.25, 1),
          left: 0,
          right: 0,
          top: 0,
          bottom: bottom,
          child: ClipRect(child: _View(stage: st, props: p, dust: _dust, safeTop: safeTop, hollowKind: hollowKind)),
        ),
        // letterbox bands during the intro
        AnimatedPositioned(
          duration: const Duration(milliseconds: 700),
          curve: const Cubic(0.3, 0.7, 0.3, 1),
          left: 0,
          right: 0,
          top: 0,
          height: intro ? safeTop + sh * 0.07 : 0,
          child: const ColoredBox(color: Color(0xFF120E18)),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 700),
          curve: const Cubic(0.3, 0.7, 0.3, 1),
          left: 0,
          right: 0,
          bottom: 0,
          height: intro ? ph + sh * 0.02 : 0,
          child: const ColoredBox(color: Color(0xFF120E18)),
        ),
        // the intro title sits in the lower letterbox, like a film's caption, clear of the shot
        Positioned(
          left: sw * 0.06,
          width: sw * 0.88,
          top: sh - ph / 2 - 60,
          height: 120,
          child: IgnorePointer(
            child: Center(
              child: _IntroTitle(
                key: ValueKey('${p.title}|${p.titleShown}|$intro'),
                shown: p.titleShown && intro,
                title: p.title,
                sub: p.titleSub,
                hollow: hollowKind,
                boss: p.view.boss,
                reducedMotion: st.reducedMotion,
              ),
            ),
          ),
        ),
        // skip
        Positioned(
          right: 12,
          top: safeTop + 10,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 400),
            opacity: intro ? 1 : 0,
            child: IgnorePointer(
              ignoring: !intro,
              child: Semantics(
                button: true,
                label: 'Skip the intro',
                child: GestureDetector(
                  onTap: p.onSkip,
                  child: Container(
                    height: 36,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0x8C140E1A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0x66FFFFFF), width: 1.5),
                    ),
                    child: const Text('Skip ›', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFFFFF6E6))),
                  ),
                ),
              ),
            ),
          ),
        ),
      ]);
    });
  }
}

/// The view: the world (camera, shake, punch, drift, backdrop, aura, sprites, foreground, effects),
/// then the grade, the flash, the dust, the plates, the ribbon and the caption.
class _View extends StatelessWidget {
  const _View({required this.stage, required this.props, required this.dust, required this.safeTop, required this.hollowKind});
  final EncounterStage stage;
  final StageProps props;
  final AnimationController dust;
  final double safeTop;
  final bool hollowKind;

  @override
  Widget build(BuildContext context) {
    final g = props.geometry;
    final p = props;
    return LayoutBuilder(builder: (ctx, box) {
      final vw = box.maxWidth;
      final vh = box.maxHeight;
      if (vw <= 0 || vh <= 0) return const SizedBox.shrink();
      // the backdrop covers the view (like object-fit: cover), with the focal point low in the shot;
      // a wide, short view (small phones, landscape-ish frames) shows the lower part
      final bw = math.max(vw, vh * g.ar);
      final bh = bw / g.ar;
      final left = (vw - bw) / 2;
      final top = (vh - bh) * (vw / vh > 0.95 ? 0.86 : 0.66);
      // where the wild one and its face land in the view (for the grade and the flash)
      Alignment viewAlign(Offset f) => Alignment(((left + f.dx * bw) / vw) * 2 - 1, ((top + f.dy * bh) / vh) * 2 - 1);
      final wildAlign = viewAlign(g.wild);
      final faceAlign = viewAlign(g.face);
      return AnimatedBuilder(
        animation: stage,
        builder: (ctx, _) {
          final st = stage;
          final hidePlates = p.phase == 'intro' || p.phase == 'result';
          return Stack(clipBehavior: Clip.hardEdge, children: [
            Positioned(
              left: left,
              top: top,
              width: bw,
              height: bh,
              child: _World(stage: st, props: p, bw: bw, bh: bh, vh: vh, hollowKind: hollowKind),
            ),
            // grade: a dark vignette on the sleeping Sentinel, a violet edge while the Hollow holds
            Positioned.fill(
              child: IgnorePointer(
                child: Stack(fit: StackFit.expand, children: [
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 1400),
                    opacity: st.introDark && !st.lit ? 1 : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(center: faceAlign, radius: 1.0, colors: const [Color(0x26120824), Color(0xD1080410)], stops: const [0, 0.7]),
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 1400),
                    opacity: st.hollow ? 1 : 0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(center: wildAlign, radius: 1.1, colors: const [Color(0x007846C8), Color(0x61361C60)], stops: const [0.25, 1]),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            // flash (outside the world: a hit-stop does not hold it)
            if (st.flash != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(st.flash!.id),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 420),
                    builder: (_, t, __) => Opacity(
                      opacity: _kf(t, [0, 0.12, 1], [0, 0.8, 0], Curves.easeOut),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: st.flash!.kind == 'white' ? Colors.white : null,
                          gradient: switch (st.flash!.kind) {
                            'gold' => RadialGradient(center: wildAlign, radius: 0.9, colors: const [Color(0xF2FFF0BE), Color(0x59FFDC8C)], stops: const [0, 0.6]),
                            'violet' => RadialGradient(center: wildAlign, radius: 0.9, colors: const [Color(0xF2E1CDFF), Color(0x73965AE6)], stops: const [0, 0.6]),
                            _ => null,
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            // dust falling while the ruins tremble
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  duration: const Duration(milliseconds: 600),
                  opacity: st.trembling ? 1 : 0,
                  child: AnimatedBuilder(
                    animation: dust,
                    builder: (_, __) => Stack(children: [
                      for (var i = 0; i < 14; i++)
                        Builder(builder: (_) {
                          final third = i % 3 == 2;
                          final period = third ? 1.3 / 1.7 : 1.0;
                          final t = ((dust.value / period) + i * 0.13 / 1.7) % 1.0;
                          return Positioned(
                            left: vw * ((i * 37) % 100) / 100,
                            top: -vh * 0.03 + vh * 1.05 * t,
                            child: Transform.rotate(
                              angle: t * 240 * math.pi / 180,
                              child: Container(
                                width: third ? 6 : 4,
                                height: third ? 5 : 4,
                                decoration: BoxDecoration(color: third ? const Color(0xFFB8AB93) : const Color(0xFFD3C6AE), borderRadius: BorderRadius.circular(1)),
                              ),
                            ),
                          );
                        }),
                    ]),
                  ),
                ),
              ),
            ),
            // the wild one's plate
            Positioned(
              left: 14,
              right: 14,
              top: safeTop + 12,
              child: _PlateFade(hidden: hidePlates, dy: -14, child: _WildPlate(stage: st, view: p.view)),
            ),
            // your Evochi's plate
            Positioned(
              left: 12,
              bottom: 34,
              width: math.min(vw * 0.66, 270),
              child: _PlateFade(hidden: hidePlates, dy: p.phase == 'intro' ? 14 : -14, child: _PetPlate(stage: st, pet: p.pet, level: p.petLevel)),
            ),
            // the result ribbon and the last line as a caption
            Positioned(
              left: 26,
              right: 26,
              top: safeTop + 16,
              child: IgnorePointer(child: _Ribbon(shown: p.phase == 'result', view: p.view, hollow: hollowKind)),
            ),
            Positioned(
              left: 14,
              right: 14,
              bottom: 32,
              child: IgnorePointer(child: _Caption(shown: p.phase == 'result', text: p.view.log.isEmpty ? '' : p.view.log.last.text, names: [p.view.creature.name, p.pet.name])),
            ),
          ]);
        },
      );
    });
  }
}

/// The world: camera, shake, punch and drift around the backdrop, the aura, the back effects, the
/// wild one, your Evochi, the foreground layer, the front effects and the widget effects.
class _World extends StatelessWidget {
  const _World({required this.stage, required this.props, required this.bw, required this.bh, required this.vh, required this.hollowKind});
  final EncounterStage stage;
  final StageProps props;
  final double bw, bh, vh;
  final bool hollowKind;

  @override
  Widget build(BuildContext context) {
    final st = stage;
    final g = props.geometry;
    final rm = st.reducedMotion;
    final clock = st.clock;
    final fx = st.effects;
    fx?.resize(bw, bh);
    final layers = Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: Image.asset(g.scene.file, fit: BoxFit.fill, excludeFromSemantics: true, gaplessPlayback: true, filterQuality: FilterQuality.medium)),
      // the Hollow's aura (gold once it's restored or befriended)
      Positioned(
        left: g.wildCx * bw - bw * 0.31,
        top: g.wildCy * bh - bw * 0.31,
        width: bw * 0.62,
        height: bw * 0.62,
        child: IgnorePointer(
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 1000),
            opacity: st.hollow || st.won ? 1 : 0,
            child: AnimatedBuilder(
              animation: clock,
              builder: (_, __) {
                final period = st.won ? 1.8 : (st.phase2 ? 1.2 : 2.6);
                final pulse = rm ? 1.0 : 0.55 + 0.45 * (0.5 - 0.5 * math.cos(2 * math.pi * (clock.seconds % period) / period));
                return Opacity(
                  opacity: pulse,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: st.won ? const [Color(0xB3FFECA0), Color(0x00FFECA0)] : const [Color(0x6BAA6EFF), Color(0x00AA6EFF)]),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
      // the light behind the creatures
      if (fx != null) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: StageFxPainter(fx, layer: 'back'), size: Size.infinite, willChange: true))),
      // the wild one
      Positioned(left: g.wildLeft * bw, top: g.wildTop * bh, width: g.wildWidth * bw, child: _WildBody(stage: st, props: props, width: g.wildWidth * bw, hollowKind: hollowKind)),
      // your Evochi, sliding in from off-left (and a touch right/down on the wild shot)
      Positioned(
        left: g.petLeft * bw,
        top: g.petTop * bh,
        width: g.petWidth * bw,
        child: AnimatedBuilder(
          animation: clock,
          builder: (_, child) => FractionalTranslation(translation: st.petSlideAt(clock), child: child),
          child: _PetBody(stage: st, props: props, width: g.petWidth * bw, hollowKind: hollowKind),
        ),
      ),
      // the foreground layer, scaled a touch more than the backdrop for parallax
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: clock,
            builder: (_, child) => Transform(origin: Offset(bw * 0.85, bh * 0.7), transform: _poseMatrix(st.fgAt(clock), bw, bh), child: child),
            child: Image.asset(g.scene.fg, fit: BoxFit.fill, excludeFromSemantics: true, gaplessPlayback: true, filterQuality: FilterQuality.medium),
          ),
        ),
      ),
      // the light in front of them
      if (fx != null) Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: StageFxPainter(fx, layer: 'front'), size: Size.infinite, willChange: true))),
      // the widget effects (numbers, the "?" bubble, Petalune)
      Positioned.fill(child: IgnorePointer(child: _FxLayer(stage: st, bw: bw, bh: bh, vh: vh))),
    ]);
    // drift (a slow 16 s push-in and back), the punch, the shake, then the camera
    Widget world = AnimatedBuilder(
      animation: clock,
      builder: (_, child) {
        if (rm) return child!;
        final t = Curves.easeInOut.transform(_tri((clock.seconds % 32) / 32));
        return Transform(
          alignment: Alignment.center,
          transform: Matrix4.identity()
            ..scale(1 + 0.03 * t, 1 + 0.03 * t)
            ..translate(-0.007 * t * bw, -0.005 * t * bh),
          child: child,
        );
      },
      child: layers,
    );
    world = _PunchLayer(stage: st, geometry: g, bw: bw, bh: bh, child: world);
    world = _ShakeLayer(stage: st, child: world);
    return AnimatedBuilder(
      animation: clock,
      builder: (_, child) => Transform(alignment: Alignment.center, transform: _poseMatrix(st.camAt(clock), bw, bh), child: child),
      child: world,
    );
  }
}

/// The camera punch: a jolt in toward the point of impact (the wild one or your Evochi), easing back.
class _PunchLayer extends StatelessWidget {
  const _PunchLayer({required this.stage, required this.geometry, required this.bw, required this.bh, required this.child});
  final EncounterStage stage;
  final ShotGeometry geometry;
  final double bw, bh;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final a = stage.punchAnim;
    if (a == null) return child;
    final g = geometry;
    final origin = a.kind == 'pet' ? Offset(g.petCx * bw, g.petCy * bh) : Offset(g.wildCx * bw, g.wildCy * bh);
    final amp = a.name == 'big' ? 0.13 : 0.06;
    final clock = stage.clock;
    return AnimatedBuilder(
      animation: clock,
      builder: (_, c) {
        final k = 1 - punchCurve.transform(a.span.t(clock));
        final s = 1 + amp * k;
        return Transform(origin: origin, transform: Matrix4.identity()..scale(s, s), child: c);
      },
      child: child,
    );
  }
}

/// Small and large shakes, and the Sentinel's continuous tremble.
class _ShakeLayer extends StatelessWidget {
  const _ShakeLayer({required this.stage, required this.child});
  final EncounterStage stage;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final sh = stage.shake;
    final clock = stage.clock;
    Widget w = child;
    if (sh != null) {
      final big = sh.name == 'large';
      w = AnimatedBuilder(
        animation: clock,
        builder: (_, c) {
          final t = sh.span.t(clock);
          final curve = big ? const Cubic(0.3, 0.6, 0.4, 1) : Curves.linear;
          final dx = big ? _kf(t, [0, .1, .22, .36, .5, .66, .82, 1], [0, -12, 11, -8, 6, -4, 2, 0], curve) : _kf(t, [0, .2, .4, .6, .8, 1], [0, -5, 5, -3, 2, 0]);
          final dy = big ? _kf(t, [0, .1, .22, .36, .5, .66, .82, 1], [0, 6, -7, -5, 5, 2, -2, 0], curve) : _kf(t, [0, .2, .4, .6, .8, 1], [0, 3, -2, -3, 2, 0]);
          final rot = big ? _kf(t, [0, .1, .22, .36, 1], [0, -0.6, 0.5, 0, 0], curve) * _deg : 0.0;
          return Transform.translate(offset: Offset(dx, dy), child: Transform.rotate(angle: rot, child: c));
        },
        child: w,
      );
    }
    if (stage.trembling && !stage.reducedMotion) {
      w = AnimatedBuilder(
        animation: clock,
        builder: (_, c) {
          final t = (clock.seconds / 0.16) % 1.0;
          return Transform.translate(
            offset: Offset(_kf(t, [0, .25, .5, .75, 1], [0, -1.5, 1.5, -1, 0]), _kf(t, [0, .25, .5, .75, 1], [0, 1, -1, -1.5, 0])),
            child: c,
          );
        },
        child: w,
      );
    }
    return w;
  }
}

/// A soft ground shadow under a sprite.
class _GroundShadow extends StatelessWidget {
  const _GroundShadow({required this.width, required this.height, required this.gy});
  final double width, height, gy;
  @override
  Widget build(BuildContext context) => Positioned(
        left: width * 0.2,
        width: width * 0.6,
        top: height * (gy - 0.05),
        height: height * 0.1,
        child: const DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0x801C160E), Color(0x001C160E)])),
        ),
      );
}

/// The wild one: its sprite in its current state (crossfading, except when it comes back restored),
/// idle breathing (or a wary shiver), the one-shot reactions, the Hollow silhouette, the Sentinel's
/// eye glows and the intro "!".
class _WildBody extends StatelessWidget {
  const _WildBody({required this.stage, required this.props, required this.width, required this.hollowKind});
  final EncounterStage stage;
  final StageProps props;
  final double width;
  final bool hollowKind;

  @override
  Widget build(BuildContext context) {
    final g = props.geometry;
    final st = stage;
    final height = width / g.wildAr;
    final cb = g.creature;
    final state = st.wildState.isEmpty ? props.view.stateKey : st.wildState;
    final rm = st.reducedMotion;
    final sprite = Image.asset(cb.state(state), key: ValueKey(state), width: width, height: height, fit: BoxFit.fill, excludeFromSemantics: true, gaplessPlayback: true, filterQuality: FilterQuality.medium);
    // the restored (or befriended) one pops in as a cut, like the web's src swap
    Widget img = st.won ? sprite : AnimatedSwitcher(duration: const Duration(milliseconds: 500), child: sprite);
    if (st.silhouette) {
      img = ColorFiltered(colorFilter: const ColorFilter.mode(Color(0xFF05030A), BlendMode.srcIn), child: img);
    }
    final eyes = g.wildEyes;
    final body = Stack(clipBehavior: Clip.none, children: [
      if (st.silhouette)
        // a violet rim light behind the black shape (the web's drop-shadow)
        Positioned(
          left: -width * 0.08,
          top: -height * 0.06,
          width: width * 1.16,
          height: height * 1.12,
          child: const DecoratedBox(
            decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Color(0xD9AA6EFF), Color(0x40AA6EFF), Color(0x00AA6EFF)], stops: [0.3, 0.62, 0.85])),
          ),
        ),
      img,
      if (eyes != null)
        for (var i = 0; i < eyes.length; i++)
          Positioned(
            left: eyes[i].dx * width - width * 0.05,
            top: eyes[i].dy * height - width * 0.1 / 1.5 / 2,
            width: width * 0.1,
            height: width * 0.1 / 1.5,
            child: _EyeGlow(on: (i == 0 ? st.eyeL : st.eyeR) && !st.won, pulsing: st.lit && st.eyeR && !st.won, clock: st.clock, rm: rm),
          ),
      if (st.wildAnim?.name == 'bang')
        Positioned(left: width / 2 - 20, top: -height * 0.04 - 20, child: const _Bang(size: 40, ms: 1600)),
    ]);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(clipBehavior: Clip.none, children: [
        _GroundShadow(width: width, height: height, gy: g.wildGy),
        Positioned.fill(
          child: _AnimatedBody(
            anim: st.wildAnim?.name == 'bang' ? null : st.wildAnim,
            clock: st.clock,
            rm: rm,
            idleKind: st.wildMood == 'wary' && st.wildAnim == null ? 'shiver' : 'wild',
            child: body,
          ),
        ),
      ]),
    );
  }
}

class _EyeGlow extends StatelessWidget {
  const _EyeGlow({required this.on, required this.pulsing, required this.clock, required this.rm});
  final bool on;
  final bool pulsing;
  final StageClock clock;
  final bool rm;
  @override
  Widget build(BuildContext context) {
    const eye = CustomPaint(painter: _EyePainter());
    if (on && pulsing && !rm) {
      // lit: a slow glow
      return AnimatedBuilder(
        animation: clock,
        builder: (_, child) {
          final t = 0.5 - 0.5 * math.cos(2 * math.pi * (clock.seconds % 2.8) / 2.8);
          return Opacity(opacity: 0.45 + 0.4 * t, child: Transform.scale(scale: 1.1 + 0.25 * t, child: child));
        },
        child: eye,
      );
    }
    // waking: a soft fade and swell
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 1500),
      curve: Curves.easeIn,
      opacity: on ? 1 : 0,
      child: AnimatedScale(duration: const Duration(milliseconds: 1500), curve: const Cubic(0.2, 0.8, 0.2, 1), scale: on ? 1.5 : 0.3, child: eye),
    );
  }
}

class _EyePainter extends CustomPainter {
  const _EyePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..blendMode = BlendMode.screen
      ..shader = const RadialGradient(
        colors: [Colors.white, Colors.white, Color(0xFFEADCFF), Color(0xCCBE96FF), Color(0x00AA78FF)],
        stops: [0, 0.22, 0.4, 0.62, 1],
      ).createShader(rect);
    canvas.drawOval(rect, paint);
  }

  @override
  bool shouldRepaint(_EyePainter old) => false;
}

/// Your Evochi: the battle sprite with its expression and wearables, breathing, its one-shot moves,
/// and the "!" over its head when it flinches.
class _PetBody extends StatelessWidget {
  const _PetBody({required this.stage, required this.props, required this.width, required this.hollowKind});
  final EncounterStage stage;
  final StageProps props;
  final double width;
  final bool hollowKind;

  @override
  Widget build(BuildContext context) {
    final g = props.geometry;
    final st = stage;
    final pet = props.pet;
    final height = width / g.petAr;
    final body = Stack(clipBehavior: Clip.none, children: [
      BattleSprite(stage: pet.stage, palette: pet.paletteId, expr: st.petExpr, overlays: pet.equipped.values.toList(), width: width),
      if (st.petAnim?.name == 'flinch')
        Positioned(left: g.petHeadLocal.dx * width - 19, top: g.petHeadLocal.dy * height - 46, child: const _Bang(size: 38, ms: 1300)),
    ]);
    return SizedBox(
      width: width,
      height: height,
      child: Stack(clipBehavior: Clip.none, children: [
        _GroundShadow(width: width, height: height, gy: g.petGy),
        Positioned.fill(
          child: _AnimatedBody(
            anim: st.petAnim,
            clock: st.clock,
            rm: st.reducedMotion,
            idleKind: 'pet',
            child: body,
          ),
        ),
      ]),
    );
  }
}

/// A sprite body: its idle loop, or the one-shot reaction playing over it (transform, brightness and
/// saturation, opacity, the white silhouette flash), per the web's keyframes with their timing
/// function eased within each segment. The transform origin is 50% / 92%. With reduced motion the
/// bodies hold still, like the web.
class _AnimatedBody extends StatelessWidget {
  const _AnimatedBody({required this.anim, required this.clock, required this.rm, required this.idleKind, required this.child});
  final StageAnim? anim;
  final StageClock clock;
  final bool rm;
  final String idleKind; // wild | shiver | pet
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (rm) return child;
    final a = anim;
    if (a == null) {
      return AnimatedBuilder(
        animation: clock,
        builder: (_, c) {
          final s = clock.seconds;
          switch (idleKind) {
            case 'shiver':
              // a wary one shivers side to side
              final t = s % 1.0;
              return FractionalTranslation(translation: Offset(_kf(t, [0, .25, .75, 1], [0, 1.2, -1.2, 0]) / 100, 0), child: c);
            case 'pet':
              // pBreath 2.6s
              final t = 0.5 - 0.5 * math.cos(2 * math.pi * (s % 2.6) / 2.6);
              return FractionalTranslation(
                translation: Offset(0, -0.008 * t),
                child: Transform(alignment: const Alignment(0, 0.84), transform: Matrix4.identity()..scale(1 + 0.012 * t, 1 + 0.03 * t), child: c),
              );
            default:
              // wIdle 2.8s: a bigger bob
              final t = 0.5 - 0.5 * math.cos(2 * math.pi * (s % 2.8) / 2.8);
              return FractionalTranslation(
                translation: Offset(0, -0.024 * t),
                child: Transform(alignment: const Alignment(0, 0.84), transform: Matrix4.identity()..scale(1 + 0.02 * t, 1 - 0.02 * t), child: c),
              );
          }
        },
        child: child,
      );
    }
    return AnimatedBuilder(
      animation: clock,
      builder: (_, c) {
        final t = a.span.t(clock);
        var dx = 0.0, dy = 0.0, sx = 1.0, sy = 1.0, rot = 0.0, op = 1.0, bright = 1.0, sat = 1.0, white = 0.0;
        switch (a.name) {
          case 'hit':
            // wHit .6s cubic-bezier(.2,.8,.3,1.1): knocked back and squashed, then it settles
            const cv = Cubic(0.2, 0.8, 0.3, 1.1);
            const st = [0.0, .14, .4, .7, 1.0];
            dx = _kf(t, st, [0, .10, .06, .015, 0], cv);
            dy = _kf(t, st, [0, -.01, 0, 0, 0], cv);
            rot = _kf(t, st, [0, 4, 0, 0, 0], cv) * _deg;
            sx = _kf(t, st, [1, 1.16, .94, 1.02, 1], cv);
            sy = _kf(t, st, [1, .84, 1.07, .98, 1], cv);
            // wFlash .5s steps(1, end): two hard white frames
            final fm = t * a.ms;
            if (fm < 70) {
              white = 1;
            } else if (fm >= 130 && fm < 190) {
              white = 1;
              op = 0.75;
            }
          case 'look':
            // wLook 1.5s ease-in-out
            const st = [0.0, .35, .7, 1.0];
            rot = _kf(t, st, [0, -3, 1.5, 0], Curves.easeInOut) * _deg;
            dx = _kf(t, st, [0, .015, 0, 0], Curves.easeInOut);
            dy = _kf(t, st, [0, -.01, 0, 0], Curves.easeInOut);
          case 'perk':
            // wPerk .7s cubic-bezier(.3,.7,.3,1.2)
            const cv = Cubic(0.3, 0.7, 0.3, 1.2);
            const st = [0.0, .3, .6, 1.0];
            dy = _kf(t, st, [0, -.07, 0, 0], cv);
            sx = _kf(t, st, [1, .97, 1.04, 1], cv);
            sy = _kf(t, st, [1, 1.05, .96, 1], cv);
          case 'munch':
            // wMunch .8s ease-in-out: three chew bounces
            const st = [0.0, .16, .32, .48, .64, .8, 1.0];
            sx = _kf(t, st, [1, 1.1, .95, 1.08, .96, 1.05, 1], Curves.easeInOut);
            sy = _kf(t, st, [1, .9, 1.07, .92, 1.05, .95, 1], Curves.easeInOut);
          case 'lunge' when idleKind != 'pet':
            // wLunge .9s cubic-bezier(.3,.7,.3,1): a crouch, then a lunge toward the camera
            const cv = Cubic(0.3, 0.7, 0.3, 1);
            const st = [0.0, .17, .33, .44, 1.0];
            dx = _kf(t, st, [0, .05, -.20, -.16, 0], cv);
            dy = _kf(t, st, [0, .01, .08, .06, 0], cv);
            sx = _kf(t, st, [1, .94, 1.24, 1.18, 1], cv);
            sy = _kf(t, st, [1, 1.05, 1.24, 1.18, 1], cv);
          case 'pop':
            // wPop .7s cubic-bezier(.2,1.5,.3,1) with wBorn: a bright, washed-out fade-in
            sx = sy = _kf(t, [0, 1], [.7, 1], const Cubic(0.2, 1.5, 0.3, 1));
            bright = _kf(t, [0, 1], [4, 1], Curves.easeOut);
            sat = _kf(t, [0, 1], [.2, 1], Curves.easeOut);
          case 'dissolve':
            // wDissolve .58s ease-in: brightness up, then a white silhouette, then gone
            const st = [0.0, .3, .55, 1.0];
            bright = _kf(t, st, [1, 2.8, 2.8, 2.8], Curves.easeIn);
            white = _kf(t, st, [0, 0, 1, 1], Curves.easeIn);
            op = _kf(t, st, [1, 1, 1, 0], Curves.easeIn);
          case 'skitter':
            // wSkitter .9s ease-in-out
            const st = [0.0, .3, .55, 1.0];
            dx = _kf(t, st, [0, .16, .10, 0], Curves.easeInOut);
            sx = sy = _kf(t, st, [1, .94, .96, 1], Curves.easeInOut);
          case 'tilt':
            // wTilt .9s ease-in-out
            const st = [0.0, .4, .7, 1.0];
            rot = _kf(t, st, [0, -8, 4, 0], Curves.easeInOut) * _deg;
            dy = _kf(t, st, [0, -.02, 0, 0], Curves.easeInOut);
          case 'surge':
            // wSurge .9s ease-in-out
            const st = [0.0, .2, .45, 1.0];
            sx = _kf(t, st, [1, .96, 1.12, 1], Curves.easeInOut);
            sy = _kf(t, st, [1, 1.03, 1.08, 1], Curves.easeInOut);
            bright = _kf(t, st, [1, 1, 1.4, 1], Curves.easeInOut);
          case 'flicker':
            // wFlicker .9s steps(6)
            final step = (t * 6).floor() / 6;
            op = _kf(step, [0, .2, .4, .6, .8, 1], [1, 0.55, 1, 0.4, 0.9, 1]);
          case 'joy' || 'hop':
            // wJoy: three hops in a row (.6s ease-in-out), two for your Evochi (.5s)
            final reps = a.name == 'joy' ? 3 : 2;
            final hop = math.min(0.999999, t * a.ms / (a.name == 'joy' ? 600 : 500)) % 1.0;
            final cv = a.name == 'joy' ? Curves.easeInOut : const Cubic(0.3, 0.6, 0.3, 1);
            final done = t * a.ms >= reps * (a.name == 'joy' ? 600 : 500);
            if (!done) {
              dy = _kf(hop, [0, .4, .7, 1], [0, -.09, 0, 0], cv);
              sx = _kf(hop, [0, .4, .7, 1], [1, .97, 1.05, 1], cv);
              sy = _kf(hop, [0, .4, .7, 1], [1, 1.04, .95, 1], cv);
            }
          case 'cast':
            // pCast .72s cubic-bezier(.3,.6,.3,1): a crouch, a rise with a glow, a settle
            const cv = Cubic(0.3, 0.6, 0.3, 1);
            const st = [0.0, .2, .42, .62, 1.0];
            dy = _kf(t, st, [0, .04, -.11, -.07, 0], cv);
            sx = _kf(t, st, [1, 1.09, .94, .99, 1], cv);
            sy = _kf(t, st, [1, .89, 1.11, 1.04, 1], cv);
            rot = _kf(t, st, [0, 0, -2, 0, 0], cv) * _deg;
            bright = _kf(t, st, [1, 1, 1.5, 1.3, 1], cv);
          case 'lunge':
            // pLunge .9s cubic-bezier(.2,.7,.3,1): a crouch, a hop into it, a landing squash
            const cv = Cubic(0.2, 0.7, 0.3, 1);
            const st = [0.0, .2, .34, .42, .7, 1.0];
            dx = _kf(t, st, [0, -.05, .34, .30, .04, 0], cv);
            dy = _kf(t, st, [0, .02, -.11, -.06, 0, 0], cv);
            sx = _kf(t, st, [1, 1.06, .94, 1.1, .98, 1], cv);
            sy = _kf(t, st, [1, .92, 1.08, .9, 1.02, 1], cv);
          case 'rest':
            // pRest 1.3s ease-in-out
            const st = [0.0, .4, .7, 1.0];
            dy = _kf(t, st, [0, .03, -.01, 0], Curves.easeInOut);
            sx = _kf(t, st, [1, 1.05, .99, 1], Curves.easeInOut);
            sy = _kf(t, st, [1, .94, 1.02, 1], Curves.easeInOut);
          case 'toss':
            // pToss .6s cubic-bezier(.3,.7,.3,1)
            const cv = Cubic(0.3, 0.7, 0.3, 1);
            const st = [0.0, .25, .5, 1.0];
            dy = _kf(t, st, [0, .02, -.07, 0], cv);
            sx = _kf(t, st, [1, 1.04, .97, 1], cv);
            sy = _kf(t, st, [1, .95, 1.05, 1], cv);
            rot = _kf(t, st, [0, 0, -3, 0], cv) * _deg;
          case 'hurt':
            // pHurt .75s cubic-bezier(.2,.8,.3,1): a recoil with a white-ish flash
            const cv = Cubic(0.2, 0.8, 0.3, 1);
            const st = [0.0, .12, .4, .65, 1.0];
            dx = _kf(t, st, [0, -.15, -.09, .03, 0], cv);
            dy = _kf(t, st, [0, .03, 0, 0, 0], cv);
            rot = _kf(t, st, [0, -8, -3, 1, 0], cv) * _deg;
            sx = _kf(t, st, [1, 1.1, .96, 1, 1], cv);
            sy = _kf(t, st, [1, .86, 1.04, 1, 1], cv);
            bright = _kf(t, [0, .12, .24, 1], [1, 2.6, 1, 1], cv);
            sat = _kf(t, [0, .12, .24, 1], [1, .2, 1, 1], cv);
          case 'flinch':
            // pFlinch 1.1s cubic-bezier(.3,.7,.3,1)
            const cv = Cubic(0.3, 0.7, 0.3, 1);
            const st = [0.0, .22, .4, .6, 1.0];
            dx = _kf(t, st, [0, -.06, -.07, -.04, 0], cv);
            dy = _kf(t, st, [0, -.09, 0, 0, 0], cv);
            sx = _kf(t, st, [1, 1, 1.04, 1, 1], cv);
            sy = _kf(t, st, [1, 1, .95, 1, 1], cv);
        }
        Widget w = c!;
        if (bright != 1 || sat != 1) w = ColorFiltered(colorFilter: _filter(bright, sat), child: w);
        if (white >= 1) {
          w = ColorFiltered(colorFilter: _whiteSilhouette, child: c);
        } else if (white > 0) {
          w = Stack(clipBehavior: Clip.none, children: [
            w,
            Positioned.fill(child: Opacity(opacity: white, child: ColorFiltered(colorFilter: _whiteSilhouette, child: c))),
          ]);
        }
        w = Transform(
          alignment: const Alignment(0, 0.84),
          transform: Matrix4.identity()
            ..rotateZ(rot)
            ..scale(sx, sy),
          child: w,
        );
        if (op != 1) w = Opacity(opacity: op, child: w);
        return FractionalTranslation(translation: Offset(dx, dy), child: w);
      },
      child: child,
    );
  }
}

// ------------------------------------------------------------------------ effects ----
/// The few effects the canvas does not draw: floating numbers, the "?" bubble, Petalune swooping
/// in, and the reduced-motion item toss.
class _FxLayer extends StatelessWidget {
  const _FxLayer({required this.stage, required this.bw, required this.bh, required this.vh});
  final EncounterStage stage;
  final double bw, bh, vh;
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        for (final f in stage.fx) _FxWidget(key: ValueKey('fx-${f.id}'), fx: f, clock: stage.clock, bw: bw, bh: bh, vh: vh),
      ]);
}

class _FxWidget extends StatelessWidget {
  const _FxWidget({super.key, required this.fx, required this.clock, required this.bw, required this.bh, required this.vh});
  final FxItem fx;
  final StageClock clock;
  final double bw, bh, vh;

  bool _has(String word) => fx.cls.split(' ').contains(word);

  @override
  Widget build(BuildContext context) {
    final f = fx;
    final x = f.x * bw;
    final y = f.y * bh;
    switch (f.kind) {
      case 'float':
        // encFloat 1.4s cubic-bezier(.2,.8,.3,1): pops in big, settles, rises and fades
        final violet = _has('violet');
        final bad = _has('bad');
        final energy = _has('energy');
        final colors = bad
            ? const [Color(0xFFF4A291), Color(0xFFD85F51)]
            : energy
                ? const [Color(0xFFFFE08A), Color(0xFFEBA73A)]
                : violet
                    ? const [Color(0xFFCDB2F5), Color(0xFF8B5FD2)]
                    : const [Color(0xFFA8E07E), Color(0xFF57A845)];
        const cv = Cubic(0.2, 0.8, 0.3, 1);
        return Positioned(
          left: x,
          top: y,
          child: AnimatedBuilder(
            animation: clock,
            builder: (_, child) {
              final t = (f.span.elapsed(clock) / 1.4).clamp(0.0, 1.0);
              final op = _kf(t, [0, .12, .7, 1], [0, 1, 1, 0], cv);
              final ty = _kf(t, [0, .12, .24, .7, 1], [-0.7, -1.28, -1.16, -1.5, -2.6], cv);
              final sc = _kf(t, [0, .12, .24, 1], [0.4, 1.28, 1, 0.9], cv);
              return Opacity(opacity: op, child: FractionalTranslation(translation: Offset(-0.5, ty), child: Transform.scale(scale: sc, child: child)));
            },
            child: Container(
              padding: const EdgeInsets.fromLTRB(11, 3, 11, 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: Colors.white, width: 2.5),
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors),
                boxShadow: const [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Text(
                f.text,
                style: TextStyle(
                  fontFamily: EvochiText.game,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  color: energy ? const Color(0xFF5A3A10) : Colors.white,
                  shadows: energy ? null : const [Shadow(color: Color(0x40000000), offset: Offset(0, 1), blurRadius: 1)],
                ),
              ),
            ),
          ),
        );
      case 'proj':
        // the reduced-motion toss: the item along an arc, turning over
        final to = f.to ?? Offset(f.x, f.y);
        final dx = (to.dx - f.x) * bw;
        final dy = (to.dy - f.y) * bh;
        final arcPx = f.arc / 100 * vh;
        final ms = math.max(1, f.ms - 80);
        final inner = f.itemId == null ? const SizedBox.shrink() : ItemImage(f.itemId!, size: 44);
        return Positioned(
          left: x,
          top: y,
          child: AnimatedBuilder(
            animation: clock,
            builder: (_, child) {
              final t = (f.span.elapsed(clock) * 1000 / ms).clamp(0.0, 1.0);
              final m = const Cubic(0.45, 0.05, 0.55, 0.95).transform(t);
              final lift = math.sin(t * math.pi) * arcPx;
              return Transform.translate(
                offset: Offset(dx * m, dy * m + lift),
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: Transform.rotate(angle: t * ms / 700 * 2 * math.pi, child: child),
                ),
              );
            },
            child: inner,
          ),
        );
      case 'bubble':
        // bubblePop 1.3s ease-out
        return Positioned(
          left: x - 17,
          top: y - 17,
          child: AnimatedBuilder(
            animation: clock,
            builder: (_, child) {
              final t = f.span.t(clock);
              final sc = _kf(t, [0, .18, .3, 1], [0, 1.15, 1, 1], Curves.easeOut);
              final op = _kf(t, [0, .1, .8, 1], [0, 1, 1, 0], Curves.easeOut);
              final dy = _kf(t, [0, .8, 1], [0, 0, -10], Curves.easeOut);
              return Opacity(opacity: op, child: Transform.translate(offset: Offset(0, dy), child: Transform.scale(scale: sc, child: child)));
            },
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(topLeft: Radius.circular(17), topRight: Radius.circular(17), bottomRight: Radius.circular(17), bottomLeft: Radius.circular(8)),
                boxShadow: [BoxShadow(color: Color(0x40000000), blurRadius: 8, offset: Offset(0, 3))],
              ),
              child: Text(f.text, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 21, color: Color(0xFF5B3AA0), height: 1)),
            ),
          ),
        );
      case 'buddy':
        // buddyIn 1.9s ease-in-out: Petalune swoops in from the left and away again
        final w = bw * 0.26;
        return Positioned(
          left: x,
          top: y,
          child: AnimatedBuilder(
            animation: clock,
            builder: (_, child) {
              final t = f.span.t(clock);
              final tx = _kf(t, [0, .2, .75, 1], [-0.9, -0.3, -0.3, -0.9], Curves.easeInOut);
              final ty = _kf(t, [0, .2, .75, 1], [0.4, -0.4, -0.46, 0.4], Curves.easeInOut);
              final rot = _kf(t, [0, .2, .75, 1], [-10, 4, -3, 0], Curves.easeInOut) * _deg;
              final op = _kf(t, [0, .2, .75, 1], [0, 1, 1, 0], Curves.easeInOut);
              return Opacity(opacity: op, child: FractionalTranslation(translation: Offset(tx, ty), child: Transform.rotate(angle: rot, child: child)));
            },
            child: SizedBox(width: w, height: w, child: VoxelIcon('creature_petalune', size: w)),
          ),
        );
    }
    return const SizedBox.shrink();
  }
}

// ------------------------------------------------------------------------- plates ----
/// A plate fades and slides out of the way during the intro and the result.
class _PlateFade extends StatelessWidget {
  const _PlateFade({required this.hidden, required this.dy, required this.child});
  final bool hidden;
  final double dy;
  final Widget child;
  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: hidden,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 500),
          opacity: hidden ? 0 : 1,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 500),
            curve: const Cubic(0.3, 0.8, 0.3, 1.2),
            offset: Offset(0, hidden ? dy / 60 : 0),
            child: child,
          ),
        ),
      );
}

BoxDecoration _plateDecoration() => BoxDecoration(
      gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFFCF6), Color(0xFFFBF1E3)]),
      border: Border.all(color: const Color(0xFFEBD8C1), width: 2),
      borderRadius: BorderRadius.circular(16),
      boxShadow: const [BoxShadow(color: Color(0xF2D0B89C), offset: Offset(0, 4)), BoxShadow(color: Color(0x471E1208), blurRadius: 22, offset: Offset(0, 10))],
    );

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.bg, required this.ring, this.size = 42});
  final String icon;
  final Color bg;
  final Color ring;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(shape: BoxShape.circle, color: bg, border: Border.all(color: ring, width: 2), boxShadow: const [BoxShadow(color: Color(0x14000000), offset: Offset(0, 2))]),
        child: VoxelIcon(icon, size: size * 0.81),
      );
}

/// A meter: a rounded bar with its label inside the fill and the value to the right.
class StageMeter extends StatelessWidget {
  const StageMeter({super.key, required this.kind, required this.label, required this.frac, required this.value, this.labelInside = true});
  final String kind; // calm | inst | energy
  final String label;
  final double frac;
  final String value;
  final bool labelInside;
  @override
  Widget build(BuildContext context) {
    final energy = kind == 'energy';
    final h = energy ? 12.0 : 24.0;
    final track = switch (kind) {
      'inst' => const Color(0xFF4C3F60),
      'energy' => const Color(0xFF5E4A36),
      _ => const Color(0xFF6E6A50),
    };
    final fillColors = switch (kind) {
      'inst' => const [Color(0xFFDECBFA), Color(0xFFA47BE6), Color(0xFF7B48C4)],
      'energy' => const [Color(0xFFFFE8A0), Color(0xFFF7C548), Color(0xFFE9A535)],
      _ => const [Color(0xFFC3F2A4), Color(0xFF74C95A), Color(0xFF4FA544)],
    };
    return Semantics(
      label: '$label $value',
      child: ExcludeSemantics(
        child: Row(children: [
          Expanded(
            child: Container(
              height: h,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(color: track, borderRadius: BorderRadius.circular(h / 2)),
              child: Stack(children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: frac, end: frac),
                  duration: const Duration(milliseconds: 700),
                  curve: const Cubic(0.3, 0.8, 0.3, 1),
                  builder: (_, t, __) => FractionallySizedBox(
                    widthFactor: t.clamp(0.0, 1.0),
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(h / 2),
                        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: fillColors, stops: const [0, 0.55, 1]),
                      ),
                    ),
                  ),
                ),
                if (labelInside)
                  Positioned(
                    left: 11,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Text(label,
                          style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13.5, color: Colors.white, shadows: [Shadow(color: Color(0x66000000), offset: Offset(0, 1), blurRadius: 1)])),
                    ),
                  ),
              ]),
            ),
          ),
          SizedBox(width: energy ? 8 : 10),
          ConstrainedBox(
            constraints: BoxConstraints(minWidth: energy ? 0 : 62),
            child: Text(value, textAlign: TextAlign.right, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: energy ? 12.5 : 14.5, color: EvochiColor.ink)),
          ),
        ]),
      ),
    );
  }
}

const rarityNames = {'rare': 'Rare', 'uncommon': 'Uncommon', 'legendary': 'Legendary', 'common': 'Common'};

/// The wild one's nameplate: badge, rarity line, name, affinity tile, and its Calm / Instability meter.
class _WildPlate extends StatelessWidget {
  const _WildPlate({required this.stage, required this.view});
  final EncounterStage stage;
  final tr.EncounterView view;
  @override
  Widget build(BuildContext context) {
    final c = view.creature;
    final hollow = c.kind == 'hollow';
    final a = tr.affinityDefs[c.affinity]!;
    final sub = c.boss ? 'Legendary · Story boss' : '${rarityNames[c.rarity] ?? ''}${hollow ? ' · Hollow' : ' · ${a.name}'}';
    return Semantics(
      container: true,
      label: '${c.name}, $sub. ${view.meterLabel} ${stage.meterText}',
      child: ExcludeSemantics(
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          decoration: _plateDecoration(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              hollow ? const _Badge(icon: 'moon', bg: Color(0xFF3F2E62), ring: Color(0xFF8E5BD6)) : _Badge(icon: a.icon, bg: const Color(0xFFE5F2CF), ring: const Color(0xFF9ACB76)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(sub, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, color: EvochiColor.textHelper)),
                  Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 20, height: 1.1, color: EvochiColor.ink)),
                ]),
              ),
              const SizedBox(width: 10),
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: hollow ? const Color(0xFFEEE8F4) : const Color(0xFFE8F3DA),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: hollow ? const Color(0xFFDCCFEA) : const Color(0xFFCFE5B5), width: 1.5),
                ),
                child: hollow ? Opacity(opacity: 0.8, child: ColorFiltered(colorFilter: const ColorFilter.matrix(_grey70), child: VoxelIcon(a.icon, size: 32))) : VoxelIcon(a.icon, size: 32),
              ),
            ]),
            const SizedBox(height: 8),
            StageMeter(kind: view.goal == 'befriend' ? 'calm' : 'inst', label: view.meterLabel, frac: stage.meter, value: stage.meterText),
          ]),
        ),
      ),
    );
  }
}

// grayscale(0.7)
const _grey70 = <double>[
  0.449, 0.501, 0.05, 0, 0, //
  0.149, 0.801, 0.05, 0, 0, //
  0.149, 0.501, 0.35, 0, 0, //
  0, 0, 0, 1, 0,
];

/// Your Evochi's plate: swirl badge, name and level, the Energy bar.
class _PetPlate extends StatelessWidget {
  const _PetPlate({required this.stage, required this.pet, required this.level});
  final EncounterStage stage;
  final Pet pet;
  final int level;
  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        label: '${pet.name}, level $level. Energy ${stage.energyText}',
        child: ExcludeSemantics(
          child: Container(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
            decoration: _plateDecoration(),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const _Badge(icon: 'swirl', bg: Color(0xFFFBE0CC), ring: Color(0xFFEE9A78)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.baseline, textBaseline: TextBaseline.alphabetic, children: [
                    Expanded(child: Text(pet.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 17, height: 1.1, color: EvochiColor.ink))),
                    const SizedBox(width: 6),
                    Text('Lv. $level', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, color: EvochiColor.textSecondary)),
                  ]),
                  const SizedBox(height: 2),
                  const Text('Energy', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12, color: EvochiColor.textSecondary)),
                  const SizedBox(height: 1),
                  StageMeter(kind: 'energy', label: 'Energy', frac: stage.energy, value: stage.energyText, labelInside: false),
                ]),
              ),
            ]),
          ),
        ),
      );
}

// ------------------------------------------------------------- title, ribbon, caption ----
class _IntroTitle extends StatelessWidget {
  const _IntroTitle({super.key, required this.shown, required this.title, required this.sub, required this.hollow, required this.boss, required this.reducedMotion});
  final bool shown;
  final String title;
  final String sub;
  final bool hollow;
  final bool boss;
  final bool reducedMotion;
  @override
  Widget build(BuildContext context) {
    if (!shown) return const SizedBox.shrink();
    final pill = Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(22, 9, 22, 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: hollow ? const [Color(0xFF2E2244), Color(0xFF241A36)] : const [Color(0xFFFFFCF6), Color(0xFFFBEFD9)]),
          border: Border.all(color: hollow ? const Color(0xFFA98BDA) : const Color(0xFFE8B956), width: 2.5),
          boxShadow: hollow
              ? const [BoxShadow(color: Color(0xFF6E4FA3), offset: Offset(0, 4)), BoxShadow(color: Color(0xA6AA6EFF), blurRadius: 30)]
              : const [BoxShadow(color: EvochiColor.primaryShadow, offset: Offset(0, 4)), BoxShadow(color: Color(0x59000000), blurRadius: 26, offset: Offset(0, 12))],
        ),
        child: Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: boss ? 24 : 21, height: 1.15, letterSpacing: boss ? 0.3 : 0, color: hollow ? const Color(0xFFEDE2FB) : EvochiColor.ink),
        ),
      ),
      if (sub.isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
          decoration: BoxDecoration(color: const Color(0xD1281C18), borderRadius: BorderRadius.circular(10)),
          child: Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 13.5, color: Color(0xFFFFF6E6))),
        ),
      ],
    ]);
    return Semantics(
      liveRegion: true,
      label: '$title. $sub',
      child: ExcludeSemantics(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: reducedMotion ? 200 : 800),
          curve: popCurve,
          builder: (_, t, child) => Opacity(opacity: t.clamp(0.0, 1.0), child: Transform.translate(offset: Offset(0, 18 * (1 - t)), child: Transform.scale(scale: 0.86 + 0.14 * t, child: child))),
          child: pill,
        ),
      ),
    );
  }
}

/// "Success!" / "Restored!" over the shot, cream with gold ends.
class _Ribbon extends StatelessWidget {
  const _Ribbon({required this.shown, required this.view, required this.hollow});
  final bool shown;
  final tr.EncounterView view;
  final bool hollow;
  @override
  Widget build(BuildContext context) {
    final befriend = view.goal == 'befriend';
    final text = befriend ? 'Success!' : 'Restored!';
    final sub = befriend ? '${view.creature.name} trusts you!' : '${view.creature.name} remembers its light.';
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 500),
      opacity: shown ? 1 : 0,
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 600),
        curve: popCurve,
        offset: shown ? Offset.zero : const Offset(0, -0.3),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 600),
          curve: popCurve,
          scale: shown ? 1 : 0.9,
          child: Semantics(
            liveRegion: shown,
            label: shown ? '$text $sub' : null,
            child: ExcludeSemantics(
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF9EA), Color(0xFFFBEBCB)]),
                    border: Border.all(color: const Color(0xFFE5BF73), width: 2.5),
                    boxShadow: const [BoxShadow(color: Color(0xFFD3A44C), offset: Offset(0, 4)), BoxShadow(color: Color(0x521E1208), blurRadius: 24, offset: Offset(0, 12))],
                  ),
                  child: Column(children: [
                    Text(text,
                        style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 27, height: 1.1, color: hollow ? const Color(0xFF5B3AA0) : const Color(0xFF3E7D33), shadows: const [Shadow(color: Colors.white, offset: Offset(0, 2))])),
                    const SizedBox(height: 2),
                    Text(sub, textAlign: TextAlign.center, style: const TextStyle(fontFamily: EvochiText.body, fontWeight: FontWeight.w700, fontSize: 15, color: EvochiColor.textSecondary)),
                  ]),
                ),
                const Positioned(left: -12, top: -8, bottom: -8, child: _RibbonEnd()),
                const Positioned(right: -12, top: -8, bottom: -8, child: _RibbonEnd()),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _RibbonEnd extends StatelessWidget {
  const _RibbonEnd();
  @override
  Widget build(BuildContext context) => Container(
        width: 18,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(9),
          gradient: const LinearGradient(colors: [Color(0xFFD69A35), Color(0xFFF9D883), Color(0xFFE2AA45)], stops: [0, 0.45, 1]),
          boxShadow: const [BoxShadow(color: Color(0xFFB47E22), offset: Offset(0, 3))],
        ),
      );
}

/// The last log line as a caption card on the shot (names in bold).
class _Caption extends StatelessWidget {
  const _Caption({required this.shown, required this.text, required this.names});
  final bool shown;
  final String text;
  final List<String> names;
  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        duration: const Duration(milliseconds: 500),
        opacity: shown ? 1 : 0,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 600),
          curve: popCurve,
          offset: shown ? Offset.zero : const Offset(0, 0.3),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
            decoration: BoxDecoration(
              color: const Color(0xF5FFFDF9),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEBDCC8), width: 2),
              boxShadow: const [BoxShadow(color: Color(0xE6D0B89C), offset: Offset(0, 4)), BoxShadow(color: Color(0x401E1208), blurRadius: 22, offset: Offset(0, 10))],
            ),
            child: logText(text, names, fontSize: 15, height: 21 / 15),
          ),
        ),
      );
}

/// A log line with the names in bold, like the board.
Widget logText(String text, List<String> names, {double fontSize = 15.5, double height = 21 / 15.5, Color color = const Color(0xFF4E3A30)}) {
  final base = TextStyle(fontFamily: EvochiText.body, fontWeight: FontWeight.w400, fontSize: fontSize, height: height, color: color);
  final bold = base.copyWith(fontWeight: FontWeight.w900, color: const Color(0xFF4A2D45));
  final spans = <TextSpan>[];
  var rest = text;
  final ns = names.where((n) => n.isNotEmpty).toList();
  while (rest.isNotEmpty) {
    var best = -1;
    var bestName = '';
    for (final n in ns) {
      final i = rest.indexOf(n);
      if (i >= 0 && (best < 0 || i < best)) {
        best = i;
        bestName = n;
      }
    }
    if (best < 0) {
      spans.add(TextSpan(text: rest));
      break;
    }
    if (best > 0) spans.add(TextSpan(text: rest.substring(0, best)));
    spans.add(TextSpan(text: bestName, style: bold));
    rest = rest.substring(best + bestName.length);
  }
  return Text.rich(TextSpan(style: base, children: spans));
}
