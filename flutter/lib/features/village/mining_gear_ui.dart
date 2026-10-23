// Mining gear on screen (MINES_PLAN.md): Flint's shop at the Crossing, the loadout you wear on the Old
// Trail and in the mines, and Bram's forge in the village (three short steps: prepare, shape, finish).
// Gear is its own loadout: it never takes off a wearable, it only covers it while you're out mining.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app/theme.dart';
import '../../controllers/game_controller.dart';
import '../../core/models/catalog.dart';
import '../../core/models/game_state.dart';
import '../../core/services/haptics.dart';
import '../../game/engine.dart' as g;
import '../../game/mining/mining.dart' as mine;
import '../shared/widgets.dart';

const _mapNames = {'trail': 'the Old Trail', 'mine': 'the mines'};

String _oreName(String id) => catalog[id]?.name ?? id;

/// What a piece costs, as small chips: coins, and each ore with how many you have of it.
class _Cost extends StatelessWidget {
  const _Cost(this.def, this.state);
  final mine.GearDef def;
  final GameState state;

  @override
  Widget build(BuildContext context) {
    final bal = g.balanceOf(state);
    Widget chip(Widget icon, String text, bool ok) => Container(
          margin: const EdgeInsets.only(right: 6, top: 4),
          padding: const EdgeInsets.fromLTRB(4, 2, 8, 2),
          decoration: BoxDecoration(
            color: ok ? const Color(0xFFF7EBD6) : const Color(0xFFF6DCD4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ok ? EvochiColor.border : const Color(0xFFD08A7A)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            icon,
            const SizedBox(width: 3),
            Text(text, style: TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 13, color: ok ? EvochiColor.ink : const Color(0xFF9A3B2B))),
          ]),
        );
    return Wrap(children: [
      if (def.coins > 0) chip(const VoxelIcon('coin', size: 18), '${def.coins}', bal >= def.coins),
      for (final e in def.ore.entries)
        chip(ItemImage(e.key, size: 20), '${g.ownedQty(state, e.key)}/${e.value} ${_oreName(e.key)}', g.ownedQty(state, e.key) >= e.value),
    ]);
  }
}

/// A piece of gear: its icon, name, what it does, and its button.
class _GearCard extends StatelessWidget {
  const _GearCard({required this.def, required this.state, required this.trailing, this.note});
  final mine.GearDef def;
  final GameState state;
  final Widget trailing;
  final String? note;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(8, 8, 10, 8),
        decoration: BoxDecoration(
          color: EvochiColor.shell,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: EvochiColor.border, width: 1.5),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: const Color(0xFFF3E1C6), borderRadius: BorderRadius.circular(12)),
            child: ItemImage('gear_${def.id}', size: 64),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(def.name, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 16, color: EvochiColor.ink)),
              Text('${mine.gearSlotNames[def.slot]} · ${mine.tierNames[def.tier]} tier',
                  style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 12, color: EvochiColor.textHelper)),
              const SizedBox(height: 3),
              Text(def.desc, style: const TextStyle(fontFamily: EvochiText.body, fontSize: 13, height: 1.3, color: EvochiColor.textSecondary)),
              if (def.stats.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(def.stats.join(' · '),
                      style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, color: EvochiColor.healthy)),
                ),
              if (note != null)
                Text(note!, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w800, fontSize: 12.5, color: EvochiColor.gold900))
              else
                _Cost(def, state),
            ]),
          ),
          const SizedBox(width: 8),
          trailing,
        ]),
      );
}

Widget _sheetHead(String title, String sub, GameState s) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: EvochiText.section),
            Text(sub, style: EvochiText.caption),
          ]),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
          decoration: BoxDecoration(color: const Color(0xFF5A3418), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const VoxelIcon('coin', size: 20),
            const SizedBox(width: 4),
            Text('${g.balanceOf(s)}', style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: Colors.white)),
          ]),
        ),
      ]),
    );

String _why(g.ActionResult r) => switch (r.error) {
      'insufficient' => 'Not enough EvoCoins yet: ${r.info['short']} more.',
      'missing_ore' => 'Not enough ore yet: ${((r.info['missing'] as Map?) ?? const {}).entries.map((e) => '${e.value} more ${_oreName(e.key as String)}').join(', ')}.',
      'owned' => 'You already have that one.',
      _ => "That didn't work.",
    };

// ------------------------------------------------------------------------------------- Flint's shop
/// Flint's shop: the tools of the trade, for EvoCoins (and ore from the iron tier up). A piece you buy
/// goes on at once if its slot is empty.
Future<void> showFlintShop(BuildContext context) => showEvochiSheet<void>(context, builder: (_) => const _FlintShop());

