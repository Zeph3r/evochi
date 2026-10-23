// Mining with the Pounce on a walkable map (MINES_PLAN.md, "Feel"): tap an ore node and your Evochi walks
// up and faces it; tap Pounce for one committed strike (one more can wait in line), hold it to keep
// striking. Each strike is the same ~480 ms: a crouch, a lunge that drives the head in, the contact, a
// recovery, ready again. Everything a hit does happens at the contact, once: the rock's crack stage,
// its shove, the chips and dust, the sound and the feel. The last hit bursts it: the ore pops out toward
// you and arcs into your satchel. A node too hard for your gear answers with a clink, a bounce and a
// puzzled tilt, and loses nothing.
//
// The Evochi needs no new sprites: the strike is the walk sheet posed in code (the Wilds' melee move).
// tools/art/mining_art.py draws the nodes (four states an ore) and nuggets; mining_sfx.py the sounds.

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

/// The strike's timeline, seconds (MINES_PLAN.md: wind-up, lunge, impact, recovery, ready).
const pounceWindup = 0.11, pounceContact = 0.195, pounceImpactEnd = 0.25, pounceRecoverEnd = 0.40, pounceEnd = 0.48;
const _hitstop = 0.045; // the pose holds this long at contact (the scene and input keep going)

/// How hard each ore is: the gear tier it needs (copper with none).
const oreTier = {'copper': 1, 'iron': 2, 'lumen': 3, 'obsidian': 4};

/// The rock's colours (chips) and the ore's (sparks of it), per ore.
const _stone = {
  'copper': [Color(0xFFBFA07C), Color(0xFFAE8F6C), Color(0xFFCCAE8A)], // sandstone
  'iron': [Color(0xFF6E4A44), Color(0xFF5E3E3A), Color(0xFF7C5650)], // rust-stained
  'lumen': [Color(0xFF5A5F72), Color(0xFF4E5366), Color(0xFF666B80)], // slate
  'obsidian': [Color(0xFF3E3A42), Color(0xFF35313A), Color(0xFF47434C)], // basalt
};
const _ore = {
  'copper': [Color(0xFFD9844A), Color(0xFFF0A56A)],
  'iron': [Color(0xFFB9C0C8), Color(0xFFEEF2F6)],
  'lumen': [Color(0xFF9FF0DA), Color(0xFFD8FFF4)],
  'obsidian': [Color(0xFF251C2C), Color(0xFF9A6BC0)],
};
const oreName = {'copper': 'Copper', 'iron': 'Iron', 'lumen': 'Lumen crystal', 'obsidian': 'Obsidian'};

class OreSprite {
  OreSprite(this.img, this.ground);
  final ui.Image img;
  final Offset ground;
}

class OreKindArt {
  OreKindArt(this.hits, this.states, this.unit, this.nugget, this.nuggetUnit);
  final int hits;
  final List<OreSprite> states; // whole, chipped, cracked, burst
  final double unit; // world units per sprite px
  final OreSprite nugget;
  final double nuggetUnit;
}

/// The ore art (assets/art/mining/mining.json).
class MiningArt {
  MiningArt(this.ores);
  final Map<String, OreKindArt> ores;

  static Future<ui.Image> _img(String path) async {
    final data = await rootBundle.load(path);
    final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
    return (await codec.getNextFrame()).image;
  }

  static Offset _off(List v) => Offset((v[0] as num).toDouble(), (v[1] as num).toDouble());

  static Future<MiningArt> load(Iterable<String> kinds) async {
    final j = jsonDecode(await rootBundle.loadString('assets/art/mining/mining.json')) as Map;
    final ores = <String, OreKindArt>{};
    for (final k in kinds.toSet()) {
      final o = (j['ores'] as Map)[k] as Map;
      final states = <OreSprite>[];
      for (final s in (o['states'] as List).cast<Map>()) {
        states.add(OreSprite(await _img(s['src'] as String), _off(s['ground'] as List)));
      }
      final n = o['nugget'] as Map;
      ores[k] = OreKindArt((o['hits'] as num).toInt(), states, (o['unit'] as num).toDouble(),
          OreSprite(await _img(n['src'] as String), _off(n['ground'] as List)), (n['unit'] as num).toDouble());
    }
    return MiningArt(ores);
  }
}

