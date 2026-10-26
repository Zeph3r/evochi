// Bram's forge: pick a piece, then work it at the anvil. The bar comes out of the coals white-hot and
// cools with every stroke; you strike as the sweep crosses the gold (a true stroke shapes it twice as
// fast, an early or late one still shapes it, a cold one only rings), and you pump the bellows to bring
// the heat back. Once the piece has its shape it is quenched in the barrel (steam, a hiss) and given its
// finish. Never a failure: a poor stroke just takes another. Everything on the stage is painted live:
// the coals breathe, sparks fly and fall, embers drift up, steam rolls off the barrel.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../game/engine.dart' as g;
import '../../game/mining/mining.dart' as mine;
import '../shared/action_button.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import 'mining_gear_ui.dart';

Future<void> showBramForge(BuildContext context) => showEvochiSheet<void>(context, builder: (_) => const _Forge());

class _Forge extends StatefulWidget {
  const _Forge();
  @override
  State<_Forge> createState() => _ForgeState();
}

/// One spark, ember, or puff of steam on the stage.
class _Mote {
  _Mote(this.kind, this.x, this.y, this.vx, this.vy, this.life, this.size, this.color);
  final String kind; // spark | ember | steam | ring
  double x, y, vx, vy, life, size;
  final Color color;
  double age = 0;
}