class _FlintShop extends StatelessWidget {
  const _FlintShop();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final defs = mine.gearDefs.values.where((d) => d.maker == 'flint').toList()..sort((a, b) => a.tier != b.tier ? a.tier - b.tier : a.coins - b.coins);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _sheetHead("Flint's Shop", 'Good gear makes for happier miners. Worn on the trail and in the mines only.', s),
      for (final d in defs)
        Builder(builder: (context) {
          final owned = mine.ownedGear(s, d.id);
          final worn = owned != null && s.mining.loadout[d.slot] == owned.id;
          return _GearCard(
            def: d,
            state: s,
            note: owned == null ? null : (worn ? 'Wearing it' : 'Yours: in your gear'),
            trailing: owned != null
                ? (worn
                    ? const SizedBox(width: 72)
                    : EvochiButton(label: 'Wear', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => _wear(c, owned.id)))
                : EvochiButton(label: 'Buy', small: true, expand: false, onPressed: () => _buy(context, c, d)),
          );
        }),
      Align(
        alignment: Alignment.centerRight,
        child: EvochiButton(label: 'Done', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => Navigator.of(context).pop()),
      ),
    ]);
  }

  void _buy(BuildContext context, GameController c, mine.GearDef d) {
    final r = c.run((s, now) => mine.buyGear(s, d.id, 'flint:${d.id}:$now', now), quiet: true);
    if (!r.ok) {
      c.toast(_why(r), icon: 'warning', kind: 'warn');
      c.audio.play('error_bonk', volume: 0.5);
      return;
    }
    final worn = r.events.any((e) => e.data['worn'] == true);
    c.audio.play('purchase', volume: 0.7);
    c.toast(worn ? '${d.name}: it’s on! Ready to mine.' : '${d.name} is yours. Wear it from your gear.', icon: 'shop');
  }
}

void _wear(GameController c, String pieceId) {
  final r = c.run((s, now) => mine.wearGear(s, pieceId), quiet: true);
  if (r.ok) c.audio.buzz(Haptic.equip);
}

// ------------------------------------------------------------------------------------- the loadout
/// Your mining loadout: the six slots, what's in each, and what it adds up to.
Future<void> showGearLoadout(BuildContext context) => showEvochiSheet<void>(context, builder: (_) => const _Loadout());

class _Loadout extends StatelessWidget {
  const _Loadout();

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final tier = mine.oreTierOf(s);
    final power = mine.miningPowerOf(s);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _sheetHead('Mining gear', 'Worn on the trail and in the mines. Your wearables stay as they are.', s),
      Container(
        padding: const EdgeInsets.all(10),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: const Color(0xFFEFF8E2), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFB7D98B))),
        child: Text(
          'Breaks ${[for (var t = 1; t <= tier; t++) mine.tierNames[t]!.toLowerCase()].join(', ')} ore · Mining power ${(power * 100).round()}%',
          style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14, color: EvochiColor.healthy),
        ),
      ),
      for (final slot in mine.gearSlots) _SlotRow(slot: slot, state: s, c: c),
      Align(
        alignment: Alignment.centerRight,
        child: EvochiButton(label: 'Done', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => Navigator.of(context).pop()),
      ),
    ]);
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.state, required this.c});
  final String slot;
  final GameState state;
  final GameController c;

  @override
  Widget build(BuildContext context) {
    final wornId = state.mining.loadout[slot];
    final worn = wornId == null ? null : state.mining.piece(wornId);
    final options = state.mining.gear.where((p) => mine.gearDefs[p.def]?.slot == slot).toList();
    final def = worn == null ? null : mine.gearDefs[worn.def];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(color: EvochiColor.shell, borderRadius: BorderRadius.circular(12), border: Border.all(color: EvochiColor.border)),
      child: Row(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: const Color(0xFFF3E1C6), borderRadius: BorderRadius.circular(10)),
          child: def == null ? const Icon(Icons.add_rounded, color: EvochiColor.border) : ItemImage('gear_${def.id}', size: 52),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mine.gearSlotNames[slot]!, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w700, fontSize: 12, color: EvochiColor.textHelper)),
            Text(def?.name ?? (options.isEmpty ? 'Nothing yet' : 'Empty'),
                style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 15, color: EvochiColor.ink)),
            if (worn != null) Text(_memory(worn), style: EvochiText.caption),
          ]),
        ),
        if (options.length > (worn == null ? 0 : 1) || worn != null)
          PopupMenuButton<String>(
            tooltip: 'Change',
            icon: const Icon(Icons.swap_horiz_rounded, color: EvochiColor.wood),
            onSelected: (v) {
              if (v == '_off') {
                c.run((s, now) => mine.takeOffGear(s, slot), quiet: true);
              } else {
                _wear(c, v);
              }
            },
            itemBuilder: (_) => [
              for (final p in options)
                if (p.id != wornId) PopupMenuItem(value: p.id, child: Text('Wear ${mine.gearDefs[p.def]!.name}')),
              if (worn != null) const PopupMenuItem(value: '_off', child: Text('Take it off')),
            ],
          ),
      ]),
    );
  }
}