/// An ore node standing on the map.
class OreNode {
  OreNode(this.kind, this.x, this.z);
  final String kind;
  final double x, z;
  double damage = 0; // hits landed (times your mining power)
  int state = 0; // 0 whole, 1 chipped, 2 cracked, 3 burst
  double hitAt = -9; // when it was last struck (it shoves and settles)
  double hitDir = 1; // which way the shove goes on screen
  double brokeAt = -9; // when it burst (it grows back)
  double noteAt = -9; // when it said it's too hard

  bool get broken => state == 3;

  /// Struck with [power]: the new state, and whether that hit broke it.
  bool strike(double power, int hits) {
    damage += power;
    if (damage >= hits - 1e-6) {
      state = 3;
      return true;
    }
    state = damage / hits < 0.5 ? 1 : 2;
    return false;
  }

  void regrow() {
    damage = 0;
    state = 0;
    brokeAt = -9;
  }
}

/// A bit of the mining in the air: a chip of rock, a puff of dust, or a nugget of ore (which pops out,
/// lands, and then flies to the satchel).
class MineBit {
  MineBit(this.kind, this.x, this.y, this.z, this.vx, this.vy, this.vz, this.born, this.life, this.color, this.size, {this.ore});
  final String kind; // chip, dust, spark, nugget
  double x, y, z, vx, vy, vz;
  final double born, life;
  final Color color;
  final double size; // world units
  final String? ore;
  bool landed = false;
  double flyAt = -1; // nuggets: when they leave for the satchel
  Offset? from; // screen point they left from
}

/// The strike under way (null node: none).
class Pounce {
  OreNode? node;
  double t = -1; // seconds into the strike (-1: none)
  bool contacted = false;
  bool tooHard = false;
  bool queued = false; // one more strike waits in line
  bool held = false; // the button held: keep striking
  double tiltAt = -9; // a puzzled head tilt (too hard) from

  bool get active => t >= 0;
}

/// Your Evochi's pose at [t] seconds into a strike: how far it has moved toward the node (world
/// units), its squash and stretch, its lean (radians, + forward), and which walk frame to show.
/// [stage] 1 hatchling (overcommits, tumbles happily), 2 juvenile (a brisk recoil with a wiggle),
/// 3 elder (grounded, quick to reset). [hard] a too-hard node: the lunge stops short and bounces back.
(double, double, double, double, int) pouncePose(double t, int stage, {bool hard = false}) {
  final reach = (stage == 1 ? 1.15 : stage == 2 ? 0.95 : 0.85) * (hard ? 0.7 : 1.0);
  final soft = stage == 3 ? 0.6 : 1.0; // how much an elder squashes
  double ease(double v) => 1 - math.pow(1 - v.clamp(0.0, 1.0), 3).toDouble();
  // hitstop: the pose holds at the contact a moment
  final tt = (t > pounceContact && t < pounceContact + _hitstop) ? pounceContact : (t >= pounceContact + _hitstop ? t - _hitstop : t);
  if (tt < pounceWindup) {
    final e = ease(tt / pounceWindup);
    return (-0.22 * e, 1 + 0.08 * e * soft, 1 - 0.14 * e * soft, -0.10 * e, 0);
  }
  if (tt < pounceContact) {
    final e = math.pow((tt - pounceWindup) / (pounceContact - pounceWindup), 1.6).toDouble();
    final stretch = math.sin(e * math.pi);
    return (-0.22 + (reach + 0.22) * e, 1 - 0.06 * stretch, 1 + 0.10 * stretch * soft, 0.16 * e, 3);
  }
  if (tt < pounceImpactEnd) {
    final e = (tt - pounceContact) / (pounceImpactEnd - pounceContact);
    final back = hard ? 0.5 * math.sin(e * math.pi / 2) : 0.0; // a too-hard rock throws you back
    return (reach - back * reach, 1 + 0.12 * soft * (1 - e), 1 - 0.12 * soft * (1 - e), 0.16 * (1 - e), 3);
  }
  if (tt < pounceRecoverEnd) {
    final e = ease((tt - pounceImpactEnd) / (pounceRecoverEnd - pounceImpactEnd) * (stage == 2 ? 1.3 : 1.0));
    final start = hard ? reach * 0.5 : reach;
    final hop = math.sin(e * math.pi) * (stage == 1 ? 0.10 : 0.05);
    final wobble = stage == 1
        ? 0.24 * math.sin(e * math.pi * 2.5) * (1 - e) // a happy tumble
        : stage == 2
            ? 0.07 * math.sin(e * math.pi * 6) * (1 - e) // a crystal wiggle
            : 0.0;
    return (start * (1 - e), 1 - hop, 1 + hop, wobble, 0);
  }
  return (0, 1, 1, 0, 0);
}