class _ForgeState extends State<_Forge> with SingleTickerProviderStateMixin {
  mine.GearDef? _making;
  // the work: 0 at the anvil, 1 quenching, 2 the finish, 3 done (the piece shown)
  int _step = 0;
  double _heat = 0.92; // 1 white-hot .. 0 cold
  double _shape = 0; // strokes' worth of shaping done
  int _need = 8; // strokes' worth a piece takes
  int _true = 0, _strokes = 0; // true strokes, strokes in all (the memory line)
  double _sweep = 0; // the timing marker, 0..1 and back
  double _hammer = 0; // 0 raised .. 1 down (its own swing)
  double _hammerT = -1; // when the last swing began (seconds)
  double _shake = 0, _flash = 0;
  String? _verdict; // 'True!' | 'Good' | 'Cold'
  double _verdictT = -1;
  double _quenchT = -1; // the bar's drop into the barrel
  double _doneT = -1;
  String _finish = 'polished';
  double _t = 0;
  final _motes = <_Mote>[];
  final _rnd = math.Random();
  late final Ticker _ticker = createTicker(_tick)..start();
  Duration _last = Duration.zero;

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _tick(Duration e) {
    final dt = ((e - _last).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _last = e;
    _t += dt;
    if (_making != null && _step == 0) {
      _sweep = (_t / 1.15) % 1.0;
      _heat = math.max(0, _heat - dt * 0.022); // it cools on its own, slowly
      if (_rnd.nextDouble() < dt * 3) _motes.add(_Mote('ember', 0.17 + (_rnd.nextDouble() - 0.5) * 0.14, 0.62, (_rnd.nextDouble() - 0.5) * 0.03, -0.05 - _rnd.nextDouble() * 0.05, 1.6 + _rnd.nextDouble(), 1.5 + _rnd.nextDouble() * 1.5, const Color(0xFFFFB347)));
    }
    if (_hammerT >= 0) {
      final k = _t - _hammerT;
      _hammer = k < 0.09 ? k / 0.09 : (k < 0.32 ? 1 - (k - 0.09) / 0.23 : 0);
      if (k >= 0.32) _hammerT = -1;
    }
    _shake = math.max(0, _shake - dt * 4);
    _flash = math.max(0, _flash - dt * 5);
    for (final m in _motes) {
      m.age += dt;
      if (m.kind == 'spark') m.vy += dt * 1.6; // gravity (in stage heights a second)
      if (m.kind == 'steam') {
        m.size += dt * 9;
        m.vx *= 0.98;
      }
      m.x += m.vx * dt;
      m.y += m.vy * dt;
    }
    _motes.removeWhere((m) => m.age >= m.life);
    if (mounted) setState(() {});
  }

  // ---- the work
  void _strike(GameController c) {
    if (_step != 0 || _hammerT >= 0 && _t - _hammerT < 0.12) return;
    _hammerT = _t;
    _strokes++;
    // how near the gold the sweep is (the marker goes out and back)
    final pos = _sweep < 0.5 ? _sweep * 2 : 2 - _sweep * 2;
    final off = (pos - 0.5).abs(); // 0 dead centre .. 0.5
    final cold = _heat < 0.3;
    String verdict;
    double gain;
    if (cold) {
      verdict = 'Cold';
      gain = 0;
    } else if (off < 0.11) {
      verdict = 'True!';
      gain = 2;
      _true++;
    } else if (off < 0.26) {
      verdict = 'Good';
      gain = 1;
    } else {
      verdict = 'Early';
      if (pos > 0.5) verdict = 'Late';
      gain = 0.5;
    }
    gain *= 0.6 + 0.4 * _heat; // a hotter bar gives more
    _shape = math.min(_need.toDouble(), _shape + gain);
    _heat = math.max(0, _heat - (cold ? 0.02 : 0.13));
    _verdict = verdict;
    _verdictT = _t;
    _shake = cold ? 0.3 : (gain >= 2 ? 1.0 : 0.6);
    _flash = cold ? 0 : (gain >= 2 ? 1 : 0.5);
    c.audio.play(cold ? 'mine_clink' : (gain >= 2 ? 'mine_iron_break' : 'mine_iron_crack'), volume: cold ? 0.5 : 0.75);
    // sparks off the bar
    final n = cold ? 2 : (gain >= 2 ? 26 : 12);
    for (var i = 0; i < n; i++) {
      final a = -math.pi * (0.1 + 0.8 * _rnd.nextDouble());
      final sp = 0.25 + _rnd.nextDouble() * (gain >= 2 ? 0.9 : 0.55);
      _motes.add(_Mote('spark', 0.52 + (_rnd.nextDouble() - 0.5) * 0.06, 0.6, math.cos(a) * sp * 0.6, math.sin(a) * sp, 0.4 + _rnd.nextDouble() * 0.5, 1.2 + _rnd.nextDouble() * 1.8,
          [const Color(0xFFFFE08A), const Color(0xFFFFB347), const Color(0xFFFF7A2A)][_rnd.nextInt(3)]));
    }
    if (gain >= 2) _motes.add(_Mote('ring', 0.52, 0.6, 0, 0, 0.45, 1, const Color(0xFFFFE5A2)));
    if (_shape >= _need) {
      _step = 1;
      _verdict = 'Shaped';
      _verdictT = _t;
    }
  }

  void _pump(GameController c) {
    if (_step != 0) return;
    _heat = math.min(1.0, _heat + 0.17);
    c.audio.play('enc_glow', volume: 0.35);
    for (var i = 0; i < 10; i++) {
      _motes.add(_Mote('ember', 0.17 + (_rnd.nextDouble() - 0.5) * 0.16, 0.6, (_rnd.nextDouble() - 0.5) * 0.08, -0.12 - _rnd.nextDouble() * 0.2, 0.8 + _rnd.nextDouble() * 0.8, 1.5 + _rnd.nextDouble() * 2, const Color(0xFFFFC561)));
    }
    _flash = 0.3;
  }

  void _quench(GameController c) {
    if (_step != 1 || _quenchT >= 0) return;
    _quenchT = _t;
    Future.delayed(const Duration(milliseconds: 520), () {
      if (!mounted) return;
      c.audio.play('enc_soothe', volume: 0.6);
      for (var i = 0; i < 18; i++) {
        _motes.add(_Mote('steam', 0.86 + (_rnd.nextDouble() - 0.5) * 0.08, 0.64, (_rnd.nextDouble() - 0.5) * 0.12, -0.18 - _rnd.nextDouble() * 0.2, 1.2 + _rnd.nextDouble() * 1.2, 6 + _rnd.nextDouble() * 8, const Color(0xFFF2EEE8)));
      }
      _heat = 0;
    });
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _step = 2);
    });
  }

  void _done(GameController c, mine.GearDef d) {
    final r = c.run((s, now) => mine.forgeGear(s, d.id, 'bram:${d.id}:$now', now, finish: _finish), quiet: true);
    if (!r.ok) {
      c.toast(whyNotGear(r), icon: 'warning', kind: 'warn');
      return;
    }
    c.audio.play('reward_chime', volume: 0.7);
    final word = _true >= _need ~/ 2 ? 'Every stroke of that rang true.' : (_true > 0 ? 'That one will last.' : 'Rough, but it will hold.');
    c.toast('${d.name}, ${mine.gearFinishes[_finish]!.toLowerCase()}, in $_strokes strokes. Bram nods: "$word"', icon: 'star');
    setState(() {
      _step = 3;
      _doneT = _t;
    });
  }

  void _start(mine.GearDef x) => setState(() {
        _making = x;
        _step = 0;
        _heat = 0.92;
        _shape = 0;
        _need = 6 + 2 * x.tier;
        _true = 0;
        _strokes = 0;
        _quenchT = -1;
        _doneT = -1;
        _verdict = null;
        _motes.clear();
      });

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final d = _making;
    if (d == null) {
      final defs = mine.gearDefs.values.where((x) => x.maker == 'bram').toList()..sort((a, b) => a.tier - b.tier);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        gearSheetHead("Bram's Forge", 'Ah, back from the trail? Let’s see what that ore can become.', s),
        SizedBox(height: 120, child: CustomPaint(painter: _ForgePainter(this, idle: true))),
        const SizedBox(height: 10),
        for (final x in defs)
          Builder(builder: (context) {
            final owned = mine.ownedGear(s, x.id);
            final can = x.ore.entries.every((e) => g.ownedQty(s, e.key) >= e.value);
            return GearCard(
              def: x,
              state: s,
              note: owned == null ? null : 'Forged: ${gearMemory(owned)}',
              trailing: owned != null
                  ? const SizedBox(width: 72)
                  : EvochiButton(label: 'Forge', small: true, expand: false, onPressed: can ? () => _start(x) : null),
            );
          }),
        Align(
          alignment: Alignment.centerRight,
          child: EvochiButton(label: 'Done', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => Navigator.of(context).pop()),
        ),
      ]);
    }
    final ore = d.ore.keys.first;
    final cold = _heat < 0.3;
    final words = switch (_step) {
      0 => cold ? 'The bar has gone dull. Pump the bellows and bring the colour back.' : 'Strike as the marker crosses the gold. A true stroke shapes it twice as fast.',
      1 => 'It has its shape. Into the barrel with it.',
      2 => 'Choose a finish. It’s how this piece will look, always.',
      _ => 'Done. Bram turns it over once and hands it across.',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      gearSheetHead(d.name, switch (_step) { 0 => 'Shape it at the anvil', 1 => 'Quench it', 2 => 'Finish it', _ => 'Forged' }, s),
      // the stage
      LayoutBuilder(builder: (ctx, b) {
        final w = b.maxWidth;
        final h = math.min(300.0, w * 0.78);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _strike(c),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: w,
              height: h,
              child: Stack(children: [
                Positioned.fill(child: CustomPaint(painter: _ForgePainter(this, ore: ore, def: d))),
                if (_step >= 2)
                  Positioned(
                    left: w * 0.52 - 48,
                    top: h * 0.42 - 48,
                    child: IgnorePointer(child: ForgedPiece(def: d, finish: _finish)),
                  ),
              ]),
            ),
          ),
        );
      }),
      const SizedBox(height: 8),
      // the shaping, as a bar of the piece's silhouette filling in
      if (_step == 0 || _step == 1)
        Row(children: [
          const Text('Shape', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, color: EvochiColor.textHelper)),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Stack(children: [
                Container(height: 10, color: const Color(0xFFE2CFB3)),
                FractionallySizedBox(
                  widthFactor: (_shape / _need).clamp(0.0, 1.0),
                  child: Container(
                    height: 10,
                    decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFFB8773F), Color(0xFFF2A867)])),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 8),
          Text('$_true true', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, color: EvochiColor.gold900)),
        ]),
      const SizedBox(height: 8),
      Text(words, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 14.5, height: 1.35, color: EvochiColor.ink)),
      const SizedBox(height: 10),
      if (_step == 0)
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          ActionButton(
            label: 'Bellows',
            size: 62,
            palette: KitButtonPalette.cream,
            icon: 'aff_ember',
            ready: cold,
            onDown: () => _pump(c),
            hint: 'Pumps heat into the bar',
          ),
          ActionButton(
            label: 'Strike',
            size: 84,
            icon: 'aff_stone',
            ready: !cold,
            dim: cold,
            onDown: () => _strike(c),
            hint: 'Strike the bar as the marker crosses the gold',
          ),
        ])
      else if (_step == 1)
        EvochiButton(label: _quenchT >= 0 ? 'Hisss...' : 'Quench it', tone: ButtonTone.cream, icon: const VoxelIcon('aff_water', size: 22), onPressed: _quenchT >= 0 ? null : () => _quench(c))
      else if (_step == 2) ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in mine.gearFinishes.keys)
            ChoiceChip(
              label: Text(mine.gearFinishes[f]!),
              selected: _finish == f,
              selectedColor: EvochiColor.gold300,
              onSelected: (_) => setState(() => _finish = f),
            ),
        ]),
        const SizedBox(height: 10),
        EvochiButton(label: 'Finish it', onPressed: () => _done(c, d)),
      ] else
        Row(children: [
          Expanded(child: EvochiButton(label: 'Forge another', tone: ButtonTone.cream, onPressed: () => setState(() => _making = null))),
          const SizedBox(width: 8),
          Expanded(child: EvochiButton(label: 'Done', onPressed: () => Navigator.of(context).pop())),
        ]),
    ]);
  }
}

