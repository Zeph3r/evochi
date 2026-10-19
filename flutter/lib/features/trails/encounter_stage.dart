// Lumen Trails: the battle shot. Your Evochi from behind in the foreground, the wild one facing it on
// a 2:3 backdrop with a foreground layer for depth, camera "shots" (wide / pet / wild / close / face),
// shakes, a flash, a Hollow aura, the nameplates, the intro title and the result ribbon, and the
// one-shot effects a turn throws around (orbs, bursts, floating numbers, hearts, petals, a lash).
//
// The stage is driven imperatively through [EncounterStage] (a ChangeNotifier the screen pokes from
// its timelines), so camera moves and effects never restart when the state re-renders. Geometry is
// expressed in fractions of the backdrop, so it lines up at any size. Mirrors the stage half of
// web/src/screens/encounter.js and the "encounter: the battle shot" CSS.

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../core/models/game_state.dart';
import '../../core/services/asset_manifest.dart';
import '../../game/trails/trails.dart' as tr;
import '../shared/sprite.dart';
import '../shared/widgets.dart';

// your Evochi's frame width (share of the shot's width) per stage, and how far right its face may reach
const petWidthByStage = {1: 0.44, 2: 0.52, 3: 0.68};
const faceMaxX = 0.38;
// lift your Evochi off the scene's mark a little, so its card below covers only its feet
const petLift = 0.075;
const camCurve = Cubic(0.3, 0.75, 0.25, 1);
const popCurve = Cubic(0.2, 1.3, 0.4, 1);

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
    required this.wildHeadY,
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
  final double wildHeadY; // top of its head (floating numbers sit above it)
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
    wildFace: cb.hasAnchor('face') ? Offset((wl + cb.anchor('face').dx * s) / w, (wt + cb.anchor('face').dy * s) / hh) : null,
    wildEyes: cb.hasAnchor('eye_l') ? [local(cb.anchor('eye_l')), local(cb.anchor('eye_r'))] : null,
    wildHeadY: (wt + ct.dy * s) / hh,
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

// ------------------------------------------------------------------ the controller ----
/// A one-shot animation on something: its name, a counter so the same one can retrigger, and how
/// long it runs.
class StageAnim {
  const StageAnim(this.name, this.id, this.ms, {this.kind = ''});
  final String name;
  final int id;
  final int ms;
  final String kind; // flash: white | gold | violet
}

/// One effect on the vfx layer.
class FxItem {
  FxItem({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.ms,
    this.cls = '',
    this.text = '',
    this.to,
    this.arc = 0,
    this.n = 0,
    this.inner = '',
    this.itemId,
  });
  final int id;
  final String kind; // float | proj | burst | rise | bubble | buddy
  final double x, y; // backdrop fractions
  final int ms;
  final String cls; // style words: 'good violet', 'orb violet', 'spark big', 'ring teal', 'boop soft', 'heart'
  final String text;
  final Offset? to; // proj: where it lands
  final double arc; // proj: lift at mid-flight (% of the view height, negative = up)
  final int n; // burst: particles
  final String inner; // burst / rise: dot | spark | heart
  final String? itemId; // proj toss: the item thrown
}

/// The live visual state of the stage, poked by the screen's timelines.
class EncounterStage extends ChangeNotifier {
  EncounterStage({required this.reducedMotion});
  final bool reducedMotion;

  String shot = 'wide';
  int cutId = 0; // bumped when the next camera move should be instant
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
  StageAnim? wildAnim, petAnim, shake, flash;
  double meter = 0; // 0..1
  String meterText = '';
  double energy = 0;
  String energyText = '';
  final List<FxItem> fx = [];
  int _ids = 0;
  final List<Timer> _timers = [];
  bool _disposed = false;

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

  /// Change the camera shot (instantly when [instant]).
  void setShot(String name, {bool instant = false}) {
    if (instant) cutId++;
    shot = name;
    _tick();
  }

  /// Change several fields at once, then repaint.
  void update(void Function(EncounterStage s) fn) {
    fn(this);
    _tick();
  }

  void retriggerWild(String name, int ms) {
    wildAnim = StageAnim(name, ++_ids, ms);
    _tick();
    final id = _ids;
    _after(ms, () {
      if (wildAnim?.id == id) {
        wildAnim = null;
        _tick();
      }
    });
  }

  void retriggerPet(String name, int ms) {
    petAnim = StageAnim(name, ++_ids, ms);
    _tick();
    final id = _ids;
    _after(ms, () {
      if (petAnim?.id == id) {
        petAnim = null;
        _tick();
      }
    });
  }