/// Pounce: tap for one strike, hold to keep striking. A clear ready state: it lifts and glows when
/// you can strike, and dims while a strike is under way.
class PounceButton extends StatelessWidget {
  const PounceButton({super.key, required this.ready, required this.onDown, required this.onUp});
  final bool ready;
  final VoidCallback onDown, onUp;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Pounce',
        hint: 'Tap to strike the ore, hold to keep striking',
        child: Listener(
          onPointerDown: (_) => onDown(),
          onPointerUp: (_) => onUp(),
          onPointerCancel: (_) => onUp(),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 86,
            height: 86,
            transform: Matrix4.translationValues(0, ready ? -2 : 1, 0),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: ready ? const Color(0xFFF4B84E) : const Color(0xFFD9B989),
              border: Border.all(color: const Color(0xFF4A2A14), width: 3),
              boxShadow: [
                BoxShadow(color: const Color(0x66000000), blurRadius: ready ? 10 : 4, offset: Offset(0, ready ? 5 : 2)),
                if (ready) const BoxShadow(color: Color(0x88FFE3A0), blurRadius: 16, spreadRadius: 1),
              ],
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              CustomPaint(size: const Size(38, 34), painter: _PickPainter()),
              const SizedBox(height: 1),
              const ExcludeSemantics(
                child: Text('Pounce', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 13, color: EvochiColor.ink)),
              ),
            ]),
          ),
        ),
      );
}

/// A pickaxe, drawn: a curved iron head on a wooden haft.
class _PickPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size s) {
    final ink = Paint()
      ..color = const Color(0xFF3B2923)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final haft = Path()
      ..moveTo(s.width * 0.22, s.height * 0.92)
      ..lineTo(s.width * 0.66, s.height * 0.26);
    canvas.drawPath(haft, ink..strokeWidth = 7);
    canvas.drawPath(haft, Paint()
      ..color = const Color(0xFFA8703F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round);
    final head = Path()
      ..moveTo(s.width * 0.18, s.height * 0.30)
      ..quadraticBezierTo(s.width * 0.55, s.height * -0.06, s.width * 0.95, s.height * 0.42);
    canvas.drawPath(head, ink..strokeWidth = 8);
    canvas.drawPath(head, Paint()
      ..color = const Color(0xFFC4CAD2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.5
      ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_PickPainter old) => false;
}

/// What's in your satchel this trip: a nugget of each ore and how many.
class SatchelChip extends StatelessWidget {
  const SatchelChip({super.key, required this.counts, required this.bumpAt, required this.now, required this.art, required this.anchor});
  final Map<String, int> counts;
  final double bumpAt, now;
  final MiningArt art;
  final GlobalKey anchor; // where the nuggets fly to

  @override
  Widget build(BuildContext context) {
    final b = (now - bumpAt).clamp(0.0, 0.3) / 0.3;
    final scale = 1 + 0.18 * math.sin(b * math.pi) * (b < 1 ? 1 : 0);
    return Semantics(
      label: 'Satchel: ${counts.entries.where((e) => e.value > 0).map((e) => '${e.value} ${oreName[e.key]}').join(', ')}',
      child: Transform.scale(
        scale: scale,
        child: Container(
          key: anchor,
          padding: const EdgeInsets.fromLTRB(8, 5, 12, 5),
          decoration: BoxDecoration(
            color: const Color(0xEEFFF8E8),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: EvochiColor.border, width: 1.5),
            boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 6, offset: Offset(0, 2))],
          ),
          child: ExcludeSemantics(
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final e in counts.entries)
                if (e.value > 0) ...[
                  RawImage(image: art.ores[e.key]?.nugget.img, width: 24, height: 24, filterQuality: FilterQuality.medium),
                  const SizedBox(width: 4),
                  Text('${e.value}', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16, color: EvochiColor.ink)),
                  const SizedBox(width: 6),
                ],
            ]),
          ),
        ),
      ),
    );
  }
}

