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
import '../../core/services/haptics.dart';
import '../../game/engine.dart' as g;
import '../../game/mining/mining.dart' as mine;
import '../shared/action_button.dart';
import '../shared/kit.dart';
import '../shared/widgets.dart';
import 'mining_gear_ui.dart';

Future<void> showBramForge(BuildContext context) => showEvochiSheet<void>(context, builder: (_) => const _Forge());

const _stageArt = 'assets/art/village/forge_stage.webp';
// a dark iron-and-oak frame around the stage
final _stageFrame = BoxDecoration(
  color: const Color(0xFF1C130F),
  borderRadius: BorderRadius.circular(16),
  border: Border.all(color: const Color(0xFF5A3A24), width: 3),
  boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 10, offset: Offset(0, 4))],
);

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
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  @override
  void initState() {
    super.initState();
    // started here, not lazily: a lazy ticker only came to life in dispose, so the sweep never moved
    _ticker = createTicker(_tick)..start();
  }

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
      if (_rnd.nextDouble() < dt * 3) _motes.add(_Mote('ember', 0.187 + (_rnd.nextDouble() - 0.5) * 0.14, 0.6, (_rnd.nextDouble() - 0.5) * 0.03, -0.05 - _rnd.nextDouble() * 0.05, 1.6 + _rnd.nextDouble(), 1.5 + _rnd.nextDouble() * 1.5, const Color(0xFFFFB347)));
    }
    if (_quenchT >= 0) {
      final q = _t - _quenchT - 0.5; // since the bar went in
      if (q > 0 && q < 1.6) {
        final wx = _ForgePainter.water.dx, wy = _ForgePainter.water.dy, half = _ForgePainter.waterHalf;
        if (_rnd.nextDouble() < dt * 16 * (1 - q / 1.6)) {
          _motes.add(_Mote('steam', wx + (_rnd.nextDouble() - 0.5) * half * 1.5, wy - 0.01, (_rnd.nextDouble() - 0.5) * 0.08 + 0.02, -0.14 - _rnd.nextDouble() * 0.16, 1.2 + _rnd.nextDouble() * 1.0, 5 + _rnd.nextDouble() * 6, const Color(0xFFF2EEE8)));
        }
        if (_rnd.nextDouble() < dt * 30 * (1 - q / 1.6)) {
          _motes.add(_Mote('bubble', wx + (_rnd.nextDouble() - 0.5) * half * 1.6, wy + (_rnd.nextDouble() - 0.5) * 0.012, 0, -0.02, 0.25 + _rnd.nextDouble() * 0.3, 1.5 + _rnd.nextDouble() * 2.2, const Color(0xFFFFFFFF)));
        }
      }
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
      if (m.kind == 'drop') m.vy += dt * 2.6;
      if (m.kind == 'glint') {
        m.vy += dt * 0.5;
        m.vx *= 0.97;
      }
      if (m.kind == 'steam') {
        m.size += dt * 11;
        m.vx *= 0.98;
        m.vy *= 0.99;
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
    } else if (off < _ForgePainter.trueZone) {
      verdict = 'True!';
      gain = 2;
      _true++;
    } else if (off < _ForgePainter.goodZone) {
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
    c.audio.buzz(cold ? Haptic.tick : (gain >= 2 ? Haptic.thump : Haptic.hit));
    // sparks off the bar
    final n = cold ? 2 : (gain >= 2 ? 26 : 12);
    for (var i = 0; i < n; i++) {
      final a = -math.pi * (0.1 + 0.8 * _rnd.nextDouble());
      final sp = 0.25 + _rnd.nextDouble() * (gain >= 2 ? 0.9 : 0.55);
      _motes.add(_Mote('spark', 0.535 + (_rnd.nextDouble() - 0.5) * 0.06, 0.47, math.cos(a) * sp * 0.6, math.sin(a) * sp, 0.4 + _rnd.nextDouble() * 0.5, 1.2 + _rnd.nextDouble() * 1.8,
          [const Color(0xFFFFE08A), const Color(0xFFFFB347), const Color(0xFFFF7A2A)][_rnd.nextInt(3)]));
    }
    if (gain >= 2) _motes.add(_Mote('ring', 0.535, 0.47, 0, 0, 0.45, 1, const Color(0xFFFFE5A2)));
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
    c.audio.buzz(Haptic.tap);
    for (var i = 0; i < 10; i++) {
      _motes.add(_Mote('ember', 0.187 + (_rnd.nextDouble() - 0.5) * 0.16, 0.6, (_rnd.nextDouble() - 0.5) * 0.08, -0.12 - _rnd.nextDouble() * 0.2, 0.8 + _rnd.nextDouble() * 0.8, 1.5 + _rnd.nextDouble() * 2, const Color(0xFFFFC561)));
    }
    _flash = 0.3;
  }

  void _quench(GameController c) {
    if (_step != 1 || _quenchT >= 0) return;
    _quenchT = _t;
    Future.delayed(const Duration(milliseconds: 500), () {
      if (!mounted) return;
      c.audio.play('enc_soothe', volume: 0.6);
      c.audio.buzz(Haptic.soothe);
      // the splash: drops thrown up out of the barrel, falling back
      final wx = _ForgePainter.water.dx, wy = _ForgePainter.water.dy, half = _ForgePainter.waterHalf;
      for (var i = 0; i < 26; i++) {
        final u = (_rnd.nextDouble() - 0.5) * 2;
        _motes.add(_Mote('drop', wx + u * half * 0.7, wy, u * 0.16 + (_rnd.nextDouble() - 0.5) * 0.06, -0.55 - _rnd.nextDouble() * 0.45, 0.55 + _rnd.nextDouble() * 0.35, 1.4 + _rnd.nextDouble() * 1.6,
            [const Color(0xFFE8F7FF), const Color(0xFFB9E3F5), const Color(0xFFFFFFFF)][_rnd.nextInt(3)]));
      }
      // the first great puff of steam
      for (var i = 0; i < 10; i++) {
        _motes.add(_Mote('steam', wx + (_rnd.nextDouble() - 0.5) * half * 1.4, wy - 0.02, (_rnd.nextDouble() - 0.5) * 0.1, -0.22 - _rnd.nextDouble() * 0.2, 1.3 + _rnd.nextDouble() * 1.0, 7 + _rnd.nextDouble() * 7, const Color(0xFFF7F4EF)));
      }
      _heat = 0;
    });
    Future.delayed(const Duration(milliseconds: 1900), () {
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
    for (var i = 0; i < 22; i++) {
      final a = -math.pi * _rnd.nextDouble();
      final sp = 0.25 + _rnd.nextDouble() * 0.5;
      _motes.add(_Mote('glint', _ForgePainter.anvil.dx, _ForgePainter.anvil.dy - 0.2, math.cos(a) * sp * 0.6, math.sin(a) * sp, 0.7 + _rnd.nextDouble() * 0.6, 2 + _rnd.nextDouble() * 2.5, const Color(0xFFFFE5A2)));
    }
    _motes.add(_Mote('ring', _ForgePainter.anvil.dx, _ForgePainter.anvil.dy - 0.2, 0, 0, 0.6, 1, const Color(0xFFFFF1C8)));
    c.audio.buzz(Haptic.win);
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
        Container(
          height: 128,
          decoration: _stageFrame,
          child: ClipRRect(borderRadius: BorderRadius.circular(13), child: Image.asset(_stageArt, fit: BoxFit.cover, alignment: const Alignment(0, 0.2))),
        ),
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
      // the stage: the Blender-rendered forge corner, the live work painted over it
      LayoutBuilder(builder: (ctx, b) {
        final w = math.min(b.maxWidth, 460.0);
        final h = w * 840 / 1080;
        final piece = math.min(96.0, h * 0.4);
        return Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _strike(c),
            child: Container(
              width: w,
              height: h,
              decoration: _stageFrame,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(13),
                child: Stack(children: [
                  Positioned.fill(child: Image.asset(_stageArt, fit: BoxFit.fill, gaplessPlayback: true)),
                  Positioned.fill(child: CustomPaint(painter: _ForgePainter(this, ore: ore, def: d))),
                  if (_step >= 2)
                    Positioned(
                      left: w * _ForgePainter.anvil.dx - piece / 2,
                      // it floats, gently, and pops up a little when Bram hands it over
                      top: h * _ForgePainter.anvil.dy - h * 0.2 - piece / 2 + math.sin(_t * 2.0) * 3,
                      child: IgnorePointer(
                        child: Transform.scale(
                          scale: _step == 3 && _doneT >= 0 ? 1 + 0.18 * Curves.easeOutBack.transform(((_t - _doneT) / 0.5).clamp(0.0, 1.0)) : 1.0,
                          child: SizedBox.square(dimension: piece, child: FittedBox(child: _Shine(t: _t, child: ForgedPiece(def: d, finish: _finish)))),
                        ),
                      ),
                    ),
                ]),
              ),
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
        // the finishes, each shown on the piece itself
        Row(children: [
          for (final f in mine.gearFinishes.keys)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Semantics(
                  button: true,
                  selected: _finish == f,
                  label: mine.gearFinishes[f],
                  child: GestureDetector(
                    onTap: () {
                      c.audio.play('ui_tap', volume: 0.35);
                      c.audio.buzz(Haptic.tick);
                      setState(() => _finish = f);
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.fromLTRB(4, 6, 4, 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: _finish == f ? const [Color(0xFFFFF1C8), Color(0xFFF2D08A)] : const [Color(0xFFFBF2E2), Color(0xFFEADCC4)]),
                        border: Border.all(color: _finish == f ? const Color(0xFFB8862E) : const Color(0xFFC9B190), width: _finish == f ? 2.5 : 1.5),
                        boxShadow: [if (_finish == f) const BoxShadow(color: Color(0x66FFC94A), blurRadius: 10)],
                      ),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        SizedBox.square(dimension: 40, child: FittedBox(child: ForgedPiece(def: d, finish: f))),
                        const SizedBox(height: 3),
                        Text(mine.gearFinishes[f]!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 12.5, color: EvochiColor.ink)),
                      ]),
                    ),
                  ),
                ),
              ),
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

/// The live work over the stage picture (forge_stage.webp, rendered in Blender by tools/art/forge_stage.py):
/// the coals breathing with the heat, the bar being worked (its heat in its colour, longer and flatter as
/// it is shaped), the hammer's swing, the timing sweep, the heat gauge, and the motes.
class _ForgePainter extends CustomPainter {
  _ForgePainter(this.s, {this.ore, this.def});
  final _ForgeState s;
  final String? ore;
  final mine.GearDef? def;

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

  // where things fall in the stage picture (tools/art/forge_stage.py writes these), as fractions
  static const hearth = Offset(0.187, 0.612);
  static const anvil = Offset(0.520, 0.497); // the middle of the anvil's face
  static const water = Offset(0.833, 0.574);
  static const waterHalf = 0.072; // the water's half-width, of the stage's width
  static const pivot = Offset(0.745, 0.17); // where the hammer swings from (Bram's hand, off the top)
  static const trueZone = 0.09, goodZone = 0.24; // the sweep's zones, as |pos - 0.5|

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final t = s._t;
    final shake = s._shake;
    canvas.save();
    if (shake > 0) canvas.translate((s._rnd.nextDouble() - 0.5) * 6 * shake, (s._rnd.nextDouble() - 0.5) * 4 * shake);
    final heat = s._heat;
    final flick = 0.85 + 0.15 * math.sin(t * 9.1) * math.sin(t * 5.3 + 1);
    // the coals breathe with the heat: dim and ashy when cold, the bellows bring them roaring back
    final hc = Offset(w * hearth.dx, h * hearth.dy);
    canvas.drawOval(Rect.fromCenter(center: hc + Offset(0, h * 0.01), width: w * 0.24, height: h * 0.1), Paint()
      ..color = Color.fromRGBO(24, 14, 10, 0.6 * (1 - heat))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    canvas.drawCircle(hc, w * 0.34, Paint()
      ..blendMode = BlendMode.plus
      ..shader = radial(hc, w * 0.34, [Color.fromRGBO(255, 120, 40, (0.06 + 0.2 * heat) * flick), const Color(0x00FF7828)]));
    canvas.drawCircle(hc, w * 0.11, Paint()
      ..blendMode = BlendMode.plus
      ..shader = radial(hc, w * 0.11, [Color.fromRGBO(255, 205, 120, 0.4 * heat * flick), const Color(0x00FFCD78)]));
    // the heat gauge: a pill over the hood, the cold line marked
    {
      final x0 = w * 0.035, x1 = w * 0.34, y = h * 0.075;
      final track = RRect.fromRectAndRadius(Rect.fromLTRB(x0, y - 7, x1, y + 7), const Radius.circular(7));
      canvas.drawRRect(track.shift(const Offset(0, 2)), Paint()..color = const Color(0x66000000));
      canvas.drawRRect(track, Paint()..color = const Color(0xE6140E0B));
      final fx = x0 + 3 + (x1 - x0 - 6) * heat;
      if (heat > 0.01) {
        final fill = RRect.fromRectAndRadius(Rect.fromLTRB(x0 + 3, y - 4, fx, y + 4), const Radius.circular(4));
        canvas.drawRRect(fill, Paint()..shader = LinearGradient(colors: [heatColor(0.35, false), heatColor(math.max(0.36, heat), false)]).createShader(fill.outerRect));
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTRB(x0 + 5, y - 3.5, fx - 2, y - 1.5), const Radius.circular(1)), Paint()..color = const Color(0x55FFFFFF));
      }
      final cx = x0 + 3 + (x1 - x0 - 6) * 0.3;
      canvas.drawLine(Offset(cx, y - 9), Offset(cx, y + 9), Paint()
        ..color = const Color(0xFFBFD4E8)
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round);
      canvas.drawRRect(track, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = const Color(0xFF8A6A3E));
      final tp = TextPainter(
        text: const TextSpan(text: 'HEAT', style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 1, color: Color(0xFFFFE5A2), shadows: [Shadow(color: Color(0xCC000000), blurRadius: 3)])),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(x0 + 2, y + 9));
    }
    // the bar on the anvil: longer and flatter as it is shaped, its colour its heat
    final step = s._step;
    final shape = (s._shape / s._need).clamp(0.0, 1.0);
    final ax = w * anvil.dx, face = h * anvil.dy;
    final bw = w * (0.12 + 0.08 * shape), bh = h * (0.05 - 0.018 * shape);
    var bx = ax, by = face - bh / 2 - 1;
    var barA = 1.0;
    if (s._quenchT >= 0) {
      final k = ((t - s._quenchT) / 0.5).clamp(0.0, 1.0);
      final e = Curves.easeIn.transform(k);
      bx = ax + (w * water.dx - ax) * e;
      by = face - bh / 2 - math.sin(k * math.pi) * h * 0.22 + (h * water.dy - face) * e;
      barA = 1 - Curves.easeIn.transform(((t - s._quenchT - 0.45) / 0.15).clamp(0.0, 1.0));
    }
    if (step < 2 && barA > 0) {
      final copper = ore == 'copper_ore';
      final col = heatColor(heat, copper);
      final r = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(bx, by), width: bw, height: bh), Radius.circular(bh * 0.4));
      if (heat > 0.25) {
        canvas.drawCircle(Offset(bx, by), bw * 0.85, Paint()
          ..blendMode = BlendMode.plus
          ..shader = radial(Offset(bx, by), bw * 0.85, [col.withValues(alpha: 0.4 * heat * barA), col.withValues(alpha: 0)]));
      }
      canvas.drawRRect(r.shift(const Offset(0, 2.5)), Paint()..color = Color.fromRGBO(0, 0, 0, 0.4 * barA));
      final lit = Color.lerp(col, Colors.white, s._flash * 0.55)!;
      canvas.drawRRect(r, Paint()
        ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color.lerp(lit, Colors.white, 0.25)!.withValues(alpha: barA), lit.withValues(alpha: barA), Color.lerp(lit, Colors.black, 0.3)!.withValues(alpha: barA)])
            .createShader(r.outerRect));
      canvas.drawRRect(r, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = Color.fromRGBO(30, 20, 16, 0.7 * barA));
    }
    // the hammer: a hand off the top of the stage swings it down onto the bar
    if (step == 0) {
      final p = Offset(w * pivot.dx, h * pivot.dy);
      final hl = w * 0.06; // half the head's length
      final target = Offset(ax + w * 0.015, face - bh - 1);
      final v = target - p;
      final len = math.sqrt(math.max(1.0, v.distanceSquared - hl * hl));
      final down = math.atan2(v.dy, v.dx) - math.atan2(hl, -len);
      final up = down + 1.15;
      final ang = up + (down - up) * Curves.easeIn.transform(s._hammer);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(ang);
      final hw = w * 0.016;
      final handle = RRect.fromRectAndRadius(Rect.fromLTRB(-len, -hw, w * 0.06, hw), Radius.circular(hw));
      canvas.drawRRect(handle.shift(const Offset(0, 3)), Paint()..color = const Color(0x55000000));
      canvas.drawRRect(handle, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFD9A066), Color(0xFFA8703F), Color(0xFF7A4E2A)]).createShader(handle.outerRect));
      // the leather grip
      final grip = RRect.fromRectAndRadius(Rect.fromLTRB(-w * 0.04, -hw - 1, w * 0.06, hw + 1), Radius.circular(hw));
      canvas.drawRRect(grip, Paint()..color = const Color(0xFF4A2E1E));
      for (var gx = -w * 0.035; gx < w * 0.055; gx += w * 0.016) {
        canvas.drawLine(Offset(gx, -hw), Offset(gx + w * 0.008, hw), Paint()
          ..color = const Color(0xFF6E4A30)
          ..strokeWidth = 1.4);
      }
      canvas.drawRRect(handle, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = _ink);
      // the head: across the handle's end, its faces bright
      final head = RRect.fromRectAndRadius(Rect.fromCenter(center: Offset(-len, 0), width: w * 0.058, height: hl * 2), const Radius.circular(4));
      canvas.drawRRect(head.shift(const Offset(2, 3)), Paint()..color = const Color(0x66000000));
      canvas.drawRRect(head, Paint()..shader = const LinearGradient(colors: [Color(0xFF5A6168), Color(0xFFA9B2BB), Color(0xFF6E767E)]).createShader(head.outerRect));
      for (final sy in [-1.0, 1.0]) {
        canvas.drawRect(Rect.fromCenter(center: Offset(-len, sy * (hl - 2.5)), width: w * 0.058 - 2, height: 4), Paint()..color = const Color(0xFFD3DAE0));
      }
      canvas.drawRRect(head, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = _ink);
      canvas.drawRect(Rect.fromCenter(center: Offset(-len + w * 0.034, 0), width: w * 0.012, height: hw * 2.6), Paint()..color = const Color(0xFF3F3531));
      canvas.restore();
    }
    // the barrel's water: the bar's heat glowing out under the surface, the surface flashing, rings
    // spreading to the rim and settling
    final wc = Offset(w * water.dx, h * water.dy);
    final wHalf = w * waterHalf;
    final q = s._quenchT >= 0 ? t - s._quenchT - 0.5 : -1.0; // since the bar went in
    if (q >= 0 && q < 2.4) {
      final heatLeft = math.max(0.0, 1 - q / 1.1);
      if (heatLeft > 0) {
        canvas.drawCircle(wc + Offset(0, h * 0.03), wHalf * 1.5, Paint()
          ..blendMode = BlendMode.plus
          ..shader = radial(wc + Offset(0, h * 0.03), wHalf * 1.5, [Color.fromRGBO(255, 130, 50, 0.55 * heatLeft), const Color(0x00FF8232)]));
      }
      final surface = Rect.fromCenter(center: wc, width: wHalf * 2, height: h * 0.03);
      canvas.save();
      canvas.clipRect(Rect.fromLTRB(surface.left - 2, surface.top - h * 0.03, surface.right + 2, surface.bottom + 2));
      final flash = math.max(0.0, 1 - q / 0.5);
      if (flash > 0) canvas.drawOval(surface, Paint()..color = Color.fromRGBO(240, 250, 255, 0.55 * flash));
      for (var i = 0; i < 3; i++) {
        final k = (q - i * 0.22) / 1.3;
        if (k <= 0 || k >= 1) continue;
        final e = Curves.easeOut.transform(k);
        canvas.drawOval(Rect.fromCenter(center: wc, width: wHalf * 2 * (0.15 + 0.85 * e), height: h * 0.03 * (0.15 + 0.85 * e)), Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.2 * (1 - k) + 0.6
          ..color = Color.fromRGBO(255, 255, 255, 0.85 * (1 - k)));
      }
      canvas.restore();
    }
    // the timing sweep across the floor: copper for a good stroke, gold for a true one
    if (step == 0) {
      final x0 = w * 0.27, x1 = w * 0.77, yy = h * 0.9;
      final mid = (x0 + x1) / 2, span = x1 - x0;
      final bar = RRect.fromRectAndRadius(Rect.fromLTRB(x0 - 6, yy - 10, x1 + 6, yy + 10), const Radius.circular(10));
      canvas.drawRRect(bar.shift(const Offset(0, 3)), Paint()..color = const Color(0x88000000));
      canvas.drawRRect(bar, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF0E0A08), Color(0xFF241A14)]).createShader(bar.outerRect));
      final pos = s._sweep < 0.5 ? s._sweep * 2 : 2 - s._sweep * 2;
      final inTrue = (pos - 0.5).abs() < trueZone;
      final good = RRect.fromRectAndRadius(Rect.fromLTRB(mid - span * goodZone, yy - 6, mid + span * goodZone, yy + 6), const Radius.circular(6));
      canvas.drawRRect(good, Paint()..shader = const LinearGradient(colors: [Color(0x00B8773F), Color(0xFFB8773F), Color(0xFFB8773F), Color(0x00B8773F)], stops: [0, 0.25, 0.75, 1]).createShader(good.outerRect));
      final gold = RRect.fromRectAndRadius(Rect.fromLTRB(mid - span * trueZone, yy - 7, mid + span * trueZone, yy + 7), const Radius.circular(7));
      if (inTrue) {
        canvas.drawRRect(gold.inflate(5), Paint()
          ..color = const Color(0x88FFD66E)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
      }
      canvas.drawRRect(gold, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: inTrue ? const [Color(0xFFFFF4C2), Color(0xFFFFC94A)] : const [Color(0xFFFFE08A), Color(0xFFD9A030)]).createShader(gold.outerRect));
      canvas.drawRRect(bar, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = const Color(0xFF8A6A3E));
      final mx = x0 + span * pos;
      canvas.drawCircle(Offset(mx, yy), 13, Paint()
        ..color = const Color(0x66FFF4E2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
      final gem = Path()
        ..moveTo(mx, yy - 13)
        ..lineTo(mx + 7, yy)
        ..lineTo(mx, yy + 13)
        ..lineTo(mx - 7, yy)
        ..close();
      canvas.drawPath(gem, Paint()..color = const Color(0xFFFFFBF2));
      canvas.drawPath(gem, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _ink);
    }
    // the motes: sparks, embers, steam, the true-stroke ring
    for (final m in s._motes) {
      final k = (m.age / m.life).clamp(0.0, 1.0);
      final p = Offset(m.x * w, m.y * h);
      switch (m.kind) {
        case 'spark':
          final tail = Offset(m.vx * w, m.vy * h) * 0.035;
          canvas.drawLine(p - tail, p, Paint()
            ..color = m.color.withValues(alpha: 1 - k)
            ..strokeWidth = m.size * (1 - k * 0.5)
            ..strokeCap = StrokeCap.round);
        case 'ember':
          canvas.drawCircle(p, m.size * (1 - k), Paint()..color = m.color.withValues(alpha: 0.8 * (1 - k)));
        case 'drop':
          // a falling drop: a short streak along its flight, a bright head
          final flight = Offset(m.vx * w, m.vy * h);
          final speed = flight.distance;
          final streak = speed > 0 ? flight / speed * math.min(9.0, speed * 0.03) : Offset.zero;
          canvas.drawLine(p - streak, p, Paint()
            ..color = m.color.withValues(alpha: 0.75 * (1 - k * k))
            ..strokeWidth = m.size
            ..strokeCap = StrokeCap.round);
          canvas.drawCircle(p, m.size * 0.45, Paint()..color = Colors.white.withValues(alpha: 0.9 * (1 - k)));
        case 'bubble':
          canvas.drawCircle(p, m.size * (0.6 + 0.6 * k), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..color = m.color.withValues(alpha: 0.8 * (1 - k)));
        case 'glint':
          _star(canvas, p, m.size * 2.2 * (1 - k * 0.6), m.color.withValues(alpha: 1 - k));
        case 'steam':
          final puff = (k < 0.15 ? k / 0.15 : 1.0) * (1 - k);
          canvas.drawCircle(p, m.size, Paint()
            ..color = m.color.withValues(alpha: 0.42 * puff)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + m.size * 0.35));
          canvas.drawCircle(p + Offset(-m.size * 0.25, -m.size * 0.2), m.size * 0.55, Paint()
            ..color = Colors.white.withValues(alpha: 0.3 * puff)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 + m.size * 0.2));
        case 'ring':
          canvas.drawCircle(p, w * (0.04 + 0.2 * k), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4 * (1 - k) + 1
            ..color = m.color.withValues(alpha: 1 - k));
      }
    }
    // the verdict word over the anvil
    if (s._verdict != null && s._verdictT >= 0) {
      final k = ((t - s._verdictT) / 0.8).clamp(0.0, 1.0);
      if (k < 1) {
        final v = s._verdict!;
        final col = switch (v) { 'True!' => const Color(0xFFFFD66E), 'Good' => const Color(0xFFF2A867), 'Cold' => const Color(0xFFBFD4E8), 'Shaped' => const Color(0xFF9FF0DA), _ => const Color(0xFFE2CFB3) };
        final pop = 1 + 0.25 * (1 - Curves.easeOutBack.transform((k * 4).clamp(0.0, 1.0)));
        final tp = TextPainter(
          text: TextSpan(text: v, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: (v == 'True!' ? 26 : 20) * pop, color: col.withValues(alpha: 1 - k * k), shadows: const [Shadow(color: Color(0xDD000000), offset: Offset(0, 2), blurRadius: 4)])),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(ax - tp.width / 2, face - h * 0.24 - k * h * 0.08 - tp.height / 2));
      }
    }
    // the finished piece, held up over the anvil: slow light rays turning behind it, a breathing
    // halo, and stars that twinkle in and out round it
    if (step >= 2 && def != null) {
      final k = step == 3 && s._doneT >= 0 ? ((t - s._doneT) / 0.6).clamp(0.0, 1.0) : 0.0;
      final pop = Curves.easeOutBack.transform(k);
      final strong = step == 3 ? 0.6 + 0.4 * pop : 0.55;
      final c = Offset(ax, face - h * 0.2);
      final r = h * 0.2;
      final breathe = 0.9 + 0.1 * math.sin(t * 2.2);
      // rays
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(t * 0.25);
      const n = 14;
      for (var i = 0; i < n; i++) {
        final a0 = i * 2 * math.pi / n;
        final wide = i.isEven ? 0.09 : 0.05;
        final len = r * (i.isEven ? 2.3 : 1.7) * breathe;
        final ray = Path()
          ..moveTo(0, 0)
          ..lineTo(math.cos(a0 - wide) * len, math.sin(a0 - wide) * len)
          ..lineTo(math.cos(a0 + wide) * len, math.sin(a0 + wide) * len)
          ..close();
        canvas.drawPath(ray, Paint()
          ..blendMode = BlendMode.plus
          ..shader = radial(Offset.zero, len, [Color.fromRGBO(255, 222, 150, 0.32 * strong), const Color(0x00FFDE96)]));
      }
      canvas.restore();
      // halo
      canvas.drawCircle(c, r * 1.35 * breathe, Paint()
        ..blendMode = BlendMode.plus
        ..shader = radial(c, r * 1.35 * breathe, [Color.fromRGBO(255, 236, 190, 0.5 * strong), Color.fromRGBO(255, 200, 120, 0.18 * strong), const Color(0x00FFC878)]));
      // twinkles: each star has its own place and beat, grows, flares and goes
      for (var i = 0; i < 7; i++) {
        final period = 1.6 + (i % 3) * 0.35;
        final ph = ((t + i * 0.53) / period) % 1.0;
        final cycle = ((t + i * 0.53) / period).floor();
        final rr = math.Random(i * 977 + cycle * 31);
        final ang = rr.nextDouble() * 2 * math.pi;
        final dist = r * (0.75 + rr.nextDouble() * 0.6);
        final life = math.sin(ph * math.pi);
        if (life <= 0.02) continue;
        _star(canvas, c + Offset(math.cos(ang) * dist, math.sin(ang) * dist * 0.8), (4 + rr.nextDouble() * 5) * life * strong, Color.fromRGBO(255, 246, 220, life));
      }
    }
    canvas.restore();
  }

  /// A four-pointed twinkle: two slim diamonds crossed, a soft glow, a white heart.
  static void _star(Canvas canvas, Offset p, double size, Color col) {
    if (size <= 0.3) return;
    canvas.drawCircle(p, size * 0.9, Paint()
      ..blendMode = BlendMode.plus
      ..shader = radial(p, size * 0.9, [col.withValues(alpha: col.a * 0.45), col.withValues(alpha: 0)]));
    final thin = size * 0.16;
    final star = Path()
      ..moveTo(p.dx, p.dy - size)
      ..lineTo(p.dx + thin, p.dy - thin)
      ..lineTo(p.dx + size, p.dy)
      ..lineTo(p.dx + thin, p.dy + thin)
      ..lineTo(p.dx, p.dy + size)
      ..lineTo(p.dx - thin, p.dy + thin)
      ..lineTo(p.dx - size, p.dy)
      ..lineTo(p.dx - thin, p.dy - thin)
      ..close();
    canvas.drawPath(star, Paint()..color = col);
    canvas.drawCircle(p, thin * 0.9, Paint()..color = Colors.white.withValues(alpha: col.a));
  }

  static Shader radial(Offset c, double r, List<Color> colors) => RadialGradient(colors: colors).createShader(Rect.fromCircle(center: c, radius: r));

  @override
  bool shouldRepaint(_ForgePainter old) => true;
}

/// A band of light sweeping across a picture now and then (only where the picture is).
class _Shine extends StatelessWidget {
  const _Shine({required this.t, required this.child});
  final double t;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final k = (t % 2.6) / 0.9; // a sweep every 2.6 s, taking 0.9 s
    if (k >= 1) return child;
    final c = -0.4 + 1.8 * Curves.easeInOut.transform(k);
    return ShaderMask(
      blendMode: BlendMode.srcATop,
      shaderCallback: (r) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: const [Color(0x00FFFFFF), Color(0xB3FFFFFF), Color(0x00FFFFFF)],
        stops: [(c - 0.14).clamp(0.0, 1.0), c.clamp(0.0, 1.0), (c + 0.14).clamp(0.0, 1.0)],
      ).createShader(r),
      child: child,
    );
  }
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