  void doShake({bool big = false}) {
    if (reducedMotion) return;
    shake = StageAnim(big ? 'large' : 'small', ++_ids, big ? 900 : 450);
    _tick();
    final id = _ids;
    _after(big ? 900 : 450, () {
      if (shake?.id == id) {
        shake = null;
        _tick();
      }
    });
  }

  void doFlash([String kind = 'white']) {
    flash = StageAnim('flash', ++_ids, 600, kind: kind);
    _tick();
    final id = _ids;
    _after(600, () {
      if (flash?.id == id) {
        flash = null;
        _tick();
      }
    });
  }

  void addFx(FxItem Function(int id) make) {
    final added = make(++_ids);
    fx.add(added);
    _tick();
    _after(added.ms, () {
      fx.remove(added);
      _tick();
    });
  }

  void floatText(Offset at, String text, String cls) => addFx((id) => FxItem(id: id, kind: 'float', x: at.dx, y: at.dy, ms: 1500, text: text, cls: cls));

  /// Something travels from [a] to [b] along an arc.
  void projectile(String cls, Offset a, Offset b, int ms, {double arc = 0, String? itemId}) =>
      addFx((id) => FxItem(id: id, kind: 'proj', x: a.dx, y: a.dy, to: b, ms: ms + 80, cls: cls, arc: arc, itemId: itemId));

  void burst(String cls, Offset p, {int n = 8, String inner = 'dot', int life = 1100}) =>
      addFx((id) => FxItem(id: id, kind: 'burst', x: p.dx, y: p.dy, ms: life, cls: cls, n: n, inner: inner));

  void rise(Offset p, String inner, int life, {bool big = false}) =>
      addFx((id) => FxItem(id: id, kind: 'rise', x: p.dx, y: p.dy, ms: life, inner: inner, cls: big ? 'heart' : ''));

  void bubble(Offset p, String text) => addFx((id) => FxItem(id: id, kind: 'bubble', x: p.dx, y: p.dy, ms: 1300, text: text));

  void buddy() => addFx((id) => FxItem(id: id, kind: 'buddy', x: 0.06, y: 0.70, ms: 1900));

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
    super.dispose();
  }
}

// ------------------------------------------------------------------------ helpers ----
/// Piecewise-linear keyframes: [stops] in 0..1 with a value each.
double _kf(double t, List<double> stops, List<double> values) {
  if (t <= stops.first) return values.first;
  for (var i = 1; i < stops.length; i++) {
    if (t <= stops[i]) {
      final a = stops[i - 1];
      final b = stops[i];
      final f = b == a ? 1.0 : (t - a) / (b - a);
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

class CamTween extends Tween<CamPose> {
  CamTween({super.begin, super.end});
  @override
  CamPose lerp(double t) => CamPose.lerp(begin!, end!, t);
}

/// The camera for a shot (port of the `.enc-cam` rules).
CamPose camPose(String shot, ShotGeometry g) {
  switch (shot) {
    case 'wild':
      return CamPose(1.13, (0.5 - g.wildCx) * 0.4, (0.5 - g.wildCy) * 0.3, 1000);
    case 'pet':
      return CamPose(1.07, (0.5 - g.petCx) * 0.3, (0.5 - g.petCy) * 0.2, 700);
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
      'pet' => const CamPose(1.04, 0, 0),
      _ => const CamPose(1, 0, 0),
    };

Matrix4 _poseMatrix(CamPose p, double w, double h) => Matrix4.identity()
  ..scale(p.scale, p.scale)
  ..translate(p.tx * w, p.ty * h);

ColorFilter _brightness(double b) => ColorFilter.matrix(<double>[b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0]);

const _heartColor = Color(0xFFF58CA6);
const _sparkFill = Color(0xFFFFF6C9);
const _sparkEdge = Color(0xFFF4B84E);

/// The four-point spark the bursts throw (the web's SPARK svg).
class _Spark extends StatelessWidget {
  const _Spark({this.size = 24});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _SparkPainter()));
}

class _SparkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = Path()
      ..moveTo(12 * s, 1.5 * s)
      ..lineTo(14.4 * s, 9.6 * s)
      ..lineTo(22.5 * s, 12 * s)
      ..lineTo(14.4 * s, 14.4 * s)
      ..lineTo(12 * s, 22.5 * s)
      ..lineTo(9.6 * s, 14.4 * s)
      ..lineTo(1.5 * s, 12 * s)
      ..lineTo(9.6 * s, 9.6 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = _sparkFill);
    canvas.drawPath(
      p,
      Paint()
        ..color = _sparkEdge
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 * s
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SparkPainter old) => false;
}

/// A little heart (the web's HEART svg).
class _Heart extends StatelessWidget {
  const _Heart({this.size = 26});
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size, child: CustomPaint(painter: _HeartPainter()));
}