final _rng = math.Random(7);

/// The bits a contact throws off: [n] chips of rock and ore, a puff of dust, and on the last hit a
/// burst of sparks. World coordinates; [toward] the unit vector from the node toward your Evochi.
List<MineBit> contactBits(OreNode node, double now, Offset toward, {required bool broke, required bool reduced}) {
  final out = <MineBit>[];
  final stone = _stone[node.kind]!, ore = _ore[node.kind]!;
  final n = reduced ? 3 : (broke ? 9 : 3 + _rng.nextInt(4));
  // where the head meets the rock: its face toward you, at about head height
  final cx = node.x + toward.dx * 1.0, cz = node.z + toward.dy * 1.0;
  for (var i = 0; i < n; i++) {
    final a = _rng.nextDouble() * math.pi * 2;
    final sp = (broke ? 2.4 : 1.6) * (0.5 + _rng.nextDouble());
    final isOre = _rng.nextDouble() < 0.35;
    out.add(MineBit('chip', cx, 1.2 + _rng.nextDouble() * 0.6, cz, math.cos(a) * sp * 0.6 + toward.dx * sp * 0.5, 2.6 + _rng.nextDouble() * 2.2,
        math.sin(a) * sp * 0.6 + toward.dy * sp * 0.5, now, 0.55 + _rng.nextDouble() * 0.3, (isOre ? ore : stone)[_rng.nextInt(isOre ? ore.length : stone.length)],
        0.12 + _rng.nextDouble() * (broke ? 0.14 : 0.08)));
  }
  for (var i = 0; i < (reduced ? 1 : (broke ? 4 : 2)); i++) {
    out.add(MineBit('dust', cx + (_rng.nextDouble() - 0.5) * 0.8, 0.6 + _rng.nextDouble() * 0.6, cz + (_rng.nextDouble() - 0.5) * 0.6,
        (_rng.nextDouble() - 0.5) * 0.6, 0.5 + _rng.nextDouble() * 0.4, (_rng.nextDouble() - 0.5) * 0.4, now, broke ? 0.9 : 0.6, const Color(0xFFD8CFC2),
        broke ? 1.3 : 0.8));
  }
  if (broke && !reduced) {
    for (var i = 0; i < 6; i++) {
      final a = _rng.nextDouble() * math.pi * 2;
      out.add(MineBit('spark', node.x, 1.4, node.z, math.cos(a) * 3.0, 1.5 + _rng.nextDouble() * 2.5, math.sin(a) * 3.0, now, 0.35, ore.last, 0.1));
    }
  }
  return out;
}

/// The ore that pops out of a burst node toward you: [n] nuggets.
List<MineBit> nuggets(OreNode node, double now, Offset toward, int n) => [
      for (var i = 0; i < n; i++)
        MineBit('nugget', node.x, 1.0, node.z, toward.dx * (1.2 + 0.5 * i) + (i - (n - 1) / 2) * 1.1, 4.2 + 0.6 * _rng.nextDouble(),
            toward.dy * (1.2 + 0.5 * i) + 1.4, now, 99, _ore[node.kind]!.first, 0.7, ore: node.kind)
          ..flyAt = now + 0.55 + 0.09 * i, // staggered off to the satchel
    ];

/// Move the bits on by [dt] (gravity, a bounce, landing). Drops the ones whose time is up.
void stepBits(List<MineBit> bits, double now, double dt, double Function(double x, double z) ground) {
  for (final b in bits) {
    if (b.kind == 'dust') {
      b.x += b.vx * dt;
      b.y += b.vy * dt;
      b.z += b.vz * dt;
      continue;
    }
    if (b.landed && b.kind != 'nugget') continue;
    b.vy -= 18 * dt;
    b.x += b.vx * dt;
    b.y += b.vy * dt;
    b.z += b.vz * dt;
    final g = ground(b.x, b.z);
    if (b.y <= g) {
      b.y = g;
      if (b.vy.abs() > 2.2) {
        b.vy = -b.vy * 0.35; // one small bounce
        b.vx *= 0.5;
        b.vz *= 0.5;
      } else {
        b.vy = 0;
        b.vx = 0;
        b.vz = 0;
        b.landed = true;
      }
    }
  }
  bits.removeWhere((b) => b.kind != 'nugget' && now - b.born > b.life);
}