/// The stage: the forge wall, the hearth and its coals, the anvil on its stump, the quench barrel, the
/// bar being worked (its heat in its colour, the piece's shape growing in it), the hammer's swing, the
/// timing sweep, the heat gauge, and the motes.
class _ForgePainter extends CustomPainter {
  _ForgePainter(this.s, {this.ore, this.def, this.idle = false});
  final _ForgeState s;
  final String? ore;
  final mine.GearDef? def;
  final bool idle;

  static const _ink = Color(0xFF1E1410);

  /// The bar's colour by heat: white-yellow, orange, cherry, dull, cold iron.
  static Color heatColor(double h, bool copper) {
    const stops = [Color(0xFF3B3B40), Color(0xFF5A2A26), Color(0xFFB03A22), Color(0xFFFF7A2A), Color(0xFFFFC561), Color(0xFFFFF1C8)];
    final k = (h.clamp(0.0, 1.0) * (stops.length - 1));
    final i = k.floor().clamp(0, stops.length - 2);
    var col = Color.lerp(stops[i], stops[i + 1], k - i)!;
    if (copper && h < 0.3) col = Color.lerp(col, const Color(0xFFB8773F), 0.6 * (1 - h / 0.3))!;
    return col;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = s._t;
    final shake = s._shake;
    canvas.save();
    if (shake > 0) canvas.translate((s._rnd.nextDouble() - 0.5) * 6 * shake, (s._rnd.nextDouble() - 0.5) * 4 * shake);
    // the wall and floor
    canvas.drawRect(Offset.zero & size, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF2B1D17), Color(0xFF3F2A20)]).createShader(Offset.zero & size));
    final brick = Paint()..color = const Color(0x22FFFFFF);
    for (var y = 0.0; y < h * 0.72; y += h * 0.09) {
      final off = ((y / (h * 0.09)).round() % 2) * w * 0.07;
      for (var x = -w * 0.07 + off; x < w; x += w * 0.14) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(x + 2, y + 2, w * 0.14 - 4, h * 0.09 - 4), const Radius.circular(3)), brick);
      }
    }
    canvas.drawRect(Rect.fromLTWH(0, h * 0.72, w, h * 0.28), Paint()..color = const Color(0xFF4A3A30));
    canvas.drawRect(Rect.fromLTWH(0, h * 0.72, w, 3), Paint()..color = const Color(0xFF2B1D17));
    // the hearth's glow on the wall
    final heat = idle ? 0.7 : s._heat;
    final flick = 0.85 + 0.15 * math.sin(t * 9.1) * math.sin(t * 5.3 + 1);
    canvas.drawCircle(Offset(w * 0.17, h * 0.6), w * 0.26, Paint()
      ..shader = radial(Offset(w * 0.17, h * 0.6), w * 0.26, [Color.fromRGBO(255, 140, 50, (0.28 + 0.1 * heat) * flick), const Color(0x00FF8C32)]));
    // the hearth: a brick arch with the coals in it
    final hx = w * 0.17, hy = h * 0.62;
    final arch = Path()
      ..moveTo(hx - w * 0.14, h * 0.72)
      ..lineTo(hx - w * 0.14, hy - h * 0.1)
      ..quadraticBezierTo(hx, hy - h * 0.42, hx + w * 0.14, hy - h * 0.1)
      ..lineTo(hx + w * 0.14, h * 0.72)
      ..close();
    canvas.drawPath(arch, Paint()..color = const Color(0xFF6E4A3C));
    canvas.drawPath(arch, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _ink);
    final mouth = Path()
      ..moveTo(hx - w * 0.1, h * 0.72)
      ..lineTo(hx - w * 0.1, hy - h * 0.05)
      ..quadraticBezierTo(hx, hy - h * 0.3, hx + w * 0.1, hy - h * 0.05)
      ..lineTo(hx + w * 0.1, h * 0.72)
      ..close();
    canvas.drawPath(mouth, Paint()..color = const Color(0xFF14100E));
    // coals: a bed of glowing lumps, brighter with the heat
    final rnd = math.Random(7);
    for (var i = 0; i < 16; i++) {
      final cx = hx + (rnd.nextDouble() - 0.5) * w * 0.17, cy = h * 0.72 - rnd.nextDouble() * h * 0.08;
      final r = w * (0.012 + rnd.nextDouble() * 0.014);
      final glow = (0.35 + 0.65 * heat) * (0.75 + 0.25 * math.sin(t * (4 + rnd.nextDouble() * 3) + i));
      canvas.drawCircle(Offset(cx, cy), r, Paint()..color = Color.lerp(const Color(0xFF3A2A22), const Color(0xFFFFB347), glow)!);
    }
    canvas.drawCircle(Offset(hx, h * 0.69), w * 0.09, Paint()
      ..shader = radial(Offset(hx, h * 0.69), w * 0.09, [Color.fromRGBO(255, 190, 90, 0.55 * heat * flick), const Color(0x00FFBE5A)]));
    // the heat gauge beside the hearth
    if (!idle) {
      final gx = w * 0.035, gy0 = h * 0.2, gy1 = h * 0.68;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(gx - 5, gy0 - 4, gx + 5, gy1 + 4), const Radius.circular(5)), Paint()..color = const Color(0xFF14100E));
      final gh = (gy1 - gy0) * heat;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(gx - 3, gy1 - gh, gx + 3, gy1), const Radius.circular(3)), Paint()..color = heatColor(heat, false));
      // the cold line
      final cy = gy1 - (gy1 - gy0) * 0.3;
      canvas.drawLine(Offset(gx - 7, cy), Offset(gx + 7, cy), Paint()
        ..color = const Color(0xFFBFD4E8)
        ..strokeWidth = 1.5);
    }
    // the anvil on its stump
    final ax = w * 0.52, ay = h * 0.6;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(ax, ay + h * 0.2), width: w * 0.16, height: h * 0.2), const Radius.circular(4)), Paint()..color = const Color(0xFF5E3A24));
    canvas.drawRect(Rect.fromCenter(center: Offset(ax, ay + h * 0.1), width: w * 0.16, height: 4), Paint()..color = const Color(0xFF3E2516));
    final anvil = Path()
      ..moveTo(ax - w * 0.19, ay)
      ..lineTo(ax + w * 0.14, ay)
      ..quadraticBezierTo(ax + w * 0.22, ay + h * 0.01, ax + w * 0.24, ay + h * 0.035)
      ..lineTo(ax + w * 0.13, ay + h * 0.06)
      ..lineTo(ax + w * 0.08, ay + h * 0.1)
      ..lineTo(ax - w * 0.08, ay + h * 0.1)
      ..lineTo(ax - w * 0.13, ay + h * 0.06)
      ..lineTo(ax - w * 0.19, ay + h * 0.06)
      ..close();
    canvas.drawPath(anvil, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF7A838C), Color(0xFF454A52)]).createShader(Rect.fromLTWH(ax - w * 0.2, ay, w * 0.44, h * 0.1)));
    canvas.drawPath(anvil, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _ink);
    canvas.drawLine(Offset(ax - w * 0.17, ay + 3), Offset(ax + w * 0.12, ay + 3), Paint()
      ..color = const Color(0x66FFFFFF)
      ..strokeWidth = 2);
    // the bar: longer and flatter as it is shaped; the piece's picture grows into it
    final step = s._step;
    final shape = idle ? 0.3 : (s._shape / s._need).clamp(0.0, 1.0);
    var bx = ax, by = ay - h * 0.028;
    var barA = 1.0;
    if (s._quenchT >= 0) {
      final k = ((t - s._quenchT) / 0.5).clamp(0.0, 1.0);
      final e = Curves.easeIn.transform(k);
      bx = ax + (w * 0.86 - ax) * e;
      by = ay - h * 0.028 - math.sin(k * math.pi) * h * 0.22 + h * 0.06 * e;
      barA = 1 - Curves.easeIn.transform(((t - s._quenchT - 0.45) / 0.15).clamp(0.0, 1.0));
    }
    if (step < 3 && barA > 0) {
      final bw = w * (0.13 + 0.09 * shape), bh = h * (0.055 - 0.02 * shape);
      final copper = ore == 'copper_ore';
      final col = heatColor(idle ? 0.8 : heat, copper);
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(bx, by + 4), width: bw, height: bh), const Radius.circular(3)), Paint()..color = Color.fromRGBO(0, 0, 0, 0.35 * barA));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(bx, by), width: bw, height: bh), const Radius.circular(3)),
          Paint()..color = Color.lerp(col, Colors.white, s._flash * 0.5)!.withValues(alpha: barA));
      if (heat > 0.3 || idle) {
        canvas.drawCircle(Offset(bx, by), bw * 0.7, Paint()
          ..shader = radial(Offset(bx, by), bw * 0.7, [col.withValues(alpha: 0.35 * (idle ? 0.8 : heat) * barA), col.withValues(alpha: 0)]));
      }
    }
    // the hammer: pivoting from the right, down onto the bar
    if (step == 0 && !idle) {
      final ang = -0.95 + 1.15 * Curves.easeIn.transform(s._hammer); // radians from horizontal
      final px = ax + w * 0.3, py = ay - h * 0.26;
      canvas.save();
      canvas.translate(px, py);
      canvas.rotate(ang);
      final L = w * 0.3;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-L, -5, L, 10), const Radius.circular(4)), Paint()..color = const Color(0xFFA8703F));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(-L, -5, L, 10), const Radius.circular(4)), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = _ink);
      final head = RRect.fromRectAndRadius(Rect.fromLTWH(-L - w * 0.03, -h * 0.07, w * 0.09, h * 0.14), const Radius.circular(5));
      canvas.drawRRect(head, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF9AA3AC), Color(0xFF5A6168)]).createShader(head.outerRect));
      canvas.drawRRect(head, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _ink);
      canvas.restore();
    }
    // the quench barrel
    final qx = w * 0.86, qy = h * 0.64;
    canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(qx, qy + h * 0.1), width: w * 0.17, height: h * 0.22), const Radius.circular(8)), Paint()..color = const Color(0xFF6E4529));
    for (final dy in [-0.06, 0.06]) {
      canvas.drawRect(Rect.fromCenter(center: Offset(qx, qy + h * 0.1 + h * dy), width: w * 0.175, height: 4), Paint()..color = const Color(0xFF3F3531));
    }
    canvas.drawOval(Rect.fromCenter(center: Offset(qx, qy), width: w * 0.16, height: h * 0.05), Paint()..color = const Color(0xFF4F3726));
    final ripple = s._quenchT >= 0 ? math.max(0.0, 1 - (t - s._quenchT - 0.5) / 1.2) : 0.0;
    canvas.drawOval(Rect.fromCenter(center: Offset(qx, qy), width: w * 0.13, height: h * 0.038), Paint()..color = Color.lerp(const Color(0xFF6FB7D4), const Color(0xFFDDF3F6), ripple * 0.6)!);
    if (ripple > 0) {
      canvas.drawOval(Rect.fromCenter(center: Offset(qx, qy), width: w * 0.13 * (0.4 + 0.6 * (1 - ripple)), height: h * 0.038 * (0.4 + 0.6 * (1 - ripple))), Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Color.fromRGBO(255, 255, 255, ripple));
    }
    // the timing sweep under the anvil: a bar with the gold in the middle and the marker going across
    if (step == 0 && !idle) {
      final x0 = w * 0.3, x1 = w * 0.74, yy = h * 0.9;
      final bar = RRect.fromRectAndRadius(Rect.fromLTRB(x0, yy - 7, x1, yy + 7), const Radius.circular(7));
      canvas.drawRRect(bar, Paint()..color = const Color(0xFF14100E));
      final mid = (x0 + x1) / 2, span = x1 - x0;
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(mid - span * 0.13, yy - 5, mid + span * 0.13, yy + 5), const Radius.circular(5)), Paint()..color = const Color(0xFFB8773F));
      canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(mid - span * 0.055, yy - 5, mid + span * 0.055, yy + 5), const Radius.circular(5)), Paint()..color = const Color(0xFFFFD66E));
      final pos = s._sweep < 0.5 ? s._sweep * 2 : 2 - s._sweep * 2;
      final mx = x0 + span * pos;
      final marker = Path()
        ..moveTo(mx, yy - 11)
        ..lineTo(mx - 6, yy - 19)
        ..lineTo(mx + 6, yy - 19)
        ..close();
      canvas.drawPath(marker, Paint()..color = const Color(0xFFFFF4E2));
      canvas.drawLine(Offset(mx, yy - 10), Offset(mx, yy + 10), Paint()
        ..color = const Color(0xFFFFF4E2)
        ..strokeWidth = 2);
    }
    // the motes: sparks, embers, steam, the true-stroke ring
    for (final m in s._motes) {
      final k = (m.age / m.life).clamp(0.0, 1.0);
      final p = Offset(m.x * w, m.y * h);
      switch (m.kind) {
        case 'spark':
          canvas.drawCircle(p, m.size * (1 - k * 0.5), Paint()..color = m.color.withValues(alpha: 1 - k));
        case 'ember':
          canvas.drawCircle(p, m.size * (1 - k), Paint()..color = m.color.withValues(alpha: 0.8 * (1 - k)));
        case 'steam':
          canvas.drawCircle(p, m.size, Paint()
            ..color = m.color.withValues(alpha: 0.35 * (1 - k))
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
        case 'ring':
          canvas.drawCircle(p, w * (0.04 + 0.2 * k), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4 * (1 - k) + 1
            ..color = m.color.withValues(alpha: 1 - k));
      }
    }
    // the verdict word over the anvil
    if (s._verdict != null && s._verdictT >= 0 && !idle) {
      final k = ((t - s._verdictT) / 0.8).clamp(0.0, 1.0);
      if (k < 1) {
        final v = s._verdict!;
        final col = switch (v) { 'True!' => const Color(0xFFFFD66E), 'Good' => const Color(0xFFF2A867), 'Cold' => const Color(0xFFBFD4E8), 'Shaped' => const Color(0xFF9FF0DA), _ => const Color(0xFFE2CFB3) };
        final tp = TextPainter(
          text: TextSpan(text: v, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: v == 'True!' ? 24 : 19, color: col.withValues(alpha: 1 - k * k), shadows: const [Shadow(color: Color(0xCC000000), offset: Offset(0, 2), blurRadius: 3)])),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(ax - tp.width / 2, ay - h * 0.2 - k * h * 0.1 - tp.height / 2));
      }
    }
    // the finished piece, held up
    if (step >= 2 && def != null) {
      final k = step == 3 && s._doneT >= 0 ? ((t - s._doneT) / 0.5).clamp(0.0, 1.0) : 0.0;
      final pop = Curves.elasticOut.transform(k);
      final r = w * 0.14 * (1 + 0.25 * pop);
      canvas.drawCircle(Offset(ax, ay - h * 0.18), r * 1.6, Paint()
        ..shader = radial(Offset(ax, ay - h * 0.18), r * 1.6, [Color.fromRGBO(255, 229, 162, 0.35 + 0.3 * pop), const Color(0x00FFE5A2)]));
      if (step == 3) {
        for (var i = 0; i < 8; i++) {
          final a = i * math.pi / 4 + t * 0.6;
          final rr = r * (1.4 + 0.4 * math.sin(t * 3 + i));
          canvas.drawCircle(Offset(ax + math.cos(a) * rr, ay - h * 0.18 + math.sin(a) * rr * 0.6), 2.5, Paint()..color = const Color(0xFFFFE5A2));
        }
      }
    }
    canvas.restore();
  }

  static Shader radial(Offset c, double r, List<Color> colors) => RadialGradient(colors: colors).createShader(Rect.fromCircle(center: c, radius: r));

  @override
  bool shouldRepaint(_ForgePainter old) => true;
}

/// The item's picture over the stage once it has its shape (a widget, so it uses the item art).
class ForgedPiece extends StatelessWidget {
  const ForgedPiece({super.key, required this.def, required this.finish});
  final mine.GearDef def;
  final String finish;
  @override
  Widget build(BuildContext context) {
    final matrix = switch (finish) {
      'brushed' => const <double>[0.8, 0.1, 0.1, 0, 0, 0.1, 0.8, 0.1, 0, 0, 0.1, 0.1, 0.8, 0, 0, 0, 0, 0, 1, 0],
      'engraved' => const <double>[1.0, 0, 0, 0, 10, 0, 0.95, 0, 0, 5, 0, 0, 0.85, 0, 0, 0, 0, 0, 1, 0],
      _ => const <double>[1.08, 0, 0, 0, 8, 0, 1.08, 0, 0, 8, 0, 0, 1.08, 0, 0, 0, 0, 0, 1, 0],
    };
    return ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: ItemImage('gear_${def.id}', size: 96));
  }
}