class _HeartPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 24;
    final p = Path()
      ..moveTo(12 * s, 21 * s)
      ..cubicTo(12 * s, 21 * s, 4.5 * s, 16.4 * s, 2.6 * s, 11.7 * s)
      ..cubicTo(1.2 * s, 8.2 * s, 3.4 * s, 4.6 * s, 7 * s, 4.6 * s)
      ..cubicTo(9.1 * s, 4.6 * s, 10.6 * s, 5.8 * s, 12 * s, 7.6 * s)
      ..cubicTo(13.4 * s, 5.8 * s, 14.9 * s, 4.6 * s, 17 * s, 4.6 * s)
      ..cubicTo(20.6 * s, 4.6 * s, 22.8 * s, 8.2 * s, 21.4 * s, 11.7 * s)
      ..cubicTo(19.5 * s, 16.4 * s, 12 * s, 21 * s, 12 * s, 21 * s)
      ..close();
    canvas.drawPath(p, Paint()..color = _heartColor);
    canvas.drawPath(
      p,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * s
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_HeartPainter old) => false;
}

Widget _innerWidget(String inner, double size) => switch (inner) {
      'heart' => _Heart(size: size),
      'spark' => _Spark(size: size),
      _ => const SizedBox.shrink(),
    };

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
  // idle loops: breathing, drift, the aura's pulse and the eye glow all read this one 16 s clock
  late final AnimationController _idle = AnimationController(vsync: this, duration: const Duration(seconds: 16));
  late final AnimationController _tremble = AnimationController(vsync: this, duration: const Duration(milliseconds: 160));
  late final AnimationController _dust = AnimationController(vsync: this, duration: const Duration(milliseconds: 1700));

  @override
  void initState() {
    super.initState();
    if (!widget.stage.reducedMotion) _idle.repeat();
    widget.stage.addListener(_onStage);
  }

  @override
  void didUpdateWidget(EncounterStageView old) {
    super.didUpdateWidget(old);
    if (old.stage != widget.stage) {
      old.stage.removeListener(_onStage);
      widget.stage.addListener(_onStage);
    }
  }

  void _onStage() {
    final st = widget.stage;
    if (st.trembling && !st.reducedMotion) {
      if (!_tremble.isAnimating) _tremble.repeat();
      if (!_dust.isAnimating) _dust.repeat();
    } else {
      if (_tremble.isAnimating) _tremble.stop();
      if (_dust.isAnimating) _dust.stop();
    }
  }

  @override
  void dispose() {
    widget.stage.removeListener(_onStage);
    _idle.dispose();
    _tremble.dispose();
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
          child: ClipRect(child: _View(stage: st, props: p, idle: _idle, tremble: _tremble, dust: _dust, safeTop: safeTop, hollowKind: hollowKind)),
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

/// The view: the world (camera, shake, drift, backdrop, aura, sprites, foreground, effects), then
/// the grade, the flash, the dust, the plates, the ribbon and the caption.
class _View extends StatelessWidget {
  const _View({required this.stage, required this.props, required this.idle, required this.tremble, required this.dust, required this.safeTop, required this.hollowKind});
  final EncounterStage stage;
  final StageProps props;
  final AnimationController idle;
  final AnimationController tremble;
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
              child: _World(stage: st, props: p, bw: bw, bh: bh, vh: vh, idle: idle, tremble: tremble, hollowKind: hollowKind),
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
            // flash
            if (st.flash != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    key: ValueKey(st.flash!.id),
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 600),
                    builder: (_, t, __) => Opacity(
                      opacity: _kf(t, [0, 0.15, 1], [0, 0.85, 0]),
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

/// The world: camera, shake and drift around the backdrop, the aura, the wild one, your Evochi, the
/// foreground layer and the effects.
class _World extends StatelessWidget {
  const _World({required this.stage, required this.props, required this.bw, required this.bh, required this.vh, required this.idle, required this.tremble, required this.hollowKind});
  final EncounterStage stage;
  final StageProps props;
  final double bw, bh, vh;
  final AnimationController idle;
  final AnimationController tremble;
  final bool hollowKind;

  @override
  Widget build(BuildContext context) {
    final st = stage;
    final g = props.geometry;
    final rm = st.reducedMotion;
    final cam = camPose(st.shot, g);
    final fg = fgPose(st.shot);
    final wildBody = _WildBody(stage: st, props: props, width: g.wildWidth * bw, idle: idle, hollowKind: hollowKind);
    final petIn = st.petIn;
    final petSlide = !petIn ? const Offset(-0.75, 0.14) : (st.shot == 'wild' ? const Offset(-0.07, 0.04) : Offset.zero);
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
              animation: idle,
              builder: (_, __) {
                final period = st.won ? 1.8 : (st.phase2 ? 1.2 : 2.6);
                final pulse = rm ? 1.0 : 0.55 + 0.45 * (0.5 - 0.5 * math.cos(2 * math.pi * ((idle.value * 16) % period) / period));
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
      // the wild one
      Positioned(left: g.wildLeft * bw, top: g.wildTop * bh, width: g.wildWidth * bw, child: wildBody),
      // your Evochi, sliding in from off-left (and a touch right/down on the wild shot)
      Positioned(
        left: g.petLeft * bw,
        top: g.petTop * bh,
        width: g.petWidth * bw,
        child: TweenAnimationBuilder<Offset>(
          key: ValueKey('pet-slide-${st.cutId}'),
          tween: Tween(begin: petSlide, end: petSlide),
          duration: rm ? const Duration(milliseconds: 300) : const Duration(milliseconds: 1000),
          curve: camCurve,
          builder: (_, off, child) => FractionalTranslation(translation: off, child: child),
          child: _PetBody(stage: st, props: props, width: g.petWidth * bw, idle: idle, hollowKind: hollowKind),
        ),
      ),
      // the foreground layer, scaled a touch more than the backdrop for parallax
      Positioned.fill(
        child: IgnorePointer(
          child: TweenAnimationBuilder<CamPose>(
            key: ValueKey('fg-${st.cutId}'),
            tween: CamTween(begin: fg, end: fg),
            duration: rm ? const Duration(milliseconds: 300) : const Duration(milliseconds: 1000),
            curve: camCurve,
            builder: (_, pose, child) => Transform(origin: Offset(bw * 0.85, bh * 0.7), transform: _poseMatrix(pose, bw, bh), child: child),
            child: Image.asset(g.scene.fg, fit: BoxFit.fill, excludeFromSemantics: true, gaplessPlayback: true, filterQuality: FilterQuality.medium),
          ),
        ),
      ),
      // effects
      Positioned.fill(child: IgnorePointer(child: _FxLayer(stage: st, bw: bw, bh: bh, vh: vh, hollowKind: hollowKind))),
    ]);
    // drift (a slow 16 s push-in and back), shake, then the camera
    Widget world = AnimatedBuilder(
      animation: idle,
      builder: (_, child) {
        if (rm) return child!;
        final t = _tri(idle.value);
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
    world = _ShakeLayer(stage: st, tremble: tremble, child: world);
    return TweenAnimationBuilder<CamPose>(
      key: ValueKey('cam-${st.cutId}'),
      tween: CamTween(begin: cam, end: cam),
      duration: rm ? const Duration(milliseconds: 300) : Duration(milliseconds: cam.ms),
      curve: camCurve,
      builder: (_, pose, child) => Transform(alignment: Alignment.center, transform: _poseMatrix(pose, bw, bh), child: child),
      child: world,
    );
  }
}

/// Small and large shakes, and the Sentinel's continuous tremble.
class _ShakeLayer extends StatelessWidget {
  const _ShakeLayer({required this.stage, required this.tremble, required this.child});
  final EncounterStage stage;
  final AnimationController tremble;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final sh = stage.shake;
    Widget w = child;
    if (sh != null) {
      final big = sh.name == 'large';
      w = TweenAnimationBuilder<double>(
        key: ValueKey('shake-${sh.id}'),
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: sh.ms),
        curve: big ? const Cubic(0.3, 0.6, 0.4, 1) : Curves.linear,
        builder: (_, t, c) {
          final dx = big ? _kf(t, [0, .1, .22, .36, .5, .66, .82, 1], [0, -12, 11, -8, 6, -4, 2, 0]) : _kf(t, [0, .2, .4, .6, .8, 1], [0, -5, 5, -3, 2, 0]);
          final dy = big ? _kf(t, [0, .1, .22, .36, .5, .66, .82, 1], [0, 6, -7, -5, 5, 2, -2, 0]) : _kf(t, [0, .2, .4, .6, .8, 1], [0, 3, -2, -3, 2, 0]);
          final rot = big ? _kf(t, [0, .1, .22, .36, 1], [0, -0.6, 0.5, 0, 0]) * math.pi / 180 : 0.0;
          return Transform.translate(offset: Offset(dx, dy), child: Transform.rotate(angle: rot, child: c));
        },
        child: w,
      );
    }
    if (stage.trembling && !stage.reducedMotion) {
      w = AnimatedBuilder(
        animation: tremble,
        builder: (_, c) {
          final t = tremble.value;
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

/// The wild one: its sprite in its current state (crossfading), idle breathing (or a wary shiver),
/// the one-shot reactions, the Hollow silhouette, the Sentinel's eye glows and the intro "!".
class _WildBody extends StatelessWidget {
  const _WildBody({required this.stage, required this.props, required this.width, required this.idle, required this.hollowKind});
  final EncounterStage stage;
  final StageProps props;
  final double width;
  final AnimationController idle;
  final bool hollowKind;

  @override
  Widget build(BuildContext context) {
    final g = props.geometry;
    final st = stage;
    final height = width / g.wildAr;
    final cb = g.creature;
    final state = st.wildState.isEmpty ? props.view.stateKey : st.wildState;
    final rm = st.reducedMotion;
    Widget img = AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: Image.asset(cb.state(state), key: ValueKey(state), width: width, height: height, fit: BoxFit.fill, excludeFromSemantics: true, gaplessPlayback: true, filterQuality: FilterQuality.medium),
    );
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
            child: _EyeGlow(on: (i == 0 ? st.eyeL : st.eyeR) && !st.won, pulsing: st.lit && st.eyeR && !st.won, idle: idle, rm: rm),
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
            idle: idle,
            rm: rm,
            idleKind: st.wildMood == 'wary' && st.wildAnim == null ? 'shiver' : 'wild',
            glow: hollowKind ? const Color(0xFFAA6EFF) : const Color(0xFFFFE28C),
            child: body,
          ),
        ),
      ]),
    );
  }
}

class _EyeGlow extends StatelessWidget {
  const _EyeGlow({required this.on, required this.pulsing, required this.idle, required this.rm});
  final bool on;
  final bool pulsing;
  final AnimationController idle;
  final bool rm;
  @override
  Widget build(BuildContext context) {
    const eye = CustomPaint(painter: _EyePainter());
    if (on && pulsing && !rm) {
      // lit: a slow glow
      return AnimatedBuilder(
        animation: idle,
        builder: (_, child) {
          final t = 0.5 - 0.5 * math.cos(2 * math.pi * ((idle.value * 16) % 2.8) / 2.8);
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
  const _PetBody({required this.stage, required this.props, required this.width, required this.idle, required this.hollowKind});
  final EncounterStage stage;
  final StageProps props;
  final double width;
  final AnimationController idle;
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
            idle: idle,
            rm: st.reducedMotion,
            idleKind: 'pet',
            glow: hollowKind ? const Color(0xFFCDAAFF) : const Color(0xFFFFE28C),
            child: body,
          ),
        ),
      ]),
    );
  }
}