/// An ore node drawn with its ambient life: lumen crystal breathes mint light, brighter as your Evochi
/// comes close (crystals answering footsteps), with a few motes drifting up from it; obsidian has a
/// violet sheen sliding across its glass now and then; copper and iron catch the light in small glints.
/// [near] 0-1: how close your Evochi is. [reduced]: the system's reduced motion (a steady glow only).
void paintOre(Canvas canvas, ui.Image img, Rect dst, String kind, int state, double t, double near, bool reduced, double seed) {
  final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
  final paint = Paint()..filterQuality = FilterQuality.medium;
  final alive = state < 3;
  if (kind == 'obsidian' && alive && !reduced) {
    final u = ((t + seed * 3) % 5.0) / 1.3;
    if (u < 1) {
      // the sprite, then a slanted band of light over its pixels only
      canvas.saveLayer(dst.inflate(2), Paint());
      canvas.drawImageRect(img, src, dst, paint);
      final x = dst.left + (-0.25 + 1.5 * u) * dst.width, w = dst.width * 0.13;
      final band = Path()
        ..moveTo(x, dst.top)
        ..lineTo(x + w, dst.top)
        ..lineTo(x + w - dst.height * 0.35, dst.bottom)
        ..lineTo(x - dst.height * 0.35, dst.bottom)
        ..close();
      canvas.drawPath(band, Paint()
        ..blendMode = BlendMode.srcATop
        ..color = const Color(0x70E9DCFF));
      canvas.restore();
      return;
    }
  }
  canvas.drawImageRect(img, src, dst, paint);
  if (!alive) return;
  final crown = Offset(dst.center.dx, dst.top + dst.height * 0.32);
  if (kind == 'lumen') {
    final pulse = reduced ? 0.0 : math.sin(t * 1.7 + seed);
    final a = (0.20 + 0.08 * pulse + 0.28 * near).clamp(0.0, 0.6);
    final r = dst.width * (0.62 + 0.04 * pulse + 0.12 * near);
    canvas.drawCircle(
        crown,
        r,
        Paint()
          ..blendMode = BlendMode.plus
          ..shader = ui.Gradient.radial(crown, r, [Color.fromRGBO(111, 227, 192, a), const Color.fromRGBO(111, 227, 192, 0)]));
    if (reduced) return;
    for (var k = 0; k < 4; k++) {
      final p = (t * 0.28 + k * 0.25 + seed) % 1.0;
      final at = crown + Offset(math.sin(k * 2.3 + t * 0.9) * dst.width * 0.22, -p * dst.height * 0.95);
      final ma = math.sin(p * math.pi) * (0.55 + 0.45 * near);
      canvas.drawCircle(at, 2.4, Paint()..color = Color.fromRGBO(201, 248, 232, ma));
      canvas.drawCircle(at, 6, Paint()
        ..color = Color.fromRGBO(111, 227, 192, ma * 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3));
    }
    return;
  }
  if (reduced || (kind != 'copper' && kind != 'iron')) return;
  // a glint now and then where the metal catches the sun
  const spots = {
    'copper': [Offset(0.30, 0.30), Offset(0.62, 0.22), Offset(0.74, 0.55)],
    'iron': [Offset(0.28, 0.36), Offset(0.50, 0.24), Offset(0.66, 0.48)],
  };
  var i = 0;
  for (final sp in spots[kind]!) {
    final a = math.pow(math.max(0.0, math.sin(t * 1.1 + i * 2.1 + seed * 5)), 14).toDouble();
    i++;
    if (a < 0.02) continue;
    final c = Offset(dst.left + sp.dx * dst.width, dst.top + sp.dy * dst.height);
    final s = 5.0 + 3.0 * a;
    final pen = Paint()
      ..color = Color.fromRGBO(255, 250, 235, a)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c - Offset(s, 0), c + Offset(s, 0), pen);
    canvas.drawLine(c - Offset(0, s), c + Offset(0, s), pen);
    canvas.drawCircle(c, 1.8, Paint()..color = Color.fromRGBO(255, 255, 255, a));
  }
}