/// A piece's memory, in a line: who made it, where its ore came from, its finish, its first trip.
String _memory(GearPiece p) {
  final parts = <String>[
    p.from == 'bram' ? 'Forged by Bram' : 'From Flint',
    if (p.oreFrom != null) 'ore from ${_mapNames[p.oreFrom] ?? p.oreFrom}',
    if (p.finish != null) mine.gearFinishes[p.finish]!.toLowerCase(),
    p.firstTrip == null ? 'not been mining yet' : 'been mining',
  ];
  return parts.join(' · ');
}

// ------------------------------------------------------------------------------------- Bram's forge
/// Bram's forge: pick a piece, then three short steps (prepare, shape, finish). Never a failure: a
/// hammer stroke off the beat just takes another.
Future<void> showBramForge(BuildContext context) => showEvochiSheet<void>(context, builder: (_) => const _Forge());

class _Forge extends StatefulWidget {
  const _Forge();
  @override
  State<_Forge> createState() => _ForgeState();
}

class _ForgeState extends State<_Forge> with SingleTickerProviderStateMixin {
  mine.GearDef? _making;
  int _step = 0; // 0 prepare, 1 shape, 2 finish
  int _strokes = 0;
  String _finish = 'polished';
  late final AnimationController _beat = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat();
  double _flash = 0;

  @override
  void dispose() {
    _beat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<GameController>();
    final s = c.state;
    final d = _making;
    if (d == null) {
      final defs = mine.gearDefs.values.where((x) => x.maker == 'bram').toList()..sort((a, b) => a.tier - b.tier);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        _sheetHead("Bram's Forge", 'Ah, back from the trail? Let’s see what that ore can become.', s),
        for (final x in defs)
          Builder(builder: (context) {
            final owned = mine.ownedGear(s, x.id);
            final can = x.ore.entries.every((e) => g.ownedQty(s, e.key) >= e.value);
            return _GearCard(
              def: x,
              state: s,
              note: owned == null ? null : 'Forged: ${_memory(owned)}',
              trailing: owned != null
                  ? const SizedBox(width: 72)
                  : EvochiButton(
                      label: 'Forge',
                      small: true,
                      expand: false,
                      onPressed: can
                          ? () => setState(() {
                                _making = x;
                                _step = 0;
                                _strokes = 0;
                              })
                          : null),
            );
          }),
        Align(
          alignment: Alignment.centerRight,
          child: EvochiButton(label: 'Done', small: true, expand: false, tone: ButtonTone.cream, onPressed: () => Navigator.of(context).pop()),
        ),
      ]);
    }
    final ore = d.ore.keys.first;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      _sheetHead(d.name, ['1 Prepare', '2 Shape', '3 Finish'][_step], s),
      SizedBox(
        height: 170,
        child: Stack(alignment: Alignment.center, children: [
          Container(decoration: BoxDecoration(color: const Color(0xFF3A2A22), borderRadius: BorderRadius.circular(14))),
          if (_step == 0)
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ItemImage(ore, size: 72),
              const Icon(Icons.arrow_forward_rounded, color: Color(0xFFF4B84E), size: 34),
              Container(
                width: 70,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: ore == 'copper_ore' ? const [Color(0xFFF2A867), Color(0xFFA8582C)] : const [Color(0xFFD4DAE0), Color(0xFF727A84)]),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: const Color(0xFF2A1A12), width: 2),
                ),
              ),
            ])
          else if (_step == 1)
            AnimatedBuilder(
              animation: _beat,
              builder: (_, __) {
                final x = math.sin(_beat.value * math.pi * 2);
                return CustomPaint(size: const Size(300, 150), painter: _AnvilPainter(x, _strokes, _flash, d.tier));
              },
            )
          else
            Column(mainAxisSize: MainAxisSize.min, children: [
              ItemImage('gear_${d.id}', size: 110),
              Text(mine.gearFinishes[_finish]!, style: const TextStyle(fontFamily: EvochiText.game, fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFFFFE5A2))),
            ]),
        ]),
      ),
      const SizedBox(height: 10),
      Text(
        switch (_step) {
          0 => 'Bram heats the ${_oreName(ore).toLowerCase()} and pours it into bars. Pick up the hammer when you’re ready.',
          1 => 'Tap the anvil as the hammer comes down: ${4 - _strokes} more ${_strokes == 3 ? 'stroke' : 'strokes'}.',
          _ => 'Choose a finish. It’s how this piece will look, always.',
        },
        style: const TextStyle(fontFamily: EvochiText.body, fontSize: 14.5, height: 1.35, color: EvochiColor.ink),
      ),
      const SizedBox(height: 10),
      if (_step == 0)
        EvochiButton(label: 'Pick up the hammer', onPressed: () => setState(() => _step = 1))
      else if (_step == 1)
        EvochiButton(label: 'Strike!', onPressed: () => _stroke(c))
      else ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in mine.gearFinishes.keys)
            ChoiceChip(label: Text(mine.gearFinishes[f]!), selected: _finish == f, onSelected: (_) => setState(() => _finish = f)),
        ]),
        const SizedBox(height: 10),
        EvochiButton(label: 'Finish it', onPressed: () => _done(c, d)),
      ],
    ]);
  }

  void _stroke(GameController c) {
    // on the beat (the hammer low) rings bright; off it just takes another stroke, never a failure
    final low = math.sin(_beat.value * math.pi * 2) < -0.55;
    c.audio.play(low ? 'mine_iron_crack' : 'mine_iron_chip', volume: low ? 0.7 : 0.45);
    setState(() {
      _flash = low ? 1 : 0.4;
      if (low) _strokes++;
      if (_strokes >= 4) _step = 2;
    });
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) setState(() => _flash = 0);
    });
  }

  void _done(GameController c, mine.GearDef d) {
    final r = c.run((s, now) => mine.forgeGear(s, d.id, 'bram:${d.id}:$now', now, finish: _finish), quiet: true);
    if (!r.ok) {
      c.toast(_why(r), icon: 'warning', kind: 'warn');
      return;
    }
    c.audio.play('reward_chime', volume: 0.7);
    c.toast('${d.name}, ${mine.gearFinishes[_finish]!.toLowerCase()}. Bram nods: "That one will last."', icon: 'star');
    setState(() => _making = null);
  }
}