/// A sprite body: its idle loop, or the one-shot reaction playing over it (transform, brightness,
/// opacity and a glow behind, per the web's keyframes). The transform origin is 50% / 92%.
class _AnimatedBody extends StatelessWidget {
  const _AnimatedBody({required this.anim, required this.idle, required this.rm, required this.idleKind, required this.glow, required this.child});
  final StageAnim? anim;
  final AnimationController idle;
  final bool rm;
  final String idleKind; // wild | shiver | pet
  final Color glow;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = anim;
    if (a == null) {
      if (rm) return child;
      return AnimatedBuilder(
        animation: idle,
        builder: (_, c) {
          final s16 = idle.value * 16;
          switch (idleKind) {
            case 'shiver':
              // a wary one shivers side to side
              final t = s16 % 1.0;
              return FractionalTranslation(translation: Offset(_kf(t, [0, .25, .75, 1], [0, 1.2, -1.2, 0]) / 100, 0), child: c);
            case 'pet':
              final t = 0.5 - 0.5 * math.cos(2 * math.pi * (s16 % 3.0) / 3.0);
              return Transform(alignment: const Alignment(0, 0.84), transform: Matrix4.identity()..scale(1 + 0.008 * t, 1 + 0.018 * t), child: c);
            default:
              final t = 0.5 - 0.5 * math.cos(2 * math.pi * (s16 % 3.2) / 3.2);
              return FractionalTranslation(
                translation: Offset(0, -0.012 * t),
                child: Transform(alignment: const Alignment(0, 0.84), transform: Matrix4.identity()..scale(1 + 0.01 * t, 1 - 0.005 * t), child: c),
              );
          }
        },
        child: child,
      );
    }
    return TweenAnimationBuilder<double>(
      key: ValueKey('body-${a.id}'),
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: a.ms),
      curve: switch (a.name) {
        'lunge' => const Cubic(0.5, 0, 0.3, 1),
        'flinch' => const Cubic(0.3, 0.7, 0.3, 1),
        'hit' || 'perk' || 'cast' || 'hurt' => Curves.easeOut,
        _ => Curves.easeInOut,
      },
      builder: (_, t, c) {
        var dx = 0.0, dy = 0.0, sx = 1.0, sy = 1.0, rot = 0.0, op = 1.0, bright = 1.0, glowA = 0.0;
        switch (a.name) {
          case 'hit':
            sx = _kf(t, [0, .25, .6, 1], [1, 1.07, 0.97, 1]);
            sy = _kf(t, [0, .25, .6, 1], [1, 0.92, 1.03, 1]);
            bright = _kf(t, [0, .25, .6, 1], [1, 1.5, 1, 1]);
          case 'perk':
            dy = _kf(t, [0, .4, 1], [0, -0.04, 0]);
          case 'skitter':
            dx = _kf(t, [0, .3, .55, 1], [0, 0.16, 0.10, 0]);
            sx = sy = _kf(t, [0, .3, .55, 1], [1, 0.94, 0.96, 1]);
          case 'tilt':
            rot = _kf(t, [0, .4, .7, 1], [0, -8, 4, 0]) * math.pi / 180;
            dy = _kf(t, [0, .4, 1], [0, -0.02, 0]);
          case 'surge':
            sx = sy = _kf(t, [0, .35, 1], [1, 1.08, 1]);
            bright = _kf(t, [0, .35, 1], [1, 1.35, 1]);
            glowA = _kf(t, [0, .35, 1], [0, 1, 0]);
          case 'flicker':
            final step = (t * 6).floor() / 6;
            op = _kf(step, [0, .2, .4, .6, .8, 1], [1, 0.55, 1, 0.4, 0.9, 1]);
          case 'joy' || 'hop':
            // three hops in a row (two for your Evochi)
            final hop = (t * (a.name == 'joy' ? 3 : 2)) % 1.0;
            dy = _kf(hop, [0, .4, .7, 1], [0, -0.09, 0, 0]);
            sx = _kf(hop, [0, .4, .7, 1], [1, 0.97, 1.05, 1]);
            sy = _kf(hop, [0, .4, .7, 1], [1, 1.04, 0.95, 1]);
          case 'cast':
            dy = _kf(t, [0, .35, 1], [0, -0.04, 0]);
            sx = sy = _kf(t, [0, .35, 1], [1, 1.02, 1]);
            bright = _kf(t, [0, .35, 1], [1, 1.18, 1]);
            glowA = _kf(t, [0, .35, 1], [0, 1, 0]);
          case 'lunge':
            dx = _kf(t, [0, .25, .5, 1], [0, -0.03, 0.16, 0]);
            dy = _kf(t, [0, .25, .5, 1], [0, 0.01, -0.07, 0]);
            sx = _kf(t, [0, .25, .5, 1], [1, 0.98, 1.03, 1]);
            sy = _kf(t, [0, .25, .5, 1], [1, 1.02, 0.97, 1]);
          case 'rest':
            dy = _kf(t, [0, .45, 1], [0, 0.02, 0]);
            sx = _kf(t, [0, .45, 1], [1, 1.02, 1]);
            sy = _kf(t, [0, .45, 1], [1, 0.96, 1]);
            glowA = _kf(t, [0, .45, 1], [0, 0.8, 0]);
          case 'hurt':
            dx = _kf(t, [0, .2, .45, 1], [0, -0.05, 0.02, 0]);
            bright = _kf(t, [0, .2, .45, 1], [1, 1.7, 1, 1]);
          case 'flinch':
            dx = _kf(t, [0, .22, .4, .6, 1], [0, -0.06, -0.07, -0.04, 0]);
            dy = _kf(t, [0, .22, .4, 1], [0, -0.09, 0, 0]);
            sx = _kf(t, [0, .22, .4, .6, 1], [1, 1, 1.04, 1, 1]);
            sy = _kf(t, [0, .22, .4, .6, 1], [1, 1, 0.95, 1, 1]);
        }
        Widget w = c!;
        if (bright != 1) w = ColorFiltered(colorFilter: _brightness(bright), child: w);
        if (glowA > 0) {
          w = Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: Opacity(
                opacity: glowA,
                child: DecoratedBox(decoration: BoxDecoration(borderRadius: BorderRadius.circular(60), boxShadow: [BoxShadow(color: glow, blurRadius: 36, spreadRadius: -10)])),
              ),
            ),
            w,
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
class _FxLayer extends StatelessWidget {
  const _FxLayer({required this.stage, required this.bw, required this.bh, required this.vh, required this.hollowKind});
  final EncounterStage stage;
  final double bw, bh, vh;
  final bool hollowKind;
  @override
  Widget build(BuildContext context) => Stack(clipBehavior: Clip.none, children: [
        for (final f in stage.fx) _FxWidget(key: ValueKey('fx-${f.id}'), fx: f, bw: bw, bh: bh, vh: vh),
      ]);
}

class _FxWidget extends StatelessWidget {
  const _FxWidget({super.key, required this.fx, required this.bw, required this.bh, required this.vh});
  final FxItem fx;
  final double bw, bh, vh;

  bool _has(String word) => fx.cls.split(' ').contains(word);

  @override
  Widget build(BuildContext context) {
    final f = fx;
    final x = f.x * bw;
    final y = f.y * bh;
    switch (f.kind) {
      case 'float':
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
        return Positioned(
          left: x,
          top: y,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: f.ms),
            curve: Curves.easeOut,
            builder: (_, t, child) {
              final op = _kf(t, [0, .18, .75, 1], [0, 1, 1, 0]);
              final ty = _kf(t, [0, .18, .3, 1], [-0.6, -1.1, -1.1, -2.6]);
              final sc = _kf(t, [0, .18, .3, 1], [0.6, 1.08, 1, 1]);
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
        final to = f.to ?? Offset(f.x, f.y);
        final dx = (to.dx - f.x) * bw;
        final dy = (to.dy - f.y) * bh;
        final arcPx = f.arc / 100 * vh;
        final ms = f.ms - 80;
        Widget inner;
        if (_has('orb')) {
          final violet = _has('violet');
          inner = Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: violet ? const [Colors.white, Colors.white, Color(0xFFEBDDFF), Color(0xBFB98CFF), Color(0x00AA78FF)] : const [Colors.white, Colors.white, Color(0xFFFFEFA8), Color(0xB3FFCD5A), Color(0x00FFBE3C)],
                stops: const [0, 0.22, 0.4, 0.62, 0.74],
              ),
              boxShadow: [BoxShadow(color: violet ? const Color(0x99BE96FF) : const Color(0x8CFFDC78), blurRadius: 26, spreadRadius: 12)],
            ),
          );
        } else if (_has('lash')) {
          inner = Container(
            width: 26,
            height: 26,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [Color(0xFFE9DDFF), Color(0xFFE9DDFF), Color(0xFF8E5BD6), Color(0x005A3296)], stops: [0, 0.18, 0.45, 0.72]),
              boxShadow: [BoxShadow(color: Color(0x8C7846C8), blurRadius: 18, spreadRadius: 8)],
            ),
          );
        } else if (_has('toss')) {
          inner = f.itemId == null ? const SizedBox.shrink() : ItemImage(f.itemId!, size: 44);
        } else {
          // a petal
          inner = Container(
            width: 14,
            height: 10,
            decoration: const BoxDecoration(
              borderRadius: BorderRadius.vertical(top: Radius.elliptical(8, 8), bottom: Radius.elliptical(8, 4)),
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFBC6D1), Color(0xFFF28CA6)]),
            ),
          );
        }
        final spins = _has('toss') || _has('petal');
        return Positioned(
          left: x,
          top: y,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: math.max(1, ms)),
            curve: Curves.linear,
            builder: (_, t, child) {
              final m = const Cubic(0.45, 0.05, 0.55, 0.95).transform(t);
              final lift = math.sin(t * math.pi) * arcPx;
              return Transform.translate(
                offset: Offset(dx * m, dy * m + lift),
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -0.5),
                  child: spins ? Transform.rotate(angle: t * ms / 700 * 2 * math.pi, child: child) : child,
                ),
              );
            },
            child: inner,
          ),
        );
      case 'burst':
        final ring = _has('ring');
        final big = _has('big');
        final boop = _has('boop');
        final soft = _has('soft');
        final violet = _has('violet');
        final teal = _has('teal');
        if (ring) {
          final color = teal
              ? const Color(0xF2AAF0D7)
              : violet
                  ? const Color(0xF2CDAFFF)
                  : const Color(0xF2FFF0C8);
          final glow = teal
              ? const Color(0xE67FD9B8)
              : violet
                  ? const Color(0xE6AA6EFF)
                  : const Color(0xCCFFE6A0);
          return Positioned(
            left: x - 25,
            top: y - 25,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 1100),
              curve: Curves.easeOut,
              builder: (_, t, __) => Opacity(
                opacity: 1 - t,
                child: Transform.scale(
                  scale: 0.3 + 5.2 * t,
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: color, width: 4), boxShadow: [BoxShadow(color: glow, blurRadius: 14)]),
                  ),
                ),
              ),
            ),
          );
        }
        final n = math.max(1, f.n);
        final dist = big ? 120.0 : 64.0;
        final size = boop ? (soft ? 18.0 : 24.0) : (big ? 16.0 : 12.0);
        return Positioned(
          left: x,
          top: y,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: big ? 1200 : 850),
            curve: Curves.easeOut,
            builder: (_, t, __) => Stack(clipBehavior: Clip.none, children: [
              for (var i = 0; i < n; i++)
                Builder(builder: (_) {
                  final a = ((360 / n) * i + (i % 2) * 11) * math.pi / 180;
                  final d = 0.7 + (i % 3) * 0.25;
                  final r = dist * d * t;
                  final sc = 0.4 + 0.6 * t;
                  return Positioned(
                    left: math.cos(a) * r - size / 2,
                    top: math.sin(a) * r - size / 2,
                    child: Opacity(
                      opacity: 1 - t,
                      child: Transform.scale(
                        scale: sc,
                        child: boop
                            ? _innerWidget(f.inner, size)
                            : Container(
                                width: size,
                                height: size,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: violet ? const Color(0xFFD9C2FF) : const Color(0xFFFFE58A),
                                  boxShadow: [BoxShadow(color: violet ? const Color(0xE6BE96FF) : const Color(0xE6FFDC78), blurRadius: 8)],
                                ),
                              ),
                      ),
                    ),
                  );
                }),
            ]),
          ),
        );
      case 'rise':
        final size = _has('heart') ? 30.0 : 26.0;
        return Positioned(
          left: x,
          top: y,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: f.ms),
            curve: Curves.easeOut,
            builder: (_, t, child) {
              final op = _kf(t, [0, .25, 1], [0, 1, 0]);
              final ty = _kf(t, [0, .25, 1], [-0.5, -0.9, -4.0]);
              final sc = _kf(t, [0, .25, 1], [0.4, 1.05, 0.9]);
              return Opacity(opacity: op, child: FractionalTranslation(translation: Offset(-0.5, ty), child: Transform.scale(scale: sc, child: child)));
            },
            child: _innerWidget(f.inner, size),
          ),
        );
      case 'bubble':
        return Positioned(
          left: x - 17,
          top: y - 17,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: f.ms),
            curve: Curves.easeOut,
            builder: (_, t, child) {
              final sc = _kf(t, [0, .18, .3, 1], [0, 1.15, 1, 1]);
              final op = _kf(t, [0, .1, .8, 1], [0, 1, 1, 0]);
              final dy = _kf(t, [0, .8, 1], [0, 0, -10]);
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
        final w = bw * 0.26;
        return Positioned(
          left: x,
          top: y,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Duration(milliseconds: f.ms),
            curve: Curves.easeInOut,
            builder: (_, t, child) {
              final tx = _kf(t, [0, .2, .75, 1], [-0.9, -0.3, -0.3, -0.9]);
              final ty = _kf(t, [0, .2, .75, 1], [0.4, -0.4, -0.46, 0.4]);
              final rot = _kf(t, [0, .2, .75, 1], [-10, 4, -3, 0]) * math.pi / 180;
              final op = _kf(t, [0, .2, .75, 1], [0, 1, 1, 0]);
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