/// The anvil, a hot bar on it, and the hammer rising and falling ([x] -1 down to 1 up). Sparks on a
/// stroke; the bar takes shape stroke by stroke.
class _AnvilPainter extends CustomPainter {
  _AnvilPainter(this.x, this.strokes, this.flash, this.tier);
  final double x, flash;
  final int strokes, tier;

  @override
  void paint(Canvas canvas, Size s) {
    final ink = Paint()..color = const Color(0xFF1E1410);
    final anvil = Path()
      ..moveTo(s.width * 0.25, s.height * 0.72)
      ..lineTo(s.width * 0.75, s.height * 0.72)
      ..lineTo(s.width * 0.68, s.height * 0.86)
      ..lineTo(s.width * 0.6, s.height * 0.86)
      ..lineTo(s.width * 0.62, s.height * 0.98)
      ..lineTo(s.width * 0.38, s.height * 0.98)
      ..lineTo(s.width * 0.4, s.height * 0.86)
      ..lineTo(s.width * 0.32, s.height * 0.86)
      ..close();
    canvas.drawPath(anvil, Paint()..color = const Color(0xFF55505A));
    canvas.drawPath(anvil, ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2);
    // the bar: longer and flatter with each stroke, glowing hot
    final w = s.width * (0.2 + 0.05 * strokes), h = s.height * (0.1 - 0.012 * strokes);
    final bar = Rect.fromCenter(center: Offset(s.width / 2, s.height * 0.72 - h / 2), width: w, height: h);
    canvas.drawRRect(RRect.fromRectAndRadius(bar, const Radius.circular(3)),
        Paint()..color = Color.lerp(tier == 1 ? const Color(0xFFFF9A4A) : const Color(0xFFFFC27A), Colors.white, flash * 0.6)!);
    // the hammer
    final hy = s.height * (0.15 + 0.22 * (1 - (x + 1) / 2));
    canvas.drawRect(Rect.fromLTWH(s.width * 0.56, hy - 6, s.width * 0.3, 8), Paint()..color = const Color(0xFFA8703F));
    canvas.drawRect(Rect.fromLTWH(s.width * 0.47, hy - 16, s.width * 0.12, 28), Paint()..color = const Color(0xFF8E959E));
    // the beat: a ring shows when the hammer is low (strike then)
    if (x < -0.55) {
      canvas.drawCircle(Offset(s.width / 2, s.height * 0.68), 26, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xCCFFE5A2));
    }
    if (flash > 0) {
      final rnd = math.Random(strokes);
      for (var i = 0; i < 10; i++) {
        final a = -math.pi * rnd.nextDouble();
        final r = 20 + 50 * rnd.nextDouble() * flash;
        canvas.drawCircle(Offset(s.width / 2 + math.cos(a) * r, s.height * 0.68 + math.sin(a) * r), 2.4, Paint()..color = Color.fromRGBO(255, 214, 120, flash));
      }
    }
  }

  @override
  bool shouldRepaint(_AnvilPainter old) => true;
}
